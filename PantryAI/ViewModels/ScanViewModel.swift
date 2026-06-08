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
        Task { await commit(included) }
    }

    private func commit(_ included: [ScannedItem]) async {
        var items: [InventoryItem] = []
        for scanned in included {
            // A scanned amount of 0 means "amount not determined", not empty.
            let quantity: Double? = scanned.measureValue > 0 ? scanned.measureValue : nil
            let cv = SourceReliability.cv(for: .scan, kind: .stock,
                                          assumedSize: false, measurementConfidence: scanned.confidence)
            let item = InventoryItem(
                name: scanned.name,
                canonicalName: scanned.canonicalName,
                brandName: scanned.brandName,
                foodCategory: scanned.foodCategory,
                measureUnit: scanned.measureUnit,
                quantity: quantity,
                quantityVariance: quantity.map { SourceReliability.measurementVariance(quantity: $0, cv: cv) },
                informationSource: .pantryScan,
                lastScannedAt: .now
            )
            await applyReferenceDefaults(to: item)
            items.append(item)
        }
        do {
            try inventory.upsert(items)
            stage = .done
            await inventory.pushUpsert(items)
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }

    private func applyReferenceDefaults(to item: InventoryItem) async {
        guard let ref = await FoodReferenceService.shared.lookup(canonicalName: item.canonicalName) else { return }
        item.packagingCategory = ref.defaultPackagingCategory
        item.storageLocation = ref.defaultStorageLocation
        // Reference half-lives override the category cold-start priors.
        item.halfLifeDays = ref.halfLifeDays
        if let opened = ref.openedHalfLifeDays { item.openHalfLifeDays = opened }
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
