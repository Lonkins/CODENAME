import SwiftUI

/// Settings surface (hosted per ADR 0005 — no SwiftUI Settings scene).
struct SettingsView: View {
  @AppStorage("integerScale") private var integerScale = true
  let licences: [(name: String, text: String)]
  var onIntegerScaleChange: (Bool) -> Void = { _ in }

  var body: some View {
    TabView {
      Form {
        Toggle("Integer scaling (sharp pixels)", isOn: $integerScale)
          .onChange(of: integerScale) { _, newValue in onIntegerScaleChange(newValue) }
        Text("Off fits the picture to the window with correct aspect ratio.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(20)
      .tabItem { Label("Display", systemImage: "display") }

      licencesTab
        .tabItem { Label("Licences", systemImage: "doc.text") }
    }
    .frame(width: 560, height: 420)
  }

  private var licencesTab: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Bundled emulator cores are separate works under their own licences.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if licences.isEmpty {
        Text("No bundled core licences found.")
          .foregroundStyle(.secondary)
      } else {
        List(licences, id: \.name) { licence in
          DisclosureGroup(licence.name) {
            ScrollView {
              Text(licence.text)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(height: 220)
          }
        }
      }
      Text("Application updates are provided by Sparkle (MIT licence).")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(12)
  }
}
