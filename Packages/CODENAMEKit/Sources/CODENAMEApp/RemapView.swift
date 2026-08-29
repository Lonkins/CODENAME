import CODENAMEKit
import SwiftUI

/// Picker-based controller remapping per core (press-to-bind capture needs
/// real HID events and comes later). Saves to the per-core mapping file the
/// session loader already reads.
struct RemapView: View {
  let coreNames: [String]
  let load: (String) -> ButtonMapping
  let save: (String, ButtonMapping) -> Void

  @State private var selectedCore: String = ""
  @State private var mapping = ButtonMapping.defaultMapping

  private static let padControls = [
    "buttonA", "buttonB", "buttonX", "buttonY",
    "dpadUp", "dpadDown", "dpadLeft", "dpadRight",
    "leftShoulder", "rightShoulder", "leftTrigger", "rightTrigger",
    "menu", "options",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Core", selection: $selectedCore) {
        ForEach(coreNames, id: \.self) { Text($0) }
      }
      .onChange(of: selectedCore) { _, core in
        mapping = load(core)
      }

      let conflicts = mapping.conflicts()
      if !conflicts.isEmpty {
        let names = conflicts.keys.map(\.rawValue).sorted().joined(separator: ", ")
        Label("Conflicting assignments: \(names)", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      }

      Form {
        ForEach(Self.padControls, id: \.self) { control in
          Picker(control, selection: binding(for: control)) {
            ForEach(RetroPadButton.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
        }
      }
      .formStyle(.grouped)

      HStack {
        Button("Reset to Defaults") {
          mapping = .defaultMapping
          save(selectedCore, mapping)
        }
        Spacer()
      }
    }
    .padding(16)
    .frame(width: 420, height: 560)
    .onAppear {
      if selectedCore.isEmpty, let first = coreNames.first {
        selectedCore = first
        mapping = load(first)
      }
    }
  }

  private func binding(for control: String) -> Binding<RetroPadButton> {
    Binding(
      get: { mapping.pad[control] ?? .b },
      set: { newValue in
        mapping.pad[control] = newValue
        save(selectedCore, mapping)
      })
  }
}
