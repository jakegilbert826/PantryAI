import Foundation

// MARK: - Receipt scanning contract (ADR-002 v1)
//
// Replaces the per-scan Gemini VLM receipt path with on-device Vision OCR.
// A scanner turns a receipt photo into raw `ScannedItem`s (free text + best-effort
// measure); identity is *not* assigned here — `ScanViewModel.resolveDetected()`
// runs the shared canonicalization cascade (source `.receiptOCR`) afterwards,
// exactly as before. This keeps the receipt front-end swappable and testable.

protocol ReceiptScanning {
    /// Recognise line items on a receipt image. Output is pre-canonicalization:
    /// `name` is raw merchant text, `measureValue == 0` means "amount undetermined".
    func scan(imageData: Data) async throws -> [ScannedItem]
}

// MARK: - OCR line (parser input)

/// One recognised line of text plus its OCR confidence and vertical position.
/// `minY` is Vision's bottom-up normalized coordinate, used only to order lines
/// top-to-bottom before parsing; the parser itself ignores it.
struct ReceiptOCRLine: Equatable {
    let text: String
    let confidence: Double
    var minY: Double = 0
}

// MARK: - Parsed item (parser output)

/// A receipt line the parser believes is a purchasable item. Measure is in the
/// app's canonical units (g/ml) when a net weight is present, else a multipack
/// count in `.unit`, else `0` / `.unit` for "undetermined".
struct ParsedReceiptLine: Equatable {
    var name: String
    var measureValue: Double
    var measureUnit: MeasureUnit
    /// Trailing line price, when present. Carried for debugging/UX, not committed.
    var price: Double?
    var confidence: Double
}
