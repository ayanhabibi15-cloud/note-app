import SwiftUI

/// The paper styles a page or notebook can use, modeled after Notability's
/// built-in note templates (blank, lined, graph, dotted, Cornell, checklist).
enum PageTemplate: String, CaseIterable, Identifiable, Codable {
    case blank
    case linedNarrow
    case linedWide
    case gridSmall
    case gridLarge
    case dotted
    case cornell
    case checklist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .linedNarrow: return "Lined (Narrow)"
        case .linedWide: return "Lined (College)"
        case .gridSmall: return "Grid (Small)"
        case .gridLarge: return "Grid (Large)"
        case .dotted: return "Dotted"
        case .cornell: return "Cornell Notes"
        case .checklist: return "Checklist"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: return "square"
        case .linedNarrow, .linedWide: return "text.alignleft"
        case .gridSmall, .gridLarge: return "grid"
        case .dotted: return "circle.grid.3x3"
        case .cornell: return "rectangle.split.2x1"
        case .checklist: return "checklist"
        }
    }

    /// Draws this template's background pattern into `context` for the given page `size`.
    /// Used both by the live editor background and by page thumbnails.
    func draw(in context: GraphicsContext, size: CGSize) {
        let lineColor = Color.gray.opacity(0.35)

        switch self {
        case .blank:
            break

        case .linedNarrow, .linedWide:
            let spacing: CGFloat = self == .linedNarrow ? 24 : 32
            var y: CGFloat = spacing
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
                y += spacing
            }
            drawMargin(in: context, size: size, color: Color.red.opacity(0.3))

        case .gridSmall, .gridLarge:
            let spacing: CGFloat = self == .gridSmall ? 18 : 32
            var x: CGFloat = spacing
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = spacing
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
                y += spacing
            }

        case .dotted:
            let spacing: CGFloat = 24
            var y: CGFloat = spacing
            while y < size.height {
                var x: CGFloat = spacing
                while x < size.width {
                    let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    context.fill(dot, with: .color(lineColor))
                    x += spacing
                }
                y += spacing
            }

        case .cornell:
            let cueColumnWidth = size.width * 0.28
            let summaryHeight: CGFloat = 90
            var vertical = Path()
            vertical.move(to: CGPoint(x: cueColumnWidth, y: 0))
            vertical.addLine(to: CGPoint(x: cueColumnWidth, y: size.height - summaryHeight))
            context.stroke(vertical, with: .color(lineColor), lineWidth: 1.5)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: size.height - summaryHeight))
            horizontal.addLine(to: CGPoint(x: size.width, y: size.height - summaryHeight))
            context.stroke(horizontal, with: .color(lineColor), lineWidth: 1.5)

            var y: CGFloat = 32
            while y < size.height - summaryHeight {
                var path = Path()
                path.move(to: CGPoint(x: cueColumnWidth, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor.opacity(0.7)), lineWidth: 1)
                y += 28
            }

        case .checklist:
            let spacing: CGFloat = 36
            var y: CGFloat = spacing
            while y < size.height {
                let box = Path(roundedRect: CGRect(x: 16, y: y - 12, width: 16, height: 16), cornerRadius: 3)
                context.stroke(box, with: .color(lineColor), lineWidth: 1.5)
                var line = Path()
                line.move(to: CGPoint(x: 44, y: y))
                line.addLine(to: CGPoint(x: size.width - 16, y: y))
                context.stroke(line, with: .color(lineColor), lineWidth: 1)
                y += spacing
            }
        }
    }

    private func drawMargin(in context: GraphicsContext, size: CGSize, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 56, y: 0))
        path.addLine(to: CGPoint(x: 56, y: size.height))
        context.stroke(path, with: .color(color), lineWidth: 1)
    }
}

/// A standard note page size (US Letter at 72dpi points) used for canvas + thumbnails.
enum PageSize {
    static let standard = CGSize(width: 612, height: 792)
}
