import Cocoa
import ApplicationServices

struct ChatCandidate {
    let name: String
    let signature: String
    let unread: Int
}

func unreadCount(_ label: String) -> Int {
    for pattern in ["(\\d+) unread message", "(\\d+)条未读", "(\\d+) 条未读"] {
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
           let range = Range(match.range(at: 1), in: label) { return Int(label[range]) ?? 0 }
    }
    return 0
}

func newUnreadCount(old: ChatCandidate?, new: ChatCandidate) -> Int {
    guard new.unread > 0, old?.signature != new.signature else { return 0 }
    guard let old else { return new.unread }
    return min(new.unread, max(1, new.unread - old.unread))
}

enum FirstScreenRowVisibility: Equatable {
    case above, visible, below, outside
}

func firstScreenRowVisibility(frame: CGRect, viewport: CGRect) throws -> FirstScreenRowVisibility {
    for rect in [frame, viewport] {
        guard rect.size.width > 0, rect.size.height > 0,
              [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy({ $0.isFinite }) else {
            throw RetryLater(message: "暂时无法核对第一屏可见范围，未读取离屏内容。")
        }
    }
    if frame.maxY <= viewport.minY { return .above }
    if frame.minY >= viewport.maxY { return .below }
    if frame.maxX <= viewport.minX || frame.minX >= viewport.maxX { return .outside }
    return .visible
}

// Align only when the list has left its first screen. Injected operations keep
// this rule testable without reading or operating a real WeChat window.
@MainActor func ensureFirstScreen(
    readPosition: () throws -> Double?,
    setTop: () throws -> Void,
    requireSafe: () throws -> Void,
    waitForLayout: () async throws -> Void
) async throws {
    let tolerance = 0.001
    try requireSafe()
    guard let position = try readPosition(), position.isFinite, (0...1).contains(position) else {
        throw RetryLater(message: "暂时无法核对聊天列表是否在第一屏，稍后再试。")
    }
    try requireSafe()
    guard position > tolerance else { return }
    try setTop()
    try requireSafe()
    try await waitForLayout()
    try requireSafe()
    guard let aligned = try readPosition(), aligned.isFinite, (0...tolerance).contains(aligned) else {
        throw RetryLater(message: "微信聊天列表尚未回到第一屏，暂缓处理。")
    }
}

extension WeChatReader {
    func mainWindow() throws -> (AXUIElement, pid_t) {
        guard AXIsProcessTrusted() else { throw AssistantError(message: "请在系统设置 → 隐私与安全性 → 辅助功能中开启本应用。") }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else { throw AssistantError(message: "请先打开并登录 Mac 微信。") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        let windows = attribute(root, "AXWindows") as? [AXUIElement] ?? []
        guard let window = windows.first(where: { window in
            controls(window).contains { ["AXTable", "AXList"].contains(string($0, "AXRole")) &&
                ["Chats", "聊天"].contains(label($0).components(separatedBy: " (").first ?? "") }
        }) else {
            let tables = windows.flatMap { controls($0).filter { ["AXTable", "AXList"].contains(string($0, "AXRole")) }.map { label($0) } }
            throw AssistantError(message: "未识别微信主聊天列表（窗口\(windows.count)，列表：\(tables.prefix(6).joined(separator: " / "))）。请回到微信主窗口。")
        }
        return (window, app.processIdentifier)
    }
    func chatTable(_ window: AXUIElement) throws -> AXUIElement {
        guard let table = controls(window).first(where: {
            ["AXTable", "AXList"].contains(string($0, "AXRole")) &&
            ["Chats", "聊天"].contains(label($0).components(separatedBy: " (").first ?? "")
        }) else { throw AssistantError(message: "无法识别微信聊天列表。") }
        return table
    }
    func elementFrame(_ element: AXUIElement) throws -> CGRect {
        guard let pointValue = attribute(element, "AXPosition"), CFGetTypeID(pointValue) == AXValueGetTypeID(),
              let sizeValue = attribute(element, "AXSize"), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw RetryLater(message: "暂时无法核对会话的可见位置，未读取离屏内容。")
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pointValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            throw RetryLater(message: "微信暂未提供可核对的会话位置，未读取离屏内容。")
        }
        let frame = CGRect(origin: point, size: size)
        _ = try firstScreenRowVisibility(frame: frame, viewport: frame)
        return frame
    }
    // Older WeChat builds may not expose visible-row attributes. Fetch only a
    // bounded prefix of child references, then inspect row geometry. Names and
    // message previews are read only after a row intersects the first viewport.
    func boundedFirstScreenRows(_ table: AXUIElement) throws -> [AXUIElement] {
        guard let parentValue = attribute(table, "AXParent"), CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            throw RetryLater(message: "暂时无法核对聊天列表第一屏的范围。")
        }
        let parent = parentValue as! AXUIElement
        let viewport = try elementFrame(table).intersection(elementFrame(parent))
        _ = try firstScreenRowVisibility(frame: viewport, viewport: viewport)
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(table, "AXChildren" as CFString, 0, 128, &values) == .success,
              let references = values as? [AXUIElement] else {
            throw RetryLater(message: "微信暂未提供第一屏可见会话，未遍历完整列表。")
        }
        if references.isEmpty { return [] }
        var result: [AXUIElement] = []
        var previousY: CGFloat?
        var lastBottom: CGFloat?
        for row in references {
            guard string(row, "AXRole") == "AXRow" else { continue }
            let frame = try elementFrame(row)
            if let previousY, frame.minY + 0.5 < previousY {
                throw RetryLater(message: "聊天列表布局有变化，稍后重新核对第一屏。")
            }
            previousY = frame.minY
            lastBottom = frame.maxY
            switch try firstScreenRowVisibility(frame: frame, viewport: viewport) {
            case .below:
                guard !result.isEmpty else { throw RetryLater(message: "暂时无法核对第一屏的会话布局，稍后再试。") }
                return result
            case .visible: result.append(row)
            case .above, .outside: continue
            }
        }
        guard !result.isEmpty,
              references.count < 128 || (lastBottom ?? 0) >= viewport.maxY else {
            throw RetryLater(message: "暂时无法完整核对第一屏可见会话，未继续读取离屏内容。")
        }
        return result
    }
    func firstScreenRows(_ table: AXUIElement) throws -> [AXUIElement] {
        if let rows = attribute(table, "AXVisibleRows") as? [AXUIElement] { return rows }
        if let rows = attribute(table, "AXVisibleChildren") as? [AXUIElement] { return rows }
        return try boundedFirstScreenRows(table)
    }
    func visibleCandidates(_ table: AXUIElement) throws -> [(ChatCandidate, AXUIElement)] {
        try firstScreenRows(table).compactMap { row in
            guard let cell = firstDescendant(row, depth: 4, matching: { string($0, "AXIdentifier").hasPrefix("MMChatsTableCellView") }) else { return nil }
            let label = firstString(cell, ["AXDescription", "AXTitle", "AXValue"])
            let name = String(label.prefix { $0 != "," }).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !["Official Accounts", "公众号", "File Transfer", "文件传输助手", "WeChat Team", "微信团队"].contains(name) else { return nil }
            return (ChatCandidate(name: name, signature: label, unread: unreadCount(label)), row)
        }
    }
    @MainActor func firstScreenTable(valid: () -> Bool) async throws -> AXUIElement {
        try requireBackground(valid)
        let (window, _) = try mainWindow()
        let table = try chatTable(window)
        guard let parentValue = attribute(table, "AXParent"), CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            throw RetryLater(message: "暂时无法核对聊天列表位置，未读取离屏内容。")
        }
        let parent = parentValue as! AXUIElement
        let scrollbar: AXUIElement
        if let value = attribute(parent, "AXVerticalScrollBar"), CFGetTypeID(value) == AXUIElementGetTypeID() {
            scrollbar = value as! AXUIElement
        } else {
            let bars = children(parent).filter { string($0, "AXRole") == "AXScrollBar" }
            let vertical = bars.filter { string($0, "AXOrientation") == "AXVerticalOrientation" }
            if vertical.count == 1 { scrollbar = vertical[0] }
            else if bars.count == 1, string(bars[0], "AXOrientation").isEmpty { scrollbar = bars[0] }
            else {
                throw RetryLater(message: "暂时无法确认聊天列表第一屏，请把微信聊天列表留在顶部。")
            }
        }
        try await ensureFirstScreen(
            readPosition: { (self.attribute(scrollbar, "AXValue") as? NSNumber)?.doubleValue },
            setTop: {
                try self.requireBackground(valid)
                guard AXUIElementSetAttributeValue(scrollbar, "AXValue" as CFString, NSNumber(value: 0)) == .success else {
                    throw RetryLater(message: "微信暂未接受回到聊天列表第一屏，稍后再试。")
                }
            },
            requireSafe: { try self.requireBackground(valid) },
            waitForLayout: { try await Task.sleep(nanoseconds: 70_000_000) }
        )
        try requireBackground(valid)
        return table
    }
    @MainActor func scanChats(valid: () -> Bool) async throws -> [ChatCandidate] {
        let table = try await firstScreenTable(valid: valid)
        let found = try visibleCandidates(table).map(\.0)
        try requireBackground(valid)
        // Even identically-labelled rows are ambiguous and remain excluded.
        let counts = Dictionary(grouping: found, by: \.name).mapValues(\.count)
        return found.filter { counts[$0.name] == 1 }
    }
    func isSettable(_ element: AXUIElement, _ key: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, key as CFString, &result) == .success && result.boolValue
    }
    func actions(_ element: AXUIElement) -> [String] {
        var result: CFArray?
        guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }
        return result as? [String] ?? []
    }
    @MainActor func openChat(name: String, valid: () -> Bool) async throws -> Snapshot {
        try requireBackground(valid)
        if let current = try? snapshot(), current.name == name {
            try requireBackground(valid)
            return current
        }
        let table = try await firstScreenTable(valid: valid)
        let matches = try visibleCandidates(table).filter { $0.0.name == name }
        try requireBackground(valid)
        guard matches.count <= 1 else { throw RetryLater(message: "第一屏有重复的好友名称，未打开。") }
        guard let (_, row) = matches.first else {
            throw RetryLater(message: "目标好友不在聊天列表第一屏，稍后重新检查。")
        }
        var attempts: [() -> AXError] = []
        if isSettable(table, "AXSelectedRows") {
            attempts.append { AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, [row] as CFArray) }
        }
        for element in walk(row, depth: 3) {
            if isSettable(element, "AXSelected") { attempts.append { AXUIElementSetAttributeValue(element, "AXSelected" as CFString, kCFBooleanTrue) } }
            if actions(element).contains("AXPress") { attempts.append { AXUIElementPerformAction(element, "AXPress" as CFString) } }
        }
        for attempt in attempts {
            try requireBackground(valid)
            guard attempt() == .success else { continue }
            try requireBackground(valid)
            try await Task.sleep(nanoseconds: 200_000_000)
            try requireBackground(valid)
            if let result = try? snapshot(), result.name == name {
                try requireBackground(valid)
                return result
            }
        }
        throw RetryLater(message: "这版微信未接受第一屏内的后台切换。助手仍保持运行，稍后重新检查。")
    }
}
