import Foundation
import Testing
@testable import LiveSliceUI

struct SessionTypesTests {
    private enum Plain: Error { case somethingSpecific }
    private struct Spoken: LocalizedError {
        var errorDescription: String? { "说人话的错误" }
    }

    @Test func localizedErrorsShowTheirOwnDescription() {
        #expect(ErrorText.describe(Spoken()) == "说人话的错误")
    }

    @Test func plainErrorsShowTheTypedCaseNotFoundationBoilerplate() {
        let text = ErrorText.describe(Plain.somethingSpecific)
        #expect(text.contains("somethingSpecific"))
        #expect(!text.contains("couldn’t be completed"))
    }

    @Test func nsErrorsKeepBothTheDomainCodeAndTheMessage() {
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11841, userInfo: [NSLocalizedDescriptionKey: "Invalid video composition"])
        let text = ErrorText.describe(error)
        #expect(text.contains("-11841"))
        #expect(text.contains("Invalid video composition"))
    }
}
