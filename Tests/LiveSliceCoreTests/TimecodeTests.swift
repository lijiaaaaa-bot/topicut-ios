import Testing
@testable import LiveSliceCore

struct TimecodeTests {
    @Test func parsesDotAndCommaMilliseconds() throws {
        #expect(try Timecode.parse("01:02:03.004") == 3723.004)
        #expect(try Timecode.parse("00:00:00,500") == 0.5)
        #expect(try Timecode.parse(" 00:10:00.000 ") == 600)
    }

    @Test(arguments: ["1:02:03.004", "00:02:03", "00:60:00.000", "00:00:61.000", "aa:bb:cc.ddd", "", "00:00:00.1"])
    func rejectsMalformedTimestamps(_ raw: String) {
        #expect(throws: TimecodeError.invalidTimestamp(raw)) { try Timecode.parse(raw) }
    }

    @Test func formatsRoundTrip() throws {
        #expect(Timecode.format(3723.004) == "01:02:03.004")
        #expect(Timecode.format(0) == "00:00:00.000")
        #expect(Timecode.format(-5) == "00:00:00.000")
        #expect(Timecode.format(59.9996) == "00:01:00.000")
        let value = 12345.678
        #expect(try Timecode.parse(Timecode.format(value)) == value)
    }
}
