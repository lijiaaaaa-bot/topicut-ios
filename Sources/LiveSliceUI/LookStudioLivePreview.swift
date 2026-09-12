// Why: 成片工作室 must preview the selected clip's real cut, not a black CaptionSample card.
// Rebuilds with ClipRenderer.preview when look/framing/crop inputs change (same path as the workbench).

import LiveSliceCore
import LiveSliceRender
import SwiftUI

struct LookStudioLivePreview: View {
    let sourceURL: URL
    let clip: EDLClip
    let cues: [SRTCue]
    let words: [TimedToken]?
    let style: CaptionStyle
    let position: CaptionPosition
    let tune: CaptionTune
    let framing: FramingMode
    let cropFocus: CGPoint?
    let cropZoom: CGFloat

    @State private var preview: PreviewState = .loading
    @State private var aspect: CGFloat = 9 / 16

    var body: some View {
        ClipStage(
            preview: preview,
            aspect: aspectForStage,
            sourceURL: sourceURL,
            posterSeconds: clip.startSec,
            captionStyle: style,
            captionTune: tune,
            clipID: clip.id,
            cropFocus: cropFocus,
            cropZoom: cropZoom,
            showCropPad: false
        )
        .animation(StudioTheme.motion, value: framing)
        .task(id: rebuildKey) {
            await rebuild()
        }
    }

    private var aspectForStage: CGFloat {
        switch framing {
        case .sourceAspect: aspect
        case .phonePortrait, .portraitFit: 9 / 16
        }
    }

    private var rebuildKey: String {
        let fx: String
        let fy: String
        if let cropFocus {
            fx = String(format: "%.3f", cropFocus.x)
            fy = String(format: "%.3f", cropFocus.y)
        } else {
            fx = "auto"
            fy = "auto"
        }
        let zoom = String(format: "%.2f", cropZoom)
        return "\(clip.id)-\(framing.rawValue)-\(style.rawValue)-\(position.rawValue)-\(tune.exportSuffix)-\(fx)-\(fy)-\(zoom)-\(clip.startSec)-\(clip.endSec)"
    }

    private func rebuild() async {
        preview = .loading
        do {
            let built = try await ClipRenderer(
                options: .standard(
                    captionStyle: style, position: position, tune: tune, framing: framing,
                    cropFocus: cropFocus, cropZoom: cropZoom
                )
            ).preview(sourceURL: sourceURL, clip: clip, cues: cues, words: words)
            guard !Task.isCancelled else { return }
            if built.renderSize.height > 0 {
                aspect = built.renderSize.width / built.renderSize.height
            }
            preview = .ready(built)
        } catch is CancellationError {
        } catch {
            preview = .failed(ErrorText.describe(error))
        }
    }
}
