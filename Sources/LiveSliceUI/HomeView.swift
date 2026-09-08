// Why: the single screen that drives the pipeline — pick a video, watch the real stages, then
// hand over to the clip workbench. Screens cross-fade on the coarse stage so progress ticks never
// re-trigger a transition. Without an API key the screen shows the three facts behind BYOK and one
// button that leads to Settings, so the first run cannot end in `missingAPIKey` after a wait.

import PhotosUI
import SwiftUI

struct HomeView: View {
    @Bindable var session: SliceSession
    @Bindable var settings: AppSettings
    let openSettings: () -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var showImporter = false
    @State private var importError: String?

    private enum Screen: Equatable { case idle, processing, ready, failed }

    private var screen: Screen {
        switch session.stage {
        case .idle: .idle
        case .preparingModel, .transcribing, .slicing: .processing
        case .ready: .ready
        case .failed: .failed
        }
    }

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()
            switch screen {
            case .idle:
                pickerScreen.transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .processing:
                ProcessingView(session: session).transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .ready:
                ClipListView(session: session).transition(.opacity.combined(with: .move(edge: .bottom)))
            case .failed:
                if case .failed(let message) = session.stage { failureScreen(message).transition(.opacity) }
            }
        }
        .animation(StudioTheme.motion, value: screen)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
            handleImport(result)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            if let importError { Text(importError) }
        }
    }

    /// Empty library: the motif fills the screen. With projects: a smaller motif, then the list.
    private var pickerScreen: some View {
        ZStack {
            GlowBackdrop()
            VStack(spacing: 0) {
                if session.projects.isEmpty {
                    Spacer()
                    SliceMotif()
                        .frame(height: 260)
                    Spacer()
                } else {
                    SliceMotif()
                        .frame(height: 150)
                        .padding(.top, 8)
                    ProjectListView(session: session, sourceURL: session.sourceURL(of:))
                        .padding(.horizontal, -28)
                        .transition(.opacity)
                }
                if settings.apiKey.isEmpty {
                    FirstRunGuide()
                        .padding(.bottom, 18)
                    Button("连接 AI 服务", action: openSettings)
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .videos) {
                        Label("选择视频", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("从文件导入") { showImporter = true }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .animation(StudioTheme.motion, value: session.projects.isEmpty)
    }

    private func failureScreen(_ message: String) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(StudioTheme.muted)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .studioCard()
            Spacer()
            Button("重新选择") { session.reset() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        do {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                importError = "相册项目不包含可导出的视频文件"
                return
            }
            pickerItem = nil
            await session.start(sourceURL: video.url)
        } catch {
            pickerItem = nil
            importError = ErrorText.describe(error)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let copied = try PickedVideo.copyIntoScratch(url)
            Task { await session.start(sourceURL: copied) }
        } catch {
            importError = ErrorText.describe(error)
        }
    }
}

/// Shown only while no key is stored. Three facts that decide whether the user goes to get a key:
/// where the video stays, what leaves the phone, and what it costs (DeepSeek V4 Flash list price;
/// a two-hour transcript with prompt is roughly 115k tokens, extrapolated from live_check — ADR-0018).
private struct FirstRunGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("iphone", "转写在手机上完成，视频不上传")
            row("text.bubble", "只把文字发给你选的 AI 服务")
            row("chineseyuanrenminbisign.circle", "两小时视频约 0.2–0.5 元")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// The idle screen says what the app does without a word: a long, dim strip (the source video)
/// is swept by a cut line, and three bright 9:16 cards rise out of it. No name, no tagline —
/// the promise is the picture, the button is the instruction.
private struct SliceMotif: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 4) / 4 // 0…1 every four seconds
            GeometryReader { proxy in
                let w = proxy.size.width
                let stripWidth = min(300, w * 0.82)
                let stripHeight: CGFloat = 54
                let cardWidth: CGFloat = 58
                let cardHeight = cardWidth * 16 / 9
                let gap: CGFloat = 16
                let cardsWidth = cardWidth * 3 + gap * 2
                let centerX = w / 2
                let stripY = proxy.size.height * 0.72
                let cardsY = proxy.size.height * 0.3

                ZStack {
                    // The source: one long strip with sprocket holes.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StudioTheme.raised)
                        .overlay {
                            HStack(spacing: 10) {
                                ForEach(0..<9, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.10)).frame(width: 14, height: 8)
                                }
                            }
                        }
                        .frame(width: stripWidth, height: stripHeight)
                        .position(x: centerX, y: stripY)

                    // The cut line sweeping the strip.
                    Capsule()
                        .fill(StudioTheme.accentGradient)
                        .frame(width: 3, height: stripHeight + 26)
                        .shadow(color: StudioTheme.cyan.opacity(0.9), radius: 10)
                        .position(x: centerX - stripWidth / 2 + stripWidth * Self.ease(cycle), y: stripY)

                    // Three vertical cards, each lifting a little later than the last.
                    ForEach(0..<3, id: \.self) { index in
                        let phase = Self.lift(cycle, index: index)
                        let x = centerX - cardsWidth / 2 + cardWidth / 2 + CGFloat(index) * (cardWidth + gap)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(StudioTheme.accentGradient)
                            .overlay(alignment: .bottom) {
                                Capsule().fill(Color.white.opacity(0.85)).frame(width: cardWidth * 0.55, height: 4).padding(.bottom, 12)
                            }
                            .frame(width: cardWidth, height: cardHeight)
                            .shadow(color: StudioTheme.accent.opacity(0.45 * phase), radius: 18, y: 10)
                            .opacity(0.35 + 0.65 * phase)
                            .scaleEffect(0.86 + 0.14 * phase)
                            .position(x: x, y: cardsY + (1 - phase) * 34)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Smooth 0→1 sweep with a short hold at the end so the eye reads it as one cut per cycle.
    private static func ease(_ cycle: Double) -> CGFloat {
        let p = min(1, cycle / 0.7)
        return CGFloat(p * p * (3 - 2 * p))
    }

    /// Card `index` rises once the cut line has passed its third of the strip, and settles.
    private static func lift(_ cycle: Double, index: Int) -> CGFloat {
        let start = 0.12 + Double(index) * 0.2
        let p = min(1, max(0, (cycle - start) / 0.28))
        let settle = cycle > 0.9 ? (1 - (cycle - 0.9) / 0.1) : 1
        return CGFloat(p * p * (3 - 2 * p)) * CGFloat(max(0, settle))
    }
}
