import XCTest
@testable import OpusCore

final class MarkdownSyntaxTests: XCTestCase {
    func testIncompleteAndIndentedFencesRemainCode() {
        for source in ["```swift\nlet n = 1", "  ~~~python\nvalue = 2\n  ~~~\n"] {
            let block = JournalCode.blocks(in: source).first
            XCTAssertNotNil(block)
            XCTAssertFalse(CodeHighlight.tokens(in: (source as NSString).substring(with: block!.innerRange), language: block!.language).isEmpty)
        }
    }
    func testMathIgnoresEscapesAndCode() {
        XCTAssertEqual(JournalMath.spans(in: #"cost \$5 and $x+1$"#).map(\.latex), ["x+1"])
        XCTAssertTrue(JournalMath.spans(in: "~~~tex\n$x$\n~~~").isEmpty)
        XCTAssertTrue(JournalMath.spans(in: "```tex\n$x$").isEmpty)
    }
    func testSQLAndSingleQuotedStringsHighlight() {
        let tokens = CodeHighlight.tokens(in: "SELECT 'hello' FROM things", language: "sql")
        XCTAssertEqual(tokens.filter { $0.1 == .keyword }.count, 2)
        XCTAssertEqual(CodeHighlight.tokens(in: "const s = 'hello'", language: "js").filter { $0.1 == .string }.count, 1)
    }
}
