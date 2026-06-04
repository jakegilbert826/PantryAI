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
            let item = InventoryItem(
                name: scanned.name,
                canonicalName: scanned.canonicalName,
                brandName: scanned.brandName,
                foodCategory: scanned.foodCategory,
                measureType: MeasureType.from(scanned.measureUnit),
                measureValue: scanned.measureValue,
                measureUnit: scanned.measureUnit,
                measureConfidence: scanned.confidence,
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

    /// Seed container metadata and the display lens from the remote
    /// food_reference table, only filling fields the scan didn't determine.
    /// Falls back to a heuristic when no reference row exists (offline / unknown).
    private func applyReferenceDefaults(to item: InventoryItem) async {
        guard let ref = await FoodReferenceService.shared.lookup(canonicalName: item.canonicalName) else {
            item.preferredUnit = InventoryItem.inferPreferredUnit(
                containerType: item.containerType,
                measureType: item.measureType
            )
            item.stepperType = Self.defaultStepperType(for: item.measureType)
            return
        }
        item.preferredUnit = ref.defaultPreferredUnit
        item.stepperType = ref.stepperType
        item.packagingCategory = ref.defaultPackagingCategory
        item.storageLocation = ref.defaultStorageLocation
        if item.containerType == nil { item.containerType = ref.defaultContainerType }
        if item.containerNominalSize == nil { item.containerNominalSize = ref.defaultContainerNominalSize }
        if item.containerNominalUnit == nil { item.containerNominalUnit = ref.defaultContainerNominalUnit }
        if item.decayRateOverride == nil { item.decayRateOverride = ref.decayRateDays }
    }

    private static func defaultStepperType(for measureType: MeasureType) -> StepperType {
        switch measureType {
        case .count, .bunch:   return .count
        case .weight, .volume: return .weightVolume
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
