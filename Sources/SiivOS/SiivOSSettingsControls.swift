import AppKit
import SiivOSCore
import SwiftUI

// Building blocks for the Settings screen. See "Settings" in docs/design.md.

/// One setting: a label with optional notes under it, and its control at the far end.
/// The label and notes wrap, so long Finnish texts are never cut off.
///
///     SettingRow(tr("Show SiivOS in the menu bar"), notes: [tr("With this on, …")]) {
///         Toggle(tr("Show SiivOS in the menu bar"), isOn: $showsMenuBar)
///             .toggleStyle(.switch)
///             .labelsHidden()
///             .tint(SiivOSTheme.prominent)
///     }
struct SettingRow<Control: View>: View {
    let title: String
    let notes: [String]
    let control: Control

    init(_ title: String, notes: [String] = [], @ViewBuilder control: () -> Control) {
        self.title = title
        self.notes = notes
        self.control = control()
    }

    var body: some View {
        // A row with only a label lines its control up with the label. A row with notes
        // keeps the control at the top, next to the label and above the notes.
        HStack(alignment: notes.isEmpty ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(notes, id: \.self) { note in
                    SettingNoteText(note)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Small explanatory text: secondary colour, wraps, at most about 640 pt wide.
struct SettingNoteText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 640, alignment: .leading)
    }
}

/// A choice from a short list, drawn like a small SiivOS button with up and down arrows.
/// Use it instead of `Picker` with `.pickerStyle(.menu)`, whose grey pop-up button does not
/// match the other buttons. The current choice has a checkmark in the menu.
struct SiivOSMenuPicker<Value: Hashable>: View {
    /// Read by VoiceOver; the row's label shows it on screen.
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 92, alignment: .leading)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SiivOSButtonStyle(.small))
        .fixedSize()
        .accessibilityLabel(title)
    }

    private var currentTitle: String {
        options.first { $0.0 == selection }?.1 ?? ""
    }
}

/// "On" or "Off" with a small dot: the tint colour when on, calm amber when off.
struct SettingStatus: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isOn ? SiivOSIconColors.tint : SiivOSIconColors.attention)
                .frame(width: 8, height: 8)
            Text(isOn ? tr("On") : tr("Off"))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A file path in a fixed-width font, cut in the middle when long, selectable, with Copy Path.
struct SettingPathField: View {
    let path: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.05))
                )
            Button(copied ? tr("Copied") : tr("Copy Path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    copied = false
                }
            }
            .buttonStyle(SiivOSButtonStyle(.small))
            .frame(minWidth: 92)
        }
    }
}

/// The one line shown when a setting could not be saved.
struct SettingErrorLine: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SiivOSIconView(.attention, size: 18)
            Text(tr("The setting could not be saved: %1$@", reason))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
