// Why: every OpenAI-compatible server returns the token count, so it is shown as is. A price is
// shown only when the call went to a service whose public price sheet is in this file — DeepSeek's
// official endpoint, in CNY, with its peak/off-peak split by Beijing time. Any other endpoint or
// model shows tokens only; a made-up number would be worse than none.

import Foundation
import LLMKit
import LiveSliceCore

/// An estimated charge for one slicing call.
struct LLMCharge: Equatable {
    let yuan: Decimal
    /// Whether the call fell into the provider's peak-price window.
    let peak: Bool
}

enum LLMCost {
    /// CNY per million tokens at off-peak; DeepSeek's peak prices are exactly double.
    struct PriceSheet: Equatable {
        let inputMiss: Decimal
        let inputHit: Decimal
        let output: Decimal
    }

    /// DeepSeek 官方 「模型 & 价格」, read 2026-09-07. `deepseek-chat` was the alias of V4 Flash.
    static let deepSeekOffPeak: [String: PriceSheet] = [
        "deepseek-v4-flash": PriceSheet(inputMiss: 1.5, inputHit: 0.05, output: 4.5),
        "deepseek-chat": PriceSheet(inputMiss: 1.5, inputHit: 0.05, output: 4.5),
        "deepseek-v4-pro": PriceSheet(inputMiss: 4.5, inputHit: 0.15, output: 13.5),
    ]
    static let deepSeekHost = "api.deepseek.com"
    static let beijing = TimeZone(identifier: "Asia/Shanghai")

    /// The estimate, or nil when the endpoint is not DeepSeek's, the model has no entry, or the
    /// document's timestamp cannot be read. `slicedWith` is `model|baseURL`; a nil (pre-provenance
    /// record) is taken as the DeepSeek default the app shipped with, provided the model is DeepSeek's.
    static func estimate(usage: LLMUsage, slicedWith: String?, generatedAt: String) -> LLMCharge? {
        guard endpointIsDeepSeek(slicedWith), let sheet = deepSeekOffPeak[usage.model] else { return nil }
        guard let date = ISO8601DateFormatter().date(from: generatedAt) else { return nil }
        let peak = isPeak(date)
        let hit: Int
        if let reported = usage.promptCacheHitTokens { hit = min(max(reported, 0), usage.promptTokens) } else { hit = 0 }
        let miss = usage.promptTokens - hit
        var yuan = perMillion(miss, sheet.inputMiss) + perMillion(hit, sheet.inputHit) + perMillion(usage.completionTokens, sheet.output)
        if peak { yuan *= 2 }
        return LLMCharge(yuan: yuan, peak: peak)
    }

    /// DeepSeek's peak window: Beijing time, Monday–Friday, 9:00–12:00 and 14:00–18:00.
    static func isPeak(_ date: Date) -> Bool {
        guard let beijing else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijing
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        guard (2...6).contains(weekday) else { return false }
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return (9 * 60..<12 * 60).contains(minutes) || (14 * 60..<18 * 60).contains(minutes)
    }

    /// `约 ¥0.02`; anything under one fen reads `不到 ¥0.01`.
    static func text(_ charge: LLMCharge) -> String {
        let oneFen = Decimal(sign: .plus, exponent: -2, significand: 1)
        if charge.yuan < oneFen { return "不到 ¥0.01" }
        return "约 ¥" + charge.yuan.formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    /// `5,135 token` with grouping separators.
    static func tokenText(_ usage: LLMUsage) -> String {
        "\(usage.totalTokens.formatted(.number.grouping(.automatic))) token"
    }

    private static func endpointIsDeepSeek(_ slicedWith: String?) -> Bool {
        guard let slicedWith else { return true }
        guard let bar = slicedWith.firstIndex(of: "|") else { return false }
        let base = String(slicedWith[slicedWith.index(after: bar)...])
        guard let host = URL(string: base)?.host() else { return false }
        return host.lowercased() == deepSeekHost
    }

    private static func perMillion(_ tokens: Int, _ price: Decimal) -> Decimal {
        Decimal(tokens) * price / 1_000_000
    }
}
