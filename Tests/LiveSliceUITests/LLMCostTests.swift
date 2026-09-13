import Foundation
import LLMKit
import Testing
@testable import LiveSliceUI
import LiveSliceCore

struct LLMCostTests {
    private func usage(model: String = "deepseek-v4-flash", prompt: Int, completion: Int, hit: Int? = nil) -> LLMUsage {
        LLMUsage(model: model, promptTokens: prompt, completionTokens: completion, totalTokens: prompt + completion, latencyMs: 1, promptCacheHitTokens: hit)
    }

    // Beijing Wednesday 2026-09-09 10:30 (peak) and 22:30 (off-peak), as UTC ISO strings.
    private let peakTime = "2026-09-09T02:30:00Z"
    private let offPeakTime = "2026-09-09T14:30:00Z"
    private let deepSeek = "deepseek-v4-flash|https://api.deepseek.com"

    @Test func offPeakFlashPriceIsInputPlusOutputPerMillion() throws {
        // 1,000,000 miss tokens × 1.5 + 1,000,000 output × 4.5 = 6.0 元
        let charge = try #require(LLMCost.estimate(usage: usage(prompt: 1_000_000, completion: 1_000_000), slicedWith: deepSeek, generatedAt: offPeakTime))
        #expect(charge.yuan == 6)
        #expect(!charge.peak)
    }

    @Test func peakDoublesAndCacheHitsAreBilledAtTheHitRate() throws {
        // 200k miss × 1.5 + 800k hit × 0.05 + 100k out × 4.5 = 0.3 + 0.04 + 0.45 = 0.79; peak ×2 = 1.58
        let charge = try #require(LLMCost.estimate(usage: usage(prompt: 1_000_000, completion: 100_000, hit: 800_000), slicedWith: deepSeek, generatedAt: peakTime))
        #expect(charge.yuan == Decimal(string: "1.58"))
        #expect(charge.peak)
    }

    @Test func realRunFromLiveCheckCostsAFewFen() throws {
        // live_check 2026-09-07 21:08 Beijing (Monday, off-peak): prompt 3454, completion 1681.
        let charge = try #require(LLMCost.estimate(usage: usage(prompt: 3454, completion: 1681), slicedWith: deepSeek, generatedAt: "2026-09-07T13:08:40Z"))
        #expect(LLMCost.text(charge) == "约 ¥0.01")
        #expect(!charge.peak)
    }

    @Test func proAndTheRetiredAliasHaveSheetsUnknownModelsDoNot() {
        #expect(LLMCost.estimate(usage: usage(model: "deepseek-v4-pro", prompt: 1_000_000, completion: 0), slicedWith: "deepseek-v4-pro|https://api.deepseek.com", generatedAt: offPeakTime)?.yuan == Decimal(string: "4.5"))
        #expect(LLMCost.estimate(usage: usage(model: "deepseek-chat", prompt: 1_000_000, completion: 0), slicedWith: "deepseek-chat|https://api.deepseek.com", generatedAt: offPeakTime)?.yuan == Decimal(string: "1.5"))
        #expect(LLMCost.estimate(usage: usage(model: "qwen-plus", prompt: 1000, completion: 10), slicedWith: "qwen-plus|https://dashscope.aliyuncs.com/compatible-mode/v1", generatedAt: offPeakTime) == nil)
    }

    @Test func otherEndpointsShowNoPriceEvenForADeepSeekModelName() {
        #expect(LLMCost.estimate(usage: usage(prompt: 1000, completion: 10), slicedWith: "deepseek-v4-flash|https://api.siliconflow.cn/v1", generatedAt: offPeakTime) == nil)
        #expect(LLMCost.estimate(usage: usage(prompt: 1000, completion: 10), slicedWith: "deepseek-v4-flash|not a url", generatedAt: offPeakTime) == nil)
    }

    @Test func preProvenanceRecordsCountAsTheDeepSeekDefault() {
        #expect(LLMCost.estimate(usage: usage(prompt: 1_000_000, completion: 0), slicedWith: nil, generatedAt: offPeakTime)?.yuan == Decimal(string: "1.5"))
    }

    @Test func unreadableTimestampMeansNoEstimate() {
        #expect(LLMCost.estimate(usage: usage(prompt: 1000, completion: 10), slicedWith: deepSeek, generatedAt: "yesterday") == nil)
    }

    @Test func peakWindowIsBeijingWeekdayMorningAndAfternoon() {
        let iso = ISO8601DateFormatter()
        func peak(_ s: String) -> Bool { LLMCost.isPeak(iso.date(from: s)!) }
        #expect(peak("2026-09-09T01:00:00Z"))   // Wed 09:00 Beijing
        #expect(peak("2026-09-09T03:59:00Z"))   // Wed 11:59
        #expect(!peak("2026-09-09T04:00:00Z"))  // Wed 12:00 lunch break
        #expect(!peak("2026-09-09T05:59:00Z"))  // Wed 13:59
        #expect(peak("2026-09-09T06:00:00Z"))   // Wed 14:00
        #expect(!peak("2026-09-09T10:00:00Z"))  // Wed 18:00
        #expect(!peak("2026-09-12T02:30:00Z"))  // Saturday 10:30
        #expect(!peak("2026-09-13T02:30:00Z"))  // Sunday 10:30
    }

    @Test func textFormatting() {
        #expect(LLMCost.text(LLMCharge(yuan: Decimal(string: "0.004")!, peak: false)) == "不到 ¥0.01")
        #expect(LLMCost.text(LLMCharge(yuan: Decimal(string: "0.5")!, peak: false)) == "约 ¥0.50")
        #expect(LLMCost.text(LLMCharge(yuan: Decimal(string: "1234.567")!, peak: true)) == "约 ¥1234.57")
        #expect(LLMCost.tokenText(usage(prompt: 5000, completion: 135)) == "5,135 token")
    }

    @Test func endpointURLStringTakesOnlyTheBaseURLSegment() {
        #expect(LLMCost.endpointURLString(from: "deepseek-v4-flash|https://api.deepseek.com") == "https://api.deepseek.com")
        #expect(
            LLMCost.endpointURLString(from: "deepseek-v4-flash|https://api.deepseek.com|more+punchy")
                == "https://api.deepseek.com"
        )
        #expect(LLMCost.endpointURLString(from: "deepseek-v4-flash| https://api.deepseek.com |fewer+roomy") == "https://api.deepseek.com")
        #expect(LLMCost.endpointURLString(from: "no-separator") == nil)
        #expect(LLMCost.endpointURLString(from: "model|") == nil)
    }

    @Test func slicedWithTasteSuffixStillEstimatesDeepSeek() throws {
        let key = PipelineReuse.sliceKey(
            model: "deepseek-v4-flash",
            baseURL: "https://api.deepseek.com",
            taste: SlicingTaste(topicDensity: .more, highlightSpan: .punchy)
        )
        #expect(key == "deepseek-v4-flash|https://api.deepseek.com|more+punchy")
        let charge = try #require(
            LLMCost.estimate(
                usage: usage(prompt: 3454, completion: 1681), slicedWith: key, generatedAt: "2026-09-07T13:08:40Z"
            )
        )
        #expect(LLMCost.text(charge) == "约 ¥0.01")
        #expect(
            LLMCost.usageLine(
                usage: usage(prompt: 3454, completion: 1681), slicedWith: key, generatedAt: "2026-09-07T13:08:40Z"
            ) == "5,135 token · 约 ¥0.01"
        )
    }

    @Test func fractionalSecondsTimestampStillEstimates() throws {
        let charge = try #require(
            LLMCost.estimate(
                usage: usage(prompt: 3454, completion: 1681),
                slicedWith: deepSeek,
                generatedAt: "2026-09-07T13:08:40.250Z"
            )
        )
        #expect(LLMCost.text(charge) == "约 ¥0.01")
        #expect(LLMCost.parseGeneratedAt("2026-09-07T13:08:40.250Z") != nil)
        #expect(LLMCost.parseGeneratedAt("2026-09-07T13:08:40Z") != nil)
        #expect(LLMCost.parseGeneratedAt("yesterday") == nil)
    }

    @Test func usageLineKeepsTokensWhenPriceIsUnknown() {
        let line = LLMCost.usageLine(
            usage: usage(prompt: 5000, completion: 135),
            slicedWith: "deepseek-v4-flash|https://api.siliconflow.cn/v1",
            generatedAt: offPeakTime
        )
        #expect(line == "5,135 token")
    }
}
