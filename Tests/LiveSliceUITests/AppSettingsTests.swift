import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceASR
import LiveSliceCore
import LiveSliceKeychain

@MainActor
struct AppSettingsTests {
    private func make() throws -> (AppSettings, APIKeyStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "liveslice.tests.\(UUID().uuidString)")!
        let store = APIKeyStore(service: "com.jiajiali.liveslice.tests.\(UUID().uuidString)")
        return (try AppSettings(store: store, defaults: defaults), store, defaults)
    }

    @Test func defaultsWhenNothingStored() throws {
        let (settings, _, _) = try make()
        #expect(settings.apiKey == "")
        #expect(settings.baseURL == DeepSeekConfiguration.defaultBaseURL)
        #expect(settings.model == DeepSeekConfiguration.defaultModel)
        #expect(settings.localeIdentifier == "auto")
        #expect(settings.localePreference == .automatic)
        #expect(settings.locale == nil)
        #expect(throws: DeepSeekError.missingAPIKey) { try settings.deepSeekConfiguration() }
    }

    @Test func apiKeyRoundTripsThroughKeychain() throws {
        let (settings, store, defaults) = try make()
        defer { try? store.delete() }
        try settings.saveAPIKey(" sk-abc \n")
        #expect(settings.apiKey == "sk-abc")
        #expect(try store.load() == "sk-abc")
        let reloaded = try AppSettings(store: store, defaults: defaults)
        #expect(reloaded.apiKey == "sk-abc")
        #expect(try reloaded.deepSeekConfiguration().apiKey == "sk-abc")
        try settings.saveAPIKey("")
        #expect(try store.load() == nil)
    }

    @Test func defaultsPointAtTheDeepSeekPreset() throws {
        let (settings, _, _) = try make()
        #expect(settings.servicePreset == .deepSeek)
    }

    @Test func applyingAPresetSetsEndpointAndModelAndKeepsTheKey() throws {
        let (settings, store, defaults) = try make()
        defer { try? store.delete() }
        try settings.saveAPIKey("sk-mine")
        settings.apply(.siliconFlow)
        #expect(settings.baseURL == "https://api.siliconflow.cn/v1")
        #expect(settings.model == "deepseek-ai/DeepSeek-V4-Flash")
        #expect(settings.apiKey == "sk-mine")
        #expect(settings.servicePreset == .siliconFlow)
        let reloaded = try AppSettings(store: store, defaults: defaults)
        #expect(reloaded.servicePreset == .siliconFlow)
        #expect(try reloaded.deepSeekConfiguration().baseURL.absoluteString == "https://api.siliconflow.cn/v1")
    }

    @Test func handTypedEndpointIsCustomNotAPreset() throws {
        let (settings, _, _) = try make()
        settings.baseURL = "https://proxy.example/v1"
        #expect(settings.servicePreset == nil)
        // A preset endpoint with a different model is still that preset: the model is a choice within it.
        settings.apply(.deepSeek)
        settings.model = "deepseek-v4-pro"
        #expect(settings.servicePreset == .deepSeek)
    }

    @Test func endpointAndLocalePersistInDefaults() throws {
        let (settings, store, defaults) = try make()
        settings.baseURL = "https://proxy.example"
        settings.model = "deepseek-reasoner"
        settings.localeIdentifier = "en_US"
        let reloaded = try AppSettings(store: store, defaults: defaults)
        #expect(reloaded.baseURL == "https://proxy.example")
        #expect(reloaded.model == "deepseek-reasoner")
        #expect(reloaded.locale?.identifier == "en_US")
        #expect(reloaded.localePreference == .fixed(Locale(identifier: "en_US")))
    }
}
