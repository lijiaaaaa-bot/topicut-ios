import Foundation
import Testing
@testable import LiveSliceCore

struct TimedTokenTests {
    @Test func roundTripsThroughJSONUnchanged() throws {
        let tokens = [TimedToken(text: "今天", start: 1.04, end: 1.52), TimedToken(text: "先看，", start: 1.52, end: 2.0)]
        let data = try JSONEncoder().encode(tokens)
        #expect(try JSONDecoder().decode([TimedToken].self, from: data) == tokens)
    }

    @Test func midpointIsStrictlyInsideTheRange() {
        let token = TimedToken(text: "a", start: 2, end: 3)
        #expect(token.midpoint == 2.5)
        #expect(token.midpoint > token.start && token.midpoint < token.end)
    }
}
