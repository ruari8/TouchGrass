import Foundation

/// A named set of apps that a Lock blocks, such as "Social" or "Everything".
public struct BlockList: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// An encoded `FamilyActivitySelection`. Core treats it as opaque; TouchGrassScreenTime decodes it.
    public var selection: Data
    /// How many apps, categories and websites the selection holds, for display.
    public var itemCount: Int

    public init(id: UUID = UUID(), name: String, selection: Data = Data(), itemCount: Int = 0) {
        self.id = id
        self.name = name
        self.selection = selection
        self.itemCount = itemCount
    }
}
