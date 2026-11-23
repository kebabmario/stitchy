import SwiftUI

struct CalendarView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if calendar.access != .granted || !settings.calendarEnabled {
            connect
        } else if calendar.events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 22)).foregroundStyle(Color.secondaryText)
                Text("Nothing else today or tomorrow").font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 18) {
                if let next = calendar.nextTimed { countdown(next).frame(width: 150, alignment: .leading) }
                IslandScroll(axis: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendar.events) { EventRow(event: $0) }
                    }
                }
            }
            .onAppear { calendar.refresh() }
        }
    }

    private func countdown(_ event: CalendarService.Event) -> some View {
        TimelineView(.periodic(from: .timelineAnchor, by: 30)) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text(event.start <= context.date ? "NOW" : "NEXT")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(event.color)
                Text(event.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(event.start <= context.date
                     ? "Ends \(event.end.formatted(date: .omitted, time: .shortened))"
                     : "in " + Self.until(event.start, from: context.date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin").font(.system(size: 10)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
            }
        }
    }

    static func until(_ date: Date, from now: Date) -> String {
        let m = max(0, Int(date.timeIntervalSince(now) / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    private var connect: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 22, weight: .medium)).foregroundStyle(Color.secondaryText)
            Text("Today's Schedule").font(.system(size: 13, weight: .semibold))
            if calendar.access == .denied {
                Text("Calendar access was denied.").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                PillButton(title: "Open Privacy Settings") { SystemSettingsLink.open(SystemSettingsLink.calendars) }
            } else {
                Text("Show upcoming events and get a reminder before meetings. Events are read on this Mac only.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 320)
                PillButton(title: "Connect Calendar", tint: .white, prominent: true) { Task { await calendar.requestAccess() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarService.Event

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(event.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
            if !Calendar.current.isDateInToday(event.start) {
                Text("Tomorrow").font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.tertiaryText)
            }
        }
    }
}
