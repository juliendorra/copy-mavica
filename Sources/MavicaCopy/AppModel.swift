import AppKit
import Foundation
import MavicaCore

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case copying(done: Int, total: Int)
        case finished(copied: Int, failed: Int)
    }

    @Published var sourceURL: URL?
    @Published var sourceIsAutodetected = false
    @Published var destinationURL: URL
    @Published var phase: Phase = .idle
    @Published var logLines: [String] = []
    @Published var lastOutcome: CopyOutcome?

    private static let destinationDefaultsKey = "MavicaCopy.destinationPath"
    private var mountObservers: [NSObjectProtocol] = []

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.destinationDefaultsKey) {
            destinationURL = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            destinationURL = MavicaLocations.defaultDestination()
        }
        refreshSource()
        watchVolumeMounts()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in mountObservers {
            center.removeObserver(observer)
        }
    }

    var isCopying: Bool {
        if case .copying = phase { return true }
        return false
    }

    var sourceIsRemovableVolume: Bool {
        guard let sourceURL else { return false }
        return sourceURL.path.hasPrefix("/Volumes/")
    }

    // MARK: - Source & destination selection

    func refreshSource() {
        // Never fight an explicit manual choice that still exists on disk.
        if let sourceURL, !sourceIsAutodetected,
           FileManager.default.fileExists(atPath: sourceURL.path) {
            return
        }
        if let detected = MavicaLocations.autodetectedCameraVolume() {
            if sourceURL != detected {
                sourceURL = detected
                sourceIsAutodetected = true
                log("Mavica floppy detected at \(detected.path)")
            }
        } else if sourceIsAutodetected || sourceURL == nil {
            if sourceURL != nil {
                log("Floppy was ejected.")
            }
            sourceURL = nil
            sourceIsAutodetected = false
        }
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Mavica floppy or photo folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceURL ?? URL(fileURLWithPath: "/Volumes")
        panel.prompt = "Use as Source"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.sourceURL = url
            self.sourceIsAutodetected = false
            self.log("Source set to \(url.path)")
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose the destination folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL.deletingLastPathComponent()
        panel.prompt = "Copy Here"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.destinationURL = url
            UserDefaults.standard.set(url.path, forKey: Self.destinationDefaultsKey)
            self.log("Destination set to \(url.path)")
        }
    }

    func resetDestinationToICloud() {
        destinationURL = MavicaLocations.defaultDestination()
        UserDefaults.standard.removeObject(forKey: Self.destinationDefaultsKey)
        log("Destination reset to \(destinationURL.path)")
    }

    // MARK: - Copying

    func startCopy() {
        guard let sourceURL, !isCopying else { return }
        let destination = destinationURL
        phase = .copying(done: 0, total: 0)
        lastOutcome = nil
        log("Scanning \(sourceURL.path)…")

        Task.detached(priority: .userInitiated) { [weak self] in
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

            let outcome = CopyEngine().copy(files: files, into: destination) { done, total, name in
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
            }
        }
    }

    /// Hops a UI update to the main queue. DispatchQueue.main is FIFO, so the
    /// completion update can never be overtaken by a late progress update
    /// (Task { @MainActor } hops carry no such ordering guarantee).
    nonisolated private func onMain(_ update: @escaping @MainActor (AppModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
    }

    func revealDestination() {
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func openSourceInFinder() {
        guard let sourceURL else { return }
        NSWorkspace.shared.open(sourceURL)
    }

    func openDestinationInFinder() {
        // The default destination may not exist before the first copy;
        // creating it here matches what the copy will do anyway.
        try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(destinationURL)
    }

    func ejectSource() {
        guard let sourceURL, sourceIsRemovableVolume else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: sourceURL)
            log("Ejected \(sourceURL.lastPathComponent).")
        } catch {
            log("Could not eject: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func watchVolumeMounts() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshSource()
                }
            }
            mountObservers.append(observer)
        }
    }

    private func log(_ message: String) {
        logLines.append(message)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }
}
