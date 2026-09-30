import Foundation

/// Splits a pool swim into sets and rests, from nothing but the lengths the
/// watch reports.
///
/// **Why this exists.** Apple's Workout app detects rest from the wrist's
/// motion, and that detector is not offered to other apps. What a third-party
/// app *does* get is a lap event at the end of every length. So a rest here is
/// inferred: the wall came and went, and the next length is overdue.
///
/// **What "overdue" means.** Relative to the swimmer, not a fixed number — a
/// 50 m length can take a minute, and a fixed 20 s would call every length a
/// rest. The threshold is 1.6 × the median of the recent lengths, never under
/// `minimumRest`. A rest is only ever recognised after that much time has
/// passed, but it is *dated* from the last length's end, so once it shows, the
/// set's time and the rest's time are both right.
///
/// A value type with no clock of its own: every question takes `now`, which is
/// what makes it testable.
public struct SetTracker: Sendable, Equatable {
    public struct Length: Sendable, Equatable {
        /// When the watch says the length began, if it said.
        public var start: Date?
        public var end: Date

        public init(start: Date?, end: Date) {
            self.start = start
            self.end = end
        }
    }

    public enum Status: Sendable, Equatable {
        /// In a set that began at `since`.
        case swimming(since: Date)
        /// Resting since `since`, after a set of `lastSet` seconds.
        case resting(since: Date, lastSet: TimeInterval)
    }

    public private(set) var workoutStart: Date
    public private(set) var lengths: [Length] = []

    /// No rest is shorter than this, however fast the lengths.
    public static let minimumRest: TimeInterval = 30
    public static let restFactor = 1.6
    /// How many recent lengths the median looks at.
    static let window = 8

    public init(workoutStart: Date) {
        self.workoutStart = workoutStart
    }

    /// Add a length. Duplicates (the same end, reported twice) are ignored,
    /// and out-of-order arrivals are put in order.
    public mutating func record(_ length: Length) {
        guard !lengths.contains(where: { abs($0.end.timeIntervalSince(length.end)) < 0.5 }) else { return }
        lengths.append(length)
        lengths.sort { $0.end < $1.end }
    }

    /// Where the swimmer is at `now`.
    public func status(at now: Date) -> Status {
        let (sets, threshold) = analyse()
        guard let current = sets.last else { return .swimming(since: workoutStart) }
        if now.timeIntervalSince(current.end) > threshold {
            return .resting(since: current.end, lastSet: current.duration)
        }
        return .swimming(since: current.start)
    }

    /// The sets so far, each from its first push-off to its last wall. A set
    /// that is still going ends at its latest length.
    public var sets: [DateInterval] { analyse().sets }

    /// How long without a length now counts as a rest.
    public var restThreshold: TimeInterval { analyse().threshold }

    /// One pass over the lengths, in order: each is either the next length of
    /// the current set, or — if it ended more than the threshold after the one
    /// before — the first of a new set. The threshold at each step comes only
    /// from lengths already placed *inside* a set, so a rest never counts as
    /// swimming time and never makes the next rest harder to see.
    private func analyse() -> (sets: [DateInterval], threshold: TimeInterval) {
        var sets: [DateInterval] = []
        var durations: [TimeInterval] = []
        var setStart = workoutStart
        var previousEnd: Date?

        for length in lengths {
            let typical = Self.median(durations.suffix(Self.window))
            let threshold = Self.threshold(typical: typical)
            let known = length.start.map { length.end.timeIntervalSince($0) }.flatMap { $0 > 0 ? $0 : nil }

            if let previousEnd, length.end.timeIntervalSince(previousEnd) <= threshold {
                // Same set. Without its own start, a length lasted from the
                // wall before.
                durations.append(known ?? length.end.timeIntervalSince(previousEnd))
            } else {
                if let previousEnd { sets.append(DateInterval(start: setStart, end: previousEnd)) }
                if let start = length.start {
                    setStart = start
                } else if let previousEnd {
                    // Back from a rest with no start given: one typical length
                    // before this wall, and never inside the rest's own start.
                    setStart = max(length.end.addingTimeInterval(-(typical ?? Self.minimumRest)), previousEnd)
                } else {
                    // The first set starts with the workout: Start is pressed
                    // at the wall.
                    setStart = min(workoutStart, length.end)
                }
                if let known {
                    durations.append(known)
                } else if previousEnd == nil {
                    // The workout's first length, timed from Start. Any
                    // standing at the wall is in it, which only makes the
                    // threshold more lenient — the safe direction: without it
                    // a slow first set would have nothing to be measured
                    // against, and every one-minute 50 m length would read as
                    // a rest.
                    durations.append(length.end.timeIntervalSince(workoutStart))
                }
                // A later set's first length with no start is left out: its
                // wall-to-wall time has the rest in it.
            }
            previousEnd = length.end
        }
        if let previousEnd { sets.append(DateInterval(start: setStart, end: max(previousEnd, setStart))) }
        return (sets, Self.threshold(typical: Self.median(durations.suffix(Self.window))))
    }

    /// 1.6 × a typical length, never under `minimumRest`. With no length to go
    /// on, `minimumRest` alone.
    static func threshold(typical: TimeInterval?) -> TimeInterval {
        max(minimumRest, restFactor * (typical ?? 0))
    }

    static func median<C: Collection>(_ values: C) -> TimeInterval? where C.Element == TimeInterval {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
