// Why: long-press on the workbench preview opens EDL edit (ClipEditSheet), never 剪辑依据.
// AVKit VideoPlayer eats SwiftUI gestures, so a clear overlay owns tap and one hold. The
// UIViewRepresentable has no intrinsic size — it must fill the stage or touches miss it.

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
    /// Sensor + hit view must expand; a ZStack UIViewRepresentable otherwise lays out ~0×0.
    static let sensorFillsStage = true
    /// `onComplete` is `openClipEdit` → ClipEditSheet (trim/merge). Not `showRationale`.
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

/// Full-stage hit target. iOS uses one UIKit long-press so VideoPlayer cannot swallow it.
struct HoldToTrimSensor: View {
    var onTap: () -> Void
    var onArmed: () -> Void
    var onComplete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        #if os(iOS)
        HoldToTrimHit(onTap: onTap, onArmed: onArmed, onComplete: onComplete, onCancel: onCancel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        #else
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        uiView.pinToSuperview()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HoldToTrimHitView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void = {}
        var onArmed: () -> Void = {}
        var onComplete: () -> Void = {}
        var onCancel: () -> Void = {}
        var opened = false
        var openTimer: Timer?

        deinit { openTimer?.invalidate() }

        func bind(onTap: @escaping () -> Void, onArmed: @escaping () -> Void, onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onTap = onTap
            self.onArmed = onArmed
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            false
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, !opened else { return }
            onTap()
        }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                opened = false
                onArmed()
                scheduleOpen()
            case .ended, .cancelled, .failed:
                cancelHold()
            default:
                break
            }
        }

        private func scheduleOpen() {
            openTimer?.invalidate()
            let remain = HoldToTrim.openAfter - HoldToTrim.armAfter
            openTimer = Timer.scheduledTimer(withTimeInterval: remain, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.opened = true
                self.openTimer?.invalidate()
                self.openTimer = nil
                self.onComplete()
            }
        }

        private func cancelHold() {
            openTimer?.invalidate()
            openTimer = nil
            if !opened { onCancel() }
        }
    }
}

/// Clear hit view pinned to the SwiftUI host. Without this, the representable is often 0×0.
private final class HoldToTrimHitView: UIView {
    weak var coordinator: HoldToTrimHit.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
        isAccessibilityElement = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        pinToSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pinToSuperview()
    }

    func pinToSuperview() {
        guard let superview else { return }
        if bounds.size != superview.bounds.size || frame.origin != .zero {
            frame = superview.bounds
        }
    }

    func install(_ coordinator: HoldToTrimHit.Coordinator) {
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        self.coordinator = coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(HoldToTrimHit.Coordinator.tap(_:)))
        tap.delegate = coordinator
        // One long-press: .began at armAfter shows 裁剪; a timer on that same recognizer opens edit.
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(HoldToTrimHit.Coordinator.hold(_:)))
        hold.minimumPressDuration = HoldToTrim.armAfter
        hold.allowableMovement = 44
        hold.cancelsTouchesInView = true
        hold.delegate = coordinator
        addGestureRecognizer(tap)
        addGestureRecognizer(hold)
    }
}
#endif
