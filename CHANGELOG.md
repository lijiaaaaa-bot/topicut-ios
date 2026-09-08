# Changelog

All notable changes to this project. Format: Keep a Changelog; versioning: SemVer.
EDL `schema_version` changes are listed under their own heading in each release.

## [Unreleased]

### Fixed
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
