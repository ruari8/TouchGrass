import SwiftUI
import FamilyControls
import UIKit
import BlockOSDomain
import BlockOSEnforcement

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var selectedTab: Tab = .session
    @State private var errorBannerTask: Task<Void, Never>?

    enum Tab { case session, challenges, history }

    var body: some View {
        Group {
            if !container.hasLoadedInitialState {
                ZStack {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                    ProgressView()
                }
            } else if !container.hasCompletedOnboarding {
                OnboardingFlowView()
            } else {
                VStack(spacing: 0) {
                    // Main Content Area
                    ZStack {
                        Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                        
                        switch selectedTab {
                        case .session: SessionView()
                        case .challenges: ChallengeSettingsView()
                        case .history: HistoryView()
                        }
                    }

                    // Refined Tab Bar
                    HStack(spacing: 0) {
                        TabButton(icon: "lock.shield", title: "Focus", tab: .session, selectedTab: $selectedTab)
                        TabButton(icon: "figure.walk", title: "Tasks", tab: .challenges, selectedTab: $selectedTab)
                        TabButton(icon: "clock", title: "History", tab: .history, selectedTab: $selectedTab)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 10, y: -5)
                }
            }
        }
        .task {
            await container.refresh()
        }
        .onChange(of: container.errorMessage) { _, message in
            errorBannerTask?.cancel()

            guard message != nil else { return }

            errorBannerTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    container.clearErrorMessage()
                }
            }
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
                HStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        container.clearErrorMessage()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
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
        .onChange(of: container.activitySelection) { previousSelection, selection in
            Task { await container.persistSelection(selection, previousSelection: previousSelection) }
        }
    }
}

private struct ActiveSessionView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isActivityPickerPresented = false
    @State private var isEmergencyOverrideConfirmationPresented = false
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
                    Text("Selected apps are blocked until you complete a real-world task.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 16) {
                Text("Configuration")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                ActionCard(
                    icon: "slider.horizontal.3",
                    title: "Add More Blocks",
                    subtitle: "\(container.selectionSummary) • You can only add more during focus",
                    action: { isActivityPickerPresented = true }
                )
            }

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
                            icon: "camera.viewfinder",
                            title: "Touch Grass",
                            subtitle: "Take a proof photo of the real-world prompt.",
                            action: { Task { await container.beginUnlock(.touchGrassPhoto) } }
                        )

                        ActionCard(
                            icon: "timer",
                            title: "Wait 2 Minutes",
                            subtitle: "Backup friction if the camera is unavailable.",
                            action: { Task { await container.beginUnlock(.timer120) } }
                        )
                    }

                    if session.state == .unlockChallengeInProgress && session.activeUnlockMethod == .touchGrassPhoto {
                        TouchGrassUnlockView(sessionID: session.id)
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

            if session.overridePolicy.allowsEmergencyOverride {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Need immediate access?")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    DangerButton(title: "Emergency Unblock") {
                        isEmergencyOverrideConfirmationPresented = true
                    }
                }
            }
        }
        .familyActivityPicker(isPresented: $isActivityPickerPresented, selection: $container.activitySelection)
        .alert("Emergency unblock?", isPresented: $isEmergencyOverrideConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("End Focus Now", role: .destructive) {
                Task { await container.emergencyOverride() }
            }
        } message: {
            Text("This immediately removes all active restrictions and ends the current focus session.")
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
                    Text("Set daily limits. When you hit them, your phone gets dumb until you move.")
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
                            title: container.isLoading ? "Requesting Access..." : "Allow Screen Time Access",
                            subtitle: "Required to block apps on this device.",
                            action: {
                                guard !container.isLoading else { return }
                                Task { await container.requestAuthorization() }
                            },
                            showsProgress: container.isLoading
                        )
                    }
                }
                
                if container.authorizationStatus == .approved {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Configuration")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        if let goalPlanSummary = container.goalPlanSummary {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Daily Goal")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(goalPlanSummary)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                if let focus = container.onboardingProfile?.goalPlan?.reductionFocus {
                                    Text("Primary reduction target: \(focus)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(16)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                        }

                        if let dailyLimitSummary = container.dailyLimitSummary {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Auto Block")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(dailyLimitSummary)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            .padding(16)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                        }
                        
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

private struct TouchGrassUnlockView: View {
    @EnvironmentObject private var container: AppContainer
    let sessionID: UUID
    @State private var isCameraPresented = false
    @State private var capturedImage: UIImage?

    private var prompt: String {
        TouchGrassChallenge.prompt(for: sessionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.green.opacity(0.15), in: Circle())
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Touch Grass Challenge")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(prompt)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .clipped()
            }

            VStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    ElegantButton(title: capturedImage == nil ? "Open Camera" : "Retake Photo", isPrimary: true) {
                        isCameraPresented = true
                    }
                } else {
                    ElegantButton(title: "Mark Task Complete", isPrimary: true) {
                        Task { await container.completeTouchGrassUnlock() }
                    }
                }

                ElegantButton(title: "Cancel Unlock", isPrimary: false) {
                    Task { await container.cancelUnlock() }
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
        .sheet(isPresented: $isCameraPresented) {
            CameraCaptureView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, image in
            guard image != nil else {
                return
            }

            Task { await container.completeTouchGrassUnlock() }
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var image: UIImage?
        private let dismiss: DismissAction

        init(image: Binding<UIImage?>, dismiss: DismissAction) {
            _image = image
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            image = info[.originalImage] as? UIImage
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private enum TouchGrassChallenge {
    private static let prompts = [
        "Take a photo of your hand touching grass.",
        "Go outside and take a photo of a tree or hedge.",
        "Take a photo of your shoes outside your front door.",
        "Take a photo of the washing machine from another room.",
        "Take a photo of daylight through an open doorway."
    ]

    static var previewPrompts: [String] {
        prompts
    }

    static func prompt(for sessionID: UUID) -> String {
        let seed = sessionID.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return prompts[seed % prompts.count]
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
    var showsProgress: Bool = false
    
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
                if showsProgress {
                    ProgressView()
                        .tint(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.3))
                }
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

private struct DangerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct ChallengeSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Unlock Tasks")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)

            Text("BlockOS uses software friction: selected apps lock after your daily limit, then a real-world photo task unlocks them.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Daily limit", systemImage: "hourglass")
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text(container.dailyLimitSummary ?? "Finish onboarding and pick apps to enable automatic blocking.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let goalPlanSummary = container.goalPlanSummary {
                            Text(goalPlanSummary)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color.black.opacity(0.03), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Touch Grass", systemImage: "camera.viewfinder")
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        VStack(spacing: 10) {
                            ForEach(TouchGrassChallenge.previewPrompts, id: \.self) { prompt in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(prompt)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color.black.opacity(0.03), radius: 10, y: 5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
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
                                                Image(systemName: attempt.method.historyIconName)
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
        case .touchGrassPhoto: "Touch Grass"
        }
    }

    var historyIconName: String {
        switch self {
        case .timer120: "timer"
        case .qrCode: "qrcode"
        case .touchGrassPhoto: "camera.viewfinder"
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
