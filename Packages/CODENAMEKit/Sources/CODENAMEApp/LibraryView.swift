import CODENAMEKit
import SwiftUI

/// The library surface: cover grid with search, actions injected by the
/// delegate. Thumbnails decode off the main thread and cache per entry —
/// a grid of synchronous NSImage(contentsOf:) reads janks on first paint.
struct LibraryView: View {
  let model: LibraryModel
  let artwork: ArtworkStore
  let onPlay: (GameEntry) -> Void
  let onAddFolder: () -> Void
  let onOpenFile: () -> Void
  let onImportArtwork: () -> Void

  @State private var searchText = ""

  private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]

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
        ScrollView {
          LazyVGrid(columns: columns, spacing: 16) {
            ForEach(visibleEntries, id: \.id) { entry in
              GameCell(
                entry: entry, artworkURL: artwork.artworkURL(for: entry.id),
                revision: model.artworkRevision
              ) {
                onPlay(entry)
              }
            }
          }
          .padding(16)
        }
        .overlay {
          if visibleEntries.isEmpty {
            Text("No matches for “\(searchText)”")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .toolbar {
      TextField("Search", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
      Button("Add Folder…", action: onAddFolder)
      Button("Import Artwork…", action: onImportArtwork)
    }
    .frame(minWidth: 480, minHeight: 340)
  }

  private var visibleEntries: [GameEntry] {
    let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
    return model.library.entries
      .filter {
        query.isEmpty || $0.displayName.lowercased().contains(query)
          || $0.coreID.lowercased().contains(query)
      }
      .sorted {
        TitleNormalizer.normalize(filename: $0.displayName).sortKey
          < TitleNormalizer.normalize(filename: $1.displayName).sortKey
      }
  }
}

/// One cover tile. The image loads in a task keyed by URL+revision so an
/// artwork import refreshes exactly the cells that changed.
private struct GameCell: View {
  let entry: GameEntry
  let artworkURL: URL?
  let revision: Int
  let onPlay: () -> Void

  @State private var image: NSImage?

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(.quaternary)
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          Image(systemName: "gamecontroller")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
        }
      }
      .frame(height: 150)
      Text(entry.displayName)
        .font(.callout)
        .lineLimit(2, reservesSpace: true)
        .multilineTextAlignment(.center)
      Text(entry.coreID)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2, perform: onPlay)
    .contextMenu {
      Button("Play", action: onPlay)
    }
    .task(id: TaskKey(url: artworkURL, revision: revision)) {
      guard let artworkURL else {
        image = nil
        return
      }
      // Decode bytes off-main; NSImage itself is not Sendable.
      let data = await Task.detached(priority: .utility) {
        try? Data(contentsOf: artworkURL)
      }.value
      image = data.flatMap(NSImage.init(data:))
    }
  }

  private struct TaskKey: Equatable {
    let url: URL?
    let revision: Int
  }
}
