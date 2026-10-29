import Foundation

/// Mutations commit in memory only after durable storage succeeds.
public final class Repository {
    public private(set) var document: Document
    private let persist: (Data) throws -> Void

    public init(document: Document = Document(), persist: @escaping (Data) throws -> Void) throws {
        guard document.schema == 1 else { throw TodoError.unsupportedSchema }
        self.document = document
        self.persist = persist
    }

    public convenience init(url: URL, now: Date = .now) throws {
        let manager = FileManager.default
        let document: Document
        if manager.fileExists(atPath: url.path) {
            document = try Self.decode(Data(contentsOf: url))
        } else {
            document = Document()
        }
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(document: document) { data in try data.write(to: url, options: .atomic) }
        // Persist expiry on startup too; never restart the five-second clock.
        try update { $0.purge(now: now) }
    }

    public static func decode(_ data: Data) throws -> Document {
        let result = try JSONDecoder().decode(Document.self, from: data)
        guard result.schema == 1 else { throw TodoError.unsupportedSchema }
        return result
    }

    public func update(_ change: (inout Document) throws -> Void) throws {
        var next = document
        try change(&next)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try persist(encoder.encode(next))
        document = next
    }
}
