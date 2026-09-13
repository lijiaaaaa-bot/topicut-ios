import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

@MainActor
struct SliceSessionRenderTests {
    @Test func renderCancellationReturnsIdle() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies(renderError: CancellationError()))
        try await harness.startThroughSlice()
        let clip = try SessionFixtures.clip()
        await harness.session.render(clip: clip)
        #expect(harness.session.renders[clip.id] == .idle)
        #expect(harness.session.isRendering(clip.id) == false)
    }

    @Test func renderRetriesOnceOnOperationInterrupted() async throws {
        let queue = RenderErrorQueue([Self.operationInterrupted])
        let harness = try SessionHarness(SliceSessionTests.dependencies(renderQueue: queue))
        try await harness.startThroughSlice()
        let clip = try SessionFixtures.clip()
        await harness.session.render(clip: clip)
        #expect(queue.calls == 2)
        guard case .done = harness.session.renders[clip.id] else {
            Issue.record("expected .done after one interrupt retry, got \(String(describing: harness.session.renders[clip.id]))")
            return
        }
    }

    @Test func renderInterruptTwiceFailsInChinese() async throws {
        let queue = RenderErrorQueue([Self.operationInterrupted, Self.operationInterrupted])
        let harness = try SessionHarness(SliceSessionTests.dependencies(renderQueue: queue))
        try await harness.startThroughSlice()
        let clip = try SessionFixtures.clip()
        await harness.session.render(clip: clip)
        #expect(queue.calls == 2)
        #expect(harness.session.renders[clip.id] == .failed(RenderInterrupt.interruptedMessage))
    }

    private static var operationInterrupted: NSError {
        NSError(
            domain: RenderInterrupt.avFoundationDomain,
            code: RenderInterrupt.operationInterruptedCode,
            userInfo: [NSLocalizedDescriptionKey: "操作已中断"]
        )
    }
}

/// Sequential errors for one `render` closure; leftover empty means the next call succeeds.
final class RenderErrorQueue: @unchecked Sendable {
    private var items: [Error]
    private(set) var calls = 0

    init(_ items: [Error]) {
        self.items = items
    }

    func pop() -> Error? {
        calls += 1
        if items.isEmpty { return nil }
        return items.removeFirst()
    }
}
