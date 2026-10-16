import AppKit
import SwiftUI
import EventKit

/// A week strip on the left, the selected day's events on the right.
struct CalendarTab: View {
    @ObservedObject var calendar: CalendarStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(calendar.selectedDate.formatted(.dateTime.month(.wide)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(calendar.selectedDate.formatted(.dateTime.weekday(.wide).day()))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }

                HStack(spacing: 2) {
                    ForEach(calendar.days, id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
            .frame(width: 230, alignment: .leading)
            .frame(maxHeight: .infinity)
            .card()

            Group {
                if calendar.authorized {
                    eventList
                } else {
                    accessPrompt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = calendar.isSelected(day)
        return Button { calendar.select(day) } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(selected ? Color.red : .clear))
                Circle()
                    .fill(calendar.isToday(day) ? Color.red : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var eventList: some View {
        if calendar.events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.35))
                Text("No events")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(calendar.events.enumerated()), id: \.offset) { _, event in
                        EventRow(event: event)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accessPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.5))
            if calendar.denied {
                Text("Calendar access is off")
                    .font(.system(size: 12, weight: .medium))
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            } else {
                Text("See your events in the notch")
                    .font(.system(size: 12, weight: .medium))
                Button("Allow Calendar Access") { calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }
}

struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar?.color ?? .systemBlue))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .opacity(event.endDate < Date() ? 0.45 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
