import SwiftUI

/// Pick the door, its hardware, what's behind it, whether a cat lives there, and whether the door
/// can be swiped. At the bottom: who made it.
struct SettingsView: View {
    @Bindable var settings: DoorSettings
    /// Without a hinge, swiping is the only way to open the door, so it can't be turned off.
    var hasHinge = true
    /// Unfolded there's room for every tile in one row; folded, at most four per row.
    var isUnfolded = false
    @Environment(\.dismiss) private var dismiss

    /// The "Swipe mode" toggle: shows the device's default until the user picks, then saves the pick.
    private var swipeMode: Binding<Bool> {
        Binding(
            get: { settings.swipeModeSetting(hasHinge: hasHinge) },
            set: { settings.savedSwipeMode = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Door") {
                    PickerGrid(
                        items: DoorStyle.allCases, selection: settings.style, label: \.displayName,
                        isUnfolded: isUnfolded
                    ) { door in
                        DoorLeafArt(
                            design: door.design,
                            palette: DoorLook(style: door, hardware: door.defaultHardware, scene: settings.scene)
                                .palette)
                    } onSelect: { door in
                        // Each door comes with its own hardware and scene; change them below if you like.
                        settings.pick(door)
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(HardwareFinish.allCases) { finish in
                            MetalSwatch(finish: finish, isSelected: finish == settings.hardware) {
                                settings.hardware = finish
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
                    PickerGrid(
                        items: InsideScene.allCases, selection: settings.scene, label: \.displayName,
                        isUnfolded: isUnfolded
                    ) { scene in
                        InsideSceneArt(scene: scene)
                    } onSelect: { scene in
                        settings.scene = scene
                    }
                }

                Section {
                    Toggle("Cat lovers", systemImage: "cat", isOn: $settings.catLovers)
                } footer: {
                    Text("A cat joins every scene behind the door, each one up to something different.")
                }

                if hasHinge {
                    Section {
                        Toggle("Swipe mode", systemImage: "hand.draw", isOn: swipeMode)
                    } footer: {
                        Text("Swipe left to open the door and right to close it, folded or unfolded.")
                    }
                }

                LanguageSection()

                MakerSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
                // On the iPhone Duo: in the vertical control lane, like the settings button.
                .axisBehavior(.verticalPreferred)
            }
        }
    }
}

/// The language Duor is shown in. iOS picks it from the device's languages; the per-app language
/// choice lives on Duor's page in the Settings app, so this opens that page instead of keeping a
/// picker of its own.
private struct LanguageSection: View {
    @Environment(\.openURL) private var openURL

    /// The language in use, named in itself ("Deutsch", "日本語").
    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).capitalized + name.dropFirst()
    }

    var body: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                LabeledContent {
                    Text(verbatim: currentLanguage)
                } label: {
                    Label("Language", systemImage: "globe")
                }
            }
        } footer: {
            Text(
                "Duor uses your device's language. To choose another language just for Duor, change it in the Settings app."
            )
        }
    }
}

/// Who made the door, for anyone curious enough to scroll all the way down: links to the maker's
/// website and a way to send a message.
private struct MakerSection: View {
    private static let website = URL(string: "https://opensf.foundation/products/duor/")!
    private static let email = URL(string: "mailto:info@opensf.foundation?subject=Duor")!

    var body: some View {
        Section {
            Link(destination: Self.website) {
                Label("Visit the workshop", systemImage: "hammer")
            }
            Link(destination: Self.email) {
                Label("Knock on the maker's door", systemImage: "envelope")
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who made this app?")
                Text("Duor is made with love by Jeff. Like the app? Come visit the workshop and say hi!")
                    .font(.footnote)
                    .fontWeight(.regular)
                    // A fixed color: `.secondary` here would dim it twice, inside the dimmed header.
                    .foregroundStyle(Color.secondary)
                    .textCase(nil)
            }
        }
    }
}

/// Picture tiles with captions, all visible at once: four per row when folded (or on a phone
/// without a hinge), every tile in one row when unfolded.
private struct PickerGrid<Item: Identifiable & Equatable, Art: View>: View {
    let items: [Item]
    let selection: Item
    let label: KeyPath<Item, LocalizedStringResource>
    let isUnfolded: Bool
    @ViewBuilder let art: (Item) -> Art
    let onSelect: (Item) -> Void

    private var columns: [GridItem] {
        let count = isUnfolded ? items.count : min(items.count, 4)
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                let isSelected = item == selection
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 6) {
                        art(item)
                            .aspectRatio(0.66, contentMode: .fit)
                            .frame(maxWidth: 80)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isSelected ? Color.primary : .secondary.opacity(0.3),
                                        lineWidth: isSelected ? 3 : 1)
                            }
                        Text(item[keyPath: label])
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
                        Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 3).padding(-5)
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
    SettingsView(settings: DoorSettings())
}
