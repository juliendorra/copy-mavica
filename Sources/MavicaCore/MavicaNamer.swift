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

    /// Returns the first non-colliding file name for a photo with the given
    /// modification date. `isTaken` is queried with candidate names until one is free.
    public static func fileName(
        for date: Date,
        timeZone: TimeZone = .current,
        isTaken: (String) -> Bool
    ) -> String {
        let base = "\(prefix)-\(timestamp(for: date, timeZone: timeZone))"
        var candidate = "\(base).\(fileExtension)"
        var suffix = 2
        while isTaken(candidate) {
            candidate = "\(base)--\(suffix).\(fileExtension)"
            suffix += 1
        }
        return candidate
    }
}
