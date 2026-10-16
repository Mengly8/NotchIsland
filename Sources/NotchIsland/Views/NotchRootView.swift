import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Top-level view inside the panel. The black island morphs between three states:
/// closed (exactly the notch), peek (notch + two "ears" with live info), open (full panel).
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let state = model.displayState
        let size = model.visibleSize
        let radii = model.radii
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)

                content(for: state)
                    .padding(.horizontal, radii.top)
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(alignment: .top) {
                if model.isDropTargeted {
                    shape.stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(state == .open ? 0.45 : 0), radius: 18, y: 8)
            // Closed = invisible. The real notch is already black, so drawing anything
            // here can only show up as stray bars if the size is even slightly off.
            .opacity(state == .closed ? 0 : 1)
            .contentShape(shape)
            .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
                model.handleDrop(providers)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(spring, value: state)
        .animation(spring, value: size)
        .animation(spring, value: model.tab)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(for state: NotchViewModel.DisplayState) -> some View {
        switch state {
        case .closed:
            Color.clear
        case .peek:
            PeekView(model: model)
                .transition(.opacity)
        case .open:
            ExpandedView(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        }
    }
}
