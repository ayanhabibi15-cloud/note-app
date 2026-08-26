import SwiftUI
import PencilKit

/// UIKit bridge for PencilKit. Owns the `PKCanvasView` and its tool picker,
/// and reports drawing changes back up so the host view can persist them.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isDrawingEnabled: Bool
    var pencilOnly: Bool
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.alwaysBounceVertical = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 4

        context.coordinator.canvasView = canvasView
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.drawing != drawing {
            canvasView.drawing = drawing
        }
        canvasView.isUserInteractionEnabled = isDrawingEnabled
        canvasView.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput

        DispatchQueue.main.async {
            guard let window = canvasView.window else { return }
            let toolPicker = PKToolPicker.shared(for: window)
            toolPicker?.setVisible(isDrawingEnabled, forFirstResponder: canvasView)
            toolPicker?.addObserver(canvasView)
            if isDrawingEnabled {
                canvasView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var canvasView: PKCanvasView?

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged(canvasView.drawing)
        }
    }
}
