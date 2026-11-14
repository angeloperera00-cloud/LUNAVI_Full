import SwiftUI

/// Geometry of the basemap square in view coordinates.
struct MapFrame {
    var origin: CGPoint
    var side: CGFloat

    func point(for mapPoint: MapPoint) -> CGPoint {
        CGPoint(x: origin.x + mapPoint.x * side, y: origin.y + mapPoint.y * side)
    }

    func mapPoint(for viewPoint: CGPoint) -> MapPoint {
        MapPoint(x: Double((viewPoint.x - origin.x) / side), y: Double((viewPoint.y - origin.y) / side))
    }
}

/// The dominant map surface. Pinch, drag, double-tap and the zoom controls change only the
/// viewport; pins are an overlay so labels stay crisp and readable at every zoom level.
struct LunarMapView: View {
    @Environment(MissionStore.self) private var store
    @Environment(MapState.self) private var mapState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var terrain: DecodedImage?
    @State private var terrainError: String?
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let frame = liveFrame(viewport: viewport)
            ZStack(alignment: .topLeading) {
                LunaviColors.mapBasalt
                terrainLayer(frame: frame, viewport: viewport)
                connectorLayer(frame: frame)
                pinsLayer(frame: frame)
            }
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture.simultaneously(with: pinchGesture))
            .simultaneousGesture(doubleTapGesture)
            .overlay(alignment: .topLeading) {
                MapHeaderPlate(basemap: store.basemap)
                    .padding(LunaviSpacing.l)
            }
            .overlay(alignment: .topTrailing) {
                sitePreview
                    .padding(LunaviSpacing.l)
            }
            .overlay(alignment: .trailing) {
                MapControlsView(onCenterActive: centerOnActiveSite)
                    .padding(.trailing, LunaviSpacing.l)
            }
            .overlay(alignment: .bottomLeading) {
                MapLegendView()
                    .padding(LunaviSpacing.l)
            }
            .overlay(alignment: .bottomTrailing) {
                MapReadoutView()
                    .padding(LunaviSpacing.l)
            }
            .overlay(alignment: .bottom) {
                scaleBar(frame: frame)
                    .padding(.bottom, LunaviSpacing.l)
            }
            .onAppear {
                mapState.viewportSize = viewport
            }
            .onChange(of: viewport) { _, newValue in
                mapState.viewportSize = newValue
            }
        }
        .task(id: store.basemap?.imageResource) {
            await loadTerrain()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lunar map")
        .accessibilityIdentifier("map")
    }

    // MARK: - Geometry

    private func liveFrame(viewport: CGSize) -> MapFrame {
        let liveScale = mapState.clampScale(mapState.scale * pinch)
        let ratio = liveScale / max(mapState.scale, 0.0001)
        let proposed = CGSize(
            width: mapState.offset.width * ratio + pan.width,
            height: mapState.offset.height * ratio + pan.height
        )
        let offset = mapState.clampOffset(proposed, scale: liveScale, viewport: viewport)
        let side = MapState.contentSide(for: viewport, scale: liveScale)
        let origin = CGPoint(
            x: (viewport.width - side) / 2 + offset.width,
            y: (viewport.height - side) / 2 + offset.height
        )
        return MapFrame(origin: origin, side: side)
    }

    // MARK: - Layers

    @ViewBuilder
    private func terrainLayer(frame: MapFrame, viewport: CGSize) -> some View {
        if let terrain {
            Image(decorative: terrain.cgImage, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.side, height: frame.side)
                .position(x: frame.origin.x + frame.side / 2, y: frame.origin.y + frame.side / 2)
                .accessibilityHidden(true)
        } else if let terrainError {
            VStack(spacing: LunaviSpacing.s) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text(terrainError)
                    .font(LunaviTypography.caption)
                    .multilineTextAlignment(.center)
                Text("Pins and analysis remain available.")
                    .font(LunaviTypography.micro)
            }
            .foregroundStyle(LunaviColors.textMuted)
            .padding(LunaviSpacing.xl)
            .frame(width: viewport.width, height: viewport.height)
        } else {
            ProgressView()
                .frame(width: viewport.width, height: viewport.height)
        }
    }

    @ViewBuilder
    private func connectorLayer(frame: MapFrame) -> some View {
        if let from = store.committedSite?.mapPosition, let to = store.connectorTargetSite?.mapPosition {
            let a = frame.point(for: from)
            let b = frame.point(for: to)
            Path { path in
                path.move(to: a)
                path.addLine(to: b)
            }
            .stroke(LunaviColors.alternativeSite.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5]))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            Text("Site-change preview")
                .font(LunaviTypography.micro)
                .foregroundStyle(LunaviColors.alternativeSite)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func pinsLayer(frame: MapFrame) -> some View {
        ForEach(store.mapSites) { site in
            if let position = site.mapPosition {
                MapPinView(
                    site: site,
                    role: store.pinRole(for: site.id),
                    detail: store.pinDetail(for: site.id),
                    isInspected: mapState.inspectedSiteID == site.id
                ) {
                    mapState.inspectedSiteID = site.id
                }
                .position(frame.point(for: position))
            }
        }
    }

    @ViewBuilder
    private var sitePreview: some View {
        if let id = mapState.inspectedSiteID, let site = store.site(id: id) {
            SitePreviewCard(site: site)
        }
    }

    @ViewBuilder
    private func scaleBar(frame: MapFrame) -> some View {
        if let basemap = store.basemap, !basemap.isIllustrative, let metersPerPixel = basemap.metersPerPixel, frame.side > 0 {
            MapScaleBar(metersPerPoint: metersPerPixel * Double(basemap.pixelWidth) / Double(frame.side))
        }
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                mapState.setScale(mapState.scale * value.magnification)
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($pan) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                mapState.commitPan(value.translation)
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let target = mapState.scale < 2 ? mapState.scale * 2 : 1
                animate {
                    mapState.setScale(target, anchor: value.location)
                }
            }
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.3), change)
        }
    }

    private func centerOnActiveSite() {
        guard let site = store.committedSite, let position = site.mapPosition else { return }
        mapState.center(on: position, minimumZoom: 1.6)
        mapState.inspectedSiteID = site.id
    }

    private func loadTerrain() async {
        guard let basemap = store.basemap else { return }
        do {
            terrain = try await TerrainImageLoader.load(resource: basemap.imageResource, ext: basemap.imageExtension, maxPixelSize: 4096)
            terrainError = nil
        } catch {
            terrain = nil
            terrainError = "Lunar imagery unavailable: \(error.localizedDescription)"
        }
    }
}

#Preview("Map — delayed plan", traits: .landscapeLeft) {
    PreviewHost(phase: .delayed) {
        LunarMapView()
    }
}
