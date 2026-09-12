import CoreGraphics
import Testing
@testable import LiveSliceRender

@Suite("FaceFocus")
struct FaceFocusTests {
    @Test func landscapeSourceCropsSidesToNineSixteen() {
        let oriented = CGSize(width: 1920, height: 1080)
        let window = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(window.height - 1080) < 0.5)
        #expect(abs(window.width / window.height - 9 / 16) < 0.01)
        #expect(abs(window.midX - 960) < 1)
        #expect(window.minX >= 0 && window.maxX <= 1920)
    }

    @Test func focusOnTheRightShiftsTheWindowRight() {
        let oriented = CGSize(width: 1920, height: 1080)
        let left = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.1, y: 0.5))
        let right = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.9, y: 0.5))
        #expect(left.minX < right.minX)
        #expect(left.minX == 0)
        #expect(right.maxX == 1920)
    }

    @Test func portraitSourceCropsTopBottom() {
        let oriented = CGSize(width: 1080, height: 1920)
        let window = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(window.width - 1080) < 0.5)
        #expect(abs(window.width / window.height - 9 / 16) < 0.01)
    }

    @Test func focusFromVisionBoxesUsesAreaWeightedCentre() throws {
        let small = CGRect(x: 0.1, y: 0.4, width: 0.1, height: 0.1)
        let large = CGRect(x: 0.6, y: 0.3, width: 0.3, height: 0.3)
        let focus = try #require(FaceFocus.focus(faces: [small, large], oriented: CGSize(width: 100, height: 100)))
        #expect(focus.x > 0.5)
        #expect(abs(focus.y - 0.55) < 0.05)
    }

    @Test func emptyFacesYieldNilFocus() {
        #expect(FaceFocus.focus(faces: [], oriented: CGSize(width: 100, height: 100)) == nil)
    }

    @Test func zoomTightensTheWindowAroundFocus() {
        let oriented = CGSize(width: 1920, height: 1080)
        let wide = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.5, y: 0.5), zoom: 1)
        let tight = FaceFocus.phoneCropWindow(oriented: oriented, focus: CGPoint(x: 0.5, y: 0.5), zoom: 2)
        #expect(tight.width < wide.width)
        #expect(abs(tight.width / tight.height - 9 / 16) < 0.01)
        #expect(abs(tight.midX - 960) < 1)
    }
}
