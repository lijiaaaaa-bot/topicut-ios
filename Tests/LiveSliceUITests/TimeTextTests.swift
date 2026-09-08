import Testing
@testable import LiveSliceUI

struct TimeTextTests {
    @Test func clockOmitsHoursUnderAnHour() {
        #expect(TimeText.clock(0) == "00:00")
        #expect(TimeText.clock(65.4) == "01:05")
        #expect(TimeText.clock(3599.6) == "1:00:00")
        #expect(TimeText.clock(3725) == "1:02:05")
    }

    @Test func durationSwitchesToMinutesAtSixty() {
        #expect(TimeText.duration(42.2) == "42 秒")
        #expect(TimeText.duration(60) == "1 分 0 秒")
        #expect(TimeText.duration(125) == "2 分 5 秒")
    }

    @Test func compactDropsSpaces() {
        #expect(TimeText.compact(42.2) == "42秒")
        #expect(TimeText.compact(60) == "1分")
        #expect(TimeText.compact(62) == "1分02秒")
        #expect(TimeText.compact(430) == "7分10秒")
    }
}
