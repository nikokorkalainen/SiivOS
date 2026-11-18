import SiivOSCore
import SwiftUI

/// A line that shows how one number has changed over days or weeks. Each reading sits
/// where its date puts it, so a long gap between readings looks like a long gap.
struct TrendChart: View {
    struct Point: Equatable {
        let date: Date
        let value: Double
    }

    /// Readings, oldest first.
    let points: [Point]
    /// The value at the bottom edge of the chart.
    let lowest: Double
    /// The value at the top edge of the chart.
    let highest: Double
    var height: CGFloat = 72

    var body: some View {
        GeometryReader { proxy in
            let places = self.places(in: proxy.size)
            ZStack {
                area(through: places, height: proxy.size.height)
                    .fill(
                        LinearGradient(
                            colors: [Color.siivosTint.opacity(0.3), Color.siivosTint.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                line(through: places)
                    .stroke(Color.siivosTint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = places.last {
                    Circle()
                        .fill(Color.siivosTint)
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Where each reading sits in the chart.
    private func places(in size: CGSize) -> [CGPoint] {
        guard let first = points.first, let last = points.last else {
            return []
        }
        // Leave room for the line's own thickness and the dot at the end.
        let inset: CGFloat = 4
        let usableWidth = max(0, size.width - inset * 2)
        let usableHeight = max(0, size.height - inset * 2)
        let duration = last.date.timeIntervalSince(first.date)
        let span = highest - lowest

        var result: [CGPoint] = []
        for point in points {
            let across = duration > 0 ? point.date.timeIntervalSince(first.date) / duration : 1
            let up = span > 0 ? min(1, max(0, (point.value - lowest) / span)) : 0.5
            result.append(
                CGPoint(
                    x: inset + usableWidth * CGFloat(across),
                    y: inset + usableHeight * CGFloat(1 - up)
                )
            )
        }
        return result
    }

    private func line(through places: [CGPoint]) -> Path {
        var path = Path()
        guard places.count > 1, let first = places.first else {
            return path
        }
        path.move(to: first)
        for place in places.dropFirst() {
            path.addLine(to: place)
        }
        return path
    }

    /// The shape under the line, down to the bottom edge.
    private func area(through places: [CGPoint], height: CGFloat) -> Path {
        var path = line(through: places)
        guard places.count > 1, let first = places.first, let last = places.last else {
            return path
        }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

/// Free space on the startup disk over time: the amount now, the line, the dates at both
/// ends, and the lowest and highest in between. Shown on the Health Timeline and the Overview.
struct FreeSpaceTrend: View {
    /// Free space in bytes at each reading, oldest first.
    let readings: [TrendChart.Point]
    /// The size of the disk, used to keep small ups and downs from looking dramatic.
    let diskTotalBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let last = readings.last {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBytes(Int64(last.value)))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                    Text(tr("free now"))
                        .foregroundStyle(.secondary)
                }
            }
            if readings.count > 1, let first = readings.first, let last = readings.last {
                TrendChart(
                    points: readings,
                    lowest: scale.lowerBound,
                    highest: scale.upperBound
                )
                TrendDates(first: first.date, last: last.date)
                Text(tr("Lowest %1$@, highest %2$@ in this time.", formatBytes(Int64(lowestValue)), formatBytes(Int64(highestValue))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TrendNotYet()
            }
        }
    }

    private var lowestValue: Double {
        readings.map { $0.value }.min() ?? 0
    }

    private var highestValue: Double {
        readings.map { $0.value }.max() ?? 0
    }

    /// The values at the bottom and top of the chart: the readings with a little air, and
    /// never less than a twentieth of the disk from bottom to top.
    private var scale: ClosedRange<Double> {
        let smallestSpan = max(Double(diskTotalBytes ?? 0) / 20, 1_000_000_000)
        let span = max(highestValue - lowestValue, smallestSpan)
        let middle = (highestValue + lowestValue) / 2
        let bottom = max(0, middle - span * 0.6)
        return bottom...(bottom + span * 1.2)
    }
}

/// The dates of the first and last reading, under the two ends of a chart.
struct TrendDates: View {
    let first: Date
    let last: Date

    var body: some View {
        HStack {
            Text(first.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            Text(last.formatted(date: .abbreviated, time: .omitted))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// What a chart shows before there are enough readings to draw a line.
struct TrendNotYet: View {
    var body: some View {
        Text(tr("A chart appears here once there are a few readings. SiivOS takes one when you open it, at most every six hours, and when you click Update Now in Health Timeline."))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
