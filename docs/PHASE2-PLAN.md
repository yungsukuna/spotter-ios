# Spotter — Phase 2 implementation plan (8 features)

**Status: implemented in PR #2 (CI green). The recommended answer was taken for every decision below. Nothing has been checked on a device yet.**

Grounded in the code as of `934a986` on `main`. Paths are relative to the repo root.

## Summary

Several of these features need no schema change because the models already cover them:
- `BodyMeasurement` covers body weight.
- `CardioEntry` covers cardio.
- `SetEntry.rpe` covers RPE.
- `Exercise.notes` and `WorkoutExercise.notes` cover exercise notes.
- `Exercise.isCardio` and the 8 seeded cardio exercises in `ExerciseLibrary.swift` are already there.

Only four things change the schema: saved meals, per-exercise rest time, the goal calculator's inputs, and two small display preferences. All four are additive, so SwiftData's automatic lightweight migration handles them. **Nothing has ever run on a device, so there is no user data to migrate yet.** The schema step should land before Kai starts using the app daily.

### Recommended build order

| # | Step | Size | Why here |
|---|---|---|---|
| 0 | Prerequisites (see "Must change first") | S | CI green; the Workouts bug fixes (PR #1) merged |
| 1 | **Consolidated schema step** | S | Every later feature depends on it. It's cheapest before any real data exists, and the backup format v1 should cover the final field set. |
| 2 | Body weight + trend | M | Top-priority item in the roadmap. The goal calculator and the cardio calorie estimate both need a current weight. |
| 3 | Backup / export / import | M–L | Insurance before daily use. Every later schema change will also need to update it. |
| 4 | Faster food logging (quick add → copy meal → saved meals) | M | Biggest daily-friction win. Mostly Nutrition-folder work. |
| 5 | Goal calculator | S–M | Needs step 2's trend weight. Pure maths, very testable. |
| 6 | Streaks + weekly summary | S–M | Pure functions over day keys. These are also the Phase 3 "check-in" signal. |
| 7 | Cardio logging | M | Needs step 2 for the calorie estimate. Also fixes an existing bug (cardio exercises get weight×reps rows). |
| 8 | RepCount extras (notes → rest override → RPE → plate calc → warm-ups) | M–L | Goes after the Workouts fixes to avoid conflicts in `ActiveWorkoutView` and `SetRowView`. |
| 9 | Live Activity for the rest timer | M | Needs the one-time `project.yml` change and the rest-timer ownership fix. |
| 10 | Home Screen widget | M | Same extension target, plus an App Group. |

---

## Decisions Kai needs to make (recommendation in bold)

1. **Can a new `@Model` be added for saved meals?** The alternative is a Codable array on `UserSettings`, like `waterPresets`. → **Yes, add a new `SavedMeal` model.** Each row keeps its own UUID for export and sync, it avoids a growing blob on the singleton (CloudKit conflicts are per record), and coach-assigned meals in Phase 3 need row identity.
2. **Should the goal calculator store its inputs (height, birth year, sex, activity, goal)?** The alternative is a one-shot calculator that only writes the targets. → **Store them as optionals on `UserSettings`.** Then "recalculate" is one tap as the weight trend moves. Treat these fields as sensitive health data for Phase 3.
3. **How should import work?** → **Merge only: insert records whose UUID is missing, never overwrite existing ones.** On a fresh install, merge is the same as a full restore. Skip "replace all" in v1, because it's a destructive, irreversible action.
4. **Do cardio calories count toward the calorie budget?** → **No, not by default.** Show them as "active kcal" on the Workout card only. MET estimates run high, and eating them back is the classic tracking mistake. An opt-in setting can come later.
5. **Does a cardio-only day count as "trained" in the weekly strip and streaks?** → **Yes.** That's the honest check-in signal for Phase 3.
6. **What counts as a "day logged"?** → **At least one `DiaryEntry` that day**, and quick-add entries count. Water and workouts get their own separate stats. Today is "pending", not broken, until the day ends.
7. **Weekly summary window?** → **Calendar week, using the locale's `Calendar.firstWeekday`.** In NZ that means Monday. The existing strip stays a rolling 7 days.
8. **Multiple weigh-ins on one day?** → **Use the daily mean** as the input to the trend.
9. **Smoothing?** → **Time-aware EWMA with α = 0.1 per day** (Hacker's Diet style, details below).
10. **Plate inventory in v1?** → **Fixed standard sets per unit, plus a stored bar weight.** kg: 25/20/15/10/5/2.5/1.25; lb: 45/35/25/10/5/2.5. Bar: 20 kg or 45 lb unless overridden.
11. **RPE or RIR?** → **Store RPE only** (it already exists). A display setting chooses Off / RPE / RIR, with RIR = 10 − RPE. **Default is Off**, which keeps the set row as uncluttered as RepCount's.
12. **Widget data path: shared SwiftData store, or a JSON snapshot?** → **Snapshot in App Group `UserDefaults`, and don't move the store.** Only move the store if you want an interactive "log water" widget. If you do, decide **now**, before any real data exists (see Feature 8).
13. **Apple developer account type.** Free personal teams may not support the App Groups capability (please check; I'm not certain). If they don't, the Home Screen widget needs the paid account. The Live Activity does **not** need an App Group.
14. **Add the missing inverse `Exercise.cardioEntries` in the schema step?** → **Yes.** CloudKit requires every relationship to have an inverse, and `CardioEntry.exercise` (in `Spotter/Core/Models/Exercise.swift`) currently has none.

---

## Must change first (current code)

1. **CI must be green**, including PR #1.
2. **The Workouts fixes (PR #1) must merge first.** Those are the `RestTimerBar`/`ActiveWorkoutView` finish feedback, the `SystemRestTimerNotifier` skip race, and passing `oneRepMaxFormula` into stats. Features 6 and 8 touch the same files, so sequence them after the fixes and rebase.
3. **Who owns the rest timer.** `ActiveWorkoutView` holds `@State private var restTimer = RestTimerController()`. Navigating back to `WorkoutsHomeView` mid-rest destroys the controller, which leaves the notification (and later the Live Activity) orphaned. Before the Live Activity step, move the controller to a longer-lived owner. The recommended owner is a `@State` in `WorkoutsHomeView`, injected into `ActiveWorkoutView` like `workout` is. The alternative is `AppEnvironment`.
4. **Cardio exercises get strength set rows.** `ExercisePickerView` and `ExercisePickerFilter` don't filter on `isCardio`, so adding "Running" to a workout gives weight×reps rows. This gets fixed in Feature 5.
5. **Placeholders are matched by position.** `PreviousPerformance.placeholders` and `ExerciseLogCardView.placeholder(for:)` match rows by raw index. Inserting warm-up sets would shift every working set's placeholder, which breaks the one-tap confirm. Fix this before warm-ups (Feature 6e).
6. **`EditDiaryEntryView` only rescales by quantity ratio.** It needs a direct-edit branch for quick-add entries (Feature 3).

---

## The consolidated schema step (one PR, one review)

**Files:** `Spotter/Core/Models/UserSettings.swift`, `Spotter/Core/Models/Exercise.swift`, new `Spotter/Core/Models/SavedMeal.swift`, `Spotter/Core/Models/Enums.swift`, `Spotter/Core/Persistence/SpotterSchema.swift`, `SpotterTests/Core/PersistenceTests.swift`.

**`Exercise` (existing model)**

| Property | Type | Default | For |
|---|---|---|---|
| `restTimerSeconds` | `Int?` | `nil` (nil means use `UserSettings.restTimerSeconds`) | Feature 6 |
| `cardioEntries` | `[CardioEntry]`, `@Relationship(deleteRule: .nullify, inverse: \CardioEntry.exercise)` | `[]` | Decision 14 / CloudKit readiness |

**`UserSettings` (existing model).** Every new field is optional, with nil meaning "unset / use the default". That's the safest shape for lightweight migration and for CloudKit.

| Property | Type | Meaning |
|---|---|---|
| `heightCM` | `Double?` | Goal calculator |
| `birthYear` | `Int?` | Goal calculator (age = current year − birthYear; a year is less sensitive than a full date) |
| `sexRaw` | `String?` | `BiologicalSex` rawValue: `male` / `female`. nil uses the midpoint constant |
| `activityLevelRaw` | `String?` | `ActivityLevel`: sedentary / light / moderate / very / extra |
| `weightGoalRaw` | `String?` | `WeightGoal`: lose / maintain / gain |
| `weeklyRateKG` | `Double?` | Size of the weekly change (kg/week), e.g. 0.5 |
| `proteinGPerKG` | `Double?` | nil means 1.6 |
| `goalWeightKG` | `Double?` | Goal line on the weight chart |
| `barbellWeightKG` | `Double?` | nil means 20 kg / 45 lb depending on unit |
| `setEffortDisplayRaw` | `String?` | `SetEffortDisplay`: off / rpe / rir. nil means off |

Each `...Raw` field gets a computed typed accessor, following the existing pattern (for example `weightUnit`).

**New enums** in `Spotter/Core/Models/Enums.swift`, all `String, CaseIterable, Codable, Identifiable, Sendable`: `BiologicalSex`, `ActivityLevel` (with `multiplier`), `WeightGoal`, `SetEffortDisplay`.

**New model: `SavedMeal`**

```swift
@Model final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0
    var defaultMealRaw: String?          // Meal rawValue; nil = use the section tapped
    var items: [SavedMealItem] = []      // Codable value array, like FoodItem.servings
}
struct SavedMealItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID; var order: Int
    var foodID: UUID?                    // soft link to FoodItem.id (no relationship)
    var foodName: String; var brandName: String?
    var quantity: Double; var servingLabel: String; var servingGramWeight: Double
    var nutrientsSnapshot: Nutrients     // fallback if the food was deleted
}
```

The items are a value array, not a child `@Model`. That means one new entity instead of two, no inverse on `FoodItem`, and nothing new to be orphaned. `order` is kept so the items read correctly through an `orderedItems` accessor, matching the convention. Register it in `SpotterSchema.models` under `// Nutrition`.

**Not changing:**
- `SetEntry.rpe` stays as is.
- `CardioEntry` fields are enough.
- `MeasurementType.bodyWeight` exists.
- Quick add reuses `DiaryEntry` (see Feature 3), so there's no new field.
- Workout notes use the existing `Exercise.notes` and `WorkoutExercise.notes`.

**Migration.** There is no `VersionedSchema` today. Every change above is an added optional or defaulted attribute, a new entity, or a new optional to-many relationship with an inverse. SwiftData's automatic lightweight migration covers all of these, so **no `VersionedSchema` or `SchemaMigrationPlan` is needed now**. Keep the Phase 3 plan in `ROADMAP.md`: adopt `VersionedSchema` there, and define V1 as an exact copy of the models as they stand at that point.

**CloudKit compatibility.**
- Every new attribute is optional or defaulted.
- There are no new unique constraints.
- The new relationship has an inverse.

**Tests (CI):** extend `PersistenceTests.schemaAcceptsEveryModel` to insert a `SavedMeal` with two items, one having `nutrientsSnapshot` with nil macros. Save, re-fetch, and assert the item round-trips with nil preserved. This matters because the in-memory store still goes through SQLite encoding. Also add typed-accessor tests for the new enums, following `SettingsPersistenceTests`.

**Needs device:** install a pre-schema build, log something, then install this build and confirm it launches. The stakes are low because there's no real data yet.

**Collision flag:** CLAUDE.md says to add no `@Model` types and to leave `Core/Models/` alone. This step is the explicit, one-time exception, and it needs Kai's sign-off on Decisions 1, 2 and 14.

---

## Feature 1 — Body weight + trend line (M)

**Goal:** fast weigh-in entry, and a smoothed trend that reads as a signal instead of daily noise.

**UX**
- **Today:** a new `BodyWeightCard` below `WorkoutSummaryCard` shows the trend weight, the 7-day change ("−0.4 kg / wk") and a mini sparkline. Tapping it pushes `BodyWeightView` inside Today's existing `NavigationStack`. Its "+" button opens `WeighInSheet` directly.
- **`BodyWeightView`:**
  - A range picker (1M / 3M / 6M / 1Y / All).
  - A Swift Charts chart: faint `PointMark`s for the raw weigh-ins, a `LineMark` for the trend, and a dashed `RuleMark` at `goalWeightKG` if it's set.
  - A list of weigh-ins below, with swipe to delete and tap to edit.
- **`WeighInSheet`:** one decimal field in the user's `weightUnit`, prefilled with the last value, and a date defaulting to now. Save converts with `UnitConverter.weightToKilograms` and inserts `BodyMeasurement(type: .bodyWeight, value: kg)`.

**Data:** none. `BodyMeasurement` already stores kg and a `dayKey`.

**Files**
- `Spotter/Features/Body/BodyWeightTrend.swift`: pure logic.
- `Spotter/Features/Body/BodyWeightView.swift`, `Spotter/Features/Body/WeighInSheet.swift`, `Spotter/Features/Body/BodyWeightChart.swift`.
- `Spotter/Features/Today/BodyWeightCard.swift`, and `Spotter/Features/Today/TodayView.swift`, which adds the card.
- `SpotterTests/Body/BodyWeightTrendTests.swift`.

**Pure logic** (`BodyWeightTrend`), working on `struct WeighIn { dayKey: String; kg: Double }` so tests need no container:
1. `dailyMeans([WeighIn]) -> [(dayKey, kg)]`, sorted by key.
2. `trend(dailyMeans, alpha: 0.1, calendar:) -> [TrendPoint(dayKey, raw, trend)]`:
   - Seed with the first value.
   - For a gap of *n* days (via `DayKey.date(from:)` plus `calendar.dateComponents([.day])`, **not** 86 400-second arithmetic), use `α_eff = 1 − (1 − α)^n`. Then `trend = prev + α_eff · (x − prev)`.
3. `weeklyRate(points) -> Double?`: `trend(latest) − trend(at or before latest − 7 days)`. nil if there's under a week of history.
4. `latestTrendKG(...) -> Double?`, which Features 4 and 5 consume.

**Tests:**
- A constant series stays constant.
- A step change converges geometrically: after 1 day it's exactly 10% of the step.
- A 3-day gap equals three single steps of the same value.
- Several weigh-ins on one day are averaged.
- Empty input gives nil or an empty result.
- A gap spanning a DST change counts days correctly (use a fixed `TimeZone(identifier: "Pacific/Auckland")` calendar).

**Risks:** 30+ points with `LineMark` is fine. `@Query` over all `BodyMeasurement` rows filtered in Swift matches the existing `WeeklyStripCard` approach. HealthKit weight import is out of scope, per the decision already made.

**CI:** trend maths, rate, conversions. **Device:** chart legibility, keyboard, card layout at large Dynamic Type sizes.

**Phase 3:** trend weight fits the "Summary" access level. Raw weigh-ins fit "Full detail".

---

## Feature 2 — Backup and export (M–L)

**Goal:** get everything out as one versioned JSON file, and get it back in without duplicates.

**UX:** a new "Data" section in `SettingsView`:
- **"Export Backup"** builds the file into `FileManager.default.temporaryDirectory` as `Spotter-Backup-yyyy-MM-dd.json`, then shows `ShareLink(item: url)`. A URL is `Transferable`, so no invented API is involved.
- **"Import Backup…"** uses `.fileImporter(isPresented:allowedContentTypes: [.json])`. Wrap the read in `url.startAccessingSecurityScopedResource()` / `stopAccessing…`. Show a summary before committing ("Adds 412 diary entries, 37 workouts… Skips 12 already present") behind a confirmation.
- The footer warns that the file contains health data in plain text.

**Format** (`SpotterBackup`, Codable):
- Top level: `formatVersion: Int = 1`, `exportedAt`, `appVersion`.
- One array per model, using **DTO structs separate from the `@Model`s**, so a model refactor doesn't silently change the file format.
- Relationships are stored as UUID references: `DiaryEntry.foodID`, `WorkoutExercise.workoutID/exerciseID`, `SetEntry.workoutExerciseID`, `RoutineExercise.routineID/exerciseID`, `Workout.sourceRoutineID`, `CardioEntry.exerciseID`.
- Enums are exported as their raw strings. `Nutrients` goes through its own Codable, so nil stays nil.
- **`dayKey` is exported and imported verbatim, never recomputed.** Re-deriving it from `loggedAt` on a phone in a different time zone would silently move entries to other days.
- Dates use `JSONEncoder.DateEncodingStrategy.iso8601`, which drops sub-second precision. That's acceptable because ordering within a meal only needs seconds; tests compare with a tolerance.

**Import rules** (`BackupImporter`, `@MainActor`, two passes):
1. **Decode.** Reject `formatVersion` greater than the supported version with a clear error.
2. **Build ID maps**, inserting parents first (Exercise, FoodItem, Routine, Workout) and children second:
   - Any UUID already in the store is skipped (local wins).
   - **Built-in exercises** (`isCustom == false`): match by lower-cased name, reusing `ExerciseLibrary.seedIfNeeded`'s rule, and map the incoming ID to the local one. **This matters because every install seeds the library with fresh random UUIDs**, so restoring on a new phone would otherwise duplicate the whole library.
   - **FoodItem with a barcode already stored under a different UUID:** map to the local row. Don't insert it. `@Attribute(.unique)` would *upsert*, silently overwriting the local row's fields.
   - **UserSettings:** a singleton, so never insert a second row. If the local settings row is fresh (nothing else in the store), copy the fields across. Otherwise leave it alone. v1 has no toggle.
   - **SavedMeal:** by UUID. `SavedMealItem.foodID` goes through the FoodItem ID map.
3. Save once at the end. On any error, roll back.

**Files**
- `Spotter/Services/Backup/BackupFormat.swift`: DTOs plus `formatVersion`.
- `Spotter/Services/Backup/BackupExporter.swift`: `ModelContext` → `SpotterBackup`.
- `Spotter/Services/Backup/BackupImporter.swift`: returns an `ImportReport`, with a dry-run mode for the summary.
- `Spotter/Features/Settings/DataManagementSection.swift`, plus a one-line addition in `SettingsView.swift`.
- `SpotterTests/Services/BackupRoundTripTests.swift`.

Backup is cross-cutting (it reads every model), so it goes in `Services/`, not in one feature folder.

**Tests (all CI, the strongest-covered feature):**
- Full round trip: seed container A, export, import into empty container B, and compare counts plus spot-check fields, including nil macros and `dayKey`.
- Importing the same file twice leaves counts unchanged.
- Built-in exercise remapping: B is seeded first, and the workouts must link to B's "Bench Press" with no duplicate exercises.
- The barcode clash maps to the existing row and doesn't overwrite its name.
- A future `formatVersion` is rejected.
- Relationships and `orderedSets` order survive the trip.

**Risks:**
- Exporting runs on the main actor. That's fine at this data scale.
- The file grows with history, but even 10 years of history is only a few MB.

**Later: CloudKit private sync.** It's a one-line `cloudKitDatabase:` change in `SpotterSchema.makeContainer`, but it's blocked by:
1. `@Attribute(.unique)` on `FoodItem.barcode` (replace it with dedupe on insert, as `FoodDetailView.resolvedFoodItem` already half-does).
2. Every relationship needing an inverse. Fixed by the schema step, which adds `Exercise.cardioEntries`.
3. **To verify:** whether CloudKit wants to-many relationships declared optional (`[T]?`). If so, that's a model-wide change.
4. The `UserSettings` singleton duplicating across devices, which needs a merge-on-launch step.

**Phase 3:** the DTOs plus UUID references are effectively the future sync wire format. Keeping them separate from `@Model` makes that easier. Phase 3 will add `updatedAt` and deletion tombstones as `formatVersion: 2`.

---

## Feature 3 — Faster food logging (M total)

All three parts touch `Spotter/Features/Nutrition/`. Ship them as three PRs.

### 3a. Quick add (S), no schema change

- **UX:** each meal section in `DiaryDayContent` gets a second row, "Quick Add", next to "Add Food". It opens `QuickAddSheet` with a name (default "Quick add"), kcal (required), and optional protein, carbs and fat.
- **Storage:** a `DiaryEntry` with `food: nil`, `quantity: 1`, `ServingSize(label: "Quick add", gramWeight: 0)`, and `nutrients` built from the fields. **An empty macro field becomes `nil`, never `0`**, and fibre, sugar and so on stay nil.
- **Detection:** add a computed `DiaryEntry.isQuickAdd { food == nil && servingGramWeight == 0 }` in `Spotter/Features/Nutrition/QuickAdd.swift` as an extension. The model file doesn't change. `servingGramWeight == 0` can't come from a food (every serving has a weight).
- **Editing:** `EditDiaryEntryView` branches. Quick-add entries edit kcal and macros directly instead of by quantity ratio.
- **Files:** `QuickAdd.swift` (`QuickAdd.makeNutrients(kcalText:proteinText:…) -> Nutrients?` plus `isQuickAdd`), `QuickAddSheet.swift`, `NutritionDiaryView.swift`, `EditDiaryEntryView.swift`.
- **Tests:**
  - Blank macros give nil.
  - "0" gives 0.
  - Blank or invalid kcal is rejected.
  - Localized decimal separators parse: use `Double(text.replacingOccurrences(of: ",", with: "."))`, or a `NumberFormatter` configured once, following the `QuantityFormatter` pattern.
  - `isQuickAdd` is true for a quick-add entry and false for an entry whose food was deleted.

### 3b. Copy a meal from yesterday or any day (S)

- **UX:** the meal section header gets a `Menu` with "Copy from Yesterday", "Copy from…" and "Save as Meal".
  - "Copy from…" opens `CopyMealSheet`: a `DatePicker` (graphical), a meal picker, and that day's entries with checkboxes (all selected by default), then "Add N items".
  - Copying goes **into the day being viewed**, not always today.
- **Pure logic, `MealCopy.copies(of: [DiaryEntrySnapshot], into meal: Meal, dayKey: String, now: Date, calendar:) -> [DiaryEntry]`:**
  - New UUIDs.
  - `loggedAt` = the target day's start (`DayKey.date(from:)`) plus the current time of day. If the target is today, use `now`.
  - Add `i` seconds per item to keep the source order.
  - Copy the snapshot fields verbatim (`nutrients`, `servingLabel`, `quantity`, `brandName`) and keep the `food` link. It must **not** re-read nutrition from `FoodItem`.
  - Call `food?.markUsed()`.
- **Files:** `Spotter/Features/Nutrition/MealCopy.swift`, `CopyMealSheet.swift`, `NutritionDiaryView.swift`.
- **Tests:**
  - The resulting `dayKey` equals the target key, including on a DST-transition day in `Pacific/Auckland`.
  - Order is preserved.
  - nil nutrients stay nil.
  - A copied entry of a deleted food keeps its snapshot.
  - New IDs are distinct from the source IDs.

### 3c. Saved meals (M), uses the new `SavedMeal` model

- **UX:**
  - Create one with "Save as Meal" on a meal section: prompt for a name, then snapshot the section's entries into `SavedMealItem`s.
  - Log one from `AddFoodView`, which gets a new `AddFoodTab.meals` ("Meals"). Each row shows the name, item count and total kcal. One tap logs every item into the current meal and dismisses. Swiping reveals Edit and Delete.
  - `SavedMealEditorView` lets you rename, remove items and change quantities. No nested food search in v1.
- **Logging rule:** for each item, if `foodID` resolves to a live `FoodItem`, use `DiaryEntry(logging:quantity:serving:meal:)`, which gets current nutrition. Otherwise build a `DiaryEntry` from `nutrientsSnapshot`. Either way the diary snapshots at log time, as the convention requires. Then bump `SavedMeal.useCount` and `lastUsedAt`.
- **Files:** `Spotter/Features/Nutrition/SavedMealLogging.swift` (pure: `items(from entries:)`, `entries(for meal:resolvingFoods:[UUID: FoodItem]…)`), `SavedMealsList.swift`, `SavedMealEditorView.swift`, `AddFoodView.swift` (new tab), `NutritionDiaryView.swift`.
- **Tests:**
  - Snapshot → items → entries round-trips.
  - The deleted-food fallback uses the snapshot.
  - A live food uses its current per-100 g values.
  - Totals keep nil-vs-zero.
  - `useCount` goes up.

**Risks:** `NutritionDiaryView.swift` (283 lines) and `AddFoodView.swift` (439 lines) are getting large. Put new UI in new files and keep the edits to these two small.

**CI:** all logic. **Device:** header menu discoverability, one-tap flow feel.

---

## Feature 4 — Goal calculator (S–M)

**Goal:** turn body stats into calorie, protein, carb and fat targets written to the existing `UserSettings.daily*Goal*` fields.

**UX:**
- A "Calculate…" button at the top of `GoalsEditorView` (Food tab → target icon) and in Settings → Goals opens `GoalCalculatorView`.
- Inputs:
  - Weight, prefilled from `BodyWeightTrend.latestTrendKG`, else the last weigh-in, else manual entry with an "also save as weigh-in" toggle.
  - Height (cm, or ft/in when the weight unit is pounds).
  - Birth year and sex (including "Prefer not to say").
  - Activity level, with a one-line description for each.
  - Goal (lose / maintain / gain) and weekly rate (0.25 / 0.5 / 0.75 / 1.0 kg/wk).
  - Protein g/kg (a stepper, 1.2–2.4, default 1.6).
- A live result card shows BMR, maintenance, the target and the macro split. "Apply" writes all four goals and saves the inputs to the new `UserSettings` fields. A footer carries a not-medical-advice note.

**Pure logic, `GoalCalculator`:**
- **Mifflin–St Jeor:** `BMR = 10·kg + 6.25·cm − 5·age + s`, where s = +5 (male), −161 (female), −78 (unspecified, the midpoint).
- **TDEE** = BMR × multiplier (1.2 / 1.375 / 1.55 / 1.725 / 1.9).
- **Goal adjustment:** `rate_kg_per_week × 7700 / 7` kcal/day (≈ 550 at 0.5 kg/wk), negative to lose and positive to gain.
- **Floor:** the target is never below `max(BMR, 1200)`. Surface a note when it's clamped.
- **Protein** = g/kg × kg. **Fat** = 0.8 g/kg (never below 20% of kcal). **Carbs** = remaining kcal ÷ 4, clamped at ≥ 0. Round kcal to the nearest 10 and grams to whole numbers.

**Files:** `Spotter/Features/Nutrition/GoalCalculator.swift`, `Spotter/Features/Nutrition/GoalCalculatorView.swift`, `GoalsEditorView.swift` (button), `Spotter/Features/Settings/SettingsView.swift` (button), `SpotterTests/Nutrition/GoalCalculatorTests.swift`.

**Tests:**
- Male, 80 kg, 180 cm, age 30 → BMR 1780. Female → 1614. Unspecified → 1697.
- Multipliers apply correctly.
- Losing 0.5 kg/wk → −550.
- The floor clamp works.
- Carbs never go negative.
- Age derives from birth year against a fixed "now".

**Collisions:** reads Body data from Feature 1, writes `UserSettings`. No project or schema change beyond the schema step.

**Phase 3:** coach-set targets later write the same four fields. Keep the "Apply" path as the one place that writes them.

---

## Feature 5 — Cardio logging (M)

**Goal:** a lightweight cardio log, in line with the doc comment on `CardioEntry` ("a strength app with a basic cardio log attached").

**UX. What would RepCount do:** keep it simple and separate from the strength set grid.
- **`WorkoutsHomeView` `activeSection`:** a "Log Cardio" button next to "Start Empty Workout".
- **`ActiveWorkoutView`:** a "Log Cardio" button below "Add Exercise", so a treadmill finisher can be logged without leaving the session. It uses the same sheet.
- **`CardioEntrySheet` fields:**
  - Exercise (picker filtered to `isCardio`).
  - Duration (h:m:s wheels or minute stepper).
  - Distance (optional; km, or miles when the weight unit is pounds, derived from the unit so there's no new setting).
  - Calories: an estimated value shown as a placeholder. The user can override it or clear it to nil.
  - Notes, and date/time.
- **History:** `WorkoutHistoryListView` and the home "Recent Workouts" merge cardio rows (`CardioHistoryRow`: name, duration, distance, kcal) by date.
- **Today:** `WorkoutSummaryCard` adds a line "Cardio: 32 min · ~310 kcal" for today's entries. **This isn't added to the calorie budget** (Decision 4).
- **Weekly strip:** `WeeklyStripCard.workoutDayKeys` unions in the cardio day keys (Decision 5).
- **Fix the strength-picker bug:** `ExercisePickerFilter.matches` gains `includeCardio: Bool` (default `false`). `ExercisePickerView` gets an `includeCardio`/`cardioOnly` parameter. The strength picker and `RoutineEditorView` hide cardio exercises.

**Calorie estimate, `CardioCalories`:**
- `kcal = MET × kg × hours`, using `latestTrendKG` from Feature 1. **If no body weight is known, return nil** (unknown), not a guess.
- **Running/Treadmill with a distance:** use ≈ 1.0 kcal/kg/km instead, which is more accurate than a fixed MET.
- MET table keyed by seed name (approximate Compendium of Physical Activities values): Treadmill 6.0, Running 9.8, Cycling 6.8, Rowing Machine 7.0, Elliptical 5.0, Stair Climber 9.0, Swimming 5.8, Jump Rope 11.8.
- Custom cardio exercises get nil unless the user types a value.
- Use gross METs for the display. If an opt-in "count toward budget" setting is ever added, use net (MET − 1) to avoid double-counting BMR.

**Data:** no new fields. `CardioEntry` has everything. The schema step adds the inverse only.

**Files:**
- `Spotter/Features/Workouts/Logic/CardioCalories.swift`.
- `Spotter/Features/Workouts/Views/CardioEntrySheet.swift`, `Spotter/Features/Workouts/Views/CardioHistoryRow.swift`.
- Changes to `WorkoutsHomeView.swift`, `ActiveWorkoutView.swift`, `ExercisePickerView.swift`, `ExercisePickerFilter.swift`, `WorkoutHistoryListView.swift`.
- Today: `WorkoutSummaryCard.swift`, `WeeklyStripCard.swift`, `DashboardAggregation.swift` (`weekGlances` takes the union set; the signature is unchanged).
- Tests: `SpotterTests/Workouts/CardioCaloriesTests.swift`, plus an extension to `ExercisePickerFilterTests`.

**Tests:**
- The MET formula.
- Distance-based running.
- No weight gives nil.
- An unknown exercise gives nil.
- The picker filter excludes cardio by default and includes it with the flag.
- The glance's `hasWorkout` is true for a cardio-only day.

**Risks:** `ActiveWorkoutView` conflicts with PR #1, so land this after it.

**Device:** duration input ergonomics.

---

## Feature 6 — RepCount extras (M–L; five small PRs)

Every one of these must keep the **one scrollable logging screen**: no sub-screens for logging, only sheets for tools.

### 6a. Notes per exercise (S), no schema change
- `Exercise.notes` becomes a **sticky note** shown under the card title in every session (for example "seat height 4").
- `WorkoutExercise.notes` is **this session's note**.
- Header `Menu` in `ExerciseLogCardView` → "Edit Note". An inline `TextField(axis: .vertical)` expands in the card. Toggle between "Exercise note" and "Today only".
- `WorkoutDetailView` and `ExerciseHistorySheet` show session notes.
- Tests: none meaningful (UI only). **Device:** keyboard avoidance inside `LazyVStack`.

### 6b. Per-exercise rest override (S), uses `Exercise.restTimerSeconds`
- Header menu → "Rest Timer ▸" with Default (1:30) / 0:30 / 1:00 / … / 5:00 / Off.
- `ExerciseLogCardView.onSetCompleted` changes from `() -> Void` to pass the `WorkoutExercise`, so `ActiveWorkoutView.handleSetCompleted(entry)` can resolve the duration.
- Pure `RestDuration.resolve(exerciseOverride: Int?, globalDefault: Int, autoStart: Bool) -> TimeInterval?`, where 0 means off.
- Tests: override wins, nil falls back, zero disables, autoStart false gives nil.
- **Collision:** `handleSetCompleted` is where PR #1's finish-feedback fix lands. Rebase onto it.

### 6c. RPE / RIR (S), uses existing `SetEntry.rpe`
- Only shown when `setEffortDisplay != .off`.
- A compact `Menu` button in `SetRowView`, between reps and the check (6, 6.5 … 10, and Clear), labelled "RPE 8" or "RIR 2". No keyboard.
- Settings → Workout Preferences gets a picker.
- Pure `SetEffort.label(rpe:display:)` and `rir(fromRPE:) = 10 − rpe`.
- **Collision:** the set row is already tight (`minWidth` 56 + 40 plus the check) and it's the most-tapped UI in the app. **Device:** check at the largest Dynamic Type size. If it's cramped, move RPE to the context menu.

### 6d. Plate calculator (S)
- `SetRowView` context menu → "Plate Calculator" (barbell exercises only; pass `exercise.equipment`). It opens a small sheet showing per-side plates as coloured chips, the bar weight, "achievable: X" when the target isn't exactly loadable, and a bar-weight override stepper that writes `barbellWeightKG`.
- **Pure `PlateCalculator.perSide(target:bar:plates:) -> (plates: [Double], achieved: Double, remainder: Double)`**, computed **in the display unit** so lb users get 45/25/10 instead of 20.41 kg. Greedy is optimal for these standard denominations.
- Tests:
  - 100 kg / 20 bar → [25, 15].
  - 225 lb / 45 → [45, 45].
  - Target below the bar → no plates.
  - Unloadable targets report the remainder.
  - 0 and negative targets are safe.

### 6e. Warm-up set generator (M)
- Header menu → "Add Warm-up Sets".
- The working weight comes from the first working set's `weightKG`, else its placeholder.
- The scheme is empty bar ×10, 40% ×5, 60% ×3, 80% ×2. Each is rounded to the smallest loadable increment (2.5 kg or 5 lb, via `PlateCalculator`), dropping duplicates and anything ≤ the bar except the first.
- Inserted as `SetEntry(isWarmup: true)` **before** the first working set, renumbering like `DropSetInsertion`.
- **Must fix first:** positional placeholder matching (see "Must change first" #5). Change `PreviousPerformance` to match per kind: the k-th warm-up to the previous k-th warm-up, the k-th working set to the previous k-th working set, and a drop set to its parent's drop sets in order. Update `ExerciseLogCardView.placeholder(for:)` to match.
- **Files:** `Spotter/Features/Workouts/Logic/WarmupGenerator.swift`, `PlateCalculator.swift`, `RestDuration.swift`, `SetEffort.swift`, `Views/PlateCalculatorSheet.swift`, plus changes to `ExerciseLogCardView.swift`, `SetRowView.swift`, `ActiveWorkoutView.swift`, `PreviousPerformance.swift`, and `SettingsView.swift` (effort display, bar weight).
- **Tests:**
  - 100 kg → [20×10, 40×5, 60×3, 80×2].
  - Rounding in lb.
  - A light working weight collapses duplicates.
  - Insertion order and renumbering.
  - **The new per-kind placeholder matching:** a session with 2 warm-ups plus 3 working sets, after a previous session with 0 warm-ups, still maps working set 1 to previous working set 1. Update the existing `PreviousPerformanceTests` expectations.

**CI:** all maths. **Device:** row density, menu reachability mid-set.

---

## Feature 7 — Streaks and weekly summary on Today (S–M)

**UX:**
- A new `StreakSummaryCard` on Today, between Water and Workout:
  - 🔥 "12-day logging streak" (or "Log today to keep your 12-day streak" while today is pending).
  - "Water goal hit 5/7 days".
  - "Workouts this week: 3".
- A new `WeeklySummaryCard` (or a footer on `WeeklyStripCard`) for the calendar week so far:
  - Days logged x/7.
  - Average kcal against goal on logged days.
  - Protein-goal hit days.
  - Workouts and total volume.
  - Cardio minutes.
  - Trend weight change (from Feature 1).

**Pure logic, `StreakCalculator`**, over `Set<String>` day keys:
- `currentStreak(days:today:calendar:) -> (length: Int, todayPending: Bool)`. Walk back from today, or from yesterday if today isn't in the set yet, stepping with `calendar.date(byAdding: .day, value: -1)` on `DayKey.date(from:)` and re-keying. Never step by 86 400 seconds.
- `longestStreak(days:calendar:)`.

**Pure logic, `WeeklySummary.make(weekKeys:diaryByDay:waterByDay:goals:workoutKeys:cardioByDay:…)`.** Week keys come from `calendar.dateInterval(of: .weekOfYear, for: now)` and are clipped to today.

**Definitions:**
- "Day logged" = at least one `DiaryEntry` (Decision 6).
- "Water goal hit" = the day's total ≥ goal.
- "Trained" = a finished `Workout` or any `CardioEntry`.

**Time zones:** a `dayKey` is frozen at log time in the device's zone. Travelling can create a gap or a double day. Accept that and document it: the streak runs over keys, not instants, which keeps it deterministic and reproducible server-side in Phase 3.

**Files:** `Spotter/Features/Today/StreakCalculator.swift`, `Spotter/Features/Today/WeeklySummary.swift`, `Spotter/Features/Today/StreakSummaryCard.swift`, `Spotter/Features/Today/WeeklySummaryCard.swift`, `TodayView.swift`, tests in `SpotterTests/Today/`.

**Tests:**
- An empty set gives 0.
- Today pending continues yesterday's streak.
- One gap breaks it.
- Across a DST boundary (Auckland April/September) and a month or year boundary.
- The longest streak is found in the middle of the data.
- The week clips at today.
- A Monday-first vs Sunday-first calendar gives the expected week.
- Average kcal ignores unlogged days and uses `effectiveKcal`.

**Performance:** keys come from `@Query` over all rows, like `WeeklyStripCard`. That's fine at this scale. If it's ever slow, fetch with a `dayKey >= cutoff` predicate, because string keys sort lexically.

**Phase 3:** these functions are the **Check-in** level ("Worked out ✓ · Logged food ✓ · Water ✗"). Keep them pure over day keys so the same definitions can be ported server-side.

---

## Feature 8 — Live Activity (rest timer), then the Home Screen widget

### The deliberate one-time `project.yml` change

**Collision:** CLAUDE.md says "Do not edit `project.yml`". This is the one sanctioned edit, reviewed on its own, in its own PR:

```yaml
targets:
  Spotter:
    # existing keys unchanged, plus:
    sources:
      - path: Spotter
      - path: Shared                      # new: code compiled into app + extension
    dependencies:
      - target: SpotterWidgets              # embeds the extension
    info:
      properties:
        # existing properties unchanged, plus:
        NSSupportsLiveActivities: true
    entitlements:                         # widget step only (see note)
      path: Spotter/Spotter.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.yungsukuna.spotter

  SpotterWidgets:
    type: app-extension
    platform: iOS
    configFiles:                          # needed so DEVELOPMENT_TEAM from Secrets.xcconfig reaches the extension
      Debug: Config/App.xcconfig
      Release: Config/App.xcconfig
    sources:
      - path: SpotterWidgets
      - path: Shared
      - path: Spotter/Core/Design/Theme.swift   # reuse tokens without moving the file
    info:
      path: SpotterWidgets/Info.plist
      properties:
        CFBundleDisplayName: Spotter
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:                         # widget step only
      path: SpotterWidgets/SpotterWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.yungsukuna.spotter
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yungsukuna.spotter.widgets
        PRODUCT_NAME: SpotterWidgets
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_UPCOMING_FEATURE_STRICT_CONCURRENCY: YES
        SKIP_INSTALL: YES
```

Also:
- Add `SpotterWidgets/Info.plist` to `.gitignore` (it's generated, like `Spotter/Info.plist`).
- Either commit the generated `.entitlements` files or gitignore them. Recommend committing them.

**Note:**
- The Live Activity needs **no** App Group. If Decision 13 comes back "free team, no App Groups", land the change without the two `entitlements:` blocks, and add them later with the widget.
- CI builds unsigned (`CODE_SIGNING_ALLOWED=NO`). Entitlements don't break that, but they're only exercised on Kai's device.

### 8a. Live Activity (M)

**Prerequisites:**
- PR #1 has landed.
- The rest-timer ownership fix ("Must change first" #3).

**Design:**
- **`Shared/RestTimerActivityAttributes.swift`:** `struct RestTimerActivityAttributes: ActivityAttributes`, with `ContentState: Codable, Hashable { endDate: Date; exerciseName: String? }` and a static `workoutName`.
- **New protocol in `Spotter/Features/Workouts/Logic/RestTimerActivityPresenting.swift`,** alongside `RestTimerNotifying`:
  - `begin(endDate:exerciseName:)`, `update(endDate:)`, `end()`. Synchronous signatures, for the same testability reason given in `RestTimerNotifying`.
  - `NoopRestTimerActivityPresenter` as the **default** in `RestTimerController.init`, so existing tests and previews don't touch ActivityKit.
  - `MockRestTimerActivityPresenter` for tests.
  - `SystemRestTimerActivityPresenter`, injected by the owner.
- **`RestTimerController` calls:**
  - `start` → `begin`.
  - `addTime` → `update` (unlike the notification, which is cancelled).
  - `skip`, `reset` and `checkExpiration` → `end`.
- **The system presenter:**
  - Checks `ActivityAuthorizationInfo().areActivitiesEnabled`.
  - Calls `Activity.request(attributes:content:pushType: nil)` with `ActivityContent(state:staleDate: endDate)`.
  - Keeps the current `Activity` in a small actor.
  - `end` also sweeps `Activity<RestTimerActivityAttributes>.activities`, which kills orphans from an app kill. Also sweep once at launch from `SpotterApp`.
  - **Reuse the per-identifier generation-counter pattern from PR #1's `SystemRestTimerNotifier`**, so a fast "complete set, then skip" can't leave an activity behind. Tests with the mock assert call order, not the async side.
- **Extension UI in `SpotterWidgets/RestTimerLiveActivity.swift`:**
  - `ActivityConfiguration(for: RestTimerActivityAttributes.self)` with a Lock Screen view: `Text(timerInterval: Date()...endDate, countsDown: true)`, `ProgressView(timerInterval:countsDown:)` and the exercise name.
  - Dynamic Island compact, minimal and expanded regions.
  - When `context.isStale`, show "Rest over".
  - `SpotterWidgets/SpotterWidgetsBundle.swift` holds `@main WidgetBundle`.

**Known limitation:** once the timer ends with the app suspended, the countdown stops at 0:00 and shows stale. It can't be ended without push notifications (out of scope). It gets ended on the next foreground or the next set.

**Tests (CI):**
- Controller → presenter calls for start, addTime, skip and expiry.
- Existing `RestTimerControllerTests` stay unchanged thanks to the no-op default.
- `ContentState` Codable round-trip.

**Needs device, for Kai:**
- Lock Screen countdown.
- Dynamic Island (iPhone 15/16 Pro, or the iPhone 16 simulator).
- A skip right after completing a set leaves nothing behind.
- Killing the app mid-rest, then relaunching, clears it.
- The iOS Settings toggle off → no request made.

### 8b. Home Screen widget (M)

**Recommendation (Decision 12): a snapshot, not a shared store.**
- **`Shared/WidgetSnapshot.swift`:** `struct WidgetSnapshot: Codable { dayKey; kcalConsumed: Double?; kcalGoal; waterML; waterGoalML; volumeUnitRaw; generatedAt }`. It's stored as `Data` in `UserDefaults(suiteName: "group.com.yungsukuna.spotter")`.
- **`Spotter/App/WidgetSnapshotWriter.swift`:** builds the snapshot using `DashboardAggregation` / `WaterAggregation`, then calls `WidgetCenter.shared.reloadAllTimelines()`.
  - Called from `SpotterApp` on `scenePhase` → `.background`.
  - Also called after the known save points: `FoodDetailView.save`, the Water logging actions, quick add, copy and saved meals, and import. That's explicit call sites, not an invented save notification.
- **Widget:** `SpotterWidgets/DailyRemainingWidget.swift`, a `StaticConfiguration` with `.systemSmall`/`.systemMedium` and `.accessoryRectangular`/`.accessoryCircular` for the Lock Screen.
  - Timeline entries at now and at the next local midnight.
  - **If `snapshot.dayKey != today`, render "0 of goal"** so yesterday's numbers never show after midnight.
  - If the suite is missing, render a placeholder.
- **Tests (CI):** snapshot building from fixture entries (kcal uses `effectiveKcal`, nil stays nil), the stale-day rule, and Codable round-trip. **Device:** real refresh cadence, the midnight rollover, and the look.

**If you want an interactive widget later (for example a "+250 ml" `AppIntent` button), the store has to move to the App Group.** Move it now, before real data exists:
- In `SpotterSchema.makeContainer`, resolve `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
- **Fall back to the current default location when that returns nil.** It may be nil in unsigned CI or simulator builds; tests use in-memory stores anyway.
- Before building the container, if `Application Support/default.store` exists and the group store doesn't, move `default.store`, `default.store-shm` and `default.store-wal` together. Do it once, and log it.
- Then use `ModelConfiguration(schema:url:)` with the group URL.
- Two processes writing one SQLite store is supported but adds risk. Keep the widget read-only unless you need the interactive button.
- **Device verify:** upgrade from the old location keeps the data.

**Phase 3:** this changes nothing there. The snapshot type is also a reasonable shape for a future "today check-in" payload.

---

## Verification matrix

| Feature | CI-verifiable | Needs Kai on a device |
|---|---|---|
| Schema step | Schema builds, insert/fetch, SavedMeal item round-trip | Upgrade install launches |
| 1 Body weight | EWMA, gaps, rate, units | Chart, entry sheet, Today card |
| 2 Backup | Full round-trip, dedupe, remaps, version guard | Share sheet, Files import, security-scoped access |
| 3 Food logging | Quick-add nil rules, copy dayKey/order, saved-meal resolution | Header menus, one-tap flow |
| 4 Goal calc | Formula values, clamps, macro split | Form usability |
| 5 Cardio | MET/distance maths, picker filter, glance union | Sheet ergonomics |
| 6 RepCount extras | Plates, warm-ups, per-kind placeholders, rest resolve, RIR | Set-row density, menus mid-set |
| 7 Streaks | Streak/week maths incl. DST | Card layout |
| 8a Live Activity | Controller→presenter calls, ContentState | Lock Screen, Dynamic Island, orphan cleanup |
| 8b Widget | Snapshot build, stale-day rule | Refresh, midnight rollover, App Group signing |

Every new view gets a `#Preview` using `SpotterSchema.previewContainer()` and `.environment(\.appEnvironment, .preview())`. For seeded weigh-ins, cardio and saved meals, add preview seeders in a new `Spotter/Features/Body/BodyPreviewData.swift` and extend `WorkoutsPreviewData.swift`.
