# Changelog

All notable changes to this project. Format: Keep a Changelog; versioning: SemVer.
EDL `schema_version` changes are listed under their own heading in each release.

## [Unreleased]

### Changed
- Workbench `ResultTabBar` drops the horizontal clip-title chips. The row is 话题|金句, token/cost,
  and overflow 重新切片; clip titles stay in the list. Caption-style「高亮词」is not on this row.
- Workbench shell matches the approved 2.0 mockups (ADR-0030): main surface is preview / 话题·金句 /
  list / 保存到相册; toolbar is edit + look only. Phone-portrait crop leaves the stage (drag lives
  in 成片工作室). Edit is a medium/large sheet with ≥44pt `TrimTimeline` handles; **完成** writes
  the EDL, **丢弃** drops the draft. 切片工作室 is three density cards + 亮点 chips + sticky
  **开始切片** (workbench re-opens it from the tab overflow). 成片工作室 is preset + framing first;
  knobs and NL describe sit under **高级**.
- Workbench trim/merge move into a toolbar half-sheet (`ClipEditSheet`); main stack is preview /
  list / save only. Closing without applying the draft discards it.
- 成片工作室 preview uses the selected clip’s live `ClipRenderer.preview` (same path as the workbench),
  not a black card with `CaptionSample`.

### Fixed
- 成片样式「高亮词」no longer bricks the preview. Caption paint errors stay a small banner (video
  keeps playing). Selecting highlightWord / 竖屏跟人 · 高亮词 without word timings is refused —
  style stays `.clean` and the existing「重新转写」copy is shown. A single `wordRangeOutOfText`
  accent skip keeps the backdrop for that frame.
- Live preview captions (ADR-0024): the player overlay scales font to the on-screen band. Build 23
  used the full export font on a phone-sized band, so 高亮词 crops were empty and the stage showed
  `wordRangeOutOfText` instead of the clip.

### Added
- Phone-first 切片/成片工作室 + workbench purity (ADR-0029): card presets, chip rows, sticky CTA;
  look/slice settings leave the edit surface (toolbar icons only); Settings drops duplicate look/taste forms.
- Failure screens gain **分享错误** (`ErrorReport` + ShareLink): version/build + verbatim message for
  pasting into chat. TestFlight still only auto-uploads process crashes.
- 切片工作室 (ADR-0028): after on-device ASR the App stops at `awaitingSlice`; presets + density/span
  live in a dedicated studio; **开始切片** is the only paid call. Workbench taste panel replaced by a
  切片偏好 entry that confirms re-slice without discarding the EDL until then.
- 成片工作室 (ADR-0027): full-screen look studio (presets + free caption band/scale/colours +
  portraitFit letterbox + optional natural-language describe → closed JSON). Workbench entry is a
  labeled 成片样式 control, not a cramped corner sheet of ClipPoster cards.
- Topicut 2.0 participatory editing (ADR-0026): **切片偏好** (topic density + highlight span) with
  explicit 重新切片 via 切片工作室 (ADR-0028); drag **and pinch** the phone-portrait framing on the
  stage (or reset to Vision auto); live draft head/tail trim while sliding, then 应用裁切; **与下一条合并**.
  Taste is part of `PipelineReuse.sliceKey` so a preference change never silently reuses an old EDL.
- Phone-portrait export framing (ADR-0025): 成片样式 defaults live in **设置** (画幅 / 字幕 / 位置);
  the workbench sheet beside 保存到相册 is a live-preview shortcut, segmented **画幅 | 字幕**.
  画幅 offers 原比例 (default) or 手机竖屏 (1080×1920). Portrait mode samples faces with Vision
  across five frames of the clip and crops a 9:16 window around them; no face → centre crop
  (mode behaviour). Preview rebuilds with the same crop before 保存到相册. Exports gain a
  `-9x16` filename suffix. Frame/Vision failures stop the export with a typed error.
- Caption styles for export (ADR-0024): `clean` (the 1.0 look), `highlightWord` (backdrop per line,
  the spoken word in the accent colour, driven by word timings) and `none`. Word timings from
  SpeechTranscriber are now kept as `words.json` next to each project. The workbench round button
  opens export options: look cards plus caption position 下 / 中 / 上. The player shows the chosen
  look and position as a live overlay while you watch a clip; burning into the MP4 happens only on
  保存到相册 (`none` = no overlay and no burn). Exports are named
  `<clipID><styleSuffix><positionSuffix>.mp4`. Projects transcribed by 1.0 have no words: the
  highlight style is a typed error for them, never a silent fall-back. 重新转写 reruns speech only.
  The save button names any non-default look/position (保存到相册 · 高亮词 · 上).
- iPad workbench: two columns. Landscape keeps player, actions and the clip's rationale on the
  left and the 话题 / 金句 lists on the right; portrait puts the player on top and splits the rest.
  The rationale is always visible there, so rows lose the ⓘ. iPhone layout unchanged.
- Highlights (金句): the same slicing call now also returns 20–90 s quotable moments (ADR-0022).
  The workbench switches between 话题 and 金句 with two pills on the token/cost line; a project
  sliced by 1.0 shows a panel with the last call's cost and an explicit 重新切片 button instead of
  re-slicing on its own. Home rows read `N 话题 · M 金句 · date`. The wait screen says
  「正在找话题和金句」. Ships as 1.1.0 (21) to TestFlight.

### EDL
- Optional `highlights` (clip array, framework `highlights`, ids `highlights_c_NN`) and
  `highlight_policy` (`duration_minutes`, `min_highlights`, `max_highlights`, `min_seconds`,
  `max_seconds`), added 2026-09-08 without a schema bump (EDL_SCHEMA rule 2). Absent = written
  before the field existed; `[]` = the model found none.

### Changed
- The OpenAI-compatible chat client (`DeepSeekClient`, `LLMUsage`, …) and the LLM JSON extraction
  (`LLMJSON`) now come from the shared sibling package `LiJiaKit` (product `LLMKit`) via a local
  path dependency (ADR-0023). Wire behaviour is unchanged; `LLMResponseParser` keeps only the EDL
  shape and its invariants. Clone `LiJiaKit` next to this repo before building.
- Product name is `Topicut` (ADR-0021): App Store name, home-screen label, site and docs. Internal
  target `LiveSlice` and bundle ID `com.jiajiali.liveslice` are unchanged.
- GitHub repository renamed `liveslice-ios` → `topicut-ios`; the Pages site moved to
  `https://lijiaaaaa-bot.github.io/topicut-ios/` and App Store Connect URLs were updated (ADR-0021 addendum).

### Fixed
- A project sliced by build 13–14 (stored key `deepseek-chat|…`) no longer re-slices once after
  upgrading: the stored key is normalized through the alias table before comparison, not only the
  current one.
- Slicing no longer hangs on "正在找话题" for minutes. `deepseek-v4-flash` (the default since
  ADR-0018) thinks at high effort by default, which over a two-hour transcript means minutes of
  reasoning before the first byte; every request now sends `thinking: {type: disabled}` and
  `enable_thinking: false` (ADR-0020). The wait screen names the service the text went to and
  says what to expect while the spinner turns.
- Preview playback no longer goes through a video composition. The composition track carries the
  source's own transform and the player layer scales it, so the stage shows the decoded frames
  with no compositor pass; scaling to the 1920 cap and burning captions stay export-only. This
  also makes the stage play in the iOS simulator (which rejected the composition's pixel format).
- The app declares `zh-Hans` as its development language, so dates in the project list format the
  way the rest of the UI reads (`9月8日`, not `Sep 8`) on Chinese devices. The Photos "add" usage
  text says 成片 instead of the retired 竖版切片.
- Clips play with sound when the phone's ring/silent switch is on silent. The stage now puts the
  audio session into `.playback` / `.moviePlayback` before playing (the default `.soloAmbient`
  category is muted by the switch); a session failure is shown on the stage like any other
  playback failure.

### Added
- The workbench shows what the slicing call consumed, in one line above the clip table: the
  server's token count (`5,135 token`), and for calls to DeepSeek's own endpoint the estimated
  charge (`约 ¥0.01`, `不到 ¥0.01`) from DeepSeek's published CNY price sheet — cache-hit tokens at
  the hit rate when the server reported them, double at Beijing peak hours (Mon–Fri 9–12, 14–18).
  Other endpoints and unknown models show tokens only. ADR-0019.
- EDL `llm.prompt_cache_hit_tokens` (optional, no schema bump): kept when the server sends it.
  `SessionResult.slicedWith` carries the record's `model|baseURL` to the workbench.

### Changed
- ADR-0018: the AI service is chosen by name. Settings opens with a 服务 picker (DeepSeek by
  default, 硅基流动, 阿里云百炼, 自定义); picking a preset fills the endpoint and default model,
  both still editable under 高级, and a link to that service's key page appears next to the key
  field. The home screen without a key shows three facts (transcription stays on the phone, only
  text is sent to the chosen service, about 0.2–0.5 CNY for a two-hour video) above one button,
  连接 AI 服务. The default model moves from the retired alias `deepseek-chat` to
  `deepseek-v4-flash`; `PipelineReuse.sliceKey` treats the old alias as the new name, so projects
  sliced under the old default are not re-sliced. The privacy manifest now declares
  user content → app functionality (the transcript leaves the device for the user's own service).
- Playback failures are shown, verbatim, on the stage: a failed `AVPlayerItem`, `AVPlayerLooper`
  or `AVQueuePlayer` (KVO on `status`) and a failed preview build both display their error text
  where the video would have been, instead of a black frame or a bare warning icon. Selecting a
  row resets the stage to loading synchronously, so a new stage never starts by playing the
  previous clip.
- One output shape. The 完整 / 满屏 / 原画 framing control is gone; every clip is previewed and
  exported in the source video's own aspect ratio (longest edge capped at 1920), which is what
  "cut at original quality" means. `RenderFraming`, `FramingChoice` and the per-framing export
  file names (`<clipID>-<framing>.mp4`) are removed; exports are `<clipID>.mp4`.
- Opening a project sliced before the unique-clip-id rule relabels its clips
  (`EDLDocument.withUniqueClipIDs`) and saves the corrected EDL, so rows that could not be
  selected in earlier builds become selectable without re-running DeepSeek.
- Workbench: the horizontal poster strip (numbers only) is replaced by a vertical table of every
  clip with its full title, first frame, number, kept duration and export mark, under a
  capped-height player. All titles are readable without selecting anything; tapping the selected
  row opens its rationale. The separate numbered headline is gone.
- Clip ids stay unique when the model repeats a framework id: `NN` in `<framework_id>_c_<NN>` is
  now the ordinal among all slices sharing that framework id (was: restarted per block, which
  produced duplicate ids and made those clips unselectable in lists keyed by id).

### Added
- ADR-0017: no repeated work for unchanged inputs. Importing a video that already has a project
  (matched by `SourceFingerprint`: byte count + SHA-256 of three 8 MiB windows) discards the new
  copy and opens that project. Every saved transcript and EDL now records the inputs that produced
  it (`transcribedWith` = ASR preference, `slicedWith` = model + endpoint); on open, a step is
  reused only while those inputs are unchanged and is rerun - together with everything after it and
  with stale exports removed - when they changed. Records written before this keep their results.
- ADR-0015: projects. Every imported video becomes a `ProjectRecord` in Application Support
  (`project.json` + the source file, excluded from backup). The transcript is saved as soon as
  speech recognition finishes and the EDL as soon as slicing finishes, so a failed DeepSeek call
  or a killed app resumes at slicing instead of re-transcribing. The idle screen lists saved
  projects (first frame, first clip title, clip count + date, or the step still missing); tapping
  a sliced project opens the workbench immediately, tapping an unfinished one resumes it; swipe
  deletes the project, its source and its exports. Exports already on disk are shown as done on
  reopen. `reset` no longer deletes the imported source.
- ADR-0014: every clip plays the instant it is selected. `ClipRenderer.preview` hands the same
  cut/concat/framing composition the export uses to an `AVPlayerItem` instead of a file, and the
  player overlays captions from the clip's subtitle windows. The MP4 export (with burnt-in
  subtitles) now runs only when the user saves, with progress shown inside the save button.
  `RenderPlan` and the automatic pre-rendering loop are removed.
- Auto locale probes now slide past silent/music intros (up to 90s) and run zh/en sequentially for device reliability; `noSpeechDetected` shows a Chinese explanation.
- ADR-0013: automatic ASR locale. Default language is `auto`; a 12 s dual-model probe picks
  `zh_CN` or `en_US` before the full transcription. English uses a 42-character, no-comma
  subtitle policy. Settings still allow forcing a locale; the processing screen shows the
  resolved language once known.
- Three output framings: complete source frame inside a 9:16 canvas, edge-to-edge 9:16 crop, and
  source aspect ratio. Subtitle geometry scales with the resolved output size.
- Tests for complete-frame transforms, source-aspect size resolution, and real exports in both new
  framings that pixel-check the uncropped frame, the dark background, and burnt-in captions.

### Changed
- Product name is now `片刻 AI`, with the shorter home-screen label `片刻` (internal target and
  bundle ID remain `LiveSlice` and `com.jiajiali.liveslice`).
- Replaced the app icon with a high-resolution selected-moment mark: one amber portrait card picked
  from a long film strip.
- Rebuilt the SwiftUI flow around the practical workbench layout: pick-video idle screen, three
  short processing labels, then a 9:16 player, numbered title, duration pills, compact framing
  control, source-frame strip, and one save button. Explanatory copy was removed. The selected
  clip starts rendering without an extra "generate" lecture. Clip rationale stays behind a tap
  on the title.
- Theme accent is now a cool blue; amber/yellow is no longer used anywhere in the UI.
- Motion pass on every screen (ADR-0011): drifting glow backdrop and floating mark on the idle
  screen; a gradient progress ring with the real stage fraction, a real elapsed clock and three
  stage segments while processing; the workbench stage shows the clip's own first frame under a
  ring while it exports and cross-fades to a looping, autoplaying player; the framing control is a
  sliding pill; the clip strip snaps card-by-card, scales the selected card and shows export
  badges; the save button confirms in place (green, haptic) instead of an alert. Screens cross-fade
  on stage changes with one shared spring.
- Exports now run ahead in `RenderPlan` order — the clip on screen first, then the rest — so
  switching clips is instant once the strip has caught up. Changing framing or clip cancels the
  in-flight export; a cancelled export returns to `.idle` (nothing was produced), never `.failed`.
  A file rendered in another framing is shown as pending, not as the current result.
- First run: without a stored API key the only button on the idle screen opens Settings, so a
  run can no longer end in `missingAPIKey` after a wait.
- While the session works the screen stays awake and a UIKit background task covers brief app
  switches (`ActivityKeeper`); the processing screen says so in one line. There is still no true
  background execution for speech or export.
- Session work files (imported source, extracted audio, renders) moved from Documents to Caches
  and are purged at the start of the next run and on reset; a failed purge is shown as an error.
- Rationale sheet: medium/large detents, human-readable times (`00:12 → 00:22 · 10秒`), tags as
  chips, no "source framework" line.
- ADR-0012: the UI carries no product name, slogan, or restating label. The idle screen's mark,
  wordmark and tagline are replaced by `SliceMotif`, a wordless animation of a strip being cut into
  three vertical cards. Processing segments lost their duplicate labels; the workbench lost the
  "original duration" pill. New guard `09_no_self_reference.sh` fails the gate on the product
  name or slogan words inside user-visible strings.

## [1.0.0] — 2026-09-07

### Added
- iOS app `LiveSlice` (`com.jiajiali.liveslice`, iOS 26) for TestFlight: import a video from Photos or
  Files → on-device transcription → DeepSeek topic-complete slicing → per-clip 1080×1920 render with
  burnt-in subtitles → preview, share, save to Photos. App target generated by xcodegen from
  `project.yml` (`scripts/gen_project.sh`); ADR-0009 supersedes ADR-0006.
- `LiveSliceASR`: `SpeechTranscriptionService` (SpeechAnalyzer / SpeechTranscriber, locale model
  download with progress), `AudioExtractor` (video → m4a), `CueSegmenter` (timed tokens → subtitle cues).
- `LiveSliceRender`: `ClipRenderer` (cut, concat, centre-crop to 9:16, export with progress),
  `ClipTimeline` (source ↔ output time mapping), `VerticalFrame` (orientation-aware fill transform),
  `SubtitleRasterizer` + `SubtitleLayerBuilder` (Core Text captions timed on the composition clock).
- `LiveSliceKeychain`: `APIKeyStore` — the DeepSeek key lives only in the Keychain on device.
- `LiveSliceUI`: SwiftUI screens (Home, ClipList, ClipDetail, Settings) and `SliceSession`
  state machine with injectable dependencies; `AppSettings`; `PhotoLibrarySaver`.
- `LiveSliceCore.SRTWriter`: cues → SRT text (round-trips through `SRTParser`).
- `LiveSliceTestSupport.SyntheticMedia`: test-time media synthesis (video, tone, `say` speech) so
  ASR and render tests exercise the real frameworks without binaries in git.
- Guards 01/03/04/08 now also scan `App/`.

### Changed
- Generalized topic-complete slicing: default strategy changed to `topic_complete + general` with a
  domain-agnostic prompt covering speeches, podcasts, interviews, lectures, and knowledge videos.
  `TopicCompletePrompt` and `SlicingStrategy` now support domain customization while preserving
  `military_news` as an optional preset (ADR-0008).
- `liveslice-cli` supports an optional `--domain <domain>` argument (defaults to `general`).
- BYOK (Bring Your Own Key) open source model formalized with MIT License (`LICENSE`),
  explicit security documentation in `README.md`, and ADR-0007 in `docs/DECISIONS.md`.
- `LLMUsage` (model, prompt/completion/total tokens, latency_ms) returned by `DeepSeekClient` and
  stored in the EDL as optional `llm`; a DeepSeek response without `usage` is now an error.
  `liveslice-cli` prints a `tokens:` line. Cost baseline for prompt/model iteration.
- `EDLClip` invariants: removed segments must lie inside the clip and never overlap kept segments
  (`removedSegmentOutsideClip`, `removedOverlapsKept`). Whole run fails; no trimming.
- Prompt rule: `removed_segments` only records gaps inside the slice, not content outside it.

### EDL schema
- `schema_version` stays 1: `llm` is an optional addition (see `docs/EDL_SCHEMA.md` rule 2).
  Documents without `llm` decode with `nil`.

## [0.1.0] — 2026-09-06

### Added
- `LiveSliceCore` (Swift package, iOS 26 / macOS 26): `Timecode`, `SRTParser`, `SlicingStrategy`
  (`topic_complete + military_news` default with duration-adaptive clip counts),
  `TopicCompletePrompt` (ported from live_slice_auto), `DeepSeekClient` (URLSession, key only from
  `DEEPSEEK_API_KEY`), `LLMResponseParser`, `EDLClip`, `EDLDocument`, `TopicSlicer`.
- `liveslice-cli slice <srt> [--out edl.json]` — the real caller of the core.
- 46 offline unit tests (Swift Testing); no network in tests.
- Debt guards `scripts/guards/01…08` and `scripts/gate.sh`; pre-commit hook installer.
- Docs: `ARCHITECTURE.yaml`, `DEBT_REGISTER.md`, `DECISIONS.md` (ADR-0001…0006), `EDL_SCHEMA.md`.

### EDL schema
- `schema_version` 1 introduced. See `docs/EDL_SCHEMA.md`.
