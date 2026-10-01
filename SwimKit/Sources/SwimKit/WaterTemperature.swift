import Foundation

/// The water's temperature, as the swim screen says it.
///
/// Whole degrees: the watch's sensor reports tenths, and a tenth that flickers
/// mid-length is noise on a cell read at a glance. HealthKit hands the reading
/// over in Celsius; which scale to SHOW is the wearer's region, decided by the
/// caller (`UnitTemperature(forLocale:)`), so this stays plain arithmetic.
public enum WaterTemperature {
    /// "79°F" or "26°C".
    public static func text(celsius: Double, fahrenheit: Bool) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°\(fahrenheit ? "F" : "C")"
    }
}
