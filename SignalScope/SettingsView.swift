import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("SignalScope.baseURL") private var storedBaseURL: String = ""
    @AppStorage("SignalScope.token") private var storedToken: String = ""
    @AppStorage("SignalScope.refreshInterval") private var storedRefresh: Double = 20

    @State private var baseURL: String = ""
    @State private var token: String = ""
    @State private var refresh: Double = 20
    @State private var didLoad = false

    private let presetIntervals: [Double] = [5, 10, 15, 20, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("https://hub.example.com", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Refresh") {
                    Picker("Interval", selection: $refresh) {
                        ForEach(presetIntervals, id: \.self) { interval in
                            Text("Every \(Int(interval))s").tag(interval)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: $refresh, in: 5...120, step: 5)
                        Text("Every \(Int(refresh)) seconds")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notifications") {
                    Toggle("Chain fault alerts", isOn: $appModel.chainNotificationsEnabled)
                        .tint(Theme.brandBlue)

                    Toggle("Silence monitoring", isOn: $appModel.silenceNotificationsEnabled)
                        .tint(Theme.brandBlue)

                    if appModel.silenceNotificationsEnabled {
                        NavigationLink {
                            SilenceNodePickerView()
                                .environmentObject(appModel)
                        } label: {
                            HStack {
                                Text("Watched nodes")
                                Spacer()
                                Text("\(appModel.silenceWatchedNodes.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Actions") {
                    Button("Save Settings") {
                        appModel.updateSettings(baseURL: baseURL, token: token, refresh: refresh)
                    }

                    Button("Refresh Now") {
                        Task { await appModel.fetchChains() }
                    }
                }

                Section("Info") {
                    LabeledContent("Status") {
                        Text(appModel.api.baseURL == nil ? "Not configured" : "Configured")
                    }
                    LabeledContent("Hub") {
                        Text(baseURL.trimmed.isEmpty ? "—" : baseURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Active faults") {
                        Text("\(appModel.displayedFaults.count)")
                    }
                    LabeledContent("Acknowledged") {
                        Text("\(appModel.acknowledgedFaultIDs.count)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient)
            .navigationTitle("Settings")
        }
        .onAppear {
            guard !didLoad else { return }
            baseURL = storedBaseURL
            token = storedToken
            refresh = max(5, storedRefresh)
            didLoad = true
        }
    }
}

// MARK: - Silence Node Picker

private struct SilenceNodePickerView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            if appModel.allNodeLabels.isEmpty {
                Text("No nodes available — refresh chains first.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(appModel.allNodeLabels, id: \.self) { label in
                        let isOn = appModel.silenceWatchedNodes.contains(label)
                        Button {
                            appModel.toggleSilenceNode(label)
                        } label: {
                            HStack {
                                Image(systemName: isOn ? "bell.fill" : "bell")
                                    .foregroundStyle(isOn ? Theme.brandBlue : Theme.mutedText)
                                    .frame(width: 20)
                                Text(label)
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.brandBlue)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Alert when level drops below –45 dBFS")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient)
        .navigationTitle("Silence Monitoring")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
