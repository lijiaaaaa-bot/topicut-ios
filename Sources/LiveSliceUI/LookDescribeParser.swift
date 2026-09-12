// Why: natural-language 成片描述 must land on a closed JSON schema (framing/style/tune). Parsing is
// pure and fail-closed so the studio never invents a look from a half-parsed reply (ADR-0027).

import Foundation
import LLMKit
import LiveSliceRender

public enum LookDescribeError: Error, Equatable, Sendable, LocalizedError {
    case emptyPrompt
    case missingJSON
    case unknownFraming(String)
    case unknownStyle(String)
    case invalidTune(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt: "描述不能为空"
        case .missingJSON: "模型没有返回成片参数 JSON"
        case .unknownFraming(let raw): "未知画幅（\(raw)）"
        case .unknownStyle(let raw): "未知字幕样式（\(raw)）"
        case .invalidTune(let raw): "字幕微调无效（\(raw)）"
        }
    }
}

public enum LookDescribeParser {
    struct Payload: Codable, Equatable, Sendable {
        var framing: String
        var style: String
        var bandY: Double
        var fontScale: Double
        var textHex: String
        var accentHex: String
    }

    public static func parse(_ text: String) throws -> (CaptionStyle, FramingMode, CaptionTune) {
        let payload = try LLMJSON.decode(Payload.self, from: text)
        guard let framing = FramingMode(rawValue: payload.framing) else {
            throw LookDescribeError.unknownFraming(payload.framing)
        }
        guard let style = CaptionStyle(rawValue: payload.style) else {
            throw LookDescribeError.unknownStyle(payload.style)
        }
        let tune = CaptionTune(
            bandY: payload.bandY, fontScale: payload.fontScale,
            textHex: payload.textHex, accentHex: payload.accentHex
        )
        do {
            _ = try tune.textCGColor()
            _ = try tune.accentCGColor()
        } catch {
            throw LookDescribeError.invalidTune("\(payload.textHex)/\(payload.accentHex)")
        }
        return (style, framing, tune)
    }

    public static func systemPrompt() -> String {
        """
        你把用户的成片外观描述转成一个 JSON 对象，不要解释。键必须齐全：
        framing: sourceAspect | phonePortrait | portraitFit
        style: clean | highlightWord | none
        bandY: 0到1，0靠下 1靠上
        fontScale: 0.6到1.8
        textHex / accentHex: 六位 RRGGBB，无#
        """
    }
}
