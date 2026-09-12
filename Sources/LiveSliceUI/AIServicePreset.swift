// Why: the slicing step speaks the OpenAI chat protocol, so "which AI service" is nothing more
// than a base URL and a model name — facts the user should not have to look up. A preset carries
// the three things a service needs (endpoint, default model, where to create a key). `matching`
// maps the stored endpoint back to its preset so the settings picker shows what is actually in
// use; an endpoint nobody recognises is shown as 自定义, never silently reassigned.

import Foundation
import LLMKit
import LiveSliceCore

public struct AIServicePreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let model: String
    /// The provider's page for creating an API key.
    public let keyPage: URL

    public static let deepSeek = AIServicePreset(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: DeepSeekConfiguration.defaultBaseURL,
        model: DeepSeekConfiguration.defaultModel,
        keyPage: "https://platform.deepseek.com/api_keys"
    )
    public static let siliconFlow = AIServicePreset(
        id: "siliconflow",
        name: "硅基流动",
        baseURL: "https://api.siliconflow.cn/v1",
        model: "deepseek-ai/DeepSeek-V4-Flash",
        keyPage: "https://cloud.siliconflow.cn/account/ak"
    )
    public static let bailian = AIServicePreset(
        id: "bailian",
        name: "阿里云百炼",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        model: "qwen-plus",
        keyPage: "https://bailian.console.aliyun.com/?tab=model#/api-key"
    )

    /// Order of appearance in the picker; the first one is the app default.
    public static let all: [AIServicePreset] = [deepSeek, siliconFlow, bailian]

    /// Picker tag for "none of the presets".
    public static let customID = "custom"

    /// The preset serving `baseURL` (trailing slash and case of the host ignored), or nil.
    public static func matching(baseURL: String) -> AIServicePreset? {
        let wanted = normalized(baseURL)
        return all.first { normalized($0.baseURL) == wanted }
    }

    private static func normalized(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private init(id: String, name: String, baseURL: String, model: String, keyPage: StaticString) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        // A literal that does not parse is a programming error, not a runtime condition.
        guard let url = URL(string: "\(keyPage)") else { preconditionFailure("invalid key page URL: \(keyPage)") }
        self.keyPage = url
    }
}
