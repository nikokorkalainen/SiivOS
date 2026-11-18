import SwiftUI

/// A sturdy, clear control for switching between views, such as Apps and Background Items.
///
/// Use it instead of `.pickerStyle(.segmented)`, which is thin and low in contrast on the green.
/// The selected option is filled with the prominent colour (mint with dark text in dark mode,
/// moss with white text in light mode). The control hugs its content and sits on the left,
/// under the page title, rather than stretching across the window.
///
///     SiivOSSegmentedControl(selection: $tab, options: [
///         (.apps, tr("Apps")),
///         (.background, tr("Background Items")),
///     ])
struct SiivOSSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Option]

    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var highlight

    init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options.map { Option(value: $0.0, title: $0.1) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = option.value
            }
        } label: {
            Text(option.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? SiivOSTheme.onProminent : Color.primary.opacity(0.85))
                .padding(.horizontal, 20)
                .frame(minWidth: 128, minHeight: 34)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SiivOSTheme.prominent)
                            .matchedGeometryEffect(id: "selected", in: highlight)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
