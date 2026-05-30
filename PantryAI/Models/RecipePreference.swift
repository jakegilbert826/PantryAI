import Foundation
import SwiftData

@Model
final class RecipePreference {
    @Attribute(.unique) var id: UUID
    var recipeName: String
    var imageURL: String?
    var liked: Bool
    var recordedAt: Date

    init(id: UUID = UUID(), recipeName: String, imageURL: String? = nil, liked: Bool, recordedAt: Date = .now) {
        self.id = id
        self.recipeName = recipeName
        self.imageURL = imageURL
        self.liked = liked
        self.recordedAt = recordedAt
    }
}

/// Stripped-down struct used for prompting Gemini — keeps the SwiftData class
/// out of value-type boundaries.
struct RecipePreferenceSnapshot: Codable, Hashable {
    let recipeName: String
    let liked: Bool
}
