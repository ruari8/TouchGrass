import DeviceActivity
import SwiftUI
import TouchGrassCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingTouchGrass = false
    @State private var isConfirmingEmergencyUnlock = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(spacing: 28) {
                        StatusHeader(now: context.date)
                        actions(now: context.date)
                        TodayView(now: context.date)
                        EmergencyUnlockDots(now: context.date)
                        GrassCountView(count: model.state.grassCount)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Touch Grass")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingTouchGrass) {
                TouchGrassFlow(mode: .unlock)
            }
            .alert("Use an Emergency Unlock?", isPresented: $isConfirmingEmergencyUnlock) {
                Button("Unlock everything", role: .destructive) {
                    model.useEmergencyUnlock()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It ends every Lock without touching grass. It comes back in 30 days.")
            }
        }
    }

    @ViewBuilder private func actions(now: Date) -> some View {
        if model.isLocked(at: now) {
            VStack(spacing: 12) {
                Button("Touch Grass") { isShowingTouchGrass = true }
                    .buttonStyle(.primary)
                if model.state.emergencyUnlocks.available(at: now) > 0 {
                    Button("Emergency Unlock") { isConfirmingEmergencyUnlock = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LockButton()
        }
    }
}

/// "Locked", "On a Break" or "Unlocked", plus what's locking you.
private struct StatusHeader: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let state = model.state
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: 44, weight: .bold, design: .rounded))
            if let breakEnd = state.breakEnds(at: now) {
                Text("Locks again in \(breakEnd, style: .timer)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(state.activeLocks(at: now)) { lock in
                Text(description(of: lock))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var title: String {
        if model.isLocked(at: now) { return "Locked" }
        return model.state.breakEnds(at: now) == nil ? "Unlocked" : "On a Break"
    }

    private var symbol: String {
        model.isLocked(at: now) ? "lock.fill" : "leaf.fill"
    }

    private var tint: Color {
        model.isLocked(at: now) ? Theme.locked : Theme.grass
    }

    private func description(of lock: Lock) -> String {
        let state = model.state
        let list = state.blockList(id: lock.blockListID)?.name ?? "Apps"
        var text = "\(list) · \(state.title(for: lock))"
        if let endsAt = lock.endsAt {
            text += " until \(endsAt.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }
}

/// Tap to lock the default Block List; press and hold to choose another list or a duration.
private struct LockButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.state
        Menu {
            ForEach(state.blockLists) { list in
                if state.settings.manualLocksCanHaveDuration {
                    Menu(list.name) {
                        Button("Until I touch grass") { model.lock(blockListID: list.id) }
                        ForEach(LockDuration.allCases) { duration in
                            Button(duration.label) { model.lock(blockListID: list.id, for: duration.interval) }
                        }
                    }
                } else {
                    Button(list.name) { model.lock(blockListID: list.id) }
                }
            }
        } label: {
            Label("Lock \(state.defaultBlockList?.name ?? "")", systemImage: "lock.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.grass, in: .capsule)
                .foregroundStyle(Theme.soil)
        } primaryAction: {
            model.lock()
        }
        Text("Press and hold to choose a Block List.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

enum LockDuration: CaseIterable, Identifiable {
    case thirtyMinutes, oneHour, twoHours, fourHours

    var id: Self { self }

    var interval: TimeInterval {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .thirtyMinutes: "For 30 minutes"
        case .oneHour: "For 1 hour"
        case .twoHours: "For 2 hours"
        case .fourHours: "For 4 hours"
        }
    }
}

/// Today's Budget usage and the next Schedule.
private struct TodayView: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let budgetCount = model.state.budgets.filter(\.isEnabled).count
        if budgetCount > 0 {
            BudgetUsageReportView(day: model.state.budgetDay(containing: now))
                .equatable()
                .frame(height: CGFloat(budgetCount) * 46)
        }
        if let next = model.state.nextScheduleStart(after: now) {
            Label {
                Text("\(next.schedule.name) locks \(model.state.blockList(id: next.schedule.blockListID)?.name ?? "apps") \(next.start.formatted(.relative(presentation: .named)))")
            } icon: {
                Image(systemName: "moon.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// Budget bars drawn by the usage report extension, the only process allowed to see usage minutes.
/// Kept in its own view so the per-second timeline doesn't rebuild the report.
private struct BudgetUsageReportView: View, Equatable {
    let day: DateInterval

    var body: some View {
        DeviceActivityReport(
            DeviceActivityReport.Context("budgets"),
            filter: DeviceActivityFilter(segment: .hourly(during: day), users: .all, devices: .init([.iPhone]))
        )
    }
}

private struct EmergencyUnlockDots: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let ledger = model.state.emergencyUnlocks
        let available = ledger.available(at: now)
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(0..<EmergencyUnlockLedger.maximum, id: \.self) { index in
                    Circle()
                        .fill(index < available ? Theme.grass : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }
            Text("Emergency Unlocks")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let refill = ledger.nextRefill(at: now) {
                Text("Next one back \(refill.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct GrassCountView: View {
    let count: Int

    var body: some View {
        Text(count == 1 ? "You've touched grass once." : "You've touched grass \(count) times.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
