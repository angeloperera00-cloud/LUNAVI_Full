import SwiftUI

/// Searchable site browser. Sites without data show an unavailable state instead of measurements.
struct SiteExplorerView: View {
    @Environment(MissionStore.self) private var store
    @Environment(MapState.self) private var mapState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String?

    private var filtered: [LunarSite] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.sites }
        return store.sites.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.shortName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let mapped = filtered.filter { $0.mapPosition != nil }
                let catalog = filtered.filter { $0.mapPosition == nil }
                if !mapped.isEmpty {
                    Section("On the map") {
                        ForEach(mapped) { site in
                            row(site)
                        }
                    }
                }
                if !catalog.isEmpty {
                    Section("Published sites — catalogue only") {
                        ForEach(catalog) { site in
                            row(site)
                        }
                    }
                }
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LunaviColors.backgroundSecondary)
            .searchable(text: $query, prompt: "Search sites")
            .navigationTitle("Site Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("siteExplorer.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
        .onAppear {
            selectedID = store.committedPlan?.siteID
        }
    }

    private func row(_ site: LunarSite) -> some View {
        let isSelected = selectedID == site.id
        let hasData = store.hasData(siteID: site.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                selectedID = isSelected ? nil : site.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name)
                            .font(LunaviTypography.bodyEmphasis)
                            .foregroundStyle(LunaviColors.textPrimary)
                        Text(site.kindDescription)
                            .font(LunaviTypography.micro)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                    Spacer()
                    if site.id == store.committedPlan?.siteID {
                        Text("CURRENT")
                            .font(LunaviTypography.captionEmphasis)
                            .foregroundStyle(LunaviColors.selectedTime)
                    }
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .foregroundStyle(LunaviColors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("siteExplorer.row.\(site.id)")

            if isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    KeyValueRow("Position", site.positionDescription)
                    KeyValueRow("Terrain data", site.hasTerrainData ? "Available" : "Not bundled", valueColor: site.hasTerrainData ? LunaviColors.success : LunaviColors.textMuted)
                    KeyValueRow("Visibility analysis", hasData ? "Available (\(store.dataSource?.label ?? "—"))" : "Unavailable", valueColor: hasData ? LunaviColors.success : LunaviColors.textMuted)
                    Text(site.terrainDataNote)
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(site.sourceNote)
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hasData {
                        Label("No terrain or visibility data is bundled for this site, so LUNAVI shows no measurements. Import computed results to analyse it (see Data & Method).", systemImage: "exclamationmark.circle")
                            .font(LunaviTypography.caption)
                            .foregroundStyle(LunaviColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: LunaviSpacing.s) {
                        if let position = site.mapPosition {
                            Button("Show on Map") {
                                mapState.center(on: position, minimumZoom: 1.6)
                                mapState.inspectedSiteID = site.id
                                dismiss()
                            }
                            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                            .accessibilityIdentifier("siteExplorer.showOnMap")
                            if site.id != store.committedPlan?.siteID {
                                Button("Plan Mission Here") {
                                    store.planMission(at: site.id)
                                    mapState.center(on: position)
                                    dismiss()
                                }
                                .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
                                .disabled(!store.canEditParameters)
                                .accessibilityIdentifier("siteExplorer.plan")
                            }
                        }
                    }
                    if site.mapPosition != nil, site.id != store.committedPlan?.siteID, !store.canEditParameters {
                        Text("Use Edit Plan… in the inspector to change the site while a comparison is open.")
                            .font(LunaviTypography.micro)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(LunaviColors.surfaceElevated)
    }
}
