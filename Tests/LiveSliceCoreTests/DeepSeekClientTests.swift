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
        #expect(defaults.model == "deepseek-chat")
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
