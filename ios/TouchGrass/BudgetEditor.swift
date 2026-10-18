import SwiftUI
import TouchGrassCore

struct BudgetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Budget
    private let isNew: Bool

    init(budget: Budget?, defaultBlockListID: UUID) {
        _draft = State(initialValue: budget ?? Budget(name: "", blockListID: defaultBlockListID, minutes: 60))
        isNew = budget == nil
    }

    var body: some View {
        let frozen = model.settingsFrozen()
        Form {
            Section("Name") {
                TextField("Social", text: $draft.name)
            }
            Section {
                Picker("Block List", selection: $draft.blockListID) {
                    ForEach(model.state.upcomingRules.blockLists) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                Picker("Minutes a day", selection: $draft.minutes) {
                    ForEach(Budget.minuteOptions, id: \.self) { minutes in
                        Text(Budget.format(minutes)).tag(minutes)
                    }
                }
                Toggle("On", isOn: $draft.isEnabled)
            } footer: {
                Text("Once the apps on this list have been used for this long, they lock until \(model.state.upcomingRules.settings.resetTime.formatted).")
            }
            if !isNew {
                Section {
                    Button("Delete Budget", role: .destructive) {
                        let id = draft.id
                        model.changeRules { $0.budgets.removeAll { $0.id == id } }
                        dismiss()
                    }
                }
            }
        }
        .disabled(frozen)
        .navigationTitle(isNew ? "New Budget" : draft.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let budget = draft
                    model.changeRules { rules in
                        if let index = rules.budgets.firstIndex(where: { $0.id == budget.id }) {
                            rules.budgets[index] = budget
                        } else {
                            rules.budgets.append(budget)
                        }
                    }
                    dismiss()
                }
                .disabled(frozen || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

extension Budget {
    static func format(_ minutes: Int) -> String {
        switch (minutes / 60, minutes % 60) {
        case (0, let m): "\(m) min"
        case (let h, 0): h == 1 ? "1 hour" : "\(h) hours"
        case (let h, let m): "\(h) h \(m) min"
        }
    }
}
