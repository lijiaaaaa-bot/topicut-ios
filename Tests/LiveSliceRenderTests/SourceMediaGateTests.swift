import Foundation
import Testing
@testable import LiveSliceRender

struct SourceMediaGateTests {
    @Test func exclusiveRunsOneOwnerAtATime() async throws {
        let gate = SourceMediaGate()
        let occupancy = Occupancy()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await gate.exclusive {
                        await occupancy.enter()
                        try await Task.sleep(for: .milliseconds(15))
                        await occupancy.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await occupancy.peak == 1)
        #expect(await occupancy.entries == 4)
    }

    @Test func acquireReleaseSerializesWithoutSendingAClosure() async throws {
        let gate = SourceMediaGate()
        let occupancy = Occupancy()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await gate.acquire()
                    await occupancy.enter()
                    try await Task.sleep(for: .milliseconds(10))
                    await occupancy.leave()
                    await gate.release()
                }
            }
            try await group.waitForAll()
        }
        #expect(await occupancy.peak == 1)
        #expect(await occupancy.entries == 3)
    }
}

private actor Occupancy {
    private var current = 0
    private(set) var peak = 0
    private(set) var entries = 0

    func enter() {
        current += 1
        entries += 1
        if current > peak { peak = current }
    }

    func leave() {
        current -= 1
    }
}
