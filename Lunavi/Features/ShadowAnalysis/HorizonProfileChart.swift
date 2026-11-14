import Charts
import SwiftUI

/// 360° terrain-horizon profile (Swift Charts) with the Sun and Earth plotted at their computed
/// azimuth and elevation. Grey columns are the modeled terrain; the dashed line is the ideal
/// (flat-Moon) horizon at 0°; hatched-looking columns mark sectors without terrain data.
struct HorizonProfileChart: View {
    let geometry: ShadowGeometry
    let sun: ShadowReading
    let earth: ShadowReading
    /// Centre the 360° window on the Sun (true) or show 0°–360° (false).
    var centeredOnSun: Bool

    private var center: Double {
        guard centeredOnSun, let azimuth = sun.direction?.azimuthDeg else { return 180 }
        return azimuth
    }

    var body: some View {
        let points = ShadowAnalysisService.chartPoints(geometry, centeredOn: center)
        let step = geometry.horizon.azimuthStepDeg
        let domain = yDomain(points)
        let lower = center - 180

        Chart {
            ForEach(points) { point in
                if point.isComplete {
                    RectangleMark(
                        xStart: .value("Azimuth", point.x - step / 2),
                        xEnd: .value("Azimuth", point.x + step / 2),
                        yStart: .value("Elevation", domain.lowerBound),
                        yEnd: .value("Terrain horizon", point.elevationDeg)
                    )
                    .foregroundStyle(LunaviColors.terrainFill)
                } else {
                    RectangleMark(
                        xStart: .value("Azimuth", point.x - step / 2),
                        xEnd: .value("Azimuth", point.x + step / 2),
                        yStart: .value("Elevation", domain.lowerBound),
                        yEnd: .value("Elevation", domain.upperBound)
                    )
                    .foregroundStyle(LunaviColors.unknown.opacity(0.18))
                }
            }

            ForEach(segments(points)) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Azimuth", point.x),
                        y: .value("Terrain horizon", point.elevationDeg),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(LunaviColors.terrainEdge)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }

            RuleMark(y: .value("Ideal horizon", 0.0))
                .foregroundStyle(LunaviColors.textMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Ideal horizon 0°")
                        .font(LunaviTypography.micro)
                        .foregroundStyle(LunaviColors.textMuted)
                }

            if let direction = earth.direction {
                targetMarks(reading: earth, direction: direction, color: LunaviColors.earthTrack, label: "Earth")
            }
            if let direction = sun.direction {
                targetMarks(reading: sun, direction: direction, color: LunaviColors.sunTrack, label: "Sun")
            }
        }
        .chartXScale(domain: lower...(lower + 360))
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: lower, through: lower + 360, by: 45))) { value in
                AxisGridLine().foregroundStyle(LunaviColors.border.opacity(0.5))
                AxisValueLabel {
                    if let x = value.as(Double.self) {
                        Text(Self.azimuthLabel(x))
                            .font(LunaviTypography.micro)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(LunaviColors.border.opacity(0.4))
                AxisValueLabel {
                    if let y = value.as(Double.self) {
                        Text("\(y.formatted(.number.precision(.fractionLength(0...1))))°")
                            .font(LunaviTypography.micro)
                            .foregroundStyle(LunaviColors.textMuted)
                    }
                }
            }
        }
        .chartXAxisLabel("Azimuth (clockwise from local north)", alignment: .center)
        .chartYAxisLabel("Elevation")
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("360 degree horizon profile")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("shadow.horizonChart")
    }

    @ChartContentBuilder
    private func targetMarks(reading: ShadowReading, direction: TargetDirection, color: Color, label: String) -> some ChartContent {
        let x = ShadowAnalysisService.chartX(for: direction.azimuthDeg, centeredOn: center)
        if let horizon = reading.terrainHorizonDeg {
            RuleMark(
                x: .value("Azimuth", x),
                yStart: .value("Elevation", min(horizon, direction.elevationDeg)),
                yEnd: .value("Elevation", max(horizon, direction.elevationDeg))
            )
            .foregroundStyle((reading.clearanceDeg ?? 0) < 0 ? LunaviColors.failureFill : color.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Azimuth", x), y: .value("Terrain horizon", horizon))
                .foregroundStyle(LunaviColors.failureFill)
                .symbol(.diamond)
                .symbolSize(40)
        }
        PointMark(x: .value("Azimuth", x), y: .value("Elevation", direction.elevationDeg))
            .foregroundStyle(color)
            .symbolSize(label == "Sun" ? 160 : 120)
            .annotation(position: .top) {
                Text(label)
                    .font(LunaviTypography.captionEmphasis)
                    .foregroundStyle(color)
            }
    }

    /// Contiguous runs of complete rays, so the horizon line never bridges a data gap.
    private func segments(_ points: [HorizonChartPoint]) -> [HorizonSegment] {
        var result: [HorizonSegment] = []
        var current: [HorizonChartPoint] = []
        for point in points {
            if point.isComplete {
                current.append(point)
            } else if !current.isEmpty {
                result.append(HorizonSegment(id: result.count, points: current))
                current = []
            }
        }
        if !current.isEmpty {
            result.append(HorizonSegment(id: result.count, points: current))
        }
        return result
    }

    private func yDomain(_ points: [HorizonChartPoint]) -> ClosedRange<Double> {
        var values = points.filter(\.isComplete).map(\.elevationDeg) + [0]
        values += [sun.direction?.elevationDeg, earth.direction?.elevationDeg].compactMap { $0 }
        let low = (values.min() ?? -1) - 0.75
        let high = (values.max() ?? 1) + 0.75
        return low...max(high, low + 1)
    }

    static func azimuthLabel(_ x: Double) -> String {
        let azimuth = ShadowAnalysisService.normalized(x.rounded())
        let cardinal: String
        switch Int(azimuth) {
        case 0: cardinal = " N"
        case 90: cardinal = " E"
        case 180: cardinal = " S"
        case 270: cardinal = " W"
        default: cardinal = ""
        }
        return "\(Int(azimuth))°\(cardinal)"
    }

    private var accessibilitySummary: String {
        [sun, earth].map { reading in
            let name = reading.condition == .sunlight ? "Sun" : "Earth"
            guard let direction = reading.direction else { return "\(name): data unavailable" }
            var text = "\(name) at azimuth \(Int(direction.azimuthDeg.rounded())) degrees, elevation \(direction.elevationDeg.formatted(.number.precision(.fractionLength(2)))) degrees"
            if let clearance = reading.clearanceDeg {
                text += clearance >= 0 ? ", above the terrain" : ", below the terrain"
            }
            return text
        }
        .joined(separator: ". ")
    }
}

private struct HorizonSegment: Identifiable {
    var id: Int
    var points: [HorizonChartPoint]
}
