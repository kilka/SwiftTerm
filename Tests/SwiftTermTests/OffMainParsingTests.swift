import Foundation
import Testing
@testable import SwiftTerm

/// Terminals fed on different threads at once, as one built off the main thread for
/// `TerminalView.adoptTerminal(_:)` while the visible one keeps receiving output.
final class OffMainParsingTests {
    private final class Muted: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    @Test func tinyAtomsFromTwoThreadsGetDistinctCodesAndKeepTheirTargets() {
        let perThread = 2_000
        var codes: [[(UInt16, String)]] = [[], []]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { thread in
            var mine: [(UInt16, String)] = []
            for i in 0..<perThread {
                let value = "t\(thread)-\(i)"
                if let atom = TinyAtom.lookup(value: value) { mine.append((atom.code, value)) }
            }
            lock.lock(); codes[thread] = mine; lock.unlock()
        }
        let all = codes.flatMap { $0 }
        #expect(all.count == 2 * perThread)
        #expect(Set(all.map(\.0)).count == all.count, "no two values share a code")
        for (code, value) in all {
            #expect(TinyAtom.map[code] as? String == value)
            TinyAtom.release(code: code)
        }
    }

    @Test func osc8LinksFedOnTwoThreadsAtOnceKeepTheirOwnUrls() {
        let links = 1_500
        let terminals = (0..<2).map { _ in Terminal(delegate: Muted(), options: TerminalOptions(cols: 80, rows: 25, scrollback: 5_000)) }
        DispatchQueue.concurrentPerform(iterations: 2) { t in
            for i in 0..<links {
                terminals[t].feed(text: "\u{1b}]8;;https://t\(t).example/\(i)\u{1b}\\link\u{1b}]8;;\u{1b}\\\r\n")
            }
        }
        for (t, terminal) in terminals.enumerated() {
            // The last visible link of each terminal still points at its own URL.
            let row = terminal.buffer.y - 1 + terminal.buffer.yBase
            let payload = terminal.buffer.lines[row][0].getPayload()
            #expect((payload as? String)?.hasSuffix("https://t\(t).example/\(links - 1)") == true, "terminal \(t): \(String(describing: payload))")
        }
    }

    @Test func disabledSynchronizedOutputNeitherSnapshotsNorDefers() {
        let terminal = Terminal(delegate: Muted(), options: TerminalOptions(cols: 40, rows: 10))
        terminal.synchronizedOutputEnabled = false
        terminal.feed(text: "before\u{1b}[?2026h after")
        #expect(terminal.displayBuffer === terminal.buffer, "no snapshot: the display is the live buffer")
        terminal.synchronizedOutputEnabled = true
        terminal.feed(text: "\u{1b}[?2026l\u{1b}[?2026h")
        #expect(terminal.displayBuffer !== terminal.buffer, "enabled again, a frame is deferred")
    }
}
