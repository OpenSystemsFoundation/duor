import SwiftUI

/// Pick the door style. The MVP has one; more styles appear here as they are added.
struct SettingsView: View {
    @Binding var style: DoorStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Door") {
                    Picker("Style", selection: $style) {
                        ForEach(DoorStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView(style: .constant(.oakWithIronHinges))
}
