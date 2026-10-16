import AppKit
import SwiftUI

/// The widened-notch state: a little info on each side of the camera cut-out.
struct PeekView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject private var media: MediaController
    @ObservedObject private var timer: TimerActivity
    @ObservedObject private var battery: BatteryMonitor

    init(model: NotchViewModel) {
        self.model = model
        media = model.media
        timer = model.timer
        battery = model.battery
    }

    private enum Kind { case transient(TransientActivity), timer, media, none }

    private var kind: Kind {
        if let t = model.transient { return .transient(t) }
        if timer.isRunning { return .timer }
        if model.mediaIsLive { return .media }
        return .none
    }

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: NotchViewModel.wing - 12, alignment: .leading)
            Spacer(minLength: model.notchSize.width)
            right.frame(width: NotchViewModel.wing - 12, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: model.notchSize.height)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    @ViewBuilder private var left: some View {
        switch kind {
        case .transient(let t):
            Image(systemName: Self.icon(for: t, battery: battery))
                .foregroundStyle(Self.tint(for: t))
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange)
        case .media:
            ArtworkView(image: media.artwork, size: 22, corner: 6)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var right: some View {
        switch kind {
        case .transient(let t):
            Text(Self.label(for: t)).foregroundStyle(Self.tint(for: t))
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(TimerActivity.format(timer.remaining(at: ctx.date)))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        case .media:
            WaveformView(isPlaying: media.isPlaying)
                .frame(width: 22, height: 14)
        case .none:
            EmptyView()
        }
    }

    static func icon(for t: TransientActivity, battery: BatteryMonitor) -> String {
        switch t {
        case .charging: return "bolt.fill"
        case .onBattery: return battery.symbolName
        case .lowBattery: return "battery.25"
        case .timerDone: return "timer"
        case .shelfAdded: return "tray.and.arrow.down.fill"
        case .upcomingEvent: return "calendar"
        }
    }

    static func label(for t: TransientActivity) -> String {
        switch t {
        case .charging(let l), .onBattery(let l), .lowBattery(let l): return "\(l)%"
        case .timerDone: return "Done"
        case .shelfAdded(let n): return "+\(n)"
        case .upcomingEvent(_, let m): return "in \(m)m"
        }
    }

    static func tint(for t: TransientActivity) -> Color {
        switch t {
        case .charging: return .green
        case .onBattery: return .white
        case .lowBattery: return .red
        case .timerDone: return .orange
        case .shelfAdded: return .blue
        case .upcomingEvent: return .pink
        }
    }
}

/// Animated equalizer bars.
struct WaveformView: View {
    var isPlaying: Bool
    var color: Color = .green

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (3.2 + Double(i) * 0.9) + Double(i) * 1.3
                    let h = isPlaying ? 0.3 + 0.7 * abs(sin(phase)) : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: 3)
                        .scaleEffect(x: 1, y: h, anchor: .center)
                }
            }
        }
    }
}

/// Album art with a fallback glyph.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
