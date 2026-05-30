import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class ScanViewModel {
    enum Stage {
        case capturing
        case analysing
        case review
        case done
    }

    var stage: Stage = .capturing
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

    func add(photo image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        captured.append(data)
    }

    func analyse() async {
        guard !captured.isEmpty else { return }
        stage = .analysing
        do {
            var all: [ScannedItem] = []
            for image in captured {
                let scanned = try await gemini.scanInventory(imageData: image)
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
                category: $0.category,
                brand: $0.brand,
                quantity: $0.quantity,
                unit: $0.unit,
                lastScanConfidence: $0.confidence,
                lastScanDate: .now
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
        stage = .capturing
        captured = []
        detected = []
        error = nil
    }

    /// If Gemini surfaces the same item across multiple frames, keep the
    /// highest-confidence read rather than double-counting.
    private func mergeDuplicates(_ items: [ScannedItem]) -> [ScannedItem] {
        var keyed: [String: ScannedItem] = [:]
        for item in items {
            let key = item.name.lowercased()
            if let existing = keyed[key] {
                if item.confidence > existing.confidence {
                    keyed[key] = item
                }
            } else {
                keyed[key] = item
            }
        }
        return Array(keyed.values).sorted { $0.confidence > $1.confidence }
    }
}
