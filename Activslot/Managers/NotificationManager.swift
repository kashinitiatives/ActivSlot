import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    private init() {
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

    // MARK: - Evening Plan Notification

    func scheduleEveningPlanNotification(for plan: DayMovementPlan) {
        guard isAuthorized else { return }

        // Remove existing evening notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["evening-plan"]
        )

        let content = UNMutableNotificationContent()
        content.title = "Tomorrow's Movement Plan"
        content.body = buildPlanSummary(for: plan)
        content.sound = .default

        // Schedule for 8 PM today
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "evening-plan",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func buildPlanSummary(for plan: DayMovementPlan) -> String {
        var parts: [String] = []

        if !plan.walkSuggestions.isEmpty {
            let totalSteps = plan.walkSuggestions.reduce(0) { $0 + $1.estimatedSteps }
            parts.append("\(plan.walkSuggestions.count) walkable meeting\(plan.walkSuggestions.count > 1 ? "s" : "") (~\(totalSteps.formatted()) steps)")
        }

        if let gym = plan.gymSuggestion {
            parts.append("\(gym.workoutType.rawValue) workout at \(formatTime(gym.suggestedTime))")
        }

        if parts.isEmpty {
            return "Focus on getting your steps in tomorrow!"
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Walkable Meeting Notification

    func scheduleWalkableMeetingNotification(for event: CalendarEvent) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Walk-Friendly Meeting"
        content.body = "\(event.title) is starting soon. This is a good one to walk during!"
        content.sound = .default

        // Schedule 5 minutes before meeting
        let triggerDate = event.startDate.addingTimeInterval(-5 * 60)

        // Only schedule if it's in the future
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "walkable-\(event.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func scheduleWalkableMeetingNotifications(for events: [CalendarEvent]) {
        // Remove all existing walkable meeting notifications
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let walkableIds = requests.filter { $0.identifier.hasPrefix("walkable-") }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: walkableIds)
        }

        // Schedule new notifications
        for event in events.filter({ $0.isWalkable }) {
            scheduleWalkableMeetingNotification(for: event)
        }
    }

    // MARK: - Cancel All

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
