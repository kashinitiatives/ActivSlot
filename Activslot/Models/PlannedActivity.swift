import Foundation
import SwiftUI

// MARK: - Activity Type

enum ActivityType: String, CaseIterable, Codable {
    case walk = "Walk"
    case workout = "Workout"
    case stretching = "Stretching"
    case meditation = "Meditation"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .workout: return "dumbbell.fill"
        case .stretching: return "figure.flexibility"
        case .meditation: return "brain.head.profile"
        case .custom: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .walk: return .green
        case .workout: return .orange
        case .stretching: return .purple
        case .meditation: return .blue
        case .custom: return .pink
        }
    }

    var defaultDuration: Int {
        switch self {
        case .walk: return 30
        case .workout: return 60
        case .stretching: return 15
        case .meditation: return 10
        case .custom: return 30
        }
    }
}

// MARK: - Repeat Option

enum RepeatOption: String, CaseIterable, Codable {
    case never = "Never"
    case daily = "Every Day"
    case weekdays = "Weekdays"
    case weekly = "Every Week"
    case biweekly = "Every 2 Weeks"
    case monthly = "Every Month"

    var calendarRecurrenceRule: String? {
        switch self {
        case .never: return nil
        case .daily: return "FREQ=DAILY"
        case .weekdays: return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly: return "FREQ=WEEKLY"
        case .biweekly: return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly: return "FREQ=MONTHLY"
        }
    }
}

// MARK: - Alert Option

enum AlertOption: String, CaseIterable, Codable {
    case none = "None"
    case atTime = "At time of event"
    case fiveMinutes = "5 minutes before"
    case fifteenMinutes = "15 minutes before"
    case thirtyMinutes = "30 minutes before"
    case oneHour = "1 hour before"

    var minutesBefore: Int? {
        switch self {
        case .none: return nil
        case .atTime: return 0
        case .fiveMinutes: return 5
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .oneHour: return 60
        }
    }
}

// MARK: - Sync Status

enum SyncStatus: String, Codable {
    case notSynced = "Not Synced"
    case syncing = "Syncing"
    case synced = "Synced"
    case error = "Error"
}

// MARK: - Planned Activity

struct PlannedActivity: Identifiable, Codable {
    var id: UUID
    var title: String
    var activityType: ActivityType
    var workoutType: WorkoutType? // Only for workout activities
    var startTime: Date
    var endTime: Date
    var notes: String
    var repeatOption: RepeatOption
    var alertOption: AlertOption
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    // Sync tracking
    var syncStatus: SyncStatus
    var externalCalendarId: String? // ID in external calendar (Google, iCloud, etc.)
    var syncedCalendars: [String] // Calendar identifiers where this is synced

    // Computed properties
    var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(startTime)
    }

    var isPast: Bool {
        endTime < Date()
    }

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: startTime)
    }

    var color: Color {
        if let workoutType = workoutType {
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

    // Initialize new activity
    init(
        title: String,
        activityType: ActivityType,
        workoutType: WorkoutType? = nil,
        startTime: Date,
        duration: Int? = nil,
        notes: String = "",
        repeatOption: RepeatOption = .never,
        alertOption: AlertOption = .fifteenMinutes
    ) {
        self.id = UUID()
        self.title = title
        self.activityType = activityType
        self.workoutType = workoutType
        self.startTime = startTime
        self.endTime = Calendar.current.date(
            byAdding: .minute,
            value: duration ?? activityType.defaultDuration,
            to: startTime
        ) ?? startTime
        self.notes = notes
        self.repeatOption = repeatOption
        self.alertOption = alertOption
        self.isCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncStatus = .notSynced
        self.externalCalendarId = nil
        self.syncedCalendars = []
    }

    // Create from step slot suggestion
    static func fromStepSlot(_ slot: StepSlot) -> PlannedActivity {
        PlannedActivity(
            title: slot.source ?? "Walk Break",
            activityType: .walk,
            startTime: slot.startTime,
            duration: slot.duration,
            notes: "Target: \(slot.targetSteps) steps"
        )
    }

    // Create from workout slot suggestion
    static func fromWorkoutSlot(_ slot: WorkoutSlot) -> PlannedActivity {
        PlannedActivity(
            title: "\(slot.workoutType.rawValue) Workout",
            activityType: .workout,
            workoutType: slot.workoutType,
            startTime: slot.startTime,
            duration: slot.duration,
            notes: slot.workoutType.description
        )
    }

    mutating func markCompleted() {
        isCompleted = true
        updatedAt = Date()
    }

    mutating func reschedule(to newStartTime: Date) {
        let duration = self.duration
        startTime = newStartTime
        endTime = Calendar.current.date(byAdding: .minute, value: duration, to: newStartTime) ?? newStartTime
        updatedAt = Date()
        syncStatus = .notSynced
    }

    mutating func updateDuration(minutes: Int) {
        endTime = Calendar.current.date(byAdding: .minute, value: minutes, to: startTime) ?? startTime
        updatedAt = Date()
        syncStatus = .notSynced
    }
}

// MARK: - Activity Store (Local Persistence)

class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published var activities: [PlannedActivity] = []

    private let saveKey = "plannedActivities"

    private init() {
        loadActivities()
    }

    // MARK: - CRUD Operations

    func addActivity(_ activity: PlannedActivity) {
        activities.append(activity)
        saveActivities()
    }

    func updateActivity(_ activity: PlannedActivity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            var updated = activity
            updated.updatedAt = Date()
            activities[index] = updated
            saveActivities()
        }
    }

    func deleteActivity(_ activity: PlannedActivity) {
        activities.removeAll { $0.id == activity.id }
        saveActivities()
    }

    /// Update the time of an activity (used for drag-to-move in calendar)
    func updateActivityTime(_ activity: PlannedActivity, to newTime: Date) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            var updated = activities[index]
            // Calculate new end time based on duration
            let duration = updated.duration
            updated.startTime = newTime
            updated.updatedAt = Date()
            activities[index] = updated
            saveActivities()
        }
    }

    /// Update the duration of an activity (used for drag-to-resize in calendar)
    func updateActivityDuration(_ activity: PlannedActivity, to newDuration: Int) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            var updated = activities[index]
            updated.updateDuration(minutes: max(15, newDuration))
            activities[index] = updated
            saveActivities()
        }
    }

    func deleteActivity(at offsets: IndexSet, from dayActivities: [PlannedActivity]) {
        for index in offsets {
            let activity = dayActivities[index]
            deleteActivity(activity)
        }
    }

    // MARK: - Query Methods

    func activities(for date: Date) -> [PlannedActivity] {
        let calendar = Calendar.current
        return activities.filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    func activities(from startDate: Date, to endDate: Date) -> [PlannedActivity] {
        activities.filter { $0.startTime >= startDate && $0.startTime <= endDate }
            .sorted { $0.startTime < $1.startTime }
    }

    func upcomingActivities(limit: Int = 5) -> [PlannedActivity] {
        let now = Date()
        return activities
            .filter { $0.startTime > now && !$0.isCompleted }
            .sorted { $0.startTime < $1.startTime }
            .prefix(limit)
            .map { $0 }
    }

    func activitiesNeedingSync() -> [PlannedActivity] {
        activities.filter { $0.syncStatus == .notSynced || $0.syncStatus == .error }
    }

    // MARK: - Persistence

    private func saveActivities() {
        if let encoded = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func loadActivities() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([PlannedActivity].self, from: data) {
            activities = decoded
        }
    }

    // MARK: - Bulk Operations

    func addSuggestedActivities(stepSlots: [StepSlot], workoutSlot: WorkoutSlot?) {
        for slot in stepSlots {
            let activity = PlannedActivity.fromStepSlot(slot)
            // Check if similar activity doesn't already exist
            let exists = activities.contains { existing in
                Calendar.current.isDate(existing.startTime, equalTo: activity.startTime, toGranularity: .minute)
                && existing.activityType == activity.activityType
            }
            if !exists {
                addActivity(activity)
            }
        }

        if let workout = workoutSlot {
            let activity = PlannedActivity.fromWorkoutSlot(workout)
            let exists = activities.contains { existing in
                Calendar.current.isDate(existing.startTime, equalTo: activity.startTime, toGranularity: .minute)
                && existing.activityType == .workout
            }
            if !exists {
                addActivity(activity)
            }
        }
    }

    func clearPastActivities(before date: Date = Date()) {
        activities.removeAll { $0.endTime < date && $0.isCompleted }
        saveActivities()
    }
}
