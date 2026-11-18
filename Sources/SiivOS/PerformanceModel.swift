import SiivOSCore
import SwiftUI

/// Keeps the Performance screen supplied with fresh readings while it is on screen.
@MainActor
final class PerformanceModel: ObservableObject {
    /// How many readings are kept for the charts: three minutes' worth.
    static let historyLimit = 60
    /// Seconds between readings.
    private static let interval: Double = 3

    /// The readings so far, oldest first.
    @Published private(set) var samples: [PerformanceSample] = []
    /// What SiivOS makes of the readings, most important first.
    @Published private(set) var diagnoses: [Diagnosis] = []

    private let sampler = PerformanceSampler()

    var latest: PerformanceSample? {
        samples.last
    }

    /// Takes a reading every few seconds until the task it runs in is cancelled, which
    /// happens when the user leaves the screen. Nothing is measured while it is closed.
    func run() async {
        // Readings from an earlier visit are too old to draw one line with new ones.
        if let last = samples.last, Date().timeIntervalSince(last.date) > Self.interval * 4 {
            samples = []
            diagnoses = []
        }

        let sampler = self.sampler
        while !Task.isCancelled {
            let sample = await Task.detached(priority: .utility) {
                sampler.sample()
            }.value
            if Task.isCancelled {
                break
            }
            samples.append(sample)
            if samples.count > Self.historyLimit {
                samples.removeFirst(samples.count - Self.historyLimit)
            }
            diagnoses = PerformanceDiagnosis.evaluate(samples)

            // Processor use needs two readings, so the second one follows quickly.
            let wait = samples.count == 1 ? 1.0 : Self.interval
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}
