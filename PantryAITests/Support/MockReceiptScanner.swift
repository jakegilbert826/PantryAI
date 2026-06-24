import Foundation
@testable import PantryAI

/// Test double for `ReceiptScanning`. Returns canned items (or throws) so the
/// receipt path can be exercised without Vision or an image.
final class MockReceiptScanner: ReceiptScanning, @unchecked Sendable {
    var result: [ScannedItem] = []
    var error: Error?
    private(set) var callCount = 0

    func scan(imageData: Data) async throws -> [ScannedItem] {
        callCount += 1
        if let error { throw error }
        return result
    }
}
