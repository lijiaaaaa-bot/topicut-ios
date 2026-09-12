// Why: fixed 切片标签 (ADR-0028) so the studio's primary path is one tap onto a known
// density+span pair; free knobs still write the same `SlicingTaste` fields.

import Foundation

public enum SliceTastePreset: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case concise
    case dense
    case longHooks
    case picky

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: "标准"
        case .concise: "少而精 · 短钩子"
        case .dense: "多一些 · 好挑选"
        case .longHooks: "标准话题 · 稍长金句"
        case .picky: "少而精 · 稍长金句"
        }
    }

    public var note: String {
        switch self {
        case .balanced: "按时长自动定条数与金句长度"
        case .concise: "话题更少、金句更短"
        case .dense: "多切几条方便挑，金句标准长度"
        case .longHooks: "话题标准密度，金句留足语境"
        case .picky: "话题精简，金句稍长"
        }
    }

    public var taste: SlicingTaste {
        switch self {
        case .balanced:
            SlicingTaste(topicDensity: .standard, highlightSpan: .standard)
        case .concise:
            SlicingTaste(topicDensity: .fewer, highlightSpan: .punchy)
        case .dense:
            SlicingTaste(topicDensity: .more, highlightSpan: .standard)
        case .longHooks:
            SlicingTaste(topicDensity: .standard, highlightSpan: .roomy)
        case .picky:
            SlicingTaste(topicDensity: .fewer, highlightSpan: .roomy)
        }
    }

    /// Matching preset for the current taste, if any free-knob combo equals a tag.
    public static func matching(_ taste: SlicingTaste) -> SliceTastePreset? {
        allCases.first { $0.taste == taste }
    }
}
