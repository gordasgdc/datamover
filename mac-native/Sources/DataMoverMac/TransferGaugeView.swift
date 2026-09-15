import SwiftUI

/// Un inel circular cu o valoare mare în centru.
///
/// `Circle().trim(...)` cu `.stroke`, nu `ProgressViewStyle`: stilul custom
/// de progres primește doar `fractionCompleted`, iar două dintre cele trei
/// inele arată o VITEZĂ, care n-are o fracție naturală — se raportează la un
/// maxim observat în sesiunea curentă (vezi `fraction`).
struct TransferGaugeView: View {
    let title: String
    let value: String
    let unit: String
    /// 0...1. Pentru viteze: raportul față de maximul atins până acum.
    let fraction: Double
    let color: Color

    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Începe de sus, nu din dreapta (unde începe implicit un arc).
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: fraction)

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.top, 2)
            }
            .padding(lineWidth + 6)
        }
        .frame(width: 128, height: 128)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}
