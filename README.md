# topicut-ios

端侧 AI 视频切片 App「Topicut」（内部 target：`LiveSlice`，bundle `com.jiajiali.liveslice`，iOS 26；曾名 LiveSlice / 片刻 AI，见 ADR-0021）及其 Swift 包。1.0.0 的完整链路：

```
导入视频 → 端侧 ASR（SpeechAnalyzer / SpeechTranscriber）→ SRT 文本 → 用户选定的 AI 服务（默认 DeepSeek，通用 topic_complete 提示词）
→ 带 schema_version 的 EDL JSON → 即点即播预览（源画面 + 字幕叠加层）→ 保存时 AVFoundation 按原比例导出（剪切、拼接、烧录字幕，长边 ≤ 1920）
→ 保存到相册
```

隐私政策与用户支持页由 `gh-pages` 分支托管：<https://lijiaaaaa-bot.github.io/topicut-ios/>。

判断「有什么 / 没什么」只看 `docs/ARCHITECTURE.yaml`，不看本 README 的语气。

## 现在就有（implemented）

- `LiveSliceCore`：SRT 解析与序列化（严格、非法即报错）、通用完整话题切片提示词（默认 `general`，保留 `military_news` 预设）、
  DeepSeek OpenAI 兼容 HTTP 客户端（URLSession）、LLM 输出校验、EDL 文档编解码。
- `LiveSliceASR`：Speech 框架的 SpeechAnalyzer / SpeechTranscriber 端侧转写，语言模型按需下载并显示进度；
  按标点 / 字数 / 时长 / 静音切成字幕条；音频不出设备。
- `LiveSliceRender`：AVFoundation 合成与导出。按 EDL 的 `segments` 剪切拼接，输出与原视频相同的画幅
  比例（最长边不超过 1920）；用 Core Text 光栅化字幕并按合成时间轴烧录
  （CATextLayer (not used) 在导出渲染器里不出字）。
- `LiveSliceKeychain`：用户自己的 AI 服务密钥只存 Keychain。App 内按名字选服务（DeepSeek 默认 / 硅基流动 /
  阿里云百炼 / 自定义 OpenAI 兼容地址），选预设即填好接口地址与模型。
- `LiveSliceUI`：深色极简 AI 工作台（视频导入、进度环、成片播放器、画幅选择、顺序预渲染、分享、存相册、设置、
  工作期间屏幕常亮）与
  可测试的会话状态机 `SliceSession`。
- `App/LiveSlice`：iOS App target（`com.jiajiali.liveslice`），由 xcodegen 从 `project.yml` 生成，用于 TestFlight。
- `liveslice-cli`：Core 的命令行调用者，供 `scripts/live_check.sh` 跑真实 DeepSeek。
- 100+ 单元测试（Swift Testing）。ASR 与渲染测试走真实框架路径：`say` 合成中文语音 → SpeechAnalyzer；
  合成视频 → AVAssetExportSession，逐像素检查字幕带。测试媒体在运行时生成，仓库不含二进制。
- 8 道债务守卫 + 一键门禁 `scripts/gate.sh`（详见 `docs/DEBT_REGISTER.md`）。

## 还没有（planned）

- 矩阵变体（同一切片多种时长 / 字幕样式）。
- App 内编辑 EDL（当前只读）。
- 真正的后台渲染 / 转写（当前只有屏幕常亮 + 短暂的 UIKit 后台任务；切走太久会中断）。

多租户后端、云端渲染属于 `requires_new_architecture`，不在本仓库演进路径上。
本项目不使用 ffmpeg (not used)、Whisper (not used)、CoreML (not used)、Metal (not used)。

## 开源与密钥安全（BYOK 模式）

本项目采用 **BYOK (Bring Your Own Key，用户自带密钥)** 模式开源，从架构设计与代码工程上杜绝密钥泄漏：

1. **纯端侧直连，无中转后端**：切片请求通过 URLSession 直连用户选定的 AI 服务（默认 DeepSeek 官方接口）。项目没有中心化服务器，不代理、不中转、不记录任何用户的密钥与视频数据。
2. **零硬编码密钥**：代码库与发布构建中绝对不包含任何开发者的私有 Key。
3. **安全凭证注入**：
   - **CLI 模式**：仅通过当前 Shell 环境变量（`DEEPSEEK_API_KEY`）临时注入；守卫 07 强制要求工作区内不得存在 `.env` 凭证文件。
   - **App 模式**：用户在设置页填入自己的 Key，`APIKeyStore` 写入系统 Keychain（`AfterFirstUnlockThisDeviceOnly`），绝不明文落盘。
4. **守卫防泄漏门禁**：项目内置 `07_no_secrets.sh` 守卫并已安装为 `pre-commit` 钩子，物理阻断任何形如 `sk-...` 的密钥被提交到 Git 历史。

## 使用

```bash
# 门禁：8 道守卫 + swift build + swift test（含真实 ASR / 渲染测试，首次会下载 zh_CN 语音模型）
bash scripts/gate.sh

# 生成 Xcode 工程并在模拟器构建（模拟器没有语音识别能力，转写只能在真机验证）
bash scripts/gen_project.sh
xcodebuild -project LiveSlice.xcodeproj -scheme LiveSlice -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 真实 DeepSeek 调用（需要 shell 里有 DEEPSEEK_API_KEY；没有则退出码 2 并说明原因）
export DEEPSEEK_API_KEY=<your-key>
bash scripts/live_check.sh                 # 默认输入 Fixtures/sample_military_news.srt，默认 domain=general
swift run liveslice-cli slice path/to.srt [--out edl.json] [--domain general|military_news]

# 安装 pre-commit 钩子（= gate.sh）
bash scripts/install_hooks.sh
```

可选环境变量（CLI）：`DEEPSEEK_BASE_URL`（默认 `https://api.deepseek.com`）、`DEEPSEEK_MODEL`（默认 `deepseek-v4-flash`）。
没有任何 mock / 示例数据回落；缺 key、HTTP 出错、LLM 输出非法、无音轨、无视频轨、模拟器无识别器都会以明确错误终止并显示在界面上。

## 目录

```
App/LiveSlice/               iOS App 入口（@main）、图标、隐私清单
Sources/LiveSliceCore/       决策层：SRT → DeepSeek → EDL
Sources/LiveSliceASR/        端侧语音转写
Sources/LiveSliceRender/     EDL 执行：合成、裁切、字幕、导出
Sources/LiveSliceKeychain/   API Key 存取
Sources/LiveSliceUI/         SwiftUI 界面 + SliceSession 状态机
Sources/LiveSliceTestSupport/ 测试期合成媒体
Sources/liveslice-cli/       CLI 入口
Tests/<Module>Tests/         每个源文件对应一个 <Name>Tests.swift（视图类文件在 ARCHITECTURE.yaml 登记 test_exempt）
project.yml                  xcodegen 规格（.xcodeproj 不入库）
scripts/gate.sh              一键门禁
scripts/guards/              债务守卫 01–08
docs/ARCHITECTURE.yaml       implemented / planned / requires_new_architecture 的唯一真源
docs/DEBT_REGISTER.md        债务类型 → 守卫 → 触发条件 → 例外
docs/DECISIONS.md            ADR
docs/EDL_SCHEMA.md           EDL JSON 契约与兼容规则
```

## Known issues（已知、未实现）

- 提示词质量：DeepSeek 偶尔把「好，咱们看看第一道题」这类答题过渡句保留在 `segments[]` 末段，
  提示词已明令禁止但模型仍会犯。**尚无启发式后校验**；这是提示词迭代问题，靠 EDL 里的 `llm`
  用量与人工抽检来跟踪，不用静默修剪掩盖。
- `removed_segments` 与外层边界的不变量现已强制（越界或与 kept 重叠即整次报错）；因此提示词新增了
  「只记录 slice 内部被删区间」一条，若模型仍越界，运行会以 `removedSegmentOutsideClip` 失败而不是自动裁掉。
- 渲染用的 `AVMutableVideoComposition` 系 API 在 iOS 26 标记为 deprecated（仍可用）；迁移到
  `AVVideoComposition.Configuration` 是后续工作。

## 与 live_slice_auto 的关系

完整话题切片的核心理念、提示词边界规则与 `highlights` 数据结构从 `/Users/lijia/live_slice_auto` 移植，
原项目只读、未修改。本项目解除了原项目单一绑定军事题材的限制，默认采用覆盖各类长视频/播客/访谈的通用
切片策略（`domain: general`），同时保留 `military_news` 作为可选预设。原项目基于 PySide6 (not used) 与
ffmpeg (not used)，本项目不复用其运行时。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
