// Why: rasterizer sample helper for caption-style unit tests (look studio uses live clip preview).

import CoreGraphics
import LiveSliceRender
import SwiftUI

struct CaptionSample: View {
    let style: CaptionStyle
    nonisolated static let sampleText = "先找话题 再动剪刀"
    nonisolated static let accentWord = 5..<9

    var body: some View {
        GeometryReader { proxy in
            let scale = 3.0
            switch Result(catching: { try Self.render(style: style, width: Int(proxy.size.width * scale), height: Int(proxy.size.height * scale)) }) {
            case .success(let image?):
                Image(decorative: image, scale: scale, orientation: .up)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            case .success(nil):
                EmptyView()
            case .failure(let error):
                Label(ErrorText.describe(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    nonisolated static func render(style: CaptionStyle, width: Int, height: Int) throws -> CGImage? {
        guard style != .none, width > 0, height > 0 else { return nil }
        let h = CGFloat(height)
        let sub = SubtitleStyle(fontSize: h * 0.13, bottomInset: h * 0.10, horizontalInset: CGFloat(width) * 0.05, strokeWidth: -h * 0.011)
        let bandWidth = width - Int(2 * sub.horizontalInset), bandHeight = Int(sub.bandHeight)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SubtitleRasterizerError.contextUnavailable }
        let band = CGRect(x: sub.horizontalInset, y: sub.bottomInset, width: CGFloat(bandWidth), height: CGFloat(bandHeight))
        let look: CaptionLook = style == .highlightWord ? .backdrop : .clean
        context.draw(try SubtitleRasterizer.image(text: sampleText, width: bandWidth, height: bandHeight, style: sub, look: look), in: band)
        if style == .highlightWord {
            let (word, frame) = try SubtitleRasterizer.wordImage(text: sampleText, range: accentWord, width: bandWidth, height: bandHeight, style: sub)
            context.draw(word, in: frame.offsetBy(dx: band.minX, dy: band.minY))
        }
        guard let image = context.makeImage() else { throw SubtitleRasterizerError.imageUnavailable }
        return image
    }
}
