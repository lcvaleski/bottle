import AppKit
import Foundation
import Observation

/// App icons pulled off the phone with `cfgutil get-app-icon`, downscaled and
/// cached per device under ~/Library/Caches/Cable/Icons/<UDID>/.
@MainActor
@Observable
final class IconCache {
    static let root: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Cable/Icons", isDirectory: true)
    }()
    private static let cachedSize = 128
    private static let batchSize = 60

    private(set) var images: [String: NSImage] = [:]
    /// Bundle IDs the phone said it has no icon for; don't ask again this session.
    private var missing: Set<String> = []
    private var loadedDeviceKey: String?
    private var isFetching = false

    private let cfgutil: CfgUtil

    init(cfgutil: CfgUtil) {
        self.cfgutil = cfgutil
    }

    func image(for bundleID: String) -> NSImage? {
        if Demo.isOn { return Demo.placeholderIcon(for: bundleID) }
        return images[bundleID]
    }

    /// Loads whatever is on disk for this phone, then fetches icons for any
    /// bundle IDs that aren't cached yet.
    func ensureIcons(for bundleIDs: [String], ecid: String, deviceKey: String) async {
        let directory = Self.root.appendingPathComponent(deviceKey, isDirectory: true)
        if loadedDeviceKey != deviceKey {
            loadFromDisk(directory)
            loadedDeviceKey = deviceKey
        }

        let wanted = bundleIDs.filter { images[$0] == nil && !missing.contains($0) }
        guard !wanted.isEmpty, !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("cable-icons-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for batch in stride(from: 0, to: wanted.count, by: Self.batchSize).map({ Array(wanted[$0..<min($0 + Self.batchSize, wanted.count)]) }) {
            do {
                try await cfgutil.run("get-app-icon", batch, ecid: ecid, timeout: 5, quiet: true, workingDirectory: scratch)
            } catch {
                cfgutil.log.error("Icon fetch failed: \(error.localizedDescription)")
                return
            }

            let fetched = await Self.downscale(batch, from: scratch, into: directory)
            for (bundleID, image) in fetched {
                images[bundleID] = image
            }
            for bundleID in batch where fetched[bundleID] == nil {
                missing.insert(bundleID)
            }
        }
    }

    private func loadFromDisk(_ directory: URL) {
        images.removeAll()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "png" {
            if let image = NSImage(contentsOf: file) {
                images[file.deletingPathExtension().lastPathComponent] = image
            }
        }
    }

    /// Converts cfgutil's 256px 16-bit PNGs into small 8-bit ones. Runs off the main thread.
    private nonisolated static func downscale(_ bundleIDs: [String], from scratch: URL, into directory: URL) async -> [String: NSImage] {
        await Task.detached(priority: .utility) {
            var result: [String: NSImage] = [:]
            for bundleID in bundleIDs {
                let source = scratch.appendingPathComponent("\(bundleID).png")
                guard let original = NSImage(contentsOf: source),
                      let data = pngData(original, size: cachedSize),
                      let image = NSImage(data: data)
                else { continue }
                try? data.write(to: directory.appendingPathComponent("\(bundleID).png"))
                result[bundleID] = image
            }
            return result
        }.value
    }

    private nonisolated static func pngData(_ image: NSImage, size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        return rep.representation(using: .png, properties: [:])
    }
}
