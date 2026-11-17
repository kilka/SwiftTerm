import Foundation
import Testing

@testable import SwiftTerm

/// What a host that composes the screen from rows it drew before relies on: `getDisplayedLine` is the line a
/// view draws (the frozen one during synchronized output), and `hashDrawing` tells lines that draw the same
/// pixels from lines that do not.
final class DisplayedLineTests {
    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private let delegate = Delegate()

    private func terminal() -> Terminal {
        Terminal(delegate: delegate, options: TerminalOptions(cols: 20, rows: 5, scrollback: 0))
    }

    private func hash(_ terminal: Terminal, row: Int) -> Int {
        var hasher = Hasher()
        terminal.getDisplayedLine(row: row)!.hashDrawing(into: &hasher, cols: terminal.cols)
        return hasher.finalize()
    }

    /// Row 0 after writing `text` on a cleared screen.
    private func hashOf(_ text: String) -> Int {
        let t = terminal()
        t.feed(text: "\u{1b}[2J\u{1b}[H" + text)
        return hash(t, row: 0)
    }

    @Test func displayedLineIsTheFrozenOneDuringSynchronizedOutput() {
        let t = terminal()
        t.feed(text: "\u{1b}[2J\u{1b}[HOLD")
        t.feed(text: "\u{1b}[?2026h\u{1b}[2J\u{1b}[HNEW")
        #expect(t.getDisplayedLine(row: 0)!.translateToString(trimRight: true) == "OLD")
        #expect(t.getLine(row: 0)!.translateToString(trimRight: true) == "NEW")
        t.feed(text: "\u{1b}[?2026l")
        #expect(t.getDisplayedLine(row: 0)!.translateToString(trimRight: true) == "NEW")
        #expect(t.displayedTopRow == t.buffer.yDisp)
    }

    @Test func displayedLineIsNilOffScreen() {
        let t = terminal()
        #expect(t.getDisplayedLine(row: -1) == nil)
        #expect(t.getDisplayedLine(row: 5) == nil)
        #expect(t.getDisplayedLine(row: 4) != nil)
    }

    @Test func sameTextAndAttributesHashAlikeOnAnyRow() {
        let t = terminal()
        t.feed(text: "\u{1b}[2J\u{1b}[1;1H\u{1b}[31mred\u{1b}[0m text\u{1b}[3;1H\u{1b}[31mred\u{1b}[0m text")
        #expect(hash(t, row: 0) == hash(t, row: 2))
        #expect(hash(t, row: 0) != hash(t, row: 1))
    }

    @Test func whatChangesThePixelsChangesTheHash() {
        let plain = hashOf("cafe")
        #expect(hashOf("cafe") == plain)
        #expect(hashOf("caf\u{e9}") != plain)
        // A combining accent on the last letter: one cell holding a cluster.
        #expect(hashOf("cafe\u{301}") != plain)
        #expect(hashOf("\u{1b}[1mcafe") != plain)
        #expect(hashOf("\u{1b}[4mcafe") != plain)
        #expect(hashOf("\u{1b}[44mcafe") != plain)
        #expect(hashOf("\u{1b}]8;;https://example.com\u{7}cafe\u{1b}]8;;\u{7}") != plain)
        // Double-width line (DECDWL).
        #expect(hashOf("\u{1b}#6cafe") != plain)
    }
}
