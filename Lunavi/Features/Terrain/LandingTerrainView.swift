import SwiftUI

/// Compact Terrain Characteristics section for the inspector. Shows pipeline-computed DEM values only
/// when they exist and are valid; otherwise says why they are not available. Never rates safety.
struct LandingTerrainView: View {
    let siteID: String?
    @Environment(MissionStore.self) private var store
    @State private var showsDetails = false

    private var terrain: TerrainCharacteristics? { store.terrain(for: siteID) }

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            HStack {
                Text("Terrain Characteristics").lunaviSectionLabel()
                Spacer()
                if terrain?.available == true {
                    Button(showsDetails ? "Less" : "Details") { showsDetails.toggle() }
                        .font(LunaviTypography.captionEmphasis)
                        .buttonStyle(.plain)
                        .foregroundStyle(LunaviColors.selectedTime)
                        .accessibilityIdentifier("terrain.details")
                }
            }
            PanelCard {
                VStack(alignment: .leading, spacing: 6) {
                    content
                    Text(LunarTerrainAnalysis.disclaimer)
                        .font(LunaviTypography.micro.weight(.semibold))
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("terrain.disclaimer")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terrain")
    }

    @ViewBuilder
    private var content: some View {
        if let terrain, terrain.available {
            KeyValueRow("Elevation", LunarTerrainAnalysis.metersText(terrain.elevationM))
            KeyValueRow("Local slope", LunarTerrainAnalysis.slopeText(terrain))
            KeyValueRow("Roughness (RMS)", LunarTerrainAnalysis.metersText(terrain.roughnessM, digits: 2))
            Text(LunarTerrainAnalysis.scopeText(terrain))
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if showsDetails {
                KeyValueRow("Relief in disc", LunarTerrainAnalysis.metersText(terrain.reliefM))
                if let source = terrain.source {
                    Text("Source: \(source)")
                        .font(LunaviTypography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let method = terrain.method {
                    Text(method)
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(terrain.limitations ?? [], id: \.self) { line in
                    Text("• \(line)")
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let terrain {
            Label("Not available", systemImage: "questionmark.diamond")
                .font(LunaviTypography.captionEmphasis)
                .foregroundStyle(LunaviColors.unknown)
            Text(terrain.reason ?? "The pipeline could not characterize the terrain here.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(store.isSimulated
                 ? "Simulated demo — no terrain data. Values appear for computed scenarios (pipeline schema 3)."
                 : "No terrain values in this dataset. Rebuild it with the current pipeline (schema 3) to add elevation, slope and roughness.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Terrain — simulated", traits: .fixedLayout(width: 360, height: 300)) {
    PreviewHost(phase: .original) {
        LandingTerrainView(siteID: "demo-point-a")
            .padding()
    }
}
