import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: OffloadSession
    @Environment(\.dismiss) private var dismiss

    @State private var limitByDate = false
    @State private var since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Layout", selection: $session.settings.organization) {
                        ForEach(OffloadSettings.Organization.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Text(session.settings.organization.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("On the drive")
                } footer: {
                    Text("Where each file ends up inside the folder you picked.")
                }

                Section("What to copy") {
                    Toggle("Photos and RAW", isOn: $session.settings.includePhotos)
                    Toggle("Videos", isOn: $session.settings.includeVideos)
                    Toggle("Sidecar files", isOn: $session.settings.includeSidecars)
                }

                Section {
                    Toggle("Only recent files", isOn: $limitByDate)
                    if limitByDate {
                        DatePicker("Taken since", selection: $since, displayedComponents: .date)
                    }
                } footer: {
                    Text("Useful when the card holds months of shoots and you only want today's.")
                }

                Section {
                    Toggle("Skip files already on the drive", isOn: $session.settings.skipExisting)
                    Toggle("Verify every copy", isOn: $session.settings.verifyAfterCopy)
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Verifying re-reads each file from the drive and compares it with the card, "
                         + "so a bad cable can't quietly corrupt a shoot. It makes the copy slower.")
                }

                Section {
                    LabeledContent("Never deletes from the card") {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                } footer: {
                    Text("This app only reads the card. Format it in the camera when you are sure "
                         + "the copy is somewhere safe.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                limitByDate = session.settings.since != nil
                if let existing = session.settings.since { since = existing }
            }
            .onChange(of: limitByDate) { _, enabled in
                session.settings.since = enabled ? Calendar.current.startOfDay(for: since) : nil
            }
            .onChange(of: since) { _, newValue in
                guard limitByDate else { return }
                session.settings.since = Calendar.current.startOfDay(for: newValue)
            }
            .onDisappear {
                // Filters change what is on the list, so the card has to be re-read.
                if session.phase == .ready || session.phase == .finished {
                    session.scan()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(OffloadSession())
}
