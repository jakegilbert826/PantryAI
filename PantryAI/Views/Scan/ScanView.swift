import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var vm: ScanViewModel?

    var body: some View {
        Group {
            if let vm {
                switch vm.stage {
                case .method:    MethodStage(vm: vm)
                case .capturing: CaptureStage(vm: vm)
                case .analysing: AnalysingStage(vm: vm)
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

// MARK: method picker

/// "Add to your pantry" — STEP 1 OF 2. The user chooses how they're capturing;
/// every method funnels into the same review pane. Only Photo is wired to a
/// backend today; the rest advertise themselves but report "coming soon".
private struct MethodStage: View {
    let vm: ScanViewModel
    @State private var comingSoon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                DisplayText(text: "Add to\nyour pantry", size: 48, italic: true)
                Text("Pick how you're capturing — every method lands in the same review pane.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 16)

            VStack(spacing: 16) {
                ForEach(CaptureMethod.allCases) { method in
                    MethodCard(method: method) {
                        switch method {
                        case .receipt: vm.startReceiptCapture()
                        case .photo:   vm.startPhotoCapture()
                        default:       comingSoon = method.title
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .alert("Coming soon", isPresented: Binding(get: { comingSoon != nil }, set: { _ in comingSoon = nil })) {
            Button("OK") {}
        } message: {
            Text("\(comingSoon ?? "This method") isn't available yet — use Photo to scan a shelf for now.")
        }
    }
}

/// The four capture methods shown on the Add screen, in design order.
private enum CaptureMethod: Int, CaseIterable, Identifiable {
    case receipt, photo, video, email

    var id: Int { rawValue }
    var number: String { String(format: "%02d", rawValue + 1) }
    var isAvailable: Bool { self == .photo || self == .receipt }

    var title: String {
        switch self {
        case .receipt: return "Receipt"
        case .photo:   return "Photo"
        case .video:   return "Video pan"
        case .email:   return "Email"
        }
    }

    var subtitle: String {
        switch self {
        case .receipt: return "Snap a paper receipt — we read it."
        case .photo:   return "Shoot a shelf or drawer."
        case .video:   return "Slow-pan for dense, packed storage."
        case .email:   return "Sync grocery orders from your inbox."
        }
    }

    var icon: String {
        switch self {
        case .receipt: return "doc.text"
        case .photo:   return "camera.fill"
        case .video:   return "video.fill"
        case .email:   return "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .receipt: return Theme.rose
        case .photo:   return Theme.sky
        case .video:   return Theme.mint
        case .email:   return Theme.amber
        }
    }
}

private struct MethodCard: View {
    let method: CaptureMethod
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChunkyCard {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(method.color)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                        Image(systemName: method.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        CaptionText(text: method.number)
                        DisplayText(text: method.title, size: 20)
                        Text(method.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    if method.isAvailable {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    } else {
                        CaptionText(text: "Soon", color: Theme.ink3)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("method.\(method.title)")
        .accessibilityLabel(Text(method.title))
    }
}

// MARK: capture

private struct CaptureStage: View {
    let vm: ScanViewModel
    @State private var captureRequest: UUID?
    @State private var cameraError: String?
    @State private var showLibrary = false
    @State private var pickedItems: [PhotosPickerItem] = []

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
        .photosPicker(
            isPresented: $showLibrary,
            selection: $pickedItems,
            maxSelectionCount: max(1, vm.remainingCapacity),
            matching: .images
        )
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadFromLibrary(items) }
        }
        .alert("Camera", isPresented: Binding(get: { cameraError != nil }, set: { _ in cameraError = nil })) {
            Button("OK") {}
        } message: {
            Text(cameraError ?? "")
        }
        .alert("Couldn't scan", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
            Button("OK") {}
        } message: {
            Text(vm.error?.errorDescription ?? "Something went wrong while reading your photos.")
        }
    }

    /// Pull the chosen library images into the capture session, respecting the
    /// 6-photo cap, then clear the selection so the picker can be reopened.
    private func loadFromLibrary(_ items: [PhotosPickerItem]) async {
        for item in items where vm.canCaptureMore {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                vm.add(photo: image)
            }
        }
        pickedItems = []
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "xmark", background: .white.opacity(0.1), foreground: .white) { vm.reset() }
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            Spacer()
            CaptionText(text: vm.captureMode == .receipt ? "RECEIPT SCAN" : "PHOTO · FRIDGE", color: .white.opacity(0.7))
            Spacer()
            CircleIconButton(systemName: "bell", background: .white.opacity(0.1), foreground: .white) {}
        }
        .padding(.horizontal, 22)
        .padding(.top, 70)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                DisplayText(text: "Found \(vm.captured.count) \(vm.captureMode == .receipt ? "receipt\(vm.captured.count == 1 ? "" : "s")" : "photo\(vm.captured.count == 1 ? "" : "s")")", size: 26, italic: true)
                Spacer()
                CaptionText(text: "LIVE")
            }
            Text(vm.captureMode == .receipt
                 ? "Lay the receipt flat — tap shutter when ready."
                 : "Hold steady — tap shutter when ready. Up to 6 photos.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .padding(.bottom, 8)

            HStack(spacing: 14) {
                CircleIconButton(systemName: "photo.on.rectangle", size: 44) {
                    if vm.canCaptureMore { showLibrary = true }
                }
                .disabled(!vm.canCaptureMore)
                .opacity(vm.canCaptureMore ? 1 : 0.4)
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
    let vm: ScanViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Ring(percentage: 0.7, size: 80, stroke: 8, color: Theme.ink, track: Theme.border)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: UUID())
            DisplayText(text: vm.captureMode == .receipt ? "Reading the receipt…" : "Reading the shelf…", size: 24, italic: true)
            Text(vm.captureMode == .receipt ? "Gemini is parsing your grocery items." : "Gemini Vision is identifying items.")
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
