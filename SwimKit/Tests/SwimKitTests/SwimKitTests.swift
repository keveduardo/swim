import Foundation
import Testing
@testable import SwimKit

@Suite("pool")
struct PoolTests {
    @Test func yardLengthsCountAsWholeLengths() {
        // Three 25 yd lengths as HealthKit sums them in metres.
        #expect(Pool.yards25.displayDistance(meters: 3 * 22.86) == 75)
        #expect(Pool.yards25.displayDistance(meters: 68.57) == 75)
        #expect(Pool.yards25.displayDistance(meters: 0) == 0)
    }

    @Test func meterPools() {
        #expect(Pool.meters25.displayDistance(meters: 100) == 100)
        #expect(Pool.meters50.displayDistance(meters: 150) == 150)
        #expect(Pool.meters50.title == "50 M")
        #expect(Pool.yards25.title == "25 YD")
    }
}

@Suite("set tracker")
struct SetTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// Lengths ending at the given offsets, with no start times — the
    /// worst case, where the watch reports only the wall.
    func tracker(ends: [TimeInterval]) -> SetTracker {
        var t = SetTracker(workoutStart: t0)
        for e in ends { t.record(.init(start: nil, end: at(e))) }
        return t
    }

    @Test func beforeAnyLengthTheSetRunsFromStart() {
        let t = SetTracker(workoutStart: t0)
        #expect(t.status(at: at(90)) == .swimming(since: t0))
        #expect(t.sets.isEmpty)
    }

    @Test func steadyLengthsAreOneSet() {
        let t = tracker(ends: [25, 50, 75, 100])
        #expect(t.sets == [DateInterval(start: t0, end: at(100))])
        #expect(t.status(at: at(120)) == .swimming(since: t0))
    }

    @Test func aPauseLongerThanTheThresholdIsARest() {
        let t = tracker(ends: [25, 50, 75, 100])
        // 1.6 × 25 s = 40 s after the last wall.
        #expect(t.restThreshold == 40)
        #expect(t.status(at: at(139)) == .swimming(since: t0))
        #expect(t.status(at: at(141)) == .resting(since: at(100), lastSet: 100))
    }

    @Test func aRestSplitsTheSets() {
        // Four lengths, a minute at the wall, then two more.
        let t = tracker(ends: [25, 50, 75, 100, 185, 210])
        #expect(t.sets.count == 2)
        #expect(t.sets[0] == DateInterval(start: t0, end: at(100)))
        // Back from rest: one typical length (25 s) before the wall at 185.
        #expect(t.sets[1] == DateInterval(start: at(160), end: at(210)))
        #expect(t.status(at: at(215)) == .swimming(since: at(160)))
    }

    @Test func theRestDoesNotInflateTheThreshold() {
        let t = tracker(ends: [25, 50, 75, 100, 185, 210])
        #expect(t.restThreshold == 40)
    }

    @Test func slowLengthsRaiseTheThreshold() {
        // 50 m lengths at a minute each: no rest is called between them.
        let t = tracker(ends: [60, 120, 180])
        #expect(t.sets.count == 1)
        #expect(t.restThreshold == 96)
    }

    @Test func theMinimumHoldsForFastLengths() {
        let t = tracker(ends: [12, 24, 36])
        #expect(t.restThreshold == SetTracker.minimumRest)
    }

    @Test func knownStartsAreUsed() {
        var t = SetTracker(workoutStart: t0)
        t.record(.init(start: at(10), end: at(35)))
        t.record(.init(start: at(36), end: at(60)))
        t.record(.init(start: at(150), end: at(175)))
        #expect(t.sets == [DateInterval(start: at(10), end: at(60)), DateInterval(start: at(150), end: at(175))])
    }

    @Test func duplicatesAndDisorderAreHandled() {
        var t = SetTracker(workoutStart: t0)
        t.record(.init(start: nil, end: at(50)))
        t.record(.init(start: nil, end: at(25)))
        t.record(.init(start: nil, end: at(25.2)))
        #expect(t.lengths.map(\.end) == [at(25), at(50)])
    }
}

@Suite("heart zones")
struct HeartZoneTests {
    @Test func zonesByPercentOfMax() {
        let max = HeartZone.maxHeartRate(age: 40) // 180
        #expect(max == 180)
        #expect(HeartZone(bpm: 71, maxHeartRate: max) == .rest)
        #expect(HeartZone(bpm: 90, maxHeartRate: max) == .one)
        #expect(HeartZone(bpm: 125, maxHeartRate: max) == .two)
        #expect(HeartZone(bpm: 140, maxHeartRate: max) == .three)
        #expect(HeartZone(bpm: 150, maxHeartRate: max) == .four)
        #expect(HeartZone(bpm: 170, maxHeartRate: max) == .five)
        #expect(HeartZone.rest.label == "REST")
        #expect(HeartZone.three.label == "3")
    }

    @Test func ageFromBirthDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        #expect(HeartZone.age(born: DateComponents(year: 1980, month: 10, day: 1), at: now, calendar: cal) == 45)
        #expect(HeartZone.age(born: DateComponents(year: 1980, month: 9, day: 30), at: now, calendar: cal) == 46)
    }
}

@Suite("clock")
struct SwimClockTests {
    @Test func setClock() {
        #expect(SwimClock.set(3.43, hundredths: true) == "00:03.43")
        #expect(SwimClock.set(3.43, hundredths: false) == "00:03")
        #expect(SwimClock.set(754.999, hundredths: true) == "12:34.99")
        #expect(SwimClock.set(3723.5, hundredths: true) == "1:02:03.50")
        #expect(SwimClock.set(-1, hundredths: true) == "00:00.00")
    }

    @Test func totalClock() {
        #expect(SwimClock.total(425) == "7:05")
        #expect(SwimClock.total(3723) == "1:02:03")
    }

    @Test func waterTemperatureInWholeDegrees() {
        #expect(WaterTemperature.text(celsius: 26.1, fahrenheit: true) == "79°F")
        #expect(WaterTemperature.text(celsius: 26.1, fahrenheit: false) == "26°C")
        #expect(WaterTemperature.text(celsius: 27.5, fahrenheit: false) == "28°C")
        #expect(WaterTemperature.text(celsius: 0, fahrenheit: true) == "32°F")
    }
}

@Suite("summary stats")
struct SwimStatsTests {
    @Test func paceIsPerHundredOfThePoolsUnitWhileSwimming() {
        // 20 lengths of 25 yd = 500 yd in 9:20 of swimming → 1:52 per 100 yd.
        let stats = SwimStats(pool: .yards25, meters: 20 * 22.86, swimSeconds: 560, strokeCount: 300, lengthStrokes: [])
        #expect(stats.lengths == 20)
        #expect(stats.pacePer100 == 112)
        #expect(SwimClock.pace(112) == "1:52")
        #expect(SwimClock.pace(59.6) == "1:00")
    }

    @Test func swolfIsStrokesPlusSecondsPerLength() {
        // 15 strokes and 28 seconds a length.
        let stats = SwimStats(pool: .yards25, meters: 20 * 22.86, swimSeconds: 560, strokeCount: 300, lengthStrokes: [])
        #expect(stats.swolf == 43)
        #expect(SwimStats(pool: .meters50, meters: 500, swimSeconds: 600, strokeCount: nil, lengthStrokes: []).swolf == nil)
    }

    @Test func aSwimWithNoLengthsHasNoPaceOrSwolf() {
        let stats = SwimStats(pool: .meters25, meters: 0, swimSeconds: 0, strokeCount: 0, lengthStrokes: [])
        #expect(stats.pacePer100 == nil && stats.swolf == nil && stats.strokes.isEmpty && stats.lengths == 0)
    }

    @Test func strokesAreAddedUpByLengthMostDistanceFirst() {
        // HKSwimmingStrokeStyle: 2 freestyle, 4 breaststroke, 0 unknown.
        let stats = SwimStats(pool: .yards25, meters: 6 * 22.86, swimSeconds: 180, strokeCount: 90,
                              lengthStrokes: [2, 2, 4, 2, 0, nil])
        #expect(stats.strokes == [
            .init(stroke: .freestyle, distance: 75),
            .init(stroke: .breaststroke, distance: 25),
        ])
        #expect(stats.strokes.first?.stroke.title == "Freestyle")
    }

    @Test func swimSecondsLeaveTheRestsOut() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var tracker = SetTracker(workoutStart: start)
        // Four 30 s lengths, two minutes at the wall, four more.
        for end in [30.0, 60, 90, 120] { tracker.record(.init(start: nil, end: start.addingTimeInterval(end), stroke: 2)) }
        for end in [270.0, 300, 330, 360] { tracker.record(.init(start: nil, end: start.addingTimeInterval(end), stroke: 2)) }
        #expect(tracker.sets.count == 2)
        #expect(tracker.swimSeconds == 240, "two sets of two minutes; the rest is not swimming")
        #expect(tracker.lengths.map(\.stroke) == Array(repeating: 2, count: 8))
    }
}

