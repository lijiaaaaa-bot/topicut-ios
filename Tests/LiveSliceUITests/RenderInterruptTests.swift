import Foundation
import Testing
@testable import LiveSliceUI

struct RenderInterruptTests {
    private var interrupted: NSError {
        NSError(
            domain: RenderInterrupt.avFoundationDomain,
            code: RenderInterrupt.operationInterruptedCode,
            userInfo: [NSLocalizedDescriptionKey: "操作已中断"]
        )
    }

    @Test func interruptedWhileCancelledIsIdle() {
        #expect(RenderInterrupt.recovery(for: interrupted, taskCancelled: true) == .idle)
    }

    @Test func cancellationErrorIsIdleEvenIfTaskStillRunning() {
        #expect(RenderInterrupt.recovery(for: CancellationError(), taskCancelled: false) == .idle)
    }

    @Test func interruptedWithoutCancelRetriesOnce() {
        #expect(RenderInterrupt.recovery(for: interrupted, taskCancelled: false) == .retryOnce)
    }

    @Test func otherErrorsFailWithTypedText() {
        #expect(RenderInterrupt.recovery(for: SessionTestError.exportBroke, taskCancelled: false) == .fail("exportBroke"))
    }

    @Test func failMessageForInterruptIsChineseNotDomainDump() {
        let message = RenderInterrupt.failMessage(interrupted)
        #expect(message == RenderInterrupt.interruptedMessage)
        #expect(!message.contains("AVFoundation"))
        #expect(!message.contains("-11847"))
    }

    @Test func runRetriesOnceThenSucceeds() async throws {
        let box = AttemptBox()
        let value = try await RenderInterrupt.run {
            box.calls += 1
            if box.calls == 1 { throw interrupted }
            return 7
        }
        #expect(value == 7)
        #expect(box.calls == 2)
    }

    @Test func runPropagatesCancellationErrorWithoutRetry() async {
        let box = AttemptBox()
        await #expect(throws: CancellationError.self) {
            try await RenderInterrupt.run {
                box.calls += 1
                throw CancellationError()
            }
        }
        #expect(box.calls == 1)
    }
}

private final class AttemptBox: @unchecked Sendable {
    var calls = 0
}
