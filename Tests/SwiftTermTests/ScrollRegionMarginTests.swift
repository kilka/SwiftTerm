import Foundation
import Testing

@testable import SwiftTerm

/// Scrolling inside a DECSTBM region must move whole rows on both buffers, also after a resize: the alternate
/// buffer used to start with `marginRight == 0`, so CSI T (SD) moved one column and left the rest
/// (htop scrolling up drew over itself), and a resize never widened the margins.
final class ScrollRegionMarginTests {
    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private let delegate = Delegate()

    /// Ten rows "row0"..."row9" (on the alternate buffer when `alt`), then `sequence`; the rows, "_" for blank.
    private func rows(alt: Bool, resizeTo cols: Int? = nil, _ sequence: String) -> String {
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 20, rows: 10))
        func feed(_ s: String) { terminal.feed(byteArray: Array(s.utf8)) }
        if alt { feed("\u{1b}[?1049h") }
        if let cols { terminal.resize(cols: cols, rows: 10) }
        for row in 0..<10 { feed("\u{1b}[\(row + 1);1Hrow\(row)" + (cols != nil ? String(repeating: "x", count: 30) + "W" : "")) }
        feed(sequence)
        return (0..<10).map { row in
            let text = terminal.getLine(row: row)!.translateToString(trimRight: true)
            return text.isEmpty ? "_" : String(text.dropFirst(3).prefix(1)) + (cols != nil && text.hasSuffix("W") ? "W" : "")
        }.joined(separator: " ")
    }

    private static let down = "0 1 _ _ 2 3 4 5 8 9"
    private static let up = "0 1 4 5 6 7 _ _ 8 9"

    @Test(arguments: [false, true])
    func scrollDownInRegionMovesWholeRows(alt: Bool) {
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[2T\u{1b}[r") == Self.down)
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[3;1H\u{1b}M\u{1b}M\u{1b}[r") == Self.down)
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[3;1H\u{1b}[2L\u{1b}[r") == Self.down)
        #expect(rows(alt: alt, "\u{1b}[2T") == "_ _ 0 1 2 3 4 5 6 7")
    }

    @Test(arguments: [false, true])
    func scrollUpInRegionMovesWholeRows(alt: Bool) {
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[2S\u{1b}[r") == Self.up)
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[8;1H\n\n\u{1b}[r") == Self.up)
        #expect(rows(alt: alt, "\u{1b}[3;8r\u{1b}[3;1H\u{1b}[2M\u{1b}[r") == Self.up)
    }

    /// After the terminal grows wider, a scroll still carries the columns it gained (the "W" at column 31).
    @Test(arguments: [false, true])
    func scrollAfterWideningCarriesNewColumns(alt: Bool) {
        let down = "0W 1W _ _ 2W 3W 4W 5W 8W 9W"
        let up = "0W 1W 4W 5W 6W 7W _ _ 8W 9W"
        #expect(rows(alt: alt, resizeTo: 40, "\u{1b}[3;8r\u{1b}[2T\u{1b}[r") == down)
        #expect(rows(alt: alt, resizeTo: 40, "\u{1b}[3;8r\u{1b}[2S\u{1b}[r") == up)
        #expect(rows(alt: alt, resizeTo: 40, "\u{1b}[3;8r\u{1b}[3;1H\u{1b}[2L\u{1b}[r") == down)
        #expect(rows(alt: alt, resizeTo: 40, "\u{1b}[3;8r\u{1b}[3;1H\u{1b}[2M\u{1b}[r") == up)
    }
}
