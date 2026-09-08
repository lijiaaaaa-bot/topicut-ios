import Foundation
import Testing
@testable import LiveSliceASR
import LiveSliceCore

struct CueSegmenterTests {
    private func token(_ text: String, _ start: Double, _ end: Double) -> TimedToken {
        TimedToken(text: text, start: start, end: end)
    }

    @Test func breaksAtSentencePunctuation() throws {
        let tokens = [token("今天", 0, 0.5), token("好。", 0.5, 1.0), token("明天", 1.1, 1.5), token("见", 1.5, 2.0)]
        let cues = try CueSegmenter.cues(from: tokens)
        #expect(cues.map(\.text) == ["今天好。", "明天见"])
        #expect(cues.map(\.start) == [0, 1.1])
        #expect(cues.map(\.end) == [1.0, 2.0])
        #expect(cues.map(\.index) == [1, 2])
    }

    @Test func breaksOnCharacterBudget() throws {
        let policy = CueSegmenterPolicy(maxCharacters: 4, maxDurationSec: 100, breakOnGapSec: 100, sentenceEnders: [])
        let tokens = [token("ab", 0, 1), token("cd", 1, 2), token("e", 2, 3)]
        let cues = try CueSegmenter.cues(from: tokens, policy: policy)
        #expect(cues.map(\.text) == ["abcd", "e"])
    }

    @Test func breaksOnDurationAndGap() throws {
        let policy = CueSegmenterPolicy(maxCharacters: 100, maxDurationSec: 3, breakOnGapSec: 1, sentenceEnders: [])
        let tokens = [token("a", 0, 1), token("b", 1, 2), token("c", 2, 3.5), token("d", 5, 6)]
        let cues = try CueSegmenter.cues(from: tokens, policy: policy)
        #expect(cues.map(\.text) == ["ab", "c", "d"])
    }

    @Test func dropsWhitespaceOnlyGroupsAndTrims() throws {
        let tokens = [token(" ", 0, 0.2), token("hi ", 0.2, 0.6)]
        let cues = try CueSegmenter.cues(from: tokens)
        #expect(cues.map(\.text) == ["hi"])
        #expect(cues[0].start == 0)
    }

    @Test func zeroDurationCueIsAnError() {
        #expect(throws: CueSegmenterError.nonPositiveCueDuration(text: "x", start: 1, end: 1)) {
            try CueSegmenter.cues(from: [token("x", 1, 1)])
        }
    }

    @Test func emptyInputYieldsNoCues() throws {
        #expect(try CueSegmenter.cues(from: []).isEmpty)
    }

    @Test func englishPolicyKeepsCommaInsideCueAndAllowsLongerLines() throws {
        let tokens = [
            token("Today,", 0, 0.5), token(" we are going to talk", 0.5, 1.3),
            token(" about artificial", 1.3, 2.2), token(" intelligence.", 2.2, 3.0),
        ]
        let chinese = try CueSegmenter.cues(from: tokens, policy: .chinese)
        let english = try CueSegmenter.cues(from: tokens, policy: .english)
        #expect(chinese.first?.text == "Today,")
        #expect(english.count < chinese.count)
        #expect(english.first?.text.hasPrefix("Today,") == true)
        #expect(CueSegmenterPolicy.forLocale(Locale(identifier: "en_US")) == .english)
        #expect(CueSegmenterPolicy.forLocale(Locale(identifier: "zh_CN")) == .chinese)
    }
}
