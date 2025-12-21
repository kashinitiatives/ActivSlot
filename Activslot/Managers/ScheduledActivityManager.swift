import Foundation
import SwiftUI

// MARK: - Recurrence Rule

enum RecurrenceRule: String, CaseIterable, Codable {
    case once = "Just This Day"
    case weekly = "Every Week"
    case weekdays = "Weekdays"
    case biweekly = "Every 2 Weeks"
    case monthly = "Every Month"

    var description: String {
        switch self {
        case .once: return "One-time only"
        case .weekly: return "Same day every week"
        case .weekdays: return "Monday to Friday"
        case .biweekly: return "Every other week"
        case .monthly: return "Same day each month"
        }
    }

    var icon: String {
        switch self {
        case .once: return "1.circle"
        case .weekly: return "repeat"
        case .weekdays: return "calendar.badge.clock"
        case .biweekly: return "2.circle"
        case .monthly: return "calendar"
        }
    }
}

// MARK: - Scheduled Activity

struct ScheduledActivity: Identifiable, Codable, Equatable {
    var id: UUID
    var activityType: ActivityType
    var workoutType: WorkoutType?
    var title: String
    var startHour: Int
    var startMinute: Int
    var duration: Int // in minutes
    var recurrence: RecurrenceRule
    var startDate: Date // First occurrence date
    var endDate: Date? // Optional end date for recurring
    var weekday: Int? // 1 = Sunday, 7 = Saturday (for weekly)
    var isActive: Bool
    var createdAt: Date
    var syncedToCalendar: Bool
    var externalCalendarId: String?

    // Computed properties
    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: startHour, minute: startMinute)) ?? Date()
        return formatter.string(from: date)
    }

    var endTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let calendar = Calendar.current
        var comps = DateComponents(hour: startHour, minute: startMinute)
        let date = calendar.date(from: comps) ?? Date()
        let endDate = calendar.date(byAdding: .minute, value: duration, to: date) ?? date
        return formatter.string(from: endDate)
    }

    var timeRangeFormatted: String {
        "\(timeFormatted) - \(endTimeFormatted)"
    }

    var color: Color {
        if activityType == .workout {
            return .orange
        }
        return activityType.color
    }

    var icon: String {
        if let workoutType = workoutType {
            return workoutType.icon
        }
        return activityType.icon
    }

    // Create from time slot
    init(
        activityType: ActivityType,
        workoutType: WorkoutType? = nil,
        title: String,
        startTime: Date,
        duration: Int,
        recurrence: RecurrenceRule = .once
    ) {
        self.id = UUID()
        self.activityType = activityType
        self.workoutType = workoutType
        self.title = title
        let calendar = Calendar.current
        self.startHour = calendar.component(.hour, from: startTime)
        self.startMinute = calendar.component(.minute, from: startTime)
        self.duration = duration
        self.recurrence = recurrence
        self.startDate = calendar.startOfDay(for: startTime)
        self.weekday = calendar.component(.weekday, from: startTime)
        self.endDate = nil
        self.isActive = true
        self.createdAt = Date()
        self.syncedToCalendar = false
        self.externalCalendarId = nil
    }

    // Check if this schedule applies to a given date
    func occursOn(date: Date) -> Bool {
        guard isActive else { return false }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        // Check if date is before start date
        if dayStart < calendar.startOfDay(for: startDate) {
            return false
        }

        // Check if date is after end date
        if let endDate = endDate, dayStart > calendar.startOfDay(for: endDate) {
            return false
        }

        switch recurrence {
        case .once:
            return calendar.isDate(date, inSameDayAs: startDate)

        case .weekly:
            let targetWeekday = calendar.component(.weekday, from: date)
            return targetWeekday == weekday

        case .weekdays:
            let targetWeekday = calendar.component(.weekday, from: date)
            return targetWeekday >= 2 && targetWeekday <= 6 // Mon-Fri

        case .biweekly:
            let targetWeekday = calendar.component(.weekday, from: date)
            guard targetWeekday == weekday else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: date).weekOfYear ?? 0
            return weeks % 2 == 0

        case .monthly:
            let startDay = calendar.component(.day, from: startDate)
            let targetDay = calendar.component(.day, from: date)
            return startDay == targetDay
        }
    }

    // Get the actual start/end time for a specific date
    func getTimeRange(for date: Date) -> (start: Date, end: Date)? {
        guard occursOn(date: date) else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = startHour
        components.minute = startMinute

        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .minute, value: duration, to: start) else {
            return nil
        }

        return (start, end)
    }
}

// MARK: - Activity Time Pattern

struct ActivityTimePattern: Codable {
    let weekday: Int // 1-7
    let hour: Int
    let minute: Int
    let activityType: ActivityType
    let workoutType: WorkoutType?
    let successCount: Int
    let totalCount: Int
    let averageDuration: Int

    var successRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(successCount) / Double(totalCount)
    }

    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Conflict Info

struct ScheduleConflict: Identifiable {
    let id = UUID()
    let scheduledActivity: ScheduledActivity
    let conflictingEvent: CalendarEvent
    let conflictType: ConflictType

    enum ConflictType {
        case overlap
        case tooClose // Within 30 minutes
    }

    var description: String {
        switch conflictType {
        case .overlap:
            return "Overlaps with \"\(conflictingEvent.title)\""
        case .tooClose:
            return "Too close to \"\(conflictingEvent.title)\""
        }
    }
}

// MARK: - Scheduled Activity Manager

class ScheduledActivityManager: ObservableObject {
    static let shared = ScheduledActivityManager()

    @Published var scheduledActivities: [ScheduledActivity] = []
    @Published var timePatterns: [ActivityTimePattern] = []
    @Published var conflicts: [ScheduleConflict] = []

    private let saveKey = "scheduledActivities"
    private let patternsKey = "activityTimePatterns"

    private init() {
        loadScheduledActivities()
        loadTimePatterns()
    }

    // MARK: - CRUD Operations

    func addScheduledActivity(_ activity: ScheduledActivity) {
        scheduledActivities.append(activity)
        saveScheduledActivities()
    }

    func updateScheduledActivity(_ activity: ScheduledActivity) {
        if let index = scheduledActivities.firstIndex(where: { $0.id == activity.id }) {
            scheduledActivities[index] = activity
            saveScheduledActivities()
        }
    }

    func deleteScheduledActivity(_ activity: ScheduledActivity) {
        scheduledActivities.removeAll { $0.id == activity.id }
        saveScheduledActivities()
    }

    func deleteScheduledActivity(id: UUID) {
        scheduledActivities.removeAll { $0.id == id }
        saveScheduledActivities()
    }

    // MARK: - Query Methods

    /// Get all scheduled activities for a specific date
    func activities(for date: Date) -> [ScheduledActivity] {
        scheduledActivities.filter { $0.occursOn(date: date) }
    }

    /// Get walk schedules for a date
    func walkSchedules(for date: Date) -> [ScheduledActivity] {
        activities(for: date).filter { $0.activityType == .walk }
    }

    /// Get workout schedules for a date
    func workoutSchedules(for date: Date) -> [ScheduledActivity] {
        activities(for: date).filter { $0.activityType == .workout }
    }

    /// Check if there's a scheduled activity at a specific time
    func hasScheduledActivity(at date: Date, type: ActivityType? = nil) -> ScheduledActivity? {
        let dayActivities = activities(for: date)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        return dayActivities.first { activity in
            guard type == nil || activity.activityType == type else { return false }

            let activityStartMinutes = activity.startHour * 60 + activity.startMinute
            let activityEndMinutes = activityStartMinutes + activity.duration
            let checkMinutes = hour * 60 + minute

            return checkMinutes >= activityStartMinutes && checkMinutes < activityEndMinutes
        }
    }

    // MARK: - Pattern Learning

    /// Learn from completed activities to suggest best times
    func recordCompletedActivity(type: ActivityType, workoutType: WorkoutType?, at time: Date, duration: Int, wasSuccessful: Bool) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: time)
        let hour = calendar.component(.hour, from: time)
        let minute = (calendar.component(.minute, from: time) / 15) * 15 // Round to 15-min

        // Find or create pattern
        if let index = timePatterns.firstIndex(where: {
            $0.weekday == weekday && $0.hour == hour && $0.activityType == type
        }) {
            var pattern = timePatterns[index]
            let newTotal = pattern.totalCount + 1
            let newSuccess = pattern.successCount + (wasSuccessful ? 1 : 0)
            let newAvgDuration = (pattern.averageDuration * pattern.totalCount + duration) / newTotal

            timePatterns[index] = ActivityTimePattern(
                weekday: weekday,
                hour: hour,
                minute: minute,
                activityType: type,
                workoutType: workoutType,
                successCount: newSuccess,
                totalCount: newTotal,
                averageDuration: newAvgDuration
            )
        } else {
            let pattern = ActivityTimePattern(
                weekday: weekday,
                hour: hour,
                minute: minute,
                activityType: type,
                workoutType: workoutType,
                successCount: wasSuccessful ? 1 : 0,
                totalCount: 1,
                averageDuration: duration
            )
            timePatterns.append(pattern)
        }

        saveTimePatterns()
    }

    /// Get best time suggestion for an activity type on a given date
    func getBestTimeSuggestion(for type: ActivityType, on date: Date, duration: Int) -> Date? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        // Find patterns for this weekday with good success rate
        let relevantPatterns = timePatterns
            .filter { $0.weekday == weekday && $0.activityType == type && $0.successRate >= 0.5 }
            .sorted { $0.successRate > $1.successRate }

        if let bestPattern = relevantPatterns.first {
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = bestPattern.hour
            components.minute = bestPattern.minute
            return calendar.date(from: components)
        }

        return nil
    }

    /// Get all time suggestions for an activity type on a given date
    func getTimeSuggestions(for type: ActivityType, on date: Date) -> [ActivityTimePattern] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        return timePatterns
            .filter { $0.weekday == weekday && $0.activityType == type }
            .sorted { $0.successRate > $1.successRate }
    }

    // MARK: - Conflict Detection

    /// Check for conflicts between scheduled activities and calendar events
    func checkConflicts(for date: Date, events: [CalendarEvent]) -> [ScheduleConflict] {
        var foundConflicts: [ScheduleConflict] = []
        let dayActivities = activities(for: date)

        for activity in dayActivities {
            guard let timeRange = activity.getTimeRange(for: date) else { continue }

            for event in events {
                // Check for overlap
                let hasOverlap = timeRange.start < event.endDate && timeRange.end > event.startDate

                // Check if too close (within 30 minutes)
                let tooCloseBefore = abs(timeRange.end.timeIntervalSince(event.startDate)) < 30 * 60
                let tooCloseAfter = abs(event.endDate.timeIntervalSince(timeRange.start)) < 30 * 60

                if hasOverlap {
                    foundConflicts.append(ScheduleConflict(
                        scheduledActivity: activity,
                        conflictingEvent: event,
                        conflictType: .overlap
                    ))
                } else if tooCloseBefore || tooCloseAfter {
                    foundConflicts.append(ScheduleConflict(
                        scheduledActivity: activity,
                        conflictingEvent: event,
                        conflictType: .tooClose
                    ))
                }
            }
        }

        self.conflicts = foundConflicts
        return foundConflicts
    }

    // MARK: - Update Options

    enum UpdateScope {
        case thisOccurrence
        case thisAndFuture
        case allOccurrences
    }

    /// Update a scheduled activity with scope options
    func updateScheduledActivity(_ activity: ScheduledActivity, newTime: Date, scope: UpdateScope) {
        let calendar = Calendar.current

        switch scope {
        case .thisOccurrence:
            // Create a new one-time activity for this date, and exclude this date from original
            var newActivity = activity
            newActivity.id = UUID()
            newActivity.recurrence = .once
            newActivity.startHour = calendar.component(.hour, from: newTime)
            newActivity.startMinute = calendar.component(.minute, from: newTime)
            newActivity.startDate = calendar.startOfDay(for: newTime)
            addScheduledActivity(newActivity)

            // Original activity continues as is (ideally we'd add exception dates)

        case .thisAndFuture:
            // End the original activity and create a new one from this date
            if var original = scheduledActivities.first(where: { $0.id == activity.id }) {
                original.endDate = calendar.date(byAdding: .day, value: -1, to: newTime)
                updateScheduledActivity(original)

                var newActivity = activity
                newActivity.id = UUID()
                newActivity.startHour = calendar.component(.hour, from: newTime)
                newActivity.startMinute = calendar.component(.minute, from: newTime)
                newActivity.startDate = calendar.startOfDay(for: newTime)
                addScheduledActivity(newActivity)
            }

        case .allOccurrences:
            // Update the time for all occurrences
            if var original = scheduledActivities.first(where: { $0.id == activity.id }) {
                original.startHour = calendar.component(.hour, from: newTime)
                original.startMinute = calendar.component(.minute, from: newTime)
                updateScheduledActivity(original)
            }
        }
    }

    // MARK: - Persistence

    private func saveScheduledActivities() {
        if let encoded = try? JSONEncoder().encode(scheduledActivities) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadScheduledActivities() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ScheduledActivity].self, from: data) {
            scheduledActivities = decoded
        }
    }

    private func saveTimePatterns() {
        if let encoded = try? JSONEncoder().encode(timePatterns) {
            UserDefaults.standard.set(encoded, forKey: patternsKey)
        }
    }

    private func loadTimePatterns() {
        if let data = UserDefaults.standard.data(forKey: patternsKey),
           let decoded = try? JSONDecoder().decode([ActivityTimePattern].self, from: data) {
            timePatterns = decoded
        }
    }
}
