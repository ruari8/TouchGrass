import SwiftUI
import TouchGrassCore

struct RulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.state
        let frozen = model.settingsFrozen()
        NavigationStack {
            List {
                if frozen {
                    Section {
                        Label("Rules are frozen while you're Locked.", systemImage: "lock.fill")
                            .foregroundStyle(Theme.locked)
                    }
                }

                Section("Block Lists") {
                    ForEach(state.blockLists) { list in
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

                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        LabeledContent("Style", value: state.settings.style.map(\.title) ?? "Custom")
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
        let settings = model.state.settings
        Form {
            Section {
                Picker("Default Block List", selection: Binding(
                    get: { model.state.defaultBlockList?.id },
                    set: { id in model.updateSettings { $0.defaultBlockListID = id } }
                )) {
                    ForEach(model.state.blockLists) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
            } footer: {
                Text("A Manual Lock locks this list unless you press and hold to choose another.")
            }

            Section {
                ForEach(Style.allCases, id: \.self) { style in
                    Button {
                        model.updateSettings { $0.apply(style) }
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
            }
        }
        .disabled(model.settingsFrozen())
        .navigationTitle("Settings")
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
            "Manual Locks last until you touch grass. Touching grass earns a 15-minute Break from Schedules and Budgets."
        case .flexible:
            "Manual Locks can have a duration. Touching grass ends Schedules and Budgets for the day."
        }
    }
}
