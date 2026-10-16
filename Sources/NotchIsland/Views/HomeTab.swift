import AppKit
import SwiftUI

/// Now playing on the left, live activities (timer + power) on the right.
struct HomeTab: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        HStack(spacing: 12) {
            NowPlayingCard(media: model.media)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()

            VStack(spacing: 8) {
                TimerCard(timer: model.timer)
                PowerCard(battery: model.battery)
            }
            .frame(width: 180)
        }
    }
}

// MARK: - Now playing

struct NowPlayingCard: View {
    @ObservedObject var media: MediaController

    var body: some View {
        if let track = media.track {
            HStack(spacing: 14) {
                ArtworkView(image: media.artwork, size: 96, corner: 14)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .onTapGesture { media.openPlayer() }

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)

                    ProgressRow(media: media, duration: track.duration)

                    HStack(spacing: 22) {
                        controlButton("backward.fill", size: 14) { media.previous() }
                        controlButton(media.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.playPause() }
                        controlButton("forward.fill", size: 14) { media.next() }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: track.source.symbol)
                            Text(track.source.displayName)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Nothing playing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                if let hint = media.setupHint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                } else {
                    Button("Open Music") { media.openPlayer() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct ProgressRow: View {
    @ObservedObject var media: MediaController
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let position = media.position(at: ctx.date)
            HStack(spacing: 6) {
                Text(Self.format(position))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white)
                            .frame(width: duration > 0 ? geo.size.width * position / duration : 0)
                    }
                }
                .frame(height: 4)
                Text(Self.format(duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Live activities

struct TimerCard: View {
    @ObservedObject var timer: TimerActivity

    var body: some View {
        Group {
            if timer.isRunning {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Color.orange.opacity(0.25), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: 1 - timer.progress(at: ctx.date))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 30, height: 30)

                        Text(TimerActivity.format(timer.remaining(at: ctx.date)))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)

                        Spacer(minLength: 0)

                        Button { timer.cancel() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Timer", systemImage: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 5) {
                        ForEach([1, 5, 15, 25], id: \.self) { minutes in
                            Button("\(minutes)m") { timer.start(minutes: Double(minutes)) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 22)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card()
    }
}

struct PowerCard: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: battery.hasBattery ? battery.symbolName : "powerplug.fill")
                .font(.system(size: 20))
                .foregroundStyle(battery.isCharging ? Color.green : (battery.level <= 20 && battery.hasBattery ? Color.red : Color.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(battery.hasBattery ? "\(battery.level)%" : "Power adapter")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card()
    }

    private var statusText: String {
        guard battery.hasBattery else { return "No battery" }
        if battery.isCharging { return "Charging" }
        return battery.isPluggedIn ? "Plugged in" : "On battery"
    }
}
