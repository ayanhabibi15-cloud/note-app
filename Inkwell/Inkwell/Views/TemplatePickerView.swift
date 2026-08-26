import SwiftUI

/// Grid of paper-style swatches (blank, lined, grid, dotted, Cornell, checklist)
/// used both when creating a notebook and when changing a page's template.
struct TemplatePicker: View {
    @Binding var selection: PageTemplate

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(PageTemplate.allCases) { template in
                VStack(spacing: 6) {
                    TemplateSwatch(template: template)
                        .frame(width: 88, height: 114)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(template == selection ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: template == selection ? 2 : 1)
                        }
                    Text(template.displayName)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selection = template }
            }
        }
    }
}

struct TemplateSwatch: View {
    let template: PageTemplate

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let scaleX = size.width / PageSize.standard.width
            let scaleY = size.height / PageSize.standard.height
            context.scaleBy(x: scaleX, y: scaleY)
            template.draw(in: context, size: PageSize.standard)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
