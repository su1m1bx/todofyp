import Foundation

public struct Day: Codable, Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }

    public func date(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }
}

public struct Todo: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var richText: Data?
    public var isComplete: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var due: Day?
    public var categoryIDs: Set<UUID>
    public var deleteAfter: Date?

    public init(title: String, now: Date = .now) {
        id = UUID(); self.title = title; richText = nil; isComplete = false
        createdAt = now; modifiedAt = now; due = nil; categoryIDs = []; deleteAfter = nil
    }
}

public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public init(name: String) { self.name = name }
}

public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}

public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

public struct Settings: Codable, Equatable, Sendable {
    public var appearance = AppAppearance.system
    public var background = RGBA(0.96, 0.95, 0.89)
    public var checkColor = RGBA(0.10, 0.48, 0.28)
    public var image: Data?
    public var useImage = false
    public var imageFill = true
    public var overlay = 0.7
    public var windowFrame: WindowFrame?
    public var hasSeenRecovery = false
    public var loginRequested = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case appearance, background, checkColor, image, useImage, imageFill, overlay
        case windowFrame, hasSeenRecovery, loginRequested
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Version-1 documents created before the theme picker follow the system.
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        background = try values.decode(RGBA.self, forKey: .background)
        checkColor = try values.decode(RGBA.self, forKey: .checkColor)
        image = try values.decodeIfPresent(Data.self, forKey: .image)
        useImage = try values.decode(Bool.self, forKey: .useImage)
        imageFill = try values.decode(Bool.self, forKey: .imageFill)
        overlay = try values.decode(Double.self, forKey: .overlay)
        windowFrame = try values.decodeIfPresent(WindowFrame.self, forKey: .windowFrame)
        hasSeenRecovery = try values.decode(Bool.self, forKey: .hasSeenRecovery)
        loginRequested = try values.decode(Bool.self, forKey: .loginRequested)
    }
}

public enum TodoError: LocalizedError {
    case emptyTitle, emptyCategory, duplicateCategory, missingItem, expiredUndo, unsupportedSchema
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "공백만 있는 제목은 저장할 수 없습니다."
        case .emptyCategory: return "카테고리 이름을 입력하세요."
        case .duplicateCategory: return "같은 이름의 카테고리가 이미 있습니다."
        case .missingItem: return "항목을 찾을 수 없습니다."
        case .expiredUndo: return "삭제 실행 취소 시간이 지났습니다."
        case .unsupportedSchema: return "지원하지 않는 데이터 버전입니다. 원본은 변경하지 않았습니다."
        }
    }
}

public struct Document: Codable, Equatable, Sendable {
    public var schema = 1
    // Master order includes completed tasks and pending deletions; filtering never changes it.
    public var todos: [Todo] = []
    public var categories: [Category] = []
    public var settings = Settings()
    public init() {}

    @discardableResult public mutating func add(title: String, now: Date = .now) throws -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TodoError.emptyTitle }
        let item = Todo(title: title, now: now)
        todos.insert(item, at: 0)
        return item.id
    }

    public mutating func edit(_ item: Todo, now: Date = .now) throws {
        guard let index = todos.firstIndex(where: { $0.id == item.id && $0.deleteAfter == nil }) else { throw TodoError.missingItem }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TodoError.emptyTitle }
        // Edit only editable fields; retain completion/order/deletion bookkeeping.
        todos[index].title = title
        todos[index].richText = item.richText
        todos[index].due = item.due
        todos[index].categoryIDs = item.categoryIDs.intersection(Set(categories.map(\.id)))
        todos[index].modifiedAt = now
    }

    public mutating func toggle(_ id: UUID, now: Date = .now) throws {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.deleteAfter == nil }) else { throw TodoError.missingItem }
        todos[index].isComplete.toggle()
        todos[index].modifiedAt = now
    }

    public mutating func delete(_ id: UUID, now: Date = .now) throws {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.deleteAfter == nil }) else { throw TodoError.missingItem }
        todos[index].deleteAfter = now.addingTimeInterval(5)
    }

    public mutating func undoDelete(_ id: UUID, now: Date = .now) throws {
        guard let index = todos.firstIndex(where: { $0.id == id }),
              let deadline = todos[index].deleteAfter, deadline > now else { throw TodoError.expiredUndo }
        todos[index].deleteAfter = nil
    }

    public mutating func purge(now: Date = .now) {
        todos.removeAll { $0.deleteAfter.map { $0 <= now } ?? false }
    }

    public mutating func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = todos.firstIndex(where: { $0.id == id && $0.deleteAfter == nil }),
              todos.contains(where: { $0.id == target && $0.deleteAfter == nil }) else { return }
        let item = todos.remove(at: from)
        let to = todos.firstIndex(where: { $0.id == target })!
        todos.insert(item, at: to)
    }

    public mutating func move(_ id: UUID, after target: UUID) {
        guard id != target, let from = todos.firstIndex(where: { $0.id == id && $0.deleteAfter == nil }),
              todos.contains(where: { $0.id == target && $0.deleteAfter == nil }) else { return }
        let item = todos.remove(at: from)
        let to = todos.firstIndex(where: { $0.id == target })!
        todos.insert(item, at: to + 1)
    }

    @discardableResult public mutating func saveCategory(id: UUID? = nil, name: String) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw TodoError.emptyCategory }
        guard !categories.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw TodoError.duplicateCategory }
        if let id {
            guard let index = categories.firstIndex(where: { $0.id == id }) else { throw TodoError.missingItem }
            categories[index].name = name
            return id
        }
        let category = Category(name: name)
        categories.append(category)
        return category.id
    }

    public mutating func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for index in todos.indices { todos[index].categoryIDs.remove(id) }
    }
}
