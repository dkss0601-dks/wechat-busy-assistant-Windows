import Foundation

enum SessionChoices {
    static let minutes = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480]
    static let limits = [1, 2, 3, 5, 8, 10, 15, 20, 30, 50, 100]
    static func minuteOptions(for current: Int) -> [Int] { Array(Set(minutes + [normalizedMinutes(current)])).sorted() }
    static func roundOptions(for current: Int) -> [Int] { Array(Set(limits + [normalizedLimit(current)])).sorted() }
    static func normalizedMinutes(_ value: Int) -> Int { min(480, max(5, value)) }
    static func normalizedLimit(_ value: Int) -> Int { min(100, max(1, value)) }
    static func reachedLimit(rounds: Int, limit: Int?) -> Bool { limit.map { rounds >= $0 } ?? false }
}

/// Ending a conversation takes precedence over the user's topic-extension setting.
func shouldExtendTopic(_ incoming: String) -> Bool {
    let text = incoming.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
    let endings = ["拜拜", "再见", "晚安", "谢谢", "谢谢你", "谢谢啦", "谢谢你啦", "好的谢谢", "嗯谢谢", "thanks", "thank you", "bye", "goodnight", "good night", "talk later"]
    let clauses = text.components(separatedBy: CharacterSet(charactersIn: "，,。.!！\n\r；;"))
        .map { $0.trimmingCharacters(in: trimSet) }.filter { !$0.isEmpty }
    if let last = clauses.last, endings.contains(last) { return false }
    let signals = ["先不聊", "不聊了", "别再问", "不要追问", "别追问", "不要再问", "别再发", "不用回复", "不用回了", "不需要回复", "别回复", "不要回复", "停止自动回复", "别自动回复", "不要自动回复", "我先忙了", "先去忙了", "我现在在忙", "我正在忙", "我在忙", "我现在很忙", "我有点忙", "现在没空", "暂时没空", "现在不方便", "晚点再聊", "等下再聊", "等会再聊", "稍后再聊", "我要睡了", "我去睡了", "我先走了", "回头聊", "下次再聊", "改天再聊", "先这样", "就这样吧", "stop asking", "don't reply", "do not reply", "got to go", "gotta go", "talk to you later", "紧急", "救命", "急救", "报警", "马上联系", "急事", "赶紧回我", "urgent", "emergency"]
    return !signals.contains(where: { text.contains($0) })
}

struct ReplyFormatError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Only the assembled reply leaves this function; JSON fields are never sent to WeChat.
func validatedExtendedReply(_ content: String, requiresQuestion: Bool) throws -> String {
    var json = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if json.hasPrefix("```"), json.hasSuffix("```") {
        let lines = json.components(separatedBy: "\n")
        guard lines.count >= 3, ["```", "```json"].contains(lines[0].lowercased()) else {
            throw ReplyFormatError(message: "AI 回复格式不完整，未发送。")
        }
        json = lines.dropFirst().dropLast().joined(separator: "\n")
    }
    struct Parts: Decodable { let reply: String; let follow_up: String }
    guard let data = json.data(using: .utf8), data.count <= 8_192,
          let parts = try? JSONDecoder().decode(Parts.self, from: data) else {
        throw ReplyFormatError(message: "AI 回复格式不完整，未发送。")
    }
    let reply = parts.reply.trimmingCharacters(in: .whitespacesAndNewlines)
    let question = parts.follow_up.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reply.isEmpty else { throw ReplyFormatError(message: "AI 回复为空，未发送。") }
    if requiresQuestion {
        let questions = (reply + question).filter { $0 == "?" || $0 == "？" }.count
        let questionBody = String(question.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        guard !questionBody.isEmpty, question.hasSuffix("?") || question.hasSuffix("？"), questions == 1 else {
            throw ReplyFormatError(message: "持续延伸回复缺少一个有效的后续问题，未发送。")
        }
    } else {
        // Respect ending/urgent signals even if the model tries to add a new topic.
        guard question.isEmpty, !reply.contains("?"), !reply.contains("？") else { throw ReplyFormatError(message: "对方需要收尾或有紧急事情，AI 仍在拓展话题，未发送。") }
    }
    let message = question.isEmpty ? reply : reply + "\n" + question
    guard message.count <= 500, !message.contains("\0"), !message.contains("```") else {
        throw ReplyFormatError(message: "AI 回复过长或格式异常，未发送。")
    }
    return message
}

func extensionTurnInstruction(requiresQuestion: Bool) -> String {
    let requirement = requiresQuestion
        ? "本次必须延伸话题：reply 先用一至两句陈述回应，follow_up 必须是一个贴着当前话题、轻松易答的新问题，并以问号结尾；两个字段合计恰好一个问号。不要重复最近已经问过的问题，不要只问泛泛的‘还有什么事吗’。"
        : "本次出现收尾、停止追问或紧急信号：认真回应或自然结束，reply 使用陈述句，不要问句，follow_up 必须为空字符串，不再引出话题。"
    return requirement + "只输出 JSON 对象，两个字段均为字符串：{\"reply\":\"回复正文\",\"follow_up\":\"后续问题或空字符串\"}。不要代码围栏或其他文字。"
}

func extensionCorrectionInstruction(requiresQuestion: Bool) -> String {
    "上一次回答没有满足本次的回复格式，请重新生成完整回答；修正内容尚未发送给好友。" + extensionTurnInstruction(requiresQuestion: requiresQuestion)
}
