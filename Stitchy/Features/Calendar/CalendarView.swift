// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CalendarView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if calendar.access != .granted || !settings.calendarEnabled {
            connect
        } else if calendar.events.isEmpty {
            EmptyState(symbol: "calendar.badge.checkmark", tint: .red, title: "All clear",
                       message: "Nothing else today or tomorrow.")
                .onAppear { calendar.refresh() }
        } else {
            HStack(alignment: .top, spacing: DS.Space.m) {
                if let next = calendar.nextTimed {
                    countdown(next).frame(width: 156, alignment: .leading).well(padding: 12)
                }
                IslandScroll(axis: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        let today = calendar.events.filter { Calendar.current.isDateInToday($0.start) }
                        let later = calendar.events.filter { !Calendar.current.isDateInToday($0.start) }
                        if !today.isEmpty {
                            SectionLabel("Today")
                            ForEach(today) { EventRow(event: $0) }
                        }
                        if !later.isEmpty {
                            SectionLabel("Tomorrow").padding(.top, today.isEmpty ? 0 : 4)
                            ForEach(later) { EventRow(event: $0) }
                        }
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
                    .font(DS.label).tracking(0.8).foregroundStyle(event.color)
                Text(event.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(event.start <= context.date
                     ? "Ends \(event.end.formatted(date: .omitted, time: .shortened))"
                     : "in " + Self.until(event.start, from: context.date))
                    .font(DS.numerals(22))
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
        Group {
            if calendar.access == .denied {
                EmptyState(symbol: "calendar", tint: .red, title: "Calendar access is off",
                           message: "Allow Stitchy in Privacy & Security › Calendars to see today's schedule.",
                           actionTitle: "Open Privacy Settings") { SystemSettingsLink.open(SystemSettingsLink.calendars) }
            } else {
                EmptyState(symbol: "calendar", tint: .red, title: "Today's schedule",
                           message: "Upcoming events and a reminder before meetings. Events are read on this Mac only.",
                           actionTitle: "Connect Calendar") { Task { await calendar.requestAccess() } }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarService.Event

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(event.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(DS.body.weight(.semibold)).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(DS.caption).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
