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
    var size: CGFloat = 72

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

    /// A four-point glint with equal arms and concave sides, the same shape as in the app icon.
    private static func glintPath(center c: CGPoint, arm: CGFloat, pinch p: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: c.x, y: c.y - arm))
            path.addQuadCurve(to: CGPoint(x: c.x + arm, y: c.y), control: CGPoint(x: c.x + p, y: c.y - p))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + arm), control: CGPoint(x: c.x + p, y: c.y + p))
            path.addQuadCurve(to: CGPoint(x: c.x - arm, y: c.y), control: CGPoint(x: c.x - p, y: c.y + p))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - arm), control: CGPoint(x: c.x - p, y: c.y - p))
            path.closeSubpath()
        }
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
