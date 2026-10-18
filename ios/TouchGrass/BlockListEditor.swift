import FamilyControls
import SwiftUI
import TouchGrassCore
import TouchGrassScreenTime

struct BlockListEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BlockList
    @State private var isPicking = false
    private let isNew: Bool

    init(blockList: BlockList?) {
        _draft = State(initialValue: blockList ?? BlockList(name: ""))
        isNew = blockList == nil
    }

    var body: some View {
        let frozen = model.settingsFrozen()
        Form {
            Section("Name") {
                TextField("Social", text: $draft.name)
            }
            Section {
                Button(draft.itemCount == 0 ? "Choose apps" : "\(draft.itemCount) apps, categories and sites") {
                    isPicking = true
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("Pick whole categories to block every app in them, including ones you install later.")
            }
            if !isNew, model.state.upcomingRules.blockLists.count > 1 {
                Section {
                    Button("Delete Block List", role: .destructive) {
                        let id = draft.id
                        model.changeRules { $0.blockLists.removeAll { $0.id == id } }
                        dismiss()
                    }
                } footer: {
                    Text("Schedules that use this list are deleted too.")
                }
            }
        }
        .disabled(frozen)
        .navigationTitle(isNew ? "New Block List" : draft.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let list = draft
                    model.changeRules { rules in
                        if let index = rules.blockLists.firstIndex(where: { $0.id == list.id }) {
                            rules.blockLists[index] = list
                        } else {
                            rules.blockLists.append(list)
                        }
                    }
                    dismiss()
                }
                .disabled(frozen || draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.itemCount == 0)
            }
        }
        .familyActivityPicker(isPresented: $isPicking, selection: $draft.activitySelection)
    }
}
