// Why: the settings screen stores a string (`auto` / `zh_CN` / `en_US`); the ASR pipeline needs a
 // typed preference. `automatic` means probe the audio and pick a locale; `fixed` means the user
 // already chose and we must not second-guess them.

import Foundation

public enum ASRLocalePreference: Equatable, Sendable {
    case automatic
    case fixed(Locale)

    public static let automaticIdentifier = "auto"

    public init(identifier: String) {
        if identifier == Self.automaticIdentifier {
            self = .automatic
        } else {
            self = .fixed(Locale(identifier: identifier))
        }
    }

    public var identifier: String {
        switch self {
        case .automatic: Self.automaticIdentifier
        case .fixed(let locale): locale.identifier
        }
    }
}
