# Swim — App Store Connect listing

Drafted 2026-09-30, in the shape of `Apps/Rowing/APPSTORE.md`. Everything in
the tables and quoted blocks below was written into App Store Connect through
the API the same day (app `6817824465`, version 1.0); this file is the record
of what was sent and the place to edit it before sending again.

Distribution: **Unlisted** (Kevin, 2026-09-30), like Soccer and Español —
request at developer.apple.com/contact/request/unlisted-app once it is
submitted; it goes through the same review.

**SUBMITTED 2026-10-01 18:59 UTC — version 1.0, build 14, manual release.**
Submission `8d040149-d9ac-4b0d-b90f-4c85d19aadfe`, WAITING_FOR_REVIEW. Kevin
swam with build 14 the same day and the water temperature showed ("i did swim
and it works. lets submit"), which is what the submission was waiting for.
Build 14 replaced 11 on the version; the Notes gained an "ABOUT THE APP"
section answering the Guideline 2.1 questions ahead of time. A cropped
dry-land recording is at `~/Downloads/review/swim-review.mp4` if App Review
asks for one (it ends on "Nothing to save"). **Unlisted request sent
2026-10-01** (developer.apple.com/contact/request/unlisted-app; Kevin OK'd the
acknowledgement); Apple answers by email. As answered: organization type Other
— "A single household (one family)"; Internally; 4 people, 1 organization;
audience Other — "Members of one household"; category Other — "Fitness
(workout recording)"; Unmanaged, 4 devices; USA. On that form the tick boxes
only take through the form-fill tool — clicks on them do not register.

**REJECTED 2026-10-01 20:45 PT** (boilerplate Guideline 2.1 "Information
Needed – New App Submission", nothing wrong found). **RESUBMITTED 2026-10-07
20:01 PT, still build 14**: reply with the six answers and the dry-land
recording, Notes updated to match. Unlisted approved 2026-10-06 (case
102982837254). Build 20's summary additions ship as 1.0.1 after approval;
bump the plist to 1.0.1 and rebuild first.

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

- **Two swims, 2026-10-01.** Build 11: everything worked except the water
  temperature, which never appeared. Build 14 (reads it from the workout
  builder): Kevin reports it works. Build 14 is the one in review.
- The app keeps one preference on the watch (the last pool), in UserDefaults
  via `@AppStorage`. `Resources/PrivacyInfo.xcprivacy` declares it (required-
  reason `CA92.1`); it was added for this submission, so the build attached is
  the first one that carries it.

---

## 1.0.1 (prepped 2026-10-07): build 24

The code shipped as TestFlight build 20 (fe042b3), rebuilt with
`MARKETING_VERSION` 1.0.1 because build 20's plist says 1.0, which would fail
with ITMS-90062. The ASC version cannot be created until 1.0 is approved and
released. After that: create version 1.0.1, attach the new build, set What's
New, and submit with manual release.

Also in this build, still untested in the water: the live water temperature
is read straight from the sensor through CMWaterSubmersionManager (build 18).
What's New does not claim it until a swim shows it.

### What's New (4000)

The end-of-swim summary now shows more:
• Pace per 100, timed while swimming, with rests left out
• SWOLF
• Active calories
• Distance swum in each stroke (freestyle, breaststroke and so on)
