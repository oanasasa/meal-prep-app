import Foundation

/// Equipment a recipe uses. Drives cook-mode parallelisation later (oven +
/// stovetop + rice cooker running at once).
public enum CookMethod: String, Codable, CaseIterable, Sendable {
    case oven, stovetop, riceCooker, noCook
}

/// A recipe. `lines` are the base ("Her" reference) raw grams; the generator
/// scales the whole recipe to a meal's macro target. Tags gate which slots a
/// recipe is eligible for.
public struct Recipe: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let suitableMealTypes: [MealType]
    public let lines: [RecipeLine]
    public let prepMinutes: Int
    public let methods: [CookMethod]

    /// Safe to eat on day 2 (stews, baked proteins, grain bowls — no fried
    /// textures). Required for lunch/dinner on batch-cooked days.
    public let batchSafe2Days: Bool
    /// Zero-/low-cook assembly meal for the weekly "tired day" fallback.
    public let tiredDay: Bool
    /// Healthy homemade fast-food so the husband doesn't order out.
    public let husbandCompromise: Bool
    public let steps: [String]

    public var isNoCook: Bool { methods == [.noCook] || (methods.count == 1 && methods.first == .noCook) }

    // Defaulting decode so the seed JSON stays compact.
    private enum CodingKeys: String, CodingKey {
        case id, name, suitableMealTypes, lines, prepMinutes, methods
        case batchSafe2Days, tiredDay, husbandCompromise, steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        suitableMealTypes = try c.decode([MealType].self, forKey: .suitableMealTypes)
        lines = try c.decode([RecipeLine].self, forKey: .lines)
        prepMinutes = try c.decode(Int.self, forKey: .prepMinutes)
        methods = try c.decode([CookMethod].self, forKey: .methods)
        batchSafe2Days = try c.decodeIfPresent(Bool.self, forKey: .batchSafe2Days) ?? false
        tiredDay = try c.decodeIfPresent(Bool.self, forKey: .tiredDay) ?? false
        husbandCompromise = try c.decodeIfPresent(Bool.self, forKey: .husbandCompromise) ?? false
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
    }

    public init(id: String, name: String, suitableMealTypes: [MealType], lines: [RecipeLine],
                prepMinutes: Int, methods: [CookMethod], batchSafe2Days: Bool = false,
                tiredDay: Bool = false, husbandCompromise: Bool = false, steps: [String] = []) {
        self.id = id; self.name = name; self.suitableMealTypes = suitableMealTypes
        self.lines = lines; self.prepMinutes = prepMinutes; self.methods = methods
        self.batchSafe2Days = batchSafe2Days; self.tiredDay = tiredDay
        self.husbandCompromise = husbandCompromise; self.steps = steps
    }
}

/// In-memory recipe catalogue + bundled-seed loader (mirrors IngredientDatabase).
public struct RecipeLibrary: Sendable {
    public let all: [Recipe]
    private let byID: [String: Recipe]

    public init(recipes: [Recipe]) {
        self.all = recipes
        self.byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }

    public func recipe(id: String) -> Recipe? { byID[id] }

    public func recipes(for type: MealType) -> [Recipe] {
        all.filter { $0.suitableMealTypes.contains(type) }
    }

    public enum LoadError: Error { case resourceNotFound, duplicateIDs([String]) }

    public static func load(from data: Data) throws -> RecipeLibrary {
        let recipes = try JSONDecoder().decode([Recipe].self, from: data)
        let ids = recipes.map(\.id)
        let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
        guard dupes.isEmpty else { throw LoadError.duplicateIDs(Array(dupes)) }
        return RecipeLibrary(recipes: recipes)
    }

    public static func loadBundled() throws -> RecipeLibrary { try load(from: .module) }

    public static func load(from bundle: Bundle) throws -> RecipeLibrary {
        guard let url = bundle.url(forResource: "recipes", withExtension: "json") else {
            throw LoadError.resourceNotFound
        }
        return try load(from: Data(contentsOf: url))
    }
}
