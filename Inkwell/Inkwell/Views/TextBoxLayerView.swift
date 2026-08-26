import SwiftUI

/// Renders and edits the typed-text annotations on a page. Active only while
/// the editor is in `.text` mode; drawing strokes always sit above/below via
/// the sibling `CanvasView` in `PageEditorView`.
struct TextBoxLayerView: View {
    @Bindable var page: Page
    var isEditing: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(page.textBoxes) { box in
                TextBoxView(
                    box: binding(for: box),
                    isEditing: isEditing,
                    onDelete: { delete(box) }
                )
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(isEditing || !page.textBoxes.isEmpty)
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard isEditing else { return }
                    addTextBox(at: value.location)
                }
        )
    }

    private func binding(for box: TextBox) -> Binding<TextBox> {
        Binding(
            get: { page.textBoxes.first { $0.id == box.id } ?? box },
            set: { updated in
                var boxes = page.textBoxes
                if let index = boxes.firstIndex(where: { $0.id == updated.id }) {
                    boxes[index] = updated
                    page.textBoxes = boxes
                    page.updatedAt = .now
                }
            }
        )
    }

    private func addTextBox(at location: CGPoint) {
        var boxes = page.textBoxes
        boxes.append(TextBox(text: "", x: location.x, y: location.y))
        page.textBoxes = boxes
        page.updatedAt = .now
    }

    private func delete(_ box: TextBox) {
        page.textBoxes.removeAll { $0.id == box.id }
        page.updatedAt = .now
    }
}

private struct TextBoxView: View {
    @Binding var box: TextBox
    var isEditing: Bool
    var onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditing {
                HStack {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = value.translation }
                        .onEnded { value in
                            box.x += value.translation.width
                            box.y += value.translation.height
                            dragOffset = .zero
                        }
                )
            }

            TextEditor(text: $box.text)
                .font(.system(size: box.fontSize))
                .foregroundStyle(Color(hex: box.colorHex))
                .scrollContentBackground(.hidden)
                .frame(width: box.width, height: max(40, box.fontSize * 3))
                .focused($isFocused)
                .disabled(!isEditing)
                .background(isEditing ? Color.yellow.opacity(0.08) : .clear)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3))
                    }
                }
        }
        .position(x: box.x + dragOffset.width, y: box.y + dragOffset.height)
    }
}
