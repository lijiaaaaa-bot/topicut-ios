// Why: workbench preview opens EDL edit (ClipEditSheet), never 剪辑依据. AVKit VideoPlayer
// steals UIKit hit-testing even from a full overlay, so the player is not hit-testable and a
// SwiftUI layer owns tap/hold. A 裁剪 chip is the same action when the gesture still fails.

import SwiftUI

enum HoldToTrim {
    static let armAfter: TimeInterval = 0.20
    static let openAfter: TimeInterval = 0.48
    static let capsule = "裁剪"
    static let hint = "长按画面可裁剪"
    static let access = "裁切与合并"
    /// Full-stage `Color.clear` + `contentShape`; the player must not hit-test (`allowsHitTesting(false)`).
    static let sensorFillsStage = true
    /// `onComplete` / chip → `openClipEdit` → ClipEditSheet. Not `showRationale`.
    static let opensEditSheet = true
}

/// Play/pause hook so the hold overlay can keep a single tap working over VideoPlayer.
final class PlaybackControl: @unchecked Sendable {
    var toggle: () -> Void = {}
}

/// Dim + center capsule while the hold is armed.
struct HoldToTrimChrome: View {
    let armed: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(armed ? 0.28 : 0)
            if armed {
                Text(HoldToTrim.capsule)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.16), value: armed)
    }
}

/// Full-stage SwiftUI hit target. Used only after `ClipPlayerView` has `allowsHitTesting(false)`.
struct HoldToTrimSensor: View {
    var onTap: () -> Void
    var onArmed: () -> Void
    var onComplete: () -> Void
    var onCancel: () -> Void
    @State private var armTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(
                minimumDuration: HoldToTrim.openAfter,
                pressing: { down in handlePressing(down) },
                perform: {
                    armTask?.cancel()
                    armTask = nil
                    onComplete()
                }
            )
    }

    private func handlePressing(_ down: Bool) {
        armTask?.cancel()
        armTask = nil
        if down {
            armTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(HoldToTrim.armAfter))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                onArmed()
            }
        } else {
            onCancel()
        }
    }
}

/// On-preview alternate to long-press. Not a toolbar scissors icon.
struct HoldToTrimChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(HoldToTrim.capsule)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(HoldToTrim.capsule)
    }
}
