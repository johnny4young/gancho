import ClipboardCore
import CoreGraphics
import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Notch shelf geometry and drop policy")
struct NotchShelfTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("The notch sits between the two unobscured top corners")
    func notch() {
        let notch = NotchShelfGeometry.notch(
            in: builtIn, safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 664)
        #expect(notch == CGRect(x: 663, y: 950, width: 185, height: 32))
        let offset = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        #expect(
            NotchShelfGeometry.notch(
                in: offset, safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 664)
                == CGRect(x: -849, y: 1150, width: 185, height: 32))
    }

    @Test("A screen without a notch has none")
    func noNotch() {
        let screen = CGRect(x: -2560, y: -289, width: 2560, height: 1440)
        #expect(
            NotchShelfGeometry.notch(
                in: screen, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil) == nil)
        #expect(
            NotchShelfGeometry.notch(
                in: builtIn, safeAreaTop: 32, leftAreaWidth: 756, rightAreaWidth: 756) == nil)
    }

    @Test("The zone is the notch, or a strip at the top center")
    func dropZone() {
        let notch = CGRect(x: 663, y: 950, width: 185, height: 32)
        #expect(
            NotchShelfGeometry.dropZone(in: builtIn, notch: notch, menuBarHeight: 24) == notch)
        let screen = CGRect(x: -2560, y: -289, width: 2560, height: 1440)
        let zone = NotchShelfGeometry.dropZone(in: screen, notch: nil, menuBarHeight: 24)
        #expect(zone.width == NotchShelfGeometry.virtualZoneWidth)
        #expect(zone.midX == screen.midX)
        #expect(zone.maxY == screen.maxY)
        #expect(zone.height == 24)
    }

    @Test("The shelf hangs centered under the zone and stays on screen")
    func shelf() {
        let size = CGSize(width: 440, height: 230)
        let zone = CGRect(x: 663, y: 950, width: 185, height: 32)
        let shelf = NotchShelfGeometry.shelf(size: size, below: zone, in: builtIn)
        #expect(shelf.midX == zone.midX)
        #expect(shelf.maxY == zone.minY)
        let nearEdge = CGRect(x: 1400, y: 950, width: 100, height: 32)
        let clamped = NotchShelfGeometry.shelf(size: size, below: nearEdge, in: builtIn)
        #expect(clamped.maxX == builtIn.maxX - NotchShelfGeometry.screenMargin)
        let nearLeft = CGRect(x: 0, y: 950, width: 100, height: 32)
        #expect(
            NotchShelfGeometry.shelf(size: size, below: nearLeft, in: builtIn).minX
                == NotchShelfGeometry.screenMargin)
    }

    @Test("A drag is a new drag-pasteboard change while the button is down")
    func dragWatch() {
        var watch = DragSessionWatch()
        let samples = [(10, false), (10, true), (11, true), (11, true), (11, false), (11, true)]
        let dragging = samples.map { watch.sample(changeCount: $0.0, isMouseDown: $0.1) }
        // Idle, a click, a drag starts, still dragging, released, the old drag's count.
        #expect(dragging == [false, false, true, true, false, false])
        var late = DragSessionWatch()
        let lateDragging = [4, 4].map { late.sample(changeCount: $0, isMouseDown: true) }
        #expect(lateDragging == [false, false], "no baseline while the button was already down")
    }

    @Test("Vetoed and unsupported drags never land")
    func accepts() {
        #expect(NotchShelfDrop.accepts(types: ["public.file-url"]))
        #expect(NotchShelfDrop.accepts(types: ["public.utf8-plain-text"]))
        #expect(NotchShelfDrop.accepts(types: [BoardDrop.clipReferenceType]))
        for veto in SensitivePasteboardTypes.captureVeto {
            #expect(!NotchShelfDrop.accepts(types: ["public.utf8-plain-text", veto]), "\(veto)")
        }
        #expect(!NotchShelfDrop.accepts(types: ["com.apple.pasteboard.promised-file-url"]))
        #expect(!NotchShelfDrop.accepts(types: []))
    }

    @Test("Image actions take only a drag that may be an image")
    func targets() {
        let boardID = UUID()
        let frames: [NotchShelfTarget: CGRect] = [
            .board(boardID): CGRect(x: 0, y: 0, width: 100, height: 30),
            .resize: CGRect(x: 200, y: 0, width: 90, height: 70),
            .newBoard: CGRect(x: 300, y: 0, width: 90, height: 70)
        ]
        let text: Set<String> = ["public.utf8-plain-text"]
        let image: Set<String> = ["public.png"]
        let file: Set<String> = ["public.file-url"]
        #expect(
            NotchShelfDrop.target(at: CGPoint(x: 10, y: 10), in: frames, types: text)
                == .board(boardID))
        #expect(NotchShelfDrop.target(at: CGPoint(x: 210, y: 10), in: frames, types: text) == nil)
        #expect(
            NotchShelfDrop.target(at: CGPoint(x: 210, y: 10), in: frames, types: image) == .resize)
        #expect(
            NotchShelfDrop.target(at: CGPoint(x: 210, y: 10), in: frames, types: file) == .resize)
        #expect(
            NotchShelfDrop.target(at: CGPoint(x: 310, y: 10), in: frames, types: text) == .newBoard)
        #expect(NotchShelfDrop.target(at: CGPoint(x: 150, y: 10), in: frames, types: text) == nil)
    }
}
