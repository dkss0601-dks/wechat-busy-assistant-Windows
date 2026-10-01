import Foundation

@MainActor func firstScreenAlignmentTests() async {
    let viewport = CGRect(x: 100, y: 100, width: 200, height: 300)
    let visibilityCases: [(CGRect, FirstScreenRowVisibility)] = [
        (CGRect(x: 100, y: 100, width: 200, height: 30), .visible),
        (CGRect(x: 90, y: 90, width: 20, height: 20), .visible),
        (CGRect(x: 100, y: 390, width: 200, height: 20), .visible),
        (CGRect(x: 100, y: 80, width: 200, height: 20), .above),
        (CGRect(x: 100, y: 400, width: 200, height: 30), .below),
        (CGRect(x: 300, y: 150, width: 20, height: 30), .outside),
        (CGRect(x: 50, y: 150, width: 30, height: 30), .outside)
    ]
    for (frame, expected) in visibilityCases {
        precondition(try! firstScreenRowVisibility(frame: frame, viewport: viewport) == expected)
    }
    for frame in [CGRect.zero, CGRect(x: 100, y: 100, width: -1, height: 30), CGRect(x: Double.infinity, y: 100, width: 20, height: 30)] {
        do {
            _ = try firstScreenRowVisibility(frame: frame, viewport: viewport)
            preconditionFailure("Unknown row geometry must be deferred")
        } catch is RetryLater { }
        catch { preconditionFailure("Unexpected row geometry error") }
    }
    do {
        _ = try firstScreenRowVisibility(frame: visibilityCases[0].0, viewport: .zero)
        preconditionFailure("Unknown viewport geometry must be deferred")
    } catch is RetryLater { }
    catch { preconditionFailure("Unexpected viewport geometry error") }

    var reads = 0
    var writes: [Double] = []
    var waits = 0
    try! await ensureFirstScreen(readPosition: { reads += 1; return 0 },
        setTop: { writes.append(0) }, requireSafe: { }, waitForLayout: { waits += 1 })
    precondition(reads == 1 && writes.isEmpty && waits == 0)
    try! await ensureFirstScreen(readPosition: { 0.0005 },
        setTop: { writes.append(0) }, requireSafe: { }, waitForLayout: { waits += 1 })
    precondition(writes.isEmpty && waits == 0)

    var position = 0.6
    reads = 0
    try! await ensureFirstScreen(readPosition: { reads += 1; return position },
        setTop: { writes.append(0); position = 0 }, requireSafe: { }, waitForLayout: { waits += 1 })
    precondition(reads == 2 && writes == [0] && waits == 1 && position == 0)
    // Returning from alignment never restores the old lower list position.
    precondition(!writes.contains(0.6))

    for invalid: Double? in [nil, .nan, .infinity, -0.01, 1.01] {
        var mutations = 0
        var layoutWaits = 0
        do {
            try await ensureFirstScreen(readPosition: { invalid },
                setTop: { mutations += 1 }, requireSafe: { }, waitForLayout: { layoutWaits += 1 })
            preconditionFailure("Invalid list position must remain unscanned")
        } catch is RetryLater { }
        catch { preconditionFailure("Unexpected error for invalid list position") }
        precondition(mutations == 0 && layoutWaits == 0)
    }

    // Accepting an AX write is insufficient: the layout must verify the top.
    var refusedWrites = 0
    var refusedWaits = 0
    do {
        try await ensureFirstScreen(readPosition: { 0.4 },
            setTop: { refusedWrites += 1 }, requireSafe: { }, waitForLayout: { refusedWaits += 1 })
        preconditionFailure("A list that did not reach the top must be deferred")
    } catch is RetryLater { }
    catch { preconditionFailure("Unexpected alignment verification error") }
    precondition(refusedWrites == 1 && refusedWaits == 1)

    // Losing user ownership during the initial position read prevents the write.
    var safe = true
    var cancelledWrites = 0
    do {
        try await ensureFirstScreen(readPosition: { safe = false; return 0.7 },
            setTop: { cancelledWrites += 1 },
            requireSafe: { if !safe { throw CancellationError() } }, waitForLayout: { })
        preconditionFailure("Ownership loss must cancel alignment")
    } catch is CancellationError { }
    catch { preconditionFailure("Unexpected ownership cancellation error") }
    precondition(cancelledWrites == 0)

    // Cancellation during layout wait prevents the verification read, and no
    // second or restorative mutation follows it.
    safe = true
    reads = 0
    cancelledWrites = 0
    do {
        try await ensureFirstScreen(readPosition: { reads += 1; return 0.7 },
            setTop: { cancelledWrites += 1 },
            requireSafe: { if !safe { throw CancellationError() } },
            waitForLayout: { safe = false })
        preconditionFailure("Ownership loss during layout must cancel alignment")
    } catch is CancellationError { }
    catch { preconditionFailure("Unexpected layout cancellation error") }
    precondition(reads == 1 && cancelledWrites == 1)

    var failedWaits = 0
    do {
        try await ensureFirstScreen(readPosition: { 0.3 },
            setTop: { throw RetryLater(message: "write refused") }, requireSafe: { },
            waitForLayout: { failedWaits += 1 })
        preconditionFailure("A rejected write must be propagated")
    } catch is RetryLater { }
    catch { preconditionFailure("Unexpected write failure error") }
    precondition(failedWaits == 0)
    print("PASS: viewport geometry excludes off-screen rows; first-screen alignment uses zero idle writes, one guarded reset and cancellation without restoration")
}
