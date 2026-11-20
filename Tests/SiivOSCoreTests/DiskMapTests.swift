import XCTest
@testable import SiivOSCore

final class DiskMapTests: TemporaryDirectoryTestCase {
    // MARK: - What grew

    private func item(_ path: String, _ size: Int64, opened children: [DiskMapNode]? = nil, otherCount: Int = 0) -> DiskMapNode {
        DiskMapNode(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            sizeBytes: size,
            canBeOpened: children != nil,
            isOpened: children != nil,
            children: children ?? [],
            otherCount: otherCount
        )
    }

    private func folder(_ size: Int64, _ children: [DiskMapNode], smaller: [DiskMapNode] = [], otherCount: Int? = nil) -> DiskMapNode {
        DiskMapNode(
            url: URL(fileURLWithPath: "/Users/x"),
            name: "x",
            sizeBytes: size,
            canBeOpened: true,
            isOpened: true,
            children: children,
            otherBytes: smaller.reduce(0) { $0 + $1.sizeBytes },
            otherCount: otherCount ?? smaller.count,
            smallerItems: smaller
        )
    }

    private let morning = Date(timeIntervalSince1970: 1_800_000_000)
    private func hoursLater(_ hours: Double) -> Date { morning.addingTimeInterval(hours * 3_600) }

    func testALaterMeasuringSaysWhatGrewShrankAndIsNew() {
        let before = folder(9_000, [
            item("/Users/x/Library", 5_000, opened: [item("/Users/x/Library/Caches", 3_000)]),
            item("/Users/x/Movies", 3_000),
            item("/Users/x/Hidden", 0)
        ], smaller: [item("/Users/x/notes.txt", 10)])
        let snapshot = DiskMapSnapshot(of: before, date: morning)

        let library = item("/Users/x/Library", 7_500, opened: [
            item("/Users/x/Library/Caches", 5_000),
            item("/Users/x/Library/Logs", 400)
        ])
        let after = folder(12_000, [
            library,
            item("/Users/x/Movies", 2_000),
            item("/Users/x/Hidden", 800),
            item("/Users/x/Downloads", 1_200),
            item("/Users/x/notes.txt", 10)
        ])

        XCTAssertEqual(snapshot.change(of: after), 3_000)
        XCTAssertEqual(snapshot.change(of: after.children[0], in: after), .changed(2_500))
        XCTAssertEqual(snapshot.change(of: after.children[1], in: after), .changed(-1_000))
        XCTAssertNil(snapshot.change(of: after.children[2], in: after), "Nothing of it could be seen before, so its size now is not growth")
        XCTAssertEqual(snapshot.change(of: after.children[3], in: after), .new, "Everything in the folder was noted down, so this was not there")
        XCTAssertEqual(snapshot.change(of: after.children[4], in: after), .changed(0), "Small items directly in the folder are noted down too")

        XCTAssertEqual(snapshot.change(of: library.children[0], in: library), .changed(2_000), "One level further down as well")
        XCTAssertEqual(snapshot.change(of: library.children[1], in: library), .new)
        XCTAssertEqual(snapshot.change(of: library), 2_500)
    }

    func testAnItemThatMayHaveBeenTooSmallToNoteDownIsNotCalledNew() {
        // More small items than were kept, at both levels.
        let before = folder(9_000, [
            item("/Users/x/Library", 5_000, opened: [item("/Users/x/Library/Caches", 3_000)], otherCount: 40)
        ], smaller: [item("/Users/x/a", 10)], otherCount: 500)
        let snapshot = DiskMapSnapshot(of: before, date: morning)
        XCTAssertTrue(snapshot.completeFolders.isEmpty)

        let library = item("/Users/x/Library", 5_000, opened: [item("/Users/x/Library/Logs", 900)])
        let after = folder(9_500, [library, item("/Users/x/b", 400)])

        XCTAssertNil(snapshot.change(of: after.children[1], in: after))
        XCTAssertNil(snapshot.change(of: library.children[0], in: library))
        XCTAssertNil(snapshot.change(of: item("/Users/elsewhere", 5, opened: [])), "A folder that was not measured then")
    }

    func testANewMeasuringIsComparedWithOneFromAtLeastHalfADayAgo() {
        func snapshot(_ hours: Double) -> DiskMapSnapshot {
            DiskMapSnapshot(of: folder(1_000, []), date: hoursLater(hours))
        }
        var history = DiskMapHistory()
        XCTAssertNil(history.baseline(now: morning))

        history.add(snapshot(0))
        XCTAssertEqual(history.baseline(now: hoursLater(6))?.date, hoursLater(0), "Nothing older yet, so the first one")

        history.add(snapshot(6))
        history.add(snapshot(7))
        XCTAssertEqual(history.snapshots.map { $0.date }, [hoursLater(0), hoursLater(7)], "Measuring again soon replaces the last, not the one to compare with")

        XCTAssertEqual(history.baseline(now: hoursLater(8))?.date, hoursLater(0))
        XCTAssertEqual(history.baseline(now: hoursLater(30))?.date, hoursLater(7), "The newest that is half a day old")

        history.add(snapshot(30))
        XCTAssertEqual(history.snapshots.count, 3)
        XCTAssertEqual(history.baseline(now: hoursLater(31))?.date, hoursLater(7), "Not the one just taken")

        for day in 2...20 {
            history.add(snapshot(Double(day) * 24))
        }
        XCTAssertEqual(history.snapshots.count, DiskMapHistory.kept)
        XCTAssertEqual(history.snapshots.last?.date, hoursLater(480))
    }

    func testMeasuringsAreKeptBetweenLaunchesAndADamagedFileStartsAfresh() throws {
        try makeFile("Movies/film.mov", bytes: 3_000_000)
        try makeFile("Documents/letter.txt", bytes: 200_000)
        let map = DiskMap.measure(home, levels: 2)
        let store = DiskMapHistoryStore(dataDirectory: root.appendingPathComponent("Data"))
        XCTAssertTrue(store.load().snapshots.isEmpty)

        var history = DiskMapHistory()
        history.add(DiskMapSnapshot(of: map, date: morning))
        try store.save(history)

        let loaded = store.load()
        XCTAssertEqual(loaded, history)
        let snapshot = try XCTUnwrap(loaded.baseline(now: hoursLater(24)))
        XCTAssertEqual(snapshot.change(of: map), 0)
        XCTAssertEqual(snapshot.change(of: map.children[0], in: map), .changed(0))
        XCTAssertTrue(snapshot.completeFolders.contains(map.url.path))

        try "not json".write(to: store.fileURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(store.load().snapshots.isEmpty)
    }

    // MARK: - Measuring

    func testAFolderIsMeasuredWithItsLargestThingsFirst() throws {
        try makeFile("Movies/film.mov", bytes: 3_000_000)
        try makeFile("Movies/Old/clip.mov", bytes: 1_000_000)
        try makeFile("Documents/letter.txt", bytes: 200_000)
        try makeFile("notes.txt", bytes: 10)

        let map = DiskMap.measure(home, levels: 2)

        XCTAssertTrue(map.isOpened)
        XCTAssertEqual(map.children.prefix(2).map { $0.url.lastPathComponent }, ["Movies", "Documents"])
        XCTAssertGreaterThanOrEqual(map.sizeBytes, 4_200_000)
        XCTAssertEqual(map.sizeBytes - FileSize.ownSize(of: home), map.children.reduce(0) { $0 + $1.sizeBytes } + map.otherBytes)

        let movies = try XCTUnwrap(map.children.first)
        XCTAssertTrue(movies.canBeOpened)
        XCTAssertTrue(movies.isOpened, "The second level is looked into as well")
        XCTAssertEqual(movies.children.map { $0.url.lastPathComponent }, ["film.mov", "Old"])
        let old = try XCTUnwrap(movies.children.last)
        XCTAssertTrue(old.canBeOpened)
        XCTAssertFalse(old.isOpened, "The third level is measured as a whole")
        XCTAssertGreaterThanOrEqual(old.sizeBytes, 1_000_000)
        XCTAssertFalse(movies.children[0].canBeOpened, "A file cannot be looked into")
    }

    func testADeeperFolderCanBeMeasuredLater() throws {
        try makeFile("Movies/Old/Older/clip.mov", bytes: 1_000_000)
        let old = home.appendingPathComponent("Movies/Old")

        let map = DiskMap.measure(old, levels: 1)

        XCTAssertEqual(map.children.map { $0.url.lastPathComponent }, ["Older"])
        XCTAssertFalse(map.children[0].isOpened)
    }

    func testLibrariesAndPackagesAreOneThing() throws {
        try makeFile("Pictures/Photos Library.photoslibrary/originals/A/photo.heic", bytes: 2_000_000)
        try makeFile("Pictures/holiday.jpg", bytes: 100_000)

        let map = DiskMap.measure(home.appendingPathComponent("Pictures"), levels: 3)

        let library = try XCTUnwrap(map.children.first)
        XCTAssertEqual(library.url.lastPathComponent, "Photos Library.photoslibrary")
        XCTAssertFalse(library.canBeOpened, "A photo library is never picked apart")
        XCTAssertTrue(library.children.isEmpty)
        XCTAssertGreaterThanOrEqual(library.sizeBytes, 2_000_000)
    }

    func testOnlyTheLargestAreListedAndTheRestAreAddedUp() throws {
        for index in 0..<(DiskMap.largestListed + 6) {
            // Far apart in size, so that rounding on disk cannot make two of them equal.
            try makeFile("Documents/file-\(index).bin", bytes: 100_000 * (index + 1))
        }

        let map = DiskMap.measure(home.appendingPathComponent("Documents"), levels: 1)

        XCTAssertEqual(map.children.count, DiskMap.largestListed)
        XCTAssertEqual(map.otherCount, 6)
        XCTAssertGreaterThan(map.otherBytes, 0)
        XCTAssertEqual(map.children.first?.url.lastPathComponent, "file-\(DiskMap.largestListed + 5).bin")
        XCTAssertTrue(zip(map.children, map.children.dropFirst()).allSatisfy { $0.sizeBytes >= $1.sizeBytes })
    }

    func testTheSmallerItemsCanBeLookedAtAsAFolderOfTheirOwn() throws {
        for index in 0..<(DiskMap.largestListed * 2 + 6) {
            try makeFile("Documents/file-\(index).bin", bytes: 100_000 * (index + 1))
        }
        let map = DiskMap.measure(home.appendingPathComponent("Documents"), levels: 1)
        XCTAssertEqual(map.smallerItems.count, DiskMap.largestListed + 6)

        let smaller = try XCTUnwrap(map.smallerItemsNode(named: "Smaller"))

        XCTAssertEqual(smaller.name, "Smaller")
        XCTAssertEqual(smaller.sizeBytes, map.otherBytes)
        XCTAssertTrue(smaller.isOpened)
        XCTAssertEqual(smaller.children.count, DiskMap.largestListed)
        XCTAssertEqual(smaller.children.first?.url.lastPathComponent, "file-\(DiskMap.largestListed + 5).bin", "The largest of the small ones comes first")
        XCTAssertEqual(smaller.otherCount, 6)
        XCTAssertEqual(smaller.children.reduce(0) { $0 + $1.sizeBytes } + smaller.otherBytes, map.otherBytes)

        // And what is left over after that can be looked at in the same way.
        let smallest = try XCTUnwrap(smaller.smallerItemsNode(named: "Smallest"))
        XCTAssertEqual(smallest.children.count, 6)
        XCTAssertEqual(smallest.otherCount, 0)
        XCTAssertNil(smallest.smallerItemsNode(named: "None"))
    }

    // MARK: - Kinds

    func testFoldersAreSortedIntoKindsByNameAndPlace() {
        let home = URL(fileURLWithPath: "/Users/someone")
        func kind(_ path: String) -> DiskMapKind {
            DiskMap.kind(of: home.appendingPathComponent(path), home: home)
        }

        XCTAssertEqual(kind("Library"), .appData)
        XCTAssertEqual(kind("Library/Caches/com.example.app"), .appData, "Anything inside Library")
        XCTAssertEqual(kind("Pictures"), .media)
        XCTAssertEqual(kind("Movies/Holiday/film.mov"), .media)
        XCTAssertEqual(kind("Music"), .media)
        XCTAssertEqual(kind("Desktop/Work"), .documents)
        XCTAssertEqual(kind("Documents"), .documents)
        XCTAssertEqual(kind("Downloads/installer.dmg"), .downloads)
        XCTAssertEqual(kind("Projects"), .other)
        XCTAssertEqual(kind("Sites/old"), .other)
    }

    func testANameCanSayOtherwiseAndWhatIsInsideTakesAfterIt() {
        let home = URL(fileURLWithPath: "/Users/someone")
        func kind(_ path: String) -> DiskMapKind {
            DiskMap.kind(of: home.appendingPathComponent(path), home: home)
        }

        XCTAssertEqual(kind("Documents/site/node_modules"), .developer)
        XCTAssertEqual(kind("Documents/site/node_modules/react/index.js"), .developer, "Inside it too")
        XCTAssertEqual(kind(".npm"), .developer)
        XCTAssertEqual(kind(".gradle/caches"), .developer)
        XCTAssertEqual(kind("Library/Developer/Xcode/DerivedData"), .developer)
        XCTAssertEqual(kind("Library/Android/sdk"), .developer)
        XCTAssertEqual(kind("tizen-studio"), .developer)
        XCTAssertEqual(kind("Documents/Photos Library.photoslibrary"), .media, "A photo library is media wherever it is kept")
        XCTAssertEqual(kind("Desktop/Lightroom Library.lrlibrary"), .media)
        XCTAssertEqual(kind(".Trash"), .other, "The Trash is not a developer tool")
        XCTAssertEqual(kind("Documents/report.final.pdf"), .documents, "An ordinary dot in a name says nothing")
    }

    func testEveryKindHasANameAndPlacesOutsideTheHomeFolderAreSortedByNameOnly() {
        XCTAssertTrue(DiskMapKind.allCases.allSatisfy { !$0.title.isEmpty })
        XCTAssertEqual(Set(DiskMapKind.allCases.map { $0.title }).count, DiskMapKind.allCases.count)

        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(DiskMap.kind(of: URL(fileURLWithPath: "/Volumes/Backup/Pictures"), home: home), .other)
        XCTAssertEqual(DiskMap.kind(of: URL(fileURLWithPath: "/Volumes/Backup/node_modules"), home: home), .developer)
        XCTAssertEqual(DiskMap.kind(of: home, home: home), .other)
    }

    func testMeasuringReportsProgressAndCanBeStopped() throws {
        // Names with no special meaning to a Mac, so they read the same in any language.
        try makeFile("Alpha/Inside/film.mov", bytes: 100_000)
        try makeFile("Beta/letter.txt", bytes: 100_000)
        try makeFile("Gamma/song.mp3", bytes: 100_000)

        var seen: [String] = []
        _ = DiskMap.measure(home, levels: 2, progress: { seen.append($0) })
        XCTAssertEqual(seen.sorted(), ["Alpha", "Beta", "Gamma"], "One line for each item at the top, none for deeper ones")

        var asked = 0
        let stopped = DiskMap.measure(home, levels: 2, isCancelled: {
            asked += 1
            return asked > 1
        })
        XCTAssertEqual(stopped.children.count, 1, "Stopped after the first item")
    }

    func testAMissingFolderIsEmptyAndMeasuringChangesNothing() throws {
        let missing = DiskMap.measure(home.appendingPathComponent("No Such Folder"))
        XCTAssertTrue(missing.children.isEmpty)
        XCTAssertEqual(missing.sizeBytes, 0)

        let file = try makeFile("Documents/keep.txt", bytes: 5_000)
        _ = DiskMap.measure(home)
        XCTAssertTrue(exists(file))
    }

    // MARK: - Drawing the map

    private func overlap(_ first: MapRect, _ second: MapRect) -> Double {
        let width = min(first.x + first.width, second.x + second.width) - max(first.x, second.x)
        let height = min(first.y + first.height, second.y + second.height) - max(first.y, second.y)
        return max(0, width) * max(0, height)
    }

    func testBlocksFillTheAreaInProportionWithoutOverlapping() {
        let sizes: [Double] = [50, 5, 20, 0, 10, 10, 3, 2]
        let rects = Treemap.layout(sizes: sizes, width: 400, height: 250)

        XCTAssertEqual(rects.count, sizes.count)
        XCTAssertEqual(rects.reduce(0) { $0 + $1.area }, 400 * 250, accuracy: 0.001)
        for (size, rect) in zip(sizes, rects) {
            XCTAssertEqual(rect.area, size / 100 * 400 * 250, accuracy: 0.001, "Each block is as large as its share")
            XCTAssertGreaterThanOrEqual(rect.x, -0.001)
            XCTAssertGreaterThanOrEqual(rect.y, -0.001)
            XCTAssertLessThanOrEqual(rect.x + rect.width, 400.001)
            XCTAssertLessThanOrEqual(rect.y + rect.height, 250.001)
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                XCTAssertEqual(overlap(rects[first], rects[second]), 0, accuracy: 0.001)
            }
        }
    }

    func testBlocksAreKeptCloseToSquare() {
        // Eight equal blocks in a wide area: a single row of thin strips would be eight
        // times taller than wide. The layout should do far better.
        let rects = Treemap.layout(sizes: Array(repeating: 1, count: 8), width: 400, height: 200)
        for rect in rects {
            let ratio = max(rect.width / rect.height, rect.height / rect.width)
            XCTAssertLessThan(ratio, 2.5)
        }
    }

    func testOddInputsGiveSensibleBlocks() {
        XCTAssertEqual(Treemap.layout(sizes: [], width: 100, height: 100), [])
        XCTAssertEqual(Treemap.layout(sizes: [7], width: 100, height: 50), [MapRect(x: 0, y: 0, width: 100, height: 50)])
        XCTAssertTrue(Treemap.layout(sizes: [0, 0], width: 100, height: 100).allSatisfy { $0.area == 0 })
        XCTAssertTrue(Treemap.layout(sizes: [1, 2], width: 0, height: 100).allSatisfy { $0.area == 0 })
        XCTAssertEqual(Treemap.layout(sizes: [-5, 10], width: 10, height: 10)[0].area, 0)
    }
}
