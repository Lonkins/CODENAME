import CODENAMEKit
import SwiftUI

/// The library surface: sources + games, actions injected by the delegate.
struct LibraryView: View {
  let model: LibraryModel
  let artwork: ArtworkStore
  let onPlay: (GameEntry) -> Void
  let onAddFolder: () -> Void
  let onOpenFile: () -> Void
  let onImportArtwork: () -> Void

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
              Group {
                if let url = artwork.artworkURL(for: entry.id),
                  let image = NSImage(contentsOf: url)
                {
                  Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                } else {
                  Image(systemName: "gamecontroller")
                    .foregroundStyle(.tertiary)
                }
              }
              .frame(width: 44, height: 44)
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
    .id(model.artworkRevision)  // re-read artwork files after an import
    .toolbar {
      Button("Add Folder…", action: onAddFolder)
      Button("Import Artwork…", action: onImportArtwork)
    }
    .frame(minWidth: 420, minHeight: 300)
  }

  private var sortedEntries: [GameEntry] {
    model.library.entries.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }
}
