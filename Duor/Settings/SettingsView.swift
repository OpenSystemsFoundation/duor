import SwiftUI

/// Pick the door, its hardware, and what's behind it.
struct SettingsView: View {
    @Binding var style: DoorStyle
    @Binding var hardware: HardwareFinish
    @Binding var scene: InsideScene
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Door") {
                    PickerRow(items: DoorStyle.allCases, selection: style, label: \.displayName) { door in
                        DoorLeafArt(
                            design: door.design,
                            palette: DoorLook(style: door, hardware: door.defaultHardware, scene: scene).palette)
                    } onSelect: { door in
                        style = door
                        // Each door comes with its own hardware and scene; change them below if you like.
                        hardware = door.defaultHardware
                        scene = door.defaultScene
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(HardwareFinish.allCases) { finish in
                            MetalSwatch(finish: finish, isSelected: finish == hardware) {
                                hardware = finish
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } header: {
                    Text("Hardware")
                } footer: {
                    Text("Hinges, handle and latch. Each metal sounds a little different, too.")
                }

                Section("Behind the door") {
                    PickerRow(items: InsideScene.allCases, selection: scene, label: \.displayName) { scene in
                        InsideSceneArt(scene: scene)
                    } onSelect: { newScene in
                        scene = newScene
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A horizontal row of picture tiles with captions.
private struct PickerRow<Item: Identifiable & Equatable, Art: View>: View {
    let items: [Item]
    let selection: Item
    let label: KeyPath<Item, LocalizedStringResource>
    @ViewBuilder let art: (Item) -> Art
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    let isSelected = item == selection
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(spacing: 6) {
                            art(item)
                                .frame(width: 66, height: 100)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : .secondary.opacity(0.3),
                                            lineWidth: isSelected ? 3 : 1)
                                }
                            Text(item[keyPath: label])
                                .font(.caption)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// A round sample of a metal.
private struct MetalSwatch: View {
    let finish: HardwareFinish
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                finish.color.mix(with: .white, by: 0.2 + finish.shine * 0.6), finish.color,
                                finish.color.mix(with: .black, by: 0.4),
                            ],
                            center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 30)
                    )
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3).padding(-5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Text(finish.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    SettingsView(style: .constant(.cottage), hardware: .constant(.brass), scene: .constant(.beach))
}
