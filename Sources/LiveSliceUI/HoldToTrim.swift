// Why: long-press on the workbench preview opens EDL edit. AVKit VideoPlayer eats SwiftUI
// gestures, so a clear overlay owns tap (play/pause) and hold (arm 裁剪, then open). Copy is
// short so the hint does not become a banner.

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum HoldToTrim {
    static let armAfter: TimeInterval = 0.20
    static let openAfter: TimeInterval = 0.48
    static let capsule = "裁剪"
    static let hint = "长按画面可裁剪"
    static let access = "裁切与合并"
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

/// Full-stage hit target. iOS uses UIKit so VideoPlayer cannot swallow the hold.
struct HoldToTrimSensor: View {
    var onTap: () -> Void
    var onArmed: () -> Void
    var onComplete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        #if os(iOS)
        HoldToTrimHit(onTap: onTap, onArmed: onArmed, onComplete: onComplete, onCancel: onCancel)
        #else
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(
                minimumDuration: HoldToTrim.openAfter,
                pressing: { down in if down { onArmed() } else { onCancel() } },
                perform: onComplete
            )
        #endif
    }
}

#if os(iOS)
private struct HoldToTrimHit: UIViewRepresentable {
    var onTap: () -> Void
    var onArmed: () -> Void
    var onComplete: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HoldToTrimHitView {
        context.coordinator.bind(onTap: onTap, onArmed: onArmed, onComplete: onComplete, onCancel: onCancel)
        let view = HoldToTrimHitView()
        view.install(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: HoldToTrimHitView, context: Context) {
        context.coordinator.bind(onTap: onTap, onArmed: onArmed, onComplete: onComplete, onCancel: onCancel)
        uiView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void = {}
        var onArmed: () -> Void = {}
        var onComplete: () -> Void = {}
        var onCancel: () -> Void = {}
        var opened = false

        func bind(onTap: @escaping () -> Void, onArmed: @escaping () -> Void, onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onTap = onTap
            self.onArmed = onArmed
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            onTap()
        }

        @objc func arm(_ g: UILongPressGestureRecognizer) {
            if g.state == .began {
                opened = false
                onArmed()
            }
            if g.state == .ended || g.state == .cancelled, !opened { onCancel() }
        }

        @objc func open(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            opened = true
            onComplete()
        }
    }
}

private final class HoldToTrimHitView: UIView {
    weak var coordinator: HoldToTrimHit.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func install(_ coordinator: HoldToTrimHit.Coordinator) {
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        self.coordinator = coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(HoldToTrimHit.Coordinator.tap(_:)))
        let arm = UILongPressGestureRecognizer(target: coordinator, action: #selector(HoldToTrimHit.Coordinator.arm(_:)))
        arm.minimumPressDuration = HoldToTrim.armAfter
        arm.allowableMovement = 44
        arm.cancelsTouchesInView = true
        arm.delegate = coordinator
        let open = UILongPressGestureRecognizer(target: coordinator, action: #selector(HoldToTrimHit.Coordinator.open(_:)))
        open.minimumPressDuration = HoldToTrim.openAfter
        open.allowableMovement = 44
        open.cancelsTouchesInView = true
        open.delegate = coordinator
        tap.require(toFail: arm)
        tap.delegate = coordinator
        addGestureRecognizer(tap)
        addGestureRecognizer(arm)
        addGestureRecognizer(open)
    }
}
#endif
