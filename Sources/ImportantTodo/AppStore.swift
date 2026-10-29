import AppKit
import Combine
import ImageIO
import ServiceManagement
import SwiftUI
import TodoCore
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var document = Document()
    @Published var error: String?
    @Published var now = Date.now
    @Published var showingSettings = false
    @Published private(set) var loginStatus = ""
    @Published private(set) var loginBusy = false
    private(set) var backgroundImage: NSImage?
    private var repository: Repository?
    private var timer: Timer?
    private var pendingFrame: WindowFrame?
    private var frameSave: DispatchWorkItem?
    private var lastExpiryFailure: Date?
    private let storageURL: URL?
    var writable: Bool { repository != nil }
    var loginEnabled: Bool {
        SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        load()
        refreshLoginStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func load() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let repo = try Repository(url: storageURL ?? base.appendingPathComponent("ImportantTodo/document.json"))
            repository = repo
            backgroundImage = repo.document.settings.image.flatMap(NSImage.init(data:))
            document = repo.document
            applyAppearance()
            error = nil
        } catch {
            repository = nil
            self.error = "데이터를 열지 못했습니다. 원본은 덮어쓰지 않습니다.\n\(error.localizedDescription)"
        }
    }

    @discardableResult func update(_ change: (inout Document) throws -> Void) -> Bool {
        guard let repository else { return false }
        do {
            try repository.update(change)
            if document.settings.image != repository.document.settings.image {
                backgroundImage = repository.document.settings.image.flatMap(NSImage.init(data:))
            }
            let appearanceChanged = document.settings.appearance != repository.document.settings.appearance
            document = repository.document
            if appearanceChanged { applyAppearance() }
            error = nil
            return true
        } catch {
            self.error = "저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    private func tick() {
        now = .now
        if document.todos.contains(where: { $0.deleteAfter.map { $0 <= now } ?? false }),
           lastExpiryFailure.map({ now.timeIntervalSince($0) >= 5 }) ?? true {
            if update({ $0.purge(now: now) }) { lastExpiryFailure = nil }
            else { lastExpiryFailure = now }
        }
    }

    private func applyAppearance() {
        // App-local override also themes AppKit editors, material, and system panels.
        // nil removes the override and keeps tracking future macOS theme changes.
        switch document.settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func queueFrame(_ frame: NSRect) {
        pendingFrame = WindowFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        frameSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushFrame() }
        frameSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @discardableResult func flushFrame() -> Bool {
        frameSave?.cancel()
        guard let frame = pendingFrame else { return true }
        if update({ $0.settings.windowFrame = frame }) { pendingFrame = nil; return true }
        return false
    }

    func importImage(parent: NSWindow) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png, .jpeg, .heic]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.message = "배경 이미지: PNG/JPEG/HEIC, 최대 10MiB·24메가픽셀. 앱에 사본을 저장합니다."
        picker.level = parent.level
        picker.beginSheetModal(for: parent) { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= 10 * 1024 * 1024 else {
                        throw ImageImportError.invalid
                    }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10 * 1024 * 1024,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let type = CGImageSourceGetType(source) as String?,
                          [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier].contains(type),
                          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = props[kCGImagePropertyPixelWidth] as? Int,
                          let height = props[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, Double(width) * Double(height) <= 24_000_000,
                          CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw ImageImportError.invalid }
                    self.update { $0.settings.image = data; $0.settings.useImage = true }
                } catch { self.error = "이미지 가져오기 실패. 기존 배경을 유지합니다.\n\(error.localizedDescription)" }
            }
        }
    }

    func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "등록됨"
        case .requiresApproval: loginStatus = "시스템 설정에서 사용자 승인이 필요합니다."
        case .notRegistered: loginStatus = "꺼짐"
        case .notFound: loginStatus = "서비스를 찾을 수 없습니다. 설치 위치와 서명 상태를 확인하세요."
        @unknown default: loginStatus = "알 수 없는 상태"
        }
    }

    func setLogin(_ enabled: Bool) {
        guard !loginBusy else { return }
        loginBusy = true
        Task { @MainActor in
            defer { loginBusy = false; refreshLoginStatus() }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
                update { $0.settings.loginRequested = enabled }
            } catch { self.error = "로그인 시작 변경 실패: \(error.localizedDescription)" }
        }
    }
}

private enum ImageImportError: LocalizedError {
    case invalid
    var errorDescription: String? { "올바른 PNG/JPEG/HEIC 파일(10MiB 이하, 24메가픽셀 이하)을 선택하세요." }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    init(color: Color) {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent)
    }
}
