import Cocoa

@MainActor func activityDescriptionTests() {
    // Dedicated suites avoid the application's real preferences and contain
    // only synthetic state. Their persisted test domains are removed afterward.
    let storeSuite = "wechat-activity-store-tests-" + UUID().uuidString
    let storeDefaults = UserDefaults(suiteName: storeSuite)!
    defer { storeDefaults.removePersistentDomain(forName: storeSuite) }
    let store = ActivityDescriptionsStore(defaults: storeDefaults)
    let initial = store.load()
    precondition(initial.currentID == "piano" && initial.descriptions.count == ActivityPreset.all.count)
    for preset in ActivityPreset.all { precondition(initial.descriptions[preset.id] == preset.description) }

    storeDefaults.set("work", forKey: "v2.activityID")
    storeDefaults.set("旧版本编辑过的工作说明", forKey: "v2.activity")
    let migrated = store.load()
    precondition(migrated.currentID == "work" && migrated.descriptions["work"] == "旧版本编辑过的工作说明")
    precondition(migrated.descriptions["piano"] == initial.descriptions["piano"] && migrated.descriptions["custom"] == "")
    storeDefaults.set(["piano": "已保存的练琴说明", "work": 99, "custom": ""], forKey: "v6.activityDescriptions")
    let partial = store.load()
    precondition(partial.descriptions["piano"] == "已保存的练琴说明")
    precondition(partial.descriptions["work"] == "旧版本编辑过的工作说明" && partial.descriptions["custom"] == "")
    var edited = partial.descriptions
    edited["work"] = "新版工作说明"; edited["custom"] = "录音中，结束后回复。"; edited["unknown"] = "not a preset"
    store.save(descriptions: edited, currentID: "custom")
    let saved = store.load()
    precondition(saved.currentID == "custom" && saved.descriptions["custom"] == "录音中，结束后回复。")
    precondition(saved.descriptions["piano"] == "已保存的练琴说明" && saved.descriptions["work"] == "新版工作说明" && saved.descriptions["unknown"] == nil)
    precondition(saved.descriptions.count == ActivityPreset.all.count)
    store.save(descriptions: ["piano": "must not replace"], currentID: "unknown")
    precondition(store.load().currentID == "custom" && store.load().descriptions == saved.descriptions)

    let modelSuite = "wechat-activity-model-tests-" + UUID().uuidString
    let modelDefaults = UserDefaults(suiteName: modelSuite)!
    defer { modelDefaults.removePersistentDomain(forName: modelSuite) }
    modelDefaults.set("DO NOT LOAD", forKey: "v3.contact")
    modelDefaults.set("DO NOT LOAD", forKey: "v2.tone")
    modelDefaults.set(true, forKey: "v3.autoSend")
    modelDefaults.set(100, forKey: "v3.limit")
    let modelStore = ActivityDescriptionsStore(defaults: modelDefaults)
    let model = Assistant(reader: MemoryChats(), isolatedTest: true, activityDefaults: modelDefaults)
    precondition(model.key.isEmpty && model.contact.isEmpty && model.tone == "自然简短" && !model.autoSend && model.limit == 5)
    let piano = ActivityPreset.all.first { $0.id == "piano" }!
    let work = ActivityPreset.all.first { $0.id == "work" }!
    let custom = ActivityPreset.all.first { $0.id == "custom" }!
    model.activity = "练慢速音阶，请先帮我记下事情。"
    precondition(modelStore.load().descriptions["piano"] == model.activity) // saved without starting a session
    model.chooseActivity(work)
    precondition(model.activity == work.description)
    model.activity = "正在赶设计稿，重要事情请标明。"
    precondition(modelStore.load().descriptions["work"] == model.activity)
    model.chooseActivity(custom)
    precondition(model.activity.isEmpty) // custom must not inherit the work description
    model.activity = "正在录音，先帮我接住消息。"; model.saveActivity()
    precondition(modelStore.load().currentID == "custom" && modelStore.load().descriptions["custom"] == model.activity)
    model.chooseActivity(piano)
    precondition(model.activity == "练慢速音阶，请先帮我记下事情。")
    model.chooseActivity(work)
    precondition(model.activity == "正在赶设计稿，重要事情请标明。")
    model.chooseActivity(custom)
    precondition(model.activity == "正在录音，先帮我接住消息。")
    let reopened = Assistant(reader: MemoryChats(), isolatedTest: true, activityDefaults: modelDefaults)
    precondition(reopened.activityID == "custom" && reopened.activity == "正在录音，先帮我接住消息。")
    reopened.chooseActivity(piano)
    precondition(reopened.activity == "练慢速音阶，请先帮我记下事情。")
    reopened.chooseActivity(work)
    precondition(reopened.activity == "正在赶设计稿，重要事情请标明。")
    reopened.chooseActivity(custom)
    reopened.activity = ""
    reopened.chooseActivity(piano); reopened.chooseActivity(custom)
    precondition(reopened.activity.isEmpty) // an explicitly empty custom description remains empty
    let emptyReopened = Assistant(reader: MemoryChats(), isolatedTest: true, activityDefaults: modelDefaults)
    precondition(emptyReopened.activityID == "custom" && emptyReopened.activity.isEmpty)
    let savedBeforeGuard = modelStore.load()
    emptyReopened.busy = true; emptyReopened.chooseActivity(work); emptyReopened.saveActivity()
    precondition(emptyReopened.activityID == "custom" && modelStore.load().descriptions == savedBeforeGuard.descriptions)
    emptyReopened.busy = false; emptyReopened.running = true; emptyReopened.chooseActivity(piano)
    precondition(emptyReopened.activityID == "custom")
    emptyReopened.running = false
    print("PASS: independent preset descriptions, legacy migration, immediate edits, custom empty state, restart persistence and isolated activity preferences")
}
