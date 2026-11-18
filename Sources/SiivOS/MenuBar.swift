import AppKit
import SiivOSCore
import SwiftUI

/// Settings that are remembered between launches.
enum AppSettings {
    static let showsMenuBarKey = "showsMenuBarWidget"

    /// Whether SiivOS shows itself in the menu bar. On unless it has been turned off.
    static var showsMenuBar: Bool {
        UserDefaults.standard.object(forKey: showsMenuBarKey) as? Bool ?? true
    }
}

/// Which section the window shows. Shared, so that the menu bar can open a section.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selection: AppSection = .overview
}

/// Keeps hold of the app's window, so that the menu bar can bring it to the front, and
/// remembers the window's size and place.
@MainActor
enum MainWindow {
    /// The identifier of the window's scene.
    static let sceneID = "main"

    static weak var current: NSWindow?

    /// The size the window opens in the first time, before it has been resized. The
    /// width gives the content its full readable width next to the open sidebar
    /// (240 + 1 + 24 + 900 + 24 = 1189), so the Overview shows three cards in a row.
    static let defaultSize = CGSize(width: 1_200, height: 800)

    /// Where the window's size and place are remembered, as macOS writes them down.
    static let frameKey = "mainWindowFrame"
    /// Where the size of the window's content is remembered, for the size of a new window.
    static let contentWidthKey = "mainWindowContentWidth"
    static let contentHeightKey = "mainWindowContentHeight"

    /// The size and place the window was last left in, or `nil` if it has never been
    /// moved or resized.
    private static var rememberedFrame: String? {
        UserDefaults.standard.string(forKey: frameKey)
    }

    /// True when the window is where it was last left.
    static func isAsRemembered(_ window: NSWindow) -> Bool {
        guard let remembered = rememberedFrame else {
            return true
        }
        return window.frameDescriptor == remembered
    }

    /// Gives the window the size and place it was last left in. macOS keeps the window
    /// on the screen if the screens have changed since.
    ///
    /// A window with nothing remembered gets the default size, centred. This is done
    /// here as well as on the scene, because macOS may bring back a size of its own
    /// from an earlier version of SiivOS, which would be the old small one.
    static func restoreFrame(of window: NSWindow) {
        if let remembered = rememberedFrame {
            window.setFrame(from: remembered)
            return
        }
        var size = defaultSize
        if let screen = window.screen ?? NSScreen.main {
            size.width = min(size.width, screen.visibleFrame.width)
            size.height = min(size.height, screen.visibleFrame.height)
        }
        window.setContentSize(size)
        window.center()
    }

    /// Brings the app's window to the front, opening a new one if it was closed, and
    /// shows the given section if there is one.
    static func show(_ section: AppSection?, openWindow: OpenWindowAction) {
        if let section {
            AppNavigation.shared.selection = section
        }
        NSApp.activate()
        if let window = current, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: sceneID)
        }
    }

    /// Remembers the window's size and place for the next time it opens.
    static func saveFrame(of window: NSWindow) {
        // A window that fills the screen has no size of its own worth remembering.
        guard !window.styleMask.contains(.fullScreen) else {
            return
        }
        let defaults = UserDefaults.standard
        let frame = window.frameDescriptor
        if defaults.string(forKey: frameKey) != frame {
            defaults.set(frame, forKey: frameKey)
        }
        // The size of the content is what a new window is asked to open in.
        if let size = window.contentView?.frame.size, size.width > 0, size.height > 0 {
            if defaults.double(forKey: contentWidthKey) != Double(size.width) {
                defaults.set(Double(size.width), forKey: contentWidthKey)
            }
            if defaults.double(forKey: contentHeightKey) != Double(size.height) {
                defaults.set(Double(size.height), forKey: contentHeightKey)
            }
        }
    }
}

/// Sits invisibly in the window's content and tells `MainWindow` which window that is.
/// It also makes the window remember its size and place: a window that is closed and
/// opened again, or the app quit and started again, comes back the way it was left.
struct MainWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackingView: NSView {
        /// False while the window is still being set up. Sizes and places it is given
        /// during that time are not the user's doing and must not be remembered.
        private var isSettled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            isSettled = false
            guard let window = self.window else {
                return
            }
            MainWindow.current = window

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didMoveNotification, object: window)
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didResizeNotification, object: window)
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.willCloseNotification, object: window)

            Task { @MainActor [weak self] in
                // Put the window where it was left. A new window is still being given
                // its size and place for a moment after it appears, which can undo
                // this, so look again shortly afterwards and correct it if needed.
                MainWindow.restoreFrame(of: window)
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !MainWindow.isAsRemembered(window) {
                    MainWindow.restoreFrame(of: window)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                // From here on, changes are the user's own and are remembered. Nothing
                // is remembered at this point itself: only what the user then does.
                if let self, self.window === window {
                    self.isSettled = true
                }
            }
        }

        /// Called by macOS when the user lets go after dragging the window's edge.
        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            remember()
        }

        @objc private func windowChanged(_ notification: Notification) {
            // While an edge is being dragged this would run for every step; the end
            // of the drag is enough.
            if let window = self.window, window.inLiveResize {
                return
            }
            remember()
        }

        private func remember() {
            guard isSettled, let window = self.window else {
                return
            }
            MainWindow.saveFrame(of: window)
        }
    }
}

// MARK: - The icon in the menu bar

/// The two glints from the logo, drawn the way the menu bar wants its icons: one colour
/// that macOS tints to suit a light or dark menu bar. A small dot is added when the
/// Health Timeline has noticed something worth a look.
enum MenuBarIcon {
    static let plain = image(hasNote: false)
    static let withNote = image(hasNote: true)

    private static func image(hasNote: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            // The glints as they sit in the logo, on a 120 x 120 grid. Together they
            // cover x 18 to 102 and y 21 to 99.
            let box = CGRect(x: 18, y: 21, width: 84, height: 78)
            let scale = min(rect.width / box.width, rect.height / box.height)
            context.translateBy(
                x: (rect.width - box.width * scale) / 2,
                y: (rect.height - box.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(SiivOSGlintShape.path(center: CGPoint(x: 68, y: 55), arm: 34).cgPath)
            context.addPath(SiivOSGlintShape.path(center: CGPoint(x: 34, y: 83), arm: 16).cgPath)
            context.fillPath()
            if hasNote {
                context.fillEllipse(in: CGRect(x: 80, y: 77, width: 22, height: 22))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// What the menu bar shows: the glints, with a dot when there is something to look at.
struct MenuBarLabel: View {
    @ObservedObject private var timeline = TimelineModel.shared

    var body: some View {
        Image(nsImage: timeline.unseenNoteworthy.isEmpty ? MenuBarIcon.plain : MenuBarIcon.withNote)
            .accessibilityLabel("SiivOS")
    }
}

// MARK: - The panel under the icon

/// Takes a few fresh readings while the menu bar panel is open.
@MainActor
final class MenuBarModel: ObservableObject {
    static let shared = MenuBarModel()

    /// The latest reading, or `nil` before the first one.
    @Published private(set) var sample: PerformanceSample?

    private let sampler = PerformanceSampler()
    private var readings: Task<Void, Never>?

    /// Takes a reading now and a few more over the next twenty seconds, then stops, so
    /// nothing is measured while nobody is looking. Processor use needs two readings,
    /// which is why the second follows quickly.
    func refresh() {
        readings?.cancel()
        let sampler = self.sampler
        readings = Task {
            for wait in [1.0, 5, 5, 5, 5] {
                let sample = await Task.detached(priority: .utility) {
                    sampler.sample()
                }.value
                if Task.isCancelled {
                    return
                }
                self.sample = sample
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled {
                    return
                }
            }
        }
    }
}

/// The small panel that opens from the menu bar: the health score, three facts about
/// right now, anything new worth a look, and a way into the app. It changes nothing.
struct MenuBarPanel: View {
    @ObservedObject private var timeline = TimelineModel.shared
    @ObservedObject private var model = MenuBarModel.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            scoreBlock
            ThemedDivider()
            facts
            if let event = timeline.unseenNoteworthy.first {
                ThemedDivider()
                note(event, others: timeline.unseenNoteworthy.count - 1)
            }
            ThemedDivider()
            HStack {
                ProminentButton(tr("Open SiivOS")) {
                    open(nil)
                }
                Spacer()
                Button(tr("Quit SiivOS")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(SiivOSButtonStyle(.standard))
            }
        }
        .padding(16)
        .frame(width: 310)
        .tint(SiivOSTheme.prominent)
        .onAppear {
            model.refresh()
        }
        // The panel can stay alive while it is closed, so also refresh when its window
        // comes forward again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window !== MainWindow.current {
                model.refresh()
            }
        }
    }

    // MARK: Score

    @ViewBuilder
    private var scoreBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Health score"))
                .font(.headline)
            if let total = timeline.latestTotal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text(tr("of 100"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                MeterBar(fraction: Double(total) / 100)
            } else {
                Text(tr("Taking the first reading…"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Right now

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            FactRow(label: tr("Startup disk"), value: diskText)
            FactRow(label: tr("Memory"), value: memoryText)
            FactRow(label: tr("Processor"), value: processorText)
        }
    }

    private var diskText: String {
        guard let sample = model.sample,
              let total = sample.diskTotalBytes,
              let available = sample.diskAvailableBytes
        else {
            return "…"
        }
        return tr("%1$@ free of %2$@", formatBytes(available), formatBytes(total))
    }

    private var memoryText: String {
        guard let pressure = model.sample?.memory?.pressure else {
            return "…"
        }
        switch pressure {
        case .normal:
            return tr("Room to spare")
        case .elevated:
            return tr("Getting tight")
        case .high:
            return tr("Under heavy pressure")
        }
    }

    private var processorText: String {
        guard let fraction = model.sample?.cpuUsedFraction else {
            return "…"
        }
        let percent = min(1, max(0, fraction)).formatted(.percent.precision(.fractionLength(0)))
        return tr("%1$@ in use", percent)
    }

    // MARK: Something new

    private func note(_ event: HealthEvent, others: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SiivOSIconView(.note, size: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .fixedSize(horizontal: false, vertical: true)
                if others > 0 {
                    Text(others == 1 ? tr("and 1 more change worth a look") : tr("and %1$@ more changes worth a look", "\(others)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(tr("Open Health Timeline")) {
                    open(.timeline)
                }
                .buttonStyle(SiivOSButtonStyle(.small))
            }
        }
    }

    // MARK: Opening the app

    /// Brings the app's window to the front, opening a new one if it was closed, and
    /// shows the given section if there is one.
    private func open(_ section: AppSection?) {
        MainWindow.show(section, openWindow: openWindow)
        dismiss()
    }
}
