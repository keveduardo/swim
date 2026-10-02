import CoreMotion
import Foundation
import HealthKit
import Observation
import SwimKit
import WatchKit

/// The watch's pool swim: one `HKWorkoutSession` from the tap on Start to End,
/// saved to Health — which puts it in Fitness on the phone with the rings.
///
/// **What the watch does for us.** With `.swimming` and a pool configuration
/// carrying the lap length, `HKLiveWorkoutDataSource` counts lengths, distance
/// and strokes itself, exactly as it does for Apple's Workout app, and ends
/// each length with a `.lap` event. The app adds only what Apple keeps to
/// itself: the set/rest split (`SetTracker`) and heart-rate zones (`HeartZone`).
@MainActor
@Observable
final class SwimSession: NSObject {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case saving
        case saved(Summary)
        /// Ended with nothing worth saving.
        case discarded
        case failed(String)
    }

    /// What the summary screen shows.
    struct Summary: Equatable {
        var pool: Pool
        var meters: Double
        var duration: TimeInterval
        var sets: Int
        var averageHeartRate: Double?
        /// The last reading of the swim, in Celsius; nil when the watch gave none.
        var waterCelsius: Double?
    }

    private(set) var phase: Phase = .idle
    private(set) var pool: Pool = .yards25
    private(set) var isPaused = false
    /// Distance so far, in metres, as HealthKit sums it.
    private(set) var meters: Double = 0
    private(set) var heartRate: Double?
    /// From Tanaka's formula and the birth date in Health; nil when Health
    /// has no birth date or would not share it, and the zone is left off.
    private(set) var maxHeartRate: Double?
    /// The water's temperature in Celsius, as the watch last recorded it. Nil
    /// until a reading arrives — and for the whole swim on a watch with no
    /// water-temperature sensor.
    private(set) var waterCelsius: Double?
    private(set) var tracker = SetTracker(workoutStart: .now)

    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var waterQuery: HKAnchoredObjectQuery?
    /// The watch's own water sensor, read directly — see `watchSensor`.
    @ObservationIgnored private var submersion: CMWaterSubmersionManager?

    nonisolated private static let heartRateType = HKQuantityType(.heartRate)
    nonisolated private static let distanceType = HKQuantityType(.distanceSwimming)
    nonisolated private static let waterType = HKQuantityType(.waterTemperature)

    /// What the watch writes: the workout and the samples the data source
    /// collects for a swim. What it reads: those, heart rate for the screen,
    /// and the birth date for the zones. Heart rate is not in the share set —
    /// the data source's samples are the system's to write (as in RowSession).
    private static let shareTypes: Set<HKSampleType> = [
        HKWorkoutType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.swimmingStrokeCount),
    ]
    private static let readTypes: Set<HKObjectType> = [
        heartRateType,
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.swimmingStrokeCount),
        waterType,
        HKCharacteristicType(.dateOfBirth),
    ]

    /// Seconds of workout so far, pauses excluded — HealthKit's own count.
    func elapsed(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    /// Start a pool swim. Asks for Health permission the first time.
    ///
    /// ! The usage strings in the Info.plist are not optional: a missing one
    /// raises inside `requestAuthorization`, and `try` cannot catch that.
    func start(in pool: Pool) async {
        guard phase == .idle || isOver else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            phase = .failed("Health isn't available on this watch")
            return
        }
        phase = .starting
        self.pool = pool
        meters = 0
        heartRate = nil
        waterCelsius = nil
        isPaused = false
        do {
            try await health.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            maxHeartRate = readMaxHeartRate()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .swimming
            configuration.locationType = .indoor
            configuration.swimmingLocationType = .pool
            configuration.lapLength = HKQuantity(
                unit: pool.isYards ? .yard() : .meter(),
                doubleValue: pool.length
            )

            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let source = HKLiveWorkoutDataSource(
                healthStore: health,
                workoutConfiguration: configuration
            )
            // Asked for by name rather than left to the source's defaults for
            // a pool swim — see `watchWater`.
            source.enableCollection(for: Self.waterType, predicate: nil)
            builder.dataSource = source
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            tracker = SetTracker(workoutStart: now)
            watchWater(since: now)
            watchSensor()
            phase = .running
            // Splashes are taps. The Digital Crown undoes it, as in Apple's app.
            WKInterfaceDevice.current().enableWaterLock()
        } catch {
            clear()
            phase = .failed(error.localizedDescription)
        }
    }

    func togglePause() {
        guard phase == .running, let session else { return }
        isPaused ? session.resume() : session.pause()
    }

    func lockScreen() {
        WKInterfaceDevice.current().enableWaterLock()
    }

    /// End the swim and save it. A swim with no distance and under a minute
    /// is a mis-tap, and is discarded rather than left in Fitness.
    func finish() async {
        guard phase == .running, let session, let builder else { return }
        phase = .saving
        let end = Date()
        let duration = builder.elapsedTime(at: end)
        let averageHeartRate = builder.statistics(for: Self.heartRateType)?
            .averageQuantity()?
            .doubleValue(for: Self.bpm)
        session.end()
        do {
            try await builder.endCollection(at: end)
            // What the builder holds once collection has ended: a reading that
            // only reached it at the end still belongs on the summary.
            if waterCelsius == nil {
                waterCelsius = builder.statistics(for: Self.waterType)?
                    .mostRecentQuantity()?
                    .doubleValue(for: .degreeCelsius())
            }
            if meters == 0, duration < 60 {
                builder.discardWorkout()
                phase = .discarded
            } else {
                _ = try await builder.finishWorkout()
                phase = .saved(Summary(
                    pool: pool,
                    meters: meters,
                    duration: duration,
                    sets: tracker.sets.count,
                    averageHeartRate: averageHeartRate,
                    waterCelsius: waterCelsius
                ))
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
        clear()
    }

    /// Back to the start screen.
    func dismiss() {
        guard isOver else { return }
        phase = .idle
    }

    private var isOver: Bool {
        switch phase {
        case .saved, .discarded, .failed: true
        case .idle, .starting, .running, .saving: false
        }
    }

    private func clear() {
        if let waterQuery { health.stop(waterQuery) }
        waterQuery = nil
        submersion?.delegate = nil
        submersion = nil
        session = nil
        builder = nil
    }

    /// Follow the water temperature the watch itself records while submerged
    /// (Kevin, 2026-09-30: "instead of the total set time box can we change
    /// that to the water temperature").
    ///
    /// **Where the number comes from.** A watch with a depth gauge — the Ultra,
    /// which is what Kevin wears — writes `waterTemperature` samples to Health
    /// when it is under water, "during dive sessions and swimming workouts"
    /// (Apple's page for the type).
    ///
    /// **Two ways in, because the first alone failed.** This query reads the
    /// samples as they land in Health, from the moment of Start. On Kevin's
    /// first swim (2026-10-01, build 11) the cell stayed "--" from Start to
    /// End. The likely reason: a live workout's samples are held by the
    /// builder and reach Health only when the workout is saved — which is why
    /// heart rate, read from the builder, did show. So since then the data
    /// source is also told to collect the type (`start`), and
    /// `workoutBuilder(_:didCollectDataOf:)` reads it from the builder as it
    /// does heart rate. The query stays, for a watch that writes the samples
    /// outside the workout.
    ///
    /// (2026-10-02: neither showed anything during a swim on build 14 — see
    /// `watchSensor`, the live source. These two stay for the summary.)
    ///
    /// ! THE SECOND WAY IS UNPROVEN IN WATER TOO. If the cell still stays "--",
    /// what is left is Core Motion's `CMWaterSubmersionManager`, which is a
    /// bigger thing than it sounds: the Shallow Depth and Pressure capability,
    /// `NSMotionUsageDescription` (without it the app crashes), and the
    /// `underwater-depth` background mode, which makes this a dive app to the
    /// system — the auto-launch list, held frontmost. See SWIM.md.
    private func watchWater(since start: Date) {
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void = { [weak self] _, samples, _, _, _ in
            // Only a number crosses to the main actor.
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let celsius = latest.quantity.doubleValue(for: .degreeCelsius())
            Task { @MainActor in self?.collected(waterCelsius: celsius) }
        }
        let query = HKAnchoredObjectQuery(
            type: Self.waterType,
            predicate: HKQuery.predicateForSamples(withStart: start, end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        health.execute(query)
        waterQuery = query
    }

    /// The third way in, and the only one that is LIVE by design: the watch's
    /// water sensor itself, through Core Motion.
    ///
    /// **Why.** The two Health routes above showed nothing during Kevin's swim
    /// of 2026-10-02 (build 14), though the day before the number did appear,
    /// and though Health held the reading afterwards both times. So the watch
    /// records the temperature, but writes it to Health on its own schedule,
    /// not as it measures it. `CMWaterSubmersionManager` hands over the
    /// sensor's reading about three times a second while the watch is under
    /// water; the reading settles over the first seconds, and the cell shows
    /// whatever is newest.
    ///
    /// **What it needs.** The Shallow Depth and Pressure capability
    /// (`Swim.entitlements`; no approval from Apple) and
    /// `NSMotionUsageDescription` — ! without that string, creating the manager
    /// CRASHES. Only a watch with the sensor has it, and the Simulator does
    /// not, so the manager is made only when the watch says it is available.
    ///
    /// ! NOT the `underwater-depth` background mode. That is for dive apps:
    /// the auto-launch list, held frontmost, a runtime session of its own. A
    /// swim already keeps this app running through its workout session.
    /// UNPROVEN IN WATER: if the cell still shows "--", the background mode is
    /// what is left to try.
    private func watchSensor() {
        guard CMWaterSubmersionManager.waterSubmersionAvailable else { return }
        let manager = CMWaterSubmersionManager()
        manager.delegate = self
        submersion = manager
    }

    private func readMaxHeartRate() -> Double? {
        guard let born = try? health.dateOfBirthComponents(),
              let age = HeartZone.age(born: born, at: .now)
        else { return nil }
        return HeartZone.maxHeartRate(age: age)
    }

    nonisolated private static let bpm = HKUnit.count().unitDivided(by: .minute())

    // MARK: Delegate callbacks, on the main actor

    fileprivate func sessionFailed(_ message: String) {
        if phase == .running || phase == .starting {
            phase = .failed(message)
            clear()
        }
    }

    fileprivate func stateChanged(to state: HKWorkoutSessionState) {
        isPaused = state == .paused
    }

    fileprivate func collected(heartRate bpm: Double?, meters: Double?) {
        if let bpm { heartRate = bpm }
        if let meters { self.meters = meters }
    }

    fileprivate func collected(waterCelsius celsius: Double) {
        // While saving too: the summary is built after the last reading lands.
        guard phase == .running || phase == .saving else { return }
        waterCelsius = celsius
    }

    fileprivate func collected(lengths: [SetTracker.Length]) {
        // The builder hands over every event so far, each time; `record`
        // ignores the ones it already has.
        for length in lengths { tracker.record(length) }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension SwimSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.stateChanged(to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.sessionFailed(message) }
    }
}

// MARK: - CMWaterSubmersionManagerDelegate

extension SwimSession: CMWaterSubmersionManagerDelegate {
    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate measurement: CMWaterTemperature) {
        // Only a number crosses to the main actor.
        let celsius = measurement.temperature.converted(to: .celsius).value
        Task { @MainActor in self.collected(waterCelsius: celsius) }
    }

    // The protocol's other three. Depth and submersion events are not this
    // app's business, and an error (no entitlement, no sensor) leaves the cell
    // to the Health routes, which is where it was before.
    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate event: CMWaterSubmersionEvent) {}
    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate measurement: CMWaterSubmersionMeasurement) {}
    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: any Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension SwimSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // Only numbers cross to the main actor.
        let bpm = collectedTypes.contains(Self.heartRateType)
            ? workoutBuilder.statistics(for: Self.heartRateType)?.mostRecentQuantity()?.doubleValue(for: Self.bpm)
            : nil
        let meters = collectedTypes.contains(Self.distanceType)
            ? workoutBuilder.statistics(for: Self.distanceType)?.sumQuantity()?.doubleValue(for: .meter())
            : nil
        let celsius = collectedTypes.contains(Self.waterType)
            ? workoutBuilder.statistics(for: Self.waterType)?.mostRecentQuantity()?.doubleValue(for: .degreeCelsius())
            : nil
        Task { @MainActor in
            self.collected(heartRate: bpm, meters: meters)
            if let celsius { self.collected(waterCelsius: celsius) }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // A `.lap` event is one length, ended at the wall. A zero-length
        // interval means the watch gave only the wall, not the push-off.
        let lengths = workoutBuilder.workoutEvents
            .filter { $0.type == .lap }
            .map { event in
                let interval = event.dateInterval
                return SetTracker.Length(start: interval.duration > 0 ? interval.start : nil, end: interval.end)
            }
        Task { @MainActor in self.collected(lengths: lengths) }
    }
}
