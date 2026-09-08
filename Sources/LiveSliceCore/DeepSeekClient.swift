// Why: the LLM is the only network dependency of the vertical slice. A thin OpenAI-compatible
// chat client with an injectable transport keeps unit tests offline while `liveslice-cli` uses
// the real URLSession. The API key comes exclusively from configuration; there is no demo mode.

import Foundation

public enum DeepSeekError: Error, Equatable, Sendable {
    /// `DEEPSEEK_API_KEY` is unset or blank. There is deliberately no offline substitute.
    case missingAPIKey
    case invalidBaseURL(String)
    case httpStatus(code: Int, body: String)
    case notHTTPResponse
    case malformedResponse(String)
}

public struct DeepSeekConfiguration: Equatable, Sendable {
    public static let environmentKeyName = "DEEPSEEK_API_KEY"
    public static let defaultBaseURL = "https://api.deepseek.com"
    /// DeepSeek's current non-thinking model. `deepseek-chat` was an alias for it that the
    /// platform retired in 2026-07 and no longer lists under `/models`.
    public static let defaultModel = "deepseek-v4-flash"

    public let apiKey: String
    public let baseURL: URL
    public let model: String

    public init(apiKey: String, baseURL: String, model: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingAPIKey
        }
        guard let url = URL(string: baseURL), url.scheme != nil, url.host() != nil else {
            throw DeepSeekError.invalidBaseURL(baseURL)
        }
        self.apiKey = apiKey
        self.baseURL = url
        self.model = model
    }

    /// Reads `DEEPSEEK_API_KEY` (required), `DEEPSEEK_BASE_URL` and `DEEPSEEK_MODEL` (optional).
    public static func fromEnvironment(_ environment: [String: String]) throws -> DeepSeekConfiguration {
        guard let apiKey = environment[environmentKeyName] else { throw DeepSeekError.missingAPIKey }
        return try DeepSeekConfiguration(
            apiKey: apiKey,
            baseURL: environment["DEEPSEEK_BASE_URL"] ?? defaultBaseURL,
            model: environment["DEEPSEEK_MODEL"] ?? defaultModel
        )
    }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct DeepSeekClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let configuration: DeepSeekConfiguration
    private let transport: Transport

    /// `transport` defaults to the shared URLSession; tests inject a canned transport.
    public init(configuration: DeepSeekConfiguration, transport: Transport? = nil) {
        self.configuration = configuration
        if let transport {
            self.transport = transport
        } else {
            self.transport = { request in try await URLSession.shared.data(for: request) }
        }
    }

    /// Sends a chat completion and returns the assistant content plus the token/latency record.
    /// A response without `usage` is malformed: cost accounting is part of the contract, never zero-filled.
    public func chatCompletion(messages: [ChatMessage], temperature: Double) async throws -> ChatCompletionResult {
        let request = try makeRequest(messages: messages, temperature: temperature)
        let clock = ContinuousClock()
        let started = clock.now
        let (data, response) = try await transport(request)
        let latencyMs = Int((clock.now - started) / .milliseconds(1))
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.notHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.httpStatus(code: http.statusCode, body: Self.snippet(data))
        }
        let body = try Self.decodeBody(data)
        return ChatCompletionResult(
            content: try Self.extractContent(body, data: data),
            usage: LLMUsage(
                model: configuration.model,
                promptTokens: body.usage.promptTokens,
                completionTokens: body.usage.completionTokens,
                totalTokens: body.usage.totalTokens,
                latencyMs: latencyMs,
                promptCacheHitTokens: body.usage.promptCacheHitTokens
            )
        )
    }

    func makeRequest(messages: [ChatMessage], temperature: Double) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequestBody(model: configuration.model, messages: messages, temperature: temperature)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func decodeBody(_ data: Data) throws -> ChatResponseBody {
        do {
            return try JSONDecoder().decode(ChatResponseBody.self, from: data)
        } catch let error as DecodingError {
            throw DeepSeekError.malformedResponse("\(error) body=\(snippet(data))")
        }
    }

    static func extractContent(_ body: ChatResponseBody, data: Data) throws -> String {
        guard let content = body.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.malformedResponse("choices[0].message.content missing or empty; body=\(snippet(data))")
        }
        return content
    }

    private static func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(500), as: UTF8.self)
    }

    /// Thinking mode is switched off in both dialects the presets speak: DeepSeek's own
    /// `thinking.type` and the `enable_thinking` flag used by SiliconFlow / Bailian (Qwen). The
    /// slicer wants one direct JSON answer at a controlled temperature; a chain of thought over a
    /// two-hour transcript runs for minutes with no bytes on the wire and ignores `temperature`
    /// (ADR-0020). Servers that reject unknown fields answer 400, which surfaces as-is.
    struct ChatRequestBody: Encodable {
        struct Thinking: Encodable {
            let type: String
        }

        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let thinking = Thinking(type: "disabled")
        let enableThinking = false

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, thinking
            case enableThinking = "enable_thinking"
        }
    }

    struct ChatResponseBody: Decodable {
        struct Choice: Decodable {
            let message: ChatMessage
        }
        struct Usage: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
            /// DeepSeek extension: how many prompt tokens were billed at the cache-hit rate. Other
            /// servers omit it; then the cost estimate treats every prompt token as a cache miss.
            let promptCacheHitTokens: Int?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
                case promptCacheHitTokens = "prompt_cache_hit_tokens"
            }
        }
        let choices: [Choice]
        /// Required: OpenAI-compatible servers (DeepSeek included) always send it. Absence is an error.
        let usage: Usage
    }
}

/// Token and latency record of one LLM call. Stored in the EDL (`llm`) as the cost baseline for iteration.
public struct LLMUsage: Codable, Equatable, Sendable {
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let latencyMs: Int
    /// Prompt tokens billed at the cache-hit rate (DeepSeek reports it; nil when the server did not).
    /// Optional EDL field added 2026-09-07 without a schema bump (EDL_SCHEMA rule 2).
    public let promptCacheHitTokens: Int?

    public init(
        model: String, promptTokens: Int, completionTokens: Int, totalTokens: Int, latencyMs: Int,
        promptCacheHitTokens: Int? = nil
    ) {
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.latencyMs = latencyMs
        self.promptCacheHitTokens = promptCacheHitTokens
    }
}

public struct ChatCompletionResult: Equatable, Sendable {
    public let content: String
    public let usage: LLMUsage

    public init(content: String, usage: LLMUsage) {
        self.content = content
        self.usage = usage
    }
}
