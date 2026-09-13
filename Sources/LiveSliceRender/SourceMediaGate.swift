// Why: preview composition and MP4 export share one source asset. Overlapping them
// interrupts AVAssetExportSession as AVError.operationInterrupted (-11847).

/// Serializes preview build and export so one owner holds the source until it finishes.
public actor SourceMediaGate {
    public static let shared = SourceMediaGate()

    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var busy = false

    public init() {}

    public func exclusive<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            let value = try await work()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
            return
        }
        waiters.removeFirst().resume()
    }
}
