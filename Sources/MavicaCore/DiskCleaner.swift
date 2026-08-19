import Foundation

/// Deletes photos from the diskette — used to empty its hidden trash and to
/// empty the disk after a fully verified copy.
public enum DiskCleaner {

    /// Removes each file plus its AppleDouble sidecar (`._<name>`) if present.
    /// Returns one message per file that could not be removed.
    public static func delete(
        files: [URL],
        fileManager: FileManager = .default
    ) -> [String] {
        var errors: [String] = []
        for url in files {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            let sidecar = url.deletingLastPathComponent()
                .appendingPathComponent("._" + url.lastPathComponent)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.removeItem(at: sidecar)
            }
        }
        return errors
    }
}
