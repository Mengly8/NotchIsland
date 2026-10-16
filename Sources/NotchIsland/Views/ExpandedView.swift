import AppKit
import SwiftUI

/// The fully opened island: a header that wraps around the notch, then the selected tab.
struct ExpandedView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            header
                .frame(height: model.notchSize.height)

            Group {
                switch model.tab {
                case .home: HomeTab(model: model)
                case .shelf: ShelfTab(model: model)
                case .calendar: CalendarTab(calendar: model.calendar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            .id(model.tab)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(NotchViewModel.Tab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .background(
                            Capsule().fill(model.tab == tab ? Color.white.opacity(0.18) : .clear)
                        )
                        .foregroundStyle(model.tab == tab ? Color.white : Color.white.opacity(0.55))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }

            Spacer(minLength: model.notchSize.width + 12)   // keep clear of the camera

            BatteryBadge(battery: model.battery)

            Menu {
                Button(LaunchAtLogin.isEnabled ? "Disable Launch at Login" : "Launch at Login") {
                    LaunchAtLogin.toggle()
                }
                Divider()
                Button("Quit Notch Island") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

struct BatteryBadge: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 4) {
                Text("\(battery.level)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Image(systemName: battery.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(battery.isCharging ? Color.green : (battery.level <= 20 ? Color.red : Color.white))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// Shared card background for the tabs.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
