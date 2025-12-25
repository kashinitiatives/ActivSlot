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

            // Filter to real meetings only (exclude OOO, all-day events, long meetings)
            let realMeetings = events.filter { $0.isRealMeeting }

            // Get existing scheduled activities for tomorrow (gym workouts, etc.)
            let scheduledActivityManager = ScheduledActivityManager.shared
            let existingActivities = scheduledActivityManager.activities(for: tomorrow)

            // Find the best walk slot, avoiding both calendar events and scheduled activities
            guard let walkSlot = findBestWalkSlot(
                for: tomorrow,
                events: realMeetings,
                scheduledActivities: existingActivities,
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
        scheduledActivities: [ScheduledActivity],
        duration: Int,
        preferredTime: PreferredWalkTime
    ) -> DateInterval? {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        // Define time windows based on preference
        let (preferredStart, preferredEnd) = getTimeWindow(for: preferredTime, on: date)

        // Get all free slots for the day (considers both calendar events and scheduled activities)
        let freeSlots = findFreeSlots(
            for: date,
            events: events,
            scheduledActivities: scheduledActivities,
            minimumDuration: duration
        )

        // Priority 1: Find slot in preferred time window
        let slotsInPreferredWindow = freeSlots.filter { slot in
            slot.start >= preferredStart &&
            slot.start < preferredEnd &&
            slot.duration >= Double(duration * 60) &&
            !prefs.isDuringMeal(slot.start)
        }

        if let slot = slotsInPreferredWindow.first {
            return DateInterval(
                start: slot.start,
                end: calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
            )
        }

        // Priority 2: Find slot in adjacent time windows based on preference
        // For evening preference, try afternoon; for morning, try midday
        let (fallbackStart, fallbackEnd) = getFallbackTimeWindow(for: preferredTime, on: date)
        let slotsInFallbackWindow = freeSlots.filter { slot in
            slot.start >= fallbackStart &&
            slot.start < fallbackEnd &&
            slot.duration >= Double(duration * 60) &&
            !prefs.isDuringMeal(slot.start)
        }

        if let slot = slotsInFallbackWindow.first {
            return DateInterval(
                start: slot.start,
                end: calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
            )
        }

        // Priority 3: Only if no preference set, use any available slot
        if preferredTime == .noPreference {
            let sortedSlots = freeSlots.sorted { $0.start < $1.start }
            for slot in sortedSlots {
                if slot.duration >= Double(duration * 60) && !prefs.isDuringMeal(slot.start) {
                    return DateInterval(
                        start: slot.start,
                        end: calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
                    )
                }
            }
        }

        return nil
    }

    /// Get fallback time window based on preference
    private func getFallbackTimeWindow(for preference: PreferredWalkTime, on date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)

        switch preference {
        case .morning:
            // Fallback to late morning / early afternoon
            startComponents.hour = 11
            startComponents.minute = 0
            endComponents.hour = 14
            endComponents.minute = 0

        case .afternoon:
            // Fallback to late afternoon / early evening
            startComponents.hour = 16
            startComponents.minute = 0
            endComponents.hour = 19
            endComponents.minute = 0

        case .evening:
            // Fallback to late afternoon
            startComponents.hour = 15
            startComponents.minute = 0
            endComponents.hour = 18
            endComponents.minute = 0

        case .noPreference:
            // No fallback needed
            startComponents.hour = 0
            startComponents.minute = 0
            endComponents.hour = 0
            endComponents.minute = 0
        }

        let start = calendar.date(from: startComponents) ?? date
        let end = calendar.date(from: endComponents) ?? date

        return (start, end)
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

    /// Find free slots in the day avoiding meetings and scheduled activities
    private func findFreeSlots(
        for date: Date,
        events: [CalendarEvent],
        scheduledActivities: [ScheduledActivity],
        minimumDuration: Int
    ) -> [DateInterval] {
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

        // Combine calendar events and scheduled activities into busy intervals
        var busyIntervals: [(start: Date, end: Date)] = []

        // Add calendar events
        for event in events {
            busyIntervals.append((start: event.startDate, end: event.endDate))
        }

        // Add scheduled activities (gym workouts, walks, etc.)
        for activity in scheduledActivities {
            if let timeRange = activity.getTimeRange(for: date) {
                busyIntervals.append((start: timeRange.start, end: timeRange.end))
            }
        }

        // Sort by start time
        busyIntervals.sort { $0.start < $1.start }

        var freeSlots: [DateInterval] = []
        var currentTime = dayStart

        for interval in busyIntervals {
            // Skip intervals outside our window
            if interval.end <= dayStart || interval.start >= dayEnd {
                continue
            }

            let intervalStart = max(interval.start, dayStart)
            let intervalEnd = min(interval.end, dayEnd)

            if intervalStart > currentTime {
                let gap = DateInterval(start: currentTime, end: intervalStart)
                let gapMinutes = Int(gap.duration / 60)
                if gapMinutes >= minimumDuration {
                    freeSlots.append(gap)
                }
            }

            if intervalEnd > currentTime {
                currentTime = intervalEnd
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

