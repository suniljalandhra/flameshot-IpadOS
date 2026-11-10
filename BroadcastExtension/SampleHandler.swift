import CoreImage
import CoreMedia
import EmberKit
import ImageIO
import ReplayKit

/// ReplayKit Broadcast Upload Extension: receives the **whole device screen**
/// while a broadcast runs and keeps the latest frames in the App Group, where
/// the app picks them up. This is the closest iPadOS gets to Flameshot's
/// "freeze the screen".
///
/// Extensions are limited to ~50 MB, so each frame is encoded to HEIC and
/// written straight to a fixed ring of slots on disk.
final class SampleHandler: RPBroadcastSampleHandler {
    /// Seconds between stored frames (2 fps).
    private static let interval: TimeInterval = 0.5

    private let store = BroadcastFrameStore.appGroup()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var lastWrite = Date.distantPast
    private var slot = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard store != nil else {
            finishBroadcastWithError(NSError(domain: "Ember", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Ember's App Group isn't set up. Check the entitlements in Xcode.",
            ]))
            return
        }
        store?.clear()
        slot = 0
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Called serially on ReplayKit's queue; doing the work inline simply
        // drops frames while we encode, which is what we want.
        guard sampleBufferType == .video,
              Date().timeIntervalSince(lastWrite) >= Self.interval,
              let store,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastWrite = Date()

        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixelBuffer)
            if let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
               let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
                image = image.oriented(orientation)
            }
            guard let cgImage = ciContext.createCGImage(image, from: image.extent),
                  let data = ImageEncoding.heic(cgImage, quality: 0.85)
            else { return }
            try? store.write(data, slot: slot)
            slot = (slot + 1) % store.capacity
        }
    }
}
