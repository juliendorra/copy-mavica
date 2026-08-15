import SwiftUI
import UniformTypeIdentifiers
import MavicaCore

struct MobileContentView: View {

    /// One fileImporter serves both folder pickers: attaching two importers to
    /// the same view is unreliable in SwiftUI (only one gets presented).
    private enum PickerTarget {
        case source
        case destination
    }

    @StateObject private var model = MobileAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickerTarget: PickerTarget?
    @State private var pickerIsPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                sourceSection
                destinationSection
                actionSection
                logSection
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refreshSource()
            }
        }
        .fileImporter(
            isPresented: $pickerIsPresented,
            allowedContentTypes: [.folder]
        ) { result in
            guard case let .success(url) = result, let pickerTarget else { return }
            switch pickerTarget {
            case .source:
                model.setSource(url)
            case .destination:
                model.setDestination(url)
            }
        }
    }

    private func presentPicker(for target: PickerTarget) {
        pickerTarget = target
        pickerIsPresented = true
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let source = model.sourceURL {
                        Image(systemName: "floppydisk")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.sourceDisplayName ?? source.lastPathComponent)
                                .fontWeight(.medium)
                            Text(model.sourceLooksLikeFloppy
                                 ? "Mavica floppy diskette"
                                 : "Chosen folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "floppydisk")
                            .foregroundStyle(.secondary)
                        Text("Plug in the floppy drive, then pick the MY_PHOTO diskette.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") { presentPicker(for: .source) }
                        .disabled(model.isCopying)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var destinationSection: some View {
        GroupBox("Destination") {
            HStack {
                if let destination = model.destinationURL {
                    Button {
                        model.openDestinationInFiles()
                    } label: {
                        HStack {
                            Image(systemName: model.destinationIsICloud ? "icloud" : "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(destination.lastPathComponent)
                                    .fontWeight(.medium)
                                Text(model.destinationIsICloud ? "iCloud Drive" : "On this device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                    Text("Pick “Mavica Photos” in iCloud Drive — the same folder the Mac app uses.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { presentPicker(for: .destination) }
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
                .disabled(model.sourceURL == nil || model.destinationURL == nil || model.isCopying)

                Spacer()
                statusText
            }

            if case let .copying(done, total) = model.phase, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
            }

            if case .finished = model.phase {
                Button {
                    model.openDestinationInFiles()
                } label: {
                    Label("Show in Files", systemImage: "folder")
                }
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
}
