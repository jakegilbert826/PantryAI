import Foundation

/// v3 `food_reference` row. Property names follow the v3 design (§7.1) but the
/// `CodingKeys` / custom decoder still map to the **v0 remote columns** because
/// the Supabase migration has not been run yet (design §11.1):
///   - `half_life_days`        ← `decay_rate_days`
///   - `opened_half_life_days` ← `decay_rate_opened_days`
///   - `id`, `default_measure_type` columns are simply ignored.
/// New v2 columns (`default_container_size`, `default_input_mode`,
/// `substitution_group`, …) are decoded with `decodeIfPresent` so the fetch does
/// not break before the migration lands.
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
        // v0 remote still names these decay_rate_*; remap until migration §7.1.
        case halfLifeDays = "decay_rate_days"
        case openedHalfLifeDays = "decay_rate_opened_days"
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
        // Not present on v0 remote yet → fall back to a unit-derived default.
        if let mode = try c.decodeIfPresent(InputMode.self, forKey: .defaultInputMode) {
            defaultInputMode = mode
        } else {
            defaultInputMode = Self.fallbackInputMode(for: defaultMeasureUnit)
        }
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
