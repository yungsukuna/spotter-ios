# Handoff

Updated 2026-09-20 after the session that picked this up. Read `CLAUDE.md` first for the
conventions, then this for where things actually stand.

---

## The one thing to understand before touching anything

**This repo is authored on Windows. There is no Swift compiler on this machine.** Nothing here can be
compiled or run locally. The macOS GitHub Actions runner is the *only* verification that exists, and it
takes 4–5 minutes per run.

That shapes the whole workflow. The loop is: read the CI annotations (and the test log, once the
build is passing), fix, push, wait, repeat. Do not guess at a fix and move on — push it and confirm.

Kai has a Mac, so the faster loop is available if he's at it: `xcodegen generate && open Tally.xcodeproj`
surfaces every error at once instead of one CI round-trip at a time. **Ask before assuming he'll do
that** — he hasn't opened the project in Xcode yet at time of writing.

---

## Current state

Repo: **https://github.com/yungsukuna/tally-ios** (public), local at `C:\Users\Kai\Documents\GitHub\tally-ios`.

`gh` CLI is installed at `C:\Program Files\GitHub CLI\gh.exe` and authenticated as **yungsukuna** with
`repo` + `workflow` scopes. **It is not on PATH in the Bash tool** — invoke it by full path:

```bash
GH="/c/Program Files/GitHub CLI/gh.exe"; "$GH" run list --limit 3
```

On PowerShell:

```powershell
& "C:\Program Files\GitHub CLI\gh.exe" run list --limit 3
```

### CI status

Run `35490081444` (handoff-notes commit) **compiled the workouts layer for the first time** and ran
218 tests. The `#require` caching-test fix held. Five assertions failed, all test bugs rather than
product bugs:

- `RestTimerController.start` always cancels before scheduling, so a later `addTime` / `skip` makes
  `cancelledIdentifiers.count == 2`, not 1.
- `WorkoutStatsCalculatorTests.logSession` called `complete()` with the default `Date()`, so every
  historical set stamped as today and `groupedByDay` collapsed two sessions into one point of 1025 kg.

Those tests are fixed. Remaining handoff items also landed in the same push:

- Food-tab `DayTotals` now uses `effectiveKcal`, matching the Today tab.
- `TallyApp` wires `OpenFoodFactsClient` + `USDAFoodDataCentralClient` through `CompositeFoodDataSource`.
- `AddFoodView` presents `BarcodeScannerView`, looks up via `CachingFoodRepository`, and routes to
  the portion picker or `CustomFoodEditorView` (`ScannedProductLookup`).
- `actions/checkout@v5`.

**Confirm the run that follows this push is green before starting anything new.**

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

### 1. Confirm this push is green (do this first)

The previous run compiled and ran 218 tests; the five failures were test-expectation mismatches,
now fixed, plus the remaining integration work. If the new run is red, read the annotations (filter
CoreData noise — see below) and the test log, not `gh run view --log-failed` alone.

### 2. Workouts compiled once, still never rendered

`Tally/Features/Workouts/` compiled on run `35490081444`. Charts, optional-enum pickers, and
`EditButton` / `.onMove` did not fail the build. That is a compile bar, not a visual one. Nothing in
this app has ever been seen on a device or simulator UI.

### 3. Smaller items

- Two `AVCaptureSession` non-Sendable capture **warnings** remain in
  `MetadataCaptureScannerRepresentable.swift`. Non-blocking. `nonisolated(unsafe)` on the property
  didn't silence them; properly fixing means confining the session to an actor.
- No app icon — `Assets.xcassets/AppIcon.appiconset` is an empty placeholder.
- `README.md` says the licence is TBD. **Ask Kai**, don't pick one.
- Changing the Open Food Facts contact in Settings does not rebuild `OpenFoodFactsClient` until the
  next launch. Fine for now.

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

The foundation is solid, and the workouts layer has now compiled. Run `35490081444` executed 218 tests;
the five failures were test-expectation mismatches (rest-timer cancel counts, stats helper stamping
`complete()` as now). Remaining integration seams (real food clients, scanner, calorie-progress
agreement) are in this push and need a green run to count as verified.

What has *not* been verified is anything visual. Not one screen in this app has been rendered, ever.
Compiling is a low bar. Expect layout problems, spacing that looks wrong on a real device, and flows
that make sense in code and not in the hand — particularly in the workouts logging screen, where the
whole point is that it feels fast, and that cannot be assessed from a diff.
