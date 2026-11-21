import SwiftUI

struct ThresholdGauge: View {
    let value: Double
    let thresholds: [Double]
    let tint: Color

    private let trackHeight: CGFloat = 5
    private let tickHeight: CGFloat = 4
    private let tickGap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(thresholds, id: \.self) { threshold in
                    Capsule()
                        .fill(.secondary.opacity(0.7))
                        .frame(width: 1.5, height: tickHeight)
                        .offset(x: width * min(max(threshold, 0), 1) - 0.75, y: 0)
                }

                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: trackHeight)
                    .offset(y: tickHeight + tickGap)

                Capsule()
                    .fill(tint)
                    .frame(width: width * min(max(value, 0), 1), height: trackHeight)
                    .offset(y: tickHeight + tickGap)
            }
        }
        .frame(height: tickHeight + tickGap + trackHeight)
    }
}
