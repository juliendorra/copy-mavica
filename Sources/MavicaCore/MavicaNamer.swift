import Foundation

/// Builds destination file names of the form `MAVICA-YYYY-MM-DD-HH-MM-SS.JPG`,
/// appending `--2`, `--3`, … on collision — the same scheme as copy-mavica.sh.
public enum MavicaNamer {

    public static let prefix = "MAVICA"
    public static let fileExtension = "JPG"

    public static func timestamp(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: date)
    }

    /// The `attempt`th candidate name for a photo with the given modification
    /// date: attempt 1 is `MAVICA-<timestamp>.JPG`, attempt 2 `…--2.JPG`, etc.
    public static func candidateName(
        for date: Date,
        timeZone: TimeZone = .current,
        attempt: Int
    ) -> String {
        let base = "\(prefix)-\(timestamp(for: date, timeZone: timeZone))"
        return attempt <= 1
            ? "\(base).\(fileExtension)"
            : "\(base)--\(attempt).\(fileExtension)"
    }

    /// Returns the first non-colliding file name for a photo with the given
    /// modification date. `isTaken` is queried with candidate names until one is free.
    public static func fileName(
        for date: Date,
        timeZone: TimeZone = .current,
        isTaken: (String) -> Bool
    ) -> String {
        var attempt = 1
        var candidate = candidateName(for: date, timeZone: timeZone, attempt: attempt)
        while isTaken(candidate) {
            attempt += 1
            candidate = candidateName(for: date, timeZone: timeZone, attempt: attempt)
        }
        return candidate
    }
}
