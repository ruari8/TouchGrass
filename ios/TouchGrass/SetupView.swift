import FamilyControls
import SwiftUI
import TouchGrassCore
import TouchGrassScreenTime
import UserNotifications

/// First run: Screen Time permission, pick distracting apps, choose a style, then a practice Touch Grass.
struct SetupView: View {
    enum Step: Int, CaseIterable {
        case welcome, screenTime, apps, style, bedtime, practice
    }

    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var blockList = BlockList(name: "Distractions")
    @State private var style = Style.strict
    @State private var wantsBedtime = true
    @State private var bedtimeStart = TimeOfDay(hour: 22)
    @State private var bedtimeEnd = TimeOfDay(hour: 7)
    @State private var wantsBudget = false
    @State private var budgetMinutes = 60
    @State private var isPicking = false
    @State private var isPracticing = false

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(Theme.grass)
            Spacer()
            content
            Spacer()
        }
        .padding(24)
        .animation(.default, value: step)
        .familyActivityPicker(isPresented: $isPicking, selection: $blockList.activitySelection)
        .sheet(isPresented: $isPracticing) {
            TouchGrassFlow(mode: .practice) { finish() }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            StepHeader(symbol: "leaf.fill", title: "Touch Grass", detail: "Brick without the brick. Lock your distracting apps, and the only way out is to go outside and take a photo of real grass.")
            Button("Get started") { step = .screenTime }
                .buttonStyle(.primary)

        case .screenTime:
            StepHeader(symbol: "hourglass", title: "Screen Time access", detail: "Touch Grass uses Screen Time to lock apps. Nothing leaves your phone.")
            if model.isScreenTimeApproved {
                Button("Continue") { step = .apps }
                    .buttonStyle(.primary)
            } else {
                Button("Allow Screen Time") {
                    Task {
                        await model.requestScreenTime()
                        if model.isScreenTimeApproved { step = .apps }
                    }
                }
                .buttonStyle(.primary)
            }

        case .apps:
            StepHeader(symbol: "apps.iphone", title: "Pick your distractions", detail: "These become your first Block List. You can add more lists later.")
            Button(blockList.itemCount == 0 ? "Choose apps" : "\(blockList.itemCount) chosen. Change") { isPicking = true }
                .buttonStyle(.bordered)
            Button("Continue") { step = .style }
                .buttonStyle(.primary)
                .disabled(blockList.itemCount == 0)

        case .style:
            StepHeader(symbol: "dial.medium", title: "How strict?", detail: "You can change any single setting later.")
            ForEach(Style.allCases, id: \.self) { option in
                StyleCard(style: option, isSelected: style == option) { style = option }
            }
            Button("Continue") { step = .bedtime }
                .buttonStyle(.primary)

        case .bedtime:
            StepHeader(symbol: "moon.fill", title: "Any limits?", detail: "Both are optional, and you can add more Schedules and Budgets later.")
            Toggle("Lock \(blockList.name) at bedtime", isOn: $wantsBedtime)
            if wantsBedtime {
                DatePicker("From", selection: $bedtimeStart.date, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $bedtimeEnd.date, displayedComponents: .hourAndMinute)
            }
            Toggle("Daily Budget for \(blockList.name)", isOn: $wantsBudget)
            if wantsBudget {
                Picker("Minutes a day", selection: $budgetMinutes) {
                    ForEach(Budget.minuteOptions, id: \.self) { minutes in
                        Text(Budget.format(minutes)).tag(minutes)
                    }
                }
            }
            Button("Continue") { step = .practice }
                .buttonStyle(.primary)
                .disabled(wantsBedtime && (bedtimeStart == bedtimeEnd || bedtime.durationMinutes < 15))

        case .practice:
            StepHeader(symbol: "camera.fill", title: "Try it once", detail: "Take a practice photo of grass. Touch Grass also needs to send you a notification when you tap a locked app.")
            Button("Practice Touch Grass") {
                Task {
                    await requestPermissions()
                    isPracticing = true
                }
            }
            .buttonStyle(.primary)
            Button("Skip practice") {
                Task {
                    await requestPermissions()
                    finish()
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private var bedtime: Schedule {
        Schedule(name: "Bedtime", blockListID: blockList.id, start: bedtimeStart, end: bedtimeEnd)
    }

    private func finish() {
        model.completeSetup(
            blockList: blockList,
            style: style,
            bedtime: wantsBedtime ? bedtime : nil,
            budget: wantsBudget ? Budget(name: blockList.name, blockListID: blockList.id, minutes: budgetMinutes) : nil
        )
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Theme.grass)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StyleCard: View {
    let style: Style
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(style.title + (style == .strict ? " (recommended)" : ""))
                    .font(.headline)
                Text(style.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Theme.grass : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
