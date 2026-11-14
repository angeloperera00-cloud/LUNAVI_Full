import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Preview, share and save the PDF mission report built from the current mission state.
struct MissionReportView: View {
    enum Phase {
        case generating
        case ready(report: MissionReport, data: Data, url: URL)
        case failed(String)
    }

    @Environment(MissionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .generating
    @State private var isExporting = false
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            content
                .background(LunaviColors.backgroundSecondary)
                .navigationTitle("Mission Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("report.done")
                    }
                    if case .ready(let report, _, let url) = phase {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                isExporting = true
                            } label: {
                                Label("Save PDF", systemImage: "square.and.arrow.down")
                            }
                            .accessibilityIdentifier("report.save")
                            ShareLink(item: url, preview: SharePreview(report.fileName)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier("report.share")
                        }
                    }
                }
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: .pdf,
                      defaultFilename: exportFileName) { result in
            switch result {
            case .success(let saved):
                exportMessage = "Saved \(saved.lastPathComponent)."
            case .failure(let error):
                exportMessage = "Could not save: \(error.localizedDescription)"
            }
        }
        .presentationBackground(LunaviColors.backgroundSecondary)
        .task { generate() }
    }

    private var exportDocument: PDFFileDocument? {
        if case .ready(_, let data, _) = phase { return PDFFileDocument(data: data) }
        return nil
    }

    private var exportFileName: String? {
        if case .ready(let report, _, _) = phase { return report.fileName }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .generating:
            ProgressView("Building report from the mission data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Report unavailable", systemImage: "doc.badge.ellipsis", description: Text(message))
        case .ready(let report, let data, _):
            VStack(spacing: 0) {
                HStack(spacing: LunaviSpacing.m) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(LunaviColors.selectedTime)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.fileName)
                            .font(LunaviTypography.bodyEmphasis)
                            .foregroundStyle(LunaviColors.textPrimary)
                        Text("\(report.planContext) · \(report.plan.siteName) · \(UTCFormat.full(report.plan.start)) · \(PDFDocument(data: data)?.pageCount ?? 0) pages")
                            .font(LunaviTypography.caption)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                    Spacer()
                    if let exportMessage {
                        Text(exportMessage)
                            .font(LunaviTypography.caption)
                            .foregroundStyle(LunaviColors.textSecondary)
                    }
                }
                .padding(LunaviSpacing.m)
                Hairline()
                PDFPreview(data: data)
                    .accessibilityLabel("Report preview")
                    .accessibilityIdentifier("report.preview")
            }
        }
    }

    private func generate() {
        guard let report = MissionReportGenerator.makeReport(store: store) else {
            phase = .failed("No mission plan is loaded, so there is nothing to report.")
            return
        }
        let data = MissionReportGenerator.renderPDF(report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(report.fileName)
        do {
            try data.write(to: url, options: .atomic)
            phase = .ready(report: report, data: data, url: url)
        } catch {
            phase = .failed("Could not write the PDF: \(error.localizedDescription)")
        }
    }
}

/// PDFKit preview of in-memory PDF data.
struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = UIColor(lunaviHex: 0x111317)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

/// Wraps PDF data for `fileExporter`.
struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview("Mission Report — simulated", traits: .landscapeLeft) {
    PreviewHost(phase: .applied) {
        MissionReportView()
    }
}
