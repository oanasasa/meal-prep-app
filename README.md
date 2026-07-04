# Meal Prep app

Rolling 2-day batch-cooking meal planner (native iOS, SwiftUI, iOS 17+, offline).

## Structure

```
meal-prep-app/
├── MealPrep.xcodeproj/          # the iOS app project (open THIS in Xcode)
├── MealPrep/                    # SwiftUI app sources
│   ├── MealPrepApp.swift        #   @main entry
│   ├── AppModel.swift           #   @Observable model — loads DB, runs the engine
│   ├── SampleMeal.swift         #   today's demo meals
│   ├── HomeView.swift           #   home: today's meals + cook countdown + substitute
│   ├── SubstituteView.swift     #   the core substitution flow (live engine)
│   ├── MacroViews.swift         #   macro pills + delta chips
│   └── Assets.xcassets
└── MealPrepCore/                # pure Swift package: all the tested logic
    ├── Package.swift
    ├── Sources/MealPrepCore/    #   MacroVector, Ingredient, PortionCalculator,
    │   └── Resources/ingredients.json   #   SubstitutionEngine, 122-item DB
    ├── Sources/MealPrepDemo/    #   CLI demo of the substitution math
    ├── Tests/                   #   27 unit tests (Swift Testing)
    └── Makefile
```

The app target depends on `MealPrepCore` as a **local Swift package**, so every
calculation the UI shows comes from the same code the unit tests cover.

## Open and run the app

1. **Install an iOS Simulator runtime if you don't have one.** This machine
   currently has none, which is why a headless build can't boot a device.
   In Xcode: **Settings ▸ Components** (or **Platforms**) → download an **iOS 17+
   simulator runtime**. (CLI equivalent: `xcodebuild -downloadPlatform iOS`.)
2. **Open the project:** `open MealPrep.xcodeproj` (or File ▸ Open in Xcode).
3. In the toolbar, pick the **MealPrep** scheme and an **iPhone simulator**
   (e.g. iPhone 16).
4. Press **⌘R**.

You'll land on the **Today** screen: two meals with live macros and a
"Something's missing → substitute" button. Tap a meal (or the button), pick the
ingredient the store didn't have, and the real engine lists whole-food swaps
re-gram'd to hold the meal within ±5%, with signed delta chips.

> Signing: for the simulator no team is needed. To run on a **physical device**,
> select the target ▸ Signing & Capabilities ▸ set your Team (the bundle id is
> `com.mealprep.MealPrep` — change if it collides).

## Run the logic tests / CLI demo (no Xcode UI needed)

```sh
cd MealPrepCore
make test    # 27 tests, 4 suites (Swift Testing)
make demo    # prints the ranked substitution example against the bundled DB
```

(The `Makefile` adds a framework search path only needed on Command-Line-Tools-
only setups; under full Xcode, plain `swift test` works too.)

## The substitution math

A meal is ingredient lines summing to a per-meal **target** `T`. When one
ingredient is missing we hold the rest fixed (remainder `R`) and solve for the
grams of a substitute so the meal returns to target:

```
N = T − R                         (what the substitute must supply)
a = v / 100                       (substitute macros per gram)
minimise Σ wᵢ(aᵢ·g − Nᵢ)²   ⇒   g* = Σ wᵢaᵢNᵢ / Σ wᵢaᵢ²   (clamped ≥ 0)
```

Weights `wᵢ = priorityᵢ / targetᵢ²` make the fit scale-invariant with double
weight on protein; kcal is checked against ±5% but excluded from the fit (it's a
linear function of P/C/F). Candidates are ranked in-tolerance-first, then by RMS
fractional error on the enforced macros (kcal + protein). Ultra-processed items
are never suggested. Full derivation: `MealPrepCore/Sources/MealPrepCore/Substitution.swift`.

## Status

- **Phase 1 (core logic): done & tested.** Value types, portion/cooked-raw math,
  substitution engine, 122-ingredient DB.
- **Phase 2: done & tested.** Trainer-plan model + per-meal split, 20-recipe
  library, `CookScheduler` (rolling 2-day sessions with the gym-Thursday shift),
  `WeeklyPlanGenerator` (protein-anchored recipe scaling, batch-safe/tired-day/
  husband-compromise rules, deterministic seed). **48 passing tests.**
- **App: builds & runs on the iOS 17+ simulator** with SwiftData persistence.
  Three tabs:
  - **Today** — today's meals with live macros, next cook-session countdown,
    one-tap substitute.
  - **Week** — the generated week grouped by day, plus the rolling cook-session
    summary (which session cooks which days).
  - **Plan** — manual trainer-plan entry (daily kcal + macros), meals/day,
    Thursday-gym toggle, husband multiplier, "regenerate week".
- **Phase 3 (partial): trainer seed import — done & tested.** Imported the real
  "Oana 1900" plan:
  - Ingredient DB merged with the trainer/Lidl values (now 138 items; fixed a few
    Phase-1 values that were cooked, not raw).
  - **4 day-variants (V1–V4)** as `variants.json` — each a full day of 4 meals,
    tagged batch-safe vs fresh-only per the trainer's rules.
  - `VariantRotationPlanner` rotates V1→V4 across the week (meals repeat ≤ every
    4 days) and ties batch-safe meals to the rolling cook sessions.
  - chicken↔turkey **equal-protein 1:1 swap** helper; husband multiplier that
    **skips piece items** (pudding/fruit stay 1 for both).
  - **Supplement + hydration reminders** (`Reminders`) → local notifications
    (`ReminderScheduler`), creatine switching gym-day vs rest-day times.
  - App: Today/Week now show the variant plan (raw-weight labels); Home has a
    **supplement checklist** ("taken today") + **water counter**, persisted in a
    SwiftData `DailyLogEntity`. **65 passing tests.**
- **Still to do in Phase 3:** fridge/pantry inventory, grocery list, restock flow
  (wiring the substitution engine + the "switch the whole day to a variant that's
  in the fridge" fallback).

### Phase 2 generator notes

- Recipes are scaled to hit each meal's **protein** target exactly (a macro
  plan's anchor); the recipe whose ratio keeps **kcal** closest is chosen, with a
  variety penalty so the week doesn't repeat.
- **Sunday is the no-cook "tired day"** (assembly meals only) — this keeps every
  cook session at ≤2 days, honouring the "never prep more than 2 days" rule.
- Husband-compromise meals are reserved for **Wednesday + Saturday dinners**
  (~2×/week) so both eat the same meal without him ordering out.
