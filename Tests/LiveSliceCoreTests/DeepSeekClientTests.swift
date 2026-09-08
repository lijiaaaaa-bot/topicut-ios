import Foundation
import Testing
@testable import LiveSliceCore

struct DeepSeekClientTests {
    @Test func missingKeyFailsFast() {
        #expect(throws: DeepSeekError.missingAPIKey) { try DeepSeekConfiguration.fromEnvironment([:]) }
        #expect(throws: DeepSeekError.missingAPIKey) {
            try DeepSeekConfiguration.fromEnvironment(["DEEPSEEK_API_KEY": "   "])
        }
    }

    @Test func environmentDefaultsAndOverrides() throws {
        let defaults = try DeepSeekConfiguration.fromEnvironment(["DEEPSEEK_API_KEY": "k"])
        #expect(defaults.baseURL.absoluteString == "https://api.deepseek.com")
        #expect(defaults.model == "deepseek-v4-flash")
        let custom = try DeepSeekConfiguration.fromEnvironment([
            "DEEPSEEK_API_KEY": "k", "DEEPSEEK_BASE_URL": "https://proxy.example", "DEEPSEEK_MODEL": "m",
        ])
        #expect(custom.baseURL.host() == "proxy.example")
        #expect(custom.model == "m")
        #expect(throws: DeepSeekError.invalidBaseURL("not a url")) {
            try DeepSeekConfiguration(apiKey: "k", baseURL: "not a url", model: "m")
        }
    }

    @Test func buildsOpenAICompatibleRequest() throws {
        let client = DeepSeekClient(configuration: try TestSupport.configuration())
        let request = try client.makeRequest(messages: [ChatMessage(role: "user", content: "hi")], temperature: 0.3)
        #expect(request.url?.absoluteString == "https://example.invalid/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-not-real")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "test-model")
        #expect(body?["temperature"] as? Double == 0.3)
        #expect((body?["messages"] as? [[String: String]])?.first?["content"] == "hi")
        // Thinking mode off in both dialects (ADR-0020): DeepSeek V4 reasons for minutes over a long
        // transcript before its first byte and ignores temperature while doing so.
        #expect((body?["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect(body?["enable_thinking"] as? Bool == false)
    }

    @Test func returnsAssistantContent() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(status: 200, body: TestSupport.chatEnvelope(content: "{\"ok\":1}"))
        )
        let result = try await client.chatCompletion(messages: [], temperature: 0)
        #expect(result.content == "{\"ok\":1}")
        #expect(result.usage.model == "test-model")
        #expect(result.usage.promptTokens == 1200)
        #expect(result.usage.completionTokens == 340)
        #expect(result.usage.totalTokens == 1540)
        #expect(result.usage.latencyMs >= 0)
        #expect(result.usage.promptCacheHitTokens == nil)
    }

    @Test func decodesDeepSeekCacheHitTokensWhenPresent() throws {
        let body = try DeepSeekClient.decodeBody(Data("""
        {"choices":[{"message":{"role":"assistant","content":"x"}}],
         "usage":{"prompt_tokens":1200,"completion_tokens":340,"total_tokens":1540,"prompt_cache_hit_tokens":1000,"prompt_cache_miss_tokens":200}}
        """.utf8))
        #expect(body.usage.promptCacheHitTokens == 1000)
    }

    @Test func usageRoundTripsThroughEDLJSONWithAndWithoutCacheHits() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let withHits = LLMUsage(model: "m", promptTokens: 10, completionTokens: 5, totalTokens: 15, latencyMs: 1, promptCacheHitTokens: 4)
        let data = try encoder.encode(withHits)
        #expect(String(decoding: data, as: UTF8.self).contains("\"prompt_cache_hit_tokens\":4"))
        #expect(try decoder.decode(LLMUsage.self, from: data) == withHits)
        // Documents written before the field existed decode with nil.
        let legacy = Data("{\"model\":\"m\",\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15,\"latency_ms\":1}".utf8)
        #expect(try decoder.decode(LLMUsage.self, from: legacy).promptCacheHitTokens == nil)
    }

    @Test func missingUsageIsAnErrorNotZero() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(
                status: 200, body: TestSupport.chatEnvelope(content: "{\"ok\":1}", includeUsage: false)
            )
        )
        await #expect(throws: DeepSeekError.self) { try await client.chatCompletion(messages: [], temperature: 0) }
        #expect(throws: DeepSeekError.self) {
            try DeepSeekClient.decodeBody(Data("{\"choices\":[],\"usage\":{\"prompt_tokens\":1}}".utf8))
        }
    }

    @Test func surfacesHTTPErrors() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(status: 401, body: Data("{\"error\":\"bad key\"}".utf8))
        )
        await #expect(throws: DeepSeekError.httpStatus(code: 401, body: "{\"error\":\"bad key\"}")) {
            try await client.chatCompletion(messages: [], temperature: 0)
        }
    }

    @Test func rejectsMalformedEnvelope() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(status: 200, body: Data("{\"choices\": []}".utf8))
        )
        await #expect(throws: DeepSeekError.self) { try await client.chatCompletion(messages: [], temperature: 0) }
        #expect(throws: DeepSeekError.self) { try DeepSeekClient.decodeBody(Data("not json".utf8)) }
    }
}
