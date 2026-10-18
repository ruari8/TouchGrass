import Foundation
import TouchGrassCore

/// Mirrors Emergency Unlock uses to iCloud so deleting and reinstalling the app doesn't refill them.
///
/// Each use is its own key, so two devices spending one while offline both survive the merge
/// instead of one overwriting the other's list.
struct EmergencyUnlockSync {
    private let store = NSUbiquitousKeyValueStore.default
    private let prefix = "emergencyUnlock."

    func load() -> EmergencyUnlockLedger {
        store.synchronize()
        let uses = store.dictionaryRepresentation
            .filter { $0.key.hasPrefix(prefix) }
            .compactMap { $0.value as? Double }
            .map(Date.init(timeIntervalSince1970:))
        return EmergencyUnlockLedger(usedAt: uses)
    }

    /// Records every outstanding use and forgets ones that have already come back.
    func save(_ ledger: EmergencyUnlockLedger, at now: Date) {
        let refilled = now.addingTimeInterval(-EmergencyUnlockLedger.refillInterval)
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix(prefix) {
            if let timestamp = value as? Double, Date(timeIntervalSince1970: timestamp) <= refilled {
                store.removeObject(forKey: key)
            }
        }
        for use in ledger.usedAt where use > refilled {
            store.set(use.timeIntervalSince1970, forKey: prefix + String(use.timeIntervalSince1970))
        }
        store.synchronize()
    }
}
