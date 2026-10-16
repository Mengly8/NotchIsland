import AppKit
import SwiftUI
import Combine

/// Measures the physical notch on the built-in display (or fakes one on other screens).
struct NotchGeometry {
    let notchSize: CGSize
    let hasNotch: Bool

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0 {
            // The gap between the two usable menu-bar areas is the notch.
            var width: CGFloat = 185
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let gap = right.minX - left.maxX
                let fallback = screen.frame.width - left.width - right.width
                width = (120...300).contains(gap) ? gap : fallback
            }
            // Never trust an obviously wrong value — a too-wide notch shows up as black bars.
            if !(120...300).contains(width) { width = 185 }
            notchSize = CGSize(width: width, height: top)
            hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: max(menuBar, 24))
            hasNotch = false
        }
        NSLog("NotchIsland: screen %@ — notch %.0f×%.0f (physical: %@), left %@, right %@",
              NSStringFromRect(screen.frame), notchSize.width, notchSize.height, hasNotch ? "yes" : "no",
              screen.auxiliaryTopLeftArea.map(NSStringFromRect) ?? "nil",
              screen.auxiliaryTopRightArea.map(NSStringFromRect) ?? "nil")
    }

    /// Prefer the screen that actually has a notch, fall back to the main screen.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}

/// Borderless, transparent, always-on-top panel that sits over the notch.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the panel and turns raw mouse movement into open / close decisions.
///
/// The panel is much bigger than the island, so it ignores mouse events
/// everywhere except over the island itself — clicks elsewhere fall through
/// to whatever is underneath.
@MainActor
final class NotchWindowController {
    static let canvas = CGSize(width: 760, height: 320)

    private let model: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var sticky = false                 // opened from the menu bar; closes on outside click
    private var dragPasteboardCount = 0         // to detect real file drags
    private var cancellables = Set<AnyCancellable>()

    init(model: NotchViewModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))

        let hosting = NSHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = hosting

        installMonitors()

        // Whenever the island changes size, re-check whether the cursor is over it.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateMouse() }
            .store(in: &cancellables)
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func reposition() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        model.applyGeometry(geometry)

        let f = screen.frame
        let frame = NSRect(
            x: f.midX - Self.canvas.width / 2,
            y: f.maxY - Self.canvas.height,
            width: Self.canvas.width,
            height: Self.canvas.height
        )
        panel.setFrame(frame, display: true)
    }

    func openSticky() {
        sticky = true
        model.open(tab: model.tab)
        panel.ignoresMouseEvents = false
    }

    // MARK: - Mouse tracking

    private func installMonitors() {
        let tracked: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: tracked, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isLocal: false) }
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: tracked, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isLocal: true) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent, isLocal: Bool) {
        switch event.type {
        case .leftMouseDown:
            dragPasteboardCount = NSPasteboard(name: .drag).changeCount
            // Click outside a menu-opened island closes it.
            if sticky, !isLocal, !hotRect().contains(NSEvent.mouseLocation) {
                sticky = false
                model.close()
            }
        default:
            break
        }
        evaluateMouse()
    }

    /// Island rectangle in screen coordinates, with a little forgiveness.
    private func hotRect() -> NSRect {
        guard let screen = panel.screen ?? NotchGeometry.targetScreen() else { return .zero }
        let size = model.visibleSize
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -6, dy: -6)
    }

    private func evaluateMouse() {
        let inside = hotRect().contains(NSEvent.mouseLocation)
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let fileDrag = buttonDown && NSPasteboard(name: .drag).changeCount != dragPasteboardCount

        panel.ignoresMouseEvents = !(inside || sticky)

        if inside {
            closeWork?.cancel()
            closeWork = nil
            guard model.status != .open, openWork == nil else { return }
            // A plain click-drag (e.g. moving a window) shouldn't pop the island open.
            if buttonDown && !fileDrag { return }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                self.model.open(tab: fileDrag ? .shelf : self.model.tab)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (fileDrag ? 0 : 0.12), execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
            // Don't collapse while the user is dragging something out of the shelf
            // or while a menu-opened island is pinned.
            guard model.status == .open, !sticky, !buttonDown, closeWork == nil else { return }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                self.model.close()
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}
