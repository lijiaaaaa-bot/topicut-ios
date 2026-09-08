import Foundation
import Testing
@testable import LiveSliceKeychain

/// Real Security.framework round trip against a throwaway service name (never the app's item).
struct APIKeyStoreTests {
    @Test func saveLoadReplaceDelete() throws {
        let store = APIKeyStore(service: "com.jiajiali.liveslice.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        try store.save("  sk-first-value \n")
        #expect(try store.load() == "sk-first-value")
        try store.save("sk-second-value")
        #expect(try store.load() == "sk-second-value")
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete() // idempotent
    }

    @Test func storesAreIsolatedByService() throws {
        let a = APIKeyStore(service: "com.jiajiali.liveslice.tests.a.\(UUID().uuidString)")
        let b = APIKeyStore(service: "com.jiajiali.liveslice.tests.b.\(UUID().uuidString)")
        defer { try? a.delete(); try? b.delete() }
        try a.save("key-a")
        #expect(try b.load() == nil)
        #expect(try a.load() == "key-a")
    }
}
