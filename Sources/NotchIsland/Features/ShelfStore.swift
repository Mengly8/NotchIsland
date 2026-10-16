import AppKit
import Combine

struct ShelfItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Files parked in the notch. Stores references (paths), not copies, and survives relaunch.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    private let defaultsKey = "NotchIsland.shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ShelfItem.init)
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop(_ items: [ShelfItem]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items.map(\.url))
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }
}
