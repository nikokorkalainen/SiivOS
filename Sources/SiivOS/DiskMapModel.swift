import Foundation
import SiivOSCore
import SwiftUI

/// Lets measuring that is running in the background be stopped from the main thread.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func set() {
        lock.lock()
        isSet = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSet
    }
}

/// Connects the Disk Map to the engine that measures folders. Measuring only reads the
/// Mac; the one thing written is SiivOS's own note of the sizes, so that the next
/// measuring can say what has grown.
@MainActor
final class DiskMapModel: ObservableObject {
    /// The way from the home folder down to the folder being shown. Empty before the
    /// first measuring.
    @Published private(set) var path: [DiskMapNode] = []
    @Published private(set) var isMeasuring = false
    /// The name of what is being measured right now.
    @Published private(set) var measuringName = ""
    /// When the home folder was last measured.
    @Published private(set) var measuredAt: Date?
    /// An earlier measuring to compare this one with, or `nil` when there is none.
    @Published private(set) var baseline: DiskMapSnapshot?
    /// True when this measuring was noted down, so that a later one can be compared
    /// with it. A measuring that was stopped early is not.
    @Published private(set) var wasNotedDown = false

    private var stopFlag: StopFlag?

    /// The folder being shown, or `nil` before the first measuring.
    var current: DiskMapNode? {
        path.last
    }

    /// Measures the home folder from the top.
    func measureHome() {
        measure(URL(fileURLWithPath: NSHomeDirectory()), replacingPathFrom: 0)
    }

    /// Looks into one of the items being shown. A folder that was only measured as a
    /// whole is measured now.
    func enter(_ node: DiskMapNode) {
        guard node.canBeOpened, !isMeasuring else { return }
        if node.isOpened {
            path.append(node)
        } else {
            measure(node.url, replacingPathFrom: path.count)
        }
    }

    /// Goes back up to one of the folders on the way down.
    func goBack(to index: Int) {
        guard !isMeasuring, index >= 0, index < path.count else { return }
        path = Array(path.prefix(index + 1))
    }

    /// Stops the measuring that is running. What was measured so far is shown.
    func stop() {
        stopFlag?.set()
    }

    /// Measures a folder two levels deep and shows it at the given place on the way down.
    private func measure(_ folder: URL, replacingPathFrom index: Int) {
        guard !isMeasuring else { return }
        isMeasuring = true
        measuringName = ""
        let flag = StopFlag()
        stopFlag = flag

        Task {
            let isHome = index == 0
            let result = await Task.detached(priority: .userInitiated) { () -> (DiskMapNode, DiskMapSnapshot?, Bool) in
                let node = DiskMap.measure(
                    folder,
                    levels: 2,
                    isCancelled: { flag.value },
                    progress: { name in
                        Task { @MainActor in
                            self.measuringName = name
                        }
                    }
                )
                // Only a whole measuring of the home folder is compared and noted down.
                // One that was stopped early would make everything look smaller.
                guard isHome, !flag.value else {
                    return (node, nil, false)
                }
                let store = DiskMapHistoryStore.standard()
                var history = store.load()
                let now = Date()
                let baseline = history.baseline(now: now)
                history.add(DiskMapSnapshot(of: node, date: now))
                let wasSaved = (try? store.save(history)) != nil
                return (node, baseline, wasSaved)
            }.value
            let node = result.0
            self.path = Array(self.path.prefix(index)) + [node]
            if isHome {
                self.measuredAt = Date()
                self.baseline = result.1
                self.wasNotedDown = result.2
            }
            self.isMeasuring = false
            self.stopFlag = nil
        }
    }
}
