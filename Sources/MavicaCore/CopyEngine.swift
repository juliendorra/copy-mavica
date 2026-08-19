import Foundation

public struct CopyOutcome: Equatable {
    public struct Copied: Equatable {
        public let source: URL
        public let destination: URL
    }

    /// A source photo whose exact bytes already exist in the destination.
    public struct SkippedDuplicate: Equatable {
        public let source: URL
        public let existing: URL
    }

    public struct Failure: Equatable {
        public let source: URL
        public let message: String
    }

    public var copied: [Copied] = []
    public var skippedDuplicates: [SkippedDuplicate] = []
    public var failures: [Failure] = []

    public init() {}
}

/// What just happened to one file, reported through the progress callback.
public enum CopyEvent: Equatable {
    case copied(name: String)
    case skippedDuplicate(sourceName: String, existingName: String)
    case failed(sourceName: String, message: String)
}

public final class CopyEngine {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Copies each file into `destination` under its Mavica name, then sets the
    /// copy's creation and modification dates to the source's modification date
    /// (the shell script did this with `cp -p` + `SetFile -d`).
    ///
    /// Every copy is verified: the source bytes are hashed as they are read
    /// (diskettes are not 100% reliable), written, read back, and compared —
    /// a mismatch removes the bad copy and reports a failure.
    ///
    /// A source whose exact bytes already exist under the same timestamp in the
    /// destination is a duplicate: skipped when `skipDuplicates` is true
    /// (reported in `skippedDuplicates`), copied under a `--N` name otherwise.
    public func copy(
        files: [MavicaFile],
        into destination: URL,
        timeZone: TimeZone = .current,
        skipDuplicates: Bool = true,
        progress: ((_ done: Int, _ total: Int, _ event: CopyEvent) -> Void)? = nil
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
            let event = process(
                file,
                into: destination,
                timeZone: timeZone,
                skipDuplicates: skipDuplicates,
                outcome: &outcome
            )
            progress?(index + 1, files.count, event)
        }

        return outcome
    }

    private func process(
        _ file: MavicaFile,
        into destination: URL,
        timeZone: TimeZone,
        skipDuplicates: Bool,
        outcome: inout CopyOutcome
    ) -> CopyEvent {
        let sourceName = file.url.lastPathComponent

        let data: Data
        do {
            data = try Data(contentsOf: file.url)
        } catch {
            let message = "Could not read: \(error.localizedDescription)"
            outcome.failures.append(.init(source: file.url, message: message))
            return .failed(sourceName: sourceName, message: message)
        }
        let sourceDigest = MavicaHasher.hexDigest(of: data)

        // Walk the candidate names: find the first free slot, and note any
        // existing same-timestamp file that already holds these exact bytes.
        var attempt = 1
        var freeSlot: URL?
        var existingDuplicate: URL?
        while freeSlot == nil {
            let name = MavicaNamer.candidateName(for: file.modificationDate, timeZone: timeZone, attempt: attempt)
            let candidate = destination.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: candidate.path) else {
                freeSlot = candidate
                break
            }
            if existingDuplicate == nil,
               let existingData = try? Data(contentsOf: candidate),
               MavicaHasher.hexDigest(of: existingData) == sourceDigest {
                existingDuplicate = candidate
            }
            attempt += 1
        }
        guard let target = freeSlot else {
            let message = "Could not find a free destination name."
            outcome.failures.append(.init(source: file.url, message: message))
            return .failed(sourceName: sourceName, message: message)
        }

        if skipDuplicates, let existingDuplicate {
            outcome.skippedDuplicates.append(.init(source: file.url, existing: existingDuplicate))
            return .skippedDuplicate(
                sourceName: sourceName,
                existingName: existingDuplicate.lastPathComponent
            )
        }

        do {
            try data.write(to: target, options: [.atomic])
            let readBack = try Data(contentsOf: target)
            guard MavicaHasher.hexDigest(of: readBack) == sourceDigest else {
                try? fileManager.removeItem(at: target)
                throw CopyVerificationError()
            }
            try? fileManager.setAttributes(
                [
                    .creationDate: file.modificationDate,
                    .modificationDate: file.modificationDate
                ],
                ofItemAtPath: target.path
            )
            outcome.copied.append(.init(source: file.url, destination: target))
            return .copied(name: target.lastPathComponent)
        } catch {
            let message = error is CopyVerificationError
                ? "Copy verification failed — the written bytes did not match the diskette."
                : error.localizedDescription
            outcome.failures.append(.init(source: file.url, message: message))
            return .failed(sourceName: sourceName, message: message)
        }
    }
}

private struct CopyVerificationError: Error {}
