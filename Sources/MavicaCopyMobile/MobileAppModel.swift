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
    @Published var destinationURL: URL?
    @Published var phase: Phase = .idle
    @Published var logLines: [String] = []
    @Published var lastOutcome: CopyOutcome?

    private static let sourceBookmarkKey = "MavicaCopy.sourceBookmark"
    private static let destinationBookmarkKey = "MavicaCopy.destinationBookmark"

    init() {
        destinationURL = Self.resolveBookmark(key: Self.destinationBookmarkKey)
        refreshSource()
    }

    var isCopying: Bool {
        if case .copying = phase { return true }
        return false
    }

    /// The floppy looks like the Mavica's diskette when the picked folder (or
    /// the volume it sits on) carries the camera's MY_PHOTO volume name.
    var sourceLooksLikeFloppy: Bool {
        guard let sourceURL else { return false }
        return sourceURL.path.contains(MavicaLocations.cameraVolumeName)
    }

    var destinationIsICloud: Bool {
        guard let destinationURL else { return false }
        return destinationURL.path.contains("com~apple~CloudDocs")
            || destinationURL.path.contains("Mobile Documents")
    }

    // MARK: - Source & destination selection

    /// Re-resolves the saved floppy bookmark. Called at launch and whenever the
    /// app returns to the foreground, so re-plugging the drive reconnects the
    /// source without another trip through the picker.
    func refreshSource() {
        if isCopying { return }
        let resolved = Self.resolveBookmark(key: Self.sourceBookmarkKey)
        if let resolved {
            if sourceURL != resolved {
                sourceURL = resolved
                log("Floppy reconnected at \(resolved.lastPathComponent).")
            }
        } else if sourceURL != nil {
            sourceURL = nil
            log("Floppy is no longer reachable. Plug it in and pick it again if needed.")
        }
    }

    func setSource(_ url: URL) {
        Self.saveBookmark(for: url, key: Self.sourceBookmarkKey)
        sourceURL = url
        log("Source set to \(url.lastPathComponent).")
    }

    func setDestination(_ url: URL) {
        Self.saveBookmark(for: url, key: Self.destinationBookmarkKey)
        destinationURL = url
        log("Destination set to \(url.lastPathComponent)\(destinationIsICloud ? " (iCloud Drive)" : "").")
    }

    // MARK: - Copying

    func startCopy() {
        guard let sourceURL, let destinationURL, !isCopying else { return }
        phase = .copying(done: 0, total: 0)
        lastOutcome = nil
        log("Scanning \(sourceURL.lastPathComponent)…")

        Task.detached(priority: .userInitiated) { [weak self] in
            let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
            let destinationAccess = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
                if destinationAccess { destinationURL.stopAccessingSecurityScopedResource() }
            }

            let files = MavicaScanner.jpegFiles(in: sourceURL)
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

            let outcome = CopyEngine().copy(files: files, into: destinationURL) { done, total, name in
                self?.onMain { model in
                    model.phase = .copying(done: done, total: total)
                    model.log("Copied \(name)")
                }
            }

            self?.onMain { model in
                model.lastOutcome = outcome
                for failure in outcome.failures {
                    model.log("Failed: \(failure.source.lastPathComponent) — \(failure.message)")
                }
                model.phase = .finished(copied: outcome.copied.count, failed: outcome.failures.count)
                model.log("Done. \(outcome.copied.count) copied, \(outcome.failures.count) failed.")
                if !outcome.copied.isEmpty {
                    model.log("You can unplug the floppy drive now.")
                }
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
