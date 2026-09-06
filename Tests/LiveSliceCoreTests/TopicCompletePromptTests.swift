import Testing
@testable import LiveSliceCore

struct TopicCompletePromptTests {
    @Test func systemPromptInterpolatesPolicyAndKeepsCoreRules() {
        let policy = ClipCountPolicy(durationMinutes: 12.5, minClips: 3, maxClips: 7, hardMaxClips: 9)
        let prompt = TopicCompletePrompt.system(policy: policy)
        #expect(prompt.contains("本场字幕约 12.5 分钟"))
        #expect(prompt.contains("建议粒度范围 3~7 条，尽量不超出 9 条"))
        #expect(prompt.contains("军事新闻直播切片助手"))
        #expect(prompt.contains("只输出 JSON"))
        #expect(prompt.contains("\"frameworks\""))
        #expect(prompt.contains("\"removed_segments\""))
        #expect(prompt.contains("能源与战略资源"))
        #expect(!prompt.contains("{{"))
    }

    @Test func userIntroIsMilitaryNews() {
        #expect(TopicCompletePrompt.userIntro.contains("军事新闻直播字幕"))
    }
}
