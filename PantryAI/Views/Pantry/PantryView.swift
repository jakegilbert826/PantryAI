import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: PantryViewModel?
    @State private var selected: InventoryItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if let vm, vm.hasLowItems {
                    heroAttentionCard(items: vm.lowItems)
                        .padding(.top, 22)
                        .padding(.horizontal, 22)
                }
                if let vm {
                    sectionHeader(count: vm.items.count)
                        .padding(.top, 22)
                        .padding(.horizontal, 22)
                    grid(items: vm.items)
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }
            }
        }
        .background(Theme.bg)
        .refreshable {
            await vm?.refresh()
        }
        .onAppear {
            if vm == nil { vm = PantryViewModel(context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm?.load() }
        }
        .sheet(item: $selected) { item in
            InventoryItemDetail(item: item)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.amber)
                Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                Text("P")
                    .font(.displayFallback(20, italic: true))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                CaptionText(text: "Hi there")
                DisplayText(text: "What's cooking?", size: 22)
            }
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.amber)
                Text("12d")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.bg)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.ink))
        }
        .padding(.horizontal, 22)
        .padding(.top, 70)
    }

    // MARK: hero attention card

    private func heroAttentionCard(items: [InventoryItem]) -> some View {
        ChunkyCard(background: Theme.amber, radius: Theme.bigCardRadius) {
            VStack(alignment: .leading, spacing: 12) {
                CaptionText(text: "USE FIRST · \(items.count) ITEMS", color: Theme.ink2)
                let headline = items.prefix(2).map(\.name).joined(separator: " & ")
                Text("\(headline)\n\(items.count > 1 ? "are" : "is") fading fast.")
                    .font(.displayFallback(28, italic: true))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                HStack(alignment: .bottom) {
                    PillButton(title: "See recipes", icon: "arrow.right", variant: .solid, size: .small) {}
                        .fixedSize()
                    Spacer()
                    Ring(percentage: items.first?.currentConfidence ?? 0.3, size: 56, stroke: 6)
                }
            }
            .padding(20)
        }
    }

    // MARK: section header

    private func sectionHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            DisplayText(text: "Your pantry", size: 22)
            Spacer()
            CaptionText(text: "\(count) items")
        }
    }

    // MARK: grid

    private func grid(items: [InventoryItem]) -> some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(items) { item in
                InventoryItemCard(item: item)
                    .onTapGesture { selected = item }
            }
        }
    }
}
