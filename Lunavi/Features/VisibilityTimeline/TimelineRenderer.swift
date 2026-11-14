import SwiftUI

/// Draws the timeline in a Canvas: UTC grid, Sun and Earth tracks (visible / obstructed / no data),
/// operating windows, failure markers and the cursor.
enum TimelineRenderer {
    static func draw(_ model: TimelineModel, layout: TimelineLayout, context: inout GraphicsContext) {
        drawGrid(model, layout, &context)
        drawTrack(model.sunSegments, color: LunaviColors.sunTrack, top: TimelineMetrics.sunTop, layout, &context)
        drawTrack(model.earthSegments, color: LunaviColors.earthTrack, top: TimelineMetrics.earthTop, layout, &context)
        drawWindows(model.windows, layout, &context)
        drawFailures(model.failures, layout, &context)
        drawCursor(model.cursor, layout, &context)
    }

    // MARK: Grid

    private static func drawGrid(_ model: TimelineModel, _ layout: TimelineLayout, _ context: inout GraphicsContext) {
        let hours = model.range.duration / 3600
        let pointsPerHour = Double(layout.plotWidth) / max(hours, 1)
        let steps: [Double] = [1, 2, 3, 6, 12, 24, 48]
        let step = steps.first(where: { $0 * pointsPerHour >= 54 }) ?? 48
        let stepSeconds = step * 3600

        var tick = UTCFormat.startOfDay(model.range.start)
        while tick < model.range.start {
            tick = tick.addingTimeInterval(stepSeconds)
        }

        var drewDayLabel = false
        while tick <= model.range.end {
            let x = layout.x(tick)
            let midnight = UTCFormat.isMidnight(tick)
            var line = Path()
            line.move(to: CGPoint(x: x, y: TimelineMetrics.windowTop - 4))
            line.addLine(to: CGPoint(x: x, y: TimelineMetrics.windowBottom))
            context.stroke(line, with: .color(LunaviColors.border.opacity(midnight ? 0.95 : 0.5)), lineWidth: midnight ? 1 : 0.5)

            let label = step >= 24 ? UTCFormat.dayMonth(tick) : UTCFormat.time(tick)
            context.draw(
                Text(label).font(.caption2).monospacedDigit().foregroundStyle(LunaviColors.textMuted),
                at: CGPoint(x: x, y: TimelineMetrics.hourLabelY),
                anchor: .top
            )
            if midnight && step < 24 {
                context.draw(
                    Text(UTCFormat.dayMonth(tick)).font(.caption2.weight(.semibold)).foregroundStyle(LunaviColors.textSecondary),
                    at: CGPoint(x: x, y: TimelineMetrics.dayLabelY),
                    anchor: .top
                )
                drewDayLabel = true
            }
            tick = tick.addingTimeInterval(stepSeconds)
        }

        if !drewDayLabel && step < 24 {
            context.draw(
                Text(UTCFormat.dayMonth(model.range.start)).font(.caption2.weight(.semibold)).foregroundStyle(LunaviColors.textSecondary),
                at: CGPoint(x: TimelineMetrics.horizontalInset, y: TimelineMetrics.dayLabelY),
                anchor: .topLeading
            )
        }
    }

    // MARK: Tracks

    private static func drawTrack(_ segments: [TimelineSegment], color: Color, top: CGFloat, _ layout: TimelineLayout, _ context: inout GraphicsContext) {
        let height = TimelineMetrics.trackHeight
        let base = CGRect(x: TimelineMetrics.horizontalInset, y: top, width: layout.plotWidth, height: height)
        context.fill(Path(roundedRect: base, cornerRadius: 3), with: .color(LunaviColors.surfaceElevated))
        for segment in segments {
            let x0 = layout.x(segment.range.start)
            let x1 = layout.x(segment.range.end)
            let rect = CGRect(x: x0, y: top, width: max(1, x1 - x0), height: height)
            switch segment.kind {
            case .visible:
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            case .obstructed:
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(LunaviColors.obstructionTrack))
            case .unknown:
                drawHatch(in: rect, &context)
            }
        }
    }

    private static func drawHatch(in rect: CGRect, _ context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            var path = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 6
            }
            layer.stroke(path, with: .color(LunaviColors.textMuted.opacity(0.6)), lineWidth: 1)
        }
        context.stroke(Path(rect), with: .color(LunaviColors.textMuted.opacity(0.35)), lineWidth: 0.5)
    }

    // MARK: Windows

    private static func color(for style: TimelineWindowMark.Style) -> Color {
        switch style {
        case .committed:
            return LunaviColors.selectedTime
        case .original:
            return LunaviColors.textSecondary
        case .delayedFailing:
            return LunaviColors.failure
        case .delayedOK:
            return LunaviColors.selectedTime
        case .preview, .applied:
            return LunaviColors.success
        }
    }

    private static func dash(for style: TimelineWindowMark.Style) -> [CGFloat] {
        switch style {
        case .delayedFailing, .delayedOK, .preview:
            return [5, 4]
        case .committed, .original, .applied:
            return []
        }
    }

    private static func drawWindows(_ windows: [TimelineWindowMark], _ layout: TimelineLayout, _ context: inout GraphicsContext) {
        for window in windows {
            let x0 = layout.x(window.range.start)
            let x1 = layout.x(window.range.end)
            let rect = CGRect(
                x: x0,
                y: TimelineMetrics.windowTop,
                width: max(2, x1 - x0),
                height: TimelineMetrics.windowBottom - TimelineMetrics.windowTop
            )
            let tint = Self.color(for: window.style)
            let shape = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(shape, with: .color(tint.opacity(0.07)))
            context.stroke(shape, with: .color(tint), style: StrokeStyle(lineWidth: window.style == .applied ? 2 : 1.5, dash: Self.dash(for: window.style)))

            let minX = TimelineMetrics.horizontalInset
            let maxX = layout.width - TimelineMetrics.horizontalInset
            let anchor: UnitPoint
            let x: CGFloat
            switch window.labelAlignment {
            case .leading:
                anchor = .topLeading
                x = min(max(rect.minX, minX), maxX)
            case .trailing:
                anchor = .topTrailing
                x = min(max(rect.maxX, minX), maxX)
            case .center:
                anchor = .top
                x = min(max(rect.midX, minX), maxX)
            }
            context.draw(
                Text(window.label).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(tint),
                at: CGPoint(x: x, y: TimelineMetrics.windowLabelY),
                anchor: anchor
            )
        }
    }

    // MARK: Markers

    private static func drawFailures(_ failures: [TimelineFailureMark], _ layout: TimelineLayout, _ context: inout GraphicsContext) {
        for failure in failures {
            let x = layout.x(failure.time)
            let top = failure.condition == .sunlight ? TimelineMetrics.sunTop : TimelineMetrics.earthTop
            var line = Path()
            line.move(to: CGPoint(x: x, y: top - 3))
            line.addLine(to: CGPoint(x: x, y: top + TimelineMetrics.trackHeight + 3))
            context.stroke(line, with: .color(LunaviColors.failure), lineWidth: 2)
            var marker = Path()
            marker.move(to: CGPoint(x: x - 5, y: top - 9))
            marker.addLine(to: CGPoint(x: x + 5, y: top - 9))
            marker.addLine(to: CGPoint(x: x, y: top - 3))
            marker.closeSubpath()
            context.fill(marker, with: .color(LunaviColors.failure))
        }
    }

    private static func drawCursor(_ cursor: Date?, _ layout: TimelineLayout, _ context: inout GraphicsContext) {
        guard let cursor, cursor >= layout.range.start, cursor <= layout.range.end else { return }
        let x = layout.x(cursor)
        var line = Path()
        line.move(to: CGPoint(x: x, y: TimelineMetrics.windowTop - 2))
        line.addLine(to: CGPoint(x: x, y: TimelineMetrics.windowBottom + 2))
        context.stroke(line, with: .color(LunaviColors.selectedTime), lineWidth: 1.5)
        let handle = CGRect(x: x - 5, y: TimelineMetrics.windowTop - 8, width: 10, height: 10)
        context.fill(Path(ellipseIn: handle), with: .color(LunaviColors.selectedTime))
        context.stroke(Path(ellipseIn: handle), with: .color(LunaviColors.background), lineWidth: 1.5)
    }
}
