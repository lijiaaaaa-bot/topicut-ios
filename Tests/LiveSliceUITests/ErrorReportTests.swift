import Foundation
import Testing
@testable import LiveSliceUI

struct ErrorReportTests {
    @Test func formatsNameVersionBuildAndMessage() {
        let text = ErrorReport.text(
            message: "speechBroke(\"no model\")",
            displayName: "Demo", version: "1.2.0", build: "29"
        )
        #expect(text == "Demo 1.2.0 (29)\nspeechBroke(\"no model\")")
    }

    @Test func omitsEmptyDisplayName() {
        let text = ErrorReport.text(
            message: "x", displayName: "", version: "1.0", build: "1"
        )
        #expect(text == "1.0 (1)\nx")
    }
}
