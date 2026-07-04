import Foundation

/// One instruction within a meal's prep, tagged by which "station" it runs on
/// (oven / stovetop / rice cooker / no-cook) so Cook Mode can merge several
/// meals into one parallelized flow — "while the chicken bakes, boil the rice".
/// `isPassive` marks hands-off time (baking, simmering) vs active attention.
public struct CookStep: Codable, Equatable, Sendable {
    public let text: String
    public let minutes: Int
    public let method: CookMethod
    public let isPassive: Bool

    public init(text: String, minutes: Int, method: CookMethod, isPassive: Bool = false) {
        self.text = text
        self.minutes = minutes
        self.method = method
        self.isPassive = isPassive
    }

    private enum CodingKeys: String, CodingKey { case text, minutes, method, isPassive }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        minutes = try c.decode(Int.self, forKey: .minutes)
        method = try c.decode(CookMethod.self, forKey: .method)
        isPassive = try c.decodeIfPresent(Bool.self, forKey: .isPassive) ?? false
    }
}

/// One meal inside a trainer day-variant. Grams are RAW "Her" weights (the
/// trainer's rule: all quantities raw unless stated). `batchSafe` meals are
/// cooked once for two days; `freshOnly` meals are assembled in <10 min.
public struct MealTemplate: Codable, Identifiable, Equatable, Sendable {
    public let id: String          // e.g. "v1-m2"
    public let name: String
    public let mealType: MealType
    public let lines: [RecipeLine]
    public let batchSafe: Bool
    public let freshOnly: Bool
    /// Structured, timed steps for Cook Mode. Empty for meals that don't need
    /// a cook flow (fresh-only assembly meals typically skip this).
    public let cookSteps: [CookStep]

    private enum CodingKeys: String, CodingKey {
        case id, name, mealType, lines, batchSafe, freshOnly, cookSteps
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mealType = try c.decode(MealType.self, forKey: .mealType)
        lines = try c.decode([RecipeLine].self, forKey: .lines)
        batchSafe = try c.decodeIfPresent(Bool.self, forKey: .batchSafe) ?? false
        freshOnly = try c.decodeIfPresent(Bool.self, forKey: .freshOnly) ?? false
        cookSteps = try c.decodeIfPresent([CookStep].self, forKey: .cookSteps) ?? []
    }

    public init(id: String, name: String, mealType: MealType, lines: [RecipeLine],
                batchSafe: Bool = false, freshOnly: Bool = false, cookSteps: [CookStep] = []) {
        self.id = id; self.name = name; self.mealType = mealType; self.lines = lines
        self.batchSafe = batchSafe; self.freshOnly = freshOnly; self.cookSteps = cookSteps
    }
}

/// A full day (4 meals) from the trainer's plan. Variants are day-level units —
/// meals may be reordered/combined WITHIN a variant, but never mixed across
/// variants (trainer rule 2).
public struct DayVariant: Codable, Identifiable, Equatable, Sendable {
    public let id: String          // "V1"…"V4"
    public let name: String
    public let meals: [MealTemplate]
}

/// In-memory catalogue + bundled-seed loader for the day-variants.
public struct VariantLibrary: Sendable {
    public let all: [DayVariant]
    private let byID: [String: DayVariant]

    public init(variants: [DayVariant]) {
        self.all = variants
        self.byID = Dictionary(uniqueKeysWithValues: variants.map { ($0.id, $0) })
    }

    public func variant(id: String) -> DayVariant? { byID[id] }
    public var count: Int { all.count }

    public enum LoadError: Error { case resourceNotFound, duplicateIDs([String]) }

    public static func load(from data: Data) throws -> VariantLibrary {
        let variants = try JSONDecoder().decode([DayVariant].self, from: data)
        let ids = variants.map(\.id)
        let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
        guard dupes.isEmpty else { throw LoadError.duplicateIDs(Array(dupes)) }
        return VariantLibrary(variants: variants)
    }

    public static func loadBundled() throws -> VariantLibrary { try load(from: .module) }

    public static func load(from bundle: Bundle) throws -> VariantLibrary {
        guard let url = bundle.url(forResource: "variants", withExtension: "json") else {
            throw LoadError.resourceNotFound
        }
        return try load(from: Data(contentsOf: url))
    }
}
