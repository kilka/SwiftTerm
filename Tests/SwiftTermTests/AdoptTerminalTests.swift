//
//  AdoptTerminalTests.swift
//
//  `TerminalView.adoptTerminal(_:)`: a view displays a terminal that was
//  built and fed elsewhere, in place of its own emulator.
//

#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

/// A delegate for terminals built away from any view.
private final class HeadlessDelegate: TerminalDelegate {
    var sent: [UInt8] = []
    func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
}

/// Records what the view forwards to its host.
private final class RecordingViewDelegate: TerminalViewDelegate {
    var sent: [UInt8] = []
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
final class AdoptTerminalTests {
    private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(origin: .zero, size: .init(width: 400, height: 300)))
    }

    private func lineText(_ terminal: Terminal, _ row: Int) -> String {
        terminal.buffer.lines[row].translateToString(trimRight: true)
    }

    @Test func adoptedTerminalKeepsItsContentCursorAndModes() {
        let view = makeView()
        view.feed(text: "preview screen")
        let (cols, rows) = view.getTerminal().getDims()
        let headless = HeadlessDelegate()
        let built = Terminal(delegate: headless, options: TerminalOptions(cols: cols, rows: rows))
        built.feed(text: "line one\r\nline two\u{1b}[?2004h")

        view.adoptTerminal(built)

        #expect(view.getTerminal() === built)
        #expect(lineText(built, built.buffer.yBase) == "line one")
        #expect(lineText(built, built.buffer.yBase + 1) == "line two")
        #expect(built.buffer.x == 8 && built.buffer.y == 1)
        #expect(built.bracketedPasteMode)
        #expect(built.cols == cols && built.rows == rows)
    }

    @Test func viewBecomesTheDelegateAndTheOldTerminalIsDetached() {
        let view = makeView()
        let host = RecordingViewDelegate()
        view.terminalDelegate = host
        let old = view.getTerminal()
        let headless = HeadlessDelegate()
        let built = Terminal(delegate: headless, options: TerminalOptions(cols: old.cols, rows: old.rows))

        view.adoptTerminal(built)

        #expect(built.tdel === view)
        #expect(old.tdel == nil)
        // A query the adopted terminal answers goes to the view's host, not the headless delegate.
        view.feed(text: "\u{1b}[6n")
        #expect(!host.sent.isEmpty)
        #expect(headless.sent.isEmpty)
    }

    @Test func scrollbackLongerThanTheDefaultSurvivesAdoption() {
        let view = makeView()
        let (cols, rows) = view.getTerminal().getDims()
        let headless = HeadlessDelegate()
        let built = Terminal(delegate: headless, options: TerminalOptions(cols: cols, rows: rows, scrollback: 10_000))
        for i in 0..<2_000 { built.feed(text: "row \(i)\r\n") }

        view.adoptTerminal(built)

        let terminal = view.getTerminal()
        #expect(terminal.buffer.lines.count > 2_000)
        #expect(lineText(terminal, 0) == "row 0")
        // The view's scroller covers the adopted buffer.
        #expect(view.canScroll)
    }

    @Test func presentationIsCarriedOver() {
        let view = makeView()
        let palette = (0..<16).map { i in Color(red: UInt16(i * 1000), green: 0, blue: UInt16(65535 - i * 1000)) }
        view.installColors(palette)
        view.getTerminal().foregroundColor = Color(red: 100, green: 200, blue: 300)
        view.getTerminal().backgroundColor = Color(red: 400, green: 500, blue: 600)
        let old = view.getTerminal()
        let built = Terminal(delegate: HeadlessDelegate(), options: TerminalOptions(cols: old.cols, rows: old.rows))

        view.adoptTerminal(built)

        #expect(built.installedColors == palette)
        #expect(built.foregroundColor == old.foregroundColor)
        #expect(built.backgroundColor == old.backgroundColor)
    }

    @Test func selectionAndSearchFollowTheAdoptedTerminal() {
        let view = makeView()
        view.feed(text: "old text")
        view.selectAll()
        let old = view.getTerminal()
        let built = Terminal(delegate: HeadlessDelegate(), options: TerminalOptions(cols: old.cols, rows: old.rows))
        built.feed(text: "needle in the new terminal")

        view.adoptTerminal(built)

        #expect(!view.selection.active)
        #expect(view.selection.terminal === built)
        #expect(view.search.findNext(term: "needle") != nil)
        #expect(view.search.findNext(term: "old text") == nil)
    }

    @Test func adoptingTheCurrentTerminalIsANoOp() {
        let view = makeView()
        view.feed(text: "same")
        let terminal = view.getTerminal()
        view.adoptTerminal(terminal)
        #expect(view.getTerminal() === terminal)
        #expect(terminal.tdel === view)
    }
}
#endif
