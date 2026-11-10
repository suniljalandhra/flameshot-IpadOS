import CoreGraphics
import Foundation
import Testing
@testable import EmberKit

/// A test screenshot: left half white, right half black, with a red square in
/// the middle that redaction must hide.
func makeTestImage(width: Int = 200, height: Int = 100) -> CGImage {
    var buf = PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width {
            let secret = (90..<110).contains(x) && (40..<60).contains(y)
            let v: UInt8 = x < width / 2 ? 255 : 0
            buf.setPixel(x: x, y: y, secret ? (255, 0, 0, 255) : (v, v, v, 255))
        }
    }
    return buf.makeImage()!
}

@MainActor
@Suite("Editor document")
struct DocumentTests {
    func makeDoc() -> EditorDocument {
        let doc = EditorDocument(image: makeTestImage(), pixelScale: 1)
        doc.selection = CGRect(x: 10, y: 10, width: 150, height: 80)
        return doc
    }

    @Test func dragCreatesSelectionAndTapSelectsAll() {
        let doc = EditorDocument(image: makeTestImage(), pixelScale: 1)
        doc.pointerDown(at: CGPoint(x: 20, y: 20))
        doc.pointerMoved(to: CGPoint(x: 120, y: 70))
        doc.pointerUp()
        #expect(doc.selection == CGRect(x: 20, y: 20, width: 100, height: 50))

        let tapped = EditorDocument(image: makeTestImage(), pixelScale: 1)
        tapped.pointerDown(at: CGPoint(x: 20, y: 20))
        tapped.pointerUp()
        #expect(tapped.selection == tapped.imageBounds)
    }

    @Test func drawingCommitsAndUndoRedo() {
        let doc = makeDoc()
        doc.selectTool(.arrow)
        doc.pointerDown(at: CGPoint(x: 30, y: 30))
        doc.pointerMoved(to: CGPoint(x: 90, y: 60))
        doc.pointerUp()
        #expect(doc.annotations.count == 1)
        #expect(doc.annotations[0].second == CGPoint(x: 90, y: 60))

        doc.undo()
        #expect(doc.annotations.isEmpty)
        doc.redo()
        #expect(doc.annotations.count == 1)
    }

    @Test func zeroLengthShapesAreDiscarded() {
        let doc = makeDoc()
        doc.selectTool(.rectangleOutline)
        doc.pointerDown(at: CGPoint(x: 30, y: 30))
        doc.pointerUp()
        #expect(doc.annotations.isEmpty)
        #expect(!doc.canUndo)
    }

    @Test func shiftSnapsLine() {
        let doc = makeDoc()
        doc.selectTool(.line)
        doc.pointerDown(at: CGPoint(x: 30, y: 30))
        doc.pointerMoved(to: CGPoint(x: 100, y: 34), modifiers: .shift)
        doc.pointerUp()
        #expect(doc.annotations[0].second == CGPoint(x: 100, y: 30))
    }

    @Test func countersNumberSequentiallyAndUndoFreesNumber() {
        let doc = makeDoc()
        doc.selectTool(.counter)
        for x in [30, 60, 90] {
            doc.pointerDown(at: CGPoint(x: x, y: 40))
            doc.pointerUp()
        }
        #expect(doc.annotations.map(\.number) == [1, 2, 3])
        doc.undo()
        #expect(doc.nextCounterNumber == 3)
    }

    @Test func textCommitsOnTapAway() {
        let doc = makeDoc()
        doc.selectTool(.text)
        doc.pointerDown(at: CGPoint(x: 30, y: 30))
        doc.pointerUp()
        doc.pendingText?.string = "Hello"
        doc.pointerDown(at: CGPoint(x: 80, y: 80))
        doc.pointerUp()
        #expect(doc.annotations.count == 1)
        #expect(doc.annotations[0].text == "Hello")
        #expect(doc.pendingText == nil)
    }

    @Test func moveToolMovesAnnotationWithUndo() {
        let doc = makeDoc()
        doc.selectTool(.rectangleFilled)
        doc.pointerDown(at: CGPoint(x: 30, y: 30))
        doc.pointerMoved(to: CGPoint(x: 50, y: 50))
        doc.pointerUp()
        doc.selectTool(.move)
        doc.pointerDown(at: CGPoint(x: 40, y: 40), tolerance: 4)
        doc.pointerMoved(to: CGPoint(x: 60, y: 45))
        doc.pointerUp()
        #expect(doc.annotations[0].first == CGPoint(x: 50, y: 35))
        doc.undo()
        #expect(doc.annotations[0].first == CGPoint(x: 30, y: 30))
    }

    @Test func navigateRoleMovesSelectionInsteadOfDrawing() {
        let doc = makeDoc()
        doc.selectTool(.pencil)
        doc.pointerDown(at: CGPoint(x: 80, y: 50), role: .navigate, tolerance: 4)
        doc.pointerMoved(to: CGPoint(x: 90, y: 50))
        doc.pointerUp()
        #expect(doc.annotations.isEmpty)
        #expect(doc.selection?.minX == 20)
    }

    @Test func undoHistoryIsCapped() {
        let doc = makeDoc()
        doc.selectTool(.line)
        for i in 0..<(EditorDocument.undoLimit + 20) {
            doc.pointerDown(at: CGPoint(x: 20, y: 20), tolerance: 2)
            doc.pointerMoved(to: CGPoint(x: 30 + i % 50, y: 40))
            doc.pointerUp()
        }
        var undos = 0
        while doc.canUndo { doc.undo(); undos += 1 }
        #expect(undos == EditorDocument.undoLimit)
    }
}

@Suite("Rendering")
struct RenderingTests {
    @Test func securePixelateNeverShowsHiddenPixels() throws {
        let image = makeTestImage()
        let buf = try #require(PixelBuffer(image: image))
        // Cover the red square completely.
        let out = try #require(Redaction.securePixelate(buf, rect: CGRect(x: 85, y: 35, width: 30, height: 30), thickness: 3, scale: 1))
        let result = try #require(PixelBuffer(image: out))
        for y in 0..<result.height {
            for x in 0..<result.width {
                let p = result.pixel(x: x, y: y)
                // Surroundings are greys; pure red can only come from the secret.
                let redness = Int(p.r) - (Int(p.g) + Int(p.b)) / 2
                #expect(redness < 60)
            }
        }
    }

    @Test func securePixelateIsDeterministic() throws {
        let buf = try #require(PixelBuffer(image: makeTestImage()))
        let rect = CGRect(x: 20, y: 20, width: 120, height: 60)
        let a = try #require(Redaction.securePixelate(buf, rect: rect, thickness: 3, scale: 1))
        let b = try #require(Redaction.securePixelate(buf, rect: rect, thickness: 3, scale: 1))
        #expect(PixelBuffer(image: a)?.bytes == PixelBuffer(image: b)?.bytes)
    }

    @Test func invertFlipsColours() throws {
        let buf = try #require(PixelBuffer(image: makeTestImage()))
        let out = try #require(Redaction.invert(buf, rect: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let p = try #require(PixelBuffer(image: out)).pixel(x: 0, y: 0)
        #expect(p.r == 0 && p.g == 0 && p.b == 0 && p.a == 255)
    }

    @MainActor
    @Test func flattenCropsToSelectionAndDrawsAnnotations() throws {
        let doc = EditorDocument(image: makeTestImage(), pixelScale: 1)
        doc.selection = CGRect(x: 10, y: 10, width: 60, height: 40)
        doc.selectTool(.rectangleFilled)
        doc.settings.color = RGBAColor(hex: 0x0000FF)
        doc.pointerDown(at: CGPoint(x: 20, y: 20), tolerance: 2)
        doc.pointerMoved(to: CGPoint(x: 40, y: 40))
        doc.pointerUp()

        let image = try #require(doc.flattenedImage())
        try #require(image.width == 60 && image.height == 40)
        #expect(image.width == 60 && image.height == 40)
        let px = try #require(PixelBuffer(image: image))
        // (30, 30) in the image → (20, 20) in the crop: inside the blue rect.
        let inside = px.pixel(x: 20, y: 20)
        #expect(inside.b > 200 && inside.r < 50)
        // (12, 12) → (2, 2): untouched white background.
        let outside = px.pixel(x: 2, y: 2)
        #expect(outside.r > 240 && outside.g > 240)
    }

    @Test func textBoxGrowsWithContent() {
        let short = TextLayout.boxSize(for: "Hi", fontSize: 20, padding: 5)
        let long = TextLayout.boxSize(for: "Hello, world", fontSize: 20, padding: 5)
        let twoLines = TextLayout.boxSize(for: "Hi\nthere", fontSize: 20, padding: 5)
        #expect(long.width > short.width)
        #expect(twoLines.height > short.height)
    }

    @Test func pngRoundTrip() throws {
        let data = try #require(ImageEncoding.png(makeTestImage()))
        let decoded = try #require(ImageEncoding.decode(data))
        #expect(decoded.width == 200 && decoded.height == 100)
    }
}

@Suite("Broadcast frame store")
struct FrameStoreTests {
    @Test func ringBufferOverwritesOldestSlots() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ember-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BroadcastFrameStore(directory: dir, capacity: 3)
        for i in 0..<7 {
            try store.write(Data([UInt8(i)]), slot: i)
        }
        let frames = store.frames()
        #expect(frames.count == 3)
        store.clear()
        #expect(store.frames().isEmpty)
    }
}
