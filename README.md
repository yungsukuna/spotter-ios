# Spotter

Spotter is a code name; the final App Store name is undecided.

An iOS app for tracking calories, workouts and water in one place.

- **Food** — manual entry, barcode scanning, and search over generic foods.
- **Workouts** — a full strength-training log, modelled closely on [RepCount](https://www.repcountapp.com/):
  one scrollable logging screen, last session's numbers prefilled, rest timer, supersets, drop sets,
  routines, and progress charts.
- **Water** — manual logging with quick-add presets.

iPhone only, iOS 18+. No accounts, no subscription, no third-party dependencies.

---

## Getting started (macOS)

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

The `.xcodeproj` is **not** committed — it is generated from [`project.yml`](project.yml):

```bash
xcodegen generate && open Spotter.xcodeproj
```

Re-run `xcodegen generate` after pulling changes that add files. Because source paths in `project.yml`
are directory globs, adding a Swift file never requires editing the project spec — create the file and
regenerate.

### Running the tests

```bash
xcodebuild test -project Spotter.xcodeproj -scheme Spotter -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs the same thing on every push, resolving an available simulator automatically via
[`Scripts/select-simulator.py`](Scripts/select-simulator.py).

---

## Configuration

The app builds and runs with no configuration. Barcode scanning works out of the box; only USDA text
search needs a key.

To enable it, get a free key from [FoodData Central](https://fdc.nal.usda.gov/api-key-signup.html),
then:

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
```

and put your key in it. `Secrets.xcconfig` is gitignored. The value travels
`Secrets.xcconfig` → `Config/App.xcconfig` → `Info.plist` → `AppConfiguration.usdaAPIKey`.

---

## Architecture

```
Spotter/
├─ App/          Entry point, tab shell, dependency injection
├─ Core/
│  ├─ Models/        SwiftData @Model types
│  ├─ Persistence/   Schema, container, seeded exercise library
│  ├─ Design/        Theme tokens and shared modifiers
│  └─ Utils/         Day keys, unit conversion, strength maths, formatting
├─ Features/     One folder per tab
└─ Services/     Food data clients, barcode scanning
```

Conventions worth knowing before changing anything:

**Everything is stored in metric.** Weights in kilograms, volumes in millilitres, circumferences in
centimetres. Units are a display preference, converted at the view layer by `UnitConverter`. Nothing
persists a converted value, because that would mean a preference change either rewrites the database
or silently reinterprets old rows.

**Diary entries snapshot their nutrition.** A `DiaryEntry` copies the food's name and computed
nutrition at the moment it is logged rather than reading through to the `FoodItem`. Open Food Facts is
crowd-edited and USDA records get revised; a correction upstream must never rewrite what last month's
diary says you ate.

**SwiftData relationships are unordered.** Every to-many relationship carries an explicit `order: Int`
on the child, and parents expose an `orderedX` accessor. Read through the accessor; never trust the
raw array's sequence.

**Enums persist as raw strings.** Stored as `somethingRaw: String` with a computed typed accessor.
SwiftData can persist `Codable` enums directly, but `#Predicate` support for them is unreliable and
this app filters on them constantly.

**Nutrition values are optional, and `nil` means unknown.** It does not mean zero. A product with no
fibre figure must not start claiming it contains none. `Nutrients` preserves this distinction through
scaling and summing.

---

## Data sources and attribution

### Open Food Facts

Barcode lookups come from [Open Food Facts](https://world.openfoodfacts.org). The database is licensed
under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/); individual
contents are under the Database Contents License, and product images are CC-BY-SA.

**ODbL carries attribution and share-alike obligations.** Any build distributed to other people must
credit Open Food Facts visibly — the app does this in Settings → About, and that screen is not
optional.

Two API constraints the client must respect, both of which will get an app blocked if ignored:

- **A descriptive `User-Agent` is required** in the form `AppName/Version (contact)`. Anonymous traffic
  can be refused.
- **15 product reads per minute per IP.** Every fetched product is cached locally, so repeat scans cost
  nothing and work offline.

### USDA FoodData Central

Generic food search comes from [FoodData Central](https://fdc.nal.usda.gov/), which is US Government
work released as **CC0 / public domain** — no attribution required, though it is credited anyway.
Free tier is 1,000 requests per hour with a registered key.

---

## Status

Early. The foundation — data model, persistence, design system, service contracts, CI — is in place;
the feature screens are being built on top of it.

## Licence

TBD.
