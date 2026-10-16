import AppKit
import SwiftUI

/// Drop files on the notch to park them; drag them back out anywhere, or AirDrop them.
struct ShelfTab: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var shelf: ShelfStore

    init(model: NotchViewModel) {
        self.model = model
        shelf = model.shelf
    }

    var body: some View {
        HStack(spacing: 12) {
            if shelf.items.isEmpty {
                dropZone
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()

                VStack(spacing: 8) {
                    actionButton("AirDrop All", systemImage: "airplayaudio") { shelf.airDrop(shelf.items) }
                    actionButton("Clear", systemImage: "trash") { shelf.clear() }
                }
                .frame(width: 120)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .light))
            Text("Drop files here")
                .font(.system(size: 13, weight: .semibold))
            Text("Park them in the notch, then drag them out anywhere")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.white.opacity(0.25))
        )
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 76)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("AirDrop") { shelf.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
