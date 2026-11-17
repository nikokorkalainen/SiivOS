import XCTest

/// Base class for tests that need real files. Each test gets its own empty folder,
/// with a pretend home folder inside it, and the folder is deleted afterwards.
class TemporaryDirectoryTestCase: XCTestCase {
    var root: URL!

    /// A pretend home folder, so tests never touch the real one.
    var home: URL {
        root.appendingPathComponent("home", isDirectory: true)
    }

    /// Where the pretend SiivOS keeps its own data.
    var baseDirectory: URL {
        home.appendingPathComponent("Library/Application Support/SiivOS", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiivOSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// Creates a file inside the pretend home folder, along with any folders it needs.
    @discardableResult
    func makeFile(_ relativePath: String, contents: String = "hello") throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Creates an empty folder inside the pretend home folder.
    @discardableResult
    func makeFolder(_ relativePath: String) throws -> URL {
        let url = home.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// True when something exists at the URL. A link counts even if its target is gone.
    func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}
