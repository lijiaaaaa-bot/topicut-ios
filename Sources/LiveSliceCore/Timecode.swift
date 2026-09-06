// Why: SRT and the EDL both speak "HH:MM:SS.mmm"; one strict parser/formatter avoids
// every module re-implementing (and subtly disagreeing about) timestamp math.
// Ported from live_slice_auto/live_slice/timecode.py.

import Foundation

public enum TimecodeError: Error, Equatable, Sendable {
    /// The string is not `HH:MM:SS.mmm` / `HH:MM:SS,mmm`.
    case invalidTimestamp(String)
}

public enum Timecode {
    /// Parses `HH:MM:SS.mmm` or `HH:MM:SS,mmm` into seconds. Throws on any other shape.
    public static func parse(_ raw: String) throws -> Double {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw TimecodeError.invalidTimestamp(raw) }
        let secParts = parts[2].split(separator: ".", omittingEmptySubsequences: false)
        guard secParts.count == 2,
              parts[0].count == 2, parts[1].count == 2,
              secParts[0].count == 2, secParts[1].count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(secParts[0]), let ms = Int(secParts[1]),
              m < 60, s < 60
        else { throw TimecodeError.invalidTimestamp(raw) }
        return Double(h * 3600 + m * 60 + s) + Double(ms) / 1000.0
    }

    /// Formats seconds as `HH:MM:SS.mmm`. Negative input is clamped to zero.
    public static func format(_ seconds: Double) -> String {
        let clamped = max(0.0, seconds)
        var totalMs = Int((clamped * 1000.0).rounded())
        let ms = totalMs % 1000
        totalMs /= 1000
        let h = totalMs / 3600
        let m = (totalMs % 3600) / 60
        let s = totalMs % 60
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
