import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var session: OffloadSession

    @State private var pickingSource = false
    @State private var pickingDestination = false
    @State private var showingSettings = false
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            List {
                folderSection
                findingsSection
                if session.phase == .transferring { progressSection }
                if session.phase == .finished { summarySection }
                actionSection
            }
            .navigationTitle("Card Offload")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .disabled(session.isBusy)
                }
            }
            .fileImporter(isPresented: $pickingSource,
                          allowedContentTypes: [.folder]) { result in
                handle(result) { session.setSource($0) }
            }
            .fileImporter(isPresented: $pickingDestination,
                          allowedContentTypes: [.folder]) { result in
                handle(result) { session.setDestination($0) }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showingResults) {
                ResultsList(results: session.results)
            }
            .alert("Something went wrong",
                   isPresented: .init(get: { session.errorMessage != nil },
                                      set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
        }
    }

    /// Cancelling the picker is not an error, so only a real failure surfaces an alert.
    private func handle(_ result: Result<URL, Error>, assign: (URL) -> Void) {
        switch result {
        case .success(let url):
            assign(url)
        case .failure(let error):
            session.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sections

    private var folderSection: some View {
        Section {
            FolderRow(title: "Copy from",
                      subtitle: "Camera card",
                      name: session.sourceName,
                      placeholder: "Choose the card",
                      symbol: "sdcard",
                      isDetached: session.isDetached(.source)) {
                pickingSource = true
            }

            FolderRow(title: "Copy to",
                      subtitle: "External drive",
                      name: session.destinationName,
                      placeholder: "Choose the drive",
                      symbol: "externaldrive",
                      isDetached: session.isDetached(.destination)) {
                pickingDestination = true
            }
        } header: {
            Text("Folders")
        } footer: {
            Text("Plug both in, then pick the card's DCIM folder and a folder on the drive. "
                 + "The app remembers them for next time.")
        }
        .disabled(session.isBusy)
    }

    @ViewBuilder
    private var findingsSection: some View {
        switch session.phase {
        case .scanning:
            Section("Looking through the card") {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.scanProgress.matches) found")
                            .font(.body.monospacedDigit())
                        Text("\(session.scanProgress.filesSeen) checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .ready where !session.files.isEmpty:
            Section("Ready to copy") {
                LabeledContent("Files", value: "\(session.files.count)")
                LabeledContent("Size", value: Format.bytes(session.totalBytes))
                ForEach(MediaFile.Kind.allCases, id: \.self) { kind in
                    if let count = session.counts[kind], count > 0 {
                        Label {
                            LabeledContent(kind.label, value: "\(count)")
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                    }
                }
            }

        case .ready:
            Section {
                ContentUnavailableView("Nothing new to copy",
                                       systemImage: "checkmark.circle",
                                       description: Text("No matching photos or videos on the card. "
                                                         + "Check the filters in Settings if that seems wrong."))
            }

        default:
            EmptyView()
        }
    }

    private var progressSection: some View {
        Section("\(session.transferProgress.phase.label) \(session.transferProgress.fileIndex) of \(session.transferProgress.totalFiles)") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: session.fractionComplete)
                Text(session.transferProgress.currentFileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text("\(Format.bytes(session.transferProgress.bytesDone)) of \(Format.bytes(session.transferProgress.totalBytes))")
                    Spacer()
                    if let rate = session.throughput {
                        Text(Format.rate(rate))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if let remaining = session.estimatedTimeRemaining {
                    Text("About \(Format.duration(remaining)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = session.summary {
            Section(summary.wasCancelled ? "Stopped" : "Done") {
                LabeledContent("Copied",
                               value: "\(summary.copied) · \(Format.bytes(summary.bytesCopied))")
                if summary.skipped > 0 {
                    LabeledContent("Already on the drive", value: "\(summary.skipped)")
                }
                if summary.failed > 0 {
                    LabeledContent("Failed", value: "\(summary.failed)")
                        .foregroundStyle(.red)
                }
                if summary.duration > 0 {
                    LabeledContent("Took", value: Format.duration(summary.duration))
                }
                Button("See every file") { showingResults = true }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            switch session.phase {
            case .transferring, .scanning:
                Button(role: .destructive) {
                    session.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }

            case .finished:
                Button {
                    session.reset()
                } label: {
                    Label("Scan the card again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

            default:
                Button {
                    session.start()
                } label: {
                    Label("Start copying", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!session.canStart || session.destinationName == nil)
            }
        }
        .buttonStyle(.borderedProminent)
        .listRowBackground(Color.clear)
    }
}

/// One tappable row representing a picked folder.
private struct FolderRow: View {
    let title: String
    let subtitle: String
    let name: String?
    let placeholder: String
    let symbol: String
    let isDetached: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(isDetached ? .orange : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(name ?? placeholder)
                        .font(.body)
                        .foregroundStyle(name == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isDetached {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .tint(.primary)
    }
}

#Preview {
    ContentView()
        .environmentObject(OffloadSession())
}
