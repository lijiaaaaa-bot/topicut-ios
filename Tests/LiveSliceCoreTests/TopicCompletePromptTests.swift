import Testing
@testable import LiveSliceCore

struct TopicCompletePromptTests {
    @Test func generalSystemPromptInterpolatesPolicyAndKeepsCoreRules() {
        let policy = ClipCountPolicy(durationMinutes: 12.5, minClips: 3, maxClips: 7, hardMaxClips: 9)
        let prompt = TopicCompletePrompt.system(policy: policy, domain: "general")
        #expect(prompt.contains("本场字幕约 12.5 分钟"))
        #expect(prompt.contains("建议粒度范围 3~7 条，尽量不超出 9 条"))
        #expect(prompt.contains("长视频/直播切片助手"))
        #expect(prompt.contains("只输出 JSON"))
        #expect(prompt.contains("\"frameworks\""))
        #expect(prompt.contains("\"removed_segments\""))
        #expect(prompt.contains("观点论述"))
        #expect(prompt.contains("知识科普"))
        #expect(!prompt.contains("军事新闻直播切片助手"))
        #expect(!prompt.contains("{{"))
    }

    @Test func militarySystemPromptUsesSpecializedCategories() {
        let policy = ClipCountPolicy(durationMinutes: 10.0, minClips: 1, maxClips: 3, hardMaxClips: 4)
        let prompt = TopicCompletePrompt.system(policy: policy, domain: "military_news")
        #expect(prompt.contains("军事新闻直播切片助手"))
        #expect(prompt.contains("能源与战略资源"))
        #expect(prompt.contains("大国博弈"))
    }

    @Test func userIntroMatchesDomain() {
        #expect(TopicCompletePrompt.userIntro(domain: "general").contains("音视频/直播字幕"))
        #expect(TopicCompletePrompt.userIntro(domain: "military_news").contains("军事新闻直播字幕"))
        #expect(TopicCompletePrompt.userIntro.contains("音视频/直播字幕"))
    }
}
