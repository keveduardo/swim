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
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: health,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            tracker = SetTracker(workoutStart: now)
            watchWater(since: now)
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
        session = nil
        builder = nil
    }

    /// Follow the water temperature the watch itself records while submerged
    /// (Kevin, 2026-09-30: "instead of the total set time box can we change
    /// that to the water temperature").
    ///
    /// **Where the number comes from.** A watch with a depth gauge — the Ultra,
    /// which is what Kevin wears — writes `waterTemperature` samples to Health
    /// when it is under water. This reads them as they land: a query from the
    /// moment of Start, with an update handler, rather than anything asked of
    /// the workout builder, so it does not depend on what the live data source
    /// chooses to collect for a pool swim.
    ///
    /// ! UNPROVEN IN WATER, like the rest of this app. If the cell stays "--"
    /// through a real swim, the watch is not recording temperature for a
    /// third-party workout, and the other way to get it is Core Motion's
    /// `CMWaterSubmersionManager` (its own entitlement and background mode).
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
        guard phase == .running else { return }
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
        Task { @MainActor in self.collected(heartRate: bpm, meters: meters) }
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
