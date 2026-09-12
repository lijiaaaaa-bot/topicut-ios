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
        windows: [SubtitleWindow], renderSize: CGSize, style: SubtitleStyle, fill: CGColor? = nil
    ) throws -> AVVideoCompositionCoreAnimationTool {
        let (parent, videoLayer) = base(renderSize: renderSize)
        for window in windows {
            let layer = try bandLayer(renderSize: renderSize, style: style)
            layer.contents = try SubtitleRasterizer.image(
                text: window.text, width: Int(layer.bounds.width), height: Int(layer.bounds.height),
                style: style, fill: fill
            )
            show(layer, from: window.start, to: window.end)
            parent.addSublayer(layer)
        }
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    /// Word-highlight look: a backdrop caption layer per window, plus one small accent layer per
    /// word, cropped from the same layout and shown only while that word is spoken.
    static func animationTool(
        captions: [WordCaption], renderSize: CGSize, style: SubtitleStyle,
        fill: CGColor? = nil, accent: CGColor? = nil
    ) throws -> AVVideoCompositionCoreAnimationTool {
        let (parent, videoLayer) = base(renderSize: renderSize)
        for caption in captions {
            let band = try bandLayer(renderSize: renderSize, style: style)
            let width = Int(band.bounds.width), height = Int(band.bounds.height)
            let look: CaptionLook = .backdrop
            band.contents = try SubtitleRasterizer.image(
                text: caption.text, width: width, height: height, style: style, look: look, fill: fill
            )
            show(band, from: caption.start, to: caption.end)
            parent.addSublayer(band)
            for word in caption.words {
                let (image, frame) = try SubtitleRasterizer.wordImage(
                    text: caption.text, range: word.range, width: width, height: height, style: style, accent: accent
                )
                let accentLayer = CALayer()
                accentLayer.frame = frame.offsetBy(dx: band.frame.minX, dy: band.frame.minY)
                accentLayer.contents = image
                accentLayer.contentsGravity = .resize
                show(accentLayer, from: word.start, to: word.end)
                parent.addSublayer(accentLayer)
            }
        }
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    private static func base(renderSize: CGSize) -> (CALayer, CALayer) {
        let frame = CGRect(origin: .zero, size: renderSize)
        let parent = CALayer()
        parent.frame = frame
        let videoLayer = CALayer()
        videoLayer.frame = frame
        parent.addSublayer(videoLayer)
        return (parent, videoLayer)
    }

    /// The caption band: full width minus insets, `bandHeight` tall, `bottomInset` up from the bottom
    /// (Core Animation's export coordinate space has its origin at the bottom-left).
    private static func bandLayer(renderSize: CGSize, style: SubtitleStyle) throws -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: style.horizontalInset, y: style.bottomInset, width: renderSize.width - 2 * style.horizontalInset, height: style.bandHeight)
        layer.contentsGravity = .resizeAspect
        return layer
    }

    private static func show(_ layer: CALayer, from start: Double, to end: Double) {
        layer.opacity = 0
        layer.add(visibility(from: start, to: end), forKey: "subtitle-visibility")
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
