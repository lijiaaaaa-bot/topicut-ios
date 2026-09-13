// Why: clock / duration / SMPTE strings for the workbench and the edit sheet. Pure so tests can
// pin the copy (`00:18`, `1分02秒`, `00:00:12:15`).

import Foundation

/// Durations and clock times as people read them, not as SRT timecode.
enum TimeText {
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) 秒" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    /// Compact Chinese duration used on the workbench pills (`48秒`, `1分02秒`, `7分10秒`).
    static func compact(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return s == 0 ? "\(h)小时\(m)分" : String(format: "%d小时%d分%02d秒", h, m, s) }
        if m > 0 { return s == 0 ? "\(m)分" : String(format: "%d分%02d秒", m, s) }
        return "\(s)秒"
    }

    /// `HH:MM:SS:FF` at `fps` (edit-sheet mock is 24 fps). Negative input clamps to zero.
    static func smpte(_ seconds: Double, fps: Int = 24) -> String {
        let rate = max(1, fps)
        let frames = Int((max(0, seconds) * Double(rate)).rounded())
        let frame = frames % rate
        let totalSec = frames / rate
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, frame)
    }
}
