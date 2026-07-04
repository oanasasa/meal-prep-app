import Foundation

/// How an ingredient is measured/bought — drives grocery aggregation and the
/// inventory decrement UI later.
public enum MeasureUnit: String, Codable, Sendable {
    case grams
    case piece   // eggs, tortillas, fruit — has `gramsPerPiece`
    case milliliter
}

/// Store-section grouping. Used to group the grocery list; NOT used for
/// substitution (that's `SubstitutionGroup`).
public enum StoreSection: String, Codable, CaseIterable, Sendable {
    case produce
    case meatAndSeafood
    case dairyAndEggs
    case grainsAndBakery
    case pantry          // oils, canned goods, legumes, condiments
    case frozen
    case nutsAndSeeds
}

/// Functional macro role. Substitutions are only offered *within* the same
/// group by default, guaranteeing the swap plays the same role in the meal
/// (a starch for a starch, a lean protein for a lean protein).
public enum SubstitutionGroup: String, Codable, CaseIterable, Sendable {
    case leanProtein      // chicken, turkey, cod, shrimp, pork loin…
    case oilyFish         // salmon, mackerel, sardines, trout
    case redMeat          // beef, lamb, bison
    case eggs
    case dairyProtein     // greek yogurt, skyr, cottage cheese, quark
    case cheese
    case plantProtein     // tofu, tempeh, edamame, seitan
    case legume           // lentils, chickpeas, beans (protein + carb)
    case starchyCarb      // rice, potato, quinoa, pasta, oats, bread
    case healthyFat       // olive oil, avocado, nuts, seeds, nut butters
    case vegetable
    case fruit
    case condiment        // low-macro flavour items; not a substitution source
}

/// A single food in the bundled nutrition database. Value type, `Codable` so it
/// loads straight from the seed JSON. The iOS layer will mirror this into a
/// SwiftData `@Model` in a later phase, but all math runs on this pure struct.
public struct Ingredient: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// Stable kebab-case slug, e.g. "chicken-breast". Used as the foreign key
    /// from recipes and fridge items.
    public let id: String
    public let name: String
    public let section: StoreSection
    public let group: SubstitutionGroup

    /// Nutrition per 100 g (or per 100 g of the raw/as-purchased form for foods
    /// that change weight on cooking — see `cookedYieldFactor`).
    public let per100g: MacroVector

    /// cooked weight ÷ raw weight. Rice/pasta absorb water (>1); meats lose
    /// water (<1); most produce ≈ 1. Macros are always computed on the RAW
    /// grams a recipe specifies (standard trainer practice); this only converts
    /// to the cooked container weight shown in cook mode.
    public let cookedYieldFactor: Double

    /// Whole-food flag. The substitution engine never *suggests* an ingredient
    /// with `isWholeFood == false`, satisfying "no ultra-processed replacements".
    public let isWholeFood: Bool

    public let unit: MeasureUnit
    /// Required when `unit == .piece`; lets us convert grams ⇄ pieces.
    public let gramsPerPiece: Double?

    /// Proteins and cooked dishes get the strict 2-day expiry rule; shelf-stable
    /// pantry items don't. Drives the "do not eat" flag in the fridge later.
    public let isPerishableProtein: Bool

    public init(id: String,
                name: String,
                section: StoreSection,
                group: SubstitutionGroup,
                per100g: MacroVector,
                cookedYieldFactor: Double = 1.0,
                isWholeFood: Bool = true,
                unit: MeasureUnit = .grams,
                gramsPerPiece: Double? = nil,
                isPerishableProtein: Bool = false) {
        self.id = id
        self.name = name
        self.section = section
        self.group = group
        self.per100g = per100g
        self.cookedYieldFactor = cookedYieldFactor
        self.isWholeFood = isWholeFood
        self.unit = unit
        self.gramsPerPiece = gramsPerPiece
        self.isPerishableProtein = isPerishableProtein
    }

    // Custom decoding so the seed JSON can omit the common defaults
    // (yield 1.0, whole-food true, grams, not perishable) and stay compact.
    private enum CodingKeys: String, CodingKey {
        case id, name, section, group, per100g
        case cookedYieldFactor, isWholeFood, unit, gramsPerPiece, isPerishableProtein
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        section = try c.decode(StoreSection.self, forKey: .section)
        group = try c.decode(SubstitutionGroup.self, forKey: .group)
        per100g = try c.decode(MacroVector.self, forKey: .per100g)
        cookedYieldFactor = try c.decodeIfPresent(Double.self, forKey: .cookedYieldFactor) ?? 1.0
        isWholeFood = try c.decodeIfPresent(Bool.self, forKey: .isWholeFood) ?? true
        unit = try c.decodeIfPresent(MeasureUnit.self, forKey: .unit) ?? .grams
        gramsPerPiece = try c.decodeIfPresent(Double.self, forKey: .gramsPerPiece)
        isPerishableProtein = try c.decodeIfPresent(Bool.self, forKey: .isPerishableProtein) ?? false
    }

    /// Macros contributed by `grams` of this ingredient (raw weight).
    public func macros(forGrams grams: Double) -> MacroVector {
        per100g * (grams / 100.0)
    }

    /// Cooked/served weight for a given raw amount.
    public func cookedGrams(forRawGrams grams: Double) -> Double {
        grams * cookedYieldFactor
    }
}
