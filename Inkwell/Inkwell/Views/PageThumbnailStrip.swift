import SwiftUI
import SwiftData
import PencilKit

struct PageThumbnailStrip: View {
    @Bindable var notebook: Notebook
    @Binding var currentPageID: PersistentIdentifier?
    var onSelect: (Page) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(notebook.sortedPages) { page in
                    Button {
                        onSelect(page)
                    } label: {
                        VStack(spacing: 4) {
                            PageThumbnail(page: page)
                                .frame(width: 60, height: 78)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            page.persistentModelID == currentPageID ? Color.accentColor : Color.gray.opacity(0.3),
                                            lineWidth: page.persistentModelID == currentPageID ? 2 : 1
                                        )
                                }
                            Text("\(page.index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

private struct PageThumbnail: View {
    let page: Page

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let scaleX = size.width / PageSize.standard.width
            let scaleY = size.height / PageSize.standard.height
            context.scaleBy(x: scaleX, y: scaleY)
            page.template.draw(in: context, size: PageSize.standard)

            if let uiImage = try? PKDrawingImage.thumbnail(for: page) {
                context.draw(Image(uiImage: uiImage), in: CGRect(origin: .zero, size: PageSize.standard))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

enum PKDrawingImage {
    static func thumbnail(for page: Page) throws -> UIImage {
        let drawing = try PKDrawing(data: page.drawingData)
        return drawing.image(from: CGRect(origin: .zero, size: PageSize.standard), scale: 1)
    }
}
