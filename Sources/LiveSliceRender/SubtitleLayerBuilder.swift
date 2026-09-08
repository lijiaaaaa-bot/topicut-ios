// Why: burnt-in subtitles are part of the product (a vertical short without captions is not
// publishable). Core Animation layers timed on the composition clock are the only export-time
// overlay path AVFoundation offers; this file owns that layer tree and nothing else.

import AVFoundation
import Foundation
import QuartzCore

public struct SubtitleStyle: Sendable, Equatable {
    public let fontSize: CGFloat
    public let bottomInset: CGFloat
    public let horizontalInset: CGFloat
    public let strokeWidth: CGFloat

    public init(fontSize: CGFloat, bottomInset: CGFloat, horizontalInset: CGFloat, strokeWidth: CGFloat) {
        self.fontSize = fontSize
        self.bottomInset = bottomInset
        self.horizontalInset = horizontalInset
        self.strokeWidth = strokeWidth
    }

    /// Caption band height: room for two wrapped lines.
    public var bandHeight: CGFloat { ceil(fontSize * 2.8) }

    public func scaled(to renderSize: CGSize) -> SubtitleStyle {
        let scale = min(renderSize.width / 1080, renderSize.height / 1920)
        return SubtitleStyle(
            fontSize: fontSize * scale,
            bottomInset: bottomInset * scale,
            horizontalInset: horizontalInset * scale,
            strokeWidth: strokeWidth * scale
        )
    }

    /// Readable on a 1080×1920 frame: two lines of ~20 CJK characters above the lower UI zone.
    public static let vertical1080p = SubtitleStyle(fontSize: 58, bottomInset: 360, horizontalInset: 64, strokeWidth: -5)
}

enum SubtitleLayerBuilder {
    /// Builds the post-processing tool: video layer underneath, one timed caption layer per subtitle window.
    static func animationTool(
        windows: [SubtitleWindow], renderSize: CGSize, style: SubtitleStyle
    ) throws -> AVVideoCompositionCoreAnimationTool {
        let frame = CGRect(origin: .zero, size: renderSize)
        let parent = CALayer()
        parent.frame = frame
        let videoLayer = CALayer()
        videoLayer.frame = frame
        parent.addSublayer(videoLayer)
        for window in windows {
            parent.addSublayer(try captionLayer(for: window, renderSize: renderSize, style: style))
        }
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    private static func captionLayer(for window: SubtitleWindow, renderSize: CGSize, style: SubtitleStyle) throws -> CALayer {
        let width = renderSize.width - 2 * style.horizontalInset
        let height = style.bandHeight
        let layer = CALayer()
        // Core Animation's export coordinate space has its origin at the bottom-left; the inset is from the bottom.
        layer.frame = CGRect(x: style.horizontalInset, y: style.bottomInset, width: width, height: height)
        layer.contents = try SubtitleRasterizer.image(text: window.text, width: Int(width), height: Int(height), style: style)
        layer.contentsGravity = .resizeAspect
        layer.opacity = 0
        layer.add(visibility(from: window.start, to: window.end), forKey: "subtitle-visibility")
        return layer
    }

    /// Opacity 1 exactly during [start, end) on the composition clock; the model value 0 applies outside.
    private static func visibility(from start: Double, to end: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = start <= 0 ? AVCoreAnimationBeginTimeAtZero : start
        animation.duration = end - start
        animation.isRemovedOnCompletion = false
        animation.fillMode = .removed
        return animation
    }
}
