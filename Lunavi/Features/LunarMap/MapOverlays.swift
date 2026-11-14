import SwiftUI

/// Title plate. An illustrative basemap is always labelled as such.
struct MapHeaderPlate: View {
    let basemap: BasemapManifest?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lunar South Pole")
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
            if let basemap {
                if basemap.isIllustrative {
                    Text("ILLUSTRATIVE TERRAIN")
                        .font(LunaviTypography.captionEmphasis)
                        .tracking(1)
                        .foregroundStyle(LunaviColors.selectedTime)
                    Text("Procedurally generated · not NASA data · not to scale")
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                } else {
                    Text(basemap.title)
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textSecondary)
                    Text(basemap.attribution)
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.terrainLabel")
    }
}

struct MapControlsView: View {
    let onCenterActive: () -> Void
    @Environment(MapState.self) private var mapState
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            control("plus", label: "Zoom in", identifier: "map.zoomIn") { mapState.zoomIn() }
            Hairline()
            control("minus", label: "Zoom out", identifier: "map.zoomOut") { mapState.zoomOut() }
            Hairline()
            control("arrow.up.left.and.arrow.down.right", label: "Fit to region", identifier: "map.fit") { mapState.fitToRegion() }
            Hairline()
            control("scope", label: "Center on the current site", identifier: "map.centerActive", action: onCenterActive)
            Hairline()
            control("sun.horizon", label: "Shadow analysis for the inspected site", identifier: "map.shadowAnalysis") {
                navigation.isShadowAnalysisPresented = true
            }
        }
        .frame(width: LunaviSpacing.minimumTouchTarget)
        .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
    }

    private func control(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeInOut(duration: 0.25), action)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LunaviColors.textPrimary)
                .frame(width: LunaviSpacing.minimumTouchTarget, height: LunaviSpacing.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct MapLegendView: View {
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Legend")
                        .lunaviSectionLabel()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LunaviColors.textMuted)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide legend" : "Show legend")
            if isExpanded {
                row(symbol: AnyView(Circle().fill(LunaviColors.activeSite).frame(width: 10, height: 10)), text: "Current site")
                row(symbol: AnyView(Rectangle().fill(LunaviColors.alternativeSite).frame(width: 9, height: 9).rotationEffect(.degrees(45))), text: "Alternative site")
                row(symbol: AnyView(TriangleShape().fill(LunaviColors.failureFill).frame(width: 12, height: 10)), text: "Obstruction / requirement not met")
                row(symbol: AnyView(dashedLine), text: "Site-change preview")
                row(symbol: AnyView(Circle().fill(LunaviColors.unselectedSite).frame(width: 8, height: 8)), text: "Other site")
            }
        }
        .padding(10)
        .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.legend")
    }

    private var dashedLine: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 16, y: 5))
        }
        .stroke(LunaviColors.alternativeSite, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        .frame(width: 16, height: 10)
    }

    private func row(symbol: AnyView, text: String) -> some View {
        HStack(spacing: 8) {
            symbol
                .frame(width: 16, height: 12)
            Text(text)
                .font(LunaviTypography.micro)
                .foregroundStyle(LunaviColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Position of the inspected (or current) site. Illustrative positions are labelled as such.
struct MapReadoutView: View {
    @Environment(MissionStore.self) private var store
    @Environment(MapState.self) private var mapState

    var body: some View {
        if let site = store.site(id: mapState.inspectedSiteID) ?? store.committedSite {
            VStack(alignment: .trailing, spacing: 2) {
                Text(site.name)
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(LunaviColors.textPrimary)
                Text(site.positionDescription)
                    .font(LunaviTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(LunaviColors.textMuted)
                    .multilineTextAlignment(.trailing)
            }
            .padding(10)
            .frame(maxWidth: 260, alignment: .trailing)
            .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("map.readout")
        }
    }
}

/// Scale bar — only for georeferenced basemaps. Never shown on the illustrative terrain.
struct MapScaleBar: View {
    let metersPerPoint: Double

    var body: some View {
        let length = Self.niceLength(metersPerPoint * 120)
        let width = CGFloat(length / metersPerPoint)
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.label(length))
                .font(LunaviTypography.micro)
                .monospacedDigit()
                .foregroundStyle(LunaviColors.textPrimary)
            Rectangle()
                .fill(LunaviColors.textPrimary)
                .frame(width: width, height: 2)
        }
        .padding(8)
        .background(LunaviColors.mapPlate, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale bar, \(Self.label(length))")
    }

    static func niceLength(_ meters: Double) -> Double {
        let candidates: [Double] = [50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000]
        return candidates.last(where: { $0 <= meters }) ?? candidates[0]
    }

    static func label(_ meters: Double) -> String {
        meters >= 1_000 ? "\(Int(meters / 1_000)) km" : "\(Int(meters)) m"
    }
}

/// Nearby-site preview: same timing as the committed plan at another site. Never commits.
struct SitePreviewCard: View {
    let site: LunarSite
    @Environment(MissionStore.self) private var store
    @Environment(MapState.self) private var mapState

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            HStack {
                Text("Site preview")
                    .lunaviSectionLabel()
                Spacer()
                Button {
                    mapState.inspectedSiteID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LunaviColors.textMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close site preview")
                .accessibilityIdentifier("map.sitePreview.close")
            }
            Text(site.name)
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
            Text(site.kindDescription)
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
            if let plan = store.committedPlan, let evaluation = store.evaluationAtCommittedTiming(siteID: site.id) {
                HStack(spacing: LunaviSpacing.s) {
                    OverallStatusBadge(overall: evaluation.overall)
                    Text("at \(UTCFormat.dayMonthTime(plan.start)) UTC · \(plan.durationHours) h")
                        .font(LunaviTypography.micro)
                        .monospacedDigit()
                        .foregroundStyle(LunaviColors.textSecondary)
                }
            }
            Text(site.terrainDataNote)
                .font(LunaviTypography.micro)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if site.id != store.committedPlan?.siteID {
                if store.canEditParameters {
                    Button("Plan Mission Here") {
                        store.planMission(at: site.id)
                        mapState.inspectedSiteID = nil
                    }
                    .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                    .accessibilityIdentifier("map.sitePreview.plan")
                } else {
                    Text("Return to plan editing to change the mission site.")
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(LunaviColors.background.opacity(0.94), in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium).stroke(LunaviColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.sitePreview")
    }
}
