import AppKit
import SwiftUI
import MavicaCore

/// The floppy symbol only exists in newer SF Symbols sets; fall back gracefully.
private let floppySymbol: String =
    NSImage(systemSymbolName: "floppydisk", accessibilityDescription: nil) != nil
        ? "floppydisk"
        : "externaldrive"

struct ContentView: View {

    @StateObject private var model = AppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceSection
            destinationSection
            actionSection
            logSection
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mavica Copy")
                    .font(.title2.bold())
                Text("Copy Mavica JPEGs, renamed by date, with fixed creation dates.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceSection: some View {
        GroupBox("Source") {
            HStack {
                if let source = model.sourceURL {
                    Button {
                        model.openSourceInFinder()
                    } label: {
                        HStack {
                            Image(systemName: model.sourceIsRemovableVolume ? floppySymbol : "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.lastPathComponent)
                                    .fontWeight(.medium)
                                Text(model.sourceIsAutodetected ? "Mavica floppy, detected automatically" : source.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")
                } else {
                    Image(systemName: floppySymbol)
                        .foregroundStyle(.secondary)
                    Text("Insert a Mavica floppy disk (MY_PHOTO), or choose a folder.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { model.chooseSource() }
                    .disabled(model.isCopying)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var destinationSection: some View {
        GroupBox("Destination") {
            HStack {
                Button {
                    model.openDestinationInFinder()
                } label: {
                    HStack {
                        Image(systemName: destinationIsICloud ? "icloud" : "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.destinationURL.lastPathComponent)
                                .fontWeight(.medium)
                            Text(destinationIsICloud ? "iCloud Drive" : model.destinationURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
                Spacer()
                if !destinationIsICloud {
                    Button("Use iCloud") { model.resetDestinationToICloud() }
                        .disabled(model.isCopying)
                }
                Button("Choose…") { model.chooseDestination() }
                    .disabled(model.isCopying)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.startCopy()
                } label: {
                    Label("Copy Photos", systemImage: "square.and.arrow.down.on.square")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.sourceURL == nil || model.isCopying)

                if case .finished = model.phase {
                    Button("Show in Finder") { model.revealDestination() }
                    if model.sourceIsRemovableVolume {
                        Button {
                            model.ejectSource()
                        } label: {
                            Label("Eject Floppy", systemImage: "eject")
                        }
                    }
                }
                Spacer()
                statusText
            }

            if case let .copying(done, total) = model.phase, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case let .copying(done, total):
            Text(total > 0 ? "Copying \(done) of \(total)…" : "Scanning…")
                .foregroundStyle(.secondary)
        case let .finished(copied, failed):
            if failed > 0 {
                Label("\(copied) copied, \(failed) failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Label("\(copied) copied", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }

    private var logSection: some View {
        GroupBox("Activity") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 150)
                .onChange(of: model.logLines.count) { count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var destinationIsICloud: Bool {
        model.destinationURL.path.contains("Mobile Documents/com~apple~CloudDocs")
    }
}
