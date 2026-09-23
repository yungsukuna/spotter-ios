# Spotter — working notes

iOS calorie / workout / water tracker. Swift 6, SwiftUI, SwiftData, iOS 18 minimum.
Read `README.md` first for the architecture overview.

## Critical constraint

**This repository is authored on Windows. There is no Swift compiler here.** Nothing you write can be
compiled or run locally. The macOS GitHub Actions runner is the only build verification that exists.

Write accordingly:

- Prefer boring, certain Swift over clever Swift. You cannot check whether the clever thing compiles.
- Do not invent API. If you are not certain a symbol exists with that exact signature, use one you are
  certain of.
- Never reference a type, property or function that is not either in this repo already or in a
  first-party Apple framework you are sure of.
- Keep files self-contained. A compile error in a file nobody else depends on is cheap; one in a shared
  type blocks everyone.

## Hard rules

**No third-party dependencies.** Everything needed is first-party: SwiftUI, SwiftData, VisionKit, Swift
Charts, Swift Testing. Do not add a package.

**Do not edit `project.yml`.** Source paths are directory globs — new files are picked up
automatically. Editing it is how four parallel workstreams create merge conflicts.

**Stay inside your assigned folder.** If you need something from a shared file (`Core/`, `Services/`),
use it; do not modify it. If a shared type genuinely needs to change, stop and say so rather than
changing it.

**Do not add `@Model` types.** The schema is fixed and complete in `Core/Models/`. Every model must be
registered in `SpotterSchema.models`, and a type added without that fails at runtime, not compile time.

## Conventions

Established in Phase 0 and enforced throughout — see README for the reasoning.

| Rule | Detail |
|---|---|
| Storage units | Always metric. kg, ml, cm. Convert at the view layer with `UnitConverter` / `Format`. |
| Day bucketing | Every logged model has a `dayKey: String` (`yyyy-MM-dd`) from `DayKey.make(from:)`. Query on that, not on date ranges. |
| Ordering | SwiftData to-many relationships are unordered. Use the `orderedX` accessors. |
| Enums | Persisted as `xRaw: String` with a computed typed accessor. |
| Unknown vs zero | `Nutrients` values are `Double?`. `nil` is "unknown", never zero. Preserve the distinction. |
| Diary snapshots | `DiaryEntry` copies name and nutrition at log time. Never read nutrition through to `FoodItem` for historical display. |
| Spacing / colour | Use `Theme.Spacing`, `Theme.Colors`, `Theme.Typography`. No literal paddings or hex colours. |
| Dynamic Type | Fonts are always relative to a system text style. Never a fixed point size. |
| Tap targets | Minimum 44pt, especially set rows — they are tapped repeatedly mid-set. |

## Services

Feature code depends on the `FoodDataSource` protocol, never on a concrete client. Get it from
`@Environment(\.appEnvironment)`. `MockFoodDataSource` provides a sample catalogue covering the awkward
cases — a product with no nutrition panel, a non-round serving size, a genuinely-zero-calorie drink,
and forced not-found / offline failures. Build and preview against it.

## Tests

Swift Testing (`@Test`, `#expect`, `#require`), not XCTest. Put tests in `SpotterTests/`, mirroring the
source layout.

Test the logic, not the layout: nutrient maths, unit conversion, 1RM and volume, PR detection, JSON
decoding, state machines. Do not write snapshot or UI tests.

Use `SpotterSchema.makeContainer(inMemory: true)` for anything touching SwiftData. `@MainActor` on the
suite.

## Previews

Every view gets a `#Preview`. The standard form:

```swift
#Preview {
    SomeView()
        .modelContainer(SpotterSchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
```

## The Workouts section

It is a deliberate replication of [RepCount](https://www.repcountapp.com/). If a decision there is
ambiguous, the tiebreaker is "what would RepCount do". The defining details, in priority order:

1. **One scrollable logging screen.** Every exercise and all of its set rows are inline. You never
   navigate into a sub-screen to log a set. This is the single most-praised thing about RepCount and it
   drives the whole view hierarchy — build it this way from the start.
2. **Last session's numbers as placeholder text** in each set row, so an unchanged set is one tap.
3. **Rest timer** on set completion, with a local notification so it fires with the screen off.
4. **Supersets** — adjacent exercises, visually bracketed, logged alternately.
5. **Drop sets** — indented sub-rows under their parent set.
6. **Exercise history from inside the workout screen**, as a sheet. Not a separate destination.
7. **Stats** — estimated 1RM over time, volume over time, heaviest weight, rep-record table.
8. **Routines** — save a workout as a template; start a session from one.
