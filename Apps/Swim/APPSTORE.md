# Swim — App Store Connect listing

Drafted 2026-09-30, in the shape of `Apps/Rowing/APPSTORE.md`. Everything in
the tables and quoted blocks below was written into App Store Connect through
the API the same day (app `6817824465`, version 1.0); this file is the record
of what was sent and the place to edit it before sending again.

---

## App information

| Field | Value |
|---|---|
| Name (30) | Brisaloca Swim |
| Subtitle (30) | Pool swims, your own layout |
| Category | Health & Fitness (secondary: Sports) |
| Content rights | Does not contain third-party content |
| Age rating | "None"/No to everything except **Health or Wellness Topics: yes** (it is a workout recorder) |
| Copyright | 2026 Kevin Amaya |
| Privacy policy URL | https://brisaloca.com/swim/privacy/ |
| Support URL | https://brisaloca.com/swim/support/ |
| Marketing URL | (blank) |
| Price | Free |
| Release | Manual, after approval |

## Promotional text (170)

A pool-swim workout with a screen you can read at the wall: total distance on top, water temperature and heart-rate zone beneath. Saved to Apple Health.

## Description (4000)

Brisaloca Swim records a pool swim as an Apple Watch workout, on a screen laid out to be read in one glance at the wall.

THE SCREEN
• Total distance across the top, in the largest type on the page
• Water temperature, on Apple Watch models that measure it
• Heart rate, with your zone — REST or 1 to 5 — and a colored dot
• Total workout time in the top corner

HOW IT WORKS
Choose your pool — 25 yd, 25 m or 50 m — and tap Start. Your watch counts lengths and distance the way it does for any pool swim, and the screen locks against water. Swipe right for End, Pause and Lock.

When you finish you see the swim's distance, time, number of sets, average heart rate and the water temperature. Sets are found automatically from your rests at the wall.

SAVED TO HEALTH
Each swim is saved to Apple Health as a pool swim, with its distance, strokes and active energy. It appears in Fitness on your iPhone and counts toward your Activity rings.

HEART-RATE ZONES
Zones are estimated from your age in Health, so they can differ from the zones Apple's Fitness app shows.

WATCH ONLY
There is no iPhone app to open and no account to create.

PRIVATE
No sign-in, no ads, no analytics, no server. Nothing leaves your watch except what you allow into Apple Health.

REQUIREMENTS
An Apple Watch running watchOS 11 or later. Water temperature needs a watch with a water temperature sensor, such as Apple Watch Ultra.

## Keywords (100)

swim,swimming,pool,laps,lengths,workout,heart rate,zones,water temperature,yards,meters,fitness

## What's New

First release (the field does not exist on a first version).

---

## App Review information

**Sign-in required: no.**

**Notes (4000):**

> Brisaloca Swim is a watch-only app. The iOS target is the stub container
> every watch-only app ships in; there is no iPhone app and nothing to open on
> the phone.
>
> TO TRY IT: open Swim on the watch, tap the pool button to choose a length,
> tap Start, and allow Health. The live screen appears and Water Lock turns on;
> press and hold the Digital Crown to unlock, swipe right, and tap End. A swim
> under a minute with no lengths is discarded ("Nothing to save"), so nothing
> is written to Health by a quick test on dry land.
>
> No pool is needed to see the app work. Lengths and distance are counted by
> the system's own pool-swim workout (HKWorkoutConfiguration, .swimming,
> .pool, with the chosen lap length), so they advance only while actually
> swimming. Water temperature shows "--" out of the water and on watches
> without the sensor.
>
> HEALTHKIT. Writes: the workout, active energy, swimming distance, stroke
> count. Reads: heart rate, swimming distance, stroke count, active energy and
> water temperature, to display them during the swim; and date of birth, only
> to estimate heart-rate zones from age. Health data is not sent anywhere; the
> app has no server and makes no network requests.
>
> BACKGROUND MODE. workout-processing, so the workout session keeps running
> with the wrist down.
>
> No account, no sign-in, no purchases, no ads, no analytics.

**Contact:** the same contact as Soccer's review detail (copied by API).

---

## App Privacy (the questionnaire — website only, the API cannot set it)

**Data collection: No, we do not collect data from this app.** No server, no
network code; Health data stays in Health. Matches brisaloca.com/swim/privacy.

Also website-only, and required before a Health & Fitness app can be added to
a submission: **App Information → Regulated Medical Device → No**.

## Screenshots

Apple Watch only. Uploaded at 410 × 502 (Apple Watch Ultra), from the `render`
job of `swim-watch.yml` — the real SwiftUI in a simulator with fixed demo
numbers: the live page (200 YD, 82°F, zone 3), the start page, the controls
page and the summary.

## Known before submitting

- ⚠️ **Nothing in this app has been in water** (`SWIM.md`, "Not yet proven"):
  not the lap events, not the set/rest split, and not the water temperature,
  which depends on the watch recording it during a third-party workout.
- The app keeps one preference on the watch (the last pool), in UserDefaults
  via `@AppStorage`. `Resources/PrivacyInfo.xcprivacy` declares it (required-
  reason `CA92.1`); it was added for this submission, so the build attached is
  the first one that carries it.
