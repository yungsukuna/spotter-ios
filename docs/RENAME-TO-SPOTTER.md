# Rename: Tally → Spotter

**Goal:** the app's code name becomes **Spotter** everywhere in the repository — product name, bundle IDs,
App Group, Xcode targets and scheme, source folders, type names, strings and docs. Nothing called
"Tally" should remain except the deliberate exceptions listed below.

Nothing has shipped and no device has installed the app, so there is no user data, no App Store record
and no provisioning to migrate. That makes this the cheapest moment the rename will ever have.

Scope measured on `86ed5a1`: 259 matching lines across 113 files.

---

## Deliberate exceptions — do NOT change

| Reference | Why it stays |
|---|---|
| `github.com/yungsukuna/tally-ios` (README, `AppConfiguration.openFoodFactsUserAgent` fallback contact, HANDOFF) | That is the repo's real URL. Renaming the GitHub repo is a separate, manual step for Kai; GitHub redirects the old URL afterwards, and these can be updated then. |
| The local checkout path `C:\Users\Kai\Documents\GitHub\tally-ios` in HANDOFF.md | Real path on disk. |
| The word "totally" | Not the app name. |
| Git history, commit messages, PR titles | History isn't rewritten. |

Everything else changes.

---

## 1. Directory renames

Use `git mv` so history follows the files:

| From | To |
|---|---|
| `Tally/` | `Spotter/` |
| `TallyTests/` | `SpotterTests/` |
| `TallyWidgets/` | `SpotterWidgets/` |
| `Spotter/App/TallyApp.swift` (after the move above) | `Spotter/App/SpotterApp.swift` |
| `Spotter/Core/Persistence/TallySchema.swift` | `Spotter/Core/Persistence/SpotterSchema.swift` |
| `SpotterWidgets/TallyWidgetsBundle.swift` | `SpotterWidgets/SpotterWidgetsBundle.swift` |

Any other file whose name contains "Tally" gets the same treatment. Check with
`git ls-files | grep -i tally` afterwards; it must print nothing.

`Shared/` keeps its name.

## 2. `project.yml`

This is the second sanctioned edit to `project.yml`, reviewed in this PR.

- `name: Tally` → `name: Spotter`. This makes the generated project `Spotter.xcodeproj`.
- `bundleIdPrefix: com.yungsukuna` is unchanged.
- **Targets:**
  - `Tally` → `Spotter`
  - `TallyWidgets` → `SpotterWidgets`
  - `TallyTests` → `SpotterTests`
  - Update every reference to them: `dependencies: - target:`, the test target's dependency on the app, and the scheme's `build.targets` / `test.targets`.
- **Scheme:** `schemes: Tally:` → `Spotter:`.
- **Source paths:**
  - `- path: Tally` → `- path: Spotter`
  - `- path: TallyWidgets` → `- path: SpotterWidgets`
  - `- path: TallyTests` → `- path: SpotterTests`
  - The four individual shared files `Tally/Core/...` → `Spotter/Core/...`
- **Bundle IDs:**
  - `com.yungsukuna.tally` → `com.yungsukuna.spotter`
  - `com.yungsukuna.tally.widgets` → `com.yungsukuna.spotter.widgets`
  - `com.yungsukuna.tally.tests` → `com.yungsukuna.spotter.tests`
- **App Group** (both entitlements blocks): `group.com.yungsukuna.tally` → `group.com.yungsukuna.spotter`
- **Product names:**
  - `PRODUCT_NAME: Tally` → `Spotter`
  - `PRODUCT_NAME: TallyWidgets` → `SpotterWidgets`
- **Info.plist paths:**
  - `Tally/Info.plist` → `Spotter/Info.plist`
  - `TallyWidgets/Info.plist` → `SpotterWidgets/Info.plist`
- **Entitlements paths:**
  - `Tally/Tally.entitlements` → `Spotter/Spotter.entitlements`
  - `TallyWidgets/TallyWidgets.entitlements` → `SpotterWidgets/SpotterWidgets.entitlements`
- **Display name:** `CFBundleDisplayName: Tally` → `Spotter` (both targets).
- `NSCameraUsageDescription` text: "Tally uses the camera…" → "Spotter uses the camera…"
- Update every comment that says Tally.

## 3. `.gitignore` and CI

- `.gitignore`: update the generated-file paths, i.e. `Tally/Info.plist`, `TallyWidgets/Info.plist` and both `.entitlements` paths, to their Spotter equivalents.
- `.github/workflows/ci.yml`: `-project Tally.xcodeproj -scheme Tally` → `-project Spotter.xcodeproj -scheme Spotter`, in both `xcodebuild` steps.
- `Scripts/select-simulator.py`: check it for any Tally reference (none expected).

## 4. Swift identifiers

Rename the declaration and every use:

| From | To |
|---|---|
| `TallyApp` | `SpotterApp` |
| `TallySchema` | `SpotterSchema` |
| `TallyBackup` | `SpotterBackup` |
| `TallyWidgetsBundle` | `SpotterWidgetsBundle` |
| `tallyCard(padding:)` (View extension in `Theme.swift`) | `spotterCard(padding:)` |
| `@testable import Tally` (every test file) | `@testable import Spotter` |

The `@testable import` module name is the app target's product module name. It changes because the
target and `PRODUCT_NAME` change, so every test file must be updated or nothing compiles.

Afterwards, `git grep -n "Tally"` over `*.swift` files must show only the exceptions in the table at
the top.

## 5. Strings and identifiers inside the code

- **App Group constant** in `Shared/WidgetSnapshot.swift`: → `group.com.yungsukuna.spotter`. It must match `project.yml` exactly.
- **Rest-timer notification ID** `com.tally.workouts.rest-timer` → `com.spotter.workouts.rest-timer`.
- **Backup file name** `Tally-Backup-yyyy-MM-dd.json` → `Spotter-Backup-yyyy-MM-dd.json`. Update the tests that assert it.
- **Open Food Facts User-Agent** `"Tally/\(appVersion) (...)"` → `"Spotter/\(appVersion) (...)"`. The fallback contact URL stays (see exceptions). Update any test asserting the User-Agent string.
- **CloudKit container comment** `iCloud.com.yungsukuna.tally` → `iCloud.com.yungsukuna.spotter`.
- **User-visible text:** Settings > About, empty states, widget/Live Activity titles, `.configurationDisplayName` / `.description` in the widget, and the notification body if it names the app. Every "Tally" → "Spotter".
- `UserDefaults` / `@AppStorage` keys: rename any key containing "tally". Nothing is installed anywhere, so there's no migration.
- `Logger` / `os_log` subsystems, if any: → `com.yungsukuna.spotter`.

## 6. Docs

- `README.md`: title and body → Spotter. Commands become `open Spotter.xcodeproj` and `-scheme Spotter`, and the architecture tree becomes `Spotter/`. Keep the repo URL.
- `CLAUDE.md`: title "Tally — working notes" → "Spotter — working notes". Update paths (`Core/Models/`, `TallySchema.models` → `SpotterSchema.models`, `TallySchema.makeContainer` / `previewContainer`) and the preview snippet.
- `HANDOFF.md`, `ROADMAP.md`, `docs/PHASE2-PLAN.md`: product name and file paths → Spotter (`Tally/Features/...` → `Spotter/Features/...` and so on). Keep the repo URL and the local disk path.
- Add a line to README under the title: *"Spotter is a code name; the final App Store name is undecided."*

## 7. Verification (the agent does this before reporting)

1. `git ls-files | grep -i tally` prints nothing.
2. `git grep -in tally` prints only lines covered by the exceptions table. Include that output in the report.
3. `project.yml` references resolve: every `path:` exists on disk after the moves, and every `target:` name matches a declared target.
4. The App Group string is identical in `project.yml` (both targets) and `Shared/WidgetSnapshot.swift`.
5. Every test file imports `Spotter`, not `Tally`.

CI is the real check: it regenerates the project from `project.yml`, builds both targets, and runs all
379 tests.

## Out of scope — Kai does these manually, afterwards if wanted

- Renaming the GitHub repo `tally-ios` → `spotter-ios` (Settings → Rename). GitHub redirects the old URL. Afterwards, `git remote set-url origin …` locally and update the kept URLs.
- Renaming the local folder `C:\Users\Kai\Documents\GitHub\tally-ios`.
- Registering the new bundle ID and App Group in the Apple developer portal. Xcode's automatic signing does this on first device run.
