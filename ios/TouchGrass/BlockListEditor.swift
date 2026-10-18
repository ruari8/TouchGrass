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
            if !isNew, model.state.blockLists.count > 1 {
                Section {
                    Button("Delete Block List", role: .destructive) {
                        model.deleteBlockList(id: draft.id)
                        dismiss()
                    }
                }
            }
        }
        .disabled(frozen)
        .navigationTitle(isNew ? "New Block List" : draft.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.save(draft)
                    dismiss()
                }
                .disabled(frozen || draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.itemCount == 0)
            }
        }
        .familyActivityPicker(isPresented: $isPicking, selection: $draft.activitySelection)
    }
}
