import Cocoa

// Basic message and routing rules; no real WeChat or API access.
func selfTest() {
    precondition(parseMessage("MeSaid:hello", contact: "Friend")?.mine == true)
    precondition(parseMessage("FriendSaid:hi", contact: "Friend")?.mine == false)
    precondition(parseMessage("OtherSaid:hi", contact: "Friend") == nil)
    precondition(parseMessage("Friend:Sent aVoice message", contact: "Friend") == nil)
    precondition(parseMessage("12:45", contact: "Friend") == nil)
    precondition(parseMessage("FriendSaid:", contact: "Friend") == nil)
    precondition(appendedRows(previous: ["a", "b"], current: ["a", "b", "b"]) == ["b"])
    precondition(appendedRows(previous: ["a", "b"], current: ["b", "c"]) == ["c"])
    precondition(appendedRows(previous: ["a", "b"], current: ["x", "y"]) == nil)
    precondition(appendedRows(previous: ["a", "b"], current: ["a", "b"]) == [])
    precondition(appendedRows(previous: [], current: ["old"]) == nil)
    precondition(unreadCount("Name,hi,12:00,12 unread message(s)") == 12)
    precondition(unreadCount("Name,hi,12:00") == 0)
    let old = ChatCandidate(name: "A", signature: "old", unread: 3)
    precondition(newUnreadCount(old: old, new: old) == 0)
    precondition(newUnreadCount(old: old, new: ChatCandidate(name: "A", signature: "new", unread: 4)) == 1)
    precondition(newUnreadCount(old: nil, new: ChatCandidate(name: "A", signature: "new", unread: 2)) == 2)
    var states = ["A": ContactState(), "B": ContactState()]
    states["A"]!.history.append(["role": "user", "content": "private A"])
    states["A"]!.rounds = 5
    precondition(states["B"]!.history.isEmpty && states["B"]!.rounds == 0)
    precondition(ActivityPreset.all.contains { $0.id == "custom" })
    precondition(backgroundOperationAllowed(wechatIsFrontmost: false, sessionIsActive: true))
    precondition(!backgroundOperationAllowed(wechatIsFrontmost: true, sessionIsActive: true))
    precondition(!backgroundOperationAllowed(wechatIsFrontmost: false, sessionIsActive: false))
    let manualBatch = [parseMessage("ASaid:before", contact: "A")!, parseMessage("MeSaid:mine", contact: "A")!, parseMessage("ASaid:after", contact: "A")!]
    precondition(textAfterLastManualReply(manualBatch) == "after")
    precondition(textAfterLastManualReply([manualBatch[0]]) == nil)
    let receipt = confirmedReply(previous: ["old"], current: ["old", "ASaid:new", "MeSaid:reply", "ASaid:later"], contact: "A", text: "reply")
    precondition(receipt?.rows == ["old", "ASaid:new", "MeSaid:reply"])
    precondition(receipt?.arrivedBeforeReply == ["new"])
    precondition(confirmedReply(previous: ["old"], current: ["old", "BSaid:reply"], contact: "A", text: "reply") == nil)
    precondition(confirmedReply(previous: ["old"], current: ["old", "ASaid:reply"], contact: "A", text: "reply") == nil)
    print("PASS: sender identity, history overlap, unread deltas, contact isolation, background yielding, manual handoff and concurrent-message send receipts")
}
