import Foundation
import SwiftUI
import UIKit
import MavicaCore

/// iOS counterpart of the Mac AppModel. There is no /Volumes and no mount
/// notifications on iOS: the floppy (plugged in through a USB adapter) and the
/// iCloud Drive destination folder both arrive via the Files document picker,
/// and access persists across launches through security-scoped bookmarks.
@MainActor
final class MobileAppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case copying(done: Int, total: Int)
        case finished(copied: Int, failed: Int)
    }

    @Published var sourceURL: URL?
    @Published var sourceDisplayName: String?
    @Published var destinationURL: URL?
    @Published var phase: Phase = .idle
    @Published var logLines: [String] = []
    @Published var lastOutcome: CopyOutcome?
    /// Deleted photos hiding in the diskette's trash (Files "deletes" onto the
    /// diskette itself, into a hidden .Trashes folder).
    @Published var trashedFiles: [MavicaFile] = []
    @Published var skipDuplicates: Bool {
        didSet { UserDefaults.standard.set(skipDuplicates, forKey: Self.skipDuplicatesKey) }
    }

    private static let sourceBookmarkKey = "MavicaCopy.sourceBookmark"
    private static let destinationBookmarkKey = "MavicaCopy.destinationBookmark"
    private static let skipDuplicatesKey = "MavicaCopy.skipDuplicates"

    private var floppyWatcher: Timer?

    init() {
        skipDuplicates = UserDefaults.standard.object(forKey: Self.skipDuplicatesKey) as? Bool ?? true
        destinationURL = Self.resolveBookmark(key: Self.destinationBookmarkKey)
        refreshSource()
        watchForFloppy()
    }

    deinit {
        floppyWatcher?.invalidate()
    }

    /// iOS has no volume-mount notifications, but re-resolving the saved
    /// bookmark is cheap — poll it so the last-picked diskette reconnects
    /// within seconds of being plugged in while the app is open.
    private func watchForFloppy() {
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.refreshSource()
                }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        floppyWatcher = timer
    }

    var isCopying: Bool {
        if case .copying = phase { return true }
        return false
    }

    /// The floppy looks like the Mavica's diskette when the picked folder (or
    /// the volume it sits on) carries the camera's MY_PHOTO volume name.
    var sourceLooksLikeFloppy: Bool {
        guard let sourceURL else { return false }
        return sourceDisplayName == MavicaLocations.cameraVolumeName
            || sourceURL.path.contains(MavicaLocations.cameraVolumeName)
    }

    var destinationIsICloud: Bool {
        guard let destinationURL else { return false }
        return destinationURL.path.contains("com~apple~CloudDocs")
            || destinationURL.path.contains("Mobile Documents")
    }

    /// The disk can be emptied only after a copy where every photo was either
    /// copied and hash-verified or skipped as an already-present duplicate.
    var canEmptyDisk: Bool {
        guard case .finished = phase, let lastOutcome, sourceURL != nil else { return false }
        return lastOutcome.failures.isEmpty
            && !(lastOutcome.copied.isEmpty && lastOutcome.skippedDuplicates.isEmpty)
    }

    /// Files (copied or duplicate) that a verified copy makes safe to erase.
    var erasableSourceCount: Int {
        guard let lastOutcome else { return 0 }
        return lastOutcome.copied.count + lastOutcome.skippedDuplicates.count
    }

    /// Files mounts external USB volumes under a UUID-named directory, so the
    /// picked folder's last path component can be a bare UUID. The volume /
    /// localized name is what the user saw in the picker ("MY_PHOTO").
    private static func displayName(for url: URL) -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.localizedNameKey, .volumeNameKey])
        return values?.localizedName ?? values?.volumeName ?? url.lastPathComponent
    }

    // MARK: - Source & destination selection

    /// Re-resolves the saved floppy bookmark. Called at launch and every few
    /// seconds, so re-plugging the drive reconnects the source without another
    /// trip through the picker.
    func refreshSource() {
        if isCopying { return }
        let resolved = Self.resolveBookmark(key: Self.sourceBookmarkKey)
        if let resolved {
            if sourceURL != resolved {
                sourceURL = resolved
                sourceDisplayName = Self.displayName(for: resolved)
                log("Floppy reconnected at \(sourceDisplayName ?? resolved.lastPathComponent).")
                rescanTrash()
            }
        } else if sourceURL != nil {
            sourceURL = nil
            sourceDisplayName = nil
            trashedFiles = []
            log("Floppy is no longer reachable. Plug it in and pick it again if needed.")
        }
    }

    func setSource(_ url: URL) {
        Self.saveBookmark(for: url, key: Self.sourceBookmarkKey)
        sourceURL = url
        sourceDisplayName = Self.displayName(for: url)
        log("Source set to \(sourceDisplayName ?? url.lastPathComponent).")
        rescanTrash()
    }

    func setDestination(_ url: URL) {
        Self.saveBookmark(for: url, key: Self.destinationBookmarkKey)
        destinationURL = url
        log("Destination set to \(url.lastPathComponent)\(destinationIsICloud ? " (iCloud Drive)" : "").")
    }

    /// Checks the diskette's hidden trash in the background and updates the UI.
    func rescanTrash() {
        guard let sourceURL else { return }
        Task.detached(priority: .utility) { [weak self] in
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            let trashed = MavicaScanner.scan(in: sourceURL).trashed
            self?.onMain { model in
                guard model.sourceURL == sourceURL else { return }
                if trashed.count != model.trashedFiles.count, !trashed.isEmpty {
                    let count = trashed.count
                    model.log("\(count) deleted photo\(count == 1 ? "" : "s") still hiding in the diskette's trash.")
                }
                model.trashedFiles = trashed
            }
        }
    }

    // MARK: - Copying

    func startCopy() {
        guard let sourceURL, let destinationURL, !isCopying else { return }
        let skipDuplicates = skipDuplicates
        phase = .copying(done: 0, total: 0)
        lastOutcome = nil
        log("Scanning \(sourceDisplayName ?? sourceURL.lastPathComponent)…")

        Task.detached(priority: .userInitiated) { [weak self] in
            let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
            let destinationAccess = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
                if destinationAccess { destinationURL.stopAccessingSecurityScopedResource() }
            }

            let scan = MavicaScanner.scan(in: sourceURL)
            self?.onMain { model in
                model.trashedFiles = scan.trashed
            }
            let files = scan.photos
            guard !files.isEmpty else {
                self?.onMain { model in
                    model.log("No JPEG photos found.")
                    model.phase = .finished(copied: 0, failed: 0)
                }
                return
            }
            self?.onMain { model in
                model.log("Found \(files.count) photo\(files.count == 1 ? "" : "s"). Copying…")
                model.phase = .copying(done: 0, total: files.count)
            }

            let outcome = CopyEngine().copy(
                files: files,
                into: destinationURL,
                skipDuplicates: skipDuplicates
            ) { done, total, event in
                self?.onMain { model in
                    model.phase = .copying(done: done, total: total)
                    switch event {
                    case let .copied(name):
                        model.log("Copied and verified \(name)")
                    case let .skippedDuplicate(sourceName, existingName):
                        model.log("Skipped \(sourceName) — already copied as \(existingName)")
                    case let .failed(sourceName, message):
                        model.log("Failed: \(sourceName) — \(message)")
                    }
                }
            }

            self?.onMain { model in
                model.lastOutcome = outcome
                model.phase = .finished(copied: outcome.copied.count, failed: outcome.failures.count)
                var summary = "Done. \(outcome.copied.count) copied and verified, \(outcome.failures.count) failed."
                if !outcome.skippedDuplicates.isEmpty {
                    summary += " \(outcome.skippedDuplicates.count) duplicate\(outcome.skippedDuplicates.count == 1 ? "" : "s") skipped."
                }
                model.log(summary)
            }
        }
    }

    // MARK: - Emptying the diskette

    /// Deletes the hidden trashed photos from the diskette.
    func emptyTrash() {
        guard let sourceURL, !isCopying, !trashedFiles.isEmpty else { return }
        let files = trashedFiles.map(\.url)
        log("Emptying the diskette's trash…")
        Task.detached(priority: .userInitiated) { [weak self] in
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            let errors = DiskCleaner.delete(files: files)
            self?.onMain { model in
                for message in errors {
                    model.log("Could not delete \(message)")
                }
                model.log("Trash emptied. \(files.count - errors.count) deleted photo\(files.count - errors.count == 1 ? "" : "s") removed from the diskette.")
                model.rescanTrash()
            }
        }
    }

    /// Deletes every photo the last copy verified (copied or already-present
    /// duplicate) from the diskette, plus anything in its hidden trash,
    /// leaving the diskette empty for the Mavica.
    func emptyDisk() {
        guard let sourceURL, canEmptyDisk, let lastOutcome else { return }
        var files = lastOutcome.copied.map(\.source)
        files += lastOutcome.skippedDuplicates.map(\.source)
        files += trashedFiles.map(\.url)
        log("Emptying the diskette…")
        Task.detached(priority: .userInitiated) { [weak self] in
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            let errors = DiskCleaner.delete(files: files)
            self?.onMain { model in
                for message in errors {
                    model.log("Could not delete \(message)")
                }
                model.log("Diskette emptied. \(files.count - errors.count) file\(files.count - errors.count == 1 ? "" : "s") removed.")
                model.lastOutcome = nil
                model.phase = .idle
                model.rescanTrash()
            }
        }
    }

    /// Hops a UI update to the main queue. DispatchQueue.main is FIFO, so the
    /// completion update can never be overtaken by a late progress update
    /// (Task { @MainActor } hops carry no such ordering guarantee).
    nonisolated private func onMain(_ update: @escaping @MainActor (MobileAppModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
    }

    /// Opens the destination folder in the Files app.
    func openDestinationInFiles() {
        guard let destinationURL else { return }
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = destinationURL.path
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Bookmarks

    private static func saveBookmark(for url: URL, key: String) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: key)
        } catch {
            // The picked URL still works this session; it just will not
            // survive a relaunch.
        }
    }

    private static func resolveBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            saveBookmark(for: url, key: key)
        }
        return url
    }

    // MARK: - Private

    private func log(_ message: String) {
        logLines.append(message)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }
}
