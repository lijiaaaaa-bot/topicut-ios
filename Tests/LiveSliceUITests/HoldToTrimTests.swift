import Testing
@testable import LiveSliceUI

struct HoldToTrimTests {
    @Test func holdOpensAfterItArms() {
        #expect(HoldToTrim.openAfter > HoldToTrim.armAfter)
        #expect(HoldToTrim.armAfter == 0.20)
        #expect(HoldToTrim.openAfter == 0.48)
    }

    @Test func copyIsTheQuietWorkbenchHint() {
        #expect(HoldToTrim.capsule == "裁剪")
        #expect(HoldToTrim.hint == "长按画面可裁剪")
        #expect(HoldToTrim.access == "裁切与合并")
    }
}
