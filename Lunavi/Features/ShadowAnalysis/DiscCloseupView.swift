import SwiftUI

/// A to-scale close-up looking toward the target: the target disc at its computed elevation and
/// angular radius, and the modeled terrain horizon across the azimuths around it, drawn on top.
/// What remains visible is what the requirement counts. One degree is the same length on both axes.
struct DiscCloseupView: View {
    let geometry: ShadowGeometry
    let reading: ShadowReading
    let color: Color

    var body: some View {
        if let direction = reading.direction {
            Canvas { context, size in
                draw(in: &context, size: size, direction: direction)
            }
            .frame(height: 180)
            .background(LunaviColors.terrainCanvas, in: RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .clipShape(RoundedRectangle(cornerRadius: LunaviSpacing.cornerSmall))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Close-up of the \(reading.condition == .sunlight ? "Sun" : "Earth") against the terrain horizon")
            .accessibilityValue(ShadowAnalysisService.explanation(for: reading))
            .accessibilityIdentifier("shadow.closeup")
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, direction: TargetDirection) {
        // Degrees shown across the width: the disc plus several radii of terrain on each side.
        let halfWidthDeg = max(1.5, direction.angularRadiusDeg * 5)
        let scale = size.width / (2 * halfWidthDeg)            // points per degree, both axes
        let centerX = size.width / 2
        let centerY = size.height / 2
        func y(_ elevation: Double) -> CGFloat { centerY - CGFloat(elevation - direction.elevationDeg) * scale }
        func x(_ azimuthOffset: Double) -> CGFloat { centerX + CGFloat(azimuthOffset) * scale }

        // Ideal (flat-Moon) horizon.
        let idealY = y(0)
        if idealY > 0, idealY < size.height {
            var ideal = Path()
            ideal.move(to: CGPoint(x: 0, y: idealY))
            ideal.addLine(to: CGPoint(x: size.width, y: idealY))
            context.stroke(ideal, with: .color(LunaviColors.textMuted), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            context.draw(Text("Ideal horizon 0°").font(LunaviTypography.micro).foregroundStyle(LunaviColors.textMuted),
                         at: CGPoint(x: 8, y: idealY - 8), anchor: .leading)
        }

        // Target disc (drawn first; terrain covers the hidden part).
        let radius = CGFloat(direction.angularRadiusDeg) * scale
        let disc = Path(ellipseIn: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(color))

        // Terrain silhouette, sampled every 2 pt; gaps where the horizon is unknown.
        var runs: [[CGPoint]] = [[]]
        var gaps: [ClosedRange<CGFloat>] = []
        var gapStart: CGFloat?
        var px: CGFloat = 0
        while px <= size.width {
            let azimuth = direction.azimuthDeg + Double((px - centerX) / scale)
            if let horizon = ShadowAnalysisService.horizonElevation(geometry, at: azimuth) {
                if let start = gapStart {
                    gaps.append(start...px)
                    gapStart = nil
                }
                runs[runs.count - 1].append(CGPoint(x: px, y: y(horizon)))
            } else {
                if gapStart == nil { gapStart = px }
                if !(runs.last?.isEmpty ?? true) { runs.append([]) }
            }
            px += 2
        }
        if let start = gapStart { gaps.append(start...size.width) }

        let obstructed = (reading.clearanceDeg ?? 0) < 0 || reading.disc == .obstructed
        for run in runs where run.count > 1 {
            var terrain = Path()
            terrain.move(to: CGPoint(x: run[0].x, y: size.height))
            for point in run { terrain.addLine(to: point) }
            terrain.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
            terrain.closeSubpath()
            context.fill(terrain, with: .color(LunaviColors.terrainSilhouette))
            var edge = Path()
            edge.addLines(run)
            context.stroke(edge, with: .color(obstructed ? LunaviColors.failureFill : LunaviColors.terrainEdge), lineWidth: 1.5)
        }
        for gap in gaps {
            context.fill(Path(CGRect(x: gap.lowerBound, y: 0, width: gap.upperBound - gap.lowerBound, height: size.height)),
                         with: .color(LunaviColors.unknown.opacity(0.18)))
        }

        // Angular scale: 1° bar.
        let bar = Path(CGRect(x: size.width - 12 - scale, y: size.height - 14, width: scale, height: 2))
        context.fill(bar, with: .color(LunaviColors.textSecondary))
        context.draw(Text("1°").font(LunaviTypography.micro).foregroundStyle(LunaviColors.textSecondary),
                     at: CGPoint(x: size.width - 12 - scale / 2, y: size.height - 24))
    }
}
