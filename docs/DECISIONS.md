# Decisions (ADR, short form)

Every non-obvious architectural choice lives here, not in chat history. Guard 08 requires each
entry to have `状态 / 决策 / 理由` and checks that the topics below are covered.
Format: `## ADR-NNNN <title>`; never renumber; supersede by adding a new ADR.

## ADR-0001 不做多租户后端

- 状态: 已采纳（2026-09-06）
- 决策: 本项目不包含任何多租户服务端；所有处理在用户设备上完成，LLM 直连 DeepSeek HTTP API。
- 理由: 单用户本地工具不需要账户体系、配额与隔离；多租户会把「渲染在客户端」的核心假设推翻，并引入运维成本与数据合规义务。若未来需要，属于 `requires_new_architecture`（见 ARCHITECTURE.yaml），不是本代码库的演进。
- 后果: 无服务器代码、无登录、无用户数据库；API key 由用户自行持有。

## ADR-0002 ASR 走端侧

- 状态: 已采纳，实现状态 planned
- 决策: 语音转写使用系统端侧能力 SpeechAnalyzer (planned) / SpeechTranscriber (planned)，不上传音频，不引入 Whisper (not used) / WhisperKit (not used) 模型文件。
- 理由: 直播录像时长以小时计，上传成本与隐私风险都高；端侧 ASR 免费、离线、不需要管理模型二进制（同时防住「大模型文件进 git」这一类债务）。
- 后果: 第一条竖切片的输入是 SRT 文本；ASR 适配器落地时只需产出同样的 SRT 文本即可接入 `SRTParser`。

## ADR-0003 EDL 带 schema_version

- 状态: 已采纳
- 决策: 每份 EDL JSON 顶层必须有整数 `schema_version`；解码器只接受自己认识的版本，缺失或未知版本直接抛错。兼容规则见 `docs/EDL_SCHEMA.md`。
- 理由: EDL 是「决策」与「渲染」之间唯一的契约，两侧会独立迭代；没有版本号就没有办法安全升级。
- 后果: 任何字段变更必须同时改 `EDL_SCHEMA.md`、`CHANGELOG.md` 与 `ARCHITECTURE.yaml` 的 `schema_version_of_edl`。

## ADR-0004 先只做一条竖切片

- 状态: 已采纳
- 决策: 0.1.0 只实现「SRT 文本 → DeepSeek 主题完整切片 → EDL JSON」；ASR、渲染、UI、矩阵、Keychain (planned) 一律只在 ARCHITECTURE.yaml `planned` 段登记，不写空实现、不预埋协议。
- 理由: 来自 math-anything 债务审计的直接教训：预埋的抽象与「以备将来」的模块会变成无人调用的僵尸代码（约 30% Sources）。每个文件必须有真实调用者；可替换性靠清晰模块边界 + 登记，而不是靠空接口。
- 后果: 守卫 01/04 强制「每个源文件有登记、有调用者、有同名测试」。

## ADR-0005 禁止 fallback

- 状态: 已采纳
- 决策: 任何上游失败（缺 API key、HTTP 非 2xx、LLM 输出不合法、时间范围非法）都以类型化错误向上抛出；没有 mock 数据、没有示例 EDL、没有「跳过坏条目继续」。Python 原版对 `start == end` 的占位条目静默跳过，这里改为报错。
- 理由: 静默降级会让 UI 展示「成功」的假象，并把错误埋在日志里；对切片产品而言，一条错的切片计划比失败更贵。
- 后果: 守卫 02 禁止 `try?` / `try!` / 空 `catch` / `?? 字面量`；例外需逐行 `// guard-allow: silent-fallback <理由>`。

## ADR-0006 0.1.0 不生成 iOS App target

- 状态: 已采纳（可被后续 ADR 取代）
- 决策: 不用 xcodegen (planned) 生成 App target，SwiftUI (planned) 外壳保持 planned。
- 理由: 当前没有一个「粘贴 SRT → 显示 EDL」之外的真实入口需要 App 才能验证；生成一个空 App 就是制造僵尸 product。CLI `liveslice-cli` 已是 Core 的真实调用者。
- 后果: `swift test` 在 macOS 上是唯一必需的验证路径；iOS 平台声明保留在 Package.swift。

## ADR-0007 开源与 API Key 安全策略（BYOK 模式）

- 状态: 已采纳
- 决策: 采用 BYOK (Bring Your Own Key, 自带密钥) 模式开源。项目不内置、不代理任何开发者密钥，无中间代付网关。CLI 工具仅从当前 Shell 环境变量（`DEEPSEEK_API_KEY`）读取；未来 App 仅通过 Keychain (planned) 加密存取；仓库内置守卫 07 物理阻断密钥入库。
- 理由: 彻底消除开发者私有 Key 泄漏与代付账单风险，确保工具 100% 运行在用户本地端侧，数据与隐私不出用户信任域，契合纯端侧工具的开源定位。
- 后果: 开发者无托管与 Token 运营成本；用户需自行申请并配置 DeepSeek API Key。

