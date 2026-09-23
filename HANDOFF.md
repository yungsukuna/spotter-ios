# Handoff

Updated 2026-09-23. Read `CLAUDE.md` first for the
conventions, then this for where things actually stand.

---

## Where things stand

Updated 2026-09-23. The repo now lives on a Mac (Xcode 26.6, iOS 26.5 simulator), so the Windows /
CI-only workflow described in earlier versions of this file is gone: build, test and run locally. The
full suite (390+ tests) passes locally, and CI still runs the same thing on every push.

The minimum deployment target is **iOS 26**. The app is primarily for Kai's own use, and dropping iOS
18 removes every `#available` branch from the upcoming Liquid Glass / AlarmKit work.

`gh` is on PATH and authenticated as **yungsukuna**.

---

## Known remaining work

### 1. Workout logging fixes (PR #7)

The first simulator run found lost set input, an un-dismissable number pad, edge-to-edge cards, empty
sets being completable, and a rest timer that outlived its workout. Fixed in
https://github.com/yungsukuna/spotter-ios/pull/7. The Live Activity and keep-awake changes still need
checking on a real device.

### 2. RepCount-style workout screen redesign

Next up, on iOS 26 APIs: glass rest-timer bar or `tabViewBottomAccessory`, column headers and units in
set rows, a keyboard Next/Done bar, set-type menu on the set number, swipe to delete, exercise reorder.
Also still open from the review: a `VersionedSchema` + migration plan before any TestFlight build
(the store fails with `fatalError` on open), and `PreviousPerformance` being recomputed per set row per
render.

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
- **App named Spotter**, bundle `com.yungsukuna.spotter`.

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
