import SwiftUI
import FamilyControls
import BlockOSDomain
import BlockOSEnforcement

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var selectedTab: Tab = .session

    enum Tab { case session, unlockMethods, history }

    var body: some View {
        VStack(spacing: 0) {
            // Main Content Area
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                switch selectedTab {
                case .session: SessionView()
                case .unlockMethods: QRCodesView()
                case .history: HistoryView()
                }
            }

            // Refined Tab Bar
            HStack(spacing: 0) {
                TabButton(icon: "lock.shield", title: "Focus", tab: .session, selectedTab: $selectedTab)
                TabButton(icon: "key", title: "Unlocks", tab: .unlockMethods, selectedTab: $selectedTab)
                TabButton(icon: "clock", title: "History", tab: .history, selectedTab: $selectedTab)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: -5)
        }
        .task {
            await container.refresh()
        }
    }
}

private struct TabButton: View {
    let icon: String
    let title: String
    let tab: RootView.Tab
    @Binding var selectedTab: RootView.Tab

    var body: some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab 
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? icon + ".fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

private struct SessionView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isActivityPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("BlockOS")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Circle()
                    .fill(container.activeSession != nil ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            if let errorMessage = container.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if let activeSession = container.activeSession {
                        ActiveSessionView(session: activeSession)
                    } else {
                        SetupSessionView(isPickerPresented: $isActivityPickerPresented)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .familyActivityPicker(isPresented: $isActivityPickerPresented, selection: $container.activitySelection)
        .onChange(of: container.activitySelection) { _, selection in
            Task { await container.persistSelection(selection) }
        }
    }
}

private struct ActiveSessionView: View {
    @EnvironmentObject private var container: AppContainer
    let session: FocusSession
    
    var body: some View {
        VStack(spacing: 32) {
            // Status Hero
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 120, height: 120)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.primary)
                }
                
                VStack(spacing: 4) {
                    Text("Focus is Active")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Selected apps are currently hidden.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 32)

            if session.state == .unlockChallengeInProgress,
               session.activeUnlockMethod == .timer120,
               let startedAt = session.activeUnlockStartedAt {
                TimerUnlockElegant(startedAt: startedAt)
            } else {
                // Actions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Need to unlock?")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if session.state == .activeBlocked {
                        ActionCard(
                            icon: "timer",
                            title: "Wait 2 Minutes",
                            subtitle: "Create healthy friction before unlocking.",
                            action: { Task { await container.beginUnlock(.timer120) } }
                        )
                        
                        ActionCard(
                            icon: "qrcode.viewfinder",
                            title: "Scan a QR Code",
                            subtitle: "Physical barrier to unlock apps.",
                            action: { Task { await container.beginUnlock(.qrCode) } }
                        )
                    }
                    
                    if session.state == .unlockChallengeInProgress && session.activeUnlockMethod == .qrCode {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                                Text("Ready to scan your physical QR code.")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(20)
                            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
                            
                            ElegantButton(title: "Cancel Unlock", isPrimary: false) {
                                Task { await container.cancelUnlock() }
                            }
                        }
                    }
                    
                    if session.state == .unlockPending {
                        VStack(spacing: 12) {
                            ElegantButton(title: "Confirm Unlock", isPrimary: true) {
                                Task { await container.confirmUnlock() }
                            }
                            ElegantButton(title: "Cancel", isPrimary: false) {
                                Task { await container.cancelUnlock() }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SetupSessionView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var isPickerPresented: Bool

    var body: some View {
        VStack(spacing: 32) {
            // Hero
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.05), radius: 20, y: 10)
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.primary)
                }
                
                VStack(spacing: 4) {
                    Text("Reclaim your time.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Block distracting apps and create healthy friction.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)

            // Configuration
            VStack(spacing: 16) {
                if container.authorizationStatus != .approved {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 1")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        ActionCard(
                            icon: "shield.righthalf.filled",
                            title: "Allow Screen Time Access",
                            subtitle: "Required to block apps on this device.",
                            action: { Task { await container.requestAuthorization() } }
                        )
                    }
                }
                
                if container.authorizationStatus == .approved {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Configuration")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Button(action: { isPickerPresented = true }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle().fill(Color.primary.opacity(0.05)).frame(width: 40, height: 40)
                                    Image(systemName: "app.badge.checkmark").foregroundColor(.primary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apps to Block")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                    
                                    if !container.makePreviewTargets().isEmpty {
                                        Text(container.selectionSummary)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text("Tap to select apps")
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(16)
                            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
                        }
                    }
                }
            }

            Spacer(minLength: 24)

            // Main Action
            if container.authorizationStatus == .approved {
                ElegantButton(
                    title: "Start Focus Session",
                    isPrimary: true,
                    isDisabled: container.makePreviewTargets().isEmpty
                ) {
                    Task { await container.startSession() }
                }
            }
        }
    }
}

private struct TimerUnlockElegant: View {
    @EnvironmentObject private var container: AppContainer
    let startedAt: Date
    private let duration: TimeInterval = 120
    @State private var didTriggerCompletion = false
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, duration - context.date.timeIntervalSince(startedAt))
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(timeString(for: remaining))
                        .font(.system(size: 72, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    
                    Text("Breathe. Do you really need to open this?")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
                
                if remaining > 0 {
                    ElegantButton(title: "I Changed My Mind", isPrimary: false) {
                        Task { await container.cancelUnlock() }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Unlocking...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 32))
            .shadow(color: Color.black.opacity(0.05), radius: 20, y: 10)
            .onChange(of: remaining <= 0) { _, hasElapsed in
                guard hasElapsed, !didTriggerCompletion else { return }
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

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
        }
    }
}

private struct ElegantButton: View {
    let title: String
    let isPrimary: Bool
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    isPrimary 
                        ? (isDisabled ? Color.primary.opacity(0.3) : Color.primary) 
                        : Color.clear
                )
                .foregroundColor(
                    isPrimary ? Color(UIColor.systemBackground) : .primary
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isPrimary ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isDisabled)
    }
}

private struct QRCodesView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Physical Unlocks")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
            
            Text("Print and place QR codes away from your typical phone scrolling spots.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Create New
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create New Code")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        VStack(spacing: 16) {
                            TextField("E.g., Kitchen Fridge, Car Dashboard", text: $newLabel)
                                .font(.system(size: 16, design: .rounded))
                                .padding()
                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                            
                            ElegantButton(title: "Generate QR Code", isPrimary: true, isDisabled: newLabel.isEmpty) {
                                Task { 
                                    await container.generateQRCode(label: newLabel)
                                    newLabel = ""
                                }
                            }
                        }
                        .padding(20)
                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        .shadow(color: Color.black.opacity(0.02), radius: 10, y: 5)
                    }
                    
                    // Saved Codes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Codes")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        if container.qrTokens.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No codes created yet.")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                            .shadow(color: Color.black.opacity(0.02), radius: 10, y: 5)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(container.qrTokens) { token in
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.primary.opacity(0.04))
                                                .frame(width: 56, height: 56)
                                            Image(systemName: "qrcode")
                                                .font(.system(size: 24))
                                                .foregroundColor(.primary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(token.label)
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            Text("Scanned \(token.lastScannedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Never")")
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        if container.activeSession?.state == .unlockChallengeInProgress,
                                           container.activeSession?.activeUnlockMethod == .qrCode {
                                            Button("Simulate") {
                                                Task { await container.unlockWithQRCode(token) }
                                            }
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.primary, in: Capsule())
                                            .foregroundColor(Color(UIColor.systemBackground))
                                        }
                                    }
                                    .padding(16)
                                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                    .shadow(color: Color.black.opacity(0.02), radius: 10, y: 5)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session History")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            
            ScrollView(showsIndicators: false) {
                if container.sessionHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No completed sessions yet.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 16) {
                        ForEach(container.sessionHistory.reversed(), id: \.id) { session in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.state.displayName)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Circle()
                                        .fill(session.state == .completed ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: session.state == .completed ? "checkmark" : "xmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(session.state == .completed ? .green : .red)
                                        )
                                }
                                
                                if !session.unlockHistory.isEmpty {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Unlocks")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .textCase(.uppercase)
                                        
                                        ForEach(session.unlockHistory, id: \.id) { attempt in
                                            HStack(spacing: 8) {
                                                Image(systemName: attempt.method == .timer120 ? "timer" : "qrcode")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                                Text(attempt.method.displayName)
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                Spacer()
                                                Text(attempt.outcome.displayName)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundColor(attempt.outcome == .succeeded ? .primary : .secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

private extension FocusSessionState {
    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .arming: "Starting..."
        case .activeBlocked: "Active"
        case .unlockChallengeInProgress: "Unlocking"
        case .unlockPending: "Ready to Unlock"
        case .unlockedGrace: "Paused"
        case .completed: "Completed"
        case .abortedEmergencyOverride: "Aborted"
        }
    }
}

private extension RestrictionAuthorizationStatus {
    var displayName: String {
        switch self {
        case .notDetermined: "Not Granted"
        case .denied: "Denied"
        case .approved: "Approved"
        }
    }
}

private extension UnlockMethod {
    var displayName: String {
        switch self {
        case .timer120: "2-Min Wait"
        case .qrCode: "QR Code"
        }
    }
}

private extension UnlockAttemptOutcome {
    var displayName: String {
        switch self {
        case .succeeded: "Success"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .emergencyOverride: "Override"
        }
    }
}

private extension BlockTarget.Kind {
    var systemImageName: String {
        switch self {
        case .application: "app.fill"
        case .category: "square.grid.2x2.fill"
        case .webDomain: "globe"
        }
    }
}
