import CODENAMEKit
import SwiftUI

/// The library surface: sources + games, actions injected by the delegate.
struct LibraryView: View {
  let model: LibraryModel
  let onPlay: (GameEntry) -> Void
  let onAddFolder: () -> Void
  let onOpenFile: () -> Void

  var body: some View {
    Group {
      if model.library.entries.isEmpty {
        VStack(spacing: 12) {
          Text("No games yet")
            .font(.title3)
            .foregroundStyle(.secondary)
          HStack {
            Button("Add Folder…", action: onAddFolder)
            Button("Open a Game…", action: onOpenFile)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(sortedEntries, id: \.id) { entry in
            HStack {
              VStack(alignment: .leading) {
                Text(entry.displayName)
                Text(entry.coreID)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Play") { onPlay(entry) }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPlay(entry) }
          }
        }
      }
    }
    .toolbar {
      Button("Add Folder…", action: onAddFolder)
    }
    .frame(minWidth: 420, minHeight: 300)
  }

  private var sortedEntries: [GameEntry] {
    model.library.entries.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }
}
