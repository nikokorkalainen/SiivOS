import AppKit
import SwiftUI

/// The SiivOS icon set, drawn in code so it needs no image files.
///
/// Every icon has three layers on a 24 x 24 grid, matching the design canvas:
/// - a soft fill with a diagonal gradient, in the tint colour,
/// - a clean outline (1.35 pt at 24 pt), in the tint colour,
/// - one white detail: a glint, the gauge needle, the check mark, the chart's end dot or the
///   clock hands. In light mode the detail is jade, so it stays visible on a light background.
enum SiivOSIcon: String, CaseIterable {
    case overview
    case cleanup
    case apps
    case performance
    case protection
    case timeline
    case history
}

/// Draws one icon from the SiivOS set.
///
///     Label {
///         Text(section.title)
///     } icon: {
///         SiivOSIconView(section.icon, isSelected: selection == section)
///     }
struct SiivOSIconView: View {
    let icon: SiivOSIcon
    /// Width and height. 30 pt in the sidebar, 22 to 24 pt on the Overview cards.
    var size: CGFloat
    /// On a selected sidebar row the whole icon turns white, so it reads on the accent colour.
    var isSelected: Bool

    init(_ icon: SiivOSIcon, size: CGFloat = 30, isSelected: Bool = false) {
        self.icon = icon
        self.size = size
        self.isSelected = isSelected
    }

    var body: some View {
        let tint = isSelected ? Color.white : SiivOSIconColors.tint
        let highlight = isSelected ? Color.white : SiivOSIconColors.highlight
        let parts = SiivOSIconParts.parts(for: icon)
        Canvas { graphics, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            graphics.scaleBy(x: scale, y: scale)
            let line = StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)

            for path in parts.fills {
                let box = path.boundingRect
                let gradient = Gradient(stops: [
                    .init(color: tint.opacity(0.5), location: 0),
                    .init(color: tint.opacity(0.06), location: 1),
                ])
                graphics.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: box.minX, y: box.minY),
                        endPoint: CGPoint(x: box.maxX, y: box.maxY)
                    )
                )
            }
            for path in parts.strokes {
                graphics.stroke(path, with: .color(tint), style: line)
            }
            for path in parts.highlightStrokes {
                graphics.stroke(path, with: .color(highlight), style: line)
            }
            for path in parts.highlightFills {
                graphics.fill(path, with: .color(highlight))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Colours for the icon set.
enum SiivOSIconColors {
    /// Lichen (#9CCBB0) in dark mode, moss (#2F7A5F) in light mode.
    static let tint = adaptive(
        dark: NSColor(srgbRed: 0.612, green: 0.796, blue: 0.690, alpha: 1),
        light: NSColor(srgbRed: 0.184, green: 0.478, blue: 0.373, alpha: 1)
    )

    /// White in dark mode, jade (#1A9E73) in light mode.
    static let highlight = adaptive(
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        light: NSColor(srgbRed: 0.102, green: 0.620, blue: 0.451, alpha: 1)
    )

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// The shapes of each icon, on a 24 x 24 grid.
struct SiivOSIconParts {
    var fills: [Path] = []
    var strokes: [Path] = []
    var highlightStrokes: [Path] = []
    var highlightFills: [Path] = []

    static func parts(for icon: SiivOSIcon) -> SiivOSIconParts {
        switch icon {
        case .overview:
            let screen = rounded(3, 5, 18, 11.5, 2)
            return SiivOSIconParts(
                fills: [screen],
                strokes: [screen, line(12, 16.5, 12, 20), line(8.5, 20, 15.5, 20)],
                highlightFills: [glint(15.6, 10.6, 3)]
            )

        case .cleanup:
            let head = polygon([(8.3, 11.5), (15.9, 11.5), (17.8, 20), (6.4, 20)], closed: true)
            return SiivOSIconParts(
                fills: [head],
                strokes: [line(18.5, 3.5, 13.9, 11.5), head, line(10.3, 15.2, 10.3, 20), line(13.8, 15.2, 13.8, 20)],
                highlightFills: [glint(6.2, 6.2, 2.6)]
            )

        case .apps:
            let tiles = [rounded(4, 4, 6.8, 6.8, 1.7), rounded(4, 13.2, 6.8, 6.8, 1.7), rounded(13.2, 13.2, 6.8, 6.8, 1.7)]
            return SiivOSIconParts(
                fills: tiles,
                strokes: tiles,
                highlightFills: [glint(16.6, 7.4, 3.6)]
            )

        case .performance:
            var dial = Path()
            dial.addRelativeArc(center: CGPoint(x: 12, y: 17), radius: 8, startAngle: .degrees(180), delta: .degrees(180))
            var dialFill = dial
            dialFill.closeSubpath()
            return SiivOSIconParts(
                fills: [dialFill],
                strokes: [
                    dial,
                    line(3.2, 17, 20.8, 17),
                    line(6.4, 11.4, 7.5, 12.5),
                    line(12, 9, 12, 10.6),
                    line(17.6, 11.4, 16.5, 12.5),
                ],
                highlightStrokes: [line(12, 17, 15.7, 12.3)],
                highlightFills: [circle(12, 17, 1.7)]
            )

        case .protection:
            var shield = Path()
            shield.move(to: CGPoint(x: 12, y: 3))
            shield.addLine(to: CGPoint(x: 19, y: 5.8))
            shield.addLine(to: CGPoint(x: 19, y: 11.2))
            shield.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 19, y: 15.5), control2: CGPoint(x: 16.1, y: 19.1))
            shield.addCurve(to: CGPoint(x: 5, y: 11.2), control1: CGPoint(x: 7.9, y: 19.1), control2: CGPoint(x: 5, y: 15.5))
            shield.addLine(to: CGPoint(x: 5, y: 5.8))
            shield.closeSubpath()
            return SiivOSIconParts(
                fills: [shield],
                strokes: [shield],
                highlightStrokes: [polygon([(8.7, 12.1), (11, 14.4), (15.3, 9.7)], closed: false)]
            )

        case .timeline:
            let points: [(CGFloat, CGFloat)] = [(3, 14), (6.5, 12), (9.5, 14.5), (13.5, 8.5), (17, 12), (21, 9)]
            let areaPoints: [(CGFloat, CGFloat)] = [(3, 20)] + points + [(21, 20)]
            let area = polygon(areaPoints, closed: true)
            return SiivOSIconParts(
                fills: [area],
                strokes: [polygon(points, closed: false), line(3, 20, 21, 20)],
                highlightFills: [circle(21, 9, 1.6)]
            )

        case .history:
            var arc = Path()
            arc.addRelativeArc(center: CGPoint(x: 12, y: 12), radius: 7.5, startAngle: .degrees(180), delta: .degrees(-315))
            return SiivOSIconParts(
                fills: [circle(12, 12, 7.5)],
                strokes: [arc, polygon([(4.5, 4.3), (4.5, 7.7), (7.9, 7.7)], closed: false)],
                highlightStrokes: [polygon([(12, 8.4), (12, 12.1), (14.6, 13.7)], closed: false)]
            )
        }
    }

    // MARK: Shape helpers

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        return path
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)], closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0, y: point.1))
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }

    /// A four-point glint with equal arms and concave sides, the logo's shape.
    private static func glint(_ cx: CGFloat, _ cy: CGFloat, _ arm: CGFloat) -> Path {
        let p = arm * 0.18
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - arm))
        path.addQuadCurve(to: CGPoint(x: cx + arm, y: cy), control: CGPoint(x: cx + p, y: cy - p))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy + arm), control: CGPoint(x: cx + p, y: cy + p))
        path.addQuadCurve(to: CGPoint(x: cx - arm, y: cy), control: CGPoint(x: cx - p, y: cy + p))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy - arm), control: CGPoint(x: cx - p, y: cy - p))
        path.closeSubpath()
        return path
    }
}
