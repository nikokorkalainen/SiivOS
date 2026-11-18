import AppKit
import SwiftUI

/// The SiivOS loading indicator: the two glints from the app icon take turns to twinkle.
///
/// Each glint grows, brightens and makes a quarter turn while the other rests. A glint looks the
/// same after a quarter turn, so the loop has no visible seam. With Reduce Motion turned on, the
/// glints stay still and only fade gently.
///
/// Use it in place of `ProgressView` while scanning:
///
///     VStack(spacing: 18) {
///         GlintLoader()
///         Text(progressText).foregroundStyle(.secondary)
///     }
struct GlintLoader: View {
    /// Width and height of the indicator.
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one full twinkle of each glint.
    private let cycle: Double = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, canvasSize in
                // The artwork is drawn on a 120 x 120 grid, like the canvas mockup.
                let unit = min(canvasSize.width, canvasSize.height) / 120
                drawGlint(
                    in: &graphics,
                    center: CGPoint(x: 68 * unit, y: 55 * unit),
                    arm: 34 * unit,
                    pinch: 6 * unit,
                    color: Self.bigGlintColor,
                    phase: phase(at: time, offset: 0)
                )
                drawGlint(
                    in: &graphics,
                    center: CGPoint(x: 34 * unit, y: 83 * unit),
                    arm: 16 * unit,
                    pinch: 3 * unit,
                    color: Self.smallGlintColor,
                    phase: phase(at: time, offset: 0.5)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Where a glint is in its twinkle, from 0 up to (but not including) 1.
    private func phase(at time: Double, offset: Double) -> Double {
        let value = (time / cycle + offset).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    private func drawGlint(
        in graphics: inout GraphicsContext,
        center: CGPoint,
        arm: CGFloat,
        pinch: CGFloat,
        color: Color,
        phase: Double
    ) {
        // 0 at the quietest point of the twinkle, 1 at the brightest.
        let wave = 0.5 - 0.5 * cos(2 * Double.pi * phase)
        let scale = reduceMotion ? 1 : 0.55 + 0.45 * wave
        let angle = reduceMotion ? 0 : phase * Double.pi / 2
        let opacity = reduceMotion ? 0.55 + 0.45 * wave : 0.6 + 0.4 * wave

        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(angle))
            .scaledBy(x: CGFloat(scale), y: CGFloat(scale))
            .translatedBy(x: -center.x, y: -center.y)
        let path = Self.glintPath(center: center, arm: arm, pinch: pinch).applying(transform)
        graphics.fill(path, with: .color(color.opacity(opacity)))
    }

    /// The SiivOS glint, as drawn in the logo file: four points joined by soft curves, with
    /// control points at 12 % and 45.4 % of the arm. `pinch` is no longer used.
    private static func glintPath(center c: CGPoint, arm: CGFloat, pinch: CGFloat) -> Path {
        let k1 = arm * 0.12, k2 = arm * 0.454
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - arm))
        path.addCurve(to: CGPoint(x: c.x + arm, y: c.y), control1: CGPoint(x: c.x + k1, y: c.y - k2), control2: CGPoint(x: c.x + k2, y: c.y - k1))
        path.addCurve(to: CGPoint(x: c.x, y: c.y + arm), control1: CGPoint(x: c.x + k2, y: c.y + k1), control2: CGPoint(x: c.x + k1, y: c.y + k2))
        path.addCurve(to: CGPoint(x: c.x - arm, y: c.y), control1: CGPoint(x: c.x - k1, y: c.y + k2), control2: CGPoint(x: c.x - k2, y: c.y + k1))
        path.addCurve(to: CGPoint(x: c.x, y: c.y - arm), control1: CGPoint(x: c.x - k2, y: c.y - k1), control2: CGPoint(x: c.x - k1, y: c.y - k2))
        path.closeSubpath()
        return path
    }

    /// Near-white in dark mode, deep green (#145C47) in light mode.
    private static let bigGlintColor = adaptiveColor(
        dark: NSColor(srgbRed: 0.961, green: 0.969, blue: 0.961, alpha: 1),
        light: NSColor(srgbRed: 0.078, green: 0.361, blue: 0.278, alpha: 1)
    )

    /// Mint (#5EE6A8) in dark mode, jade (#1A9E73) in light mode.
    private static let smallGlintColor = adaptiveColor(
        dark: NSColor(srgbRed: 0.369, green: 0.902, blue: 0.659, alpha: 1),
        light: NSColor(srgbRed: 0.102, green: 0.620, blue: 0.451, alpha: 1)
    )

    private static func adaptiveColor(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
