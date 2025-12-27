import Foundation
import EventKit
import UserNotifications

// MARK: - Autopilot Manager

/// Manages full autopilot mode - automatically schedules walks throughout the day
/// without requiring user intervention
class AutopilotManager: ObservableObject {
    static let shared = AutopilotManager()

    private let eventStore = EKEventStore()
    private let calendarManager = CalendarManager.shared
    private let scheduledActivityManager = ScheduledActivityManager.shared

    @Published var isProcessing = false
    @Published var lastScheduledWalks: [ScheduledWalk] = []
    @Published var pendingApprovals: [ScheduledWalk] = []

    // Tracking via UserDefaults (can't use @AppStorage in non-SwiftUI class)
    private var lastScheduledDateString: String {
        get { UserDefaults.standard.string(forKey: "autopilotLastScheduledDate") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "autopilotLastScheduledDate") }
    }
    private var scheduledEventIDsJSON: String {
        get { UserDefaults.standard.string(forKey: "autopilotScheduledEventIDs") ?? "[]" }
        set { UserDefaults.standard.set(newValue, forKey: "autopilotScheduledEventIDs") }
    }

    struct ScheduledWalk: Identifiable, Codable {
        let id: UUID
        let date: Date
        let startTime: Date
        let duration: Int
        let type: WalkType
        var calendarEventID: String?
        var isApproved: Bool

        enum WalkType: String, Codable {
            case microWalk = "micro"       // 5-10 min
            case shortWalk = "short"       // 15-20 min
            case standardWalk = "standard" // 25-30 min

            var displayName: String {
                switch self {
                case .microWalk: return "Quick Reset"
                case .shortWalk: return "Energy Boost"
                case .standardWalk: return "Power Walk"
                }
            }

            var icon: String {
                switch self {
                case .microWalk: return "figure.walk"
                case .shortWalk: return "figure.walk.motion"
                case .standardWalk: return "figure.run"
                }
            }
        }
    }

    private init() {
        loadScheduledWalks()
    }

    // MARK: - Main Scheduling Logic

    /// Schedule walks for tomorrow - called from evening briefing or app lifecycle
    func scheduleWalksForTomorrow() async {
        let prefs = UserPreferences.shared
        guard prefs.autopilotEnabled else { return }

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowDateString = formatDateString(tomorrow)

        // Check if already scheduled
        if lastScheduledDateString == tomorrowDateString {
            return
        }

        await MainActor.run { isProcessing = true }
        defer { Task { await MainActor.run { isProcessing = false } } }

        do {
            // Fetch tomorrow's events
            let events = try await calendarManager.fetchEvents(for: tomorrow)
            let realMeetings = events.filter { $0.isRealMeeting }

            // Get existing scheduled activities
            let existingActivities = scheduledActivityManager.activities(for: tomorrow)

            // Find optimal walk slots
            let walkSlots = findOptimalWalkSlots(
                for: tomorrow,
                events: realMeetings,
                scheduledActivities: existingActivities,
                targetWalks: prefs.autopilotWalksPerDay,
                includeMicroWalks: prefs.autopilotIncludeMicroWalks,
                minDuration: prefs.autopilotMinWalkDuration,
                maxDuration: prefs.autopilotMaxWalkDuration
            )

            guard !walkSlots.isEmpty else {
                print("Autopilot: No suitable walk slots found for tomorrow")
                return
            }

            // Create scheduled walks based on trust level
            var scheduledWalks: [ScheduledWalk] = []

            for slot in walkSlots {
                let walkType = determineWalkType(duration: slot.duration)
                var walk = ScheduledWalk(
                    id: UUID(),
                    date: tomorrow,
                    startTime: slot.start,
                    duration: slot.duration,
                    type: walkType,
                    calendarEventID: nil,
                    isApproved: prefs.autopilotTrustLevel == .fullAuto
                )

                switch prefs.autopilotTrustLevel {
                case .fullAuto:
                    // Create calendar event immediately
                    if let eventID = try? await createCalendarEvent(for: walk) {
                        walk.calendarEventID = eventID
                    }
                    // Also add to scheduled activities
                    addToScheduledActivities(walk)

                case .confirmFirst:
                    // Add to pending approvals
                    await MainActor.run {
                        pendingApprovals.append(walk)
                    }
                    // Schedule notification for approval
                    scheduleApprovalNotification(for: walk)

                case .suggestOnly:
                    // Just store for display in app
                    break
                }

                scheduledWalks.append(walk)
            }

            await MainActor.run {
                lastScheduledWalks = scheduledWalks
                lastScheduledDateString = tomorrowDateString
            }

            saveScheduledWalks()

            // Send summary notification if full auto
            if prefs.autopilotTrustLevel == .fullAuto {
                sendScheduleSummaryNotification(walks: scheduledWalks, for: tomorrow)
            }

        } catch {
            print("Autopilot: Error scheduling walks - \(error)")
        }
    }

    // MARK: - Find Optimal Walk Slots

    private func findOptimalWalkSlots(
        for date: Date,
        events: [CalendarEvent],
        scheduledActivities: [ScheduledActivity],
        targetWalks: Int,
        includeMicroWalks: Bool,
        minDuration: Int,
        maxDuration: Int
    ) -> [(start: Date, duration: Int)] {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        // Build busy intervals
        var busyIntervals: [(start: Date, end: Date)] = []

        for event in events {
            busyIntervals.append((start: event.startDate, end: event.endDate))
        }

        for activity in scheduledActivities {
            if let range = activity.getTimeRange(for: date) {
                busyIntervals.append((start: range.start, end: range.end))
            }
        }

        busyIntervals.sort { $0.start < $1.start }

        // Define day boundaries
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = prefs.wakeTime.hour + 1 // 1 hour after wake
        let dayStart = calendar.date(from: startComponents) ?? date

        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)
        endComponents.hour = min(prefs.sleepTime.hour - 1, 21) // 1 hour before sleep, max 9 PM
        let dayEnd = calendar.date(from: endComponents) ?? date

        // Find all free slots
        var freeSlots: [DateInterval] = []
        var currentTime = dayStart

        for interval in busyIntervals {
            if interval.end <= dayStart || interval.start >= dayEnd {
                continue
            }

            let intervalStart = max(interval.start, dayStart)

            if intervalStart > currentTime {
                let gap = DateInterval(start: currentTime, end: intervalStart)
                if gap.duration >= Double(minDuration * 60) {
                    freeSlots.append(gap)
                }
            }

            currentTime = max(currentTime, min(interval.end, dayEnd))
        }

        if currentTime < dayEnd {
            let gap = DateInterval(start: currentTime, end: dayEnd)
            if gap.duration >= Double(minDuration * 60) {
                freeSlots.append(gap)
            }
        }

        // Filter out meal times
        freeSlots = freeSlots.filter { !prefs.isDuringMeal($0.start) }

        // Strategic walk placement
        var selectedSlots: [(start: Date, duration: Int)] = []

        // Strategy: Distribute walks throughout the day
        // Morning walk, post-lunch walk, afternoon walk
        let timeCategories: [(name: String, startHour: Int, endHour: Int, priority: Int)] = [
            ("morning", 8, 11, 2),
            ("midday", 11, 14, 1),
            ("afternoon", 14, 17, 3),
            ("evening", 17, 20, 2)
        ]

        for category in timeCategories.sorted(by: { $0.priority < $1.priority }) {
            if selectedSlots.count >= targetWalks { break }

            var categoryStart = calendar.dateComponents([.year, .month, .day], from: date)
            categoryStart.hour = category.startHour
            let catStartDate = calendar.date(from: categoryStart) ?? date

            var categoryEnd = calendar.dateComponents([.year, .month, .day], from: date)
            categoryEnd.hour = category.endHour
            let catEndDate = calendar.date(from: categoryEnd) ?? date

            // Find best slot in this category
            if let bestSlot = freeSlots.first(where: { slot in
                slot.start >= catStartDate &&
                slot.start < catEndDate &&
                !selectedSlots.contains(where: { abs($0.start.timeIntervalSince(slot.start)) < 3600 })
            }) {
                let availableDuration = Int(bestSlot.duration / 60)
                let walkDuration = min(maxDuration, max(minDuration, availableDuration))

                selectedSlots.append((start: bestSlot.start, duration: walkDuration))
            }
        }

        // If we still need more walks and micro walks are enabled
        if selectedSlots.count < targetWalks && includeMicroWalks {
            // Look for short gaps between meetings (perfect for micro walks)
            for slot in freeSlots {
                if selectedSlots.count >= targetWalks { break }

                let durationMins = Int(slot.duration / 60)
                if durationMins >= 5 && durationMins <= 15 {
                    // Perfect micro-walk slot
                    if !selectedSlots.contains(where: { abs($0.start.timeIntervalSince(slot.start)) < 1800 }) {
                        selectedSlots.append((start: slot.start, duration: min(durationMins, 10)))
                    }
                }
            }
        }

        return selectedSlots.sorted { $0.start < $1.start }
    }

    private func determineWalkType(duration: Int) -> ScheduledWalk.WalkType {
        if duration <= 10 {
            return .microWalk
        } else if duration <= 20 {
            return .shortWalk
        } else {
            return .standardWalk
        }
    }

    // MARK: - Calendar Integration

    private func createCalendarEvent(for walk: ScheduledWalk) async throws -> String? {
        let prefs = UserPreferences.shared
        guard !prefs.autopilotCalendarID.isEmpty else { return nil }

        let calendars = eventStore.calendars(for: .event)
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == prefs.autopilotCalendarID }) else {
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = "\(walk.type.displayName) \(walk.type == .microWalk ? "🚶" : "🚶‍♂️")"
        event.startDate = walk.startTime
        event.endDate = Calendar.current.date(byAdding: .minute, value: walk.duration, to: walk.startTime)

        // Add motivational note based on user's Why
        let whyMessage = prefs.personalWhy?.motivationalMessage ?? "Time to move!"
        event.notes = """
        \(whyMessage)

        Duration: \(walk.duration) minutes
        Type: \(walk.type.displayName)

        ---
        Auto-scheduled by Activslot
        """

        // Add reminder
        let alarm = EKAlarm(relativeOffset: TimeInterval(-5 * 60)) // 5 min before
        event.addAlarm(alarm)

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    private func addToScheduledActivities(_ walk: ScheduledWalk) {
        let activity = ScheduledActivity(
            activityType: .walk,
            workoutType: nil,
            title: walk.type.displayName,
            startTime: walk.startTime,
            duration: walk.duration,
            recurrence: .once
        )
        scheduledActivityManager.addScheduledActivity(activity)
    }

    // MARK: - Notifications

    private func scheduleApprovalNotification(for walk: ScheduledWalk) {
        let content = UNMutableNotificationContent()
        content.title = "Walk Scheduled for Tomorrow"

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: walk.startTime)

        content.body = "\(walk.type.displayName) at \(timeString) (\(walk.duration) min). Tap to confirm or adjust."
        content.sound = .default
        content.categoryIdentifier = "AUTOPILOT_APPROVAL"
        content.userInfo = [
            "type": "autopilotApproval",
            "walkID": walk.id.uuidString
        ]

        // Schedule for evening (8 PM)
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "autopilot-approval-\(walk.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendScheduleSummaryNotification(walks: [ScheduledWalk], for date: Date) {
        let content = UNMutableNotificationContent()

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)

        content.title = "\(dayName)'s Walks Ready"

        let walkSummary = walks.map { walk in
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "\(timeFormatter.string(from: walk.startTime)) - \(walk.duration)min"
        }.joined(separator: ", ")

        content.body = "\(walks.count) walks scheduled: \(walkSummary)"
        content.sound = .default

        // Schedule for 9 PM
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = 21
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "autopilot-summary-\(formatDateString(date))",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Approval Handling

    func approveWalk(_ walkID: UUID) async {
        guard let index = pendingApprovals.firstIndex(where: { $0.id == walkID }) else { return }

        var walk = pendingApprovals[index]
        walk.isApproved = true

        // Create calendar event
        if let eventID = try? await createCalendarEvent(for: walk) {
            walk.calendarEventID = eventID
        }

        // Add to scheduled activities
        addToScheduledActivities(walk)

        await MainActor.run {
            pendingApprovals.remove(at: index)
            if let lastIndex = lastScheduledWalks.firstIndex(where: { $0.id == walkID }) {
                lastScheduledWalks[lastIndex] = walk
            }
        }

        saveScheduledWalks()
    }

    func rejectWalk(_ walkID: UUID) async {
        await MainActor.run {
            pendingApprovals.removeAll { $0.id == walkID }
            lastScheduledWalks.removeAll { $0.id == walkID }
        }
        saveScheduledWalks()
    }

    func adjustWalkTime(_ walkID: UUID, newTime: Date) async {
        guard let index = pendingApprovals.firstIndex(where: { $0.id == walkID }) else { return }

        var walk = pendingApprovals[index]
        let updatedWalk = ScheduledWalk(
            id: walk.id,
            date: walk.date,
            startTime: newTime,
            duration: walk.duration,
            type: walk.type,
            calendarEventID: nil,
            isApproved: true
        )

        await MainActor.run {
            pendingApprovals.remove(at: index)
        }

        await approveWalk(updatedWalk.id)
    }

    // MARK: - Persistence

    private func saveScheduledWalks() {
        if let data = try? JSONEncoder().encode(lastScheduledWalks),
           let jsonString = String(data: data, encoding: .utf8) {
            scheduledEventIDsJSON = jsonString
        }
    }

    private func loadScheduledWalks() {
        if let data = scheduledEventIDsJSON.data(using: .utf8),
           let walks = try? JSONDecoder().decode([ScheduledWalk].self, from: data) {
            lastScheduledWalks = walks
            pendingApprovals = walks.filter { !$0.isApproved }
        }
    }

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Contextual Triggers

    /// Called when a meeting ends - check if it's a good time for a walk
    func checkPostMeetingOpportunity(meetingEndTime: Date) async -> ScheduledWalk? {
        let prefs = UserPreferences.shared
        guard prefs.autopilotEnabled else { return nil }

        let calendar = Calendar.current

        // Check if there's at least 10 minutes before next event
        let events = (try? await calendarManager.fetchEvents(for: Date())) ?? []
        let upcomingEvents = events.filter { $0.startDate > meetingEndTime }
            .sorted { $0.startDate < $1.startDate }

        guard let nextEvent = upcomingEvents.first else {
            // No more meetings - suggest a walk
            return createMicroWalkSuggestion(at: meetingEndTime)
        }

        let gapMinutes = Int(nextEvent.startDate.timeIntervalSince(meetingEndTime) / 60)

        if gapMinutes >= 10 && !prefs.isDuringMeal(meetingEndTime) {
            let walkDuration = min(gapMinutes - 5, 15) // Leave 5 min buffer
            return ScheduledWalk(
                id: UUID(),
                date: Date(),
                startTime: meetingEndTime,
                duration: walkDuration,
                type: walkDuration <= 10 ? .microWalk : .shortWalk,
                calendarEventID: nil,
                isApproved: false
            )
        }

        return nil
    }

    private func createMicroWalkSuggestion(at time: Date) -> ScheduledWalk {
        ScheduledWalk(
            id: UUID(),
            date: Date(),
            startTime: time,
            duration: 10,
            type: .microWalk,
            calendarEventID: nil,
            isApproved: false
        )
    }

    /// Called when user has been sitting too long
    func suggestSittingBreak() -> ScheduledWalk {
        ScheduledWalk(
            id: UUID(),
            date: Date(),
            startTime: Date(),
            duration: 5,
            type: .microWalk,
            calendarEventID: nil,
            isApproved: false
        )
    }
}
