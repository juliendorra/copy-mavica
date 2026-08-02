import Foundation

/// A source photo found on the camera card.
public struct MavicaFile: Equatable {
    public let url: URL
    public let modificationDate: Date

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }
}

public enum MavicaScanner {

    /// Recursively finds JPEG files under `root`, sorted oldest first.
    /// AppleDouble sidecars (`._*`) that macOS leaves on FAT volumes are skipped.
    public static func jpegFiles(in root: URL, fileManager: FileManager = .default) -> [MavicaFile] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return []
        }

        var found: [MavicaFile] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("._") { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            found.append(MavicaFile(
                url: url,
                modificationDate: values.contentModificationDate ?? Date()
            ))
        }

        return found.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate < $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }
    }
}
