import Foundation
import Vision
import UIKit

// MARK: - On-device receipt OCR (ADR-002 v1)
//
// `VNRecognizeTextRequest` runs on the Neural Engine: zero bundle size, zero
// running cost — the whole point of replacing the per-scan Gemini call (ADR-001).
// This type is a thin shell: OCR → order lines top-to-bottom → `ReceiptLineParser`
// (the testable logic) → `ScannedItem`s for the canonicalization cascade.

struct VisionReceiptScanner: ReceiptScanning {

    func scan(imageData: Data) async throws -> [ScannedItem] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw PantryError.decoding("Couldn't read the receipt image.")
        }
        let lines = try await recognizeLines(in: cgImage)
        return ReceiptLineParser.parse(lines).map { line in
            ScannedItem(
                name: line.name,
                // Category is unknown pre-resolution; food_reference defaults are
                // applied at commit. `.dryGoods` mirrors the old Gemini receipt path.
                foodCategory: .dryGoods,
                brandName: nil,
                measureValue: line.measureValue,
                measureUnit: line.measureUnit,
                confidence: line.confidence
            )
        }
    }

    // MARK: - Vision

    private func recognizeLines(in cgImage: CGImage) async throws -> [ReceiptOCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: PantryError.network(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { obs -> ReceiptOCRLine? in
                    guard let best = obs.topCandidates(1).first else { return nil }
                    return ReceiptOCRLine(text: best.string,
                                          confidence: Double(best.confidence),
                                          minY: Double(obs.boundingBox.minY))
                }
                // Vision coordinates are bottom-up; sort descending minY for
                // natural top-to-bottom receipt order.
                continuation.resume(returning: lines.sorted { $0.minY > $1.minY })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PantryError.network(error.localizedDescription))
            }
        }
    }
}
