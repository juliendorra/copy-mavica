import Foundation

/// Well-known locations used by the Mavica workflow.
public enum MavicaLocations {

    /// The volume name Sony Mavica floppy diskettes mount as.
    public static let cameraVolumeName = "MY_PHOTO"

    public static let defaultICloudSubfolder = "Mavica Photos"

    /// `/Volumes/MY_PHOTO` if a Mavica floppy is currently mounted, else nil.
    public static func autodetectedCameraVolume(fileManager: FileManager = .default) -> URL? {
        let path = "/Volumes/\(cameraVolumeName)"
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The on-disk iCloud Drive root (`~/Library/Mobile Documents/com~apple~CloudDocs`).
    public static func iCloudDriveRoot(fileManager: FileManager = .default) -> URL? {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return root
    }

    /// Default destination: `iCloud Drive/Mavica Photos`, falling back to
    /// `~/Pictures/Mavica Photos` when iCloud Drive is unavailable.
    public static func defaultDestination(fileManager: FileManager = .default) -> URL {
        if let icloud = iCloudDriveRoot(fileManager: fileManager) {
            return icloud.appendingPathComponent(defaultICloudSubfolder, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(defaultICloudSubfolder, isDirectory: true)
    }
}
