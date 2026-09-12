import CoreGraphics
import Foundation
import Testing
@testable import LiveSliceUI

@Suite("CropFocusStore")
struct CropFocusStoreTests {
    @Test func roundTripsFocusAndZoom() throws {
        var store = CropFocusStore()
        #expect(store.focus(for: "a") == nil)
        store.setFocus(CGPoint(x: 0.25, y: 0.75), for: "a")
        #expect(store.focus(for: "a") == CGPoint(x: 0.25, y: 0.75))
        #expect(store.zoom(for: "a") == 1)
        store.setZoom(2.5, for: "a")
        #expect(store.zoom(for: "a") == 2.5)
        #expect(store.focus(for: "a") == CGPoint(x: 0.25, y: 0.75))
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(CropFocusStore.self, from: data)
        #expect(decoded.override(for: "a")?.zoom == 2.5)
        store.setOverride(nil, for: "a")
        #expect(store.focus(for: "a") == nil)
    }

    @Test func decodesLegacyPointsArray() throws {
        let json = Data(#"{"points":{"c1":[0.1,0.2]}}"#.utf8)
        let store = try JSONDecoder().decode(CropFocusStore.self, from: json)
        #expect(store.focus(for: "c1") == CGPoint(x: 0.1, y: 0.2))
        #expect(store.zoom(for: "c1") == 1)
    }
}
