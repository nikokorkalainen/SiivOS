import AppKit
import SiivOSCore
import SwiftUI

/// Whether the welcome has been shown on this Mac.
enum Welcome {
    static let hasBeenSeenKey = "hasSeenWelcome"

    static var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: hasBeenSeenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: hasBeenSeenKey)
    }
}

/// The first thing anyone sees of SiivOS. It fills the window, without the sidebar, in
/// two steps: what SiivOS is, and the one optional permission. It changes nothing, and
/// can be opened again from Settings. See "Welcome" in docs/design.md.
struct WelcomeView: View {
    let onDone: () -> Void

    @State private var step = 1
    /// When the logo's entrance began. Kept for as long as the welcome is open, so that
    /// coming back to the first step does not play it again.
    @State private var startedAt = Date()
    /// True once a step's content has risen in. It rises in once.
    @State private var stepOneIsShown = false
    @State private var stepTwoIsShown = false
    /// Whether macOS lets SiivOS see every folder. Looked up again whenever SiivOS
    /// comes forward, for example after a visit to System Settings.
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // A centred column, centred vertically too. In a small window it scrolls.
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if step == 1 {
                            stepOne
                        } else {
                            stepTwo
                        }
                    }
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
            footer
        }
        .background(SiivOSWindowBackground())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
    }

    /// Lets a part of a step rise 10 pt and fade in, a little after the part before it.
    /// With Reduce Motion on, it only fades in.
    private func rising(_ isShown: Bool, after delay: Double) -> RiseIn {
        RiseIn(isShown: isShown, delay: delay, reduceMotion: reduceMotion)
    }

    // MARK: Step 1: what SiivOS is

    /// The heading and what follows wait for the logo's entrance, which takes about two
    /// seconds to write the name.
    private var stepOneDelay: Double {
        reduceMotion ? 0 : 1.9
    }

    private var stepOne: some View {
        VStack(spacing: 0) {
            // The canvas around the logo is larger than the logo, for its glow. Only
            // about the logo's own height counts in the layout. The logo brings its own
            // entrance; with Reduce Motion on it fades in like the rest.
            WelcomeLogo(startedAt: startedAt)
                .frame(height: 104)
                .modifier(rising(stepOneIsShown || !reduceMotion, after: 0))

            Text(tr("Free up space and keep this Mac running well"))
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .modifier(rising(stepOneIsShown, after: stepOneDelay))

            Text(tr("SiivOS also shows what is slowing this Mac down and keeps an eye on what changes on it."))
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .modifier(rising(stepOneIsShown, after: stepOneDelay + 0.12))

            VStack(alignment: .leading, spacing: 0) {
                point(
                    .history,
                    tr("You decide, and you can undo"),
                    tr("Nothing is removed before you see what will happen. What you remove waits in a holding area, and History puts it back with one click.")
                )
                pointDivider
                point(
                    .cleanup,
                    tr("Honest labels"),
                    tr("Everything Cleanup finds is marked Safe to remove or Check first, with the reason. No scare numbers.")
                )
                pointDivider
                point(
                    .protection,
                    tr("It stays on this Mac"),
                    tr("No account, no tracking, no ads. SiivOS sends nothing anywhere, and goes online only if you ask it to download virus definitions.")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SiivOSTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SiivOSTheme.divider)
            )
            .padding(.top, 32)
            .modifier(rising(stepOneIsShown, after: stepOneDelay + 0.24))
        }
        .onAppear {
            stepOneIsShown = true
        }
    }

    /// One row of the panel: a 40 pt icon from the SiivOS set, a title and a sentence
    /// or two.
    private func point(_ icon: SiivOSIcon, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SiivOSIconView(icon, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// A divider between rows, starting under the text and not under the icon.
    private var pointDivider: some View {
        ThemedDivider()
            .padding(.leading, 16 + 40 + 14)
    }

    // MARK: Step 2: Full Disk Access

    private var stepTwo: some View {
        VStack(spacing: 0) {
            PermissionPicture()
                .modifier(rising(stepTwoIsShown, after: 0))

            Text(tr("One permission, if you want it"))
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
                .modifier(rising(stepTwoIsShown, after: 0.1))

            VStack(spacing: 8) {
                Text(tr("With Full Disk Access, SiivOS can look through every folder in one go instead of macOS asking about one at a time, and show which apps hold which permissions."))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(tr("It does not make SiivOS less careful: you still see everything before anything is removed."))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            .modifier(rising(stepTwoIsShown, after: 0.2))

            Group {
                if hasFullDiskAccess {
                    accessIsOn
                } else {
                    howToTurnItOn
                }
            }
            .padding(.top, 24)
            .modifier(rising(stepTwoIsShown, after: 0.3))
        }
        .onAppear {
            stepTwoIsShown = true
        }
    }

    /// While the permission is off: three numbered steps, then the way to the page in
    /// System Settings, with the state beside it.
    private var howToTurnItOn: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                numbered(1, tr("Open Full Disk Access in System Settings."))
                numbered(2, tr("Switch SiivOS on. If it is not in the list, add it with the + button."))
                numbered(3, tr("Come back here. macOS may ask you to reopen SiivOS."))
            }

            HStack(spacing: 14) {
                ProminentButton(tr("Open Full Disk Access Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                HStack(spacing: 7) {
                    Circle()
                        .fill(SiivOSIconColors.attention)
                        .frame(width: 8, height: 8)
                    Text(tr("Not on yet"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 22, height: 22)
                .background(SiivOSTheme.panel, in: Circle())
                .overlay(Circle().strokeBorder(SiivOSTheme.divider))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Once the permission is on, the steps and the button give way to this.
    private var accessIsOn: some View {
        HStack(spacing: 12) {
            SiivOSIconView(.good, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Full Disk Access is on"))
                    .fontWeight(.semibold)
                Text(tr("SiivOS can see every folder, so macOS will not ask folder by folder."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 460, alignment: .leading)
        .cardBackground()
    }

    // MARK: Footer

    /// Pinned to the bottom: the step dots on the left, and the way on at the right.
    private var footer: some View {
        HStack(spacing: 14) {
            stepDots
            Spacer(minLength: 12)
            if step == 1 {
                ProminentButton(tr("Continue"), minWidth: 140) {
                    go(to: 2)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if !hasFullDiskAccess {
                    Text(tr("You can turn it on later in Settings."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(tr("Back")) {
                    go(to: 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                if hasFullDiskAccess {
                    ProminentButton(tr("Get Started"), minWidth: 140, action: onDone)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(tr("Get Started"), action: onDone)
                        .buttonStyle(SiivOSButtonStyle(.standard))
                }
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 30)
        .padding(.horizontal, 40)
        // On the first step the footer comes in last, after the logo has written the name.
        .modifier(rising(stepOneIsShown, after: stepOneDelay + 0.36))
    }

    /// The current step is a pill in the accent icon colour, the other a dot in the
    /// outline colour of the plain buttons.
    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { number in
                Capsule()
                    .fill(number == step ? SiivOSIconColors.tint : dotColor)
                    .frame(width: number == step ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tr("Step %1$@ of %2$@", "\(step)", "2"))
    }

    private var dotColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    private func go(to newStep: Int) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = newStep
            }
        }
    }
}

/// Lets a view rise 10 pt and fade in after a delay. With Reduce Motion on, it only
/// fades in, over 0.3 s.
private struct RiseIn: ViewModifier {
    let isShown: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.5).delay(delay),
                value: isShown
            )
    }
}

/// A picture of what to do: a small panel drawn like the Full Disk Access list in System
/// Settings, with a pointer that clicks SiivOS's switch on. It is a drawing in SwiftUI
/// shapes, not a screenshot, and it shows no other app's name or icon.
private struct PermissionPicture: View {
    @State private var pointerHasArrived = false
    @State private var isPressing = false
    @State private var switchIsOn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let mint = Color(red: 0.369, green: 0.902, blue: 0.659)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SiivOSIconView(.protection, size: 16)
                Text(tr("Full Disk Access"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            ThemedDivider()

            VStack(spacing: 4) {
                blankRow(nameWidth: 96)
                siivosRow
                    // Above the rows around it, so that the pointer passes over them.
                    .zIndex(1)
                blankRow(nameWidth: 128)
            }
            .padding(8)
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SiivOSTheme.panel)
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SiivOSTheme.divider)
        )
        .accessibilityHidden(true)
        .task {
            await play()
        }
    }

    /// A row that stands for some other app: a grey square, a grey bar and a grey switch.
    private func blankRow(nameWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(grey)
                .frame(width: 26, height: 26)
            Capsule()
                .fill(grey)
                .frame(width: nameWidth, height: 9)
            Spacer()
            drawnSwitch(isOn: false, fill: grey, knob: Color.white.opacity(colorScheme == .dark ? 0.35 : 0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// SiivOS's own row, tinted mint, with the switch the pointer clicks.
    private var siivosRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
            Text("SiivOS")
                .fontWeight(.semibold)
            Spacer()
            drawnSwitch(isOn: switchIsOn, fill: switchIsOn ? SiivOSTheme.prominent : grey, knob: Color.white)
                .overlay {
                    pointer
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Self.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Self.mint.opacity(0.30))
        )
    }

    private var grey: Color {
        Color.primary.opacity(0.13)
    }

    /// A switch drawn by hand, so that it can be shown turning on without being one.
    private func drawnSwitch(isOn: Bool, fill: Color, knob: Color) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: 34, height: 20)
            .overlay(
                Circle()
                    .fill(knob)
                    .frame(width: 16, height: 16)
                    .offset(x: isOn ? 7 : -7)
            )
    }

    /// The pointer: it comes in from below, lands on the switch and presses it. Left
    /// out with Reduce Motion on, where the switch is simply drawn on.
    @ViewBuilder
    private var pointer: some View {
        if !reduceMotion {
            Image(systemName: "cursorarrow")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.6), radius: 1.5, x: 0, y: 1)
                .scaleEffect(isPressing ? 0.88 : 1)
                .offset(x: pointerHasArrived ? 8 : -64, y: pointerHasArrived ? 11 : 58)
                .opacity(pointerHasArrived ? 1 : 0)
        }
    }

    /// The pointer moves onto the switch, presses, and the switch slides on: over 1.6 s,
    /// starting half a second after the picture appears.
    @MainActor
    private func play() async {
        guard !reduceMotion else {
            switchIsOn = true
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            pointerHasArrived = true
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isPressing = true
        }
        try? await Task.sleep(nanoseconds: 180_000_000)
        if Task.isCancelled { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            switchIsOn = true
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isPressing = false
        }
    }
}
