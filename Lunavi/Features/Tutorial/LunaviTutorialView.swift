import SwiftUI

/// Interactive beginner tutorial: twelve steps from "what is LUNAVI" to Mission Rescue.
///
/// Opening, paging through and closing the tutorial never changes the active mission. Completion
/// (Finish or Skip) is stored locally, and the tutorial can be reopened from Help at any time.
struct LunaviTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tutorial = TutorialState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                TutorialStepContent(step: tutorial.current)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(LunaviSpacing.xl)
                    .frame(maxWidth: .infinity)
                    .id(tutorial.current.id)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            Hairline()
            controls
        }
        .background(LunaviColors.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tutorial.index)
        .accessibilityIdentifier("tutorial")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.s) {
            HStack {
                Label("LUNAVI Tutorial", systemImage: "graduationcap")
                    .font(LunaviTypography.headline)
                    .foregroundStyle(LunaviColors.textPrimary)
                Spacer()
                Text(tutorial.positionLabel)
                    .font(LunaviTypography.measurementSmall)
                    .foregroundStyle(LunaviColors.textMuted)
                    .accessibilityIdentifier("tutorial.position")
                Button("Skip") {
                    tutorial.skip()
                    dismiss()
                }
                .buttonStyle(LunaviToolbarButtonStyle())
                .accessibilityHint("Closes the tutorial. You can reopen it from Help.")
                .accessibilityIdentifier("tutorial.skip")
            }
            ProgressView(value: tutorial.fraction)
                .tint(LunaviColors.selectedTime)
                .accessibilityLabel("Tutorial progress")
                .accessibilityValue(tutorial.positionLabel)
            HStack(spacing: 6) {
                ForEach(tutorial.steps) { step in
                    Button {
                        tutorial.go(to: step.id)
                    } label: {
                        Circle()
                            .fill(step.id == tutorial.index ? LunaviColors.selectedTime : step.id < tutorial.index ? LunaviColors.textSecondary : LunaviColors.border)
                            .frame(width: 8, height: 8)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(step.id + 1): \(step.title)")
                    .accessibilityAddTraits(step.id == tutorial.index ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, LunaviSpacing.xl)
        .padding(.vertical, LunaviSpacing.m)
        .background(LunaviColors.navigationBar)
    }

    private var controls: some View {
        HStack(spacing: LunaviSpacing.m) {
            Button {
                tutorial.back()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(LunaviSecondaryButtonStyle(compact: true))
            .disabled(tutorial.isFirst)
            .accessibilityIdentifier("tutorial.back")
            Spacer()
            if tutorial.isLast {
                Button {
                    tutorial.finish()
                    dismiss()
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .frame(minWidth: 160)
                }
                .buttonStyle(LunaviPrimaryButtonStyle())
                .frame(maxWidth: 260)
                .accessibilityIdentifier("tutorial.finish")
            } else {
                Button {
                    tutorial.next()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(minWidth: 160)
                }
                .buttonStyle(LunaviPrimaryButtonStyle())
                .frame(maxWidth: 260)
                .accessibilityIdentifier("tutorial.next")
            }
        }
        .padding(.horizontal, LunaviSpacing.xl)
        .padding(.vertical, LunaviSpacing.m)
        .background(LunaviColors.navigationBar)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

struct TutorialStepContent: View {
    let step: TutorialStep

    var body: some View {
        VStack(alignment: .leading, spacing: LunaviSpacing.l) {
            HStack(spacing: LunaviSpacing.m) {
                Image(systemName: step.symbol)
                    .font(.title2)
                    .foregroundStyle(LunaviColors.selectedTime)
                    .frame(width: 44, height: 44)
                    .background(LunaviColors.surfaceElevated, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerMedium))
                    .accessibilityHidden(true)
                Text(step.title)
                    .font(LunaviTypography.screenTitle)
                    .foregroundStyle(LunaviColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("tutorial.title")
            }
            Text(step.body)
                .font(.body)
                .foregroundStyle(LunaviColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if step.diagram != .none {
                PanelCard(fill: LunaviColors.terrainCanvas) {
                    VStack(alignment: .leading, spacing: 6) {
                        TutorialDiagramView(diagram: step.diagram)
                            .frame(height: 200)
                        Text("Diagram — conceptual, not to scale, no data values.")
                            .font(LunaviTypography.micro)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(diagramDescription)
            }
            if !step.terms.isEmpty {
                VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                    Text("Key terms").lunaviSectionLabel()
                    ForEach(step.terms, id: \.term) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.term)
                                .font(LunaviTypography.bodyEmphasis)
                                .foregroundStyle(LunaviColors.textPrimary)
                            Text(item.definition)
                                .font(LunaviTypography.body)
                                .foregroundStyle(LunaviColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !step.references.isEmpty {
                VStack(alignment: .leading, spacing: LunaviSpacing.s) {
                    Text("Where to find it").lunaviSectionLabel()
                    ForEach(step.references, id: \.self) { reference in
                        Label {
                            Text("\(reference.name) — \(reference.location)")
                        } icon: {
                            Image(systemName: "hand.point.right")
                        }
                        .font(LunaviTypography.body)
                        .foregroundStyle(LunaviColors.textSecondary)
                    }
                }
            }
        }
    }

    private var diagramDescription: String {
        switch step.diagram {
        case .none:
            return ""
        case .siteMap:
            return "Diagram: a polar map with several site pins."
        case .azimuthElevation:
            return "Diagram: azimuth is measured clockwise from north along the horizon; elevation is the angle above the horizon."
        case .terrainBlocking:
            return "Diagram: a ridge rises above the flat horizon. A Sun above the ridge is visible; a Sun below the ridge is blocked."
        case .earthLineOfSight:
            return "Diagram: Earth's disc partly above a ridge counts as line of sight."
        case .timeline:
            return "Diagram: two tracks with visible, obstructed and no-data stretches, and a cursor line."
        case .delay:
            return "Diagram: an original window and a later delayed window that runs into an obstruction."
        case .rescue:
            return "Diagram: option A starts later at the same site; option B uses another site at the delayed time."
        }
    }
}

/// Conceptual drawings in the app's palette. No values, no scale.
struct TutorialDiagramView: View {
    let diagram: TutorialDiagram

    var body: some View {
        Canvas { context, size in
            switch diagram {
            case .none:
                break
            case .siteMap:
                drawSiteMap(&context, size)
            case .azimuthElevation:
                drawAzimuthElevation(&context, size)
            case .terrainBlocking:
                drawTerrain(&context, size, target: LunaviColors.sunTrack, earth: false)
            case .earthLineOfSight:
                drawTerrain(&context, size, target: LunaviColors.earthTrack, earth: true)
            case .timeline:
                drawTimeline(&context, size)
            case .delay:
                drawWindows(&context, size, rescue: false)
            case .rescue:
                drawWindows(&context, size, rescue: true)
            }
        }
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at point: CGPoint, color: Color = LunaviColors.textSecondary) {
        context.draw(Text(text).font(LunaviTypography.caption).foregroundStyle(color), at: point)
    }

    private func drawSiteMap(_ context: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.45
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(LunaviColors.terrainFill))
        for (dx, dy, r) in [(-0.3, -0.2, 0.22), (0.25, 0.15, 0.3), (0.05, -0.45, 0.14)] {
            let c = CGPoint(x: center.x + radius * dx, y: center.y + radius * dy)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - radius * r, y: c.y - radius * r, width: 2 * radius * r, height: 2 * radius * r)),
                           with: .color(LunaviColors.terrainEdge.opacity(0.5)), lineWidth: 1)
        }
        for (i, (dx, dy)) in [(-0.15, 0.05), (0.32, -0.1), (0.0, 0.35)].enumerated() {
            let p = CGPoint(x: center.x + radius * dx, y: center.y + radius * dy)
            let color = i == 0 ? LunaviColors.selectedTime : LunaviColors.unselectedSite
            context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color))
        }
        label(&context, "Selected site", at: CGPoint(x: center.x - radius * 0.15, y: center.y + radius * 0.05 - 18), color: LunaviColors.selectedTime)
    }

    private func drawAzimuthElevation(_ context: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.68)
        let rx = size.width * 0.32, ry = size.height * 0.18
        let horizon = Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry))
        context.stroke(horizon, with: .color(LunaviColors.border), lineWidth: 1.5)
        label(&context, "N", at: CGPoint(x: center.x, y: center.y - ry - 10))
        // Sun up and to the right; azimuth arc from north.
        let foot = CGPoint(x: center.x + rx * 0.8, y: center.y - ry * 0.6)
        let sun = CGPoint(x: foot.x, y: foot.y - size.height * 0.32)
        var azimuth = Path()
        azimuth.addArc(center: center, radius: ry * 0.9, startAngle: .degrees(-90), endAngle: .degrees(-25), clockwise: false)
        context.stroke(azimuth, with: .color(LunaviColors.selectedTime), lineWidth: 2)
        label(&context, "Azimuth", at: CGPoint(x: center.x + rx * 0.25, y: center.y - ry - 4), color: LunaviColors.selectedTime)
        var ray = Path()
        ray.move(to: center)
        ray.addLine(to: foot)
        context.stroke(ray, with: .color(LunaviColors.detailMuted), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        var line = Path()
        line.move(to: center)
        line.addLine(to: sun)
        context.stroke(line, with: .color(LunaviColors.sunTrack), lineWidth: 1.5)
        context.fill(Path(ellipseIn: CGRect(x: sun.x - 9, y: sun.y - 9, width: 18, height: 18)), with: .color(LunaviColors.sunTrack))
        label(&context, "Elevation", at: CGPoint(x: foot.x - 50, y: (foot.y + sun.y) / 2), color: LunaviColors.sunTrack)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(LunaviColors.textPrimary))
        label(&context, "Site", at: CGPoint(x: center.x, y: center.y + 14))
    }

    private func drawTerrain(_ context: inout GraphicsContext, _ size: CGSize, target: Color, earth: Bool) {
        let ground = size.height * 0.78
        let observer = CGPoint(x: size.width * 0.12, y: ground)
        var flat = Path()
        flat.move(to: CGPoint(x: 0, y: ground))
        flat.addLine(to: CGPoint(x: size.width, y: ground))
        context.stroke(flat, with: .color(LunaviColors.detailMuted), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        label(&context, "Flat horizon", at: CGPoint(x: size.width * 0.88, y: ground + 12), color: LunaviColors.textMuted)
        var ridge = Path()
        ridge.move(to: CGPoint(x: size.width * 0.45, y: ground))
        ridge.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.42))
        ridge.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.5))
        ridge.addLine(to: CGPoint(x: size.width * 0.85, y: ground))
        ridge.closeSubpath()
        context.fill(ridge, with: .color(LunaviColors.terrainFill))
        context.stroke(ridge, with: .color(LunaviColors.terrainEdge.opacity(0.6)), lineWidth: 1)
        let peak = CGPoint(x: size.width * 0.62, y: size.height * 0.42)
        var horizonRay = Path()
        horizonRay.move(to: observer)
        horizonRay.addLine(to: CGPoint(x: size.width * 0.98, y: observer.y + (peak.y - observer.y) * (size.width * 0.86) / (peak.x - observer.x)))
        context.stroke(horizonRay, with: .color(LunaviColors.terrainEdge), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        label(&context, "Terrain horizon", at: CGPoint(x: size.width * 0.36, y: size.height * 0.5), color: LunaviColors.terrainEdge)
        context.fill(Path(ellipseIn: CGRect(x: observer.x - 5, y: observer.y - 10, width: 10, height: 10)), with: .color(LunaviColors.textPrimary))
        if earth {
            let center = CGPoint(x: size.width * 0.9, y: size.height * 0.3)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)), with: .color(target))
            label(&context, "Earth: any part of the disc above the terrain counts", at: CGPoint(x: size.width * 0.5, y: size.height * 0.1), color: target)
        } else {
            let high = CGPoint(x: size.width * 0.9, y: size.height * 0.12)
            let low = CGPoint(x: size.width * 0.93, y: size.height * 0.6)
            context.fill(Path(ellipseIn: CGRect(x: high.x - 11, y: high.y - 11, width: 22, height: 22)), with: .color(target))
            context.fill(Path(ellipseIn: CGRect(x: low.x - 11, y: low.y - 11, width: 22, height: 22)), with: .color(target.opacity(0.35)))
            label(&context, "Above terrain: sunlit", at: CGPoint(x: high.x - 90, y: high.y), color: target)
            label(&context, "Behind terrain: shadow", at: CGPoint(x: low.x - 70, y: low.y - 22), color: LunaviColors.failure)
        }
    }

    private func bar(_ context: inout GraphicsContext, y: CGFloat, width: CGFloat, pieces: [(CGFloat, CGFloat, Color)]) {
        for (start, end, color) in pieces {
            let rect = CGRect(x: width * start, y: y, width: width * (end - start), height: 14)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
        }
    }

    private func drawTimeline(_ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width
        label(&context, "Sun", at: CGPoint(x: 24, y: size.height * 0.3 + 7))
        bar(&context, y: size.height * 0.3, width: w, pieces: [(0.08, 0.55, LunaviColors.sunTrack), (0.55, 0.7, LunaviColors.obstructionTrack), (0.7, 0.85, LunaviColors.sunTrack), (0.85, 1, LunaviColors.unknown.opacity(0.4))])
        label(&context, "Earth", at: CGPoint(x: 24, y: size.height * 0.55 + 7))
        bar(&context, y: size.height * 0.55, width: w, pieces: [(0.08, 0.3, LunaviColors.obstructionTrack), (0.3, 0.85, LunaviColors.earthTrack), (0.85, 1, LunaviColors.unknown.opacity(0.4))])
        var cursor = Path()
        cursor.move(to: CGPoint(x: w * 0.45, y: size.height * 0.18))
        cursor.addLine(to: CGPoint(x: w * 0.45, y: size.height * 0.8))
        context.stroke(cursor, with: .color(LunaviColors.selectedTime), lineWidth: 2)
        label(&context, "Cursor", at: CGPoint(x: w * 0.45, y: size.height * 0.1), color: LunaviColors.selectedTime)
        label(&context, "visible · obstructed · no data", at: CGPoint(x: w * 0.5, y: size.height * 0.92), color: LunaviColors.textMuted)
    }

    private func drawWindows(_ context: inout GraphicsContext, _ size: CGSize, rescue: Bool) {
        let w = size.width
        bar(&context, y: size.height * 0.15, width: w, pieces: [(0.1, 0.62, LunaviColors.sunTrack), (0.62, 0.78, LunaviColors.obstructionTrack), (0.78, 1, LunaviColors.sunTrack)])
        label(&context, "Sunlight at the plan site", at: CGPoint(x: w * 0.25, y: size.height * 0.08), color: LunaviColors.textMuted)
        func window(_ y: CGFloat, _ start: CGFloat, _ end: CGFloat, _ color: Color, _ text: String) {
            let rect = CGRect(x: w * start, y: y, width: w * (end - start), height: 18)
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(color), lineWidth: 2)
            context.draw(Text(text).font(LunaviTypography.caption).foregroundStyle(color), at: CGPoint(x: rect.midX, y: rect.midY))
        }
        window(size.height * 0.36, 0.12, 0.5, LunaviColors.textPrimary, "Original")
        window(size.height * 0.52, 0.3, 0.68, LunaviColors.failure, "Delayed — runs into shadow")
        if rescue {
            window(size.height * 0.68, 0.78, 0.99, LunaviColors.success, "A: same site, later")
            window(size.height * 0.84, 0.3, 0.68, LunaviColors.success, "B: other site, same time")
        }
    }
}

#Preview("Tutorial", traits: .landscapeLeft) {
    LunaviTutorialView()
        .preferredColorScheme(.dark)
}
