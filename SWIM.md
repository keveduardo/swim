# Swim: a pool-swim watch app with Kevin's layout

Asked 2026-09-30. Apple's Workout app would not show the swim metrics in the
layout Kevin wanted, so this is a standalone watch app that records the same
workout with his own screen. Built and shipped exactly like Rowing
(`WORKOUTS.md` §4, "The build"): no Hub changes and no Mac. XcodeGen runs on a
GitHub macOS runner and the build goes to TestFlight.

## What Kevin asked for

- **Start screen:** Start, plus a pool button that opens a menu with three
  choices: **25 yd, 25 m, 50 m**. The last choice is remembered.
- **Live screen** (his mockup): Total Distance across the top; below it,
  **Total Set Time** (with hundredths) beside **heart rate** with
  **ZONE: REST / 1–5** and a coloured dot. Thin rules between.
- **Sets:** detected automatically.
- **Zones:** from his age in Health.
- **Total workout time:** yes. It sits in yellow beside the swimmer badge in the
  clock's row, so it is never read as the clock.
- **Ending:** swipe right for End, Pause and Water Lock, as in Rowing and
  Apple's app. A summary follows: distance, time, sets, average heart rate.

## How it works

| Piece | Where | Proven by |
|---|---|---|
| Pool lengths, unit display | `SwimKit/Pool.swift` | `swift test` on kevg10 |
| Set / rest split | `SwimKit/SetTracker.swift` | `swift test` |
| Heart zones from age | `SwimKit/HeartZone.swift` | `swift test` |
| Clock formats | `SwimKit/SwimClock.swift` | `swift test` |
| The workout (`HKWorkoutSession`, pool config) | `Apps/Swim/Sources/SwimSession.swift` | the runner's build |
| Screens | `Apps/Swim/Sources/SwimScreen.swift` | the `render` job's screenshots |

- **Lengths, distance and strokes are Apple's.** They come from an
  `HKWorkoutConfiguration` of `.swimming` / `.pool` with `lapLength` set. The
  live data source counts them as it does for the Workout app, and ends each
  length with a `.lap` event.
- **Rest is inferred, not detected.** Apple's motion-based rest detection is
  not offered to other apps. `SetTracker` calls it rest when no length has
  finished for **1.6 × the median recent length**, and never less than 30 s.
  So a rest shows about half a length late, but it is dated from the wall. The
  left cell then reads **Rest** and counts the rest. A fixed threshold
  (20 s was floated) would not work: a 50 m length takes longer than that.
- **Zones:** max HR = 208 − 0.7 × age (Tanaka). Zones are 10 % bands from 50 %,
  and below 50 % is REST. Apple's own zones are private to its app, so these
  can differ from what Fitness shows. With no birth date in Health, the zone
  line is hidden.
- **Water Lock** turns on at Start (`WKInterfaceDevice.enableWaterLock`). The
  Crown clears it.
- **Always-On:** the same layout, ticking once a second without hundredths.
- A swim with no distance and under a minute is discarded, not saved.

## Identifiers

- `com.brisaloca.swim`: the iOS stub container, and the App Store record.
- `com.brisaloca.swim.watchkitapp`: the watch app, **HealthKit on**.
- App record **Brisaloca Swim** `6817824465` (created on the website by
  Kevin, 2026-09-30). The internal TestFlight group **Household** and Kevin's
  place in it were both set up through the API.
- First TestFlight build: **4** (2026-09-30), expiring 2026-12-29 unless the
  weekly `due` job replaces it.
- CI: `.github/workflows/swim-watch.yml`, a copy of Rowing's, using the same
  repository secrets. The weekly `due` job reuses `tools/ci/rowing-due.mjs`
  with the swim bundle id.

## Not yet proven

None of this has been in water. The things to check on the first swim:

1. Lap events arrive per length, and whether they carry a start time.
2. The rest threshold feels right at the wall.
3. The clock-row header renders as in the mockup (see the render job).
