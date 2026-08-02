import Foundation

public struct CopyOutcome: Equatable {
    public struct Copied: Equatable {
        public let source: URL
        public let destination: URL
    }

    public struct Failure: Equatable {
        public let source: URL
        public let message: String
    }

    public var copied: [Copied] = []
    public var failures: [Failure] = []

    public init() {}
}

public final class CopyEngine {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Copies each file into `destination` under its Mavica name, then sets the
    /// copy's creation and modification dates to the source's modification date
    /// (the shell script did this with `cp -p` + `SetFile -d`).
    public func copy(
        files: [MavicaFile],
        into destination: URL,
        timeZone: TimeZone = .current,
        progress: ((_ done: Int, _ total: Int, _ name: String) -> Void)? = nil
    ) -> CopyOutcome {
        var outcome = CopyOutcome()

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            for file in files {
                outcome.failures.append(.init(
                    source: file.url,
                    message: "Could not create destination folder: \(error.localizedDescription)"
                ))
            }
            return outcome
        }

        for (index, file) in files.enumerated() {
            let name = MavicaNamer.fileName(for: file.modificationDate, timeZone: timeZone) { candidate in
                fileManager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
            }
            let destinationURL = destination.appendingPathComponent(name)
            do {
                try fileManager.copyItem(at: file.url, to: destinationURL)
                try? fileManager.setAttributes(
                    [
                        .creationDate: file.modificationDate,
                        .modificationDate: file.modificationDate
                    ],
                    ofItemAtPath: destinationURL.path
                )
                outcome.copied.append(.init(source: file.url, destination: destinationURL))
            } catch {
                outcome.failures.append(.init(source: file.url, message: error.localizedDescription))
            }
            progress?(index + 1, files.count, name)
        }

        return outcome
    }
}
