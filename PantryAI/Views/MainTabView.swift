import SwiftUI
import SwiftData

enum Tab: Hashable {
    case pantry, scan, recipes, household
}

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: Tab = .pantry

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            content
            FloatingTabBar(selection: $selection)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(Theme.bg)
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case .pantry:    PantryView()
        case .scan:      ScanView()
        case .recipes:   RecipesView()
        case .household: SettingsView()
        }
    }
}

/// Pill-shaped floating tab bar, matches the `.tabbar` CSS class.
private struct FloatingTabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 4) {
            tab(.pantry, system: "tray.full.fill")
            tab(.scan, system: "plus")
            tab(.recipes, system: "fork.knife")
            tab(.household, system: "person.2.fill")
        }
        .accessibilityIdentifier("tabbar")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
        .shadow(color: Theme.ink.opacity(0.12), radius: 20, y: 8)
    }

    private func tab(_ kind: Tab, system: String) -> some View {
        Button {
            selection = kind
        } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(selection == kind ? Theme.bg : Theme.ink3)
                .background(
                    Capsule(style: .continuous)
                        .fill(selection == kind ? Theme.ink : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(kind)")
        .accessibilityLabel(Text(label(for: kind)))
    }

    private func label(for kind: Tab) -> String {
        switch kind {
        case .pantry:    return "Pantry"
        case .scan:      return "Scan"
        case .recipes:   return "Recipes"
        case .household: return "Household"
        }
    }
}
