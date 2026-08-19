import Foundation

/// A source photo found on the camera diskette.
public struct MavicaFile: Equatable {
    public let url: URL
    public let modificationDate: Date

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }
}

/// The photos on a diskette, split into real photos and hidden/trashed ones.
public struct MavicaScan: Equatable {
    /// Visible JPEGs, sorted oldest first — what a copy should import.
    public let photos: [MavicaFile]
    /// JPEGs hiding inside hidden folders — Files (iOS) and Finder (macOS)
    /// "delete" by moving files into `.Trashes` on the diskette itself, so
    /// these still occupy space and would otherwise be re-imported.
    public let trashed: [MavicaFile]

    public init(photos: [MavicaFile], trashed: [MavicaFile]) {
        self.photos = photos
        self.trashed = trashed
    }
}

public enum MavicaScanner {

    /// Recursively finds JPEG files under `root`, classifying anything inside
    /// a hidden directory (`.Trashes`, `.Trash-1000`, …) or itself hidden as
    /// trashed. AppleDouble sidecars (`._*`) that macOS leaves on FAT volumes
    /// are ignored entirely. Both lists are sorted oldest first.
    public static func scan(in root: URL, fileManager: FileManager = .default) -> MavicaScan {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return MavicaScan(photos: [], trashed: [])
        }

        let rootComponentCount = root.pathComponents.count
        var photos: [MavicaFile] = []
        var trashed: [MavicaFile] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("._") { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "jpg" || ext == "jpeg" else { continue }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let file = MavicaFile(
                url: url,
                modificationDate: values.contentModificationDate ?? Date()
            )
            // Only components below the picked root count as hiding the file:
            // the root itself may legitimately sit under a dotted mount path.
            let relativeComponents = url.pathComponents.dropFirst(rootComponentCount)
            if relativeComponents.contains(where: { $0.hasPrefix(".") }) {
                trashed.append(file)
            } else {
                photos.append(file)
            }
        }

        return MavicaScan(photos: sorted(photos), trashed: sorted(trashed))
    }

    /// Recursively finds visible JPEG files under `root`, sorted oldest first.
    public static func jpegFiles(in root: URL, fileManager: FileManager = .default) -> [MavicaFile] {
        scan(in: root, fileManager: fileManager).photos
    }

    private static func sorted(_ files: [MavicaFile]) -> [MavicaFile] {
        files.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate < $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }
    }
}
