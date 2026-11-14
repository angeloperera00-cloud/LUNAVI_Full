import CoreGraphics
import Foundation
import Observation

/// Map viewport state. Nothing here touches mission data.
///
/// The basemap is drawn as a square of side `max(viewport.width, viewport.height) * scale`
/// (aspect-fill at scale 1), offset from the centred position by `offset`.
@MainActor
@Observable
final class MapState {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var viewportSize: CGSize = .zero
    /// Site whose preview card is open. Inspecting a site never changes the mission.
    var inspectedSiteID: String?

    let minimumScale: CGFloat = 1
    let maximumScale: CGFloat = 4

    nonisolated static func contentSide(for viewport: CGSize, scale: CGFloat) -> CGFloat {
        max(viewport.width, viewport.height) * scale
    }

    func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }

    func clampOffset(_ proposed: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let side = Self.contentSide(for: viewport, scale: scale)
        let limitX = max(0, (side - viewport.width) / 2)
        let limitY = max(0, (side - viewport.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    /// Changes zoom while keeping the content under `anchor` (view coordinates) fixed.
    /// Without an anchor the viewport centre is used.
    func setScale(_ newValue: CGFloat, anchor: CGPoint? = nil) {
        let viewport = viewportSize
        let target = clampScale(newValue)
        guard viewport.width > 0, viewport.height > 0 else {
            scale = target
            return
        }
        let oldSide = Self.contentSide(for: viewport, scale: scale)
        let newSide = Self.contentSide(for: viewport, scale: target)
        let point = anchor ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let originX = (viewport.width - oldSide) / 2 + offset.width
        let originY = (viewport.height - oldSide) / 2 + offset.height
        let fractionX = (point.x - originX) / oldSide
        let fractionY = (point.y - originY) / oldSide
        let proposed = CGSize(
            width: point.x - (viewport.width - newSide) / 2 - fractionX * newSide,
            height: point.y - (viewport.height - newSide) / 2 - fractionY * newSide
        )
        scale = target
        offset = clampOffset(proposed, scale: target, viewport: viewport)
    }

    func commitPan(_ translation: CGSize) {
        offset = clampOffset(
            CGSize(width: offset.width + translation.width, height: offset.height + translation.height),
            scale: scale,
            viewport: viewportSize
        )
    }

    func zoomIn() {
        setScale(scale * 1.6)
    }

    func zoomOut() {
        setScale(scale / 1.6)
    }

    func fitToRegion() {
        scale = 1
        offset = .zero
    }

    /// Centres a map point in the viewport, zooming in to at least `minimumZoom` if given.
    func center(on point: MapPoint, minimumZoom: CGFloat? = nil) {
        if let minimumZoom {
            scale = clampScale(max(scale, minimumZoom))
        }
        let side = Self.contentSide(for: viewportSize, scale: scale)
        let proposed = CGSize(width: side * (0.5 - point.x), height: side * (0.5 - point.y))
        offset = clampOffset(proposed, scale: scale, viewport: viewportSize)
    }

    func reset() {
        fitToRegion()
        inspectedSiteID = nil
    }
}
