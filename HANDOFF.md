# Handoff

Written 2026-09-20 by the session that scaffolded this repo. Read `CLAUDE.md` first for the
conventions, then this for where things actually stand.

---

## The one thing to understand before touching anything

**This repo is authored on Windows. There is no Swift compiler on this machine.** Nothing here can be
compiled or run locally. The macOS GitHub Actions runner is the *only* verification that exists, and it
takes 4–5 minutes per run.

That shapes the whole workflow. Every remaining task in this document is a compile error that CI found.
The loop is: read the CI annotations, fix, push, wait, repeat. Do not guess at a fix and move on — push
it and confirm.

Kai has a Mac, so the faster loop is available if he's at it: `xcodegen generate && open Tally.xcodeproj`
surfaces every error at once instead of one CI round-trip at a time. **Ask before assuming he'll do
that** — he hasn't opened the project in Xcode yet at time of writing.

---

## Current state

Repo: **https://github.com/yungsukuna/tally-ios** (public), local at `C:\Users\Kai\Documents\GitHub\tally-ios`.

9 commits, ~10,000 lines, working tree clean, everything pushed.

`gh` CLI is installed at `C:\Program Files\GitHub CLI\gh.exe` and authenticated as **yungsukuna** with
`repo` + `workflow` scopes. **It is not on PATH in the Bash tool** — invoke it by full path:

```bash
GH="/c/Program Files/GitHub CLI/gh.exe"; "$GH" run list --limit 3
```

### CI status: RED

Last green run was `35489393682` (nutrition + water/today/settings, 126 tests). Everything since has
failed on Swift 6 strict-concurrency errors in the newer layers.

Run `35490027126` was in flight when this was written — it carries a fix for the
`CachingFoodRepositoryTests` failure below. **Check it first.**

```bash
GH="/c/Program Files/GitHub CLI/gh.exe"; "$GH" run list --limit 3
```

---

## How to read CI failures

`gh run view --log-failed` returns nothing useful here. Use the annotations, and filter the CoreData
file-permission noise that xcodebuild emits:

```bash
GH="/c/Program Files/GitHub CLI/gh.exe"
"$GH" run view <RUN_ID> 2>&1 | tr -d '\r' | sed -n '/ANNOTATIONS/,$p' \
  | grep -E "^X |^! " \
  | grep -vE "^X (Information|  |File Permissions|755|644|drwx|-rw|component)"
```

`X` lines are errors, `!` are warnings.

**Do not pipe `gh run watch --exit-status` into anything.** The pipeline's exit code is the last
command's, not `gh`'s, which silently turns a failure into a success. This cost a false "CI is green"
report earlier in the session. Use:

```bash
"$GH" run watch <ID> --exit-status > "$LOG" 2>&1 && echo SUCCESS || echo FAILED
```

---

## Known remaining work

### 1. Verify the in-flight fix (do this first)

Run `35490027126` tests a fix to `TallyTests/Services/CachingFoodRepositoryTests.swift:93`.
`CachingFoodRepository` is `@MainActor` (because `ModelContext` isn't Sendable), so
`product(barcode:)` returns a main-actor-isolated, non-Sendable `FoodItem`. Letting the
`#require(throws:)` closure return it made the macro hand it back as a `sending` result. Fixed by
discarding with `_ =`. If CI is green, this section is done.

### 2. The workouts layer has never had a clean compile

This is the biggest open risk. `Tally/Features/Workouts/` is **3,100 lines across 35 files** and has
never once passed a build — every run since it landed has aborted on errors in *other* files before
reaching it, or failed on the test target. It may be entirely fine, or it may have a queue of errors
behind the ones already fixed. Assume the latter until a run goes green.

The workouts agent flagged these as its least-certain areas:
- Swift Charts `Chart`/`LineMark`/`PointMark` usage in `Views/ExerciseStatsView.swift`
- `Picker(selection: Optional<Enum>)` with `.tag(Enum?.some(x))` / `.tag(Enum?.none)` in
  `Views/ExercisePickerView.swift`
- `EditButton()` / `.onMove` inside a `Form` in `Views/RoutineEditorView.swift`

### 3. Known cross-workstream inconsistency (real bug, not a compile error)

`DayTotals.kcalProgress` (`Features/Nutrition/DayTotals.swift`) uses `consumed.kcal`.
`DashboardAggregation.NutritionSummary.kcalFraction` (`Features/Today/DashboardAggregation.swift`) uses
`consumed.effectiveKcal`.

For a food with macros but no stated calorie figure, **the Food tab and the Today tab will show
different progress for the same day.** Two agents built these in parallel and couldn't see each other's
code. Pick one — `effectiveKcal` is the better default, since it uses the Atwater estimate rather than
silently dropping the food — and make both match.

### 4. `AppEnvironment` still uses the mock

`Tally/App/TallyApp.swift` constructs `AppEnvironment(foodDataSource: MockFoodDataSource())`. The real
clients exist and are tested but **are not wired in**, so barcode scanning and search currently return
sample data.

The wiring, once the build is green:

```swift
let settings = UserSettings.current(in: modelContainer.mainContext)
let off = OpenFoodFactsClient(contact: settings.openFoodFactsContact)
let usda = USDAFoodDataCentralClient()          // no-ops to .missingAPIKey when unconfigured
let composite = CompositeFoodDataSource(openFoodFacts: off, usda: usda)
```

Then wrap in `CachingFoodRepository` for barcode lookups. Check the actual initialiser signatures in
`Tally/Services/Food/` — don't trust the sketch above verbatim.

### 5. Scanner isn't connected to the nutrition UI

`AddFoodView` exposes `onScanRequested: (() -> Void)?` and shows a placeholder alert when it's nil.
`BarcodeScannerView` in `Tally/Services/Scanning/` exposes `onScan: (String) -> Void`. Nobody joins
them. The two agents worked in parallel and neither could reach across.

Flow to build: scan → barcode string → `CachingFoodRepository.product(barcode:)` → on
`.productNotFound`, push `CustomFoodEditorView` with the barcode prefilled (it already accepts
`prefilledBarcode`).

### 6. Smaller items

- `actions/checkout@v4` throws a Node 20 deprecation warning. Bump to `@v5`.
- Two `AVCaptureSession` non-Sendable capture **warnings** remain in
  `MetadataCaptureScannerRepresentable.swift`. Non-blocking. `nonisolated(unsafe)` on the property
  didn't silence them; properly fixing means confining the session to an actor.
- No app icon — `Assets.xcassets/AppIcon.appiconset` is an empty placeholder.
- `README.md` says the licence is TBD. **Ask Kai**, don't pick one.

---

## Architecture, in brief

Read `README.md` and `CLAUDE.md` in full. The conventions that are load-bearing and easy to violate:

- **Everything is stored metric.** kg, ml, cm. Units are a display preference converted at the view
  layer via `UnitConverter` / `Format`. Never persist a converted value.
- **`DiaryEntry` snapshots its nutrition** at log time. Never read historical nutrition back through
  `FoodItem` — the food may have been corrected upstream or deleted.
- **`Nutrients` values are `Double?` and `nil` means unknown, not zero.** Preserve this through every
  transformation.
- **SwiftData to-many relationships are unordered.** Use the `orderedX` accessors, always.
- **Enums persist as `xRaw: String`** with a computed typed accessor, because `#Predicate` support for
  Codable enums is unreliable.
- **`project.yml` must not be edited** to add files. Source paths are globs; new files are picked up by
  `xcodegen generate` automatically. Four parallel agents added ~100 files without touching it.

### The Workouts section is a deliberate RepCount replica

Not "inspired by" — the brief was to replicate it. If a design decision is ambiguous, the tiebreaker is
what RepCount does. The eight non-negotiables are listed in `CLAUDE.md`; the first two matter most:

1. **One scrollable logging screen, no drill-down.** Every exercise and all its set rows inline. This is
   the single most-praised thing about RepCount and it dictates the view hierarchy. `ActiveWorkoutView`
   is built this way (verified: one `ScrollView`/`LazyVStack`, sheets only for picker/history/stats).
   Do not refactor toward per-exercise detail screens.
2. **Last session's numbers as placeholder text**, so an unchanged set is one tap. `PreviousPerformance`
   handles this and correctly excludes both unfinished workouts *and* the session being edited — that
   second exclusion is subtle and removing it would make a session prefill from its own empty rows.

---

## Decisions already made — don't relitigate without asking

- **HealthKit is out of scope.** Kai's explicit choice. The model keeps the door open; nothing blocks
  adding it later as a self-contained module.
- **No third-party dependencies.** Everything is first-party: SwiftUI, SwiftData, VisionKit, Swift
  Charts, Swift Testing.
- **XcodeGen, `.xcodeproj` gitignored.** Because Xcode can't be opened on this machine and hand-editing
  pbxproj is how that breaks.
- **Public repo**, which is what makes the macOS CI runners free.
- **SwiftData, not Core Data.** CloudKit private sync is a later flag; note that enabling it requires
  removing the `@Attribute(.unique)` on `FoodItem.barcode`, since CloudKit forbids unique constraints.
- **App named Tally**, bundle `com.yungsukuna.tally`.

---

## Things Kai still needs to do

- **USDA API key** (free, instant, ~2 min): https://fdc.nal.usda.gov/api-key-signup.html — then
  `cp Secrets.example.xcconfig Secrets.xcconfig` and paste it in. The app builds and runs without it;
  only USDA text search is disabled. Barcode scanning needs no key.
- **Open the project on his Mac** and run it on a device. Nothing has ever been seen rendering.
- **Test on a real phone**: scan an actual barcode, log a full workout and confirm the next session
  prefills from it, run a superset and a drop set, log water, check the Today totals.

---

## Honest assessment

The foundation is solid and verified — models, persistence, schema, utilities and both API clients all
passed CI green with 126 tests. The failures since are all the same category: Swift 6 strict concurrency
at the boundary between SwiftData's `@MainActor`-bound models and non-Sendable Apple framework types.
They're mechanical, they're surfacing one layer at a time, and each fix has revealed the next one
underneath.

What has *not* been verified is anything visual. Not one screen in this app has been rendered, ever.
Compiling is a low bar. Expect layout problems, spacing that looks wrong on a real device, and flows
that make sense in code and not in the hand — particularly in the workouts logging screen, where the
whole point is that it feels fast, and that cannot be assessed from a diff.
