import SwiftUI

/// Scientific transparency: what the session uses, what LUNAVI calculates, and the limits.
struct DataAndMethodView: View {
    @Environment(MissionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LunaviSpacing.xl) {
                    disclaimer
                    sessionStatus
                    if let metadata = store.metadata {
                        imagerySection(metadata)
                        elevationSection
                        ephemerisSection(metadata)
                        horizonsSection
                        methodSection
                        criteriaSection(metadata)
                        limitationsSection(metadata)
                        provenanceSection(metadata)
                        validationSection(metadata)
                    }
                    sensitivitySection
                    attributionSection
                }
                .padding(LunaviSpacing.xl)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(LunaviColors.backgroundSecondary)
            .navigationTitle("Data & Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("dataMethod.done")
                }
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
    }

    // MARK: Sections

    private var disclaimer: some View {
        Text("LUNAVI is an independent project for the NASA Space Apps Challenge 2026. It uses publicly available NASA data and tools and is not affiliated with, endorsed by, or approved by NASA. Results are geometric visibility analyses, not operational flight products.")
            .font(LunaviTypography.caption)
            .foregroundStyle(LunaviColors.textSecondary)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(LunaviColors.border, lineWidth: 1))
    }

    private var sessionStatus: some View {
        section("Session data source", systemImage: "externaldrive") {
            ForEach(DataSourceKind.allCases, id: \.self) { kind in
                let active = kind == store.dataSource
                HStack(spacing: 10) {
                    Image(systemName: active ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(active ? LunaviColors.selectedTime : LunaviColors.textMuted)
                    Text(kind.sessionDescription)
                        .foregroundStyle(active ? LunaviColors.textPrimary : LunaviColors.textMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Text("A session uses exactly one source. Sources are never mixed.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
            if let notice = store.dataNotice {
                NoticeBanner(text: notice)
            }
        }
        .accessibilityIdentifier("dataMethod.session")
    }

    private func imagerySection(_ metadata: DatasetMetadata) -> some View {
        section("Lunar imagery", systemImage: "photo") {
            if store.basemap?.isIllustrative ?? true {
                Text("This build bundles an illustrative, procedurally generated terrain image. It is not NASA data, is not georeferenced, and has no scale. No LROC imagery is bundled.")
            } else {
                Text(store.basemap?.attribution ?? "")
            }
            Text("Integration path: LROC RDR polar products from the PDS archive, or the LOLA-derived hillshade in PGDA product 90, cropped and georeferenced by ScienceService/basemap. LROC credit: NASA/GSFC/Arizona State University.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
            link("LRO data products", "https://science.nasa.gov/mission/lro/data-products/")
        }
    }

    private var elevationSection: some View {
        section("Lunar elevation", systemImage: "mountain.2") {
            Text("LOLA digital elevation models from NASA's Planetary Geodynamics Data Archive. Product 78 provides 5 m/pixel DEMs around named south-pole sites (MOON_ME, DE421; about 90 % of pixels interpolated). Product 90 provides 10–240 m/pixel south-pole DEMs used for the distant horizon. Product 69 provides long-term average illumination and Earth-visibility maps used as a validation reference.")
            Text(store.isSimulated ? "Not used in this session (simulated fixture)." : "Used in this session — see provenance below.")
                .font(LunaviTypography.caption)
                .foregroundStyle(LunaviColors.textMuted)
            link("PGDA product 78", "https://pgda.gsfc.nasa.gov/products/78")
            link("PGDA product 90", "https://pgda.gsfc.nasa.gov/products/90")
            link("PGDA product 69", "https://pgda.gsfc.nasa.gov/products/69")
        }
    }

    private func ephemerisSection(_ metadata: DatasetMetadata) -> some View {
        section("Astronomical position — NASA NAIF SPICE", systemImage: "sun.max") {
            Text("Sun and Earth directions come from JPL planetary ephemerides and the high-accuracy lunar orientation kernels, evaluated with SPICE in the MOON_ME frame (the frame of the LOLA DEMs), with light-time and stellar-aberration corrections.")
            KeyValueRow("Ephemeris", metadata.ephemeris)
            KeyValueRow("Reference frame", metadata.referenceFrame)
            link("NAIF generic kernels", "https://naif.jpl.nasa.gov/naif/data_generic.html")
        }
    }

    private var horizonsSection: some View {
        section("Independent reference — JPL Horizons", systemImage: "scope") {
            Text("The pipeline queries the Horizons API for apparent azimuth and elevation of the Sun and Earth from each site and compares them with the SPICE values. This checks ephemeris geometry only; it does not validate the terrain horizon.")
            link("Horizons API documentation", "https://ssd-api.jpl.nasa.gov/doc/horizons.html")
        }
    }

    private var methodSection: some View {
        section("Calculation method", systemImage: "list.number") {
            let steps = [
                "Select the observation position (latitude, longitude, observer height).",
                "Calculate Sun and Earth geometric directions at the selected UTC times (SPICE).",
                "Construct the local terrain horizon from LOLA elevation data, including lunar curvature.",
                "Compare each direction, with its disc size, against the horizon at that azimuth.",
                "Produce timestamped visibility intervals, refining each transition by bisection.",
                "Check whether both requirements cover the whole operating window without interruption.",
                "Compare the original and revised scenarios with identical requirements.",
                "Search supported recovery candidates: same site later, or another site at the same time.",
                "Report assumptions, provenance and validation state.",
            ]
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(LunaviColors.selectedTime)
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if store.isSimulated {
                Text("In this session steps 1–5 are replaced by the simulated fixture; steps 6–9 run exactly as they would on computed data.")
                    .font(LunaviTypography.caption)
                    .foregroundStyle(LunaviColors.selectedTime)
            }
        }
    }

    private func criteriaSection(_ metadata: DatasetMetadata) -> some View {
        section("Visibility criteria and assumptions", systemImage: "ruler") {
            KeyValueRow("Sun", metadata.sunCriterion)
            KeyValueRow("Earth", metadata.earthCriterion)
            KeyValueRow("Time step", metadata.timeStepSeconds.map { "\(Int($0)) s" } ?? "Not applicable")
            KeyValueRow("Observer height", metadata.observerHeightMeters.map { "\($0.formatted(.number.precision(.fractionLength(1)))) m" } ?? "Not applicable")
            KeyValueRow("Minimum clearance", metadata.minimumClearanceDeg.map { "\($0.formatted(.number.precision(.fractionLength(2))))°" } ?? "Not applicable")
            bullets(metadata.assumptions)
        }
    }

    private func limitationsSection(_ metadata: DatasetMetadata) -> some View {
        section("Scientific limitations", systemImage: "exclamationmark.triangle") {
            bullets([
                "Sun geometrically visible does not guarantee enough power generation.",
                "Earth geometrically visible does not guarantee radio link quality.",
                "Favorable visibility does not certify landing safety.",
                "Terrain resolution affects obstruction predictions.",
                "Observer height changes the local horizon.",
                "Ephemeris and reference-frame choices must be documented.",
                "Time sampling can affect detected boundary times.",
                "Results cannot be considered operational flight certification.",
            ] + metadata.limitations)
        }
    }

    private func provenanceSection(_ metadata: DatasetMetadata) -> some View {
        section("Data provenance", systemImage: "doc.text.magnifyingglass") {
            ForEach(metadata.provenance) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.role)
                        .lunaviSectionLabel()
                    Text(record.name)
                        .font(LunaviTypography.bodyEmphasis)
                        .foregroundStyle(LunaviColors.textPrimary)
                    KeyValueRow("Provider", record.provider)
                    KeyValueRow("Version", record.version)
                    KeyValueRow("Resolution", record.resolution)
                    KeyValueRow("Coordinate system", record.coordinateSystem)
                    KeyValueRow("Status", record.status)
                    if let link = record.link {
                        self.link("Source documentation", link)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
            }
        }
        .accessibilityIdentifier("dataMethod.provenance")
    }

    private func validationSection(_ metadata: DatasetMetadata) -> some View {
        section("Validation", systemImage: "checkmark.shield") {
            ForEach(metadata.validation) { record in
                VStack(alignment: .leading, spacing: 2) {
                    KeyValueRow(record.component, record.level.label)
                    Text(record.detail)
                        .font(LunaviTypography.caption)
                        .foregroundStyle(LunaviColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(metadata.disclaimer)
                .font(LunaviTypography.captionEmphasis)
                .foregroundStyle(LunaviColors.selectedTime)
        }
    }

    private var sensitivitySection: some View {
        section("Scientific sensitivity", systemImage: "slider.horizontal.3") {
            ScientificSensitivityView()
        }
    }

    private var attributionSection: some View {
        section("Attribution", systemImage: "quote.bubble") {
            bullets([
                "LOLA data: NASA Goddard Space Flight Center, Planetary Geodynamics Data Archive (Barker et al. 2021, 2023; Mazarico et al. 2011).",
                "SPICE kernels and Horizons: NASA JPL (NAIF; Solar System Dynamics).",
                "LROC imagery, when used: NASA/GSFC/Arizona State University.",
                "Wueller et al. (2026), JGR Planets 131, e2025JE009434; dataset CC BY 4.0 — used only if imported.",
                "Illustrative terrain and app icon: LUNAVI project, Apache-2.0.",
            ])
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            Label(title, systemImage: systemImage)
                .font(LunaviTypography.headline)
                .foregroundStyle(LunaviColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
                .font(LunaviTypography.body)
                .foregroundStyle(LunaviColors.textSecondary)
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(LunaviTypography.caption)
            }
        }
    }

    @ViewBuilder
    private func link(_ title: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                Label(title, systemImage: "arrow.up.right.square")
                    .font(LunaviTypography.caption)
            }
            .foregroundStyle(LunaviColors.selectedTime)
        }
    }
}

#Preview("Data & Method", traits: .landscapeLeft) {
    PreviewHost(phase: .original) {
        DataAndMethodView()
    }
}
