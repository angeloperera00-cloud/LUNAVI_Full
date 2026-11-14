import SwiftUI

/// Interactive UTC visibility timeline. Scrubbing and tap-to-seek move a preview cursor only;
/// they never commit a plan. VoiceOver users step the cursor hour by hour or jump between events.
struct VisibilityTimelineView: View {
    @Environment(MissionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: TimelineZoom = .focus

    var body: some View {
        let model = TimelineModel.make(store: store, zoom: zoom)
        VStack(alignment: .leading, spacing: 0) {
            TimelineHeader(model: model, zoom: $zoom)
                .padding(.horizontal, LunaviSpacing.l)
                .padding(.top, 10)
                .padding(.bottom, 4)
            HStack(alignment: .top, spacing: 0) {
                TimelineTrackLabels()
                    .frame(width: 108)
                TimelinePlot(
                    model: model,
                    onSeek: { date in store.moveCursor(to: date) },
                    onStep: { hours in store.stepCursor(hours: hours) }
                )
            }
            .frame(height: TimelineMetrics.plotHeight)
            .padding(.trailing, LunaviSpacing.l)
            TimelineLegend(model: model)
                .padding(.horizontal, LunaviSpacing.l)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LunaviColors.background)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.range)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline")
    }
}

struct TimelineHeader: View {
    let model: TimelineModel
    @Binding var zoom: TimelineZoom
    @Environment(MissionStore.self) private var store

    var body: some View {
        HStack(spacing: LunaviSpacing.m) {
            Label("Visibility Timeline (UTC)", systemImage: "calendar")
                .font(LunaviTypography.bodyEmphasis)
                .foregroundStyle(LunaviColors.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: LunaviSpacing.s)
            cursorReadout
            eventButtons
            Picker("Timeline range", selection: $zoom) {
                ForEach(TimelineZoom.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .accessibilityIdentifier("timeline.zoom")
        }
    }

    @ViewBuilder
    private var cursorReadout: some View {
        if let cursor = model.cursor {
            HStack(spacing: LunaviSpacing.s) {
                Text("\(UTCFormat.dayMonthTime(cursor)) UTC")
                    .font(LunaviTypography.measurementSmall)
                    .foregroundStyle(LunaviColors.selectedTime)
                stateChip(.sunlight, model.cursorSun)
                stateChip(.earthLineOfSight, model.cursorEarth)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timeline.cursorReadout")
        }
    }

    private func stateChip(_ condition: VisibilityCondition, _ state: PointState) -> some View {
        let color: Color
        switch state {
        case .visible:
            color = condition == .sunlight ? LunaviColors.sunTrack : LunaviColors.earthTrack
        case .obstructed:
            color = LunaviColors.failure
        case .unknown:
            color = LunaviColors.textMuted
        }
        return HStack(spacing: 3) {
            Image(systemName: condition.symbolName)
            Text(state.label)
        }
        .font(LunaviTypography.micro)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.title) \(state.label)")
    }

    private var eventButtons: some View {
        HStack(spacing: 2) {
            iconButton("chevron.left", label: "Previous event", identifier: "timeline.previousEvent") {
                store.jumpToEvent(forward: false)
            }
            iconButton("flag", label: "Jump to first failure", identifier: "timeline.firstFailure") {
                store.jumpToFirstFailure()
            }
            .disabled(model.firstFailureTime == nil)
            iconButton("chevron.right", label: "Next event", identifier: "timeline.nextEvent") {
                store.jumpToEvent(forward: true)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LunaviColors.textSecondary)
        .overlay(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall).stroke(LunaviColors.border, lineWidth: 1))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct TimelineTrackLabels: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Label("Sunlight", systemImage: VisibilityCondition.sunlight.symbolName)
                .foregroundStyle(LunaviColors.sunTrack)
                .offset(y: TimelineMetrics.sunTop + 2)
            Label("Earth LOS", systemImage: VisibilityCondition.earthLineOfSight.symbolName)
                .foregroundStyle(LunaviColors.earthTrack)
                .offset(y: TimelineMetrics.earthTop + 2)
        }
        .font(LunaviTypography.captionEmphasis)
        .lineLimit(1)
        .padding(.leading, LunaviSpacing.l)
        .accessibilityHidden(true)
    }
}

struct TimelinePlot: View {
    let model: TimelineModel
    let onSeek: (Date) -> Void
    let onStep: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = TimelineLayout(width: proxy.size.width, range: model.range)
            Canvas { context, _ in
                TimelineRenderer.draw(model, layout: layout, context: &context)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(layout.date(atX: value.location.x))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Timeline cursor")
        .accessibilityValue(model.cursorAccessibilityValue)
        .accessibilityHint("Swipe up or down to move the cursor by one hour. Use the event buttons to jump.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onStep(1)
            case .decrement:
                onStep(-1)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("timeline.plot")
    }
}

struct TimelineLegend: View {
    let model: TimelineModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                swatch(LunaviColors.sunTrack, "Sunlight")
                swatch(LunaviColors.earthTrack, "Earth line of sight")
                swatch(LunaviColors.obstructionTrack, "Obstructed")
                hatchSwatch
                outline(LunaviColors.textSecondary, dashed: false, "Original")
                outline(LunaviColors.failure, dashed: true, "Delayed")
                outline(LunaviColors.success, dashed: true, "Recovery")
                Text("Tracks: \(model.trackSiteName)\(model.isPreviewTrack ? " (preview)" : "")")
                    .foregroundStyle(LunaviColors.textMuted)
            }
            .font(LunaviTypography.micro)
            .foregroundStyle(LunaviColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: amber sunlight, blue-grey Earth line of sight, clay obstructed, hatched no data. Tracks show \(model.trackSiteName).")
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 16, height: 8)
            Text(text)
        }
    }

    private func outline(_ color: Color, dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .frame(width: 16, height: 8)
            Text(text)
        }
    }

    private var hatchSwatch: some View {
        HStack(spacing: 5) {
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 4
                }
                context.stroke(path, with: .color(LunaviColors.textMuted), lineWidth: 1)
            }
            .frame(width: 16, height: 8)
            .overlay(Rectangle().stroke(LunaviColors.textMuted.opacity(0.5), lineWidth: 0.5))
            Text("No data")
        }
    }
}

#Preview("Interactive timeline — delayed plan", traits: .fixedLayout(width: 1036, height: 200)) {
    PreviewHost(phase: .delayed) {
        VisibilityTimelineView()
    }
}
