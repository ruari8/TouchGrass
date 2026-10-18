#if os(iOS)
import FamilyControls
import Foundation
import ManagedSettings
import TouchGrassCore

extension BlockList {
    /// The apps, categories and websites this Block List covers.
    public var activitySelection: FamilyActivitySelection {
        get {
            (try? JSONDecoder().decode(FamilyActivitySelection.self, from: selection))
                ?? FamilyActivitySelection(includeEntireCategory: true)
        }
        set {
            selection = (try? JSONEncoder().encode(newValue)) ?? Data()
            itemCount = newValue.applicationTokens.count + newValue.categoryTokens.count + newValue.webDomainTokens.count
        }
    }

    public func contains(_ application: ApplicationToken) -> Bool {
        activitySelection.applicationTokens.contains(application)
    }

    public func contains(_ webDomain: WebDomainToken) -> Bool {
        activitySelection.webDomainTokens.contains(webDomain)
    }

    public func contains(_ category: ActivityCategoryToken) -> Bool {
        activitySelection.categoryTokens.contains(category)
    }
}
#endif
