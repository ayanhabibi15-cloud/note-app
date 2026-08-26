import PencilKit
import Vision
import UIKit

/// Turns a page's ink strokes into plain text using on-device Vision OCR, so
/// the AI assistant (and search, eventually) can work from handwritten notes
/// without any network round trip for the recognition step itself.
enum HandwritingRecognizer {
    static func recognizeText(from drawing: PKDrawing, pageSize: CGSize) async -> String {
        guard !drawing.strokes.isEmpty else { return "" }

        let scale: CGFloat = 2
        let bounds = CGRect(origin: .zero, size: pageSize)
        let image = drawing.image(from: bounds, scale: scale)

        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
