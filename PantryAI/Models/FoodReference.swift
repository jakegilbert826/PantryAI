import Foundation

/// v3 `food_reference` row (design §7.1). The Supabase migration has been applied,
/// so `CodingKeys` map straight to the v3 column names (PK = `canonical_name`;
/// `half_life_days` / `opened_half_life_days`; `default_container_size`,
/// `default_input_mode`, `substitution_group`). `measure_type` is derived in-app
/// from the canonical unit and never stored remotely.
struct FoodReference: Decodable {
    let canonicalName: String
    let displayName: String
    let pluralName: String?
    let defaultMeasureUnit: MeasureUnit
    let defaultStorageLocation: StorageLocation
    let defaultPackagingCategory: PackagingCategory
    let defaultContainerType: ContainerType?
    let defaultContainerSize: Double?      // canonical units; drives estimates
    let halfLifeDays: Double?              // sealed; NULL = infinite (shelf-stable)
    let openedHalfLifeDays: Double?        // applies once opened
    let defaultInputMode: InputMode
    let substitutionGroup: String?

    /// `measure_type` is derived from the canonical unit, never stored remotely.
    var defaultMeasureType: MeasureType { MeasureType.from(defaultMeasureUnit) }

    enum CodingKeys: String, CodingKey {
        case canonicalName = "canonical_name"
        case displayName = "display_name"
        case pluralName = "plural_name"
        case defaultMeasureUnit = "default_measure_unit"
        case defaultStorageLocation = "default_storage_location"
        case defaultPackagingCategory = "default_packaging_category"
        case defaultContainerType = "default_container_type"
        case defaultContainerSize = "default_container_size"
        case halfLifeDays = "half_life_days"
        case openedHalfLifeDays = "opened_half_life_days"
        case defaultInputMode = "default_input_mode"
        case substitutionGroup = "substitution_group"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canonicalName = try c.decode(String.self, forKey: .canonicalName)
        displayName = try c.decode(String.self, forKey: .displayName)
        pluralName = try c.decodeIfPresent(String.self, forKey: .pluralName)
        defaultMeasureUnit = try c.decode(MeasureUnit.self, forKey: .defaultMeasureUnit)
        defaultStorageLocation = try c.decode(StorageLocation.self, forKey: .defaultStorageLocation)
        defaultPackagingCategory = try c.decode(PackagingCategory.self, forKey: .defaultPackagingCategory)
        defaultContainerType = try c.decodeIfPresent(ContainerType.self, forKey: .defaultContainerType)
        defaultContainerSize = try c.decodeIfPresent(Double.self, forKey: .defaultContainerSize)
        halfLifeDays = try c.decodeIfPresent(Double.self, forKey: .halfLifeDays)
        openedHalfLifeDays = try c.decodeIfPresent(Double.self, forKey: .openedHalfLifeDays)
        defaultInputMode = try c.decode(InputMode.self, forKey: .defaultInputMode)
        substitutionGroup = try c.decodeIfPresent(String.self, forKey: .substitutionGroup)
    }

    /// Memberwise initializer (the custom decoder above suppresses the synthesized one).
    init(
        canonicalName: String,
        displayName: String,
        pluralName: String? = nil,
        defaultMeasureUnit: MeasureUnit,
        defaultStorageLocation: StorageLocation,
        defaultPackagingCategory: PackagingCategory,
        defaultContainerType: ContainerType? = nil,
        defaultContainerSize: Double? = nil,
        halfLifeDays: Double? = nil,
        openedHalfLifeDays: Double? = nil,
        defaultInputMode: InputMode? = nil,
        substitutionGroup: String? = nil
    ) {
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.pluralName = pluralName
        self.defaultMeasureUnit = defaultMeasureUnit
        self.defaultStorageLocation = defaultStorageLocation
        self.defaultPackagingCategory = defaultPackagingCategory
        self.defaultContainerType = defaultContainerType
        self.defaultContainerSize = defaultContainerSize
        self.halfLifeDays = halfLifeDays
        self.openedHalfLifeDays = openedHalfLifeDays
        self.defaultInputMode = defaultInputMode ?? Self.fallbackInputMode(for: defaultMeasureUnit)
        self.substitutionGroup = substitutionGroup
    }

    private static func fallbackInputMode(for unit: MeasureUnit) -> InputMode {
        switch unit {
        case .unit, .bunch: return .count
        default:            return .weightVolume
        }
    }
}
