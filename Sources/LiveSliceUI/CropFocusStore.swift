// Why: optional per-clip phone-portrait framing override (focus + zoom). Kept beside the project
// like words.json so the home list never decodes it (ADR-0026).

import CoreGraphics
import Foundation

/// Manual 9:16 framing for one clip. `zoom` 1 = widest legal window; larger = tighter on focus.
public struct CropOverride: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var zoom: Double

    public init(x: Double, y: Double, zoom: Double = 1) {
        self.x = x
        self.y = y
        self.zoom = max(1, zoom)
    }

    public var focus: CGPoint { CGPoint(x: x, y: y) }

    public static func focus(_ point: CGPoint, zoom: Double = 1) -> CropOverride {
        CropOverride(x: Double(point.x), y: Double(point.y), zoom: zoom)
    }
}

public struct CropFocusStore: Codable, Equatable, Sendable {
    /// clipID → override. Legacy `[x,y]` arrays still decode via custom init below… actually we
    /// store objects only; missing file = empty.
    public var overrides: [String: CropOverride]

    public init(overrides: [String: CropOverride] = [:]) {
        self.overrides = overrides
    }

    enum CodingKeys: String, CodingKey { case overrides, points }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        if let modern = try box.decodeIfPresent([String: CropOverride].self, forKey: .overrides) {
            overrides = modern
            return
        }
        // Legacy shape from the first 2.0 cut: clipID → [x, y].
        let legacy: [String: [Double]]
        if let decoded = try box.decodeIfPresent([String: [Double]].self, forKey: .points) {
            legacy = decoded
        } else {
            legacy = [:]
        }
        var mapped: [String: CropOverride] = [:]
        for (id, pair) in legacy where pair.count >= 2 {
            mapped[id] = CropOverride(x: pair[0], y: pair[1], zoom: pair.count > 2 ? pair[2] : 1)
        }
        overrides = mapped
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(overrides, forKey: .overrides)
    }

    public func override(for clipID: String) -> CropOverride? { overrides[clipID] }

    public func focus(for clipID: String) -> CGPoint? { overrides[clipID]?.focus }

    public func zoom(for clipID: String) -> CGFloat {
        if let zoom = overrides[clipID]?.zoom { return CGFloat(zoom) }
        return 1
    }

    public mutating func setOverride(_ value: CropOverride?, for clipID: String) {
        if let value {
            overrides[clipID] = value
        } else {
            overrides.removeValue(forKey: clipID)
        }
    }

    public mutating func setFocus(_ point: CGPoint?, for clipID: String) {
        if let point {
            let zoom: Double
            if let existing = overrides[clipID]?.zoom {
                zoom = existing
            } else {
                zoom = 1
            }
            overrides[clipID] = CropOverride.focus(point, zoom: zoom)
        } else {
            overrides.removeValue(forKey: clipID)
        }
    }

    public mutating func setZoom(_ zoom: Double, for clipID: String) {
        let current = overrides[clipID] ?? CropOverride(x: 0.5, y: 0.5, zoom: 1)
        overrides[clipID] = CropOverride(x: current.x, y: current.y, zoom: min(3, max(1, zoom)))
    }
}
