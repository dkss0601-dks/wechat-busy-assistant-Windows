import Cocoa

private func rejectsExtendedReply(_ value: String, requiresQuestion: Bool = true) {
    do { _ = try validatedExtendedReply(value, requiresQuestion: requiresQuestion); preconditionFailure("Expected invalid reply to be rejected") }
    catch is ReplyFormatError { }
    catch { preconditionFailure("Unexpected error type") }
}

private func parts(_ reply: String, _ followUp: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: ["reply": reply, "follow_up": followUp])
    return String(data: data, encoding: .utf8)!
}

func conversationRulesTests() {
    precondition(SessionChoices.minuteOptions(for: 35).contains(35))
    precondition(SessionChoices.roundOptions(for: 7).contains(7))
    precondition(SessionChoices.normalizedMinutes(0) == 5 && SessionChoices.normalizedMinutes(Int.max) == 480)
    precondition(SessionChoices.normalizedLimit(0) == 1 && SessionChoices.normalizedLimit(Int.max) == 100)
    precondition(!SessionChoices.reachedLimit(rounds: 10_000, limit: nil))
    precondition(SessionChoices.reachedLimit(rounds: 2, limit: 2))
    precondition(shouldExtendTopic("今天听了爵士钢琴，很喜欢。"))
    precondition(shouldExtendTopic("谢谢，你喜欢哪部电影？"))
    for text in ["晚安！", "好的，谢谢你！", "谢谢你，晚安", "谢谢\n拜拜", "不聊了，我先忙了", "我现在在忙，晚点再聊", "不要追问", "这是急事，请马上联系本人", "bye", "urgent: please contact them"] {
        precondition(!shouldExtendTopic(text))
    }
    let response = parts("听起来很放松。", "你更喜欢独奏还是乐队演奏？")
    precondition(try! validatedExtendedReply(response, requiresQuestion: true) == "听起来很放松。\n你更喜欢独奏还是乐队演奏？")
    precondition(try! validatedExtendedReply("```json\n" + response + "\n```", requiresQuestion: true).contains("你更喜欢"))
    let closing = parts("晚安，祝你好梦。", "")
    precondition(try! validatedExtendedReply(closing, requiresQuestion: false) == "晚安，祝你好梦。")
    for bad in ["plain text?", "{}", parts("", "你喜欢什么？"), parts("听起来不错。", ""), parts("听起来不错。", "？"), parts("听起来不错。", "... ?"), parts("不错。", "请继续说"), parts("你喜欢爵士吗？", "哪位演奏者？"), parts(String(repeating: "长", count: 501), "喜欢吗？"), parts("不可用\0", "好吗？")] {
        rejectsExtendedReply(bad)
    }
    rejectsExtendedReply(response, requiresQuestion: false)
    rejectsExtendedReply(parts("你还想聊什么？", ""), requiresQuestion: false)
    let prompt = makeReplyPrompt(activity: "工作", tone: "轻松幽默", instructions: "", interaction: .playful, expansion: .continuous, profile: nil)
    precondition(prompt.contains("必须主动接出") && prompt.contains("不要反复问同一个问题"))
    print("PASS: quick selection bounds, unlimited cap, closing signals and structured follow-up validation")
}

@MainActor func conversationLifecycleTests() async {
    let chats = MemoryChats()
    var requests = 0
    var captured: [[[String: String]]] = []
    let model = Assistant(reader: chats, isolatedTest: true, completionGenerator: { messages in
        requests += 1; captured.append(messages)
        if requests == 1 { return parts("很好听。", "") }
        return parts("爵士的节奏很适合放松。", "你偏爱即兴还是熟悉的旋律？")
    })
    model.key = "test-only"; model.contact = "A"; model.expansion = .continuous; model.autoSend = true
    model.start(); await model.pollOnceForTesting()
    model.expansion = .off // active turn continues to enforce the frozen setting
    chats.rows["A"]!.append("ASaid:今天在听爵士")
    await model.pollOnceForTesting()
    precondition(requests == 2 && captured[0].contains { $0["content"]?.contains("本次必须延伸话题") == true })
    precondition(captured[1].last?["role"] == "system" && captured[1].last?["content"]?.contains("上一次回答") == true)
    precondition(model.draft.hasSuffix("？") && !model.draft.contains("follow_up") && chats.sent.isEmpty)
    await model.pollOnceForTesting()
    precondition(chats.sent.count == 1 && chats.sent[0].1.hasSuffix("？"))
    await model.pollOnceForTesting(); precondition(requests == 2 && chats.sent.count == 1)
    model.stop()

    let badChats = MemoryChats()
    var badRequests = 0
    let bad = Assistant(reader: badChats, isolatedTest: true, completionGenerator: { _ in badRequests += 1; return parts("不会接话。", "") })
    bad.key = "test-only"; bad.contact = "A"; bad.expansion = .continuous; bad.autoSend = true
    bad.start(); await bad.pollOnceForTesting(); badChats.rows["A"]!.append("ASaid:在看电影")
    await bad.pollOnceForTesting()
    precondition(badRequests == 2 && bad.draft.isEmpty && badChats.sent.isEmpty && bad.running)
    await bad.pollOnceForTesting(); precondition(badRequests == 2 && badChats.sent.isEmpty) // existing retry delay still applies
    bad.stop()

    let endChats = MemoryChats()
    var endRequest: [[String: String]] = []
    let ending = Assistant(reader: endChats, isolatedTest: true, completionGenerator: { messages in endRequest = messages; return parts("晚安，祝你好梦。", "") })
    ending.key = "test-only"; ending.contact = "A"; ending.expansion = .continuous
    ending.start(); await ending.pollOnceForTesting(); endChats.rows["A"]!.append("ASaid:晚安！")
    await ending.pollOnceForTesting()
    precondition(ending.draft == "晚安，祝你好梦。" && endRequest.contains { $0["content"]?.contains("follow_up 必须为空字符串") == true })
    ending.stop()

    let cancelChats = MemoryChats()
    var cancelRequests = 0
    var cancelled: Assistant!
    cancelled = Assistant(reader: cancelChats, isolatedTest: true, completionGenerator: { _ in
        cancelRequests += 1; cancelled.stop(); return parts("未完成。", "")
    })
    cancelled.key = "test-only"; cancelled.contact = "A"; cancelled.expansion = .continuous
    cancelled.start(); await cancelled.pollOnceForTesting(); cancelChats.rows["A"]!.append("ASaid:继续聊电影")
    await cancelled.pollOnceForTesting()
    precondition(cancelRequests == 1 && !cancelled.running && cancelled.draft.isEmpty && cancelChats.sent.isEmpty)
    print("PASS: forced follow-up correction, frozen expansion, invalid draft suppression, ending signals and correction cancellation")
}
