import SwiftUI
import Charts
import SwiftData

struct InventoryItemDetail: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                content
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            item.category.cardColor
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }
                    Spacer()
                    CaptionText(text: "\(item.category.displayName.uppercased()) · \(item.category.location.displayName.uppercased())", color: Theme.ink2)
                    Spacer()
                    CircleIconButton(systemName: "ellipsis") {}
                }
                .padding(.top, 70)
                .padding(.horizontal, 22)

                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayText(text: item.name, size: 44, italic: true)
                            .multilineTextAlignment(.leading)
                        Text("\(item.brand ?? item.category.displayName) · opened \(daysSinceScan)d ago")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 0)
                    Ring(percentage: item.currentConfidence, size: 70, stroke: 7)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
        }
        .background(item.category.cardColor)
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 32, bottomTrailing: 32))
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 32, bottomTrailing: 32)))
    }

    // MARK: content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                DisplayText(text: "How it's aging", size: 19)
                Spacer()
                CaptionText(text: "30 DAYS")
            }
            decayChart
            HStack(spacing: 10) {
                statCard(label: "USE BY", value: "~ \(daysLeftEstimate) days", color: Theme.mint)
                statCard(label: "CONFIDENCE", value: "\(Int(item.currentConfidence * 100))%", color: Theme.sky)
            }
            PillButton(title: "Find recipes using this", icon: "arrow.right", variant: .solid) {}
                .padding(.top, 4)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private var decayChart: some View {
        let points = decayProjection()
        return ChunkyCard(background: Theme.surface, radius: Theme.cardRadius) {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(points, id: \.day) { p in
                        AreaMark(
                            x: .value("Day", p.day),
                            y: .value("Confidence", p.confidence)
                        )
                        .foregroundStyle(Theme.amber.opacity(0.4))
                        LineMark(
                            x: .value("Day", p.day),
                            y: .value("Confidence", p.confidence)
                        )
                        .foregroundStyle(Theme.ink)
                        .lineStyle(.init(lineWidth: 2.5))
                    }
                    PointMark(
                        x: .value("Day", 0),
                        y: .value("Confidence", item.currentConfidence)
                    )
                    .foregroundStyle(item.category.cardColor)
                    .symbolSize(120)
                }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 130)

                HStack {
                    Text("OPENED")
                    Spacer()
                    Text("TODAY").foregroundStyle(Theme.ink).bold()
                    Spacer()
                    Text("WK 2")
                    Spacer()
                    Text("WK 3")
                    Spacer()
                    Text("SPOILED")
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.ink3)
            }
            .padding(16)
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptionText(text: label, color: Theme.ink2)
            Text(value)
                .font(.displayFallback(24, italic: true))
                .foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
    }

    // MARK: derived

    private var daysSinceScan: Int {
        max(0, Calendar.current.dateComponents([.day], from: item.lastScanDate, to: .now).day ?? 0)
    }

    private var daysLeftEstimate: Int {
        let model = item.decayModel
        for day in 0...60 {
            let pretendScanDate = item.lastScanDate.addingTimeInterval(-Double(day) * 86_400)
            let projected = model.confidence(
                lastScanConfidence: item.lastScanConfidence,
                lastScanDate: pretendScanDate,
                householdSize: UserPreferences.shared.householdSize,
                usageHistory: item.usageHistory
            )
            if projected < 0.05 { return day }
        }
        return 30
    }

    private struct ProjectedPoint { let day: Int; let confidence: Double }

    private func decayProjection() -> [ProjectedPoint] {
        // The decay model is `f(lastScanConfidence, lastScanDate, now)`. To
        // project `offset` days into the future, we shift the scan date that
        // many days into the past instead — same elapsed delta.
        let model = item.decayModel
        return (0...30).map { offset in
            let pretendScanDate = item.lastScanDate.addingTimeInterval(-Double(offset) * 86_400)
            let conf = model.confidence(
                lastScanConfidence: item.lastScanConfidence,
                lastScanDate: pretendScanDate,
                householdSize: UserPreferences.shared.householdSize,
                usageHistory: item.usageHistory
            )
            return ProjectedPoint(day: offset, confidence: conf)
        }
    }
}
