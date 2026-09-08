// Why: the workbench plays a clip the moment it is selected — straight from the source through the
// same cut/concat/framing composition the export uses — so nothing is written to disk until the
// user saves. One AVQueuePlayer lives as long as the stage and loops via AVPlayerLooper; the
// subtitle overlay follows the player clock because captions cannot be burnt into live playback.
// The audio session is switched to `.playback` before the first play: the default `.soloAmbient`
// obeys the ring/silent switch, which is why a clip could play with no sound at all.

import AVFoundation
import AVKit
import LiveSliceRender
import SwiftUI

struct ClipPlayerView: View {
    let preview: ClipPreview
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var observer: Any?
    @State private var statusObservers: [NSKeyValueObservation] = []
    @State private var caption = ""
    /// A player, item or looper failure, verbatim. A black frame with no words is not acceptable.
    @State private var playbackError: String?

    var body: some View {
        VideoPlayer(player: player)
            .overlay(alignment: .bottom) { captionView }
            .overlay { if let playbackError { PlaybackFailure(message: playbackError) } }
            .onAppear { load(preview) }
            .onChange(of: preview.playerItem) { _, _ in load(preview) }
            .onDisappear { tearDown() }
    }

    @ViewBuilder
    private var captionView: some View {
        if !caption.isEmpty {
            Text(caption)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func load(_ preview: ClipPreview) {
        tearDown()
        activateAudioOutput()
        let subtitles = preview.subtitles
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
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [player] _ in
            // The looper swaps items at the loop point; the player's own clock is not the clip's.
            guard let item = player.currentItem else { return }
            let seconds = item.currentTime().seconds
            let next: String
            if let window = subtitles.first(where: { seconds >= $0.start && seconds < $0.end }) {
                next = window.text
            } else {
                next = "" // between cues there is nothing to show
            }
            if next != caption { withAnimation(.easeOut(duration: 0.12)) { caption = next } }
        }
        player.play()
    }

    /// Movie playback that ignores the silent switch and pauses other apps' audio while a clip plays.
    /// macOS has no audio session. A failure is shown on the stage like any other playback failure.
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
        if let error {
            detail = ErrorText.describe(error)
        } else {
            detail = "未提供错误信息" // AVFoundation reported .failed without an NSError
        }
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
        caption = ""
        playbackError = nil
    }
}

/// The exact failure, on the stage, where the video would have been.
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
