import XCTest
@testable import SiivOSCore

final class DiskMapTests: TemporaryDirectoryTestCase {
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
