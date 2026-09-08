// Why: a saved transcript or EDL is only worth reusing if the inputs that produced it are the
// inputs the user has now. These rules are the single place that decides "unchanged, keep it" vs
// "changed, run the step again"; SliceSession applies them, the tests pin them down.

import Foundation
import LiveSliceASR

public enum PipelineReuse {
    /// Retired model names and the model they were an alias for, per the provider's changelog.
    /// An EDL sliced under the old name came from the same model, so moving the app default to
    /// the new name must not trigger a paid re-slice of every existing project.
    static let retiredModelAliases: [String: String] = [
        "deepseek-chat": "deepseek-v4-flash",
    ]

    /// What the LLM step depends on besides the transcript: the model and where it is served.
    /// The API key is deliberately not part of it — a new key does not change the answer.
    public static func sliceKey(model: String, baseURL: String) -> String {
        var name = model.trimmingCharacters(in: .whitespaces)
        if let current = retiredModelAliases[name] { name = current }
        return "\(name)|\(baseURL.trimmingCharacters(in: .whitespaces))"
    }

    /// A stored key written before an alias retired (`deepseek-chat|…`) means the same model as
    /// the key the app computes today; compare both in normalized form.
    static func normalizedSliceKey(_ stored: String) -> String {
        guard let bar = stored.firstIndex(of: "|") else { return stored }
        return sliceKey(model: String(stored[..<bar]), baseURL: String(stored[stored.index(after: bar)...]))
    }

    /// The saved transcript stands if it exists and the current ASR setting would produce a
    /// transcript in the same language: same preference, or a fixed locale equal to the one the
    /// transcript already has. Records from before provenance was stored (`transcribedWith == nil`)
    /// are kept as they are — a re-transcription would cost minutes and prove nothing.
    public static func transcriptIsCurrent(_ record: ProjectRecord, preference: ASRLocalePreference) -> Bool {
        guard record.srt != nil, let produced = record.localeIdentifier else { return false }
        guard let with = record.transcribedWith else { return true }
        if with == preference.identifier { return true }
        if case .fixed(let locale) = preference { return locale.identifier == produced }
        return false
    }

    /// The saved EDL stands if the transcript stands and the model/endpoint that produced it are
    /// the current ones. Older records without `slicedWith` are kept.
    public static func sliceIsCurrent(_ record: ProjectRecord, transcriptCurrent: Bool, key: String) -> Bool {
        guard transcriptCurrent, record.document != nil else { return false }
        guard let with = record.slicedWith else { return true }
        return normalizedSliceKey(with) == normalizedSliceKey(key)
    }
}
