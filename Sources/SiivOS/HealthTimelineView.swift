import SiivOSCore
import SwiftUI

/// The health score with its reasons, how the score and free space have moved over time,
/// and what has changed on this Mac. Nothing on this screen changes the Mac.
struct HealthTimelineView: View {
    @ObservedObject var model: TimelineModel
    /// Opens another section of the app.
    let open: (AppSection) -> Void

    /// False while only the most recent changes are listed.
    @State private var showsEverything = false

    /// How many changes are listed before "Show Earlier Changes" is clicked.
    private static let initialLimit = 40

    var body: some View {
        content
            .navigationTitle(tr("Health Timeline"))
            .onAppear {
                model.prepareForDisplay()
            }
            .alert(
                "SiivOS",
                isPresented: isShowingMessage,
                presenting: model.message
            ) { _ in
                Button("OK") {}
            } message: { text in
                Text(text)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.latestTotal == nil {
            // The very first reading, before there is anything to show.
            LoadingView(text: tr("Taking the first reading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: tr("Health Timeline"), subtitle: subtitle) {
                    ProminentButton(tr("Update Now"), systemImage: "arrow.clockwise") {
                        model.update()
                    }
                    .disabled(model.isUpdating)
                    .help(tr("Look at this Mac again and add a reading. Updating only looks; nothing is changed."))
                }

                scoreSection
                trendsSection
                changesSection
            }
            .padding(24)
            .readableWidth()
        }
    }

    private var subtitle: String {
        if model.isUpdating {
            return tr("Looking at this Mac…")
        }
        guard let date = model.history.readings.last?.date else {
            return tr("Everything here is kept on this Mac only.")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return tr("Last reading: %1$@. Everything here is kept on this Mac only.", formatter.string(from: date))
    }

    // MARK: - The score

    private var scoreSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("Health score"))
                    .font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(total)")
                        .font(.system(size: 52, weight: .semibold))
                        .monospacedDigit()
                    Text(tr("of 100"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                MeterBar(fraction: Double(total) / 100)
                Text(verdict)
                    .fixedSize(horizontal: false, vertical: true)

                if let score = model.score {
                    ForEach(score.parts) { part in
                        ThemedDivider()
                        ScorePartRow(part: part)
                    }
                    ThemedDivider()
                    Text(tr("The score counts what really affects a Mac, free disk space most of all. Memory that is simply in use costs nothing, and neither does a firewall that is off, because that is how macOS comes."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ThemedDivider()
                    HStack(spacing: 12) {
                        GlintLoader(size: 32)
                        Text(tr("Looking at this Mac to explain the score…"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var total: Int {
        model.latestTotal ?? 0
    }

    private var verdict: String {
        switch total {
        case 90...:
            return tr("This Mac is in good shape.")
        case 70..<90:
            return tr("This Mac is doing fine, with a thing or two worth a look.")
        case 50..<70:
            return tr("A few things are holding this Mac back.")
        default:
            return tr("This Mac needs some care. The list below says where.")
        }
    }

    // MARK: - Over time

    private var trendsSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Health score over time"))
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(total)")
                            .font(.system(size: 28, weight: .semibold))
                            .monospacedDigit()
                        Text(tr("now"))
                            .foregroundStyle(.secondary)
                    }
                    if model.scorePoints.count > 1, let first = model.scorePoints.first, let last = model.scorePoints.last {
                        TrendChart(points: model.scorePoints, lowest: 0, highest: 100)
                        TrendDates(first: first.date, last: last.date)
                        Text(tr("Lowest %1$@, highest %2$@ in this time.", "\(lowestScore)", "\(highestScore)"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        TrendNotYet()
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Free space over time"))
                        .font(.headline)
                    FreeSpaceTrend(readings: model.freeSpacePoints, diskTotalBytes: model.diskTotalBytes)
                }
            }
        }
    }

    private var lowestScore: Int {
        model.history.readings.map { $0.score }.min() ?? total
    }

    private var highestScore: Int {
        model.history.readings.map { $0.score }.max() ?? total
    }

    // MARK: - What has changed

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("What has changed"))
                .font(.title3)
                .bold()
            Text(tr("SiivOS notices a change when it takes a reading, so the time shown is when it noticed, not the moment it happened."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayTitle(day.id))
                        .font(.headline)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(day.entries) { entry in
                            if entry.id != day.entries.first?.id {
                                ThemedDivider()
                            }
                            TimelineEntryRow(entry: entry, open: open)
                        }
                    }
                    .cardBackground()
                }
            }

            if hiddenCount > 0 {
                Button(tr("Show Earlier Changes")) {
                    showsEverything = true
                }
                .buttonStyle(SiivOSButtonStyle(.standard))
            }
        }
    }

    /// Everything that has changed, newest first: what SiivOS noticed, and what SiivOS did.
    private var entries: [TimelineEntry] {
        var all: [TimelineEntry] = []
        for event in model.history.events {
            all.append(
                TimelineEntry(
                    id: "event-" + event.id.uuidString,
                    date: event.date,
                    title: event.title,
                    explanation: event.explanation,
                    mark: event.isNoteworthy ? .noteworthy : .plain
                )
            )
        }
        for record in model.ownActions {
            all.append(
                TimelineEntry(
                    id: "action-" + record.id.uuidString,
                    date: record.date,
                    title: record.title,
                    explanation: tr("SiivOS did this. It is listed in History."),
                    mark: .ownAction
                )
            )
        }
        // Newest first. Changes noticed at the same reading keep the order they were found in.
        return all.enumerated()
            .sorted { first, second in
                if first.element.date != second.element.date {
                    return first.element.date > second.element.date
                }
                return first.offset < second.offset
            }
            .map { $0.element }
    }

    private var shownEntries: [TimelineEntry] {
        showsEverything ? entries : Array(entries.prefix(Self.initialLimit))
    }

    private var hiddenCount: Int {
        showsEverything ? 0 : max(0, entries.count - Self.initialLimit)
    }

    /// The listed changes, one group for each day.
    private var days: [TimelineDay] {
        let calendar = Calendar.current
        var result: [TimelineDay] = []
        for entry in shownEntries {
            let start = calendar.startOfDay(for: entry.date)
            if let last = result.last, last.id == start {
                result[result.count - 1] = TimelineDay(id: start, entries: last.entries + [entry])
            } else {
                result.append(TimelineDay(id: start, entries: [entry]))
            }
        }
        return result
    }

    /// "Today", "Yesterday", or the date written out.
    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// True while a problem is being shown to the user.
    private var isShowingMessage: Binding<Bool> {
        Binding(
            get: { model.message != nil },
            set: { isShown in
                if !isShown { model.message = nil }
            }
        )
    }
}

// MARK: - Rows

/// One line in the list of changes.
private struct TimelineEntry: Identifiable {
    enum Mark {
        /// Worth a second glance, such as something new that starts by itself.
        case noteworthy
        /// Something SiivOS itself did.
        case ownAction
        case plain
    }

    let id: String
    let date: Date
    let title: String
    let explanation: String?
    let mark: Mark
}

/// The changes of one day, newest first.
private struct TimelineDay: Identifiable {
    /// The start of the day.
    let id: Date
    let entries: [TimelineEntry]
}

/// One part of the score: what it is, why it got its points, and the points.
private struct ScorePartRow: View {
    let part: HealthScore.Part

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SiivOSIconView(icon, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.title)
                Text(part.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text("\(part.points) / \(part.maximum)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: SiivOSIcon {
        if part.points >= part.maximum {
            return .good
        }
        return part.points == 0 ? .attention : .note
    }
}

private struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let open: (AppSection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            mark
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = entry.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.mark == .noteworthy {
                    Button(tr("Open Protection")) {
                        open(.protection)
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var mark: some View {
        switch entry.mark {
        case .noteworthy:
            SiivOSIconView(.note, size: 24)
        case .ownAction:
            SiivOSIconView(.history, size: 24)
        case .plain:
            Circle()
                .fill(Color.siivosTint)
                .frame(width: 7, height: 7)
        }
    }
}
