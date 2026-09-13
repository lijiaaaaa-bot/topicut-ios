// Why: AVAssetExportSession surfaces a cancelled or torn-down export as NSError
// AVFoundation -11847, not CancellationError. Map that to idle / one retry / Chinese copy.

import Foundation

public enum RenderExportRecovery: Equatable, Sendable {
    case idle
    case retryOnce
    case fail(String)
}

public enum RenderInterrupt {
    public static let avFoundationDomain = "AVFoundationErrorDomain"
    public static let operationInterruptedCode = -11847
    public static let interruptedMessage = "导出被中断，请再试一次。"

    public static func isOperationInterrupted(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == avFoundationDomain && ns.code == operationInterruptedCode
    }

    /// Cancelled task (or `CancellationError`) → idle. Transient -11847 → one retry unless
    /// `alreadyRetried` (then Chinese fail — no second automatic retry).
    public static func recovery(
        for error: Error, taskCancelled: Bool, alreadyRetried: Bool = false
    ) -> RenderExportRecovery {
        if error is CancellationError || taskCancelled { return .idle }
        if isOperationInterrupted(error) {
            if alreadyRetried { return .fail(interruptedMessage) }
            return .retryOnce
        }
        return .fail(ErrorText.describe(error))
    }

    public static func failMessage(_ error: Error) -> String {
        if isOperationInterrupted(error) { return interruptedMessage }
        return ErrorText.describe(error)
    }

    /// First attempt; on -11847 without cancel, run `work` once more; cancelled → `CancellationError`.
    /// MainActor so `SliceSession.render` can pass `invokeRender` without sending a non-Sendable closure.
    @MainActor
    public static func run<T: Sendable>(_ work: @MainActor () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            switch recovery(for: error, taskCancelled: Task.isCancelled) {
            case .idle:
                throw CancellationError()
            case .retryOnce:
                return try await retryOnce(work)
            case .fail:
                throw error
            }
        }
    }

    @MainActor
    private static func retryOnce<T: Sendable>(_ work: @MainActor () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            switch recovery(for: error, taskCancelled: Task.isCancelled, alreadyRetried: true) {
            case .idle:
                throw CancellationError()
            case .retryOnce, .fail:
                throw error
            }
        }
    }
}
