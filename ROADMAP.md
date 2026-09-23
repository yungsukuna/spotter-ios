# Roadmap

Where Spotter is going, in order. Read `README.md` and `CLAUDE.md` first for how the app is built today.

The rule for this document: **nothing in Phase 3 starts until Phases 1 and 2 are done and the app has
been used day-to-day on a real phone.** Social features multiply every rough edge in the single-player
app, so the single-player app has to be good first.

---

## Phase 1 — Make it run and feel right on a real phone

The app compiles and 200+ logic tests pass in CI, but no screen has ever been rendered. This phase is
about closing that gap.

### Needed to run it

- **Simulator:** nothing extra. `brew install xcodegen && xcodegen generate && open Spotter.xcodeproj`, pick
  an iPhone simulator, Run.
- **Your own iPhone:** a signing team. Don't set it in Xcode's Signing tab — `xcodegen generate` wipes it
  on every regenerate. Put it in the gitignored `Secrets.xcconfig` instead (already included by
  `Config/App.xcconfig`):

  ```
  DEVELOPMENT_TEAM = ABCDE12345
  ```

  With a free Apple ID the install expires after 7 days; a paid developer account lasts a year and is
  needed for TestFlight anyway.
- **USDA key** (optional): only needed for text search of generic foods. Barcode scanning works without it.
- **Camera / barcode scanning** only works on a real device, not the simulator.

### Known gaps found in code review (no Mac needed to fix)

| Gap | Where | Why it matters |
|---|---|---|
| Rest timer ends silently in the foreground | `RestTimerBar`, `ActiveWorkoutView` | The bar is only shown while `.running`, so on `.finished` it just disappears. iOS suppresses the local notification while the app is open (no `UNUserNotificationCenterDelegate`). Needs a haptic + sound on finish. |
| Rest notification can outlive a skip | `SystemRestTimerNotifier` | Scheduling happens in an unstructured `Task` after an `await` on permissions. A skip that lands first cancels nothing, then the notification is added anyway. Most likely on the very first set, while the permission prompt is up. |
| 1RM formula setting is ignored | `ExerciseStatsView` | Settings lets you pick Epley/Brzycki, but the stats screen never passes it through, so it's always Epley. |
| Cardio and body measurements have models but no UI | `CardioEntry`, `BodyMeasurement` | Schema exists, nothing creates or displays them. |
| No app icon | `Assets.xcassets/AppIcon.appiconset` | Empty placeholder. |
| Licence is TBD | `README.md` | Needs a decision before anyone else touches the code. |

### Hands-on checklist (needs the phone)

- Scan a real barcode; log it; edit the portion.
- Log a full workout, finish it, start the same routine again — confirm last session's numbers show as
  placeholders and one tap completes an unchanged set.
- Run a superset and a drop set.
- Lock the phone during a rest timer — confirm the notification fires.
- Log water from a preset; check the Today totals match the Food and Water tabs.
- Switch to lb / fl oz and back — confirm nothing stored changes.

---

## Phase 2 — Flesh out the single-player app

Suggested features, roughly in priority order. The first three are the ones that most change whether
the app gets used every day.

1. **Body weight tracking + trend line.** The `BodyMeasurement` model is already there. A weigh-in
   screen and a smoothed trend chart is the thing calorie trackers are ultimately judged on.
2. **Backup and export.** Everything is local-only today; deleting the app deletes the history. A JSON
   export via `ShareLink` is cheap insurance. Longer-term, turn on CloudKit private sync (see the note in
   `SpotterSchema` — the unique constraint on `FoodItem.barcode` has to go first).
3. **Faster food logging.** Copy yesterday's meal / a whole meal from any day, saved "meals" (a group
   of foods logged in one tap), and quick-add calories without a food record.
4. **Goal helper.** Compute a calorie and protein target from weight, height, age, activity and goal
   (lose / maintain / gain), instead of making people type numbers in.
5. **Cardio logging** using the existing `CardioEntry` model — time, distance, rough calorie burn.
6. **Workout extras from RepCount:** plate calculator, warm-up set generator, per-exercise rest time
   overrides, RPE/RIR on sets, notes per exercise.
7. **Streaks and weekly summary** on Today — days logged, workouts this week, water goal hit rate.
   These are also exactly the signals Phase 3 shares at the "minimal" level, so building them now pays
   twice.
8. **Widgets and Live Activity.** A Lock Screen Live Activity for the rest timer is the single most
   useful one; a Home Screen widget for calories/water remaining is the second.
9. **Reminders:** optional nudges to log water or meals.

HealthKit stays out of scope unless that decision is revisited.

---

## Phase 3 — Social (the end goal)

### The idea

Spotter becomes something you can share with people who keep you honest. You choose **who** can see your
profile and **how much** they can see. Friends check that you trained today; a coach sees every set and
every meal of every client and can comment on them.

### Who it's for

- **Friend groups / training partners** — light accountability. "Did Sam train today? Did they hit
  protein?"
- **Anyone you invite** — a partner, a sibling, a gym buddy. Access is always opt-in and per person.
- **Coaches** — one coach, many clients. A dashboard of everyone, flagged by who's off track, with the
  ability to drill into any client's full log and leave feedback.

### Access levels

Access is granted **by the owner, per viewer**, and can be changed or revoked at any time. Levels are
set per category (training, nutrition, water, body weight), so someone can share full workouts but only
"yes/no" on food.

| Level | What the viewer sees | Example |
|---|---|---|
| **None** | Nothing in that category. | Default for everything. |
| **Check-in** | Did it happen today / this week. Streaks. No numbers. | "Worked out ✓ · Logged food ✓ · Water goal ✗" |
| **Summary** | Totals and trends. | Calories vs goal, macros, workout name + duration + total volume, weekly averages. |
| **Full detail** | Everything. | Every exercise, set, rep and weight; every food and portion; PRs; body weight. |

Presets make this easy to set up: **Friend** (check-in across the board), **Training partner** (full
training, check-in elsewhere), **Coach** (full everything).

### Features

- **Profiles** — name, photo, optional bio/goal, and the parts of your activity the viewer is allowed
  to see.
- **Connections** — invite by link or username; the owner approves; the owner picks the access level.
  Connections are one-directional: me sharing with you doesn't mean you share with me.
- **Groups** — a set of friends who share at the same level with each other, with a group view of
  today's check-ins.
- **Comments and reactions** on a workout, a day of food, or a single meal. Owner can delete any comment
  on their own data.
- **Feed** — recent activity from the people who share with you, filtered by what each has allowed.
- **Coach dashboard** — list of clients with at-a-glance status (trained? logged? on target?), sorted by
  who needs attention; tap in for the full log. Later: coach-assigned routines and nutrition targets
  that land in the client's app.
- **Notifications** — new comment, new connection request, a client missed N days.
- **Privacy controls** — revoke anyone instantly, hide a single day or workout, pause sharing, delete
  account and all server data.

### How it should be built (decisions to make before starting)

- **Stay local-first.** SwiftData on the phone stays the source of truth, so the app keeps working
  offline and the single-player app doesn't get slower. Sharing *publishes* a copy of your data to a
  server; it doesn't move your data there.
- **A real backend is required.** Profiles, cross-user permissions, comments and a coach seeing many
  clients don't fit CloudKit private sync. CloudKit sharing (`CKShare`) can do simple one-to-one
  shares but gets awkward for discovery, groups and coach dashboards. A hosted Postgres with row-level
  security (e.g. Supabase) or a small custom API is the likely fit — called with plain `URLSession`, so
  the app still has no third-party packages.
- **Enforce access on the server, never in the app.** If a viewer only has "check-in" access, the server
  must not send them the sets and reps at all. Filtering in the client means anyone with a proxy can
  read everything.
- **Sign in with Apple** for accounts. Accounts are only needed once you turn sharing on; the app keeps
  working with no account for people who never use social.
- **Schema groundwork.** Every model already has a stable `UUID` `id`, which is the most important part.
  Sync will also need an `updatedAt` on each model and a way to record deletions, and the schema will
  need to move to a versioned `VersionedSchema` + migration plan so existing users' data upgrades
  cleanly. That's a change to `Core/Models/`, so it's a deliberate, one-time step at the start of
  Phase 3, not something to sneak in earlier.
- **Health data is sensitive.** Body weight and food logs count as health information in a lot of
  places. Plan for a privacy policy, data deletion on request, and App Store privacy labels before any
  of this ships.
- **Open Food Facts licence.** ODbL share-alike may apply to food data you redistribute to other users.
  Check this before shipping shared food logs.
