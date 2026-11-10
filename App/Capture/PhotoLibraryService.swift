import EmberKit
import Photos
import UIKit

/// The primary iPad "capture" path: the user takes a system screenshot (top
/// button + volume up, or the Pencil corner swipe) and Ember opens the newest
/// one.
enum PhotoLibraryService {
    struct LatestScreenshot: Equatable {
        let assetID: String
        let creationDate: Date?
        let thumbnail: UIImage?
    }

    enum Failure: LocalizedError {
        case notAuthorized
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Ember doesn't have access to your photos. You can allow it in Settings › Privacy › Photos."
            case .unreadable: "That image couldn't be read."
            }
        }
    }

    static var readStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var canRead: Bool {
        readStatus == .authorized || readStatus == .limited
    }

    static func requestReadAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Newest asset tagged as a screenshot.
    static func latestScreenshotAsset() -> PHAsset? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                        Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: options).firstObject
    }

    static func latestScreenshot(thumbnailSize: CGSize) async -> LatestScreenshot? {
        guard canRead, let asset = latestScreenshotAsset() else { return nil }
        let thumb = await thumbnail(for: asset, size: thumbnailSize)
        return LatestScreenshot(assetID: asset.localIdentifier, creationDate: asset.creationDate, thumbnail: thumb)
    }

    static func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // exactly one callback
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Full-resolution pixels of an asset.
    static func fullImage(assetID: String) async throws -> CGImage {
        guard canRead else { throw Failure.notAuthorized }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            throw Failure.unreadable
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let image = ImageEncoding.decode(data) else { throw Failure.unreadable }
        return image
    }

    /// Save PNG data as a new photo. Needs only add-only access.
    static func save(pngData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: pngData, options: nil)
        }
    }
}
