import SwiftUI

/// Crescent built from two circles (custom geometry — SF Symbols must not be used in logos or icons).
struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let originX = rect.midX - diameter / 2
        let originY = rect.midY - diameter / 2
        let outer = Path(ellipseIn: CGRect(x: originX, y: originY, width: diameter, height: diameter))
        let cut = Path(ellipseIn: CGRect(
            x: originX + diameter * 0.32,
            y: originY - diameter * 0.08,
            width: diameter * 0.9,
            height: diameter * 0.9
        ))
        return outer.subtracting(cut)
    }
}

/// LUNAVI mark: crescent over a low-Sun horizon line.
struct LunaviLogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            CrescentShape()
                .fill(LunaviColors.textPrimary)
                .frame(width: size * 0.82, height: size * 0.82)
                .offset(y: -size * 0.06)
            Capsule()
                .fill(LunaviColors.selectedTime)
                .frame(width: size * 0.92, height: max(1.5, size * 0.055))
                .offset(y: size * 0.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Upward triangle used for obstruction / failing markers.
struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
