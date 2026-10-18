import SwiftUI
import TouchGrassCore

/// Take a photo, check it for grass, and on success release every active Lock.
struct TouchGrassFlow: View {
    enum Mode {
        /// Ends or pauses the active Locks.
        case unlock
        /// A practice run during setup that changes nothing.
        case practice
    }

    enum Phase {
        case ready
        case checking
        case passed
        case failed(String)
    }

    let mode: Mode
    var onFinish: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.ready
    @State private var isShowingCamera = false
    private let checker: GrassChecker = OnDeviceGrassChecker()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            content
            Spacer()
        }
        .padding(24)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraView { image in
                isShowingCamera = false
                Task { await check(image) }
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled(isChecking)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready:
            Image(systemName: "leaf.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.grass)
            Text("Go touch grass")
                .font(.largeTitle.bold())
            Text("Head outside and take a photo of real grass. Other plants don't count.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open camera") { isShowingCamera = true }
                .buttonStyle(.primary)
                .disabled(!CameraView.isAvailable)
            if !CameraView.isAvailable {
                Text("This device has no camera.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .checking:
            ProgressView()
                .controlSize(.large)
            Text("Checking for grass…")
                .foregroundStyle(.secondary)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.grass)
            Text(mode == .practice ? "That's grass." : "You touched grass.")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(passedDetail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { finish() }
                .buttonStyle(.primary)
        case let .failed(reason):
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.locked)
            Text("That's not grass.")
                .font(.largeTitle.bold())
            Text(reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") { isShowingCamera = true }
                .buttonStyle(.primary)
            Button("Cancel") { finish() }
        }
    }

    private var isChecking: Bool {
        if case .checking = phase { true } else { false }
    }

    private var passedDetail: String {
        switch mode {
        case .practice:
            return "That's all it takes to get out of a Lock."
        case .unlock:
            if let breakEnd = model.state.breakEnds(at: .now) {
                return "You're on a Break until \(breakEnd.formatted(date: .omitted, time: .shortened))."
            }
            return model.isLocked() ? "Some apps are still locked." : "Your apps are unlocked."
        }
    }

    private func check(_ image: UIImage) async {
        phase = .checking
        do {
            let verdict = try await checker.check(image)
            guard verdict.passed else {
                phase = .failed("Make sure real grass fills most of the photo.")
                return
            }
            if mode == .unlock {
                model.recordTouchGrass()
            }
            phase = .passed
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}
