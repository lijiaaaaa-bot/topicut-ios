import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

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

    @Test func replacingDocumentKeepsProvenance() throws {
        let document = try SessionFixtures.document()
        let trimmed = try EDLEdit.trim(
            try SessionFixtures.clip(), start: 5, end: 20, sourceStart: 1, sourceEnd: 22
        )
        let result = SessionResult(
            projectID: "p", sourceURL: URL(filePath: "/tmp/source.mov"), cues: SessionFixtures.cues,
            document: document, localeIdentifier: "zh_CN", slicedWith: "m|u"
        )
        let replaced = result.replacingDocument(document.replacingClips([trimmed]))
        #expect(replaced.projectID == "p")
        #expect(replaced.cues == SessionFixtures.cues)
        #expect(replaced.slicedWith == "m|u")
        #expect(replaced.document.clips.first?.startSec == 5)
    }

    @Test func nsErrorsKeepBothTheDomainCodeAndTheMessage() {
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11841, userInfo: [NSLocalizedDescriptionKey: "Invalid video composition"])
        let text = ErrorText.describe(error)
        #expect(text.contains("-11841"))
        #expect(text.contains("Invalid video composition"))
    }
}
