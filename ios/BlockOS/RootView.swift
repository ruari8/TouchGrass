import SwiftUI
import FamilyControls
import BlockOSDomain
import BlockOSEnforcement

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            SessionTab()
            .tabItem {
                Label("Session", systemImage: "hourglass")
            }

            QRCodesTab()
            .tabItem {
                Label("QR Codes", systemImage: "qrcode")
            }

            HistoryTab()
            .tabItem {
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
        }
        .task {
            await container.refresh()
        }
    }
}

private struct SessionTab: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isActivityPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    errorBanner
                    currentStatusCard
                    if let activeSession = container.activeSession {
                        if activeSession.state == .unlockChallengeInProgress,
                           activeSession.activeUnlockMethod == .timer120,
                           let startedAt = activeSession.activeUnlockStartedAt {
                            TimerUnlockCard(startedAt: startedAt)
                        }
                        unlockActionsCard(for: activeSession)
                    } else {
                        sessionSetupCard
                    }
                    historySummaryCard
                }
                .padding(20)
            }
            .navigationTitle("Session")
            .familyActivityPicker(isPresented: $isActivityPickerPresented, selection: $container.activitySelection)
            .onChange(of: container.activitySelection) { _, selection in
                Task { await container.persistSelection(selection) }
            }
            .toolbar {
                if container.isLoading {
                    ProgressView()
                }
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = container.errorMessage {
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Status")
                .font(.headline)
            if let activeSession = container.activeSession {
                Text(activeSession.state.displayName)
                    .font(.title3.weight(.semibold))
                Text("Focus set: \(activeSession.blockSet.name)")
                    .foregroundStyle(.secondary)
            } else {
                Text("No active session")
                    .font(.title3.weight(.semibold))
                Text("Start a sample focus session to exercise the timer and QR unlock flows.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var sessionSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phase 0 Blocking Prototype")
                .font(.headline)
            Text(container.blockingModeDescription)
                .foregroundStyle(.secondary)

            if container.supportsSystemBlocking {
                LabeledContent("Authorization", value: container.authorizationStatus.displayName)
            }

            Text("Blocked Targets")
                .font(.subheadline.weight(.semibold))
            Text(container.selectionSummary)
                .foregroundStyle(.secondary)

            ForEach(container.makePreviewTargets()) { target in
                Label(target.displayName, systemImage: target.kind.systemImageName)
                    .font(.subheadline)
            }

            if container.supportsSystemBlocking {
                Button("Grant Blocking Access") {
                    Task { await container.requestAuthorization() }
                }
                .buttonStyle(.bordered)
                .disabled(container.activeSession != nil)

                Button("Choose Apps To Block") {
                    isActivityPickerPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(container.activeSession != nil || container.authorizationStatus != .approved)
            }

            Button("Start Focus Session") {
                Task { await container.startSession() }
            }
            .buttonStyle(.borderedProminent)
            .disabled((container.supportsSystemBlocking && container.authorizationStatus != .approved) || container.makePreviewTargets().isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func unlockActionsCard(for session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unlock Actions")
                .font(.headline)
            Text("Allowed methods: \(session.allowedUnlockMethods.map(\.displayName).joined(separator: ", "))")
                .foregroundStyle(.secondary)

            if session.state == .activeBlocked {
                Button("Start 120-Second Timer") {
                    Task { await container.beginUnlock(.timer120) }
                }
                .buttonStyle(.borderedProminent)

                Button("Start QR Unlock") {
                    Task { await container.beginUnlock(.qrCode) }
                }
                .buttonStyle(.bordered)
            }

            if session.state == .unlockChallengeInProgress,
               session.activeUnlockMethod == .qrCode {
                Text("Use the QR Codes tab to simulate scanning one of the generated codes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Cancel Unlock") {
                    Task { await container.cancelUnlock() }
                }
                .buttonStyle(.bordered)
            }

            if session.state == .unlockPending {
                Button("Confirm Unlock") {
                    Task { await container.confirmUnlock() }
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel Unlock") {
                    Task { await container.cancelUnlock() }
                }
                .buttonStyle(.bordered)
            }

            Button("Emergency Override") {
                Task { await container.emergencyOverride() }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var historySummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
            if container.sessionHistory.isEmpty {
                Text("No completed sessions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(container.sessionHistory.suffix(3).reversed(), id: \.id) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.blockSet.name)
                            .font(.subheadline.weight(.semibold))
                        Text(session.state.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TimerUnlockCard: View {
    @EnvironmentObject private var container: AppContainer
    let startedAt: Date

    private let duration: TimeInterval = 120
    @State private var didTriggerCompletion = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, duration - context.date.timeIntervalSince(startedAt))
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer Unlock")
                    .font(.headline)
                Text(timeString(for: remaining))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Wait out the full countdown. Once it reaches zero, BlockOS removes the shield automatically.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") {
                        Task { await container.cancelUnlock() }
                    }
                    .buttonStyle(.bordered)

                    if remaining > 0 {
                        Text("Unlocks automatically at 00:00")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView("Unlocking…")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: remaining <= 0) { _, hasElapsed in
                guard hasElapsed, !didTriggerCompletion else {
                    return
                }

                didTriggerCompletion = true
                Task { await container.completeTimerUnlock() }
            }
        }
    }

    private func timeString(for remaining: TimeInterval) -> String {
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct QRCodesTab: View {
    @EnvironmentObject private var container: AppContainer
    @State private var newLabel = "Home Office"

    var body: some View {
        NavigationStack {
            List {
                Section("Create QR Code") {
                    TextField("Label", text: $newLabel)
                    Button("Generate QR Code") {
                        Task { await container.generateQRCode(label: newLabel) }
                    }
                }

                Section("Saved Codes") {
                    if container.qrTokens.isEmpty {
                        Text("No QR codes yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(container.qrTokens) { token in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(token.label)
                                    .font(.headline)
                                Text(token.payload)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let lastScannedAt = token.lastScannedAt {
                                    Text("Last used: \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if container.activeSession?.state == .unlockChallengeInProgress,
                                   container.activeSession?.activeUnlockMethod == .qrCode {
                                    Button("Use This Code To Unlock") {
                                        Task { await container.unlockWithQRCode(token) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("QR Codes")
        }
    }
}

private struct HistoryTab: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        NavigationStack {
            List {
                if container.sessionHistory.isEmpty {
                    Text("No sessions completed yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(container.sessionHistory.reversed(), id: \.id) { session in
                        Section(session.blockSet.name) {
                            LabeledContent("State", value: session.state.displayName)
                            LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            if let endedAt = session.endedAt {
                                LabeledContent("Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if session.unlockHistory.isEmpty {
                                Text("No unlock attempts recorded.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(session.unlockHistory, id: \.id) { attempt in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(attempt.method.displayName): \(attempt.outcome.displayName)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(attempt.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private extension FocusSessionState {
    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .arming:
            "Arming"
        case .activeBlocked:
            "Active and Blocked"
        case .unlockChallengeInProgress:
            "Unlock in Progress"
        case .unlockPending:
            "Unlock Pending"
        case .unlockedGrace:
            "Unlocked Grace"
        case .completed:
            "Completed"
        case .abortedEmergencyOverride:
            "Emergency Override"
        }
    }
}

private extension RestrictionAuthorizationStatus {
    var displayName: String {
        switch self {
        case .notDetermined:
            "Not granted"
        case .denied:
            "Denied"
        case .approved:
            "Approved"
        }
    }
}

private extension UnlockMethod {
    var displayName: String {
        switch self {
        case .timer120:
            "120-second timer"
        case .qrCode:
            "QR code"
        }
    }
}

private extension UnlockAttemptOutcome {
    var displayName: String {
        switch self {
        case .succeeded:
            "Succeeded"
        case .cancelled:
            "Cancelled"
        case .failed:
            "Failed"
        case .emergencyOverride:
            "Emergency override"
        }
    }
}

private extension BlockTarget.Kind {
    var systemImageName: String {
        switch self {
        case .application:
            "app.fill"
        case .category:
            "square.grid.2x2.fill"
        case .webDomain:
            "globe"
        }
    }
}
