import Foundation
import TouchGrassCore

/// Mirrors Emergency Unlock uses to iCloud so deleting and reinstalling the app doesn't refill them.
struct EmergencyUnlockSync {
    private let store = NSUbiquitousKeyValueStore.default
    private let key = "emergencyUnlocksUsedAt"

    func load() -> EmergencyUnlockLedger {
        store.synchronize()
        let timestamps = store.array(forKey: key) as? [Double] ?? []
        return EmergencyUnlockLedger(usedAt: timestamps.map(Date.init(timeIntervalSince1970:)))
    }

    func save(_ ledger: EmergencyUnlockLedger) {
        store.set(ledger.usedAt.map(\.timeIntervalSince1970), forKey: key)
        store.synchronize()
    }
}
