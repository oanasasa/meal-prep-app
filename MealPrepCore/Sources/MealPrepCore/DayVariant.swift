import Foundation

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
    public let steps: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, mealType, lines, batchSafe, freshOnly, steps
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mealType = try c.decode(MealType.self, forKey: .mealType)
        lines = try c.decode([RecipeLine].self, forKey: .lines)
        batchSafe = try c.decodeIfPresent(Bool.self, forKey: .batchSafe) ?? false
        freshOnly = try c.decodeIfPresent(Bool.self, forKey: .freshOnly) ?? false
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
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
