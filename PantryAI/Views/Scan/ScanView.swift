import SwiftUI
import SwiftData
import UIKit

struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var vm: ScanViewModel?

    var body: some View {
        Group {
            if let vm {
                switch vm.stage {
                case .capturing: CaptureStage(vm: vm)
                case .analysing: AnalysingStage()
                case .review:    ReviewStage(vm: vm)
                case .done:      DoneStage(vm: vm)
                }
            } else {
                Color.clear.onAppear { vm = ScanViewModel(context: context) }
            }
        }
        .background(Theme.bg)
    }
}

// MARK: capture

private struct CaptureStage: View {
    let vm: ScanViewModel
    @State private var captureRequest: UUID?
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            CameraView(
                captureRequest: $captureRequest,
                onPhoto: { vm.add(photo: $0) },
                onError: { cameraError = $0 }
            )
            .ignoresSafeArea()

            VStack { topBar; Spacer(); bottomPanel }
        }
        .alert("Camera", isPresented: Binding(get: { cameraError != nil }, set: { _ in cameraError = nil })) {
            Button("OK") {}
        } message: {
            Text(cameraError ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "xmark", background: .white.opacity(0.1), foreground: .white) {}
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            Spacer()
            CaptionText(text: "PHOTO · FRIDGE", color: .white.opacity(0.7))
            Spacer()
            CircleIconButton(systemName: "bell", background: .white.opacity(0.1), foreground: .white) {}
        }
        .padding(.horizontal, 22)
        .padding(.top, 70)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                DisplayText(text: "Found \(vm.captured.count) photos", size: 26, italic: true)
                Spacer()
                CaptionText(text: "LIVE")
            }
            Text("Hold steady — tap shutter when ready. Up to 6 photos.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .padding(.bottom, 8)

            HStack(spacing: 14) {
                CircleIconButton(systemName: "photo.on.rectangle", size: 44) {}
                Spacer()
                Button {
                    if vm.canCaptureMore { captureRequest = UUID() }
                } label: {
                    ZStack {
                        Circle().fill(Theme.amber)
                        Circle().stroke(Theme.ink, lineWidth: 3)
                        Circle().fill(Theme.ink).frame(width: 28, height: 28)
                    }
                    .frame(width: 68, height: 68)
                    .background(
                        Circle().fill(Theme.ink).offset(y: 5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!vm.canCaptureMore)
                Spacer()
                PillButton(title: "Done", variant: .solid, size: .small) {
                    Task { await vm.analyse() }
                }
                .fixedSize()
                .disabled(vm.captured.isEmpty)
                .opacity(vm.captured.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 44)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 32, topTrailing: 32))
                .fill(Theme.bg)
        )
    }
}

// MARK: analysing

private struct AnalysingStage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Ring(percentage: 0.7, size: 80, stroke: 8, color: Theme.ink, track: Theme.border)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: UUID())
            DisplayText(text: "Reading the shelf…", size: 24, italic: true)
            Text("Gemini Vision is identifying items.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

// MARK: review

private struct ReviewStage: View {
    @Bindable var vm: ScanViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    CircleIconButton(systemName: "chevron.left") { vm.reset() }
                    VStack(alignment: .leading, spacing: 2) {
                        CaptionText(text: "STEP 2 OF 2")
                        DisplayText(text: "Review what we found", size: 24, italic: true)
                    }
                    Spacer()
                }
                .padding(.top, 70)
                .padding(.horizontal, 22)

                Text("Tap to toggle. Confirmed items will join your pantry.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 22)

                VStack(spacing: 12) {
                    ForEach(vm.detected) { item in
                        DetectedRow(item: item, toggle: { vm.toggle(item) })
                    }
                }
                .padding(.horizontal, 22)

                PillButton(title: "Add \(vm.detected.filter { $0.include }.count) to pantry", icon: "arrow.right", variant: .solid) {
                    vm.commit()
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .background(Theme.bg)
    }
}

private struct DetectedRow: View {
    let item: ScannedItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.bg)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                    Image(systemName: item.include ? "checkmark" : "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    DisplayText(text: item.name, size: 19)
                    Text("\(item.category.displayName) · \(Int(item.confidence * 100))% confident")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(item.include ? item.category.cardColor : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DoneStage: View {
    let vm: ScanViewModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Mascot(size: 140)
            DisplayText(text: "Pantry updated!", size: 28, italic: true)
            Text("Your new items are in.")
                .font(.system(size: 14)).foregroundStyle(Theme.ink2)
            PillButton(title: "Scan more", variant: .ghost, size: .regular) { vm.reset() }
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}
