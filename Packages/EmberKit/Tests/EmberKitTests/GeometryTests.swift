import CoreGraphics
import Testing
@testable import EmberKit

@Suite("Snapping")
struct SnappingTests {
    @Test func nearlyHorizontalSnapsFlat() {
        let v = Snapping.adjust(CGVector(dx: 100, dy: 8), mode: .octilinear)
        #expect(v == CGVector(dx: 100, dy: 0))
    }

    @Test func nearlyVerticalSnapsUpright() {
        let v = Snapping.adjust(CGVector(dx: -6, dy: -90), mode: .octilinear)
        #expect(v == CGVector(dx: 0, dy: -90))
    }

    @Test func diagonalHasEqualLegs() {
        let up = Snapping.adjust(CGVector(dx: 50, dy: -40), mode: .octilinear)
        #expect(abs(up.dx) == abs(up.dy))
        #expect(up.dx > 0 && up.dy < 0)
        let down = Snapping.adjust(CGVector(dx: -50, dy: -60), mode: .octilinear)
        #expect(down.dx == down.dy)
        #expect(down.dx < 0)
    }

    @Test func squareModeAlwaysGivesSquare() {
        for v in [CGVector(dx: 80, dy: 20), CGVector(dx: -30, dy: 70), CGVector(dx: -40, dy: -10)] {
            let s = Snapping.adjust(v, mode: .square)
            #expect(abs(s.dx) == abs(s.dy))
        }
    }
}

@Suite("Arrow geometry")
struct ArrowTests {
    @Test func headTipIsAtReleasePoint() {
        let g = ArrowGeometry.make(from: .zero, to: CGPoint(x: 200, y: 0), thickness: 3, scale: 1, style: .standard)
        let box = g.head.boundingBoxOfPath
        #expect(abs(box.maxX - 200) < 0.001)
        // Head length 18 + 4·3 = 30, shaft = 200 + 6 − 30 = 176.
        #expect(abs(g.shaftEnd.x - 176) < 0.001)
        // Head base width 10 + 2·3 = 16.
        #expect(abs(box.height - 16) < 0.001)
    }

    @Test func shortArrowCollapsesShaft() {
        let g = ArrowGeometry.make(from: .zero, to: CGPoint(x: 10, y: 0), thickness: 4, scale: 1, style: .standard)
        #expect(g.shaftEnd.x <= 1.0001)
    }

    @Test func scaleMultipliesSizes() {
        let g1 = ArrowGeometry.make(from: .zero, to: CGPoint(x: 400, y: 0), thickness: 3, scale: 1, style: .standard)
        let g2 = ArrowGeometry.make(from: .zero, to: CGPoint(x: 400, y: 0), thickness: 3, scale: 2, style: .standard)
        #expect(abs(g2.head.boundingBoxOfPath.height - 2 * g1.head.boundingBoxOfPath.height) < 0.001)
    }
}

@Suite("Marker geometry")
struct MarkerTests {
    @Test func markerIsFourteenWiderThanThickness() {
        #expect(MarkerGeometry.width(thickness: 3, scale: 1) == 17)
        #expect(MarkerGeometry.width(thickness: 3, scale: 2) == 34)
        let a = Annotation(kind: .marker, points: [CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100)],
                           color: .red, size: 3, scale: 2)
        #expect(a.boundingRect.height >= 34)
    }
}

@Suite("Counter geometry")
struct CounterTests {
    @Test func radiusFollowsThickness() {
        #expect(CounterGeometry.radius(thickness: 3, scale: 2) == 36)
    }

    @Test func tailOnlyOutsideBubble() {
        #expect(CounterGeometry.tail(center: .zero, tip: CGPoint(x: 10, y: 0), radius: 18) == nil)
        #expect(CounterGeometry.tail(center: .zero, tip: CGPoint(x: 60, y: 0), radius: 18) != nil)
    }
}

@Suite("Selection handles")
struct SelectionTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func hitFindsNearestHandle() {
        #expect(SelectionHandle.hit(CGPoint(x: 302, y: 98), in: rect, tolerance: 10) == .topRight)
        #expect(SelectionHandle.hit(CGPoint(x: 200, y: 150), in: rect, tolerance: 10) == nil)
    }

    @Test func draggingPastOppositeEdgeFlips() {
        let r = SelectionHandle.right.resize(rect, by: CGVector(dx: -300, dy: 0), within: bounds)
        #expect(r == CGRect(x: 0, y: 100, width: 100, height: 100))
    }

    @Test func moveStaysInBounds() {
        let r = rect.moved(by: CGVector(dx: 5000, dy: -5000), within: bounds)
        #expect(r == CGRect(x: 800, y: 0, width: 200, height: 100))
    }
}

@Suite("Toolbar layout")
struct ToolbarLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1366, height: 1024)

    @Test func placesEveryButtonOnScreen() {
        let sel = CGRect(x: 400, y: 300, width: 500, height: 300)
        let centers = ToolbarLayout.centers(count: 20, selection: sel, bounds: screen, buttonSize: 44, spacing: 6)
        #expect(centers.count == 20)
        for c in centers { #expect(screen.contains(c)) }
    }

    @Test func firstRowGoesBelowSelection() {
        let sel = CGRect(x: 400, y: 300, width: 500, height: 300)
        let centers = ToolbarLayout.centers(count: 5, selection: sel, bounds: screen, buttonSize: 44, spacing: 6)
        for c in centers { #expect(c.y > sel.maxY) }
        // Centred under the selection.
        let mid = (centers.map(\.x).min()! + centers.map(\.x).max()!) / 2
        #expect(abs(mid - sel.midX) < 0.001)
    }

    @Test func noButtonsOverlap() {
        let sel = CGRect(x: 600, y: 450, width: 120, height: 80)
        let centers = ToolbarLayout.centers(count: 20, selection: sel, bounds: screen, buttonSize: 44, spacing: 6)
        for i in centers.indices {
            for j in centers.indices where j > i {
                #expect(centers[i].distance(to: centers[j]) >= 44 - 0.001)
            }
        }
    }

    @Test func fullScreenSelectionPutsButtonsInside() {
        let centers = ToolbarLayout.centers(count: 20, selection: screen, bounds: screen, buttonSize: 44, spacing: 6)
        #expect(centers.count == 20)
        for c in centers { #expect(screen.contains(c)) }
    }
}

@Suite("Radial picker")
struct RadialTests {
    @Test func firstSwatchIsAtTwelveOClock() {
        let c = RadialLayout.centers(count: 9, around: CGPoint(x: 100, y: 100), radius: 50)
        #expect(abs(c[0].x - 100) < 0.001)
        #expect(abs(c[0].y - 50) < 0.001)
    }

    @Test func pickingRoundTrips() {
        let center = CGPoint(x: 100, y: 100)
        let centers = RadialLayout.centers(count: 9, around: center, radius: 71)
        for (i, p) in centers.enumerated() {
            #expect(RadialLayout.index(at: p, count: 9, around: center, radius: 71) == i)
        }
        #expect(RadialLayout.index(at: center, count: 9, around: center, radius: 71) == nil)
    }
}

@Suite("Viewport")
struct ViewportTests {
    @Test func roundTrip() {
        let m = ViewportMapping(imageSize: CGSize(width: 2732, height: 2048), viewSize: CGSize(width: 1366, height: 1100))
        #expect(abs(m.scale - 0.5) < 0.0001)
        let p = CGPoint(x: 123, y: 456)
        let back = m.toImage(m.toView(p))
        #expect(abs(back.x - p.x) < 0.001 && abs(back.y - p.y) < 0.001)
        #expect(abs(m.imageFrame.minY - 38) < 0.001) // letterboxed vertically
    }
}
