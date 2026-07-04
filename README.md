# Meal Prep app

Rolling 2-day batch-cooking meal planner (native iOS, SwiftUI, iOS 17+, offline).

## Structure

```
meal-prep-app/
├── MealPrep.xcodeproj/          # the iOS app project (open THIS in Xcode)
├── MealPrep/                    # SwiftUI app sources
│   ├── MealPrepApp.swift        #   @main entry
│   ├── AppModel.swift           #   @Observable model — loads DB, runs the engines
│   ├── RootView.swift           #   tab shell + notification setup/deep-link routing
│   ├── HomeView.swift           #   today's meals + cook countdown + substitute + supplements + water
│   ├── WeekView.swift           #   the variant-rotation week + tappable cook sessions
│   ├── PlanEntryView.swift      #   trainer-plan entry + schedule + notification-time settings
│   ├── SubstituteView.swift     #   the substitution flow (live engine)
│   ├── CookModeView.swift       #   merged parallel cook flow, timers, batch grams, portions
│   ├── GroceryListView.swift    #   read-only week shopping list
│   ├── MacroViews.swift         #   macro pills + delta chips
│   ├── TrainerPlanEntity.swift  #   SwiftData: the editable plan + notification times
│   ├── DailyLogEntity.swift     #   SwiftData: supplements taken + water per day
│   ├── CookSessionLogEntity.swift #  SwiftData: has-this-session-been-cooked
│   ├── ReminderScheduler.swift  #   supplement/hydration local notifications
│   ├── MealNotificationScheduler.swift # grocery/cook-session/morning/evening-nudge notifications
│   ├── NotificationRouter.swift #   UNUserNotificationCenterDelegate → SwiftUI deep links
│   ├── InventoryView.swift      #   fridge/pantry: add, decrement, expiry badges
│   ├── RestockView.swift        #   grocery checklist → fridge merge + substitution trigger
│   ├── FridgeItemEntity.swift   #   SwiftData: one row per ingredient in stock
│   ├── OnboardingView.swift     #   first-run: macros → schedule → done (3 screens)
│   ├── VariantEntity.swift      #   SwiftData: editable variant/meal/change-history
│   ├── IngredientEntity.swift   #   SwiftData: user-added ingredients
│   ├── PlanDataSeeder.swift     #   copies bundled variants.json into SwiftData once
│   ├── VariantsListView.swift   #   all variants, "+" for a new one from scratch
│   ├── VariantDetailView.swift  #   one variant's meals, active toggle, duplicate, history
│   ├── MealEditorView.swift     #   edit a meal — live day-total delta vs target
│   ├── IngredientPickerView.swift # search bundled+custom, or add a new ingredient
│   ├── VariantHistoryView.swift #   change history + restore a previous version
│   └── Assets.xcassets
└── MealPrepCore/                # pure Swift package: all the tested logic
    ├── Package.swift
    ├── Sources/MealPrepCore/    #   MacroVector, Ingredient, PortionCalculator, SubstitutionEngine,
    │   │                            DayVariant(+isActive)/CookStep, CookPlanBuilder, GroceryListBuilder,
    │   │                            NotificationPlanBuilder, VariantRotationPlanner, CookScheduler,
    │   │                            FridgeExpiry/FridgeInventory, RestockPlanner, VariantFallback…
    │   └── Resources/            #   ingredients.json (138), recipes.json (20), variants.json (V1–V4, seed only)
    ├── Sources/MealPrepDemo/    #   CLI demo of the substitution math
    ├── Tests/                   #   98 unit tests (Swift Testing)
    └── Makefile
```

The app target depends on `MealPrepCore` as a **local Swift package**, so every
calculation the UI shows comes from the same code the unit tests cover.

## Open and run the app

1. **Install an iOS Simulator runtime if you don't have one.** In Xcode:
   **Settings ▸ Components** (or **Platforms**) → download an **iOS 17+**
   simulator runtime. (CLI equivalent: `xcodebuild -downloadPlatform iOS`.)
2. **Open the project:** `open MealPrep.xcodeproj` (or File ▸ Open in Xcode).
3. In the toolbar, pick the **MealPrep** scheme and an **iPhone simulator**.
4. Press **⌘R**.

You'll land on **Today**: the trainer's actual meal plan for the day (rotating
through variants V1–V4), a cook-session countdown (tap it to open **Cook
Mode**), a substitute button, a supplement checklist, and a water counter. The
**Week** tab shows the rotation and lets you tap any of the 3 rolling cook
sessions to open Cook Mode directly. **Fridge** is your inventory (add/decrement,
expiry badges for perishable proteins past 2 days) with a **Restock** flow for
after grocery trips. **Plan** holds the trainer macro entry, schedule toggles,
and notification-time settings.

On first launch the app asks for notification permission (supplements,
hydration, grocery-ready, cook-session reminders, morning summaries, and
evening "did you cook yet?" nudges — all scheduled as local, repeating
notifications; no server).

> Signing: for the simulator no team is needed. To run on a **physical device**,
> select the target ▸ Signing & Capabilities ▸ set your Team.

## Run the logic tests / CLI demo (no Xcode UI needed)

```sh
cd MealPrepCore
make test    # 83 tests, 14 suites (Swift Testing)
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

## The cook-session time estimate

Cook Mode merges every batch-safe meal assigned to a session into one flow,
grouped by equipment station (oven / stovetop / rice cooker / assembly). Each
step is tagged `isPassive` (hands-off — baking, simmering) or active (needs
your hands). The wall-clock estimate is:

```
totalMinutes = max( Σ active step minutes,  max single passive step minutes )
```

Active steps are sequential (one person, one task at a time); passive steps
overlap with everything else and with each other (oven + rice cooker + a
simmering pot all run unattended at once). See
`MealPrepCore/Sources/MealPrepCore/CookPlan.swift`.

## Status

- **Phase 1 (core logic): done & tested.** Value types, portion/cooked-raw math,
  substitution engine, ingredient DB.
- **Phase 2: done & tested.** Trainer-plan model + per-meal split, recipe
  library, `CookScheduler` (rolling 2-day sessions with the gym-Thursday shift),
  `WeeklyPlanGenerator` (protein-anchored scaling, deterministic seed).
- **Phase 3: done & tested.** Imported the real "Oana 1900" trainer plan:
  ingredient DB merged with trainer/Lidl values (138 items), 4 day-variants
  (V1–V4) rotating so meals repeat ≤ every 4 days, chicken↔turkey equal-protein
  swap, husband multiplier that skips piece items, supplement + hydration
  reminders, and now:
  - **Fridge/pantry inventory** (`InventoryView`) — add ingredients with
    quantity, tap to decrement, swipe to delete, "do not eat" badge for
    perishable proteins past the trainer's 2-day rule.
  - **Restock flow** (`RestockView`) — after shopping, check off what you
    found (defaults to checked, so you only touch the exceptions); anything
    left unchecked immediately shows which meals it affects with a
    "Substitute →" button, and — matching the seed doc's fallback rule — a
    "switch the whole day to variant X" suggestion when a different variant
    is a meaningfully better fit for what you actually have.
  - Fridge-aware substitution: `SubstituteView` now has a "Replace with
    something I have" toggle that searches fresh (non-expired) fridge stock
    instead of the same-food-group default.
  - Cross-phase integration: Cook Mode's "mark as cooked" now decrements the
    fridge by exactly the batch grams that session used.
- **Phase 4: done & tested.** Notifications + Cook Mode:
  - **Cook Mode** — merged parallel step flow per session (grouped by oven/
    stovetop/rice cooker/assembly), a built-in per-step countdown timer, total
    raw grams to cook (2 days × 2 people), per-container per-person portioning,
    and a "mark session as cooked" toggle.
  - **Notifications** — grocery-ready (Saturday, with a real item count from a
    lightweight week-level aggregator — see caveat below), cook-session
    reminders that deep-link straight into Cook Mode, a morning meal summary,
    and an evening "have you cooked yet?" nudge that gets locally cancelled the
    moment you mark a session cooked. All times except which weekday each
    fires on are adjustable in **Plan ▸ Notification times**.
- **Phase 5: done.** Polish:
  - **Onboarding** (`OnboardingView`) — exactly 3 screens (macros → schedule →
    done) on first launch, pre-filled with sensible defaults so a tired user
    can just tap through; every field stays editable later in Plan. Replaces
    the old silent auto-seeded default plan.
  - **Empty states** — every screen that can legitimately have nothing to show
    (grocery list, restock, cook mode, week, home) now uses a friendly
    `ContentUnavailableView` instead of a bare fallback string.
  - **Dynamic Type** — `MacroSummary`/`DeltaChips` switched from a fixed
    4-across `HStack` to an adaptive grid that reflows to fewer columns at
    accessibility text sizes instead of clipping; numeric entry fields got
    `.minimumScaleFactor` as a safety net.
  - **Dark mode** — verified live (Home, a substitution sheet); works
    automatically since every view already used semantic system colors.
- **Phase 6: done.** Plan editor — the variants/meals/ingredient database moved
  from read-only bundled JSON into SwiftData (seeded once on first launch by
  `PlanDataSeeder`, then authoritative), making the whole plan editable:
  - **Edit a meal** (`MealEditorView`) — rename, retag batch-safe/fresh-only,
    add/remove/re-gram ingredients (stepper, live), with a **live day-total vs
    target banner** for both Her and Husband (propagated via his multiplier),
    colour-coded green/orange/red at ±5%/±10%/beyond.
  - **Create variants** — duplicate an existing one as a starting point, or
    build one from scratch (`VariantsListView`'s "+"). The rotation now
    supports any number of variants and only cycles through **active** ones
    (`DayVariant.isActive`, filtered in `VariantRotationPlanner`).
  - **Retire, don't delete** — an inactive variant drops out of the rotation
    (and out of the fridge-fit fallback suggestion) but its data and history
    stay intact.
  - **Edit macro targets with a drift warning** — changing daily kcal/protein/
    carbs/fat in Plan now live-lists which active variants fall outside ±5% of
    the new target, computed from the same `MacroDelta` the substitution engine
    uses.
  - **Add new ingredients** inline from the meal editor's ingredient picker —
    name, category, per-100g macros, substitution group; IDs are auto-slugged
    and de-duplicated against the bundled catalogue.
  - **Change history & restore** (`VariantHistoryView`) — every edit snapshots
    the variant's prior state; tapping a past entry restores it (and that
    restore is itself recorded, so it can be undone).
  - **Already-cooked weeks are protected** — marking a cook session as cooked
    freezes exactly what was cooked (`CookSessionLogEntity.snapshotData`), so
    editing a variant afterward can't rewrite that history. Not-yet-cooked
    weeks reflect edits immediately (useful before you've shopped/cooked).
- **98 passing tests** across all phases' core logic.

### Known caveats / deliberate scope calls

- The standing **grocery list** (`GroceryListView`, and the Saturday notification)
  is still "everything the week needs" pre-shop, not fridge-subtracted — only
  the **Restock** flow (post-shop) is fridge-aware.
- **Evening nudges** are pre-scheduled weekly-repeating local notifications, not
  dynamically re-evaluated at delivery time (iOS local notifications can't check
  live app state without a notification service extension). The app cancels the
  specific pending nudge the moment you mark a session cooked in Cook Mode —
  but if you never open the app, it'll still fire even after you cooked
  elsewhere/manually.
- **Cook-session reminder times and supplement/hydration times** use the
  trainer's defaults and aren't yet exposed as adjustable Settings controls
  (only grocery/morning-summary/evening-nudge times are); the underlying
  `TimeOfDay` plumbing supports it, it's just not wired into a picker yet.
- The **variant rotation doesn't optimize cook-session time balance** — pairing
  is a sequential cycle over however many variants are active, so some week
  configurations land a heavier session than others (still verified to fit
  comfortably under an hour with the current V1–V4 set, but this isn't a
  general guarantee for arbitrary user-created variants).
- **No deleting a variant or a meal outright** — only deactivate (variants) is
  supported, matching "history stays intact." Removing a whole meal from a
  variant (as opposed to editing its ingredients) isn't wired up either; not
  explicitly requested, and easy to add the same way "Add meal" works.
- **No dedicated screen for managing custom ingredients** — they're added
  inline from the meal editor's ingredient picker; there's no top-level list to
  review/edit/remove ones you've already added.

### Phase 2 generator notes (legacy `WeeklyPlanGenerator`, superseded by variants for the trainer's actual plan)

- Recipes are scaled to hit each meal's **protein** target exactly; the recipe
  whose ratio keeps **kcal** closest is chosen, with a variety penalty.
- **Sunday is the no-cook "tired day"** — this keeps every cook session at ≤2
  days, honouring the "never prep more than 2 days" rule.
- Husband-compromise meals are reserved for **Wednesday + Saturday dinners**.
