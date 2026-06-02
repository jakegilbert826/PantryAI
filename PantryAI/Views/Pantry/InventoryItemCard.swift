import SwiftUI

struct InventoryItemCard: View {
    let item: InventoryItem

    var body: some View {
        let confidence = item.currentConfidence
        let isUrgent = confidence < 0.4
        ZStack(alignment: .topTrailing) {
            cardContent(confidence: confidence)
                .opacity(confidence < 0.4 ? 0.78 : 1)
            if isUrgent {
                Text("SOON")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.ink))
                    .offset(x: -12, y: -8)
            }
        }
    }

    @ViewBuilder
    private func cardContent(confidence: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CaptionText(text: item.storageLocation.displayName, color: Theme.ink2)
            DisplayText(text: item.canonicalName, size: 19)
                .lineLimit(2)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(alignment: .bottom) {
                Text("\(Int(confidence * 100))%")
                    .font(.displayFallback(22, italic: true))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Ring(percentage: confidence, size: 32, stroke: 4)
            }
            if AppConfig.showDecayModelDebug {
                Text(item.decayModel.modelIdentifier)
                    .font(.system(size: 9, weight: .semibold).monospaced())
                    .foregroundStyle(Theme.ink2.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(item.foodCategory.cardColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let brand = item.brandName { parts.append(brand) }
        if let value = item.measureValue {
            parts.append("\(Int(value * 100))% \(item.measureUnit.rawValue)")
        }
        if parts.isEmpty { parts.append(item.foodCategory.displayName.lowercased()) }
        return parts.joined(separator: " · ")
    }
}
