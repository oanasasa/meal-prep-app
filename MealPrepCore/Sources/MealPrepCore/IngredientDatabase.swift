import Foundation

/// In-memory index over the bundled ingredient seed. Loaded once on first launch
/// (the iOS layer will copy it into SwiftData); pure and value-typed here so the
/// engine and tests can spin one up without any app context.
public struct IngredientDatabase: Sendable {
    public let all: [Ingredient]
    private let byID: [String: Ingredient]
    private let byGroup: [SubstitutionGroup: [Ingredient]]

    public init(ingredients: [Ingredient]) {
        self.all = ingredients
        self.byID = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })
        self.byGroup = Dictionary(grouping: ingredients, by: { $0.group })
    }

    public func ingredient(id: String) -> Ingredient? { byID[id] }

    public func ingredients(in group: SubstitutionGroup) -> [Ingredient] {
        byGroup[group] ?? []
    }

    public var count: Int { all.count }

    // MARK: - Loading the bundled seed

    public enum LoadError: Error {
        case resourceNotFound
        case duplicateIDs([String])
    }

    /// Decode a seed JSON payload and validate that ids are unique.
    public static func load(from data: Data) throws -> IngredientDatabase {
        let decoder = JSONDecoder()
        let ingredients = try decoder.decode([Ingredient].self, from: data)
        let ids = ingredients.map(\.id)
        let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
        guard dupes.isEmpty else { throw LoadError.duplicateIDs(Array(dupes)) }
        return IngredientDatabase(ingredients: ingredients)
    }

    /// Load the seed bundled with the package (`Resources/ingredients.json`).
    public static func loadBundled() throws -> IngredientDatabase {
        try load(from: .module)
    }

    /// Load from an explicit bundle (the iOS app passes `.main`).
    public static func load(from bundle: Bundle) throws -> IngredientDatabase {
        guard let url = bundle.url(forResource: "ingredients", withExtension: "json") else {
            throw LoadError.resourceNotFound
        }
        return try load(from: Data(contentsOf: url))
    }
}
