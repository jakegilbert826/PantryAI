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
                if let vm, vm.hasLowItems {
                    heroAttentionCard(items: vm.lowItems)
                        .padding(.top, 22)
                        .padding(.horizontal, 22)
                }
                if let vm {
                    sectionHeader(count: vm.filteredItems.count)
                        .padding(.top, 16)
                        .padding(.horizontal, 22)
                    searchBar(text: Binding(
                        get: { vm.searchText },
                        set: { vm.searchText = $0 }
                    ))
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    grid(items: vm.filteredItems)
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
        .sheet(item: $selected, onDismiss: { vm?.load() }) { item in
            InventoryItemDetail(item: item)
        }
    }

    // MARK: hero attention card

    private func heroAttentionCard(items: [InventoryItem]) -> some View {
        ChunkyCard(background: Theme.amber, radius: Theme.bigCardRadius) {
            VStack(alignment: .leading, spacing: 12) {
                CaptionText(text: "USE FIRST · \(items.count) ITEMS", color: Theme.ink2)
                let headline = items.prefix(2).map(\.canonicalName).joined(separator: " & ")
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

    // MARK: search bar

    private func searchBar(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            TextField("Search pantry…", text: text)
                .font(.body(15))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .submitLabel(.search)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.ink)
                .offset(y: Theme.chunkyShadowOffset)
        )
    }

    // MARK: section header

    private func sectionHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            DisplayText(text: "Your pantry", size: 48)
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
