import SwiftUI

/// Per-file outcome of the last run. Failures float to the top — those are the
/// only rows anyone actually needs to look at.
struct ResultsList: View {
    let results: [TransferResult]

    @Environment(\.dismiss) private var dismiss

    private var failures: [TransferResult] { results.filter { $0.outcome.isFailure } }
    private var succeeded: [TransferResult] { results.filter { !$0.outcome.isFailure } }

    var body: some View {
        NavigationStack {
            List {
                if !failures.isEmpty {
                    Section("Didn't copy") {
                        ForEach(failures) { ResultRow(result: $0) }
                    }
                }
                Section(failures.isEmpty ? "Files" : "Everything else") {
                    ForEach(succeeded) { ResultRow(result: $0) }
                }
            }
            .navigationTitle("Last run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "tray")
                }
            }
        }
    }
}

private struct ResultRow: View {
    let result: TransferResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.file.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(Format.bytes(result.file.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch result.outcome {
        case .copied: return "checkmark.circle.fill"
        case .skippedAlreadyPresent: return "equal.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch result.outcome {
        case .copied: return .green
        case .skippedAlreadyPresent: return .secondary
        case .failed: return .red
        }
    }

    private var detail: String {
        switch result.outcome {
        case .copied(let destination):
            return destination.deletingLastPathComponent().lastPathComponent
        case .skippedAlreadyPresent:
            return "Already on the drive"
        case .failed(let message):
            return message
        }
    }
}

#Preview {
    ResultsList(results: [])
}
