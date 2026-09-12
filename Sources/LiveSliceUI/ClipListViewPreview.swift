// Why: preview build and save-to-photos for ClipListView — kept out so the layout file stays under the god-object line budget.

import LiveSliceCore
import LiveSliceRender
import SwiftUI

extension ClipListView {
    /// Instant preview for the shown clip (SwiftUI cancels on id change).
    func previewTaskID(_ clip: EDLClip) -> String {
        let focus = session.cropFocus(for: clip.id)
        let fx: String
        let fy: String
        if let focus {
            fx = String(format: "%.3f", focus.x)
            fy = String(format: "%.3f", focus.y)
        } else {
            fx = "auto"
            fy = "auto"
        }
        let zoom = String(format: "%.2f", session.cropZoom(for: clip.id))
        let draft = session.clipForPreview(clip)
        return "\(clip.id)-\(session.framingMode.rawValue)-\(session.captionStyle.rawValue)-\(session.captionTune.exportSuffix)-\(fx)-\(fy)-\(zoom)-\(draft.startSec)-\(draft.endSec)"
    }

    func buildPreview(result: SessionResult, clip: EDLClip) async {
        preview = .loading
        do {
            let playable = session.clipForPreview(clip)
            let built = try await ClipRenderer(
                options: .standard(
                    captionStyle: session.captionStyle, position: session.captionPosition,
                    tune: session.captionTune, framing: session.framingMode,
                    cropFocus: session.cropFocus(for: clip.id),
                    cropZoom: session.cropZoom(for: clip.id)
                )
            ).preview(sourceURL: result.sourceURL, clip: playable, cues: result.cues, words: result.words)
            guard !Task.isCancelled else { return }
            if built.renderSize.height > 0 { sourceAspect = built.renderSize.width / built.renderSize.height }
            preview = .ready(built)
        } catch is CancellationError {
        } catch {
            preview = .failed(ErrorText.describe(error))
        }
    }

    func exportAndSave(_ clip: EDLClip) async {
        isSaving = true
        defer { isSaving = false }
        if case .done(let url) = renderState(of: clip) {
            await save(url)
            return
        }
        await session.render(clip: clip)
        if case .done(let url) = renderState(of: clip) {
            await save(url)
        }
    }

    func save(_ url: URL) async {
        do {
            try await PhotoLibrarySaver.save(videoURL: url)
            saved = url
        } catch {
            saveError = ErrorText.describe(error)
        }
    }
}
