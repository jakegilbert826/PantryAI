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
    /// Injected for tests; when nil the shared (network-bootstrapped) index is used.
    private let injectedCanonicalizer: CanonicalizationService?

    init(context: ModelContext,
         gemini: GeminiServiceProtocol = GeminiService(),
         canonicalizer: CanonicalizationService? = nil) {
        self.gemini = gemini
        self.injectedCanonicalizer = canonicalizer
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
            await resolveDetected()
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

    // MARK: - Canonicalization (ADR-002a)

    /// Resolve every detected item to a `food_reference` PK before review. Runs
    /// the on-device cascade (sync hot path) per item; HITL items surface in the
    /// review UI. Bootstraps the shared index if launch prefetch hasn't finished.
    private func resolveDetected() async {
        let service: CanonicalizationService?
        if let injectedCanonicalizer {
            service = injectedCanonicalizer
        } else {
            if CanonicalizationService.shared == nil { await CanonicalizationService.bootstrap() }
            service = CanonicalizationService.shared
        }
        guard let service else { return }
        let source: InflowSource = captureMode == .receipt ? .receiptOCR : .pantryScan
        for idx in detected.indices {
            let query = CanonicalizationQuery(
                source: source,
                rawText: detected[idx].name,
                brandHint: detected[idx].brandName
            )
            detected[idx].apply(service.resolve(query))
        }
    }

    /// HITL pick: lock an item to a chosen candidate and feed the correction back
    /// into the alias flywheel (local index + Supabase).
    func confirm(_ item: ScannedItem, as candidate: Candidate) {
        guard let idx = detected.firstIndex(where: { $0.id == item.id }) else { return }
        detected[idx].resolvedCanonical = candidate.canonicalName
        detected[idx].resolvedDisplayName = candidate.displayName
        detected[idx].requiresConfirmation = false
        detected[idx].matchStage = .confirmed

        let source: InflowSource = captureMode == .receipt ? .receiptOCR : .pantryScan
        if let service = injectedCanonicalizer ?? CanonicalizationService.shared {
            let entry = service.recordCorrection(rawText: item.name, source: source,
                                                 canonicalName: candidate.canonicalName)
            Task { await CanonicalAliasService.shared.pushCorrection(entry) }
        }
    }

    /// True while any *included* item still lacks a confirmed PK — commit is blocked.
    var hasUnresolvedItems: Bool {
        detected.contains { $0.include && $0.needsConfirmation }
    }

    func commit() {
        guard !hasUnresolvedItems else { return }
        let included = detected.filter { $0.include && !$0.needsConfirmation }
        Task { await commit(included) }
    }

    private func commit(_ included: [ScannedItem]) async {
        var items: [InventoryItem] = []
        for scanned in included {
            // A scanned amount of 0 means "amount not determined", not empty.
            let quantity: Double? = scanned.measureValue > 0 ? scanned.measureValue : nil
            let cv = SourceReliability.cv(for: .scan, kind: .stock,
                                          assumedSize: false, measurementConfidence: scanned.confidence)
            // Guaranteed non-nil: commit() filters out items still needing confirmation.
            let canonical = scanned.resolvedCanonical ?? scanned.name
            let item = InventoryItem(
                name: scanned.name,
                canonicalName: canonical,
                displayName: scanned.resolvedDisplayName,
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
        // Authoritative display name from food_reference (overrides the candidate's,
        // which may have been a fuzzy/HITL pick before confirmation).
        item.displayName = ref.displayName
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
        // Pre-resolution: dedup by raw name (PKs aren't assigned yet).
        var keyed: [String: ScannedItem] = [:]
        for item in items {
            let key = item.name.lowercased()
            if let existing = keyed[key] {
                if item.confidence > existing.confidence { keyed[key] = item }
            } else {
                keyed[key] = item
            }
        }
        return Array(keyed.values).sorted { $0.confidence > $1.confidence }
    }
}
