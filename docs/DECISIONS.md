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

- 状态: 已采纳，已实现（`LiveSliceASR`，ADR-0009）
- 决策: 语音转写使用系统端侧能力 SpeechAnalyzer / SpeechTranscriber，不上传音频，不引入 Whisper (not used) / WhisperKit (not used) 模型文件。
- 理由: 直播录像时长以小时计，上传成本与隐私风险都高；端侧 ASR 免费、离线、不需要管理模型二进制（同时防住「大模型文件进 git」这一类债务）。
- 后果: 第一条竖切片的输入是 SRT 文本；ASR 适配器（`SpeechTranscriptionService`）产出 `[SRTCue]`，经 `SRTWriter` 变成同样的 SRT 文本接入 `TopicSlicer`。

## ADR-0003 EDL 带 schema_version

- 状态: 已采纳
- 决策: 每份 EDL JSON 顶层必须有整数 `schema_version`；解码器只接受自己认识的版本，缺失或未知版本直接抛错。兼容规则见 `docs/EDL_SCHEMA.md`。
- 理由: EDL 是「决策」与「渲染」之间唯一的契约，两侧会独立迭代；没有版本号就没有办法安全升级。
- 后果: 任何字段变更必须同时改 `EDL_SCHEMA.md`、`CHANGELOG.md` 与 `ARCHITECTURE.yaml` 的 `schema_version_of_edl`。

## ADR-0004 先只做一条竖切片

- 状态: 已采纳
- 决策: 0.1.0 只实现「SRT 文本 → DeepSeek 主题完整切片 → EDL JSON」；ASR、渲染、UI、矩阵、Keychain 一律只在 ARCHITECTURE.yaml `planned` 段登记，不写空实现、不预埋协议。（1.0.0 起除矩阵外均已实现，见 ADR-0009；原则不变：每个文件仍需真实调用者。）
- 理由: 来自 math-anything 债务审计的直接教训：预埋的抽象与「以备将来」的模块会变成无人调用的僵尸代码（约 30% Sources）。每个文件必须有真实调用者；可替换性靠清晰模块边界 + 登记，而不是靠空接口。
- 后果: 守卫 01/04 强制「每个源文件有登记、有调用者、有同名测试」。

## ADR-0005 禁止 fallback

- 状态: 已采纳
- 决策: 任何上游失败（缺 API key、HTTP 非 2xx、LLM 输出不合法、时间范围非法）都以类型化错误向上抛出；没有 mock 数据、没有示例 EDL、没有「跳过坏条目继续」。Python 原版对 `start == end` 的占位条目静默跳过，这里改为报错。
- 理由: 静默降级会让 UI 展示「成功」的假象，并把错误埋在日志里；对切片产品而言，一条错的切片计划比失败更贵。
- 后果: 守卫 02 禁止 `try?` / `try!` / 空 `catch` / `?? 字面量`；例外需逐行 `// guard-allow: silent-fallback <理由>`。

## ADR-0006 0.1.0 不生成 iOS App target

- 状态: 已被 ADR-0009 取代（2026-09-07）
- 决策: 0.1.0 不用 xcodegen 生成 App target，SwiftUI 外壳保持 planned。
- 理由: 当前没有一个「粘贴 SRT → 显示 EDL」之外的真实入口需要 App 才能验证；生成一个空 App 就是制造僵尸 product。CLI `liveslice-cli` 已是 Core 的真实调用者。
- 后果: `swift test` 在 macOS 上是唯一必需的验证路径；iOS 平台声明保留在 Package.swift。

## ADR-0007 开源与 API Key 安全策略（BYOK 模式）

- 状态: 已采纳
- 决策: 采用 BYOK (Bring Your Own Key, 自带密钥) 模式开源。项目不内置、不代理任何开发者密钥，无中间代付网关。CLI 工具仅从当前 Shell 环境变量（`DEEPSEEK_API_KEY`）读取；App 仅通过 Keychain 存取（`APIKeyStore`，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）；仓库内置守卫 07 物理阻断密钥入库。
- 理由: 彻底消除开发者私有 Key 泄漏与代付账单风险，确保工具 100% 运行在用户本地端侧，数据与隐私不出用户信任域，契合纯端侧工具的开源定位。
- 后果: 开发者无托管与 Token 运营成本；用户需自行申请并配置 DeepSeek API Key。

## ADR-0008 切片策略通用化（默认通用题材）

- 状态: 已采纳
- 决策: 默认切片策略设为通用话题完整切片（`topic_complete + general`），提示词覆盖长视频、访谈、演讲、播客、知识科普、直播等多种通用场景。原 `military_news` 保留为可选预设领域策略，而非整个项目的硬编码绑定。
- 理由: 本项目定位为通用的端侧 AI 视频切片 Agent；军事题材是桌面端 `live_slice_auto` 遗留的垂直领域设定，将其从核心库中解耦为可选预设，使工具对通用视频创作场景具备通用可用性。
- 后果: `SlicingStrategy` 默认策略为 `.topicCompleteGeneral`（domain: `"general"`）；`TopicCompletePrompt` 依据传入的 `domain` 切换通用或领域特化提示词与分类；CLI 默认跑通用切片，支持 `--domain` 传参切换。

## ADR-0009 1.0.0 交付成品 App（取代 ADR-0006）

- 状态: 已采纳（2026-09-07），取代 ADR-0006
- 决策: 交付可上 TestFlight 的 iOS App「片刻」（内部 target `LiveSlice`，`com.jiajiali.liveslice`）：导入视频 → 端侧 ASR（SpeechAnalyzer / SpeechTranscriber）→ DeepSeek 主题完整切片 → AVFoundation 渲染成片（剪切、拼接、画幅适配、烧录字幕）→ 预览 / 分享 / 存相册。App target 用 xcodegen 由 `project.yml` 生成，`.xcodeproj` 不入库；App 代码只有一个 `@main` 文件，其余在 SwiftPM 的 `LiveSliceUI` 中，在 macOS 上编译与测试。
- 理由: 用户需要的是手机上能用的成品，不是 CLI；ADR-0006 拒绝「空 App」的理由在 ASR 与渲染真实存在后不再成立。每个新模块（ASR、Render、Keychain、UI）都有真实调用链（App → UI → 模块）与同名测试；ASR 与渲染的测试跑真实框架路径（`say` 合成语音 → SpeechAnalyzer；合成视频 → AVAssetExportSession，逐像素校验字幕），不打桩。
- 后果: 守卫 01/03/04/08 扫描范围扩展到 `App/`；`SubtitleRasterizer` 用 Core Text 光栅化字幕（CATextLayer (not used) 在导出渲染器里不出字）；`SourceInfo` 必须持有 `AVURLAsset`，否则导出报 -12780；模拟器没有语音识别能力（`recognizerUnavailable` 会直接显示），真机验证在 TestFlight。

## ADR-0010 结果优先的极简工作台与显式画幅选择

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 产品名改为「片刻 AI」（App Store 中「片刻」已被其他账号占用），桌面短名称保留「片刻」，内部 target `LiveSlice` 与既有 bundle ID 不变；界面采用深色、结果优先的极简 AI 工作台，不增加聊天框或虚构的 AI 控件。用户只选择视频、查看三个真实处理阶段、审核话题成片，并在导出前从「竖屏完整 / 竖屏满屏 / 原画比例」三种可验证画幅中选择。
- 理由: 对本产品而言，AI 价值是减少找片段和手工剪辑，而不是要求用户学习 Prompt。原先固定 9:16 居中裁切会丢失横屏两侧的人物、PPT 或分屏嘉宾；默认完整画面比猜测主体位置更可靠，满屏裁切仍作为明确选择保留。
- 后果: `RenderFraming` 穿过 UI → `SliceSession` → `SessionDependencies` → `ClipRenderer`；默认 `.portraitFit` 不裁内容，`.portraitFill` 保留旧的满屏行为，`.sourceAspect` 输出原画比例。Vision 主体跟踪没有在本次实现，不能在 UI 或文档中描述为已有。
- 补充（2026-09-07，用户选定）: 成片页对齐 practical workbench 效果图的骨架，而不是复述效果图上的说明文字。屏幕上只有：9:16 播放器、两位序号 + 标题、时长胶囊、短画幅分段、封面横滑、一个保存按钮。点标题打开只读剪辑依据。效果图里的「自动居中主播」等开关没有对应实现，不能画成已开启。主题色为冷蓝，保存按钮用绿色（效果图的主操作色），不用黄色。
- 字幕位置: 字幕带始终按输出画布底部内边距定位，并随输出尺寸等比缩放。竖屏完整模式下横屏素材的字幕因此落在画面下方的深色区，不遮挡任何原画内容；竖屏满屏与原画比例模式下字幕压在画面底部。三种画幅都有真实导出的像素测试（`ClipRendererTests`）。


## ADR-0011 先发布：动效、顺序预渲染与前台保活

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 在不新增功能的前提下，把"能用"做成"顺手"。（1）所有屏幕共用一条弹簧曲线，阶段切换交叉淡入；首页有漂移光晕和浮动标志，处理页用一个渐变进度环显示当前阶段的真实分数（LLM 调用没有分数就旋转）、真实已用时间和三段阶段条；成片页在导出时用该切片自己的首帧垫底并叠进度环，完成后交叉淡入到自动循环播放的单实例播放器；画幅是滑动胶囊，封面条逐张吸附、放大选中项并显示导出状态；保存在按钮内确认并伴随触感，不弹窗。（2）导出按 `RenderPlan` 顺序自动进行：屏幕上的切片优先，其余按序预渲染；切换画幅或切片会取消进行中的导出，被取消的导出回到 `.idle`（什么都没产出，不是失败）；另一画幅的成品显示为待生成，不冒充当前结果。（3）没有 Key 时首页唯一的按钮通向设置，不再让用户等完转写才收到 `missingAPIKey`。（4）会话工作期间屏幕常亮并持有 UIKit 后台任务（`ActivityKeeper`），处理页用一行字说明"保持打开"。（5）工作文件（导入源、抽出的音频、成品）从 Documents 移到 Caches，下一次开始和返回首页时清理，清理失败作为错误显示。
- 理由: 用户明确要求先发布、先有亮点、再改进。这些改动全部作用于真实状态：环上的分数来自 `SessionStage`，时钟来自 `startedAt`，垫底帧来自源视频，徽标来自 `renders`；没有任何一处用假动画替代真实进度。顺序预渲染让"切换切片"从等待十秒变成即时，是这一版最大的体感提升。前台保活是 iOS 上一个前台 App 能做的全部：语音识别和导出没有真正的后台模式，所以界面把这个限制说出来，而不是假装能后台处理。
- 后果: `ClipRenderState.done` 现在携带 `RenderFraming`；`SliceSession` 把 `CancellationError` 映射为 `.idle`，新增 `startedAt`、`hasRenderInFlight`、`isWorking` 和文件清理；`RenderPlan` 是纯函数并有测试。新增文件 `StudioTheme.swift`、`ProcessingView.swift`、`ClipPlayerView.swift`、`ActivityKeeper.swift`。模拟器上 `AVVideoCompositionCoreAnimationTool` 会触发 IOSurface xpc 断言（Apple 已知的仅模拟器问题），因此成片页的模拟器可视化验证使用不烧字幕的导出；字幕烧录仍由 macOS 上的 `ClipRendererTests` 逐像素验证，真机验证在 TestFlight。视觉验证脚手架（fixture 依赖 + XCUITest 走查）只存在于仓库之外的 `/tmp`，不进入代码库。

## ADR-0012 界面上没有一个字是多余的（禁止自我指涉文案）

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 界面文字只允许两类：动作标签（「选择视频」「保存到相册」）和真实状态值（「正在转写」「19秒」「已保存到相册」）。产品名、口号、欢迎语、对可见事物的解释、复述旁边数值的前缀标签（「标签：」「来源框架：」）一律不进界面。产品名只存在于 `project.yml` 的显示名和图标里。首页用一幅无字动画说明产品做什么：一条长胶片被切线扫过，三张 9:16 卡片从中升起。守卫 09 把这条规则变成机械检查。
- 理由: 用户指出首页的「片刻」二字"多余、难看、出戏"。多余，因为图标和桌面已经说了名字；难看，因为系统字体排出来的两个汉字撑不起一屏；出戏，因为它让用户从"我要剪视频"切换到"这是某个 App 在自我介绍"。这不是一处文案问题，而是一类：凡是让用户阅读却不改变其下一步操作的文字，都是同一种噪音。处理页阶段条下的「模型 / 转写 / 切片」重复了上方标题；成片页的「原22秒」不影响任何决定；依据页的「来源框架：样例框架」是内部术语。全部一起清掉。
- 后果: 新增 `scripts/guards/09_no_self_reference.sh`（DEBT_REGISTER 第 9 类）。`HomeView` 的 `AppMark` + 名字 + 口号替换为 `SliceMotif`；`ProcessingView` 阶段条不再带标签，提示缩为「请保持 App 打开」；`ClipListView` 只保留成片时长胶囊；`ClipDetailView` 去掉来源框架行，标签改为胶囊。以后想加一句说明文字之前，先问：它改变用户的下一步吗？不改变就不加。

## ADR-0015 项目化：每步落盘，重开即续（取代 ADR-0011 第 5 条中「返回首页即清理」）

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 每次导入的视频成为一个 `ProjectRecord`，存放在 Application Support/Projects/<id>/（`project.json` + 源视频，目录排除备份）。转写完成即写入 SRT 与 locale，切片完成即写入 EDL；`SliceSession.open` 从第一个未完成的步骤继续（已切片直接进成品页，已转写只跑 DeepSeek）。已导出的 MP4 按 `<clipID>.mp4`（ADR-0016 前为 `<clipID>-<framing>.mp4`）存放在 Caches/Renders/<projectID>/，重开时扫描恢复为「已导出」。首页在有项目时显示项目列表；滑动删除会一并删除源视频与导出。`reset` 只清理 scratch（抽出的音频），不再删源视频。
- 理由: 转写 + LLM 是分钟级工作，之前离开成品页或杀掉 App 就归零，用户每次都要从头来。转写结果对同一视频是稳定的，LLM 输出则有随机性且依赖网络与 Key——两者边界正好是天然的检查点。源视频保留在本地副本里是刻意选择：`PhotosPicker` 的临时文件不可回溯，安全作用域书签对相册项无效；用副本换取「随时可重开、可重导出」，代价是磁盘占用，用户可在列表里删除。
- 后果: 新增 `ProjectStore.swift`、`ProjectListView.swift`；`SessionResult` 携带 `projectID`；`SliceSession` 增加 `projects`、`open`、`delete`、`sourceURL(of:)`。源视频被系统外力删掉时报 `sourceMissing` 并停在失败页。导入失败前不会创建项目（缺 Key 时拾取文件原样留在 scratch）。存储占用尚未在 UI 中显示（planned）。

## ADR-0017 输入不变就不重做：视频指纹去重 + 每步记录来源

- 状态: 已采纳，已实现（2026-09-07）
- 决策: （1）导入时先算 `SourceFingerprint`（文件字节数 + 头/中/尾三个 8 MiB 窗口的 SHA-256，小文件整文件哈希），命中已有项目就删掉刚拷入的副本、直接打开那个项目，不新建。（2）`ProjectRecord` 为每一步的产物记录产生它的输入：`transcribedWith`（当时的 ASR 语言偏好）、`slicedWith`（模型 + 服务地址，故意不含 API Key）。`SliceSession.run` 按 `PipelineReuse` 判定：转写在「偏好相同」或「固定语言等于转写已有的语言」时沿用；切片在「转写沿用且模型/地址相同」时沿用；否则重跑该步及其后所有步骤，并删除该项目已导出的 MP4（新 EDL 会复用切片 id，旧文件会冒充新成品）。（3）没有来源字段的旧记录一律沿用。
- 理由: 转写按分钟计、DeepSeek 按 token 计费，同一个视频反复导入却每次从零跑，是最直接的资源浪费；而「设置变了还沿用旧结果」是另一种错误——用户换了模型却看到旧模型的切片。把输入记在产物旁边，两种错误都能用同一条规则避免。整文件哈希在两小时 4K 素材上会比导入本身更慢，三窗口采样在实际使用中不会把两个不同录像判成同一个，且任何重编码都会改变所有窗口。API Key 不进指纹：换 Key 不改变答案。
- 后果: 新增 `SourceFingerprint.swift`、`PipelineReuse.swift`；会话的值类型移到 `SessionTypes.swift`。`ProjectStore.adopt` 接受指纹。同一视频重新导入后落在已有项目上（列表不新增一行）；改模型后重开旧项目会重新调用 DeepSeek 一次并清掉旧导出；改语言设置为「自动」会重跑已用固定语言转写过的项目（自动检测可能选到别的语言，不能假定相同）。首页尚未提示「已识别为同一视频」（planned）。

## ADR-0026 Topicut 2.0：用户参与的切片偏好与可交互裁剪（方向决策）

- 状态: 已采纳，已实现（2026-09-10）
- 决策: 1.x 市场版冻结后，下一阶段产品重心从「全自动出片」转到「用户可参与」。（1）切片 / 金句：露出可理解的偏好旋钮（时长带、密度、风格/语气等），写入策略与提示词后显式「重新切片」，费用可见；不做静默重切。（2）裁剪：在 ADR-0025 自动跟人之外，允许拖移/捏合 9:16 窗口（或焦点），工作台预览立即跟几何，保存用同一窗口。（3）EDL 在 App 内可微调（trim/merge）——扩展既有 `EDL editing in app (planned)`，仍是客户端决策层。（4）Android / HarmonyOS 不在本仓库演进：ASR 与合成绑在 Speech + AVFoundation；云端 LLM 可移植，端侧链路需新客户端（`requires_new_architecture`）。
- 理由: 自动结果是好的起点，发片人仍要「按自己的味道」改；实时预览已由 ADR-0014/0025 铺好，缺的是把用户意图写回 EDL/画幅参数。跨端不是性能神话，是框架边界。
- 后果: 已实现 `SlicingTaste`（设置 + 工作台）、`CropOverride`/`CropFocusPad`（拖+捏）、草稿片头片尾裁切（滑条即时预览，应用才落盘）、`EDLClipMerge`（与下一条合并）。`PipelineReuse.sliceKey` 含 taste。语气/领域 UI、自由手绘裁剪窗仍 planned。
## ADR-0024 导出字幕样式：简洁 / 高亮词 / 无字幕，词级时间随转写保存

- 状态: 已采纳，已实现（2026-09-08；UI 于 Build 22 接入；Build 23 起试看叠字随选项实时刷新，并增加字幕位置 下/中/上）
- 决策: 转写不再只落 SRT：`TranscriptionOutcome` 带回 `SpeechTranscriber` 的逐词时间（`TimedToken`，移到 LiveSliceCore），项目目录里单独存为 `words.json`（不进 `project.json`，首页列表不解码它）。导出选项面板里：`CaptionStyle`（`clean` / `highlightWord` / `none`）决定试看叠字的样子，以及导出时是否烧录（`none` = 试看不叠、导出不烧）；`CaptionPosition`（`bottom` / `middle` / `top`）决定字幕带在画面上的位置，试看与烧录共用。选择都存在 defaults 里跨项目记住。导出文件名带样式与位置后缀（默认 clean+bottom 无后缀，老导出仍能识别）。`highlightWord` 的画面由同一份 Core Text 布局（`CaptionLayout`）出两种图：整条底图 + 每个词裁到字形的强调色小图；缺词是 typed error，不回落到普通字幕。旧项目的高亮词入口显示原因和一个「重新转写」按钮；`retranscribe` 只重跑语音识别。试看用 `PreviewCaptionPainter` 叠在播放器上，**不是**把字幕烧进预览帧——烧录只发生在「保存到相册」。工作台一个圆形选项按钮打开半屏面板（字幕样式 + 位置；画幅留给阶段 3）。
- 理由: 逐词高亮是竖屏短视频的通行字幕样式；词级时间本来就有，1.0 只是丢掉了。试看要实时看到当前选项，导出才决定是否烧进文件——两者共用同一套 look/position，但职责分开，后面才能在导出面板加更多调整而不绑架试看。位置用三档而不是自由拖拽，符合本 app「少操作」：一条选择对所有切片生效。按词裁小图、文件名带后缀、`nil` 词不降级，理由同前。
- 后果: `TimedToken`、`CaptionStyle`、`CaptionPosition`、`CaptionLayout`、`PlaybackCaptions` / `PreviewCaptionPainter` 新增；`RenderOptions` 带 style+position；`ClipRenderer.preview` 带回 plain/word 窗口供叠字；`SessionDependencies.render` 多 words、style、position；`AppSettings` 记住两者；导出名 `<clipID><styleSuffix><positionSuffix>.mp4`。

## ADR-0023 LLM 客户端与 JSON 提取移入共享包 LiJiaKit（LLMKit）

- 状态: 已采纳，已实现（2026-09-08）
- 决策: `DeepSeekClient`、`DeepSeekConfiguration`、`ChatMessage`、`LLMUsage`、`ChatCompletionResult` 以及 `LLMResponseParser` 里定位 JSON 对象、描述解码错误的两段逻辑（现为 `LLMJSON`）搬到独立的 SwiftPM 包 `LiJiaKit`（`~/Projects/LiJiaKit`，product `LLMKit`，iOS 17 / macOS 14）。本仓库通过 `.package(path: "../LiJiaKit")` 按本地路径依赖；上架时以 tag 锁版本。搬动原则：原样迁移、编译过、测试绿，不在搬的同时泛化——`LLMKit` 唯一新增的是 `responseFormat: .jsonObject` 可选参数，因为 Evident 的同名客户端一直在发这个字段，合并后它必须还能发。`LLMResponseParser` 只保留 EDL 形状与不变量，错误类型 `LLMResponseError` 不变（从 `LLMJSONError` 映射）。
- 理由: 同一份 OpenAI 兼容客户端在 liveslice 与 Evident 各写了一遍，「解析模型 JSON → 校验 → 报出缺哪个字段」在四个项目里写了四遍；bug 修四次、每次重新生成都要重新验证，这才是重复的真实成本。抽包的判断标准是「已经有两个以上调用者且带一套花过时间才跑绿的测试」，`DeepSeekClient` 与 JSON 提取都满足。本地路径依赖让一个人开发时改包、改 App 都不需要提交和打 tag；tag 只在某个 App 上架时打，维护中的 App 锁 tag 不主动升。
- 后果: `Sources/LiveSliceCore/DeepSeekClient.swift` 与其测试从本仓库删除，测试随代码迁到 `LiJiaKit/Tests/LLMKitTests`（19 个用例）；本仓库 gate 不重跑它们，改包后要在包目录另跑 `swift test`。引用这些类型的源文件与测试各加一行 `import LLMKit`。`ARCHITECTURE.yaml` 以 `kind: external_package` 登记 `../LiJiaKit/Package.swift`，守卫 01 因此会在包未检出时失败——这与 `swift build` 的失败一致，是想要的行为。后续按同一标准迁入的候选：MediaCore / MediaRender（本仓库的 SRT、Timecode、字幕烧录），OnDeviceML（hardlaw / my-vision / AgentEngine 的 MLX 注册与下载）。


## ADR-0029 切片/成片工作室手机化，工作台只做视觉剪辑

- 状态: 已采纳，已实现（2026-09-10；裁切/合并半屏 sheet 2026-09-11）
- 决策: （1）切片工作室与成片工作室改为手机优先全屏：大号状态/预览、卡片预设、横向 chip、底部主按钮；不做桌面 Form + 分段控件墙。（2）成片工作台主面只留预览、列表、保存；头尾裁切与合并从工具栏进半屏 sheet（草稿仍驱动上方试看，未应用关闭即丢弃）；切片与成片设置从工具栏全屏打开。（3）全局「设置」只留 AI 服务与语音；不再重复成片/切片偏好表单。
- 理由: 用户明确不要「Windows 软件搬到 App」的观感；常驻双滑条挤掉列表；两种设置既已独立，就不该混进切片后的视觉编辑。
- 后果: 删除 `ExportLookSettingsForm` 与工作台 `ExportLookStudioButton`/`SliceStudioButton` 行；`StudioChoice` 共用卡片/chip；`ClipEditSheet` 承接 trim/merge。

## ADR-0030 工作台外壳对齐效果图：主面只预览/列表/保存

- 状态: 已采纳，已实现（2026-09-12）
- 决策: 在不改 2.0 引擎（金句、成片样式、竖屏跟人、awaitingSlice、EDL 裁切/合并、LiJiaKit、taste 进 PipelineReuse）的前提下，把工作台外壳收成效果图的三层。（1）成片主面只有预览、话题/金句列表、保存到相册；工具栏只留裁切（剪刀）和成片样式（滑块）。裁切滑条、口味面板、竖屏拖点都不出现在主面。（2）EDL 裁切/合并是中大号半屏：胶片时间轴、≥44pt 手柄、与下一条合并、丢弃、完成。拖动手柄只改草稿预览；完成才写入 EDL；丢弃或下滑关闭丢掉草稿。（3）切片工作室仍是转写后、付费前的全屏门闩：三张密度卡 + 亮点长度 chips + 底部开始切片。工作台用话题栏溢出菜单重新打开，不再占第三个工具栏图标。（4）成片工作室主路径是预设卡 + 画幅 chips；自由旋钮和自然语言描述收进「高级」。手机竖屏拖点改在该工作室预览上操作。
- 理由: 用户锁定的效果图是干净主面 + 半屏裁切 + 切片工作室三卡。主面上堆叠工作室控件、裁切垫和内联口味，是把 2.0 能力做成了外壳噪音，而不是能力本身。
- 后果: `ClipListView` 主面不再挂 `CropFocusPad`；`ClipEditSheet` 改用 `TrimTimeline`/`TrimDraft`；`SliceStudio` 三卡对应 `TopicDensity`（条数仍按时长缩放，卡片不写死 3–5 条）；`ExportLookStudio` 默认不再露出调节/描述页。工作台 `ResultTabBar` 只有 话题|金句、用量和溢出「重新切片」，没有标题 chips（会和列表重复、也容易被看成「高亮词」标签）。守卫与 ADR 文化不变。

## ADR-0031 工作台玻璃工具钮、裁切半屏形变、费用行解析

- 状态: 已采纳，已实现（2026-09-13）
- 决策: 在 ADR-0030 外壳上对齐新的工作台效果图，不改媒体/EDL/ASR 引擎。（1）工具栏只留成片样式的圆形系统玻璃按钮（`glassEffect`）。导航栏不写产品名。长按预览打开 EDL 裁切半屏：画面上方清层接住触摸（AVKit 不再吞掉手势），约 0.2 秒变暗并出「裁剪」胶囊，约 0.48 秒打开半屏；预览下有一行弱提示「长按画面可裁剪」。VoiceOver 用无障碍动作「裁切与合并」。不再用剪刀图标。（2）半屏从预览 `matchedTransitionSource` + `navigationTransition(.zoom)` 形变；走系统玻璃，不再铺实色底。内容仍是胶片轴、≥44pt 手柄、与下一条合并、丢弃、完成——效果图底部的分割/插入/标记条不实现。（3）`LLMCost` 只取 `slicedWith` 的 baseURL 段（`model|baseURL|taste`），ISO8601 带小数秒也能解析；话题栏费用行让位于 话题/金句 固有宽度，有 `document.llm` 就显示 token，DeepSeek 官方价再跟 ¥。（4）手机与 iPad 主面切片列表都是纵向标题行。（5）导出遇到 `AVError.operationInterrupted`（-11847）：任务已取消则回 `.idle`；否则自动重试一次；仍失败再用中文「导出被中断，请再试一次。」。预览重建与导出经 `SourceMediaGate` 串行；该条 `.rendering` 时打开裁切半屏不拆预览。
- 理由: 效果图曾锁定玻璃剪刀钮，真机反馈是剪刀要人猜、不如长按预览。taste 写入 `sliceKey` 之后若把第一根 `|` 之后整段当 URL，`URL(string:)` 失败，真机上 ¥ 消失；实色 `presentationBackground` 会抹掉系统玻璃半屏。
- 后果: `LLMCost.endpointURLString` / `parseGeneratedAt` / `usageLine` 有单测。ResultTabBar 仍无标题 chips。高亮词预览安全路径不动。真机反馈后手机列表改回纵向标题行，不再用横向小卡片；剪刀工具钮已去掉。`-11847` 的 idle/重试映射在 `RenderInterruptTests`；导出与预览互斥在 `SourceMediaGateTests`。

## ADR-0028 转写后进入切片工作室，显式开始才调用 AI

- 状态: 已采纳，已实现（2026-09-10）
- 决策: （1）App 流水线在端侧 ASR 完成后停在 `SessionStage.awaitingSlice`，不自动发 DeepSeek。（2）「切片工作室」是独立全屏环境（预设 `SliceTastePreset` + 细调密度/金句时长），与「成片工作室」对称；工作台只留入口 sheet，不再内嵌整块偏好面板。（3）只有点「开始切片」或工作台确认重新切片（`confirmSlice` / `resliceFromTaste`）才计费；设置页的切片偏好只是默认值。（4）模型/口味变更导致 EDL 过期时同样进工作室，不静默重切。CLI 仍一次跑完（无 UI 门闩）。
- 理由: 切片设置增多后，转写与切片应拆开；用户要先定味道再付钱，与 ADR-0026「显式重切」一致。
- 后果: `HomeView` 增加 awaitingSlice 屏；`SliceSession.run` 在缺/过期 EDL 时写 `AwaitingSliceInfo` 并停住；happy-path 测试经 `startThroughSlice`。

## ADR-0027 成片工作室：预设标签 + 自由字幕旋钮 + 自然语言描述

- 状态: 已采纳，已实现（2026-09-10）
- 决策: （1）成片外观从右下角蜷缩按钮改为独立全屏「成片工作室」；工作台只留「成片样式」入口。（2）工作室主路径是固定预设标签（`LookPreset`）；同时提供自由旋钮：`CaptionTune`（bandY / fontScale / textHex / accentHex）与画幅 `sourceAspect | phonePortrait | portraitFit`。（3）「用一句话描述」经 DeepSeek 落到同一闭集 JSON（`LookDescribeParser`），失败即报错，不半套用。（4）工作室顶部用当前选中切片的 `ClipRenderer.preview`（与工作台同一路径）做效果预览，改选项即重建；失败即报错，不用黑底样板字顶替。
- 理由: 用户反馈导出设置变慢、变乱，且需要比三档位置更大的自由度；产品仍是切片工具，不是剪映——不做任意特效轨。预览必须是「这条切片会怎样」，黑框样板无法判断画幅/字幕是否贴片。
- 后果: `RenderOptions.captionTune`；`FramingMode.portraitFit`；`ExportLookStudio` + `LookStudioLivePreview`；全局设置里的简表仍可改默认。NL 描述会调用已配置的 AI 服务并计费。

## ADR-0022 一次切片调用同时输出完整话题与金句短片

- 状态: 已采纳，已实现（2026-09-08）
- 决策: 切片请求的输出增加第二个顶层数组 `highlights`：从全场挑出 20~90 秒、可独立传播的金句短片（条数按时长 2~4 / 4~8 / 6~12 / 10~20），与 `frameworks` 里的完整话题切片并列，互不替代。键必须存在（可为空数组），缺键即解析错误。EDL 新增可选字段 `highlights`、`highlight_policy`（schema 不升版）。工作台在原 token/费用那一行左侧放「话题 / 金句」两个胶囊切换列表，其余界面不变。1.0 切出的项目（`highlights == nil`）不自动重切：金句页只显示一句说明、上次费用与一个「重新切片」按钮，由用户决定是否再花钱；`SliceSession.reslice()` 只重跑切片步骤。
- 理由: 完整话题服务的是「发一条讲完了的内容」，金句服务的是「发一条钩子」，长视频用户两者都要（Opus Clip 一类产品只做后者）。同一份字幕已经在请求里，让模型在同一次输出里多给一组短片，增量只是几千个输出 token（两小时视频约 +0.05 元），而分成两次调用会让输入 token 翻倍。`nil` 与 `[]` 必须区分：前者是旧版本没问过，后者是模型认为没有值得单独发的句子；把前者悄悄当后者会让老用户以为功能坏了，自动重切又会在用户不知情时花钱。
- 后果: `HighlightCountPolicy`、`LLMSlices`、`ResultTabs.swift` 新增；`LLMResponseParser.parseClips` 改为 `parse` 返回两组；`TopicCompletePrompt.system` 多一个参数；highlights 的 id 规则与 clip 相同（`highlights_c_NN`），导出文件名随之，重开项目时两组导出都能恢复；CLI 摘要多打一行 highlights。live_check（3.6 分钟样例）实测 3 条话题 + 3 条金句，金句在短样例上偏短（6~19 秒），提示词已加「不足 20 秒向前后扩语境」，仍需在真实两小时素材上抽检。金句列表与话题列表共用保存、理由、播放逻辑，没有新增交互。

## ADR-0021 产品名 Topicut

- 状态: 已采纳，已实现（2026-09-08）
- 决策: 产品名改为 `Topicut`（Topic + cut），App Store 名称、桌面名称、站点、文档统一使用；不再有中文名或副名。内部 target `LiveSlice`、bundle ID `com.jiajiali.liveslice`、仓库名与 GitHub Pages 地址在送审当天保持不变——改动会让已提交的隐私政策 URL 失效。
- 补充（2026-09-08，送审后）: 用户决定把仓库改名为 `topicut-ios`（开源展示用，与产品名一致）。GitHub 对仓库地址与 git 操作自动跳转，但 **Pages 站点不跳转**；因此同一次改动里更新了 gh-pages 内的仓库链接，并通过 App Store Connect API 把隐私政策 / 支持 / 营销三个 URL 改到 `https://lijiaaaaa-bot.github.io/topicut-ios/…`（等待审核状态下这些字段可编辑，已验证返回 200）。旧地址 `…/liveslice-ios/` 从此 404。SwiftPM 包名 `liveslice-ios`（`Package.swift` / `project.yml`）仍不改：对用户不可见，改动只会触碰构建。
- 理由: 用户不接受 `LiveSlice`（像直播工具）与「片刻 AI」（既不表意，又带着 ADR-0011 清掉的那类自我介绍气味）。要求纯英文、可自造。候选在美区与中国区 App Store 检索后无同名：Topicut / Wholecut / Cutpoint / Segmenta / Seamly；选 Topicut 是因为它一眼说清产品动作「按话题切」，七个字母，可读可拼。
- 后果: 守卫 09 的产品名列表加入 `Topicut`；图标无文字，不需改。App Store Connect 的名称与描述中的产品名同步改为 Topicut。

## ADR-0020 切片请求显式关闭模型的思考模式

- 状态: 已采纳，已实现（2026-09-08）
- 决策: `DeepSeekClient` 的每个 chat/completions 请求都带 `"thinking": {"type": "disabled"}`（DeepSeek 方言）和 `"enable_thinking": false`（硅基流动 / 百炼的 Qwen 方言）。等待页在「正在找话题」下方说明：整段文字已发给哪个服务、通常多久、5 分钟无回复会报错（`SliceSession.slicingService`）。
- 理由: ADR-0018 把默认模型换成 `deepseek-v4-flash` 后，真机上出现「导入视频后一直正在找话题」。用官方接口复核：V4 系列默认开启思考模式且强度为 high，回复里带 `reasoning_content`；对 11 万 token 的转写文本，模型先推理数分钟、期间一个字节都不回，非流式请求看起来就是卡死，还会撞上 300 秒空闲超时；文档同时说明思考模式下 `temperature` 无效，而 `TopicSlicer` 依赖 0.3 的温度拿稳定 JSON。旧默认 `deepseek-chat`（V3）没有思考模式，所以 build 14 之前「两小时 1–2 分钟」成立。关掉思考模式后同一请求 prompt token 也少了（DeepSeek 在思考模式下会注入额外系统提示），费用更低。两个字段同时发而不是按域名分发：预设之外的自定义地址也可能挂着 V4 或 Qwen3，宁可让严格校验未知字段的服务器明确返回 400，也不让任何人再遇到无声的几分钟等待。
- 后果: 对 DeepSeek 官方接口实测两个字段都被接受。同一份 102 分钟、4 万 token 的转写文本：思考模式开着 89 秒、9,559 个推理 token；关掉后 4 秒、601 个输出 token（2026-09-08 实测；真实两小时内容的推理量只会更大）。OpenAI 官方接口会拒绝未知字段——它不在预设里（ADR-0018 已说明原因），需要的人得到的是带服务器原话的错误，不是挂起。切片质量走非思考路径，与 build 14 之前一致；若日后需要思考模式，应配合流式响应与进度显示一起引入，而不是单独打开。

## ADR-0019 成片页显示本次切片的 token 与费用；费用只在有官方价目表时显示

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 成片页舞台与切片表之间一行灰字：服务返回的总 token 数（所有 OpenAI 兼容服务都有），以及——仅当调用打到 `api.deepseek.com` 且模型在价目表中（v4-flash / v4-pro / 已退役别名 deepseek-chat）——按 DeepSeek 官方人民币价目估算的费用。估算规则：缓存命中 token（服务返回 `prompt_cache_hit_tokens` 时）按命中价，其余输入按未命中价，输出按输出价；北京时间周一至周五 9–12、14–18 为高峰，价格翻倍（用 EDL 的 `generated_at` 判定）。其他服务、未知模型、时间戳不可读时只显示 token，不显示任何价格。不到一分显示「不到 ¥0.01」。
- 理由: 用户自带密钥，钱是他的，每次切片花了多少应当看得见；token 数是服务器的事实，直接显示。价格不是事实而是估算，且只有 DeepSeek 官方价目在此可核对；对硅基流动、百炼或自定义代理编一个数字，比不显示更糟。价目表随 DeepSeek 调整需要人工更新，因此写在一处（`LLMCost`）并注明读取日期。
- 后果: `LLMUsage` 增加可选 `promptCacheHitTokens`（EDL 可选字段，不升版本）；`SessionResult` 携带 `slicedWith`；新增 `LLMCost.swift` 与测试。同一次同时修复：成片页播放无声——iOS 默认音频会话类别 `.soloAmbient` 受静音键控制，`ClipPlayerView` 播放前切到 `.playback / .moviePlayback`，激活失败在舞台上显示。

## ADR-0018 AI 服务按名字选，密钥仍由用户自带（补充 ADR-0007）

- 状态: 已采纳，已实现（2026-09-07）
- 决策: （1）界面上不再出现「DeepSeek Key」这种要求用户先懂术语的措辞；设置页第一项是「服务」选择器，预设 DeepSeek（默认）、硅基流动、阿里云百炼，加「自定义」。选预设即写入接口地址与默认模型（`AIServicePreset` / `AppSettings.apply`），两者仍可在「高级」里改；地址被改成预设之外的值时选择器显示「自定义」，不会被悄悄改回。选定预设后出现「在 X 创建密钥」链接直达该平台。（2）没有密钥时，首页在唯一按钮「连接 AI 服务」上方放三行事实：转写在手机上完成、只把文字发给所选服务、两小时视频约 0.2–0.5 元。（3）默认模型从已退役的别名 `deepseek-chat` 改为 `deepseek-v4-flash`（DeepSeek `/models` 已不再列出旧名）；`PipelineReuse.sliceKey` 把旧别名归一到新名，旧项目不因这次默认值变化而重新付费切片。（4）隐私清单声明「用户内容 → App 功能」（转写文字离开设备，去向是用户自己配置的服务，不关联身份、不用于追踪）。
- 理由: BYOK 是这个产品能不建后端、不收订阅的前提，但「去 DeepSeek 申请 sk- 开头的密钥」对普通用户是一道门。把门降到最低的办法不是内置开发者密钥（ADR-0007 已否决：会被滥用、成本不可控、审核上等同于隐藏付费），而是：名字代替地址、链接代替搜索、三行事实回答「视频会不会被上传」「要花多少钱」。费用估算来自 `live_check.sh` 的真实用量外推：3.6 分钟样例消耗 prompt 3454 / completion 1681 token，两小时约 11–12 万 prompt token、不到 1 万 completion token；按 DeepSeek V4 Flash 2026-08 起的公开价（输入 0.22–0.44 美元/百万、输出 0.66–1.32 美元/百万，谷/峰）一次切片约 0.03–0.06 美元，即 0.2–0.5 元人民币；价格会变，文案只给量级。没有 OpenAI 预设：其现行模型对本客户端固定发送的 `temperature` 参数的行为没有验证，且国内用户付款不便；需要的人用「自定义」。
- 后果: 新增 `AIServicePreset.swift`；`AppSettings` 增加 `servicePreset` 与 `apply(_:)`，UserDefaults 键名保留 `deepseek.*` 以读到旧值；`HomeView` 增加 `FirstRunGuide`；`SettingsView` 分区改名「AI 服务」。硅基流动与百炼两个预设按各平台文档的 OpenAI 兼容地址配置，未用真实密钥跑过；`scripts/live_check.sh` 只覆盖 DeepSeek。App Store 提交时：审核备注附开发者自己的测试密钥；隐私标签勾「用户内容 → App 功能」；因默认服务为 DeepSeek，首发不勾意大利。

## ADR-0025 可选手机竖屏画幅：Vision 人脸取景 + 成片样式分栏（部分取代 ADR-0016）

- 状态: 已采纳，已实现（2026-09-10）
- 决策: （1）默认仍是原比例（ADR-0016）；用户可在「成片样式」里显式选「手机竖屏」导出 1080×1920。该模式用 `VNDetectFaceRectanglesRequest` 在切片时间轴上取 5 帧，按脸面积加权定焦点，再取最大 9:16 窗口；**无人脸时居中裁切**——这是模式约定，不是 API 失败的静默降级。取帧或 Vision 失败抛 `FaceSamplerError`，导出停止。（2）预览与导出同几何：手机竖屏预览走 `videoComposition`，改画幅会重建播放器，保存前就能看到裁切。（3）文件名加 `-9x16`（及既有字幕后缀）。（4）成片样式默认写在全局「设置」里（`ExportLookSettingsForm`：画幅 / 字幕 / 位置）；成片页旁 sheet 只做对着当前画面的试看快捷入口，分段「画幅 | 字幕」，两边绑同一套 `AppSettings`。
- 理由: 发短视频时常要 9:16；横屏素材硬居中会切掉说话人。定点人脸采样比连续跟踪简单、可复现，够用。选项变多后，默认不应继续挤在导出旁浮层——用户明确要求把设置做成更好用的结构。
- 后果: 恢复 `VerticalFrame.fillTransform`；新增 `FramingMode` / `FaceFocus` / `FaceSampler`；`AppSettings.framingMode`；`SessionDependencies.render` 再带画幅参数。ADR-0016 的「只有原比例」被本条覆盖为「默认原比例，可选手机竖屏」。逐帧主体跟踪仍不在范围。

## ADR-0016 只有一种输出画幅：原视频比例（取代 ADR-0010 的三画幅选择）

- 状态: 已取代（部分）→ ADR-0025（2026-09-10）；原比例仍是默认
- 决策: 删除「竖屏完整 / 竖屏满屏 / 原画比例」选择。预览与导出都使用源视频自己的画幅比例，最长边不超过 1920（`RenderOptions.standard`）。`RenderFraming`、`FramingChoice`、`VerticalFrame.fillTransform` 与按画幅命名的导出文件一并删除；导出文件名改为 `<clipID>.mp4`。
- 理由: 本产品的价值是「从长视频里找出完整话题并切出来」，不是改画幅。竖屏满屏会裁掉横屏里的人物或 PPT，竖屏完整会把横屏画面缩在中间留大片黑边——两者都在替用户做他没提出的构图决定，且在成片页上占据一整行控件，与「少操作、少认知」的方向相反。首版按原画质、原比例切，是最不需要解释的行为；平台若要求竖屏，用户在发布工具里再裁。
- 后果: `SessionDependencies.render` 少一个参数；`ClipRenderState.done` 只携带 URL；成片页舞台按第一次预览得到的 `renderSize` 取比例（之前默认 16:9）。旧版本按 `<clipID>-<framing>.mp4` 导出的文件不再被识别为已导出（重开后会重新导出一次）。Vision 主体跟踪裁切仍是 `requires new architecture`，不在此列（定点人脸取景见 ADR-0025）。

## ADR-0014 成片页即点即播，导出只发生在保存时（取代 ADR-0011 第 2 条）

- 状态: 已采纳，已实现（2026-09-07）
- 决策: 选中任一切片时不再导出文件。`ClipRenderer.preview` 用与导出完全相同的 `AVMutableComposition`（剪切、拼接、画幅变换）生成 `AVPlayerItem` 直接交给播放器，字幕以 `SubtitleWindow`（合成时间轴）叠在播放器上随时钟刷新。写 MP4（含烧字幕）只在用户点「保存到相册」时进行，进度显示在按钮内；同一画幅已导出过的文件直接复用。删除 `RenderPlan` 与自动预渲染循环。
- 理由: 切片计划本身（转写 + LLM）对两小时视频只需 1–2 分钟，真正让用户等的是每条切片各自的 1080p 导出。原设计把「看一眼」和「产出文件」绑在一起，导致每点一条都出进度条，用户误以为「切」很慢、只能挑几条看。切片的产物是十几条完整话题，用户要能像翻相册一样逐条看完再决定保存哪些；导出是发布动作，不是浏览动作。
- 后果: 成片页的唯一等待是亚秒级的合成构建（用切片首帧垫底）。预览字幕是叠加层而非烧录（`animationTool` 仅导出可用），字号与导出略有差异，属可接受的已知偏差。预渲染取消后，切换切片/画幅不再触发任何导出，也不再占用 CPU/电量。`ClipRenderState` 只描述导出状态；列表行上的对勾表示「已导出」。原比例预览的 `AVPlayerItem` 不带 `videoComposition`：合成轨道携带源视频的 `preferredTransform`，由播放层缩放（2026-09-08 起；此前预览也走合成器，iOS 模拟器因像素格式不支持而黑屏/报错，真机正常）。手机竖屏（ADR-0025）预览必须带 `videoComposition`，否则舞台看不到 9:16 裁切。

## ADR-0013 语音语言自动识别（禁止用中文模型硬转英文）

- 状态: 已采纳，已实现（2026-09-07）
- 决策: ASR 默认偏好为 `auto`。转写前用同一 `SpeechAnalyzer` 并行跑 `zh_CN` 与 `en_US` 对片头约 12 秒的探测，按脚本匹配度（CJK 占比 vs 拉丁字母占比）选定 locale，再用该 locale 与对应的 `CueSegmenterPolicy`（中文 22 字/可逗号断句；英文 42 字符/不按逗号断句）跑全片。用户在设置里选定固定语言时跳过探测。探测与全片均在端侧完成。
- 理由: 英文音频喂给中文声学模型会产出乱码拉丁（`artifialelge`）；中文专属切句策略会把英文切成单词碎片。语言是输入属性，不是用户必须先配置的偏好；「自动」符合少操作原则，固定语言仍保留给刻意覆盖的场景。
- 后果: 新增 `ASRLocalePreference`、`SpeechLanguageDetector`；`SpeechTranscriptionService.transcribe(preference:)` 返回 `TranscriptionOutcome`；设置默认 `auto`；处理页在识别出语言后显示「正在转写 · 英语/中文」。探测为串行双模型 + 最多 90 秒滑动窗口，避免片头静音/音乐直接 `noSpeechDetected`。混语视频以首个有人声窗口为准（已知限制，不假装能做句级切语种）。
