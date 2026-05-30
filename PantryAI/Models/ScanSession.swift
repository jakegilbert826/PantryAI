import Foundation
import SwiftData

@Model
final class ScanSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var photoCount: Int
    var itemsDetected: Int
    var itemsConfirmed: Int

    init(id: UUID = UUID(), date: Date = .now, photoCount: Int, itemsDetected: Int, itemsConfirmed: Int) {
        self.id = id
        self.date = date
        self.photoCount = photoCount
        self.itemsDetected = itemsDetected
        self.itemsConfirmed = itemsConfirmed
    }
}
