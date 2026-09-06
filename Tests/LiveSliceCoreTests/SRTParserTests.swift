import Testing
@testable import LiveSliceCore

struct SRTParserTests {
    @Test func parsesMultilineCuesAndReindexes() throws {
        let cues = try SRTParser.parse(TestSupport.sampleSRT)
        #expect(cues.count == 5)
        #expect(cues[1].text == "这条海峡承担全球大约五分之一的海运原油，\n任何风吹草动都会直接传导到油价。")
        #expect(cues[1].start == 4.5)
        #expect(cues.map(\.index) == [1, 2, 3, 4, 5])
    }

    @Test func emptyInputYieldsNoCues() throws {
        #expect(try SRTParser.parse("").isEmpty)
        #expect(try SRTParser.parse("  \n\n \r\n").isEmpty)
    }

    @Test func sortsOutOfOrderCuesByStart() throws {
        let srt = """
        2
        00:00:10,000 --> 00:00:12,000
        second

        1
        00:00:01,000 --> 00:00:03,000
        first
        """
        let cues = try SRTParser.parse(srt)
        #expect(cues.map(\.text) == ["first", "second"])
        #expect(cues.map(\.index) == [1, 2])
    }

    @Test func acceptsBlocksWithoutIndexAndWithCRLF() throws {
        let cues = try SRTParser.parse("00:00:01.000 --> 00:00:02.000 X1:0\r\nhello\r\n")
        #expect(cues == [SRTCue(index: 1, start: 1, end: 2, text: "hello")])
    }

    @Test func rejectsInvalidTimestamp() {
        let srt = "1\n00:00:01,000 --> 00:00:0X,000\ntext"
        #expect(throws: SRTParseError.invalidTimestamp(blockNumber: 1, value: "00:00:0X,000")) {
            try SRTParser.parse(srt)
        }
    }

    @Test func rejectsMissingArrow() {
        let srt = "1\n00:00:01,000 - 00:00:02,000\ntext"
        #expect(throws: SRTParseError.invalidTimeLine(blockNumber: 1, line: "00:00:01,000 - 00:00:02,000")) {
            try SRTParser.parse(srt)
        }
    }

    @Test func rejectsNonPositiveDurationAndEmptyText() {
        #expect(throws: SRTParseError.nonPositiveDuration(blockNumber: 1, start: 2, end: 2)) {
            try SRTParser.parse("1\n00:00:02,000 --> 00:00:02,000\ntext")
        }
        #expect(throws: SRTParseError.emptyText(blockNumber: 1)) {
            try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000")
        }
        #expect(throws: SRTParseError.malformedBlock(blockNumber: 2)) {
            try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000\nok\n\njust-one-line")
        }
    }

    @Test func plainTranscriptUsesBracketedRanges() throws {
        let cues = try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,500\nhi")
        #expect(SRTParser.plainTranscript(cues) == "[00:00:01.000 -> 00:00:02.500] hi")
    }
}
