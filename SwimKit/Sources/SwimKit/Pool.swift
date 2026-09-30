import Foundation

/// The pools Kevin swims in. Three, and only three (2026-09-30): a picker
/// with every length Apple allows would be a scroll through choices never made.
public enum Pool: String, CaseIterable, Identifiable, Sendable {
    case yards25
    case meters25
    case meters50

    public var id: String { rawValue }

    /// The length in the pool's own unit.
    public var length: Double {
        switch self {
        case .yards25, .meters25: 25
        case .meters50: 50
        }
    }

    public var isYards: Bool { self == .yards25 }

    /// One length in metres — what HealthKit is told, and what the app
    /// converts back from.
    public var lengthInMeters: Double {
        isYards ? length * Self.metersPerYard : length
    }

    /// "YD" or "M", beside the distance.
    public var unitLabel: String { isYards ? "YD" : "M" }

    /// "25 YD", "50 M" — the start screen's button and the menu's rows.
    public var title: String { "\(Int(length)) \(unitLabel)" }

    /// A distance HealthKit reported in metres, in this pool's unit, rounded
    /// to the nearest whole length.
    ///
    /// ! Rounded to lengths, not to units: 25 yd is 22.86 m, and HealthKit's
    /// sum of three yard lengths comes back as 68.58 m. Converted naively that
    /// reads 75 yd on one watch and 74 on another; counted in lengths it is
    /// always three.
    public func displayDistance(meters: Double) -> Int {
        let lengths = (meters / lengthInMeters).rounded()
        return Int(lengths * length)
    }

    public static let metersPerYard = 0.9144
}
