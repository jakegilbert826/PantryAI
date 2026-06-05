import Foundation

struct FoodReference: Codable {
    let id: UUID
    let canonicalName: String
    let displayName: String
    let pluralName: String?
    let defaultMeasureType: MeasureType
    let defaultMeasureUnit: MeasureUnit
    let defaultStorageLocation: StorageLocation
    let defaultPackagingCategory: PackagingCategory
    let decayRateDays: Double
    let decayRateOpenedDays: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case displayName = "display_name"
        case pluralName = "plural_name"
        case defaultMeasureType = "default_measure_type"
        case defaultMeasureUnit = "default_measure_unit"
        case defaultStorageLocation = "default_storage_location"
        case defaultPackagingCategory = "default_packaging_category"
        case decayRateDays = "decay_rate_days"
        case decayRateOpenedDays = "decay_rate_opened_days"
    }
}
