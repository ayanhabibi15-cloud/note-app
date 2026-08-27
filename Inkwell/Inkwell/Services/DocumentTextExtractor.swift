import Foundation
import PDFKit
import Vision
import UIKit

/// Pulls plain text out of an imported document so the assistant can read it.
///
/// Everything here runs on the device: PDFKit for embedded PDF text, Vision
/// OCR for scanned pages and photos, and a direct read for plain-text formats.
/// No file is ever uploaded — only the extracted text is included in a prompt,
/// and only when the user asks a question.
enum DocumentTextExtractor {

    struct Result {
        var text: String
        var pageCount: Int
        var failed: Bool
    }

    /// Extraction caps the amount of text kept per document. Long PDFs blow up
    /// prompt size (and cost) far faster than they add usable context, so the
    /// text is truncated with a marker the model can see.
    static let characterLimit = 60_000

    static func extract(from url: URL, kind: DocumentKind) async -> Result {
        switch kind {
        case .pdf:
            return await extractPDF(at: url)
        case .image:
            return await extractImage(at: url)
        case .text:
            return extractPlainText(at: url)
        case .other:
            // Some "other" types (.rtf, .csv, .json, source files) are still
            // readable as UTF-8; try that before giving up.
            let plain = extractPlainText(at: url)
            return plain.failed ? Result(text: "", pageCount: 0, failed: true) : plain
        }
    }

    private static func extractPDF(at url: URL) async -> Result {
        guard let document = PDFDocument(url: url) else {
            return Result(text: "", pageCount: 0, failed: true)
        }

        var pieces: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.isEmpty {
                // Scanned page with no text layer — OCR it.
                let ocr = await recognizeText(in: image(of: page))
                if !ocr.isEmpty {
                    pieces.append("[Page \(index + 1)]\n\(ocr)")
                }
            } else {
                pieces.append("[Page \(index + 1)]\n\(pageText)")
            }
        }

        let joined = truncated(pieces.joined(separator: "\n\n"))
        return Result(text: joined, pageCount: document.pageCount, failed: joined.isEmpty)
    }

    private static func image(of page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private static func extractImage(at url: URL) async -> Result {
        guard let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) else {
            return Result(text: "", pageCount: 0, failed: true)
        }
        let text = await recognizeText(in: uiImage)
        return Result(text: truncated(text), pageCount: 1, failed: text.isEmpty)
    }

    private static func extractPlainText(at url: URL) -> Result {
        guard let data = try? Data(contentsOf: url) else {
            return Result(text: "", pageCount: 0, failed: true)
        }
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let decoded, !decoded.isEmpty else {
            return Result(text: "", pageCount: 0, failed: true)
        }
        return Result(text: truncated(decoded), pageCount: 1, failed: false)
    }

    private static func recognizeText(in image: UIImage?) async -> String {
        guard let cgImage = image?.cgImage else { return "" }
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

    private static func truncated(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        let cut = text.prefix(characterLimit)
        return String(cut) + "\n\n[… document truncated at \(characterLimit) characters …]"
    }
}
