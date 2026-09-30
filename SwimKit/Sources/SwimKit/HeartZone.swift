import Foundation

/// Heart-rate zones from age, the way Kevin asked for them (2026-09-30).
///
/// Apple's own zones are computed inside the Workout app and not published to
/// other apps, so these are the textbook ones: a maximum from Tanaka's
/// formula (208 − 0.7 × age, which fits adults better than 220 − age) and five
/// bands of ten percent from 50 %. Below the first band is **Rest**.
public enum HeartZone: Int, CaseIterable, Sendable {
    case rest = 0
    case one, two, three, four, five

    /// "REST", or the zone's number — what follows "ZONE:" on the screen.
    public var label: String { self == .rest ? "REST" : String(rawValue) }

    /// The zone of `bpm` for someone whose maximum is `maxHeartRate`.
    public init(bpm: Double, maxHeartRate: Double) {
        let fraction = bpm / maxHeartRate
        switch fraction {
        case ..<0.5: self = .rest
        case ..<0.6: self = .one
        case ..<0.7: self = .two
        case ..<0.8: self = .three
        case ..<0.9: self = .four
        default: self = .five
        }
    }

    public static func maxHeartRate(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }

    /// Whole years from a birth date to `now`.
    public static func age(born: DateComponents, at now: Date, calendar: Calendar = .current) -> Int? {
        guard let birthday = calendar.date(from: born) else { return nil }
        return calendar.dateComponents([.year], from: birthday, to: now).year
    }
}
