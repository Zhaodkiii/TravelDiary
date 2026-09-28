import Foundation
import PDFKit
import QuickLookThumbnailing
import UIKit

struct OCRDocumentExtractor {
    let config: OCRConfiguration

    func extractText(from url: URL, orchestrator: OCROrchestrator, options: OCRRequestOptions) async throws -> OCRRecognition {
        guard url.isFileURL else {
            throw OCRError.invalidDocumentURL
        }

        switch url.pathExtension.lowercased() {
        case "pdf":
            if let textLayer = try extractPDFTextLayer(url), !textLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let corrected = options.correctMedicalTerms ? SparkMedicalTermsCorrector.shared.correct(textLayer) : textLayer
                let output = OCRTextOutput(engine: "pdf_text_layer", text: corrected, confidence: 1.0, elapsedMs: nil)
                return OCRRecognition(text: corrected, selectedEngine: "pdf_text_layer", outputs: [output])
            }
            return try await ocrScannedPDF(url: url, orchestrator: orchestrator, options: options)

        case "txt":
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let corrected = options.correctMedicalTerms ? SparkMedicalTermsCorrector.shared.correct(text) : text
            let output = OCRTextOutput(engine: "plain_text", text: corrected, confidence: 1.0, elapsedMs: nil)
            return OCRRecognition(text: corrected, selectedEngine: "plain_text", outputs: [output])

        default:
            if let image = try await quickLookThumbnail(url: url, maxSide: config.thumbnailMaxSide),
               let data = image.jpegData(compressionQuality: 0.95) {
                return try await orchestrator.recognize(imageData: data, options: options)
            }
            throw OCRError.response("unsupported_document_or_thumbnail_failed")
        }
    }

    private func extractPDFTextLayer(_ url: URL) throws -> String? {
        guard let document = PDFDocument(url: url) else {
            return nil
        }
        var allTexts: [String] = []
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex), let text = page.string, !text.isEmpty {
                allTexts.append(text)
            }
        }
        return allTexts.isEmpty ? nil : allTexts.joined(separator: "\n")
    }

    private func ocrScannedPDF(url: URL, orchestrator: OCROrchestrator, options: OCRRequestOptions) async throws -> OCRRecognition {
        guard let document = PDFDocument(url: url) else {
            throw OCRError.invalidDocumentURL
        }

        var pageRecognitions: [OCRRecognition] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let image = renderPDFPage(page, scale: config.pdfRenderScale),
                  let data = image.jpegData(compressionQuality: 0.95) else {
                continue
            }
            let recognition = try await orchestrator.recognize(imageData: data, options: options)
            pageRecognitions.append(recognition)
        }

        let joinedText = pageRecognitions.map(\.text).joined(separator: "\n")
        let outputs = pageRecognitions.flatMap(\.outputs)
        return OCRRecognition(text: joinedText, selectedEngine: pageRecognitions.last?.selectedEngine ?? "vision", outputs: outputs)
    }

    private func renderPDFPage(_ page: PDFPage, scale: CGFloat) -> UIImage? {
        let rect = page.bounds(for: .mediaBox)
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }

    private func quickLookThumbnail(url: URL, maxSide: CGFloat) async throws -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxSide, height: maxSide),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )

        return try await withCheckedThrowingContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }
}
