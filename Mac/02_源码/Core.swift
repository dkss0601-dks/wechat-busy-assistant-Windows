import Cocoa
import SwiftUI
import ApplicationServices
import Security

struct AssistantError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct RetryLater: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct SendUncertain: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Navigation and ordinary computer use never end a session. Only WeChat itself
// needs exclusive access while a background operation changes its controls.
func backgroundOperationAllowed(wechatIsFrontmost: Bool, sessionIsActive: Bool) -> Bool {
    sessionIsActive && !wechatIsFrontmost
}

struct Message: Equatable {
    let raw: String
    let text: String
    let mine: Bool
}

struct MediaMessage: Equatable {
    let raw: String
    let kind: MediaPreviewKind
    let mine: Bool
}

// Only accept explicit sender labels exposed by this WeChat version.
// Unknown sender labels, timestamps and media are never passed to the model.
func parseMessage(_ raw: String, contact: String) -> Message? {
    for (prefix, mine) in [("MeSaid:", true), ("\(contact)Said:", false)] {
        if raw.hasPrefix(prefix) {
            let text = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Message(raw: raw, text: text, mine: mine)
        }
    }
    return nil
}

func parseMediaMessage(_ raw: String, contact: String) -> MediaMessage? {
    let prefixes: [(String, Bool)] = [
        ("\(contact):Sent a", false), ("\(contact):Sent an", false),
        ("Me:Sent a", true), ("Me:Sent an", true),
        ("\(contact):发送了", false), ("我:发送了", true)
    ]
    guard let (prefix, mine) = prefixes.first(where: { raw.hasPrefix($0.0) }) else { return nil }
    let description = String(raw.dropFirst(prefix.count).split(separator: ",", maxSplits: 1,
        omittingEmptySubsequences: false).first ?? "").lowercased()
    let markers: [(MediaPreviewKind, [String])] = [
        (.sticker, ["sticker", "动画表情"]),
        (.image, ["photo", "image", "picture", "图片"]),
        (.video, ["video", "视频"]),
        (.voice, ["voice", "语音"])
    ]
    let kind = markers.first(where: { $0.1.contains(where: description.contains) })?.0 ?? .other
    return MediaMessage(raw: raw, kind: kind, mine: mine)
}

func latestMessageRow(_ rows: [String]) -> String? {
    rows.last(where: { $0.contains("Said:") || $0.contains(":Sent a") || $0.contains(":发送了") })
}

func latestMediaMessage(_ snapshot: Snapshot) -> MediaMessage? {
    latestMessageRow(snapshot.rows).flatMap { parseMediaMessage($0, contact: snapshot.name) }
}

// Require overlap with the prior visible history; never guess when scrolling
// or an unrecognised UI transition removes the baseline.
func appendedRows(previous: [String], current: [String]) -> [String]? {
    if previous == current { return [] }
    guard !previous.isEmpty, !current.isEmpty else { return nil }
    for count in stride(from: min(previous.count, current.count), through: 1, by: -1) {
        if Array(previous.suffix(count)) == Array(current.prefix(count)) {
            return Array(current.dropFirst(count))
        }
    }
    return nil
}

struct Snapshot {
    let name: String
    let rows: [String]
    let input: AXUIElement
    let draft: String
    let pid: pid_t
    let isDirect: Bool
}

@MainActor protocol ChatAccess {
    func snapshot() throws -> Snapshot
    func isWeChatFrontmost() -> Bool
    func requireBackground(_ valid: () -> Bool) throws
    func scanChats(valid: () -> Bool) async throws -> [ChatCandidate]
    func openChat(name: String, valid: () -> Bool) async throws -> Snapshot
    func send(_ text: String, expected: Snapshot, stillActive: () -> Bool) async throws -> SendReceipt
}
extension WeChatReader: ChatAccess {}

struct SendReceipt {
    let rows: [String]
    let arrivedBeforeReply: [String]
}
func confirmedReply(previous: [String], current: [String], contact: String, text: String) -> SendReceipt? {
    guard let added = appendedRows(previous: previous, current: current),
          let index = added.firstIndex(where: { parseMessage($0, contact: contact).map { $0.mine && $0.text == text } ?? false }) else { return nil }
    return SendReceipt(rows: Array(current.dropLast(added.count - index - 1)),
        arrivedBeforeReply: added.prefix(index).compactMap { parseMessage($0, contact: contact).flatMap { $0.mine ? nil : $0.text } })
}

func backgroundReturnEvents() throws -> (CGEvent, CGEvent) {
    let source = CGEventSource(stateID: .privateState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
        throw AssistantError(message: "无法创建发送按键。")
    }
    // A background AppKit responder needs an explicit Return character, not
    // only its physical key code. Do not inherit modifiers from the user's app.
    var carriageReturn: UniChar = 0x0D
    for event in [down, up] {
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &carriageReturn)
    }
    return (down, up)
}

func fileTransferDiagnosticAllowed(name: String, isDirect: Bool) -> Bool {
    !isDirect && ["File Transfer", "文件传输助手"].contains(name)
}

let returnDiagnosticText = "忙碌消息助手：后台回车发送检查（仅文件传输助手，不调用 AI）。"

final class WeChatReader {
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    func string(_ element: AXUIElement, _ key: String) -> String {
        attribute(element, key) as? String ?? ""
    }
    func label(_ element: AXUIElement) -> String {
        firstString(element, ["AXTitle", "AXDescription"])
    }
    func firstString(_ element: AXUIElement, _ keys: [String]) -> String {
        for key in keys { let value = string(element, key); if !value.isEmpty { return value } }
        return ""
    }
    func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, "AXChildren") as? [AXUIElement] ?? []
    }
    func walk(_ root: AXUIElement, depth: Int = 24) -> [AXUIElement] {
        guard depth > 0 else { return [root] }
        return [root] + children(root).flatMap { walk($0, depth: depth - 1) }
    }
    // Do not enumerate hundreds of offscreen chat/message rows when looking
    // for the window's controls. AX requests cross process boundaries.
    func controls(_ root: AXUIElement, depth: Int = 16) -> [AXUIElement] {
        guard depth > 0, !["AXTable", "AXList"].contains(string(root, "AXRole")) else { return [root] }
        return [root] + children(root).flatMap { controls($0, depth: depth - 1) }
    }
    func firstDescendant(_ root: AXUIElement, depth: Int = 8, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        if matching(root) { return root }
        guard depth > 0 else { return nil }
        for child in children(root) { if let found = firstDescendant(child, depth: depth - 1, matching: matching) { return found } }
        return nil
    }
    func visibleRows(_ table: AXUIElement) -> [AXUIElement] {
        if let rows = attribute(table, "AXVisibleRows") as? [AXUIElement], !rows.isEmpty { return rows }
        if let rows = attribute(table, "AXVisibleChildren") as? [AXUIElement], !rows.isEmpty { return rows }
        return children(table)
    }
    func snapshot() throws -> Snapshot {
        let (window, pid) = try mainWindow()
        let elements = controls(window)
        let inputs = elements.filter {
            string($0, "AXRole") == "AXTextArea" && !label($0).isEmpty &&
            !["搜索", "Search"].contains(label($0))
        }
        guard inputs.count == 1, let input = inputs.first else {
            throw AssistantError(message: "无法唯一识别聊天输入框；请打开一个好友的聊天，关闭弹窗。")
        }
        let name = label(input)
        guard elements.contains(where: { string($0, "AXRole") == "AXStaticText" &&
            (string($0, "AXValue") == name || string($0, "AXTitle") == name) }) else {
            throw AssistantError(message: "聊天标题和输入框身份无法交叉核对，已停止。")
        }
        let lists = elements.filter {
            ["AXTable", "AXList"].contains(string($0, "AXRole")) &&
            ["Messages", "消息"].contains(label($0))
        }
        guard lists.count == 1, let list = lists.first else {
            throw AssistantError(message: "无法识别消息列表，此微信界面暂不兼容。")
        }
        guard let parentValue = attribute(list, "AXParent") else {
            throw AssistantError(message: "无法核对消息滚动位置，未读取。")
        }
        let parent = parentValue as! AXUIElement
        guard let scrollbar = children(parent).first(where: { string($0, "AXRole") == "AXScrollBar" }),
              let position = attribute(scrollbar, "AXValue") as? NSNumber,
              position.doubleValue >= 0.99 else {
            throw AssistantError(message: "请将微信消息列表滚动到最底部；历史消息不会用于自动回复。")
        }
        var rows: [String] = []
        for row in visibleRows(list) {
            guard let cell = firstDescendant(row, depth: 6, matching: {
                let identifier = string($0, "AXIdentifier")
                return identifier.hasPrefix("MM") && identifier.contains("MessageCellView") || identifier == "MMTimeStampCellView"
            }) else { continue }
            let label = firstString(cell, ["AXDescription", "AXValue", "AXTitle"])
            guard !label.isEmpty else { continue }
            // A timestamp or media row is also part of the history fingerprint.
            rows.append(label)
        }
        guard !rows.isEmpty else { throw AssistantError(message: "没有可读取的消息；请打开有聊天记录的好友对话。") }
        let buttonNames = Set(elements.filter { string($0, "AXRole") == "AXButton" }.flatMap { [string($0, "AXTitle"), string($0, "AXDescription")] })
        let direct = !buttonNames.isDisjoint(with: ["Video Call", "视频通话"]) && !buttonNames.isDisjoint(with: ["Voice Call", "语音通话"])
        return Snapshot(name: name, rows: rows, input: input, draft: string(input, "AXValue"), pid: pid, isDirect: direct)
    }

    func isWeChatFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.tencent.xinWeChat"
    }
    func requireBackground(_ valid: () -> Bool) throws {
        guard valid(), !Task.isCancelled else { throw CancellationError() }
        guard !isWeChatFrontmost() else { throw RetryLater(message: "你正在使用微信，助手暂缓操作；切到其他应用后继续，忙碌模式保持开启。") }
    }

    @MainActor func send(_ text: String, expected: Snapshot, stillActive: () -> Bool) async throws -> SendReceipt {
        try await performSend(text, expected: expected, selfDiagnostic: false, stillActive: stillActive)
    }

    @MainActor func checkReturnToFileTransfer(expected: Snapshot, stillActive: () -> Bool) async throws -> SendReceipt {
        guard fileTransferDiagnosticAllowed(name: expected.name, isDirect: expected.isDirect) else {
            throw AssistantError(message: "发送键检查只允许文件传输助手，不向好友发送检查文字。")
        }
        return try await performSend(returnDiagnosticText, expected: expected, selfDiagnostic: true, stillActive: stillActive)
    }

    @MainActor private func performSend(_ text: String, expected: Snapshot, selfDiagnostic: Bool,
                                       stillActive: () -> Bool) async throws -> SendReceipt {
        func eligible(_ snapshot: Snapshot) -> Bool {
            selfDiagnostic ? fileTransferDiagnosticAllowed(name: snapshot.name, isDirect: snapshot.isDirect) : snapshot.isDirect
        }
        try requireBackground(stillActive)
        guard NSRunningApplication(processIdentifier: expected.pid)?.bundleIdentifier == "com.tencent.xinWeChat" else { throw RetryLater(message: "微信进程已变化，重新核对后继续。") }
        let before = try snapshot()
        guard before.pid == expected.pid, eligible(before), before.name == expected.name, before.rows == expected.rows, before.draft.isEmpty else {
            throw RetryLater(message: "消息或输入框有变化，暂缓发送并重新核对。")
        }
        let (down, up) = try backgroundReturnEvents()
        var filled = false
        var posted = false
        do {
            try requireBackground(stillActive)
            guard AXUIElementSetAttributeValue(before.input, "AXFocused" as CFString, kCFBooleanTrue) == .success else {
                throw RetryLater(message: "微信暂不接受后台输入焦点，稍后重试。")
            }
            try requireBackground(stillActive)
            guard AXUIElementSetAttributeValue(before.input, "AXValue" as CFString, text as CFString) == .success else {
                throw RetryLater(message: "微信暂不接受后台填写，稍后重试。")
            }
            filled = true
            // Setting AXValue may rebuild WeChat's editor and reset its internal
            // responder. Reacquire focus on the actual filled input before Return.
            try await Task.sleep(nanoseconds: 100_000_000)
            try requireBackground(stillActive)
            let filledSnapshot = try snapshot()
            guard filledSnapshot.pid == expected.pid, eligible(filledSnapshot),
                  filledSnapshot.name == expected.name, filledSnapshot.rows == expected.rows,
                  filledSnapshot.draft == text else {
                throw RetryLater(message: "填写后聊天发生变化，未按发送键。")
            }
            guard AXUIElementSetAttributeValue(filledSnapshot.input, "AXFocused" as CFString, kCFBooleanTrue) == .success else {
                throw RetryLater(message: "填写后微信输入焦点暂未就绪，稍后重新核对。")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            let ready = try snapshot()
            try requireBackground(stillActive)
            guard ready.pid == expected.pid, eligible(ready), ready.name == expected.name, ready.rows == expected.rows, ready.draft == text else {
                throw RetryLater(message: "发送前界面有变化，重新核对后继续。")
            }
            // Deliver to WeChat's process; never activate it or send global input.
            down.postToPid(expected.pid); up.postToPid(expected.pid); posted = true
            for _ in 0..<12 {
                try await Task.sleep(nanoseconds: 250_000_000)
                let after = try snapshot()
                guard after.name == expected.name else { throw SendUncertain(message: "发送后聊天被切换，暂停这位好友，请核对实际发送结果。") }
                if after.draft.isEmpty, let receipt = confirmedReply(previous: expected.rows, current: after.rows, contact: expected.name, text: text) {
                    return receipt
                }
            }
            throw SendUncertain(message: "未确认后台发送结果，已暂停这位好友，不重复发送；请检查微信输入框。")
        } catch {
            if posted { throw SendUncertain(message: error is CancellationError ? "发送后核验被取消，请核对微信。" : error.localizedDescription) }
            if filled {
                // Remove only our exact, unsubmitted draft while WeChat remains
                // in the background. Never edit a draft the user has changed.
                if !isWeChatFrontmost(), let now = try? snapshot(), now.name == expected.name,
                   now.rows == expected.rows, now.draft == text,
                   AXUIElementSetAttributeValue(now.input, "AXValue" as CFString, "" as CFString) == .success {
                    throw error
                }
                throw SendUncertain(message: "发送已让行，微信可能保留了助手草稿；已暂停这位好友，请检查。")
            }
            throw error
        }
    }
}

enum SecretStore {
    static let service = "local.wechat.practice-assistant"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "deepseek",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "deepseek"]
        if key.isEmpty { SecItemDelete(query as CFDictionary); return }
        let update = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(key.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AssistantError(message: "无法将密钥保存到钥匙串。") }
        } else if result != errSecSuccess { throw AssistantError(message: "无法更新钥匙串中的密钥。") }
    }
}
