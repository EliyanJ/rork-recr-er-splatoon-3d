import SwiftUI

/// Octagonal "spider" chart for the 8 weapon stat axes — animated grid,
/// filled polygon that morphs when the selected weapon changes, and a
/// center graphic (weapon icon) sitting right in the middle of the web.
struct RadarChartView: View {
    let axes: [(label: String, value: Double)]
    let accent: Color
    let centerIcon: String

    private let ringCount = 4

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side * 0.36
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                // Background rings.
                ForEach(1...ringCount, id: \.self) { ring in
                    polygonPath(center: center, radius: radius * CGFloat(ring) / CGFloat(ringCount), values: nil)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                // Spokes.
                ForEach(0..<axes.count, id: \.self) { index in
                    spokeLine(center: center, radius: radius, index: index)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                // Filled data polygon.
                polygonPath(center: center, radius: radius, values: axes.map(\.value))
                    .fill(accent.opacity(0.28))
                polygonPath(center: center, radius: radius, values: axes.map(\.value))
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .shadow(color: accent.opacity(0.6), radius: 6)
                // Vertex dots.
                ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
                    let point = vertex(center: center, radius: radius, index: index, value: axis.value)
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
                // Axis labels.
                ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
                    let labelPoint = vertex(center: center, radius: radius + side * 0.135, index: index, value: 1)
                    Text(axis.label.uppercased())
                        .font(.system(size: side * 0.032, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(width: side * 0.22)
                        .position(labelPoint)
                }
                // Center graphic.
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: side * 0.2, height: side * 0.2)
                    Circle()
                        .stroke(accent.opacity(0.7), lineWidth: 1.5)
                        .frame(width: side * 0.2, height: side * 0.2)
                    Image(systemName: centerIcon)
                        .font(.system(size: side * 0.09, weight: .bold))
                        .foregroundStyle(accent)
                }
                .position(center)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: axes.map(\.value))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func angle(for index: Int) -> Angle {
        .degrees(-90 + Double(index) * (360.0 / Double(axes.count)))
    }

    private func vertex(center: CGPoint, radius: CGFloat, index: Int, value: Double) -> CGPoint {
        let a = angle(for: index).radians
        let r = radius * CGFloat(max(0.04, min(value, 1)))
        return CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
    }

    private func spokeLine(center: CGPoint, radius: CGFloat, index: Int) -> Path {
        var path = Path()
        let a = angle(for: index).radians
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius))
        return path
    }

    /// `values` nil draws a plain background ring at the given radius.
    private func polygonPath(center: CGPoint, radius: CGFloat, values: [Double]?) -> Path {
        var path = Path()
        let count = values?.count ?? axes.count
        guard count > 0 else { return path }
        for index in 0..<count {
            let value = values?[index] ?? 1
            let point = vertex(center: center, radius: radius, index: index, value: values == nil ? 1 : value)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RadarChartView(axes: WeaponType.charger.radarAxes, accent: Team.orange.color, centerIcon: WeaponType.charger.iconSystemName)
            .padding(40)
    }
}
