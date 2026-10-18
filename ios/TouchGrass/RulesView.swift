import SwiftUI
import TouchGrassCore

struct RulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.state
        let rules = state.upcomingRules
        let frozen = model.settingsFrozen()
        NavigationStack {
            List {
                if frozen {
                    Section {
                        Label("Rules are frozen while you're Locked.", systemImage: "lock.fill")
                            .foregroundStyle(Theme.locked)
                    }
                }

                if let pending = state.pendingRules {
                    Section {
                        Label("Some changes loosen your rules, so they take effect at \(pending.appliesAt.formatted(date: .omitted, time: .shortened)). What you see here includes them.", systemImage: "clock")
                        Button("Cancel waiting changes", role: .destructive) {
                            model.cancelPendingRules()
                        }
                        .disabled(frozen)
                    }
                }

                Section("Block Lists") {
                    ForEach(rules.blockLists) { list in
                        NavigationLink {
                            BlockListEditor(blockList: list)
                        } label: {
                            LabeledContent(list.name, value: "\(list.itemCount)")
                        }
                    }
                    NavigationLink("New Block List") {
                        BlockListEditor(blockList: nil)
                    }
                    .disabled(frozen)
                }

                Section {
                    ForEach(rules.schedules) { schedule in
                        NavigationLink {
                            ScheduleEditor(schedule: schedule, defaultBlockListID: schedule.blockListID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(schedule.name)
                                    .foregroundStyle(schedule.isEnabled ? .primary : .secondary)
                                Text(schedule.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let defaultList = rules.blockLists.first {
                        NavigationLink("New Schedule") {
                            ScheduleEditor(schedule: nil, defaultBlockListID: rules.settings.defaultBlockListID ?? defaultList.id)
                        }
                        .disabled(frozen || rules.automaticRuleCount >= AppState.maximumAutomaticRules)
                    }
                } header: {
                    Text("Schedules")
                } footer: {
                    Text("A Schedule locks its Block List during its window on the days you choose.")
                }

                Section {
                    ForEach(rules.budgets) { budget in
                        NavigationLink {
                            BudgetEditor(budget: budget, defaultBlockListID: budget.blockListID)
                        } label: {
                            LabeledContent {
                                Text(Budget.format(budget.minutes))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(budget.name)
                                        .foregroundStyle(budget.isEnabled ? .primary : .secondary)
                                    Text(rules.blockLists.first { $0.id == budget.blockListID }?.name ?? "")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let defaultList = rules.blockLists.first {
                        NavigationLink("New Budget") {
                            BudgetEditor(budget: nil, defaultBlockListID: rules.settings.defaultBlockListID ?? defaultList.id)
                        }
                        .disabled(frozen || rules.automaticRuleCount >= AppState.maximumAutomaticRules)
                    }
                } header: {
                    Text("Budgets")
                } footer: {
                    Text("A Budget locks its Block List once you've used it for so many minutes a day.")
                }

                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        LabeledContent("Style", value: rules.settings.style.map(\.title) ?? "Custom")
                    }
                    if GrassCheckSettings.isDeveloperBuild {
                        NavigationLink("Developer Settings") {
                            DeveloperSettingsView()
                        }
                    }
                }
            }
            .navigationTitle("Rules")
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rules = model.state.upcomingRules
        let settings = rules.settings
        Form {
            Section {
                ForEach(Style.allCases, id: \.self) { style in
                    Button {
                        model.changeRules { $0.settings.apply(style) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.title).foregroundStyle(.primary)
                                Text(style.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.style == style {
                                Image(systemName: "checkmark").foregroundStyle(Theme.grass)
                            }
                        }
                    }
                }
            } header: {
                Text("Style")
            } footer: {
                Text("Choosing a style sets the options below. You can then change any of them on their own.")
            }

            Section("Options") {
                Toggle("Manual Locks can have a duration", isOn: binding(\.manualLocksCanHaveDuration))
                Toggle("Touching grass gives a Break", isOn: binding(\.touchGrassGivesBreak))
                if settings.touchGrassGivesBreak {
                    Picker("Break length", selection: binding(\.breakMinutes)) {
                        ForEach(Settings.breakMinuteOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                }
                Toggle("Loosening waits until tomorrow", isOn: binding(\.looseningWaitsUntilTomorrow))
            }

            Section {
                Picker("Reset Time", selection: Binding(
                    get: { settings.resetTime.hour },
                    set: { hour in model.changeRules { $0.settings.resetTime = TimeOfDay(hour: hour) } }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(TimeOfDay(hour: hour).formatted).tag(hour)
                    }
                }
            } footer: {
                Text("When Budgets refill and waiting changes apply. Night owls might pick 4:00.")
            }

            Section {
                Picker("Default Block List", selection: Binding(
                    get: { settings.defaultBlockListID ?? rules.blockLists.first?.id },
                    set: { id in model.changeRules { $0.settings.defaultBlockListID = id } }
                )) {
                    ForEach(rules.blockLists) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
            } footer: {
                Text("A Manual Lock locks this list unless you press and hold to choose another.")
            }
        }
        .disabled(model.settingsFrozen())
        .navigationTitle("Settings")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.state.upcomingRules.settings[keyPath: keyPath] },
            set: { value in model.changeRules { $0.settings[keyPath: keyPath] = value } }
        )
    }
}

extension Style {
    var title: String {
        switch self {
        case .strict: "Strict"
        case .flexible: "Flexible"
        }
    }

    var summary: String {
        switch self {
        case .strict:
            "Manual Locks last until you touch grass. Touching grass earns a Break from Schedules and Budgets. Loosening a rule waits until tomorrow."
        case .flexible:
            "Manual Locks can have a duration. Touching grass ends Schedules and Budgets for the day. Changes apply straight away."
        }
    }
}
