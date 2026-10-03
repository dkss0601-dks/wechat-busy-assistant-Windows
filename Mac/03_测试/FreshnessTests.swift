import Cocoa
import ApplicationServices

@MainActor func freshnessTests() async {
    let now = Date()
    let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
    let clock = formatter.string(from: now)
    let historical = chatCandidate("Friend,old,2026/09/26,1 unread message(s)", now: now)!
    precondition(!candidateIsRecent(historical, startedAt: now, now: now))
    precondition(!candidateIsRecent(ChatCandidate(name: "Friend", signature: "unknown", unread: 1), startedAt: now))
    precondition(unreadCount("Friend,1 unread message(s)," + clock) == 0)
    precondition(unreadCount("Friend,12条未读," + clock) == 0)
    let read = chatCandidate("Friend,new," + clock + ",Sticky on Top", now: now)!
    let markedUnread = chatCandidate("Friend,new," + clock + ",1 unread message(s),Sticky on Top", now: now)!
    precondition(read.signature == markedUnread.signature && newUnreadCount(old: read, new: markedUnread) == 0)
    precondition(candidateIsRecent(markedUnread, startedAt: now, now: now))
    let staleBody = Snapshot(name: "Friend", rows: ["FriendSaid:old"], input: AXUIElementCreateApplication(0), draft: "", pid: 0, isDirect: true)
    precondition(!candidateMatchesLatestMessage(markedUnread, snapshot: staleBody))
    let readyBody = Snapshot(name: "Friend", rows: ["FriendSaid:new"], input: staleBody.input, draft: "", pid: 0, isDirect: true)
    precondition(candidateMatchesLatestMessage(markedUnread, snapshot: readyBody))
    for preview in ["[Sticker]", "[Sticker] 早安", "[动画表情]", "[动画表情] 早安"] {
        precondition(mediaPreviewKind(preview) == .sticker)
    }
    for preview in ["[Image]", "[image] 说明", "[Photo]", "[Picture]", "[图片]", "[图片] 说明"] {
        precondition(mediaPreviewKind(preview) == .image)
    }
    for preview in ["[Video]", "[视频] 片段"] { precondition(mediaPreviewKind(preview) == .video) }
    for preview in ["[Voice]", "[语音] 片段"] { precondition(mediaPreviewKind(preview) == .voice) }
    precondition(mediaPreviewKind("[unknown] text") == .other)
    for preview in ["早安", "今天[图片]", "[Sticker]ish"] {
        precondition(mediaPreviewKind(preview) == nil)
    }
    precondition(parseMediaMessage("Friend:Sent aSTICKER,早安", contact: "Friend")?.kind == .sticker)
    precondition(parseMediaMessage("Friend:Sent aPhoto", contact: "Friend")?.kind == .image)
    precondition(parseMediaMessage("Friend:Sent aPhoto,sticker album", contact: "Friend")?.kind == .image)
    precondition(parseMediaMessage("Friend:Sent aVideo", contact: "Friend")?.kind == .video)
    precondition(parseMediaMessage("Friend:Sent aFile", contact: "Friend")?.kind == .other)
    precondition(parseMediaMessage("Me:Sent aSTICKER", contact: "Friend")?.mine == true)
    precondition(parseMediaMessage("FriendSaid:[Sticker] 早安", contact: "Friend") == nil)

    let chats = MemoryChats()
    chats.messageDates["A"] = now.addingTimeInterval(-86400)
    chats.messageDates["B"] = now.addingTimeInterval(-86400)
    var incoming: [String] = []
    let model = Assistant(reader: chats, isolatedTest: true, replyGenerator: { text, _ in incoming.append(text); return "safe reply" })
    model.key = "test-only"; model.scope = .all; model.autoSend = true
    model.start(); await model.pollOnceForTesting()
    // Rendering another old row in the initially open, already-read chat must
    // not create either an API request or an unsolicited reply.
    chats.rows["A"]!.append("ASaid:late-rendered historical text")
    await model.pollOnceForTesting()
    precondition(incoming.isEmpty && model.draft.isEmpty && chats.sent.isEmpty)
    // Even a new unread mark or a newly discovered contact is insufficient
    // when the list timestamp predates this session.
    chats.unread["B"] = 1
    chats.rows["C"] = ["CSaid:old unanswered"]
    chats.messageDates["C"] = now.addingTimeInterval(-86400)
    chats.unread["C"] = 1; chats.firstScreenNames.append("C")
    await model.pollOnceForTesting()
    precondition(incoming.isEmpty && chats.sent.isEmpty && !chats.openedNames.contains("C"))
    // The same friend can still deliver a genuinely new message this session.
    chats.messageDates["C"] = Date(); chats.rows["C"]!.append("CSaid:fresh delivery"); chats.unread["C"] = 2
    await model.pollOnceForTesting(); await model.pollOnceForTesting()
    precondition(incoming == ["fresh delivery"] && chats.sent.count == 1 && chats.sent[0].0 == "C")
    model.stop()

    // The friend already appears in the first-screen baseline, but becomes
    // the open chat only later. WeChat reads the first incoming row immediately.
    let openChats = MemoryChats()
    var openRequests: [String] = []
    let openModel = Assistant(reader: openChats, isolatedTest: true, replyGenerator: { text, _ in
        openRequests.append(text); return "reply to open chat"
    })
    openModel.key = "test-only"; openModel.scope = .all; openModel.autoSend = true
    openModel.start(); await openModel.pollOnceForTesting()
    openChats.current = "B"
    openChats.rows["B"]!.append("BSaid:first new message")
    openChats.unread["B"] = 0
    await openModel.pollOnceForTesting(); await openModel.pollOnceForTesting()
    precondition(openRequests == ["first new message"] && openChats.sent.count == 1 && openChats.sent[0].0 == "B")
    openModel.stop()

    // Opening an unread conversation can clear its badge before its body has
    // finished loading. Keep the old list baseline until the body catches up.
    let loadingChats = MemoryChats()
    var loadingRequests: [String] = []
    let loadingModel = Assistant(reader: loadingChats, isolatedTest: true, replyGenerator: { text, _ in
        loadingRequests.append(text); return "reply after load"
    })
    loadingModel.key = "test-only"; loadingModel.scope = .all; loadingModel.autoSend = true
    loadingModel.start(); await loadingModel.pollOnceForTesting()
    loadingChats.previewOverrides["B"] = "arrived while loading"
    loadingChats.unread["B"] = 1
    await loadingModel.pollOnceForTesting()
    precondition(loadingRequests.isEmpty && loadingChats.sent.isEmpty)
    // A different friend may be handled while B's body is stale. Returning to
    // B must still recover even though opening B cleared its unread badge.
    loadingChats.rows["C"] = ["CSaid:another fresh delivery"]
    loadingChats.unread["C"] = 1; loadingChats.firstScreenNames.append("C")
    await loadingModel.pollOnceForTesting(); await loadingModel.pollOnceForTesting()
    precondition(loadingRequests == ["another fresh delivery"] && loadingChats.sent.count == 1 && loadingChats.current == "C")
    loadingChats.unread["B"] = 0
    loadingChats.rows["B"]!.append("BSaid:arrived while loading")
    await loadingModel.pollOnceForTesting(); await loadingModel.pollOnceForTesting()
    precondition(loadingRequests == ["another fresh delivery", "arrived while loading"] && loadingChats.sent.count == 2 && loadingChats.sent[1].0 == "B")
    loadingModel.stop()

    // A real sticker row and its list placeholder describe the same media in
    // different words. Send one fixed notice, then handle later text normally.
    let stickerChats = MemoryChats()
    var stickerAIRequests: [String] = []
    let stickerModel = Assistant(reader: stickerChats, isolatedTest: true, replyGenerator: { text, _ in
        stickerAIRequests.append(text); return "text reply"
    })
    stickerModel.key = "test-only"; stickerModel.scope = .all; stickerModel.autoSend = true
    stickerModel.start(); await stickerModel.pollOnceForTesting()
    stickerChats.rows["B"]!.append("B:Sent aSTICKER,早安")
    stickerChats.previewOverrides["B"] = "[Sticker] 早安"; stickerChats.unread["B"] = 1
    stickerChats.drafts["B"] = "user's unfinished text"
    await stickerModel.pollOnceForTesting()
    precondition(stickerChats.sent.isEmpty && stickerChats.drafts["B"] == "user's unfinished text")
    stickerChats.drafts["B"] = ""
    await stickerModel.pollOnceForTesting(); await stickerModel.pollOnceForTesting()
    precondition(stickerAIRequests.isEmpty && stickerChats.sent.count == 1 && stickerChats.sent[0].0 == "B")
    precondition(stickerChats.sent[0].1.contains("无法识别这个表情包"))
    await stickerModel.pollOnceForTesting()
    precondition(stickerChats.sent.count == 1)
    stickerChats.rows["B"]!.append("BSaid:接着说")
    stickerChats.previewOverrides["B"] = "接着说"; stickerChats.unread["B"] = 1
    await stickerModel.pollOnceForTesting(); await stickerModel.pollOnceForTesting()
    precondition(stickerAIRequests == ["接着说"] && stickerChats.sent.count == 2)
    stickerModel.stop()

    // A newly opened, already-read conversation can receive an image first.
    let imageChats = MemoryChats()
    var imageAIRequests = 0
    let imageModel = Assistant(reader: imageChats, isolatedTest: true, replyGenerator: { _, _ in
        imageAIRequests += 1; return "unexpected"
    })
    imageModel.key = "test-only"; imageModel.scope = .all; imageModel.autoSend = true
    imageModel.start(); await imageModel.pollOnceForTesting()
    imageChats.current = "B"
    imageChats.rows["B"]!.append("B:Sent aPhoto")
    imageChats.previewOverrides["B"] = "[图片]"; imageChats.unread["B"] = 0
    await imageModel.pollOnceForTesting(); await imageModel.pollOnceForTesting()
    precondition(imageAIRequests == 0 && imageChats.sent.count == 1 && imageChats.sent[0].1.contains("无法识别这张图片"))
    imageModel.stop()

    let selectedMediaChats = MemoryChats()
    var selectedMediaAI: [String] = []
    let selectedMediaModel = Assistant(reader: selectedMediaChats, isolatedTest: true, replyGenerator: { text, _ in
        selectedMediaAI.append(text); return "text reply"
    })
    selectedMediaModel.key = "test-only"; selectedMediaModel.contact = "A"; selectedMediaModel.autoSend = true
    selectedMediaModel.start(); await selectedMediaModel.pollOnceForTesting()
    selectedMediaChats.rows["A"]!.append("A:Sent aPhoto")
    await selectedMediaModel.pollOnceForTesting(); await selectedMediaModel.pollOnceForTesting()
    precondition(selectedMediaAI.isEmpty && selectedMediaChats.sent.count == 1 && selectedMediaChats.sent[0].1.contains("无法识别这张图片"))
    selectedMediaChats.rows["A"]!.append("ASaid:这是刚拍的")
    selectedMediaChats.rows["A"]!.append("A:Sent aSTICKER")
    await selectedMediaModel.pollOnceForTesting(); await selectedMediaModel.pollOnceForTesting()
    precondition(selectedMediaAI == ["这是刚拍的"] && selectedMediaChats.sent.count == 2)
    selectedMediaModel.stop()

    let uncertainMediaChats = MemoryChats(); uncertainMediaChats.uncertain = true
    let uncertainMediaModel = Assistant(reader: uncertainMediaChats, isolatedTest: true, replyGenerator: { _, _ in "unexpected" })
    uncertainMediaModel.key = "test-only"; uncertainMediaModel.contact = "A"; uncertainMediaModel.autoSend = true
    uncertainMediaModel.start(); await uncertainMediaModel.pollOnceForTesting()
    uncertainMediaChats.rows["A"]!.append("A:Sent aPhoto")
    await uncertainMediaModel.pollOnceForTesting(); await uncertainMediaModel.pollOnceForTesting(); await uncertainMediaModel.pollOnceForTesting()
    precondition(uncertainMediaChats.sent.isEmpty && uncertainMediaModel.log.contains { $0.kind == "暂停好友" && $0.contact == "A" })
    uncertainMediaModel.stop()

    // Videos are deliberately not answered, but a subsequent text delivery
    // remains eligible. Re-marking an unchanged old sticker is also ignored.
    let videoChats = MemoryChats()
    var videoRequests: [String] = []
    let videoModel = Assistant(reader: videoChats, isolatedTest: true, replyGenerator: { text, _ in
        videoRequests.append(text); return "text after video"
    })
    videoModel.key = "test-only"; videoModel.scope = .all; videoModel.autoSend = true
    videoModel.start(); await videoModel.pollOnceForTesting()
    videoChats.rows["B"]!.append("B:Sent aVideo")
    videoChats.previewOverrides["B"] = "[Video]"; videoChats.unread["B"] = 1
    await videoModel.pollOnceForTesting()
    precondition(videoRequests.isEmpty && videoChats.sent.isEmpty && !videoChats.openedNames.contains("B"))
    videoChats.rows["B"]!.append("BSaid:视频后的新文字")
    videoChats.previewOverrides["B"] = "视频后的新文字"; videoChats.unread["B"] = 2
    await videoModel.pollOnceForTesting(); await videoModel.pollOnceForTesting()
    precondition(videoRequests == ["视频后的新文字"] && videoChats.sent.count == 1)
    videoModel.stop()

    let unknownChats = MemoryChats()
    var unknownRequests: [String] = []
    let unknownModel = Assistant(reader: unknownChats, isolatedTest: true, replyGenerator: { text, _ in
        unknownRequests.append(text); return "text reply"
    })
    unknownModel.key = "test-only"; unknownModel.scope = .all; unknownModel.autoSend = true
    unknownModel.start(); await unknownModel.pollOnceForTesting()
    unknownChats.rows["B"]!.append("B:Sent aFile")
    unknownChats.previewOverrides["B"] = "[File]"; unknownChats.unread["B"] = 1
    await unknownModel.pollOnceForTesting()
    precondition(unknownRequests.isEmpty && unknownChats.sent.isEmpty)
    unknownChats.rows["B"]!.append("BSaid:文件后的文字")
    unknownChats.previewOverrides["B"] = "文件后的文字"; unknownChats.unread["B"] = 2
    await unknownModel.pollOnceForTesting(); await unknownModel.pollOnceForTesting()
    precondition(unknownRequests == ["文件后的文字"] && unknownChats.sent.count == 1)
    unknownModel.stop()

    let bracketTextChats = MemoryChats()
    var bracketRequests: [String] = []
    let bracketModel = Assistant(reader: bracketTextChats, isolatedTest: true, replyGenerator: { text, _ in
        bracketRequests.append(text); return "emoji text reply"
    })
    bracketModel.key = "test-only"; bracketModel.scope = .all; bracketModel.autoSend = true
    bracketModel.start(); await bracketModel.pollOnceForTesting()
    bracketTextChats.rows["B"]!.append("BSaid:[Whimper]")
    bracketTextChats.previewOverrides["B"] = "[Whimper]"; bracketTextChats.unread["B"] = 1
    await bracketModel.pollOnceForTesting(); await bracketModel.pollOnceForTesting()
    precondition(bracketRequests == ["[Whimper]"] && bracketTextChats.sent.count == 1)
    bracketModel.stop()

    let oldMediaChats = MemoryChats()
    oldMediaChats.messageDates["B"] = now.addingTimeInterval(-86400)
    var oldMediaRequests = 0
    let oldMediaModel = Assistant(reader: oldMediaChats, isolatedTest: true, replyGenerator: { _, _ in
        oldMediaRequests += 1; return "unexpected"
    })
    oldMediaModel.key = "test-only"; oldMediaModel.scope = .all; oldMediaModel.autoSend = true
    oldMediaModel.start(); await oldMediaModel.pollOnceForTesting()
    oldMediaChats.rows["B"]!.append("B:Sent aSTICKER")
    oldMediaChats.previewOverrides["B"] = "[动画表情]"; oldMediaChats.unread["B"] = 1
    await oldMediaModel.pollOnceForTesting()
    precondition(oldMediaRequests == 0 && oldMediaChats.sent.isEmpty)
    oldMediaModel.stop()

    let markedMediaChats = MemoryChats()
    markedMediaChats.rows["B"]!.append("B:Sent aSTICKER")
    markedMediaChats.previewOverrides["B"] = "[Sticker]"
    let markedMediaModel = Assistant(reader: markedMediaChats, isolatedTest: true, replyGenerator: { _, _ in "unexpected" })
    markedMediaModel.key = "test-only"; markedMediaModel.scope = .all; markedMediaModel.autoSend = true
    markedMediaModel.start(); await markedMediaModel.pollOnceForTesting()
    markedMediaChats.unread["B"] = 1
    await markedMediaModel.pollOnceForTesting()
    precondition(markedMediaChats.sent.isEmpty && !markedMediaChats.openedNames.contains("B"))
    markedMediaModel.stop()

    // Verify the actual events have Return text, the correct physical key and
    // no inherited command/control modifiers. No events are posted by tests.
    let events = try! backgroundReturnEvents()
    for event in [events.0, events.1] {
        var length = 0
        var character: UniChar = 0
        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &length, unicodeString: &character)
        precondition(length == 1 && character == 0x0D)
        precondition(event.getIntegerValueField(.keyboardEventKeycode) == 0x24 && event.flags.isEmpty)
    }
    precondition(events.0.type == .keyDown && events.1.type == .keyUp)
    precondition(fileTransferDiagnosticAllowed(name: "File Transfer", isDirect: false))
    precondition(fileTransferDiagnosticAllowed(name: "文件传输助手", isDirect: false))
    precondition(!fileTransferDiagnosticAllowed(name: "Friend", isDirect: true))
    precondition(!fileTransferDiagnosticAllowed(name: "File Transfer", isDirect: true))
    precondition(!fileTransferDiagnosticAllowed(name: "Group", isDirect: false))
    print("PASS: historical/read conversations do not replay, preview badges are not unread counts, stale cached bodies are rejected, fresh deliveries continue and background Return has explicit characters")
}
