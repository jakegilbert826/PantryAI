import SwiftUI

struct InventoryItemDetail: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var quantity: Double
    @State private var initialQuantity: Double
    @State private var location: StorageLocation
    @State private var draftQuantityText: String = ""
    @State private var draftUnit: MeasureUnit
    @State private var isEditingQuantity = false

    init(item: InventoryItem) {
        self.item = item
        // `measureValue` is the single source of truth; the container view is a
        // lens over it. `quantity` mirrors it for snappy stepping.
        let initialQty = item.measureValue ?? 0
        _quantity = State(initialValue: initialQty)
        _initialQuantity = State(initialValue: initialQty)
        _location = State(initialValue: item.storageLocation)
        _draftUnit = State(initialValue: item.measureUnit)
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            bodyContent
        }
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
        .onDisappear {
            saveLocationIfNeeded()
            logConsumptionIfNeeded()
        }
    }

    // MARK: hero

    private var hero: some View {
        ZStack {
            item.foodCategory.cardColor
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }
                    Spacer()
                    CaptionText(text: item.foodCategory.displayName.uppercased(), color: Theme.ink2)
                    Spacer()
                    CircleIconButton(systemName: "ellipsis") {}
                }
                .padding(.top, 56)
                .padding(.horizontal, 22)

                VStack(alignment: .leading, spacing: 6) {
                    DisplayText(text: item.canonicalName, size: 40, italic: true)
                        .multilineTextAlignment(.leading)
                    Text("\(item.brandName ?? item.foodCategory.displayName) · \(location.displayName.lowercased())")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28))
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28)))
    }

    // MARK: body

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if (item.measureValue ?? 0) <= 0 {
                addAmountCard
            } else {
                amountCard
            }
            Grid(horizontalSpacing: 12) {
                GridRow(alignment: .top) {
                    useByCard
                    addToListCard
                }
            }
            locationCard
            sourcesCard
            Spacer()
            PillButton(title: "Find recipes using this", icon: "arrow.right", variant: .solid) {}
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 28)
    }

    // MARK: add amount card (shown when quantity is unknown)

    private var inputUnits: [MeasureUnit] {
        switch item.measureType {
        case .weight:       return [.g, .kg]
        case .volume:       return [.ml, .l]
        case .count, .bunch: return [.unit]
        }
    }

    private var addAmountCard: some View {
        ChunkyCard(background: Theme.surface, shadowOffset: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CaptionText(text: "ADD AMOUNT")
                    Spacer()
                    Menu {
                        ForEach(inputUnits, id: \.self) { unit in
                            Button(unit.rawValue) { draftUnit = unit }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(draftUnit.rawValue.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.ink2)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .padding(.bottom, 12)

                TextField("0", text: $draftQuantityText)
                    .keyboardType(.decimalPad)
                    .font(.displayFallback(36, italic: true))
                    .foregroundStyle(Theme.ink)
                    .frame(height: 44)
                    .padding(.bottom, 14)

                Divider()
                    .padding(.bottom, 12)

                PillButton(title: "Save", icon: "checkmark", variant: .solid, size: .small) {
                    saveQuantity()
                }
                .disabled((Double(draftQuantityText) ?? 0) <= 0)
                .opacity((Double(draftQuantityText) ?? 0) > 0 ? 1 : 0.4)
            }
            .padding(16)
        }
    }

    private func saveQuantity() {
        guard let raw = Double(draftQuantityText), raw > 0 else { return }
        let (value, unit): (Double, MeasureUnit) = switch draftUnit {
            case .kg: (raw * 1000, .g)
            case .l:  (raw * 1000, .ml)
            default:  (raw, draftUnit)
        }
        item.measureValue = value
        item.measureUnit = unit
        item.measureType = MeasureType.from(unit)
        item.updatedAt = .now
        quantity = value
        initialQuantity = value
        try? context.save()
    }

    // MARK: amount card

    private var amountCard: some View {
        ChunkyCard(background: Theme.surface, shadowOffset: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CaptionText(text: "AMOUNT")
                    Spacer()
                    CaptionText(text: item.displayUnitLabel)
                }
                .padding(.bottom, 12)

                amountStepper
                    .padding(.bottom, 14)

                Divider()
                    .padding(.bottom, 12)

                presetChips
            }
            .padding(16)
        }
    }

    // MARK: persistence

    /// Write the edited amount straight through to the model (fixes the prior
    /// "doesn't update on save()" bug). `measureValue` is the source of truth.
    private func setQuantity(_ newValue: Double) {
        let clamped = max(0, newValue)
        quantity = clamped
        item.measureValue = clamped
        item.updatedAt = .now
        try? context.save()
    }

    /// Steps the amount up/down by `stepAmount`, snapping to the next clean
    /// multiple of the step rather than offsetting an "untidy" current value
    /// (e.g. 173 → 180 / 170, not 183 / 163).
    private func stepQuantity(up: Bool) {
        let step = item.amountStepSize
        guard step > 0 else { return }
        let ratio = quantity / step
        let index: Double = up ? (floor(ratio + 1e-6) + 1) : (ceil(ratio - 1e-6) - 1)
        setQuantity(index * step)
    }

    /// Records net consumption once when leaving the screen. Usage logs are in
    /// 0–1 confidence-fraction units (see `DecayModel.applyingUsage`), so we log
    /// the consumed proportion of the amount present when the card opened.
    private func saveLocationIfNeeded() {
        guard location != item.storageLocation else { return }
        item.storageLocation = location
        item.updatedAt = .now
        try? context.save()
    }

    private func logConsumptionIfNeeded() {
        let start = initialQuantity
        let finalQty = item.measureValue ?? 0
        guard start > 0, finalQty < start else { return }
        let fraction = min(1, (start - finalQty) / start)
        guard fraction > 0 else { return }
        let log = ItemQuantityLog(
            item: item,
            measureType: item.measureType,
            measureValue: fraction,
            measureUnit: item.measureUnit,
            measureConfidence: item.measureConfidence,
            source: .manual
        )
        context.insert(log)
        item.quantityLog.append(log)
        item.updatedAt = .now
        try? context.save()
    }

    private var amountStepper: some View {
        HStack(spacing: 14) {
            Button {
                isEditingQuantity = false
                stepQuantity(up: false)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
            }
            .buttonStyle(.plain)

            if isEditingQuantity {
                TextField("", text: $draftQuantityText)
                    .keyboardType(.decimalPad)
                    .font(.displayFallback(36, italic: true))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .onSubmit { commitInlineEdit() }
            } else {
                DisplayText(text: quantityLabel, size: 36, italic: true)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { beginInlineEdit() }
            }

            Button {
                isEditingQuantity = false
                stepQuantity(up: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
            }
            .buttonStyle(.plain)
        }
    }

    private func beginInlineEdit() {
        let v = quantity
        let displayValue: Double = switch item.measureUnit {
            case .g  where v >= 1000: v / 1000
            case .ml where v >= 1000: v / 1000
            default: v
        }
        draftQuantityText = InventoryItem.formatNumber(displayValue)
        isEditingQuantity = true
    }

    private func commitInlineEdit() {
        guard let raw = Double(draftQuantityText), raw > 0 else {
            isEditingQuantity = false
            return
        }
        let value: Double = switch item.measureUnit {
            case .g  where quantity >= 1000: raw * 1000
            case .ml where quantity >= 1000: raw * 1000
            default: raw
        }
        setQuantity(value)
        isEditingQuantity = false
    }

    private var presetChips: some View {
        HStack(spacing: 8) {
            presetChip("Half left",   danger: false) { setQuantity((initialQuantity * 0.5).rounded(toDecimalPlaces: 1)) }
            presetChip("Almost gone", danger: false) { setQuantity((initialQuantity * 0.1).rounded(toDecimalPlaces: 1)) }
            presetChip("Used it all", danger: true)  { setQuantity(0) }
        }
    }

    @ViewBuilder
    private func presetChip(_ label: String, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.displayFallback(13))
                .foregroundStyle(Theme.ink)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Capsule(style: .continuous).fill(danger ? Color.clear : Theme.surface))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(style: danger
                            ? StrokeStyle(lineWidth: Theme.strokeWidth, dash: [5, 3])
                            : StrokeStyle(lineWidth: Theme.strokeWidth))
                        .foregroundStyle(Theme.ink)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 2-up stat cards

    private var useByCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CaptionText(text: "USE BY")
            DisplayText(text: "~ \(daysLeftEstimate) days", size: 26, italic: true)
                .padding(.vertical, 4)
            freshnessBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.mint))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
    }

    private var freshnessBar: some View {
        let pct = item.currentConfidence
        let fill: Color = pct > 0.6 ? Theme.mint : pct > 0.3 ? Theme.amber : Theme.rose
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bg)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, geo.size.width * CGFloat(pct)))
            }
            .overlay(Capsule().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
        }
        .frame(height: 12)
    }

    private var addToListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptionText(text: "ADD TO LIST")
            Spacer()
            HStack(spacing: 8) {
                Button {} label: {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink))
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.amber))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
    }

    // MARK: location card

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptionText(text: "STORED IN")
            locationControl
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
    }

    private var locationControl: some View {
        HStack(spacing: 6) {
            ForEach(StorageLocation.allCases) { loc in
                let selected = loc == location
                Button { location = loc } label: {
                    VStack(spacing: 4) {
                        Image(systemName: locationIcon(loc))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selected ? Theme.bg : Theme.ink)
                        Text(loc.displayName)
                            .font(.displayFallback(11))
                            .foregroundStyle(selected ? Theme.bg : Theme.ink2)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.ink : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
        )
    }

    private func locationIcon(_ loc: StorageLocation) -> String {
        switch loc {
        case .fridge:  return "refrigerator"
        case .freezer: return "snowflake"
        case .pantry:  return "archivebox"
        }
    }

    // MARK: sources card

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptionText(text: "WHERE THIS CAME FROM")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sourceChip(icon: "camera", label: "Pantry scan", when: relativeScanDate)
                    ForEach(derivedSources, id: \.label) { src in
                        sourceChip(icon: src.icon, label: src.label, when: src.when)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
    }

    private func sourceChip(icon: String, label: String, when: String) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .overlay(Circle().stroke(Theme.ink, lineWidth: 1))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !when.isEmpty {
                Text("·")
                    .foregroundStyle(Theme.ink3)
                Text(when)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .background(Capsule().fill(Theme.bg).overlay(Capsule().stroke(Theme.ink, lineWidth: Theme.strokeWidth)))
    }

    // MARK: derived

    private var quantityLabel: String { item.amountDisplay }

    private var daysLeftEstimate: Int {
        let model = item.decayModel
        let scanDate = item.lastScannedAt ?? item.addedAt
        for day in 0...60 {
            let pretendScanDate = scanDate.addingTimeInterval(-Double(day) * 86_400)
            let projected = model.confidence(
                lastScanConfidence: item.measureConfidence,
                lastScanDate: pretendScanDate,
                householdSize: UserPreferences.shared.householdSize,
                usageHistory: item.quantityLog
            )
            if projected < 0.05 { return day }
        }
        return 30
    }

    private var relativeScanDate: String {
        let ref = item.lastScannedAt ?? item.addedAt
        let days = max(0, Calendar.current.dateComponents([.day], from: ref, to: .now).day ?? 0)
        return days == 0 ? "today" : "\(days)d ago"
    }

    private struct DerivedSource { let icon: String; let label: String; let when: String }

    private var derivedSources: [DerivedSource] {
        var sources: [DerivedSource] = []
        if item.quantityLog.contains(where: { $0.source == .manual }) {
            sources.append(.init(icon: "hand.tap", label: "You, in app", when: ""))
        }
        if item.quantityLog.contains(where: { $0.source == .usageLog }) {
            sources.append(.init(icon: "frying.pan", label: "Recipe cooked", when: ""))
        }
        return sources
    }

}

private extension Double {
    func rounded(toDecimalPlaces dp: Int) -> Double {
        let factor = pow(10.0, Double(dp))
        return (self * factor).rounded() / factor
    }
}
