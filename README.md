# liveslice-ios

本地视频切片 AI Agent 的 iOS/macOS 核心库。当前版本 0.1.0 只实现一条竖切片：

```
SRT 文本 → SRTParser → DeepSeek（topic_complete + military_news 提示词）→ 带 schema_version 的 EDL JSON
```

其余能力（端侧 ASR、渲染、界面）**尚未实现**，登记在 `docs/ARCHITECTURE.yaml` 的 `planned` 段。
判断「有什么 / 没什么」只看那个文件，不看本 README 的语气。

## 现在就有（implemented）

- Swift 包（SwiftPM，`platforms: iOS 26, macOS 26`），纯 Foundation，无第三方依赖。
- `LiveSliceCore`：SRT 解析（严格、乱序排序、非法即报错）、军事新闻完整话题提示词、
  DeepSeek OpenAI 兼容 HTTP 客户端（URLSession）、LLM 输出校验、EDL 文档编解码。
- `liveslice-cli`：Core 的真实调用者，供 `scripts/live_check.sh` 跑真实 DeepSeek。
- 46 个离线单元测试（Swift Testing）。
- 8 道债务守卫 + 一键门禁 `scripts/gate.sh`（详见 `docs/DEBT_REGISTER.md`）。

## 还没有（planned）

- 端侧 ASR：SpeechAnalyzer (planned) / SpeechTranscriber (planned)。
- 渲染：AVFoundation (planned)，执行 EDL 的 segments。
- 界面：SwiftUI (planned)；App target 用 xcodegen (planned) 生成，见 ADR-0006。
- Key 存储：Keychain (planned)，替代环境变量。
- 矩阵变体。

多租户后端、云端渲染属于 `requires_new_architecture`，不在本仓库演进路径上。
本项目不使用 ffmpeg (not used)、Whisper (not used)、CoreML (not used)、Metal (not used)。

## 开源与密钥安全（BYOK 模式）

本项目采用 **BYOK (Bring Your Own Key，用户自带密钥)** 模式开源，从架构设计与代码工程上杜绝密钥泄漏：

1. **纯端侧直连，无中转后端**：本项目为 100% 运行在本地设备上的开源工具，切片请求通过 URLSession 直连 DeepSeek 官方接口。项目没有中心化服务器，不代理、不中转、不记录任何用户的密钥与视频数据。
2. **零硬编码密钥**：代码库与发布构建中绝对不包含任何开发者的私有 Key。
3. **安全凭证注入**：
   - **CLI 模式**：仅通过当前 Shell 环境变量（`DEEPSEEK_API_KEY`）临时注入；守卫 07 强制要求工作区内不得存在 `.env` 凭证文件。
   - **App 模式（planned）**：在未来的 SwiftUI (planned) 界面中，用户在设置页填入自己的 Key，通过系统原生 Keychain (planned) 加密存取，绝不明文落盘。
4. **守卫防泄漏门禁**：项目内置 `07_no_secrets.sh` 守卫并已安装为 `pre-commit` 钩子，物理阻断任何形如 `sk-...` 的密钥被提交到 Git 历史。

## 使用

```bash
# 门禁：8 道守卫 + swift build + swift test
bash scripts/gate.sh

# 真实 DeepSeek 调用（需要 shell 里有 DEEPSEEK_API_KEY；没有则退出码 2 并说明原因）
export DEEPSEEK_API_KEY=<your-key>
bash scripts/live_check.sh                 # 默认输入 Fixtures/sample_military_news.srt
swift run liveslice-cli slice path/to.srt --out edl.json

# 安装 pre-commit 钩子（= gate.sh）
bash scripts/install_hooks.sh
```

可选环境变量：`DEEPSEEK_BASE_URL`（默认 `https://api.deepseek.com`）、`DEEPSEEK_MODEL`（默认 `deepseek-chat`）。
没有任何 mock / 示例数据回落；缺 key、HTTP 出错、LLM 输出非法都会以明确错误终止。

## 目录

```
Sources/LiveSliceCore/     核心库（每个文件头部有 // Why:）
Sources/liveslice-cli/     CLI 入口
Tests/LiveSliceCoreTests/  每个源文件对应一个 <Name>Tests.swift
Fixtures/                  live_check 用的合成 SRT
scripts/gate.sh            一键门禁
scripts/guards/            债务守卫 01–08
docs/ARCHITECTURE.yaml     implemented / planned / requires_new_architecture 的唯一真源
docs/DEBT_REGISTER.md      债务类型 → 守卫 → 触发条件 → 例外
docs/DECISIONS.md          ADR
docs/EDL_SCHEMA.md         EDL JSON 契约与兼容规则
```

## Known issues（已知、未实现）

- 提示词质量：DeepSeek 偶尔把「好，咱们看看第一道题」这类答题过渡句保留在 `segments[]` 末段，
  提示词已明令禁止但模型仍会犯。**尚无启发式后校验**；这是提示词迭代问题，靠 EDL 里的 `llm`
  用量与人工抽检来跟踪，不用静默修剪掩盖。
- `removed_segments` 与外层边界的不变量现已强制（越界或与 kept 重叠即整次报错）；因此提示词新增了
  「只记录 slice 内部被删区间」一条，若模型仍越界，运行会以 `removedSegmentOutsideClip` 失败而不是自动裁掉。

## 与 live_slice_auto 的关系

提示词、`highlights` 字段（start/end/start_sec/end_sec/title/score/tags/reason/segments/
removed_segments/category）与 `topic_complete + military_news` 默认策略从
`/Users/lijia/live_slice_auto` 移植，原项目只读、未修改。原项目基于 PySide6 (not used) 与
ffmpeg (not used)，本项目不复用其运行时。

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

