import XCTest
@testable import SiivOSCore

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
        // The tests check English wording, so pin the language whatever the machine is set to.
        L10n.overrideLanguage = .english
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

    /// Creates a file of an exact size inside the pretend home folder. Files made with the
    /// same `fill` have the same contents; `ending` changes only the last byte.
    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int, fill: UInt8 = 1, ending: UInt8? = nil) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = Data(repeating: fill, count: bytes)
        if let ending, bytes > 0 {
            data[bytes - 1] = ending
        }
        try data.write(to: url)
        return url
    }

    /// A pretend Applications folder, next to the pretend home folder.
    var applications: URL {
        root.appendingPathComponent("Applications", isDirectory: true)
    }

    /// Creates a pretend app in the pretend Applications folder. Without an identifier
    /// the app gets no Info.plist at all.
    @discardableResult
    func makeApp(_ relativePath: String, identifier: String?, version: String = "1.0") throws -> URL {
        let app = applications.appendingPathComponent(relativePath, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 10_000).write(to: contents.appendingPathComponent("MacOS/program"))
        if let identifier {
            try writePlist(
                ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version],
                to: contents.appendingPathComponent("Info.plist")
            )
        }
        return app
    }

    /// Writes a settings file in Apple's property list format.
    func writePlist(_ contents: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url)
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
