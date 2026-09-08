import Foundation
import Testing
@testable import LiveSliceASR

struct ASRLocalePreferenceTests {
    @Test func parsesAutoAndFixedIdentifiers() {
        #expect(ASRLocalePreference(identifier: "auto") == .automatic)
        #expect(ASRLocalePreference(identifier: "en_US") == .fixed(Locale(identifier: "en_US")))
        #expect(ASRLocalePreference.automatic.identifier == "auto")
        #expect(ASRLocalePreference.fixed(Locale(identifier: "zh_CN")).identifier == "zh_CN")
    }
}
