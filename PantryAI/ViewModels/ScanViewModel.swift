import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class ScanViewModel {
    enum Stage {
        case method      // "Add to your pantry" — pick a capture method
        case capturing
        case analysing
        case review
        case done
    }

    enum CaptureMode { case photo, receipt }

    var stage: Stage = .method
    var captureMode: CaptureMode = .photo
    var captured: [Data] = []          // up to 6 photos
    var detected: [ScannedItem] = []
    var error: PantryError?
    var isStreaming = false

    private let gemini: GeminiServiceProtocol
    private let inventory: InventoryService

    init(context: ModelContext, gemini: GeminiServiceProtocol = GeminiService()) {
        self.gemini = gemini
        self.inventory = InventoryService(context: context)
    }

    var canCaptureMore: Bool { captured.count < 6 }

    var remainingCapacity: Int { max(0, 6 - captured.count) }

    func startPhotoCapture() {
        captureMode = .photo
        captured = []
        detected = []
        error = nil
        stage = .capturing
    }

    func startReceiptCapture() {
        captureMode = .receipt
        captured = []
        detected = []
        error = nil
        stage = .capturing
    }

    func add(photo image: UIImage) {
        guard canCaptureMore, let data = image.jpegData(compressionQuality: 0.8) else { return }
        captured.append(data)
    }

    func analyse() async {
        guard !captured.isEmpty else { return }
        stage = .analysing
        do {
            var all: [ScannedItem] = []
            for image in captured {
                let scanned = switch captureMode {
                case .photo:   try await gemini.scanInventory(imageData: image)
                case .receipt: try await gemini.scanReceipt(imageData: image)
                }
                all.append(contentsOf: scanned)
            }
            detected = mergeDuplicates(all)
            stage = .review
        } catch let err as PantryError {
            error = err
            stage = .capturing
        } catch {
            self.error = .network(String(describing: error))
            stage = .capturing
        }
    }

    func toggle(_ item: ScannedItem) {
        guard let idx = detected.firstIndex(where: { $0.id == item.id }) else { return }
        detected[idx].include.toggle()
    }

    func commit() {
        let included = detected.filter { $0.include }
        let items: [InventoryItem] = included.map {
            InventoryItem(
                name: $0.name,
                canonicalName: $0.canonicalName,
                brandName: $0.brandName,
                foodCategory: $0.foodCategory,
                measureType: MeasureType.from($0.measureUnit),
                measureValue: $0.measureValue,
                measureUnit: $0.measureUnit,
                measureConfidence: $0.confidence,
                informationSource: .pantryScan,
                lastScannedAt: .now
            )
        }
        do {
            try inventory.upsert(items)
            Task { await inventory.pushUpsert(items) }
            stage = .done
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }

    func reset() {
        stage = .method
        captured = []
        detected = []
        error = nil
    }

    private func mergeDuplicates(_ items: [ScannedItem]) -> [ScannedItem] {
        var keyed: [String: ScannedItem] = [:]
        for item in items {
            let key = item.canonicalName.lowercased()
            if let existing = keyed[key] {
                if item.confidence > existing.confidence { keyed[key] = item }
            } else {
                keyed[key] = item
            }
        }
        return Array(keyed.values).sorted { $0.confidence > $1.confidence }
    }
}
