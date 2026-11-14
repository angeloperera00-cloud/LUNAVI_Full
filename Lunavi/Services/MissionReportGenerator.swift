import Foundation
import UIKit

/// Builds a `MissionReport` from the store, and renders it as a paginated PDF.
enum MissionReportGenerator {
    // MARK: - Report data

    @MainActor
    static func makeReport(store: MissionStore, createdAt: Date = Date()) -> MissionReport? {
        guard let scenario = store.scenario, let committed = store.committedPlan else { return nil }
        let evaluation = VisibilityEvaluator.evaluate(committed, data: store.visibility(for: committed.siteID))
        let isSimulated = store.isSimulated

        func summary(_ plan: MissionPlan, _ overall: OverallStatus) -> MissionReport.PlanSummary {
            let site = scenario.site(id: plan.siteID)
            return MissionReport.PlanSummary(
                siteID: plan.siteID,
                siteName: site?.name ?? plan.siteID,
                coordinateText: site?.positionDescription ?? "Coordinates not available",
                latitude: site?.coordinate?.latitude,
                longitude: site?.coordinate?.longitude,
                start: plan.start,
                end: plan.end,
                durationHours: plan.durationHours,
                overall: overall
            )
        }

        func candidate(_ c: RecoveryCandidate) -> MissionReport.CandidateSummary {
            MissionReport.CandidateSummary(letter: c.kind.letter, title: c.kind.title, plan: summary(c.plan, c.evaluation.overall),
                                           explanation: c.explanation, benefit: c.benefit, tradeoff: c.tradeoff,
                                           validation: c.validationSummary)
        }

        let delayedFailure = store.delayedEvaluation?.firstFailure.map {
            "\($0.condition.title) obstructed from \(UTCFormat.full($0.time))"
        }
        let rescue = MissionReport.RescueSection(
            originalPlan: store.originalPlan.map { summary($0, store.originalEvaluation?.overall ?? .unknown) },
            delayHours: store.delayHours,
            delayedPlan: store.delayedPlan.map { summary($0, store.delayedEvaluation?.overall ?? .unknown) },
            delayedFailure: delayedFailure,
            hasSearched: store.hasSearchedForRecovery,
            candidates: store.candidates.map(candidate),
            applied: store.appliedCandidate.map(candidate),
            acceptedDelayedPlan: store.acceptedDelayedPlan
        )

        let metadata = scenario.metadata
        let spice = metadata.provenance.first { $0.id == "spice" }
        let science = MissionReport.ScienceSection(
            datasetTitle: metadata.title,
            dataSource: metadata.source.label,
            isSimulated: isSimulated,
            generatedAt: metadata.generatedAt,
            timeStepSeconds: metadata.timeStepSeconds,
            observerHeightMeters: metadata.observerHeightMeters,
            minimumClearanceDeg: metadata.minimumClearanceDeg,
            sunCriterion: metadata.sunCriterion,
            earthCriterion: metadata.earthCriterion,
            referenceFrame: metadata.referenceFrame,
            ephemeris: metadata.ephemeris,
            spiceKernels: spice?.version,
            sources: metadata.provenance,
            assumptions: metadata.assumptions,
            validation: metadata.validation,
            limitations: metadata.limitations + MissionReport.standardLimitations,
            disclaimer: metadata.disclaimer
        )

        return MissionReport(
            createdAt: createdAt,
            missionName: store.missionName,
            plan: summary(committed, evaluation.overall),
            planContext: store.phase == .recoveryApplied ? "Updated plan" : "Committed plan",
            siteCoverage: store.visibility(for: committed.siteID).flatMap { EarthCommunicationWindowService.hull($0.coverage) },
            datasetCoverage: scenario.coverageHull,
            sunlight: section(evaluation.sunlight, data: store.visibility(for: committed.siteID), isSimulated: isSimulated),
            earth: section(evaluation.earth, data: store.visibility(for: committed.siteID), isSimulated: isSimulated),
            rescue: rescue,
            science: science
        )
    }

    static func section(_ assessment: ConditionAssessment, data: SiteVisibility?, isSimulated: Bool) -> MissionReport.ConditionSection {
        let window = assessment.window
        let visible = IntervalMath.complement(of: assessment.obstructedSegments + assessment.unknownSegments, within: window)
        return MissionReport.ConditionSection(
            condition: assessment.condition,
            status: assessment.status,
            statusText: ConditionCopy.badgeText(condition: assessment.condition, status: assessment.status),
            explanation: ConditionCopy.explanation(for: assessment, isSimulated: isSimulated),
            visible: visible,
            obstructed: assessment.obstructedSegments,
            unknown: assessment.unknownSegments,
            visibleDuration: assessment.visibleDuration,
            obstructedDuration: assessment.obstructedDuration,
            unknownDuration: assessment.unknownDuration,
            continuousFromStart: min(assessment.validFromStart, window.duration)
        )
    }

    // MARK: - Text content (shared by the PDF and the tests)

    /// Report numbers use a fixed locale, like the UTC times, so the PDF reads the same everywhere.
    static let numberLocale = Locale(identifier: "en_US_POSIX")

    static func degrees(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(0...2)).locale(numberLocale)))°" } ?? "Unknown"
    }

    static func meters(_ value: Double?) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)).locale(numberLocale))) m" } ?? "Unknown"
    }

    /// One row per interval, in time order (sorted by the instant, not by the formatted text).
    static func intervalRows(_ section: MissionReport.ConditionSection) -> [[String]] {
        let labelled = section.visible.map { ("Visible", $0) } + section.obstructed.map { ("Obstructed", $0) }
            + section.unknown.map { ("No data (Unknown)", $0) }
        return labelled
            .sorted { $0.1.start < $1.1.start }
            .map { [$0.0, UTCFormat.full($0.1.start), UTCFormat.full($0.1.end), UTCFormat.duration($0.1.duration)] }
    }

    // MARK: - PDF

    /// US Letter, 0.6" margins.
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 44

    @MainActor
    static func renderPDF(_ report: MissionReport) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format(for: report))
        return renderer.pdfData { context in
            var writer = PDFFlowWriter(context: context, pageSize: pageSize, margin: margin, footer: footer(for: report))
            write(report, to: &writer)
            writer.finish()
        }
    }

    @MainActor
    private static func format(for report: MissionReport) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "LUNAVI Mission Report — \(report.plan.siteName)",
            kCGPDFContextCreator as String: "LUNAVI",
        ]
        return format
    }

    private static func footer(for report: MissionReport) -> String {
        let mode = report.science.isSimulated ? "SIMULATED DEMO — illustrative values" : "Computed geometric visibility — not a NASA product"
        return "LUNAVI Mission Report · \(report.plan.siteName) · created \(UTCFormat.full(report.createdAt)) · \(mode)"
    }

    @MainActor
    static func write(_ report: MissionReport, to writer: inout PDFFlowWriter) {
        writer.title("LUNAVI Mission Report")
        writer.paragraph("\(report.missionName) · \(report.planContext) · created \(UTCFormat.full(report.createdAt))", style: .muted)
        if report.science.isSimulated {
            writer.paragraph("SIMULATED DEMO — every interval in this report is an illustrative fixture value, not lunar data.", style: .warning)
        }
        writer.paragraph(report.science.disclaimer, style: .muted)

        writer.heading("Mission information")
        writer.table(columns: [0.38, 0.62], header: nil, rows: [
            ["Lunar site", report.plan.siteName],
            ["Latitude, longitude", report.plan.coordinateText],
            ["UTC start", UTCFormat.full(report.plan.start)],
            ["UTC end", UTCFormat.full(report.plan.end)],
            ["Required operating duration", "\(report.plan.durationHours) h, uninterrupted"],
            ["Overall result", StatusStyle.title(for: report.plan.overall)],
            ["Data coverage at this site", report.siteCoverage.map { "\(UTCFormat.full($0.start)) – \(UTCFormat.full($0.end))" } ?? "No computed data (Unknown)"],
            ["Data coverage, all sites", report.datasetCoverage.map { "\(UTCFormat.full($0.start)) – \(UTCFormat.full($0.end))" } ?? "No computed data (Unknown)"],
        ])

        for section in [report.sunlight, report.earth] {
            writer.heading(section.condition == .sunlight ? "Sunlight analysis" : "Earth visibility (direct geometric line of sight)")
            writer.table(columns: [0.38, 0.62], header: nil, rows: [
                ["Requirement result", section.statusText],
                ["Visible", UTCFormat.duration(section.visibleDuration)],
                ["Obstructed", UTCFormat.duration(section.obstructedDuration)],
                ["No data (Unknown)", UTCFormat.duration(section.unknownDuration)],
                ["Uninterrupted from start", UTCFormat.duration(section.continuousFromStart)],
            ])
            writer.paragraph(section.explanation)
            writer.table(columns: [0.22, 0.31, 0.31, 0.16], header: ["State", "Start (UTC)", "End (UTC)", "Duration"],
                         rows: intervalRows(section))
        }

        writer.heading("Mission Rescue")
        let rescue = report.rescue
        if let delayed = rescue.delayedPlan {
            writer.table(columns: [0.38, 0.62], header: nil, rows: [
                ["Original plan", rescue.originalPlan.map { "\($0.siteName), \(UTCFormat.full($0.start)), \($0.durationHours) h — \(StatusStyle.shortTitle(for: $0.overall))" } ?? "Unknown"],
                ["Simulated delay", "+\(rescue.delayHours) h"],
                ["Delayed plan", "\(delayed.siteName), \(UTCFormat.full(delayed.start)), \(delayed.durationHours) h — \(StatusStyle.shortTitle(for: delayed.overall))"],
                ["First failure", rescue.delayedFailure ?? "None in the computed data"],
            ])
        } else {
            writer.paragraph("No delay has been simulated for this plan.", style: .muted)
        }
        if rescue.hasSearched {
            if rescue.candidates.isEmpty {
                writer.paragraph("Recovery search ran: no option meets both requirements for the whole window within the computed data.")
            }
            for c in rescue.candidates {
                writer.subheading("Option \(c.letter) — \(c.title)")
                writer.table(columns: [0.38, 0.62], header: nil, rows: [
                    ["Plan", "\(c.plan.siteName), \(UTCFormat.full(c.plan.start)) – \(UTCFormat.full(c.plan.end))"],
                    ["Result", StatusStyle.title(for: c.plan.overall)],
                    ["Why it qualifies", c.explanation],
                    ["Benefit", c.benefit],
                    ["Trade-off", c.tradeoff],
                    ["Data status", c.validation],
                ])
            }
        } else if rescue.delayedPlan != nil {
            writer.paragraph("Recovery options have not been searched.", style: .muted)
        }
        if let applied = rescue.applied {
            writer.paragraph("Applied alternative: option \(applied.letter), \(applied.plan.siteName) from \(UTCFormat.full(applied.plan.start)).", style: .emphasis)
        } else if rescue.acceptedDelayedPlan {
            writer.paragraph("The delayed plan was accepted (both requirements still hold).", style: .emphasis)
        } else {
            writer.paragraph("No alternative has been applied.", style: .muted)
        }

        let science = report.science
        writer.heading("Scientific information")
        writer.table(columns: [0.38, 0.62], header: nil, rows: [
            ["Dataset", science.datasetTitle],
            ["Data source", science.dataSource],
            ["Dataset generated", science.generatedAt.map(UTCFormat.full) ?? "Not stated"],
            ["Sampling", science.timeStepSeconds.map { "\(Int($0)) s; transitions refined by the pipeline" } ?? "Not stated"],
            ["Observer height", meters(science.observerHeightMeters)],
            ["Minimum clearance", degrees(science.minimumClearanceDeg)],
            ["Sunlight criterion", science.sunCriterion],
            ["Earth criterion", science.earthCriterion],
            ["Reference frame", science.referenceFrame],
            ["Ephemeris", science.ephemeris],
            ["SPICE kernels", science.spiceKernels ?? "Not available for this dataset"],
        ])
        writer.subheading("Data sources")
        writer.table(columns: [0.26, 0.4, 0.34], header: ["Role", "Source", "Provider / resolution"],
                     rows: science.sources.map { [$0.role, "\($0.name) (\($0.version))", "\($0.provider); \($0.resolution)"] })
        writer.subheading("Validation status")
        writer.table(columns: [0.3, 0.28, 0.42], header: ["Component", "Level", "Detail"],
                     rows: science.validation.map { [$0.component, $0.level.label, $0.detail] })
        writer.subheading("Calculation assumptions")
        writer.bullets(science.assumptions)
        writer.heading("Known limitations")
        writer.bullets(science.limitations)
    }
}

/// Minimal flowing-layout writer for UIGraphicsPDFRenderer: wraps text, paginates, and repeats
/// table headers on new pages. Content taller than a page is continued on the next page.
@MainActor
struct PDFFlowWriter {
    enum Style {
        case body
        case muted
        case warning
        case emphasis
    }

    let context: UIGraphicsPDFRendererContext
    let pageSize: CGSize
    let margin: CGFloat
    let footer: String
    private(set) var pageCount = 0
    private var y: CGFloat = 0

    init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat, footer: String) {
        self.context = context
        self.pageSize = pageSize
        self.margin = margin
        self.footer = footer
        beginPage()
    }

    private var contentWidth: CGFloat { pageSize.width - 2 * margin }
    private var bottom: CGFloat { pageSize.height - margin - 18 }

    private static let ink = UIColor(white: 0.08, alpha: 1)
    private static let mutedInk = UIColor(white: 0.38, alpha: 1)
    private static let warningInk = UIColor(red: 0.62, green: 0.26, blue: 0.21, alpha: 1)
    private static let rule = UIColor(white: 0.82, alpha: 1)

    private mutating func beginPage() {
        context.beginPage()
        pageCount += 1
        y = margin
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5), .foregroundColor: Self.mutedInk]
        let text = NSAttributedString(string: "\(footer) · page \(pageCount)", attributes: attributes)
        text.draw(with: CGRect(x: margin, y: pageSize.height - margin + 2, width: contentWidth, height: 20),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    mutating func finish() {}

    private func attributed(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// Draws a block, starting a new page first if it does not fit; a block taller than a whole page
    /// is drawn in page-sized slices.
    private mutating func block(_ text: NSAttributedString, x: CGFloat = 0, width: CGFloat? = nil, spacingAfter: CGFloat) {
        let w = width ?? contentWidth
        let h = height(of: text, width: w)
        let pageContent = bottom - margin
        if y + h > bottom && h <= pageContent {
            beginPage()
        }
        var drawn: CGFloat = 0
        while drawn < h {
            let available = bottom - y
            let cg = context.cgContext
            cg.saveGState()
            cg.clip(to: CGRect(x: margin + x, y: y, width: w, height: available))
            text.draw(with: CGRect(x: margin + x, y: y - drawn, width: w, height: h),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            cg.restoreGState()
            let step = min(available, h - drawn)
            drawn += step
            y += step
            if drawn < h { beginPage() }
        }
        y += spacingAfter
    }

    mutating func title(_ text: String) {
        block(attributed(text, font: .systemFont(ofSize: 22, weight: .semibold), color: Self.ink), spacingAfter: 4)
    }

    mutating func heading(_ text: String) {
        if y + 60 > bottom { beginPage() }
        y += 8
        block(attributed(text, font: .systemFont(ofSize: 14, weight: .semibold), color: Self.ink), spacingAfter: 2)
        let cg = context.cgContext
        cg.setStrokeColor(Self.rule.cgColor)
        cg.setLineWidth(0.6)
        cg.move(to: CGPoint(x: margin, y: y))
        cg.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        cg.strokePath()
        y += 6
    }

    mutating func subheading(_ text: String) {
        if y + 40 > bottom { beginPage() }
        y += 2
        block(attributed(text, font: .systemFont(ofSize: 11, weight: .semibold), color: Self.ink), spacingAfter: 3)
    }

    mutating func paragraph(_ text: String, style: Style = .body) {
        let font: UIFont = style == .emphasis ? .systemFont(ofSize: 9.5, weight: .semibold) : .systemFont(ofSize: 9.5)
        let color: UIColor
        switch style {
        case .body, .emphasis:
            color = Self.ink
        case .muted:
            color = Self.mutedInk
        case .warning:
            color = Self.warningInk
        }
        block(attributed(text, font: font, color: color), spacingAfter: 6)
    }

    mutating func bullets(_ items: [String]) {
        if items.isEmpty {
            paragraph("None stated.", style: .muted)
        }
        for item in items {
            block(attributed("•  \(item)", font: .systemFont(ofSize: 9.5), color: Self.ink), x: 6, width: contentWidth - 6, spacingAfter: 3)
        }
        y += 4
    }

    /// Table with wrapping cells. `columns` are width fractions. Header repeats after a page break.
    mutating func table(columns: [CGFloat], header: [String]?, rows: [[String]]) {
        let headerCells = header.map { cells($0, font: .systemFont(ofSize: 8.5, weight: .semibold)) }
        if rows.isEmpty {
            if let headerCells { drawRow(headerCells, columns: columns, shaded: true) }
            paragraph("None in this window.", style: .muted)
            return
        }
        if let headerCells, y + rowHeight(headerCells, columns: columns) + 20 > bottom { beginPage() }
        if let headerCells { drawRow(headerCells, columns: columns, shaded: true) }
        for values in rows {
            let rowCells = cells(values, font: .systemFont(ofSize: 8.5))
            if y + rowHeight(rowCells, columns: columns) > bottom {
                beginPage()
                if let headerCells { drawRow(headerCells, columns: columns, shaded: true) }
            }
            drawRow(rowCells, columns: columns, shaded: false)
        }
        y += 8
    }

    private static let cellPadding: CGFloat = 4

    private func cells(_ values: [String], font: UIFont) -> [NSAttributedString] {
        values.map { attributed($0, font: font, color: Self.ink) }
    }

    private func rowHeight(_ cells: [NSAttributedString], columns: [CGFloat]) -> CGFloat {
        let padding = Self.cellPadding
        let heights = zip(cells, columns).map { height(of: $0.0, width: contentWidth * $0.1 - 2 * padding) }
        return (heights.max() ?? 0) + 2 * padding
    }

    private mutating func drawRow(_ cells: [NSAttributedString], columns: [CGFloat], shaded: Bool) {
        let padding = Self.cellPadding
        let h = rowHeight(cells, columns: columns)
        let cg = context.cgContext
        if shaded {
            cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: h))
        }
        var x = margin
        for (cell, fraction) in zip(cells, columns) {
            let w = contentWidth * fraction
            cell.draw(with: CGRect(x: x + padding, y: y + padding, width: w - 2 * padding, height: h),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            x += w
        }
        cg.setStrokeColor(Self.rule.cgColor)
        cg.setLineWidth(0.4)
        cg.move(to: CGPoint(x: margin, y: y + h))
        cg.addLine(to: CGPoint(x: margin + contentWidth, y: y + h))
        cg.strokePath()
        y += h
    }
}
