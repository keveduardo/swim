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
  **Water Temp** beside **heart rate** with **ZONE: REST / 1–5** and a
  coloured dot. Thin rules between. (The mockup had **Total Set Time** in the
  left cell; Kevin swapped it for the water temperature later on 2026-09-30,
  so no set or rest clock is on screen. Sets are still counted for the
  summary.)
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
- **Water temperature** is the watch's own: an Ultra writes
  `waterTemperature` samples while submerged. The app reads them two ways:
  from the workout builder, as it reads heart rate (the live data source is
  told to collect the type), and from Health with an anchored query from Start
  (`SwimSession.watchWater`). The query alone showed nothing on the first swim.
  Shown in whole degrees, °F or °C by region; "--" until a reading arrives,
  and always on a watch without the sensor.
- **Water Lock** turns on at Start (`WKInterfaceDevice.enableWaterLock`). The
  Crown clears it.
- **Always-On:** the same layout; the page ticks once a second either way now that no hundredths are on it.
- A swim with no distance and under a minute is discarded, not saved.

## The water temperature, as it stands (2026-10-02)

Three sources, because the first two are not live:

1. **The water sensor itself** — `CMWaterSubmersionManager`
   (`SwimSession.watchSensor`, build 18). The only one that is live by design:
   about three readings a second while submerged. Needs the Shallow Depth and
   Pressure capability (now on `com.brisaloca.swim.watchkitapp`; Xcode's
   automatic signing switched it on at the first signed build that asked) and
   `NSMotionUsageDescription` — the app crashes creating the manager without
   that string. **No `underwater-depth` background mode**; that is the thing
   to try next if a swim still shows "--". ⚠️ Unproven in water.
2. **The workout builder** — the data source is told to collect
   `waterTemperature` (build 14).
3. **Health** — an anchored query from Start (build 9).

What the swims showed: build 11 (query only) nothing; build 14, 2026-10-01,
Kevin said it worked; build 14, 2026-10-02, nothing during the workout. Health
held the reading afterwards each time, so the watch records it and writes it
late. Sources 2 and 3 now mostly serve the summary, which also takes a reading
that reaches the builder only as the swim ends.

**App Review has build 14.** Build 18 is TestFlight only until a swim proves
it; then it replaces 14 on the version (which means taking the version out of
review and submitting again).

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

**First swim, 2026-10-01 (build 11).** Kevin: "overall it worked well", except
that the water temperature neither showed nor was recorded — the cell read
"--" throughout. He did not go through the items below one by one, so 1–3
stand as "nothing complained of", not as checked.

1. Lap events arrive per length, and whether they carry a start time.
2. The rest threshold feels right at the wall.
3. The clock-row header renders as in the mockup (see the render job).
4. **The water temperature actually appears.** ❌ on the first swim, when the
   app only queried Health for the samples. The build after it also reads them
   from the workout builder, and ✅ on Kevin's second swim the same day
   (build 14: "i did swim and it works"). What tells the two
   failures apart: iPhone **Health → Browse → Other Data → Water Temperature**.
   A reading from the time of that swim means the watch records it and the app
   was reading it wrongly; none means the watch does not record it for a
   third-party workout, and what is left is Core Motion's
   `CMWaterSubmersionManager`. That needs the Shallow Depth and Pressure
   capability (no approval from Apple, to 6 m), `NSMotionUsageDescription`
   (the app crashes without it), and the `underwater-depth` background mode,
   which puts the app on the watch's auto-launch list and holds it frontmost
   as a dive app — a real change, not a quiet fallback.
