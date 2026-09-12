import Testing
@testable import LiveSliceUI
import LiveSliceRender

struct LookDescribeParserTests {
    @Test func parsesClosedJSON() throws {
        let text = """
        {"framing":"phonePortrait","style":"highlightWord","bandY":0.25,"fontScale":1.2,"textHex":"FFFFFF","accentHex":"FFD60A"}
        """
        let (style, framing, tune) = try LookDescribeParser.parse(text)
        #expect(style == .highlightWord)
        #expect(framing == .phonePortrait)
        #expect(abs(tune.bandY - 0.25) < 0.001)
        #expect(abs(tune.fontScale - 1.2) < 0.001)
    }

    @Test func rejectsUnknownFraming() {
        let text = #"{"framing":"cinema","style":"clean","bandY":0.2,"fontScale":1,"textHex":"FFFFFF","accentHex":"FFD60A"}"#
        #expect(throws: LookDescribeError.unknownFraming("cinema")) {
            try LookDescribeParser.parse(text)
        }
    }
}
