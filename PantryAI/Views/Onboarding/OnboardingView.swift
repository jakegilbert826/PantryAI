import SwiftUI
import AVFoundation
import SwiftData

struct OnboardingView: View {
    var onFinish: () -> Void
    @Environment(\.modelContext) private var context
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch step {
            case 0: WelcomeStep(next: { step = 1 })
            case 1: HouseholdStep(next: { step = 2 })
            case 2: RecipeSwipeView(onComplete: { step = 3 })
            case 3: CameraPermissionStep(next: onFinish)
            default: WelcomeStep(next: onFinish)
            }
        }
    }
}

// MARK: welcome

private struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            CaptionText(text: "PANTRY · v1.0")
                .padding(.bottom, 18)
            Mascot(size: 170)
            DisplayText(text: "Hi there!", size: 58, italic: true)
                .padding(.top, 28)
            DisplayText(text: "Let's stock\nyour pantry.", size: 28)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Text("Snap, scan, or sync — Pantry watches what you keep and tells you what's about to turn.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 18)
            Spacer()
            VStack(spacing: 12) {
                PillButton(title: "Get started", icon: "arrow.right", variant: .solid, size: .large, action: next)
                PillButton(title: "I already have an account", variant: .ghost, size: .regular) {}
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
}

// MARK: household

private struct HouseholdStep: View {
    let next: () -> Void
    @State private var size: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 90)
            CaptionText(text: "STEP 2 OF 4")
            DisplayText(text: "Who's eating?", size: 44, italic: true)
                .padding(.top, 8)
            Text("How many people share this kitchen?")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 8)
            HStack(spacing: 16) {
                Button { size = max(1, size - 1) } label: {
                    Image(systemName: "minus").font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.bg))
                        .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                Text("\(size)")
                    .font(.displayFallback(60, italic: true))
                    .frame(minWidth: 80)
                Button { size = min(8, size + 1) } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.bg))
                        .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)

            Spacer()
            PillButton(title: "Continue", icon: "arrow.right", variant: .solid, size: .large) {
                UserPreferences.shared.householdSize = size
                next()
            }
            .padding(.bottom, 50)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: camera

private struct CameraPermissionStep: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 90)
            CaptionText(text: "STEP 4 OF 4")
            DisplayText(text: "Open the lens.", size: 44, italic: true)
                .padding(.top, 8)
            Text("Pantry scans your shelves with the camera — only when you tap the shutter.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 12)
            Spacer()
            VStack(spacing: 12) {
                PillButton(title: "Allow camera access", icon: "camera.fill", variant: .solid, size: .large) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { next() }
                    }
                }
                PillButton(title: "Skip for now", variant: .ghost, size: .regular, action: next)
            }
            .padding(.bottom, 50)
        }
        .padding(.horizontal, 24)
    }
}
