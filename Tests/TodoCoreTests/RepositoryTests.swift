import XCTest
@testable import TodoCore

final class RepositoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testIndependentDeletionDeadlinesSurviveRestart() throws {
        var bytes = Data()
        let repo = try Repository { bytes = $0 }
        var first = UUID(), second = UUID()
        try repo.update {
            first = try $0.add(title: "first", now: start)
            second = try $0.add(title: "second", now: start)
            try $0.toggle(first, now: start)
            try $0.delete(first, now: start)
            try $0.delete(second, now: start.addingTimeInterval(2))
        }
        let reopened = try Repository(document: Repository.decode(bytes)) { bytes = $0 }
        try reopened.update { $0.purge(now: start.addingTimeInterval(5)) }
        XCTAssertFalse(reopened.document.todos.contains { $0.id == first })
        XCTAssertThrowsError(try reopened.update { try $0.undoDelete(first, now: start.addingTimeInterval(5)) })
        try reopened.update { try $0.undoDelete(second, now: start.addingTimeInterval(6)) }
        XCTAssertEqual(reopened.document.todos.map(\.id), [second])
        XCTAssertNil(reopened.document.todos[0].deleteAfter)
    }

    func testUndoPreservesOriginalCompletionDataAndMasterOrder() throws {
        var doc = Document()
        let older = try doc.add(title: "old", now: start)
        let newer = try doc.add(title: "new", now: start)
        try doc.toggle(older, now: start)
        let original = doc.todos
        try doc.delete(older, now: start)
        try doc.undoDelete(older, now: start.addingTimeInterval(4.99))
        XCTAssertEqual(doc.todos, original)
        try doc.toggle(older, now: start)
        XCTAssertEqual(doc.todos.map(\.id), [newer, older])
    }

    func testFailedSaveDoesNotLoseDataOrCommitDeletion() throws {
        struct DiskFull: Error {}
        var reject = false
        let repo = try Repository { _ in if reject { throw DiskFull() } }
        try repo.update { try $0.add(title: "keep", now: start) }
        let before = repo.document
        reject = true
        XCTAssertThrowsError(try repo.update { try $0.delete(before.todos[0].id, now: start) })
        XCTAssertEqual(repo.document, before)
    }

    func testCategoryDeletionOnlyRemovesLinksIncludingTombstones() throws {
        var doc = Document()
        let category = try doc.saveCategory(name: " Work ")
        XCTAssertThrowsError(try doc.saveCategory(name: "work"))
        _ = try doc.add(title: "one", now: start)
        doc.todos[0].categoryIDs = [category]
        try doc.delete(doc.todos[0].id, now: start)
        doc.deleteCategory(category)
        XCTAssertEqual(doc.todos.count, 1)
        XCTAssertTrue(doc.todos[0].categoryIDs.isEmpty)
        XCTAssertNotNil(doc.todos[0].deleteAfter)
    }

    func testReorderAndCompletionDoNotDestroyHiddenOrder() throws {
        var doc = Document()
        let a = try doc.add(title: "A"), b = try doc.add(title: "B"), c = try doc.add(title: "C")
        try doc.toggle(b)
        doc.move(a, before: c)
        XCTAssertEqual(doc.todos.map(\.id), [a, c, b])
        doc.move(a, after: c)
        try doc.toggle(b)
        XCTAssertEqual(doc.todos.map(\.id), [c, a, b])
        XCTAssertThrowsError(try doc.add(title: " \n "))
    }

    func testDateOnlyAcrossTimeZonesAndFullDocumentRoundTrip() throws {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let day = Day(date: start, timeZone: seoul)
        XCTAssertEqual(Day(date: day.date(timeZone: la), timeZone: la), day)
        var doc = Document()
        try doc.add(title: "persist", now: start)
        doc.todos[0].due = day
        doc.todos[0].richText = Data("{\\rtf1 hello}".utf8)
        doc.settings.image = Data([1, 2, 3])
        doc.settings.windowFrame = WindowFrame(x: 100, y: 200, width: 360, height: 480)
        XCTAssertEqual(try Repository.decode(JSONEncoder().encode(doc)), doc)
    }

    func testAtomicFileAndCorruptDataIsNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("data.json")
        let repo = try Repository(url: url, now: start)
        try repo.update { try $0.add(title: "on disk", now: start) }
        XCTAssertEqual(try Repository(url: url, now: start).document, repo.document)
        let invalid = Data("not json".utf8)
        try invalid.write(to: url)
        XCTAssertThrowsError(try Repository(url: url, now: start))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    func testFutureSchemaRejected() throws {
        var doc = Document(); doc.schema = 2
        XCTAssertThrowsError(try Repository.decode(JSONEncoder().encode(doc)))
    }

    func testLegacyDocumentDefaultsToSystemAppearanceWithoutLosingData() throws {
        var doc = Document()
        try doc.add(title: "기존 할 일", now: start)
        doc.settings.background = RGBA(0.4, 0.5, 0.6)
        doc.settings.image = Data([1, 2, 3])
        doc.settings.hasSeenRecovery = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "appearance")
        json["settings"] = settings
        let restored = try Repository.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.settings.appearance, .system)
        XCTAssertEqual(restored, doc)
    }

    func testAppearanceSelectionSurvivesRestartForEveryMode() throws {
        var bytes = Data()
        let repo = try Repository { bytes = $0 }
        for mode in AppAppearance.allCases {
            try repo.update { $0.settings.appearance = mode }
            let reopened = try Repository(document: Repository.decode(bytes)) { _ in }
            XCTAssertEqual(reopened.document.settings.appearance, mode)
        }
    }

    func testFailedAppearanceSaveKeepsPreviousSelection() throws {
        struct DiskFull: Error {}
        let repo = try Repository { _ in throw DiskFull() }
        XCTAssertThrowsError(try repo.update { $0.settings.appearance = .dark })
        XCTAssertEqual(repo.document.settings.appearance, .system)
    }
}
