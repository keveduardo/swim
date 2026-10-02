import Foundation

/// What the summary says about a finished swim beyond its distance and time:
/// pace, SWOLF and which strokes — all worked out from what the watch already
/// reports (Kevin, 2026-10-02: "yes add all those to the summary").
///
/// A value with no HealthKit in it: the session hands over plain numbers, and
/// the arithmetic is tested here.
public struct SwimStats: Sendable, Equatable {
    /// The strokes the watch tells apart. The raw values are HealthKit's
    /// `HKSwimmingStrokeStyle`, which is what a lap event carries; 0 there is
    /// "unknown" and is simply not a case here.
    public enum Stroke: Int, Sendable, CaseIterable {
        case mixed = 1
        case freestyle = 2
        case backstroke = 3
        case breaststroke = 4
        case butterfly = 5
        case kickboard = 6

        public var title: String {
            switch self {
            case .mixed: "Mixed"
            case .freestyle: "Freestyle"
            case .backstroke: "Backstroke"
            case .breaststroke: "Breaststroke"
            case .butterfly: "Butterfly"
            case .kickboard: "Kickboard"
            }
        }
    }

    /// One stroke's share of the swim, in the pool's own unit.
    public struct StrokeDistance: Sendable, Equatable, Identifiable {
        public var stroke: Stroke
        public var distance: Int
        public var id: Int { stroke.rawValue }

        public init(stroke: Stroke, distance: Int) {
            self.stroke = stroke
            self.distance = distance
        }
    }

    /// Whole lengths swum.
    public var lengths: Int
    /// Seconds per 100 of the pool's unit, while swimming; nil with no distance.
    public var pacePer100: TimeInterval?
    /// Strokes plus seconds, per length, averaged — lower is more efficient.
    /// Nil when the watch counted no strokes or no lengths.
    public var swolf: Int?
    /// The strokes swum, most distance first. Empty when the watch named none.
    public var strokes: [StrokeDistance]

    /// - Parameters:
    ///   - meters: the distance as HealthKit sums it.
    ///   - swimSeconds: time actually swimming — the sets, not the rests.
    ///     Pace and SWOLF measured against the whole workout would count
    ///     standing at the wall as slow swimming.
    ///   - strokeCount: the watch's stroke count for the swim, if it has one.
    ///   - lengthStrokes: each length's `HKSwimmingStrokeStyle` raw value, in
    ///     any order; nil or 0 for a length the watch could not name.
    public init(pool: Pool, meters: Double, swimSeconds: TimeInterval, strokeCount: Double?, lengthStrokes: [Int?]) {
        let lengths = Int((meters / pool.lengthInMeters).rounded())
        self.lengths = lengths
        let distance = Double(lengths) * pool.length

        if distance > 0, swimSeconds > 0 {
            pacePer100 = swimSeconds / (distance / 100)
        } else {
            pacePer100 = nil
        }

        if lengths > 0, swimSeconds > 0, let strokeCount, strokeCount > 0 {
            swolf = Int(((strokeCount + swimSeconds) / Double(lengths)).rounded())
        } else {
            swolf = nil
        }

        var perStroke: [Stroke: Int] = [:]
        for raw in lengthStrokes {
            guard let raw, let stroke = Stroke(rawValue: raw) else { continue }
            perStroke[stroke, default: 0] += 1
        }
        strokes = perStroke
            .map { StrokeDistance(stroke: $0.key, distance: $0.value * Int(pool.length)) }
            .sorted { ($0.distance, $1.stroke.rawValue) > ($1.distance, $0.stroke.rawValue) }
    }
}

public extension SwimClock {
    /// A pace: "1:52" for 112 seconds per 100. Whole seconds, minutes unpadded.
    static func pace(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
