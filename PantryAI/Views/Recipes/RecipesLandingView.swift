import SwiftUI

struct RecipesLandingView: View {
    let vm: RecipesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(spacing: 14) {
                    NavigationLink {
                        RecipesView(vm: vm)
                    } label: {
                        LandingCard(
                            title: "Recipe Suggestions",
                            description: "Recipes Pip picks based on your pantry",
                            icon: "sparkles",
                            accent: Theme.mint
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SavedRecipesView(vm: vm)
                    } label: {
                        LandingCard(
                            title: "Saved Recipes",
                            description: "Your bookmarked recipes, ready to cook",
                            icon: "heart.fill",
                            accent: Theme.sky
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RecipeChatView(vm: vm)
                    } label: {
                        LandingCard(
                            title: "Recipe Chat",
                            description: "Tell Pip exactly what you're craving",
                            icon: "bubble.left.and.bubble.right.fill",
                            accent: Theme.amber
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LiveCookingView()
                    } label: {
                        LandingCard(
                            title: "Live Cooking",
                            description: "Step-by-step instructions with a built-in timer",
                            icon: "timer",
                            accent: Theme.lilac,
                            comingSoon: true
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .onAppear {
            Task { await vm.refresh() }
        }
    }

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
                CaptionText(text: "PIP'S KITCHEN")
                DisplayText(text: "What are we making?", size: 22)
            }
            Spacer()
        }
        .padding(.top, 70)
    }
}

private struct LandingCard: View {
    let title: String
    let description: String
    let icon: String
    let accent: Color
    var comingSoon: Bool = false

    var body: some View {
        ChunkyCard {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                    )
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    )
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.displayFallback(18, italic: true))
                            .foregroundStyle(Theme.ink)
                        if comingSoon {
                            Text("SOON")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous).fill(Theme.lilac)
                                )
                                .overlay(
                                    Capsule(style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                                )
                        }
                    }
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(16)
        }
    }
}
