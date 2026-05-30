import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var vm: SettingsViewModel?
    @State private var showClearAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let vm {
                    householdCard(vm)
                    serverCard(vm)
                    geminiCard(vm)
                    debugCard(vm)
                    dangerCard(vm)
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .onAppear { if vm == nil { vm = SettingsViewModel(context: context) } }
        .alert("Clear all inventory?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { vm?.clearAllInventory() }
        } message: {
            Text("This deletes every item, usage log, and scan from this device. The decay model history will be lost too.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptionText(text: "HOUSEHOLD")
            DisplayText(text: "Settings", size: 36, italic: true)
        }
        .padding(.top, 70)
    }

    private func householdCard(_ vm: SettingsViewModel) -> some View {
        ChunkyCard(background: Theme.mint, radius: Theme.cardRadius) {
            VStack(alignment: .leading, spacing: 10) {
                CaptionText(text: "PEOPLE IN HOUSEHOLD", color: Theme.ink2)
                HStack(spacing: 16) {
                    Button { vm.householdSize = max(1, vm.householdSize - 1) } label: {
                        Image(systemName: "minus").font(.system(size: 18, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.bg))
                            .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)

                    Text("\(vm.householdSize)")
                        .font(.displayFallback(36, italic: true))
                        .frame(minWidth: 60)

                    Button { vm.householdSize = min(8, vm.householdSize + 1) } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.bg))
                            .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                }
                Text("Affects how fast Pantry assumes items get used up.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(16)
        }
    }

    private func serverCard(_ vm: SettingsViewModel) -> some View {
        sectionCard(title: "SERVER", background: Theme.sky) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL")
                    .font(.system(size: 12, weight: .semibold))
                TextField("http://localhost:8000", text: Binding(get: { vm.baseURLString }, set: { vm.baseURLString = $0 }))
                    .font(.system(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 1))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private func geminiCard(_ vm: SettingsViewModel) -> some View {
        sectionCard(title: "GEMINI", background: Theme.amber) {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.system(size: 12, weight: .semibold))
                SecureField("paste your key", text: Binding(get: { vm.geminiAPIKey }, set: { vm.geminiAPIKey = $0 }))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 1))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                PillButton(title: "Save key", variant: .solid, size: .small) {
                    vm.persistAPIKey()
                }
                .fixedSize()

                Divider().background(Theme.ink.opacity(0.2))

                Text("Model")
                    .font(.system(size: 12, weight: .semibold))
                Picker("Model", selection: Binding(get: { vm.geminiModel }, set: { vm.geminiModel = $0 })) {
                    Text("gemini-3.1-flash-lite").tag("gemini-3.1-flash-lite")
                    Text("gemini-2.0-pro").tag("gemini-2.0-pro") // TODO: remove
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func debugCard(_ vm: SettingsViewModel) -> some View {
        sectionCard(title: "DEBUG", background: Theme.lilac) {
            Toggle(isOn: Binding(get: { vm.showDebugModelIDs }, set: { vm.showDebugModelIDs = $0 })) {
                Text("Show decay model name on each item")
                    .font(.system(size: 13))
            }
            .tint(Theme.ink)
        }
    }

    private func dangerCard(_ vm: SettingsViewModel) -> some View {
        sectionCard(title: "DANGER", background: Theme.rose) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Clears every item, usage event, and scan from this device.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink2)
                PillButton(title: "Clear all inventory", variant: .solid, size: .small) {
                    showClearAlert = true
                }
                .fixedSize()
            }
        }
    }

    private func sectionCard<Content: View>(title: String, background: Color, @ViewBuilder content: @escaping () -> Content) -> some View {
        ChunkyCard(background: background, radius: Theme.cardRadius) {
            VStack(alignment: .leading, spacing: 10) {
                CaptionText(text: title, color: Theme.ink2)
                content()
            }
            .padding(16)
        }
    }
}
