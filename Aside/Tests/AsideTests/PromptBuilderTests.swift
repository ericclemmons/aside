import XCTest
@testable import AsideCore

final class PromptBuilderTests: XCTestCase {

    func testTranscriptionOnly() {
        let result = PromptBuilder.buildPrompt(transcription: "fix this bug", context: nil)
        XCTAssertEqual(result, "fix this bug")
    }

    func testWithSelectedText() {
        let ctx = ActiveContext(appName: "Code", windowTitle: "main.swift", selectedText: "let x = 1")
        let result = PromptBuilder.buildPrompt(transcription: "fix this", context: ctx)
        XCTAssertTrue(result.hasPrefix("> let x = 1"))
        XCTAssertTrue(result.hasSuffix("fix this"))
        XCTAssertTrue(result.contains("\n\n"))
    }

    func testWithURL() {
        let ctx = ActiveContext(appName: "Safari", windowTitle: "Google", url: "https://google.com")
        let result = PromptBuilder.buildPrompt(transcription: "summarize", context: ctx)
        XCTAssertTrue(result.contains("> - https://google.com"))
        XCTAssertTrue(result.hasSuffix("summarize"))
    }

    func testWithSelectedTextAndURL() {
        let ctx = ActiveContext(appName: "Safari", windowTitle: "Page", url: "https://example.com", selectedText: "some text")
        let result = PromptBuilder.buildPrompt(transcription: "explain", context: ctx)
        XCTAssertTrue(result.contains("> some text"))
        XCTAssertTrue(result.contains("> - https://example.com"))
        XCTAssertTrue(result.hasSuffix("explain"))
    }

    func testLongSelectedTextTruncated() {
        let longText = String(repeating: "a", count: 600)
        let ctx = ActiveContext(appName: "Code", windowTitle: "test", selectedText: longText)
        let result = PromptBuilder.buildPrompt(transcription: "fix", context: ctx)
        XCTAssertTrue(result.contains("..."))
        // Should have truncated to 500 + "..."
        let firstLine = result.components(separatedBy: "\n").first!
        XCTAssertTrue(firstLine.count <= 510) // "> " prefix + 500 + "..."
    }

    func testEmptyContextFieldsIgnored() {
        let ctx = ActiveContext(appName: "Code", windowTitle: "test", url: "", selectedText: "")
        let result = PromptBuilder.buildPrompt(transcription: "do something", context: ctx)
        XCTAssertEqual(result, "do something")
    }
}
