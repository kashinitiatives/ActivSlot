import Foundation
import SwiftUI

class MovementPlanManager: ObservableObject {
    static let shared = MovementPlanManager()

    private let healthKitManager = HealthKitManager.shared
    private let calendarManager = CalendarManager.shared
    private let userPreferences = UserPreferences.shared
    private let scheduledActivityManager = ScheduledActivityManager.shared

    @Published var todayPlan: DayMovementPlan?
    @Published var tomorrowPlan: DayMovementPlan?
    @Published var isLoading = false

    // Suggested slots (before user schedules them)
    @Published var suggestedWalkSlot: StepSlot?
    @Published var suggestedWorkoutSlot: WorkoutSlot?

    // Conflicts for today
    @Published var todayConflicts: [ScheduleConflict] = []

    // Track completed gym days this week
    @AppStorage("lastWorkoutType") private var lastWorkoutTypeRaw: String = "Legs"
    @AppStorage("gymDaysThisWeek") private var gymDaysThisWeek: Int = 0
    @AppStorage("weekStartDate") private var weekStartDateTimestamp: Double = 0

    private init() {}

    var lastWorkoutType: WorkoutType {
        get { WorkoutType(rawValue: lastWorkoutTypeRaw) ?? .legs }
        set { lastWorkoutTypeRaw = newValue.rawValue }
    }

    // MARK: - Plan Generation

    @MainActor
    func generatePlans() async {
        isLoading = true
        defer { isLoading = false }

        async let todayPlanTask = generatePlan(for: Date())
        async let tomorrowPlanTask = generatePlan(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)

        todayPlan = await todayPlanTask
        tomorrowPlan = await tomorrowPlanTask

        resetWeekIfNeeded()
    }

    func generatePlan(for date: Date) async -> DayMovementPlan {
        var stepSlots: [StepSlot] = []
        var workoutSlot: WorkoutSlot? = nil

        // Get current steps if today
        let currentSteps: Int
        if Calendar.current.isDateInToday(date) {
            currentSteps = (try? await healthKitManager.fetchTodaySteps()) ?? 0
        } else {
            currentSteps = 0
        }

        // Get calendar events for conflict checking
        let calendarEvents = (try? await calendarManager.fetchEvents(for: date)) ?? []

        // FIRST: Check for scheduled activities (user has already set these)
        let scheduledWalks = scheduledActivityManager.walkSchedules(for: date)
        let scheduledWorkouts = scheduledActivityManager.workoutSchedules(for: date)

        // Add scheduled walk slots
        for scheduled in scheduledWalks {
            if let timeRange = scheduled.getTimeRange(for: date) {
                let duration = scheduled.duration
                let slot = StepSlot(
                    startTime: timeRange.start,
                    endTime: timeRange.end,
                    slotType: .freeTime,
                    targetSteps: duration * 100, // 100 steps per minute
                    source: scheduled.title
                )
                stepSlots.append(slot)
            }
        }

        // Add scheduled workout slot
        if let scheduledWorkout = scheduledWorkouts.first,
           let timeRange = scheduledWorkout.getTimeRange(for: date) {
            workoutSlot = WorkoutSlot(
                startTime: timeRange.start,
                endTime: timeRange.end,
                workoutType: scheduledWorkout.workoutType ?? getNextWorkoutType(),
                isRecommended: true
            )
        }

        // Check for conflicts with calendar events
        if Calendar.current.isDateInToday(date) {
            await MainActor.run {
                self.todayConflicts = scheduledActivityManager.checkConflicts(for: date, events: calendarEvents)
            }
        }

        // SECOND: If no scheduled activities, provide suggestions
        let hasScheduledWalk = !scheduledWalks.isEmpty
        let hasScheduledWorkout = !scheduledWorkouts.isEmpty

        if !hasScheduledWalk {
            // Get walkable meetings and convert to step slots
            if let walkableMeetings = try? await calendarManager.getWalkableMeetings(for: date) {
                for meeting in walkableMeetings {
                    // Skip if during meal time
                    if userPreferences.isDuringMeal(meeting.startDate) {
                        continue
                    }

                    // Skip if outside buffered active hours
                    if !userPreferences.isWithinBufferedActiveHours(meeting.startDate) {
                        continue
                    }

                    let slot = StepSlot(
                        startTime: meeting.startDate,
                        endTime: meeting.endDate,
                        slotType: .walkableMeeting,
                        targetSteps: meeting.estimatedSteps,
                        source: meeting.title
                    )
                    stepSlots.append(slot)
                }
            }

            // Find free time slots for walking
            let freeTimeSlots = await findFreeTimeWalkSlots(for: date)
            stepSlots.append(contentsOf: freeTimeSlots)

            // Set the best suggestion for display
            if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
                let bestWalkSlot = await findBestWalkSlot(for: date)
                await MainActor.run {
                    self.suggestedWalkSlot = bestWalkSlot
                }
            }
        }

        // Find workout slot if gym goal is set and no scheduled workout
        if !hasScheduledWorkout && userPreferences.hasWorkoutGoal && shouldSuggestGym(for: date) {
            let suggestedWorkout = await findBestWorkoutSlot(for: date)
            workoutSlot = suggestedWorkout

            if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
                await MainActor.run {
                    self.suggestedWorkoutSlot = suggestedWorkout
                }
            }
        }

        // Sort by time
        stepSlots.sort { $0.startTime < $1.startTime }

        let targetSteps = userPreferences.dailyStepGoal

        return DayMovementPlan(
            date: date,
            stepSlots: stepSlots,
            workoutSlot: workoutSlot,
            targetSteps: targetSteps,
            currentSteps: currentSteps
        )
    }

    // MARK: - Best Slot Finding (Based on Patterns)

    /// Find the best walk slot based on user's past patterns
    private func findBestWalkSlot(for date: Date) async -> StepSlot? {
        // First check if there's a pattern-based suggestion
        if let patternTime = scheduledActivityManager.getBestTimeSuggestion(for: .walk, on: date, duration: 30) {
            // Verify this time is still available
            let events = (try? await calendarManager.fetchEvents(for: date)) ?? []
            let conflictsWithEvent = events.contains { event in
                patternTime >= event.startDate && patternTime < event.endDate
            }

            if !conflictsWithEvent && userPreferences.isWithinBufferedActiveHours(patternTime) {
                let endTime = Calendar.current.date(byAdding: .minute, value: 30, to: patternTime) ?? patternTime
                return StepSlot(
                    startTime: patternTime,
                    endTime: endTime,
                    slotType: .freeTime,
                    targetSteps: 3000,
                    source: "Best time for you"
                )
            }
        }

        // Fall back to finding a free slot based on preference
        let freeSlots = await findFreeTimeWalkSlots(for: date)
        return freeSlots.first
    }

    // MARK: - Free Time Walk Slots

    private func findFreeTimeWalkSlots(for date: Date) async -> [StepSlot] {
        guard let freeSlots = try? await calendarManager.findFreeSlots(for: date, minimumDuration: 15) else {
            return []
        }

        // Check if it's a light day (few or no meetings)
        let events = (try? await calendarManager.fetchEvents(for: date)) ?? []
        let isLightDay = events.count <= 3

        var walkSlots: [StepSlot] = []
        let stepsPerMinute = 100 // Walking pace
        let calendar = Calendar.current
        let preferredWalkTime = userPreferences.preferredWalkTime

        for slot in freeSlots {
            // Skip if during meal time
            if userPreferences.isDuringMeal(slot.start) {
                continue
            }

            // Skip if outside buffered active hours (1 hour after wake, 1 hour before sleep)
            // Users can still manually add activities in these buffer times
            if !userPreferences.isWithinBufferedActiveHours(slot.start) {
                continue
            }

            // Limit to reasonable walk durations (15-45 mins)
            let duration = min(45, Int(slot.duration / 60))
            if duration < 15 {
                continue
            }

            let endTime = calendar.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end
            let hour = calendar.component(.hour, from: slot.start)

            // Determine source description based on time of day
            var source = "Walk break"
            if hour < 10 {
                source = "Morning walk"
            } else if hour < 14 {
                source = "Midday walk"
            } else if hour < 17 {
                source = "Afternoon walk"
            } else {
                source = "Evening walk"
            }

            let walkSlot = StepSlot(
                startTime: slot.start,
                endTime: endTime,
                slotType: .freeTime,
                targetSteps: duration * stepsPerMinute,
                source: source
            )
            walkSlots.append(walkSlot)
        }

        // Sort and filter based on preferred walk time
        let sortedSlots = sortWalkSlotsByPreference(walkSlots, preferredTime: preferredWalkTime, isLightDay: isLightDay)

        // Suggest more walk slots on light days
        let maxSlots = isLightDay ? 5 : 3
        return Array(sortedSlots.prefix(maxSlots))
    }

    /// Sort walk slots based on user's preferred walk time
    private func sortWalkSlotsByPreference(_ slots: [StepSlot], preferredTime: PreferredWalkTime, isLightDay: Bool) -> [StepSlot] {
        let calendar = Calendar.current

        switch preferredTime {
        case .morning:
            // Prioritize morning slots (5-10 AM), then sort by time within preference
            return slots.sorted { slot1, slot2 in
                let hour1 = calendar.component(.hour, from: slot1.startTime)
                let hour2 = calendar.component(.hour, from: slot2.startTime)
                let isMorning1 = hour1 >= 5 && hour1 < 10
                let isMorning2 = hour2 >= 5 && hour2 < 10

                if isMorning1 && !isMorning2 { return true }
                if !isMorning1 && isMorning2 { return false }
                return slot1.startTime < slot2.startTime
            }

        case .afternoon:
            // Prioritize afternoon slots (12-17), then sort by time
            return slots.sorted { slot1, slot2 in
                let hour1 = calendar.component(.hour, from: slot1.startTime)
                let hour2 = calendar.component(.hour, from: slot2.startTime)
                let isAfternoon1 = hour1 >= 12 && hour1 < 17
                let isAfternoon2 = hour2 >= 12 && hour2 < 17

                if isAfternoon1 && !isAfternoon2 { return true }
                if !isAfternoon1 && isAfternoon2 { return false }
                return slot1.startTime < slot2.startTime
            }

        case .evening:
            // Prioritize evening slots (17-21), then sort by time
            return slots.sorted { slot1, slot2 in
                let hour1 = calendar.component(.hour, from: slot1.startTime)
                let hour2 = calendar.component(.hour, from: slot2.startTime)
                let isEvening1 = hour1 >= 17 && hour1 < 21
                let isEvening2 = hour2 >= 17 && hour2 < 21

                if isEvening1 && !isEvening2 { return true }
                if !isEvening1 && isEvening2 { return false }
                return slot1.startTime < slot2.startTime
            }

        case .noPreference:
            // On light days, prioritize earlier slots to get steps in early
            // On busy days, just sort by time
            return slots.sorted { $0.startTime < $1.startTime }
        }
    }

    // MARK: - Gym Logic

    private func shouldSuggestGym(for date: Date) -> Bool {
        let calendar = Calendar.current

        // Check if we've already hit our gym goal this week
        if gymDaysThisWeek >= userPreferences.gymFrequency.rawValue {
            return false
        }

        // Check remaining days in week vs remaining gym sessions needed
        let weekday = calendar.component(.weekday, from: date)
        let daysLeftInWeek = 8 - weekday // Sunday = 1, Saturday = 7
        let gymSessionsNeeded = userPreferences.gymFrequency.rawValue - gymDaysThisWeek

        // If we need more sessions than days left, we should definitely suggest today
        if gymSessionsNeeded >= daysLeftInWeek {
            return true
        }

        return true
    }

    private func findBestWorkoutSlot(for date: Date) async -> WorkoutSlot? {
        guard let freeSlots = try? await calendarManager.findFreeSlots(
            for: date,
            minimumDuration: userPreferences.workoutDuration.rawValue
        ) else {
            return nil
        }

        let calendar = Calendar.current
        let preferredTime = userPreferences.preferredGymTime

        // Check if it's a light day
        let events = (try? await calendarManager.fetchEvents(for: date)) ?? []
        let isLightDay = events.count <= 3

        // Filter valid slots first
        let validSlots = freeSlots.filter { slot in
            // Skip if outside buffered active hours (1 hour after wake, 1 hour before sleep)
            // Users can still manually add activities in these buffer times
            if !userPreferences.isWithinBufferedActiveHours(slot.start) {
                return false
            }

            // Skip if during meal time
            if userPreferences.isDuringMeal(slot.start) {
                return false
            }

            return true
        }

        guard !validSlots.isEmpty else { return nil }

        // Find the best slot based on preference
        var bestSlot: DateInterval?

        switch preferredTime {
        case .morning:
            // Pick the earliest morning slot (5-10 AM)
            bestSlot = validSlots.first { slot in
                let hour = calendar.component(.hour, from: slot.start)
                return hour >= 5 && hour < 10
            } ?? validSlots.first // Fallback to first available

        case .afternoon:
            // Pick the earliest afternoon slot (12-17)
            bestSlot = validSlots.first { slot in
                let hour = calendar.component(.hour, from: slot.start)
                return hour >= 12 && hour < 17
            } ?? validSlots.first

        case .evening:
            // Pick the earliest evening slot (17-21)
            bestSlot = validSlots.first { slot in
                let hour = calendar.component(.hour, from: slot.start)
                return hour >= 17 && hour < 21
            } ?? validSlots.last // Fallback to last available (likely later in day)

        case .noPreference:
            if isLightDay {
                // On light days, pick early slot to get it done
                bestSlot = validSlots.first
            } else {
                // On busy days, prefer morning or evening
                bestSlot = validSlots.first { slot in
                    let hour = calendar.component(.hour, from: slot.start)
                    return (hour >= 5 && hour < 9) || (hour >= 17 && hour < 21)
                } ?? validSlots.first
            }
        }

        guard let selectedSlot = bestSlot else { return nil }

        let nextWorkoutType = getNextWorkoutType()
        let duration = userPreferences.workoutDuration.rawValue
        let endTime = calendar.date(byAdding: .minute, value: duration, to: selectedSlot.start) ?? selectedSlot.end

        return WorkoutSlot(
            startTime: selectedSlot.start,
            endTime: endTime,
            workoutType: nextWorkoutType,
            isRecommended: true
        )
    }

    func getNextWorkoutType() -> WorkoutType {
        switch lastWorkoutType {
        case .push: return .pull
        case .pull: return .legs
        case .legs: return .push
        default: return .push
        }
    }

    func markWorkoutCompleted(type: WorkoutType) {
        lastWorkoutType = type
        gymDaysThisWeek += 1
    }

    private func resetWeekIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        if weekStartDateTimestamp != weekStart.timeIntervalSince1970 {
            weekStartDateTimestamp = weekStart.timeIntervalSince1970
            gymDaysThisWeek = 0
        }
    }

    // MARK: - Learning (Rule-based)

    @AppStorage("morningWalkSuccess") private var morningWalkSuccessRate: Double = 0.5
    @AppStorage("eveningGymSuccess") private var eveningGymSuccessRate: Double = 0.5

    func recordWalkOutcome(wasSuccessful: Bool, timeOfDay: Int) {
        let alpha = 0.2
        if timeOfDay < 12 {
            morningWalkSuccessRate = alpha * (wasSuccessful ? 1.0 : 0.0) + (1 - alpha) * morningWalkSuccessRate
        }
    }

    func recordGymOutcome(wasSuccessful: Bool, timeOfDay: Int) {
        let alpha = 0.2
        if timeOfDay >= 17 {
            eveningGymSuccessRate = alpha * (wasSuccessful ? 1.0 : 0.0) + (1 - alpha) * eveningGymSuccessRate
        }
    }

    var shouldSuggestMorningWalks: Bool {
        morningWalkSuccessRate > 0.3
    }

    var shouldSuggestEveningGym: Bool {
        eveningGymSuccessRate > 0.3
    }
}
