import Foundation

public struct BroadcastFrame: Identifiable, Hashable, Sendable {
    public var url: URL
    public var date: Date
    /// Slots are reused, so the identity includes the write time.
    public var id: String { "\(url.lastPathComponent)@\(date.timeIntervalSince1970)" }
}

/// A fixed ring of recent screen frames shared between the ReplayKit broadcast
/// extension (writer) and the app (reader) through the App Group container.
///
/// The extension has a ~50 MB memory limit, so frames go straight to disk as
/// HEIC files in a fixed number of slots; nothing accumulates.
public struct BroadcastFrameStore: Sendable {
    /// Info.plist key (in both targets) holding the App Group identifier.
    public static let infoPlistKey = "EmberAppGroup"

    public let directory: URL
    public let capacity: Int

    public init(directory: URL, capacity: Int = 10) {
        self.directory = directory
        self.capacity = max(capacity, 1)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The store in the App Group named by the bundle's `EmberAppGroup` key.
    public static func appGroup(bundle: Bundle = .main, capacity: Int = 10) -> BroadcastFrameStore? {
        guard let group = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return BroadcastFrameStore(directory: container.appendingPathComponent("BroadcastFrames", isDirectory: true),
                                   capacity: capacity)
    }

    public func url(forSlot slot: Int) -> URL {
        directory.appendingPathComponent("frame-\(((slot % capacity) + capacity) % capacity).heic")
    }

    public func write(_ data: Data, slot: Int) throws {
        try data.write(to: url(forSlot: slot), options: .atomic)
    }

    /// Stored frames, newest first.
    public func frames() -> [BroadcastFrame] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("frame-") }
            .compactMap { url in
                guard let date = try? url.resourceValues(forKeys: keys).contentModificationDate else { return nil }
                return BroadcastFrame(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    public func clear() {
        for frame in frames() { try? FileManager.default.removeItem(at: frame.url) }
    }
}
