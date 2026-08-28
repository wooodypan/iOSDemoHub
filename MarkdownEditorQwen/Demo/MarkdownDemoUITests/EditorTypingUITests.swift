import XCTest

/// Golden-path check: typing markdown into the live editor must not crash, must
/// keep the typed text intact (debounced re-highlighting only touches attributes),
/// and mode switching must stay stable.
final class EditorTypingUITests: XCTestCase {

    func testTypingMarkdownAndSwitchingModes() {
        let app = XCUIApplication()
        app.launch()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "editor text view should appear")

        editor.tap()
        editor.typeText("\n\n# 标题")
        editor.typeText("\n**粗体**中文😀")

        // The debounced highlighter runs while typing; a crash or text corruption
        // fails the test here.
        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.contains("# 标题"), "typed heading should survive highlighting")
        XCTAssertTrue(value.contains("**粗体**中文😀"), "typed bold+emoji should survive highlighting")

        // Round-trip through preview and AST; both consume the current text.
        app.segmentedControls.buttons["预览"].tap()
        app.segmentedControls.buttons["AST"].tap()
        app.segmentedControls.buttons["编辑"].tap()

        XCTAssertTrue(editor.waitForExistence(timeout: 5), "editor should reappear")
        let valueAfterSwitch = editor.value as? String ?? ""
        XCTAssertTrue(valueAfterSwitch.contains("# 标题"), "text should survive mode switching")
    }
}
