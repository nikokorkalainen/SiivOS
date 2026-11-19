import Foundation
import SwiftUI

/// The logo as the welcome shows it: 84 pt tall with a soft mint glow behind it, and an
/// entrance the first time it appears. The glints sparkle in, a ping of light leaves the
/// big one, the letters are drawn along their outlines and filled, and a shine passes
/// over them. After that the glints twinkle now and then. See "Welcome", "Motion" in
/// docs/design.md.
///
/// Everything is worked out from the time since the entrance began, so the view has no
/// state of its own: shown again later, it is simply further along. With Reduce Motion
/// on, the logo and the glow stand still.
struct WelcomeLogo: View {
    /// When the entrance began.
    let startedAt: Date
    /// The height of the logo itself.
    var height: CGFloat = 84

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room around the logo for the glow and the ping of light.
    static let canvasSize = CGSize(width: 360, height: 220)

    private static let mint = Color(red: 0.369, green: 0.902, blue: 0.659)

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    glow
                    SiivOSLogo()
                        .frame(height: height)
                }
            } else {
                TimelineView(.animation) { timeline in
                    moving(at: timeline.date.timeIntervalSince(startedAt))
                }
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .accessibilityElement()
        .accessibilityLabel("SiivOS")
    }

    /// The glow: mint at 20 % in the middle, fading to nothing at the edge of an ellipse
    /// as large as the canvas. Drawn as a circle and flattened, so that it fades evenly
    /// in every direction.
    private var glow: some View {
        let width = Self.canvasSize.width
        return Circle()
            .fill(
                RadialGradient(
                    colors: [Self.mint.opacity(0.20), Self.mint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: width / 2
                )
            )
            .frame(width: width, height: width)
            .scaleEffect(x: 1, y: Self.canvasSize.height / width)
            .frame(width: width, height: Self.canvasSize.height)
    }

    private func moving(at time: TimeInterval) -> some View {
        ZStack {
            // 0 s: the glow grows from half size with a slight overshoot.
            glow
                .scaleEffect(Self.mix(0.5, 1, Self.overshoot(time / 1.2, by: 1.2)))
                .opacity(Self.unit(time / 0.5))
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let box = SiivOSLogoPaths.logoSize
        let scale = height / box.height
        // The logo sits in the middle of the canvas. From here on everything is in the
        // logo file's own coordinates.
        context.translateBy(
            x: (size.width - box.width * scale) / 2,
            y: (size.height - box.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        // How wide a line of one point on screen is in those coordinates.
        let point = 1 / scale

        drawLetters(in: context, time: time, point: point)
        drawShine(in: context, time: time)
        drawGlint(
            SiivOSLogoPaths.logoBigGlint,
            around: SiivOSLogoPaths.logoBigGlintCenter,
            color: SiivOSLogoPaths.siivColor,
            pose: Self.glintPose(at: time, entersAt: 0.2, twinklesAfter: 0),
            in: context
        )
        drawGlint(
            SiivOSLogoPaths.logoSmallGlint,
            around: SiivOSLogoPaths.logoSmallGlintCenter,
            color: SiivOSLogoPaths.osColor,
            pose: Self.glintPose(at: time, entersAt: 0.42, twinklesAfter: 0.35),
            in: context
        )
        drawPing(in: context, time: time, point: point)
    }

    /// 0.7 s: the letters are drawn along their outlines, one character after another,
    /// 0.12 s apart. When a character's outline is closed its fill fades in, and the
    /// outline line fades away, leaving the exact logo shape.
    private func drawLetters(in context: GraphicsContext, time: TimeInterval, point: CGFloat) {
        for index in SiivOSLogoPaths.logoLetters.indices {
            let local = time - (0.7 + 0.12 * Double(index))
            guard local > 0 else {
                continue
            }
            let color = index < SiivOSLogoPaths.logoSiivCount ? SiivOSLogoPaths.siivColor : SiivOSLogoPaths.osColor

            let filled = Self.unit((local - 0.65) / 0.45)
            if filled > 0 {
                var layer = context
                layer.opacity = filled
                layer.fill(SiivOSLogoPaths.logoLetters[index], with: .color(color))
            }

            let lineOpacity = 1 - Self.unit((local - 0.95) / 0.35)
            if lineOpacity > 0 {
                let traced = CGFloat(Self.easeInOut(local / 0.95))
                var layer = context
                layer.opacity = lineOpacity
                for outline in SiivOSLogoPaths.logoLetterOutlines[index] {
                    layer.stroke(
                        outline.trimmedPath(from: 0, to: traced),
                        with: .color(color),
                        lineWidth: 1.5 * point
                    )
                }
            }
        }
    }

    /// Every letter in one path, to keep the shine inside their shape.
    private static let allLetters: Path = {
        var path = Path()
        for letter in SiivOSLogoPaths.logoLetters {
            path.addPath(letter)
        }
        return path
    }()

    /// 2.35 s: a soft mint band, slanted 18 degrees, sweeps across the letters once,
    /// inside their shape only.
    private func drawShine(in context: GraphicsContext, time: TimeInterval) {
        let local = time - 2.35
        guard local > 0, local < 1.1 else {
            return
        }
        let box = SiivOSLogoPaths.logoNameBox
        let band: CGFloat = 70
        let progress = CGFloat(Self.easeInOut(local / 1.1))
        let x = box.minX - band + (box.width + 2 * band) * progress
        let slant = 18 * Double.pi / 180
        let start = CGPoint(x: x, y: box.midY)
        let end = CGPoint(x: x + band * CGFloat(cos(slant)), y: box.midY - band * CGFloat(sin(slant)))

        var layer = context
        layer.clip(to: Self.allLetters)
        layer.fill(
            Path(box.insetBy(dx: -band, dy: -10)),
            with: .linearGradient(
                Gradient(colors: [Self.mint.opacity(0), Self.mint.opacity(0.95), Self.mint.opacity(0)]),
                startPoint: start,
                endPoint: end
            )
        )
    }

    private func drawGlint(
        _ path: Path,
        around center: CGPoint,
        color: Color,
        pose: (scale: Double, degrees: Double),
        in context: GraphicsContext
    ) {
        guard pose.scale > 0.001 else {
            return
        }
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(pose.degrees))
        layer.scaleBy(x: CGFloat(pose.scale), y: CGFloat(pose.scale))
        layer.translateBy(x: -center.x, y: -center.y)
        layer.fill(path, with: .color(color))
    }

    /// 0.62 s: a thin outline of the big glint grows from it to 2.6 times its size and
    /// fades out, like a ping of light.
    private func drawPing(in context: GraphicsContext, time: TimeInterval, point: CGFloat) {
        let local = time - 0.62
        guard local > 0, local < 0.9 else {
            return
        }
        let progress = Self.easeOut(local / 0.9)
        let size = CGFloat(Self.mix(1, 2.6, progress))
        let center = SiivOSLogoPaths.logoBigGlintCenter
        let grow = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: size, y: size)
            .translatedBy(x: -center.x, y: -center.y)

        var layer = context
        layer.opacity = 1 - progress
        layer.stroke(
            SiivOSLogoPaths.logoBigGlint.applying(grow),
            with: .color(SiivOSLogoPaths.osColor),
            lineWidth: 2.5 * point
        )
    }

    // MARK: Timing

    /// A glint's size and turn at a moment: nothing before it enters, the sparkle while
    /// it enters, and a twinkle every seven seconds after that.
    private static func glintPose(
        at time: TimeInterval,
        entersAt start: TimeInterval,
        twinklesAfter delay: TimeInterval
    ) -> (scale: Double, degrees: Double) {
        let local = time - start
        if local <= 0 {
            return (0, -135)
        }
        // The sparkle: from nothing and turned away, past full size, back under it,
        // and settled, in 0.8 s.
        if local < 0.42 {
            let part = easeOut(local / 0.42)
            return (mix(0, 1.22, part), mix(-135, 10, part))
        }
        if local < 0.62 {
            let part = easeInOut((local - 0.42) / 0.2)
            return (mix(1.22, 0.94, part), mix(10, -3, part))
        }
        if local < 0.8 {
            let part = easeInOut((local - 0.62) / 0.18)
            return (mix(0.94, 1, part), mix(-3, 0, part))
        }

        // The twinkle: shrink a little, turn a quarter and spring back. A glint has four
        // arms, so a quarter turn ends where it started.
        let sinceFirst = time - 7 - delay
        guard sinceFirst >= 0 else {
            return (1, 0)
        }
        let within = sinceFirst.truncatingRemainder(dividingBy: 7)
        guard within < 0.8 else {
            return (1, 0)
        }
        let part = within / 0.8
        let scale = part < 0.45
            ? mix(1, 0.82, easeInOut(part / 0.45))
            : mix(0.82, 1, overshoot((part - 0.45) / 0.55, by: 1.4))
        return (scale, 90 * easeInOut(part))
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func mix(_ from: Double, _ to: Double, _ part: Double) -> Double {
        from + (to - from) * part
    }

    private static func easeInOut(_ value: Double) -> Double {
        let part = unit(value)
        return part < 0.5 ? 2 * part * part : 1 - pow(-2 * part + 2, 2) / 2
    }

    private static func easeOut(_ value: Double) -> Double {
        1 - pow(1 - unit(value), 3)
    }

    /// Eases out past the end by a little and comes back to it.
    private static func overshoot(_ value: Double, by amount: Double) -> Double {
        let part = unit(value) - 1
        return 1 + (amount + 1) * part * part * part + amount * part * part
    }
}
