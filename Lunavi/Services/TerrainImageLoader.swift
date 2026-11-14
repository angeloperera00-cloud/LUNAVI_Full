import CoreGraphics
import Foundation
import ImageIO

/// An immutable decoded image that can cross actor boundaries.
struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}

enum TerrainImageError: LocalizedError, Sendable {
    case missing(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "The basemap \(name) is not in the app bundle."
        case .unreadable(let name):
            return "The basemap \(name) could not be decoded."
        }
    }
}

/// Decodes the basemap off the main thread with ImageIO, downsampled to `maxPixelSize`.
enum TerrainImageLoader {
    static func load(resource: String, ext: String, maxPixelSize: Int) async throws -> DecodedImage {
        let name = "\(resource).\(ext)"
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw TerrainImageError.missing(name)
        }
        return try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw TerrainImageError.unreadable(name)
            }
            // ImageIO option keys are CFStrings whose values equal their names; string literals
            // avoid capturing imported CF globals inside this @Sendable closure.
            let options = [
                "kCGImageSourceCreateThumbnailFromImageAlways": true,
                "kCGImageSourceCreateThumbnailWithTransform": true,
                "kCGImageSourceShouldCacheImmediately": true,
                "kCGImageSourceThumbnailMaxPixelSize": maxPixelSize,
            ] as [String: Any] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                throw TerrainImageError.unreadable(name)
            }
            return DecodedImage(cgImage: image)
        }.value
    }
}
