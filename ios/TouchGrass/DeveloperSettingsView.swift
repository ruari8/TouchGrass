import SwiftUI

/// Only reachable in debug and TestFlight builds: switch between the Grass Checks to compare them.
struct DeveloperSettingsView: View {
    @State private var mode = GrassCheckSettings.mode
    @State private var serverURL = GrassCheckSettings.serverURL
    @State private var serverToken = GrassCheckSettings.serverToken
    @State private var threshold = GrassCheckSettings.onDeviceThreshold

    var body: some View {
        Form {
            Section {
                Picker("Grass Check", selection: $mode) {
                    ForEach(GrassCheckMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Grass Check")
            } footer: {
                Text("App Store builds always use Apple's on-device check. A Touch Grass in these builds shows what the checker saw under the result.")
            }

            if mode == .server {
                Section {
                    TextField("https://touchgrass-grass-check.example.workers.dev", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API token", text: $serverToken)
                } header: {
                    Text("Server")
                } footer: {
                    Text("The Worker in backend/. See docs/grass-check-server.md.")
                }
            }

            if mode != .server {
                Section {
                    LabeledContent("Passes at", value: "\(Int(threshold * 100))%")
                    Slider(value: $threshold, in: 0.1...0.9, step: 0.05)
                } header: {
                    Text("Grass confidence")
                }
            }

            if mode == .customModel, CustomModelGrassChecker.modelURL == nil {
                Section {
                    Label("No GrassClassifier.mlmodel is bundled, so this check will fail.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.locked)
                }
            }
        }
        .navigationTitle("Developer Settings")
        .onChange(of: mode) { _, value in GrassCheckSettings.mode = value }
        .onChange(of: serverURL) { _, value in GrassCheckSettings.serverURL = value.trimmingCharacters(in: .whitespaces) }
        .onChange(of: serverToken) { _, value in GrassCheckSettings.serverToken = value }
        .onChange(of: threshold) { _, value in GrassCheckSettings.onDeviceThreshold = value }
    }
}
