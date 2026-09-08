import Testing
@testable import LiveSliceCore

struct SRTWriterTests {
    @Test func roundTripsThroughParser() throws {
        let cues = try SRTParser.parse(TestSupport.sampleSRT)
        let text = try SRTWriter.serialize(cues)
        let reparsed = try SRTParser.parse(text)
        #expect(reparsed == cues)
        #expect(text.hasPrefix("1\n00:00:01,000 --> 00:00:04,500\n"))
    }

    @Test func reordersAndReindexes() throws {
        let cues = [SRTCue(index: 9, start: 10, end: 12, text: "second"), SRTCue(index: 3, start: 1, end: 3, text: "first")]
        let text = try SRTWriter.serialize(cues)
        #expect(text == "1\n00:00:01,000 --> 00:00:03,000\nfirst\n\n2\n00:00:10,000 --> 00:00:12,000\nsecond\n")
    }

    @Test func emptyInputIsEmptyString() throws {
        #expect(try SRTWriter.serialize([]) == "")
    }

    @Test func rejectsNonPositiveDurationAndEmptyText() {
        #expect(throws: SRTWriterError.nonPositiveDuration(index: 1, start: 2, end: 2)) {
            try SRTWriter.serialize([SRTCue(index: 1, start: 2, end: 2, text: "x")])
        }
        #expect(throws: SRTWriterError.emptyText(index: 1)) {
            try SRTWriter.serialize([SRTCue(index: 1, start: 1, end: 2, text: "  \n")])
        }
    }
}
