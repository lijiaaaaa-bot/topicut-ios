import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

struct AIServicePresetTests {
    @Test func everyPresetIsAValidConfigurationWithAChatCompletionsEndpoint() throws {
        for preset in AIServicePreset.all {
            let configuration = try DeepSeekConfiguration(apiKey: "sk-test", baseURL: preset.baseURL, model: preset.model)
            let endpoint = configuration.baseURL.appending(path: "chat/completions").absoluteString
            #expect(endpoint == preset.baseURL + "/chat/completions", "\(preset.id)")
            #expect(configuration.model == preset.model)
            #expect(preset.keyPage.scheme == "https", "\(preset.id)")
        }
    }

    @Test func idsAndNamesAreUniqueAndTheDefaultComesFirst() {
        let ids = AIServicePreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(AIServicePreset.customID))
        #expect(Set(AIServicePreset.all.map(\.name)).count == ids.count)
        #expect(AIServicePreset.all.first == .deepSeek)
        #expect(AIServicePreset.deepSeek.baseURL == DeepSeekConfiguration.defaultBaseURL)
        #expect(AIServicePreset.deepSeek.model == DeepSeekConfiguration.defaultModel)
    }

    @Test func matchingIgnoresTrailingSlashSpacesAndHostCase() {
        #expect(AIServicePreset.matching(baseURL: "https://api.deepseek.com") == .deepSeek)
        #expect(AIServicePreset.matching(baseURL: " https://API.deepseek.com/ ") == .deepSeek)
        #expect(AIServicePreset.matching(baseURL: "https://api.siliconflow.cn/v1/") == .siliconFlow)
        #expect(AIServicePreset.matching(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1") == .bailian)
    }

    @Test func unknownEndpointsMatchNothing() {
        #expect(AIServicePreset.matching(baseURL: "https://api.deepseek.com/v1") == nil)
        #expect(AIServicePreset.matching(baseURL: "https://proxy.example") == nil)
        #expect(AIServicePreset.matching(baseURL: "") == nil)
    }
}
