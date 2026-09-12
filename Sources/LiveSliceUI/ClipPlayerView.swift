// Why: the workbench plays a clip the moment it is selected — straight from the source through the
// same cut/concat composition the export uses — so nothing is written to disk until the user saves.
// One AVQueuePlayer lives as long as the stage and loops via AVPlayerLooper. Captions cannot be
// burnt into live playback (`animationTool` is export-only), so the overlay is drawn by the same
// SubtitleRasterizer the export uses (ADR-0024). A caption look error must not cover the video;
// only AVPlayer/looper failures use the full-stage overlay.

import AVFoundation
import AVKit
import LiveSliceRender
import SwiftUI

struct ClipPlayerView: View {
    let preview: ClipPreview
    let style: CaptionStyle
    let tune: CaptionTune
    let clipID: String
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var observer: Any?
    @State private var statusObservers: [NSKeyValueObservation] = []
    @State private var caption: PreviewCaptionFrame?
    @State private var captionKey = ""
    @State private var viewSize: CGSize = .zero
    @State private var playbackError: String?
    @State private var captionError: String?

    var body: some View {
        GeometryReader { proxy in
            VideoPlayer(player: player)
                .overlay(alignment: .bottom) { captionOverlay }
                .overlay(alignment: .top) { captionErrorBanner }
                .overlay { if let playbackError { PlaybackFailure(message: playbackError) } }
                .onAppear {
                    viewSize = proxy.size
                    load(preview)
                }
                .onChange(of: preview.playerItem) { _, _ in load(preview) }
                .onChange(of: style) { _, _ in paint(force: true) }
                .onChange(of: tune) { _, _ in paint(force: true) }
                .onChange(of: proxy.size) { _, size in
                    viewSize = size
                    paint(force: true)
                }
                .onDisappear { tearDown() }
        }
    }

    @ViewBuilder
    private var captionOverlay: some View {
        if let caption {
            let scale = caption.bandSize.width > 0 ? CGFloat(caption.image.width) / caption.bandSize.width : 1
            Image(decorative: caption.image, scale: scale)
                .resizable()
                .frame(width: caption.bandSize.width, height: caption.bandSize.height)
                .padding(.bottom, caption.bottomInset)
                .padding(.horizontal, caption.horizontalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func load(_ preview: ClipPreview) {
        tearDown()
        activateAudioOutput()
        let looper = AVPlayerLooper(player: player, templateItem: preview.playerItem)
        self.looper = looper
        statusObservers = [
            looper.observe(\.status, options: [.initial, .new]) { looper, _ in
                guard looper.status == .failed else { return }
                Task { @MainActor in report(looper.error, from: "循环器") }
            },
            player.observe(\.status, options: [.initial, .new]) { player, _ in
                guard player.status == .failed else { return }
                Task { @MainActor in report(player.error, from: "播放器") }
            },
            player.observe(\.currentItem?.status, options: [.initial, .new]) { player, _ in
                guard let item = player.currentItem, item.status == .failed else { return }
                Task { @MainActor in report(item.error, from: "切片合成") }
            },
        ]
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { _ in
            Task { @MainActor in paint(force: false) }
        }
        player.play()
        paint(force: true)
    }

    private func paint(force: Bool) {
        guard viewSize.width > 1, viewSize.height > 1 else { return }
        let seconds: Double
        if let item = player.currentItem { seconds = item.currentTime().seconds } else { seconds = 0 }
        do {
            let captions = try preview.captions(style: style, clipID: clipID)
            let key = Self.key(captions: captions, at: seconds, style: style, tune: tune)
            guard force || key != captionKey else { return }
            captionKey = key
            let next = try PreviewCaptionPainter.frame(
                captions: captions, at: seconds, tune: tune,
                renderSize: preview.renderSize, viewSize: viewSize
            )
            withAnimation(.easeOut(duration: 0.12)) { caption = next }
            captionError = nil
        } catch {
            captionError = ErrorText.describe(error)
            caption = nil
            captionKey = ""
        }
    }

    @ViewBuilder
    private var captionErrorBanner: some View {
        if let captionError {
            Text(captionError)
                .font(.caption2)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.55))
        }
    }

    /// Stable while the same cue (and spoken word, for highlight) is on screen — skips redraws.
    private static func key(
        captions: PlaybackCaptions, at seconds: Double, style: CaptionStyle, tune: CaptionTune
    ) -> String {
        let tuneKey = "\(tune.bandY)-\(tune.fontScale)-\(tune.textHex)-\(tune.accentHex)"
        switch captions {
        case .none:
            return "none|\(tuneKey)"
        case .plain(let windows):
            guard let window = windows.first(where: { seconds >= $0.start && seconds < $0.end }) else {
                return "\(style.rawValue)|\(tuneKey)|"
            }
            return "\(style.rawValue)|\(tuneKey)|\(window.start)|\(window.text)"
        case .words(let list):
            guard let caption = list.first(where: { seconds >= $0.start && seconds < $0.end }) else {
                return "\(style.rawValue)|\(tuneKey)|"
            }
            let word = caption.words.last(where: { seconds >= $0.start && seconds < $0.end })
            let wordStart: Int
            if let word { wordStart = word.range.lowerBound } else { wordStart = -1 }
            return "\(style.rawValue)|\(tuneKey)|\(caption.start)|\(wordStart)"
        }
    }

    private func activateAudioOutput() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            playbackError = "无法打开音频输出：\(ErrorText.describe(error))"
        }
        #endif
    }

    private func report(_ error: Error?, from stage: String) {
        let detail: String
        if let error { detail = ErrorText.describe(error) } else { detail = "未提供错误信息" }
        playbackError = "\(stage)无法播放这一条：\(detail)"
    }

    private func tearDown() {
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        statusObservers.forEach { $0.invalidate() }
        statusObservers = []
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        caption = nil
        captionKey = ""
        captionError = nil
        playbackError = nil
    }
}

private struct PlaybackFailure: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }
}
