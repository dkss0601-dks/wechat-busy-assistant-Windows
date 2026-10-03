import Cocoa
import ApplicationServices

// In-memory transport: these tests never read WeChat, Keychain, user defaults,
// real message logs or the network.
@MainActor final class MemoryChats: ChatAccess {
    var current = "A"
    var frontmost = false
    var rows = ["A": ["ASaid:old"], "B": ["BSaid:old"]]
    var drafts: [String: String] = [:]
    var sent: [(String, String)] = []
    var uncertain = false
    var unread: [String: Int] = [:]
    var firstScreenNames = ["A", "B"]
    var scanCount = 0
    var openedNames: [String] = []
    var messageDates: [String: Date] = [:]
    var previewOverrides: [String: String] = [:]
    func snapshot() throws -> Snapshot {
        Snapshot(name: current, rows: rows[current]!, input: AXUIElementCreateApplication(0), draft: drafts[current] ?? "", pid: 0, isDirect: true)
    }
    func isWeChatFrontmost() -> Bool { frontmost }
    func requireBackground(_ valid: () -> Bool) throws {
        guard valid() else { throw CancellationError() }
        if frontmost { throw RetryLater(message: "user owns WeChat") }
    }
    func scanChats(valid: () -> Bool) async throws -> [ChatCandidate] {
        try requireBackground(valid)
        scanCount += 1
        return firstScreenNames.map { name in
            ChatCandidate(name: name, signature: name + ":" + (previewOverrides[name] ?? rows[name]?.last ?? ""), unread: unread[name] ?? 0,
                lastMessageAt: messageDates[name] ?? Date(),
                preview: previewOverrides[name] ?? rows[name]?.last.flatMap { parseMessage($0, contact: name)?.text })
        }
    }
    func openChat(name: String, valid: () -> Bool) async throws -> Snapshot {
        try requireBackground(valid)
        guard name == current || firstScreenNames.contains(name) else { throw RetryLater(message: "contact is outside the first screen") }
        openedNames.append(name); current = name; return try snapshot()
    }
    func send(_ text: String, expected: Snapshot, stillActive: () -> Bool) async throws -> SendReceipt {
        try requireBackground(stillActive)
        let now = try snapshot()
        precondition(now.name == expected.name && now.rows == expected.rows && now.draft.isEmpty)
        if uncertain { throw SendUncertain(message: "unconfirmed receipt") }
        sent.append((current, text)); rows[current]!.append("MeSaid:" + text)
        return SendReceipt(rows: rows[current]!, arrivedBeforeReply: [])
    }
}

@MainActor func lifecycleTests() async {
    let chats = MemoryChats()
    var requests = 0
    let model = Assistant(reader: chats, isolatedTest: true, replyGenerator: { incoming, history in
        requests += 1
        precondition(incoming == "new" && history.isEmpty)
        // Simulate the user switching chats while the API is generating.
        chats.current = "B"; chats.frontmost = true
        return "queued reply"
    })
    model.key = "test-only"; model.contact = "A"; model.autoSend = true; model.limit = 10
    model.start(); await model.pollOnceForTesting()
    chats.rows["A"]!.append("ASaid:new")
    await model.pollOnceForTesting()
    precondition(model.running && model.draft == "queued reply" && requests == 1 && chats.sent.isEmpty)
    await model.pollOnceForTesting()
    precondition(model.running && chats.current == "B" && chats.sent.isEmpty)
    // A user's unfinished draft blocks automation without being changed.
    chats.frontmost = false; chats.drafts["B"] = "user text"
    await model.pollOnceForTesting()
    precondition(model.running && chats.drafts["B"] == "user text" && chats.sent.isEmpty)
    chats.drafts["B"] = ""
    await model.pollOnceForTesting()
    precondition(model.running && chats.sent.count == 1 && chats.sent[0].0 == "A" && model.rounds == 1)
    await model.pollOnceForTesting()
    precondition(chats.sent.count == 1 && requests == 1) // no duplicate or false manual handoff
    chats.rows["A"]!.append("MeSaid:human reply")
    chats.rows["A"]!.append("ASaid:after human reply")
    await model.pollOnceForTesting()
    precondition(model.running && model.log.contains { $0.kind == "本人接管" } && requests == 1)
    model.stop(); precondition(!model.running)

    let failedChats = MemoryChats(); failedChats.uncertain = true
    let failed = Assistant(reader: failedChats, isolatedTest: true, replyGenerator: { _, _ in "reply" })
    failed.key = "test-only"; failed.contact = "A"; failed.autoSend = true
    failed.start(); await failed.pollOnceForTesting()
    failedChats.rows["A"]!.append("ASaid:new")
    await failed.pollOnceForTesting(); await failed.pollOnceForTesting()
    precondition(failed.running && failed.draft.isEmpty && failed.log.contains { $0.kind == "暂停好友" })
    await failed.pollOnceForTesting()
    precondition(failedChats.sent.isEmpty && failed.running)
    failed.stop()
    print("PASS: chat switch during generation, foreground yielding, draft preservation, recipient reacquisition, no duplicate send, manual handoff and uncertain-send isolation")
    await replyLimitLifecycleTests()
}


// Each delivery follows the real generation/pending/send lifecycle. Unread
// counters allow all-friends mode to discover a contact absent from its states.
@MainActor private func deliverLimitTestMessage(_ text: String, to name: String,
                                              model: Assistant, chats: MemoryChats) async {
    chats.current = name
    chats.rows[name]!.append(name + "Said:" + text)
    chats.unread[name] = (chats.unread[name] ?? 0) + 1
    await model.pollOnceForTesting()
    await model.pollOnceForTesting()
    chats.unread[name] = 0
}

@MainActor private func replyLimitLifecycleTests() async {
    for scope in ReplyScope.allCases {
        let chats = MemoryChats()
        var requests = 0
        let model = Assistant(reader: chats, isolatedTest: true, replyGenerator: { incoming, history in
            precondition(history.count <= 8 && history.count.isMultiple(of: 2))
            if incoming == "new 1" || incoming == "B new 1" { precondition(history.isEmpty) }
            if incoming == "new 12" || incoming == "B new 12" { precondition(history.count == 8) }
            requests += 1
            return "reply \(requests)"
        })
        precondition(!model.unlimitedReplies) // existing finite behavior is the default
        model.key = "test-only"; model.contact = "A"; model.scope = scope
        model.autoSend = true; model.limit = 1; model.unlimitedReplies = true
        model.start(); await model.pollOnceForTesting()
        precondition(model.running)
        // Changing the visible options cannot impose a new cap on this session.
        model.unlimitedReplies = false; model.limit = 1
        for number in 1...12 {
            await deliverLimitTestMessage("new \(number)", to: "A", model: model, chats: chats)
            precondition(model.running && model.rounds == number && chats.sent.count == number && requests == number)
            precondition(chats.sent.last!.0 == "A")
        }
        await model.pollOnceForTesting()
        precondition(requests == 12 && chats.sent.count == 12 && model.running)
        if scope == .all {
            for number in 1...12 {
                await deliverLimitTestMessage("B new \(number)", to: "B", model: model, chats: chats)
                precondition(model.running && chats.sent.count == 12 + number && requests == 12 + number)
                precondition(chats.sent.last!.0 == "B")
            }
            precondition(model.friendCount == 2 && model.rounds == 24)
        }
        model.stop(); precondition(!model.running)
    }

    // A finite selected-friend session ends at its original cap even if visible
    // settings are subsequently changed to a larger or unlimited cap.
    let selectedChats = MemoryChats()
    var selectedRequests = 0
    let selected = Assistant(reader: selectedChats, isolatedTest: true, replyGenerator: { _, _ in
        selectedRequests += 1; return "finite reply"
    })
    selected.key = "test-only"; selected.contact = "A"; selected.autoSend = true; selected.limit = 2
    selected.start(); await selected.pollOnceForTesting()
    selected.limit = 100; selected.unlimitedReplies = true
    await deliverLimitTestMessage("one", to: "A", model: selected, chats: selectedChats)
    precondition(selected.running && selectedChats.sent.count == 1)
    await deliverLimitTestMessage("two", to: "A", model: selected, chats: selectedChats)
    precondition(!selected.running && selected.rounds == 2 && selectedRequests == 2 && selectedChats.sent.count == 2)
    await deliverLimitTestMessage("after cap", to: "A", model: selected, chats: selectedChats)
    precondition(selectedRequests == 2 && selectedChats.sent.count == 2)

    // In all-friends mode the same cap pauses only the exhausted friend. A new
    // private conversation is still discovered and can use its own full quota.
    let allChats = MemoryChats()
    var allRequests = 0
    let all = Assistant(reader: allChats, isolatedTest: true, replyGenerator: { _, _ in
        allRequests += 1; return "all reply"
    })
    all.key = "test-only"; all.scope = .all; all.autoSend = true; all.limit = 2
    all.start(); await all.pollOnceForTesting()
    all.limit = 100; all.unlimitedReplies = true
    await deliverLimitTestMessage("A one", to: "A", model: all, chats: allChats)
    await deliverLimitTestMessage("A two", to: "A", model: all, chats: allChats)
    precondition(all.running && all.rounds == 2 && allRequests == 2)
    await deliverLimitTestMessage("A after cap", to: "A", model: all, chats: allChats)
    precondition(all.running && allRequests == 2 && allChats.sent.count == 2)
    await deliverLimitTestMessage("B one", to: "B", model: all, chats: allChats)
    await deliverLimitTestMessage("B two", to: "B", model: all, chats: allChats)
    precondition(all.running && all.rounds == 4 && all.friendCount == 2 && allRequests == 4)
    precondition(allChats.sent.map { $0.0 } == ["A", "A", "B", "B"])
    await deliverLimitTestMessage("B after cap", to: "B", model: all, chats: allChats)
    precondition(all.running && allRequests == 4 && allChats.sent.count == 4)
    all.stop()

    for scope in ReplyScope.allCases {
        let chats = MemoryChats()
        var requests = 0
        let model = Assistant(reader: chats, isolatedTest: true, replyGenerator: { _, _ in
            requests += 1; return "reply"
        })
        model.key = "test-only"; model.contact = "A"; model.scope = scope
        model.autoSend = true; model.limit = 1; model.unlimitedReplies = true
        model.start(); await model.pollOnceForTesting()
        await deliverLimitTestMessage("hello", to: "A", model: model, chats: chats)
        await deliverLimitTestMessage("请停止自动回复", to: "A", model: model, chats: chats)
        precondition(model.running && requests == 1 && chats.sent.count == 1 && model.draft.isEmpty)
        precondition(model.log.contains { $0.kind == "暂停好友" && $0.contact == "A" })
        await deliverLimitTestMessage("later message", to: "A", model: model, chats: chats)
        precondition(model.running && requests == 1 && chats.sent.count == 1)
        if scope == .all {
            await deliverLimitTestMessage("B remains available", to: "B", model: model, chats: chats)
            precondition(model.running && requests == 2 && chats.sent.last!.0 == "B")
        }
        model.stop()
    }
    print("PASS: selected/all unlimited replies exceed old cap, frozen finite/unlimited settings, per-friend finite isolation, bounded separate histories and stop-word handling")
}


@MainActor func firstScreenLifecycleTests() async {
    let chats = MemoryChats()
    chats.rows["B"] = ["BSaid:old unread 1", "BSaid:old unread 2", "BSaid:old unread 3"]
    chats.unread["B"] = 3
    chats.rows["D"] = ["DSaid:hidden old 1", "DSaid:hidden old 2", "DSaid:hidden newest"]
    chats.unread["D"] = 3
    chats.messageDates["D"] = Date().addingTimeInterval(-86400)
    var requests: [String] = []
    let model = Assistant(reader: chats, isolatedTest: true, replyGenerator: { incoming, _ in
        requests.append(incoming); return "first-screen reply"
    })
    model.key = "test-only"; model.scope = .all; model.autoSend = true; model.unlimitedReplies = true
    model.start(); await model.pollOnceForTesting()
    precondition(model.running && requests.isEmpty && chats.sent.isEmpty && chats.scanCount == 1)
    for _ in 0..<3 {
        let count = chats.scanCount
        await model.pollOnceForTesting()
        precondition(chats.scanCount == count + 1 && requests.isEmpty && chats.sent.isEmpty)
    }
    precondition(!chats.openedNames.contains("B") && !chats.openedNames.contains("D"))

    // Foreground ownership and unfinished text prevent any further scanning.
    chats.frontmost = true
    let foregroundCount = chats.scanCount
    await model.pollOnceForTesting()
    precondition(model.running && chats.scanCount == foregroundCount && chats.sent.isEmpty)
    chats.frontmost = false; chats.drafts["A"] = "user's unfinished message"
    let draftCount = chats.scanCount
    await model.pollOnceForTesting()
    precondition(model.running && chats.scanCount == draftCount && chats.drafts["A"] == "user's unfinished message" && chats.sent.isEmpty)
    chats.drafts["A"] = ""

    // A new candidate may have accumulated unread history outside the first
    // screen. First discovery uses only its newest message, without a rescan.
    chats.rows["C"] = ["CSaid:older unread 1", "CSaid:older unread 2", "CSaid:C newest"]
    chats.unread["C"] = 3; chats.firstScreenNames.append("C")
    let discoveryCount = chats.scanCount
    await model.pollOnceForTesting()
    precondition(chats.scanCount == discoveryCount + 1 && requests == ["C newest"] && model.draft == "first-screen reply")
    await model.pollOnceForTesting()
    precondition(chats.sent.count == 1 && chats.sent[0].0 == "C" && model.running)
    chats.unread["C"] = 0
    for _ in 0..<2 {
        let count = chats.scanCount
        await model.pollOnceForTesting()
        precondition(chats.scanCount == count + 1 && requests == ["C newest"])
    }
    precondition(!chats.openedNames.contains("D"))

    // An off-screen contact remains undiscovered until it enters the first
    // screen; a historical timestamp now excludes even its latest old message.
    chats.firstScreenNames.append("D")
    let appearedCount = chats.scanCount
    await model.pollOnceForTesting()
    precondition(chats.scanCount == appearedCount + 1 && requests == ["C newest"])
    precondition(chats.sent.count == 1 && !chats.openedNames.contains("D"))
    chats.messageDates["D"] = Date()
    await deliverLimitTestMessage("D fresh", to: "D", model: model, chats: chats)
    precondition(requests == ["C newest", "D fresh"] && chats.sent.count == 2 && chats.sent.last!.0 == "D" && model.running)
    chats.unread["D"] = 0
    await deliverLimitTestMessage("停止自动回复", to: "D", model: model, chats: chats)
    let stoppedRequests = requests.count
    await deliverLimitTestMessage("D later message", to: "D", model: model, chats: chats)
    precondition(model.running && requests.count == stoppedRequests && chats.sent.count == 2)
    precondition(model.log.contains { $0.kind == "暂停好友" && $0.contact == "D" })
    model.stop()

    // A selected friend explicitly shown in the current chat can start without
    // scanning the list, even when that chat is absent from its first viewport.
    let selectedChats = MemoryChats(); selectedChats.firstScreenNames = ["B"]
    var selectedRequests = 0
    let selected = Assistant(reader: selectedChats, isolatedTest: true, replyGenerator: { incoming, _ in
        precondition(incoming == "selected new"); selectedRequests += 1; return "selected reply"
    })
    selected.key = "test-only"; selected.contact = "A"; selected.autoSend = true
    selected.start(); await selected.pollOnceForTesting()
    precondition(selected.running && selectedChats.scanCount == 0 && selectedRequests == 0)
    await deliverLimitTestMessage("selected new", to: "A", model: selected, chats: selectedChats)
    precondition(selected.running && selectedChats.scanCount == 0 && selectedRequests == 1 && selectedChats.sent.count == 1)
    selected.stop()
    print("PASS: first-screen-only scans, old unread baseline, newest-only discovery, off-screen exclusion, scan reuse, selected snapshot baseline and user ownership protection")
}
