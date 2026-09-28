import Foundation
import UIKit
import Vision

nonisolated struct VisionOCREngine: OCRTextEngine {
    let name: String = "vision"

    func recognize(imageData: Data, hints: OCRRecognitionHints) async throws -> OCRTextOutput {
        let start = Date()
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let text: String = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let sorted = sortObservationsByLines(observations)
                let lines = sorted.compactMap { observation -> String? in
                    extractBestCandidate(from: observation, topCount: hints.topCandidatesCount)
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLanguages = hints.languages
            request.recognitionLevel = hints.recognitionLevel
            request.usesLanguageCorrection = hints.useLanguageCorrection

            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        return OCRTextOutput(engine: name, text: text, confidence: nil, elapsedMs: elapsed)
    }

    nonisolated private func sortObservationsByLines(_ observations: [VNRecognizedTextObservation]) -> [VNRecognizedTextObservation] {
        let sortedByY = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        var lines: [[VNRecognizedTextObservation]] = []

        for observation in sortedByY {
            var added = false
            for idx in 0..<lines.count {
                guard let reference = lines[idx].first else { continue }
                let centerDiff = abs(observation.boundingBox.midY - reference.boundingBox.midY)
                let tolerance = max(reference.boundingBox.height * 0.6, 0.01)
                if centerDiff < tolerance {
                    lines[idx].append(observation)
                    added = true
                    break
                }
            }
            if !added {
                lines.append([observation])
            }
        }

        return lines.flatMap { line in
            line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        }
    }

    nonisolated private func extractBestCandidate(from observation: VNRecognizedTextObservation, topCount: Int) -> String? {
        let candidates = observation.topCandidates(max(1, topCount))
        guard !candidates.isEmpty else { return nil }

        if let best = candidates.first(where: { candidate in
            candidate.string.rangeOfCharacter(from: .alphanumerics) != nil
        }) {
            return best.string
        }
        return candidates.first?.string
    }
}
