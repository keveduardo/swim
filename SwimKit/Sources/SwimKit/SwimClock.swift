import Foundation

/// The clock formats on the swim screen. Plain arithmetic rather than a
/// `DateComponentsFormatter`, which has no hundredths and pads inconsistently.
public enum SwimClock {
    /// The set timer: "00:03.43", or "00:03" when the screen is dimmed and
    /// updates only once a second. Past an hour, "1:02:03.43".
    public static func set(_ seconds: TimeInterval, hundredths: Bool) -> String {
        let s = max(0, seconds)
        let whole = Int(s)
        let (h, m, sec) = (whole / 3600, whole / 60 % 60, whole % 60)
        var text = h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
        if hundredths {
            text += String(format: ".%02d", min(99, Int((s - Double(whole)) * 100)))
        }
        return text
    }

    /// The workout's total time in the top bar: "7:05", "1:02:03".
    public static func total(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        let (h, m, sec) = (whole / 3600, whole / 60 % 60, whole % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
