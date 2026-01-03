import Foundation
import UserNotifications

// MARK: - Notification Identifiers

enum NotificationIdentifier {
    static let eveningBriefing = "evening-briefing"
    static let walkableMeetingPrefix = "walkable-meeting-"
    static let workoutReminder = "workout-reminder"
    static let afternoonCheckIn = "afternoon-checkin"
    static let daySummary = "day-summary"
    static let streakAtRisk = "streak-at-risk"
}

// MARK: - Tomorrow Briefing Data

struct TomorrowBriefing {
    let date: Date
    let totalMeetingMinutes: Int
    let realMeetingCount: Int
    let walkableMeetings: [CalendarEvent]
    let bestWorkoutWindow: DateInterval?
    let dayType: DayType

    enum DayType {
        case light      // < 2 hours meetings
        case moderate   // 2-5 hours meetings
        case heavy      // > 5 hours meetings

        var emoji: String {
            switch self {
            case .light: return "🌤️"
            case .moderate: return "⛅"
            case .heavy: return "🌧️"
            }
        }

        var description: String {
            switch self {
            case .light: return "Light day"
            case .moderate: return "Moderate day"
            case .heavy: return "Busy day"
            }
        }
    }

    var walkableSteps: Int {
        walkableMeetings.reduce(0) { $0 + $1.estimatedSteps }
    }

    init(date: Date, events: [CalendarEvent], freeSlots: [DateInterval]) {
        self.date = date

        // Filter to real meetings only
        let realMeetings = events.filter { $0.isRealMeeting }
        self.realMeetingCount = realMeetings.count
        self.totalMeetingMinutes = realMeetings.reduce(0) { $0 + $1.duration }
        self.walkableMeetings = realMeetings.filter { $0.isWalkable }

        // Determine day type
        if totalMeetingMinutes < 120 {
            self.dayType = .light
        } else if totalMeetingMinutes <= 300 {
            self.dayType = .moderate
        } else {
            self.dayType = .heavy
        }

        // Find best workout window (prefer morning for heavy days)
        let userPrefs = UserPreferences.shared
        let preferMorning = dayType == .heavy || userPrefs.preferredGymTime == .morning

        if preferMorning {
            // Find morning slot (before 9 AM)
            self.bestWorkoutWindow = freeSlots.first { interval in
                let hour = Calendar.current.component(.hour, from: interval.start)
                return hour < 9 && interval.duration >= Double(userPrefs.workoutDuration.rawValue * 60)
            } ?? freeSlots.first { $0.duration >= Double(userPrefs.workoutDuration.rawValue * 60) }
        } else {
            // Find slot matching preference
            self.bestWorkoutWindow = freeSlots.first { $0.duration >= Double(userPrefs.workoutDuration.rawValue * 60) }
        }
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    // Notification Settings (stored in UserDefaults)
    @Published var eveningBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(eveningBriefingEnabled, forKey: "notification_eveningBriefing") }
    }
    @Published var walkableMeetingRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(walkableMeetingRemindersEnabled, forKey: "notification_walkableMeetings") }
    }
    @Published var workoutRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(workoutRemindersEnabled, forKey: "notification_workoutReminders") }
    }
    @Published var eveningBriefingTime: Date {
        didSet { UserDefaults.standard.set(eveningBriefingTime.timeIntervalSince1970, forKey: "notification_eveningBriefingTime") }
    }
    @Published var walkableMeetingLeadTime: Int { // minutes before meeting
        didSet { UserDefaults.standard.set(walkableMeetingLeadTime, forKey: "notification_walkableLeadTime") }
    }

    private init() {
        // Load settings from UserDefaults
        self.eveningBriefingEnabled = UserDefaults.standard.object(forKey: "notification_eveningBriefing") as? Bool ?? true
        self.walkableMeetingRemindersEnabled = UserDefaults.standard.object(forKey: "notification_walkableMeetings") as? Bool ?? true
        self.workoutRemindersEnabled = UserDefaults.standard.object(forKey: "notification_workoutReminders") as? Bool ?? true

        // Default evening briefing time: 8 PM
        if let storedTime = UserDefaults.standard.object(forKey: "notification_eveningBriefingTime") as? Double {
            self.eveningBriefingTime = Date(timeIntervalSince1970: storedTime)
        } else {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 20
            components.minute = 0
            self.eveningBriefingTime = Calendar.current.date(from: components) ?? Date()
        }

        self.walkableMeetingLeadTime = UserDefaults.standard.object(forKey: "notification_walkableLeadTime") as? Int ?? 10

        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        await MainActor.run {
            self.isAuthorized = granted
        }
        return granted
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Evening Briefing Notification

    func scheduleEveningBriefing(briefing: TomorrowBriefing) {
        guard isAuthorized && eveningBriefingEnabled else { return }

        // Remove existing evening notification
        cancelNotification(identifier: NotificationIdentifier.eveningBriefing)

        let content = UNMutableNotificationContent()
        content.title = "\(briefing.dayType.emoji) Tomorrow's Game Plan"
        content.body = buildEveningBriefingBody(briefing: briefing)
        content.sound = .default
        content.categoryIdentifier = "EVENING_BRIEFING"

        // Add action buttons
        content.userInfo = [
            "type": "eveningBriefing",
            "date": briefing.date.timeIntervalSince1970
        ]

        // Schedule for the configured time today
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.hour, .minute], from: eveningBriefingTime)

        // If it's already past the briefing time today, schedule for tomorrow
        let now = Date()
        var scheduledDate = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: calendar.component(.day, from: now),
            hour: dateComponents.hour,
            minute: dateComponents.minute
        )) ?? now

        if scheduledDate <= now {
            scheduledDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.eveningBriefing,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling evening briefing: \(error)")
            }
            #endif
        }
    }

    private func buildEveningBriefingBody(briefing: TomorrowBriefing) -> String {
        var parts: [String] = []
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        // Meeting summary
        let hours = briefing.totalMeetingMinutes / 60
        let mins = briefing.totalMeetingMinutes % 60
        if hours > 0 {
            parts.append("\(hours)h\(mins > 0 ? " \(mins)m" : "") of meetings")
        } else if mins > 0 {
            parts.append("\(mins)m of meetings")
        }

        // Workout recommendation
        if let workoutWindow = briefing.bestWorkoutWindow {
            let time = formatter.string(from: workoutWindow.start)
            if briefing.dayType == .heavy {
                parts.append("Best workout: \(time) (before meetings)")
            } else {
                parts.append("Workout window: \(time)")
            }
        }

        // Walkable meetings
        if !briefing.walkableMeetings.isEmpty {
            let count = briefing.walkableMeetings.count
            let steps = briefing.walkableSteps.formatted()
            parts.append("\(count) walkable meeting\(count > 1 ? "s" : "") (~\(steps) steps)")
        }

        if parts.isEmpty {
            return "Plan your movement for tomorrow!"
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Walkable Meeting Notification

    func scheduleWalkableMeetingReminder(for event: CalendarEvent) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }
        guard event.isWalkable else { return }

        let content = UNMutableNotificationContent()
        content.title = "Walk this call?"
        content.body = "\"\(event.title)\" in \(walkableMeetingLeadTime) min\n\(event.attendeeCount) attendees • \(event.duration) min • ~\(event.estimatedSteps.formatted()) steps"
        content.sound = .default
        content.categoryIdentifier = "WALKABLE_MEETING"

        content.userInfo = [
            "type": "walkableMeeting",
            "eventId": event.id,
            "eventTitle": event.title
        ]

        // Schedule X minutes before meeting
        let triggerDate = event.startDate.addingTimeInterval(-Double(walkableMeetingLeadTime) * 60)

        // Only schedule if it's in the future
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.walkableMeetingPrefix)\(event.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling walkable meeting reminder: \(error)")
            }
            #endif
        }
    }

    func scheduleAllWalkableMeetingReminders(for events: [CalendarEvent]) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }

        // Remove all existing walkable meeting notifications
        cancelNotificationsWithPrefix(NotificationIdentifier.walkableMeetingPrefix)

        // Schedule new notifications for walkable meetings
        let walkableEvents = events.filter { $0.isWalkable && $0.startDate > Date() }
        for event in walkableEvents {
            scheduleWalkableMeetingReminder(for: event)
        }
    }

    // MARK: - Workout Reminder

    func scheduleWorkoutReminder(at time: Date, message: String? = nil) {
        guard isAuthorized && workoutRemindersEnabled else { return }
        guard time > Date() else { return }

        // Remove existing workout reminder
        cancelNotification(identifier: NotificationIdentifier.workoutReminder)

        let content = UNMutableNotificationContent()
        content.title = "Workout Time"
        content.body = message ?? "Your scheduled workout is coming up in 15 minutes!"
        content.sound = .default
        content.categoryIdentifier = "WORKOUT_REMINDER"

        // Schedule 15 minutes before
        let triggerDate = time.addingTimeInterval(-15 * 60)
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.workoutReminder,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Streak At Risk Notification

    func scheduleStreakAtRiskNotification(currentSteps: Int, goalSteps: Int, currentStreak: Int) {
        guard isAuthorized else { return }
        guard currentStreak > 0 else { return } // Only if they have a streak to protect
        guard currentSteps < goalSteps else { return } // Only if goal not yet met

        // Cancel any existing streak notification
        cancelNotification(identifier: NotificationIdentifier.streakAtRisk)

        let stepsNeeded = goalSteps - currentSteps
        let content = UNMutableNotificationContent()

        if currentStreak >= 7 {
            content.title = "🔥 Don't lose your \(currentStreak)-day streak!"
        } else {
            content.title = "Keep your streak alive!"
        }
        content.body = "You need \(stepsNeeded.formatted()) more steps today. A 15-min walk can do it!"
        content.sound = .default
        content.categoryIdentifier = "STREAK_AT_RISK"

        content.userInfo = [
            "type": "streakAtRisk",
            "stepsNeeded": stepsNeeded,
            "currentStreak": currentStreak
        ]

        // Schedule for 7 PM today if not already past
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 19
        components.minute = 0

        guard let scheduledDate = calendar.date(from: components),
              scheduledDate > Date() else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: scheduledDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.streakAtRisk,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling streak at risk notification: \(error)")
            }
            #endif
        }
    }

    // MARK: - Daily Refresh

    /// Call this method to refresh all notifications for today/tomorrow
    func refreshDailyNotifications() async {
        guard isAuthorized else { return }

        let calendarManager = CalendarManager.shared
        let userPrefs = UserPreferences.shared
        let healthKitManager = HealthKitManager.shared
        let streakManager = StreakManager.shared

        // Get tomorrow's date
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

        // Fetch tomorrow's events
        if let tomorrowEvents = try? await calendarManager.fetchEvents(for: tomorrow) {
            // Get free slots for tomorrow
            let freeSlots = (try? await calendarManager.findFreeSlots(
                for: tomorrow,
                minimumDuration: userPrefs.workoutDuration.rawValue
            )) ?? []

            // Create briefing and schedule notification
            let briefing = TomorrowBriefing(date: tomorrow, events: tomorrowEvents, freeSlots: freeSlots)
            scheduleEveningBriefing(briefing: briefing)
        }

        // Get today's events for walkable meeting reminders
        if let todayEvents = try? await calendarManager.fetchEvents(for: Date()) {
            scheduleAllWalkableMeetingReminders(for: todayEvents)
        }

        // Schedule streak-at-risk notification if user has a streak to protect
        let currentSteps = healthKitManager.todaySteps
        let goalSteps = userPrefs.dailyStepGoal
        let currentStreak = streakManager.currentStreak
        scheduleStreakAtRiskNotification(
            currentSteps: currentSteps,
            goalSteps: goalSteps,
            currentStreak: currentStreak
        )
    }

    // MARK: - Cancel Helpers

    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotificationsWithPrefix(_ prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let idsToRemove = requests.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Notification Categories (for actions)

    func registerNotificationCategories() {
        // Evening Briefing actions
        let planAction = UNNotificationAction(
            identifier: "PLAN_DAY",
            title: "Plan My Day",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        let eveningCategory = UNNotificationCategory(
            identifier: "EVENING_BRIEFING",
            actions: [planAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Walkable Meeting actions
        let startWalkingAction = UNNotificationAction(
            identifier: "START_WALKING",
            title: "Start Walking",
            options: [.foreground]
        )
        let skipAction = UNNotificationAction(
            identifier: "SKIP",
            title: "Skip",
            options: []
        )
        let walkableCategory = UNNotificationCategory(
            identifier: "WALKABLE_MEETING",
            actions: [startWalkingAction, skipAction],
            intentIdentifiers: [],
            options: []
        )

        // Workout Reminder actions
        let startWorkoutAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: "Let's Go!",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Remind in 15 min",
            options: []
        )
        let workoutCategory = UNNotificationCategory(
            identifier: "WORKOUT_REMINDER",
            actions: [startWorkoutAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            eveningCategory,
            walkableCategory,
            workoutCategory
        ])
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Support (backward compatibility)

extension NotificationManager {
    func scheduleEveningPlanNotification(for plan: DayMovementPlan) {
        // Convert legacy plan to new briefing format
        let events = plan.walkSuggestions.map { suggestion in
            CalendarEvent(
                id: UUID().uuidString,
                title: suggestion.meetingTitle,
                startDate: suggestion.startTime,
                endDate: Calendar.current.date(byAdding: .minute, value: suggestion.duration, to: suggestion.startTime) ?? suggestion.startTime,
                attendeeCount: 5,
                isOrganizer: false
            )
        }

        let freeSlots: [DateInterval] = []
        let briefing = TomorrowBriefing(date: plan.date, events: events, freeSlots: freeSlots)
        scheduleEveningBriefing(briefing: briefing)
    }

    func scheduleWalkableMeetingNotification(for event: CalendarEvent) {
        scheduleWalkableMeetingReminder(for: event)
    }

    func scheduleWalkableMeetingNotifications(for events: [CalendarEvent]) {
        scheduleAllWalkableMeetingReminders(for: events)
    }
}
