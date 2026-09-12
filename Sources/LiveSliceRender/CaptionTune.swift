// Why: ADR-0027 free caption knobs — vertical band position, font scale, text/accent colours —
// must be one Codable value shared by the 成片工作室, live overlay, and burn-in. Invalid hex is a
// typed error, never a silent default colour.

import CoreGraphics
import Foundation

public enum CaptionTuneError: Error, Equatable, Sendable, LocalizedError {
    case invalidHex(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHex(let raw): "无效的颜色值（\(raw)）"
        }
    }
}

/// Free caption geometry and colours on top of CaptionStyle (look) (ADR-0027).
public struct CaptionTune: Codable, Equatable, Sendable {
    /// 0 = classic lower-third (bottom), 1 = classic top. Clamped on init.
    public var bandY: Double
    /// Multiplier on the scaled SubtitleStyle font. Clamped to 0.6…1.8.
    public var fontScale: Double
    /// Fill colour as RRGGBB (no #).
    public var textHex: String
    /// Highlight-word accent as RRGGBB.
    public var accentHex: String

    public static let standard = CaptionTune(bandY: 0, fontScale: 1, textHex: "FFFFFF", accentHex: "FFD60A")

    public init(bandY: Double, fontScale: Double, textHex: String, accentHex: String) {
        self.bandY = min(1, max(0, bandY))
        self.fontScale = min(1.8, max(0.6, fontScale))
        self.textHex = textHex.uppercased()
        self.accentHex = accentHex.uppercased()
    }

    /// Maps the three fixed positions onto bandY so old UI and free sliders share one path.
    public static func from(position: CaptionPosition) -> CaptionTune {
        let y: Double
        switch position {
        case .bottom: y = 0
        case .middle: y = 0.5
        case .top: y = 1
        }
        return CaptionTune(bandY: y, fontScale: 1, textHex: "FFFFFF", accentHex: "FFD60A")
    }

    public var exportSuffix: String {
        var parts: [String] = []
        if abs(bandY) > 0.02 { parts.append("y\(Int((bandY * 100).rounded()))") }
        if abs(fontScale - 1) > 0.02 { parts.append("s\(Int((fontScale * 100).rounded()))") }
        if textHex != "FFFFFF" { parts.append("t\(textHex)") }
        if accentHex != "FFD60A" { parts.append("a\(accentHex)") }
        return parts.isEmpty ? "" : "-" + parts.joined(separator: "-")
    }

    public func style(from base: SubtitleStyle = .vertical1080p, renderSize: CGSize) -> SubtitleStyle {
        let scaled = base.scaled(to: renderSize)
        let font = scaled.fontSize * fontScale
        let tuned = SubtitleStyle(
            fontSize: font,
            bottomInset: scaled.bottomInset,
            horizontalInset: scaled.horizontalInset,
            strokeWidth: scaled.strokeWidth * fontScale
        )
        let low = scaled.bottomInset
        let high = max(low, renderSize.height - tuned.bandHeight - scaled.bottomInset)
        let inset = low + bandY * (high - low)
        return SubtitleStyle(
            fontSize: tuned.fontSize,
            bottomInset: inset,
            horizontalInset: tuned.horizontalInset,
            strokeWidth: tuned.strokeWidth
        )
    }

    public func textCGColor() throws -> CGColor { try Self.cgColor(hex: textHex) }
    public func accentCGColor() throws -> CGColor { try Self.cgColor(hex: accentHex) }

    public static func cgColor(hex: String) throws -> CGColor {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else {
            throw CaptionTuneError.invalidHex(hex)
        }
        let r = CGFloat((value >> 16) & 0xff) / 255
        let g = CGFloat((value >> 8) & 0xff) / 255
        let b = CGFloat(value & 0xff) / 255
        let space = CGColorSpaceCreateDeviceRGB()
        guard let color = CGColor(colorSpace: space, components: [r, g, b, 1]) else {
            throw CaptionTuneError.invalidHex(hex)
        }
        return color
    }
}
