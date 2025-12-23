import Foundation
import EventKit
import SwiftUI

// MARK: - Auto Walk Manager

/// Manages automatic daily walk scheduling based on next day's calendar
class AutoWalkManager: ObservableObject {
    static let shared = AutoWalkManager()

    private let eventStore = EKEventStore()

    @Published var lastScheduledDate: Date?
    @Published var lastScheduledWalkTime: Date?
    @Published var isScheduling = false
    @Published var lastError: String?

    // Track auto-scheduled walks to avoid duplicates
    @AppStorage("autoWalkLastScheduledDateString") private var lastScheduledDateString: String = ""
    @AppStorage("autoWalkEventID") private var autoWalkEventID: String = ""

    private init() {}

    // MARK: - Main Scheduling Logic

    /// Schedule auto walk for tomorrow based on calendar events
    /// Called from evening briefing time or app lifecycle
    func scheduleAutoWalkForTomorrow() async {
        let prefs = UserPreferences.shared
        guard prefs.autoWalkEnabled else { return }

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowDateString = formatDateString(tomorrow)

        // Check if we already scheduled for tomorrow
        if lastScheduledDateString == tomorrowDateString {
            return
        }

        await MainActor.run { isScheduling = true }
        defer { Task { await MainActor.run { isScheduling = false } } }

        do {
            // Fetch tomorrow's events
            let calendarManager = CalendarManager.shared
            let events = try await calendarManager.fetchEvents(for: tomorrow)

            // Filter to real meetings only (exclude OOO, all-day events)
            let realMeetings = events.filter { $0.isRealMeeting }

            // Find the best walk slot
            guard let walkSlot = findBestWalkSlot(
                for: tomorrow,
                events: realMeetings,
                duration: prefs.autoWalkDuration,
                preferredTime: prefs.autoWalkPreferredTime
            ) else {
                await MainActor.run {
                    lastError = "No suitable time slot found for tomorrow"
                }
                return
            }

            // Remove previous auto-scheduled walk if exists
            await removePreviousAutoWalk()

            // Create the walk in ScheduledActivityManager
            let activity = ScheduledActivity(
                activityType: .walk,
                workoutType: nil,
                title: "Daily Walk",
                startTime: walkSlot.start,
                duration: prefs.autoWalkDuration,
                recurrence: .once
            )
            ScheduledActivityManager.shared.addScheduledActivity(activity)

            // Sync to calendar if enabled
            if prefs.autoWalkSyncToCalendar {
                let eventID = try await createCalendarEvent(
                    title: "Daily Walk",
                    startTime: walkSlot.start,
                    duration: prefs.autoWalkDuration,
                    calendarID: prefs.autoWalkCalendarID
                )
                await MainActor.run {
                    autoWalkEventID = eventID ?? ""
                }
            }

            // Update tracking
            await MainActor.run {
                lastScheduledDateString = tomorrowDateString
                lastScheduledDate = tomorrow
                lastScheduledWalkTime = walkSlot.start
                lastError = nil
            }

        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Find Best Walk Slot

    /// Find the best time slot for a walk based on preference and meetings
    private func findBestWalkSlot(
        for date: Date,
        events: [CalendarEvent],
        duration: Int,
        preferredTime: PreferredWalkTime
    ) -> DateInterval? {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        // Define time windows based on preference
        let (preferredStart, preferredEnd) = getTimeWindow(for: preferredTime, on: date)

        // Get all free slots for the day
        let freeSlots = findFreeSlots(for: date, events: events, minimumDuration: duration)

        // Priority 1: Find slot in preferred time window
        if let slot = freeSlots.first(where: { slot in
            slot.start >= preferredStart &&
            slot.end <= preferredEnd &&
            slot.duration >= Double(duration * 60) &&
            !prefs.isDuringMeal(slot.start)
        }) {
            return DateInterval(
                start: slot.start,
                end: calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
            )
        }

        // Priority 2: Find any slot that works, preferring earlier times
        let sortedSlots = freeSlots.sorted { $0.start < $1.start }
        for slot in sortedSlots {
            if slot.duration >= Double(duration * 60) && !prefs.isDuringMeal(slot.start) {
                return DateInterval(
                    start: slot.start,
                    end: calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
                )
            }
        }

        return nil
    }

    /// Get time window based on preference
    private func getTimeWindow(for preference: PreferredWalkTime, on date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)

        switch preference {
        case .morning:
            startComponents.hour = 6
            startComponents.minute = 0
            endComponents.hour = 11
            endComponents.minute = 0

        case .afternoon:
            startComponents.hour = 12
            startComponents.minute = 0
            endComponents.hour = 17
            endComponents.minute = 0

        case .evening:
            startComponents.hour = 17
            startComponents.minute = 0
            endComponents.hour = 21
            endComponents.minute = 0

        case .noPreference:
            // Full day window
            startComponents.hour = 7
            startComponents.minute = 0
            endComponents.hour = 21
            endComponents.minute = 0
        }

        let start = calendar.date(from: startComponents) ?? date
        let end = calendar.date(from: endComponents) ?? date

        return (start, end)
    }

    /// Find free slots in the day avoiding meetings
    private func findFreeSlots(for date: Date, events: [CalendarEvent], minimumDuration: Int) -> [DateInterval] {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        // Start from wake time
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = prefs.wakeTime.hour
        startComponents.minute = prefs.wakeTime.minute
        let dayStart = calendar.date(from: startComponents) ?? date

        // End at sleep time
        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)
        endComponents.hour = min(prefs.sleepTime.hour, 22) // Cap at 10 PM
        endComponents.minute = 0
        let dayEnd = calendar.date(from: endComponents) ?? date

        // Sort events by start time
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }

        var freeSlots: [DateInterval] = []
        var currentTime = dayStart

        for event in sortedEvents {
            // Skip events outside our window
            if event.endDate <= dayStart || event.startDate >= dayEnd {
                continue
            }

            let eventStart = max(event.startDate, dayStart)
            let eventEnd = min(event.endDate, dayEnd)

            if eventStart > currentTime {
                let gap = DateInterval(start: currentTime, end: eventStart)
                let gapMinutes = Int(gap.duration / 60)
                if gapMinutes >= minimumDuration {
                    freeSlots.append(gap)
                }
            }

            if eventEnd > currentTime {
                currentTime = eventEnd
            }
        }

        // Check for free time after last event
        if currentTime < dayEnd {
            let gap = DateInterval(start: currentTime, end: dayEnd)
            let gapMinutes = Int(gap.duration / 60)
            if gapMinutes >= minimumDuration {
                freeSlots.append(gap)
            }
        }

        return freeSlots
    }

    // MARK: - Calendar Integration

    /// Create a calendar event for the walk
    private func createCalendarEvent(
        title: String,
        startTime: Date,
        duration: Int,
        calendarID: String
    ) async throws -> String? {
        guard !calendarID.isEmpty else { return nil }

        let calendars = eventStore.calendars(for: .event)
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID }) else {
            throw AutoWalkError.calendarNotFound
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startTime
        event.endDate = Calendar.current.date(byAdding: .minute, value: duration, to: startTime)
        event.notes = "🚶 Auto-scheduled by Activslot\n\nThis walk was automatically scheduled based on your calendar for tomorrow.\n\n---\nCreated by Activslot"

        // Add reminder 10 minutes before
        let alarm = EKAlarm(relativeOffset: TimeInterval(-10 * 60))
        event.addAlarm(alarm)

        try eventStore.save(event, span: .thisEvent)

        return event.eventIdentifier
    }

    /// Remove previously auto-scheduled walk event
    private func removePreviousAutoWalk() async {
        guard !autoWalkEventID.isEmpty else { return }

        if let event = eventStore.event(withIdentifier: autoWalkEventID) {
            try? eventStore.remove(event, span: .thisEvent)
        }

        await MainActor.run {
            autoWalkEventID = ""
        }
    }

    // MARK: - Helpers

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Get formatted time for the last scheduled walk
    var lastScheduledWalkTimeFormatted: String? {
        guard let time = lastScheduledWalkTime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    /// Get day name for last scheduled date
    var lastScheduledDayName: String? {
        guard let date = lastScheduledDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: - Manual Trigger

    /// Force schedule for tomorrow (useful for testing or manual trigger)
    func forceScheduleForTomorrow() async {
        // Clear last scheduled date to force reschedule
        await MainActor.run {
            lastScheduledDateString = ""
        }
        await scheduleAutoWalkForTomorrow()
    }

    // MARK: - Error Types

    enum AutoWalkError: Error, LocalizedError {
        case calendarNotFound
        case noFreeSlot
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .calendarNotFound:
                return "Selected calendar not found"
            case .noFreeSlot:
                return "No suitable time slot found"
            case .notAuthorized:
                return "Calendar access not authorized"
            }
        }
    }
}

