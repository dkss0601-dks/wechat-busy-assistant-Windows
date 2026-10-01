import Foundation

struct ActivityDescriptionsState {
    let currentID: String
    let descriptions: [String: String]
}

/// Every preset, including custom, owns an independent saved description.
struct ActivityDescriptionsStore {
    let defaults: UserDefaults
    private let key = "v6.activityDescriptions"
    static var initialDescriptions: [String: String] {
        Dictionary(uniqueKeysWithValues: ActivityPreset.all.map { ($0.id, $0.description) })
    }
    func load() -> ActivityDescriptionsState {
        let legacyID = defaults.string(forKey: "v2.activityID") ?? "piano"
        let currentID = ActivityPreset.all.contains(where: { $0.id == legacyID }) ? legacyID : "piano"
        var descriptions = Self.initialDescriptions
        let saved = defaults.dictionary(forKey: key) ?? [:]
        for preset in ActivityPreset.all {
            if let text = saved[preset.id] as? String { descriptions[preset.id] = text }
        }
        // Preserve the previous app version's last edited activity on upgrade.
        if saved[currentID] as? String == nil, let old = defaults.string(forKey: "v2.activity") {
            descriptions[currentID] = old
        }
        return ActivityDescriptionsState(currentID: currentID, descriptions: descriptions)
    }
    func save(descriptions: [String: String], currentID: String) {
        guard ActivityPreset.all.contains(where: { $0.id == currentID }) else { return }
        let known = descriptions.filter { Self.initialDescriptions[$0.key] != nil }
        defaults.set(known, forKey: key)
        defaults.set(currentID, forKey: "v2.activityID")
        defaults.set(known[currentID] ?? "", forKey: "v2.activity")
    }
}
