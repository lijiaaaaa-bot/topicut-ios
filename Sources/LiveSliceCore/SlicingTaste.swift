// Why: Topicut 2.0 lets the user steer how many topics and how long highlights should feel before
// paying for a re-slice. These enums scale the duration-adaptive policies without inventing a
// second prompt family (ADR-0026).

import Foundation

/// How densely the model should pack topic clips for a given video length.
public enum TopicDensity: String, CaseIterable, Codable, Equatable, Sendable {
    case fewer
    case standard
    case more

    public var title: String {
        switch self {
        case .fewer: "少而精"
        case .standard: "标准"
        case .more: "多一些"
        }
    }

    public var note: String {
        switch self {
        case .fewer: "话题更少、每条更完整"
        case .standard: "按时长自动定条数"
        case .more: "多切几条，方便挑"
        }
    }

    /// Third line on the 切片工作室 density card (qualitative; counts stay duration-adaptive).
    public var studioTag: String {
        switch self {
        case .fewer: "精炼 · 重点突出"
        case .standard: "平衡 · 通用"
        case .more: "详尽 · 好挑选"
        }
    }

    /// Multiplier applied to min/max/hardMax clip counts (then clamped to ≥1).
    public var clipScale: Double {
        switch self {
        case .fewer: 0.6
        case .standard: 1.0
        case .more: 1.4
        }
    }
}

/// Preferred length band for 金句 highlights (seconds guidance in the prompt).
public enum HighlightSpan: String, CaseIterable, Codable, Equatable, Sendable {
    case punchy
    case standard
    case roomy

    public var title: String {
        switch self {
        case .punchy: "短钩子"
        case .standard: "标准"
        case .roomy: "稍长"
        }
    }

    public var note: String {
        switch self {
        case .punchy: "约 12–45 秒"
        case .standard: "约 20–90 秒"
        case .roomy: "约 40–150 秒"
        }
    }

    /// Chip label in 切片工作室 — representative seconds for the band, not a hard cap.
    public var studioChip: String {
        switch self {
        case .punchy: "15秒"
        case .standard: "30秒"
        case .roomy: "90秒"
        }
    }

    public var minSeconds: Int {
        switch self {
        case .punchy: 12
        case .standard: 20
        case .roomy: 40
        }
    }

    public var maxSeconds: Int {
        switch self {
        case .punchy: 45
        case .standard: 90
        case .roomy: 150
        }
    }
}

/// User taste applied on top of the duration table before the prompt is built.
public struct SlicingTaste: Codable, Equatable, Sendable {
    public var topicDensity: TopicDensity
    public var highlightSpan: HighlightSpan

    public init(topicDensity: TopicDensity = .standard, highlightSpan: HighlightSpan = .standard) {
        self.topicDensity = topicDensity
        self.highlightSpan = highlightSpan
    }

    public static let standard = SlicingTaste()

    /// Fragment stored inside `PipelineReuse.sliceKey` so a taste change invalidates the EDL.
    public var keyFragment: String { "\(topicDensity.rawValue)+\(highlightSpan.rawValue)" }

    public func apply(_ policy: ClipCountPolicy) -> ClipCountPolicy {
        let scale = topicDensity.clipScale
        func scaled(_ n: Int) -> Int { max(1, Int((Double(n) * scale).rounded())) }
        let minClips = scaled(policy.minClips)
        let maxClips = max(minClips, scaled(policy.maxClips))
        let hardMax = max(maxClips, scaled(policy.hardMaxClips))
        return ClipCountPolicy(
            durationMinutes: policy.durationMinutes, minClips: minClips, maxClips: maxClips, hardMaxClips: hardMax
        )
    }

    public func apply(_ policy: HighlightCountPolicy) -> HighlightCountPolicy {
        HighlightCountPolicy(
            durationMinutes: policy.durationMinutes,
            minHighlights: policy.minHighlights,
            maxHighlights: policy.maxHighlights,
            minSeconds: highlightSpan.minSeconds,
            maxSeconds: highlightSpan.maxSeconds
        )
    }
}
