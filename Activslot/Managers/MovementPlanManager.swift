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

        // SECOND: If no scheduled activities, use smart allocation
        let hasScheduledWalk = !scheduledWalks.isEmpty
        let hasScheduledWorkout = !scheduledWorkouts.isEmpty
        let needsWalkSuggestion = !hasScheduledWalk
        let needsWorkoutSuggestion = !hasScheduledWorkout && userPreferences.hasWorkoutGoal && shouldSuggestGym(for: date)

        if needsWalkSuggestion || needsWorkoutSuggestion {
            // Smart allocation: find 1-hour+ breaks and allocate intelligently
            let allocation = await smartAllocateSlots(
                for: date,
                events: calendarEvents,
                needsWalk: needsWalkSuggestion,
                needsWorkout: needsWorkoutSuggestion
            )

            // Set the suggested workout slot
            if needsWorkoutSuggestion {
                workoutSlot = allocation.workoutSlot

                if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
                    await MainActor.run {
                        self.suggestedWorkoutSlot = allocation.workoutSlot
                    }
                }
            }

            // Set the suggested walk slot
            if needsWalkSuggestion {
                if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
                    await MainActor.run {
                        self.suggestedWalkSlot = allocation.walkSlot
                    }
                }

                // Add the suggested walk slot to stepSlots
                if let walkSlot = allocation.walkSlot {
                    stepSlots.append(walkSlot)
                }

                // Add walkable meetings as additional options
                stepSlots.append(contentsOf: allocation.walkableMeetings)

                // Add other free time slots (not used for workout or main walk)
                stepSlots.append(contentsOf: allocation.otherWalkSlots)
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

    // MARK: - Smart Slot Allocation

    /// Result of smart slot allocation
    private struct SlotAllocation {
        var workoutSlot: WorkoutSlot?
        var walkSlot: StepSlot?
        var walkableMeetings: [StepSlot]
        var otherWalkSlots: [StepSlot]
    }

    /// Smart allocation of slots based on available 1-hour breaks
    private func smartAllocateSlots(
        for date: Date,
        events: [CalendarEvent],
        needsWalk: Bool,
        needsWorkout: Bool
    ) async -> SlotAllocation {
        let calendar = Calendar.current
        let workoutDuration = userPreferences.workoutDuration.rawValue

        // Find all free slots (minimum 45 minutes for walks, 60 for workouts)
        let allFreeSlots = (try? await calendarManager.findFreeSlots(for: date, minimumDuration: 45)) ?? []

        // Filter to valid slots (within active hours, not during meals)
        let validFreeSlots = allFreeSlots.filter { slot in
            userPreferences.isWithinBufferedActiveHours(slot.start) &&
            !userPreferences.isDuringMeal(slot.start)
        }

        // Separate into 1-hour+ slots and shorter slots
        let oneHourSlots = validFreeSlots.filter { Int($0.duration / 60) >= 60 }
        let shorterSlots = validFreeSlots.filter { Int($0.duration / 60) >= 45 && Int($0.duration / 60) < 60 }

        // Get walkable meetings
        var walkableMeetings: [StepSlot] = []
        if let meetings = try? await calendarManager.getWalkableMeetings(for: date) {
            for meeting in meetings {
                if userPreferences.isDuringMeal(meeting.startDate) { continue }
                if !userPreferences.isWithinBufferedActiveHours(meeting.startDate) { continue }

                walkableMeetings.append(StepSlot(
                    startTime: meeting.startDate,
                    endTime: meeting.endDate,
                    slotType: .walkableMeeting,
                    targetSteps: meeting.estimatedSteps,
                    source: meeting.title
                ))
            }
        }

        var result = SlotAllocation(
            workoutSlot: nil,
            walkSlot: nil,
            walkableMeetings: walkableMeetings,
            otherWalkSlots: []
        )

        // Smart allocation logic
        if oneHourSlots.isEmpty {
            // NO 1-hour breaks available
            // Workout: Try to fit in shorter slots if duration allows
            if needsWorkout {
                let workoutFitSlots = shorterSlots.filter { Int($0.duration / 60) >= workoutDuration }
                if let bestWorkoutSlot = selectBestSlotForWorkout(from: workoutFitSlots) {
                    result.workoutSlot = createWorkoutSlot(from: bestWorkoutSlot)
                }
            }

            // Walk: Use walkable meetings as primary suggestion
            if needsWalk {
                if let bestWalkableMeeting = walkableMeetings.first {
                    result.walkSlot = bestWalkableMeeting
                } else if let firstShortSlot = shorterSlots.first {
                    // Use first short slot for walk if no workout used it
                    if result.workoutSlot == nil || firstShortSlot.start != result.workoutSlot?.startTime {
                        result.walkSlot = createWalkSlot(from: firstShortSlot)
                    }
                }
            }

        } else if oneHourSlots.count == 1 {
            // ONLY ONE 1-hour break available
            let theOneSlot = oneHourSlots[0]

            if needsWorkout {
                // Prioritize workout for the only 1-hour slot
                result.workoutSlot = createWorkoutSlot(from: theOneSlot)

                // Walk: Use walkable meetings
                if needsWalk {
                    if let bestWalkableMeeting = walkableMeetings.first {
                        result.walkSlot = bestWalkableMeeting
                    } else if let shortSlot = shorterSlots.first {
                        result.walkSlot = createWalkSlot(from: shortSlot)
                    }
                }
            } else if needsWalk {
                // No workout needed, use 1-hour slot for walk
                result.walkSlot = createWalkSlot(from: theOneSlot)
            }

        } else {
            // TWO OR MORE 1-hour breaks available
            // Allocate one for workout (based on preference), another for walk

            if needsWorkout {
                // Select best slot for workout based on user preference
                let bestWorkoutSlot = selectBestSlotForWorkout(from: oneHourSlots)
                if let workoutInterval = bestWorkoutSlot {
                    result.workoutSlot = createWorkoutSlot(from: workoutInterval)
                }
            }

            if needsWalk {
                // Select best slot for walk (different from workout slot)
                let workoutStart = result.workoutSlot?.startTime
                let availableForWalk = oneHourSlots.filter { slot in
                    workoutStart == nil || slot.start != workoutStart
                }

                let bestWalkSlot = selectBestSlotForWalk(from: availableForWalk)
                if let walkInterval = bestWalkSlot {
                    result.walkSlot = createWalkSlot(from: walkInterval)
                }

                // Add remaining 1-hour slots as other walk options
                let usedSlots = [result.workoutSlot?.startTime, result.walkSlot?.startTime].compactMap { $0 }
                let remainingSlots = oneHourSlots.filter { slot in
                    !usedSlots.contains(slot.start)
                }
                result.otherWalkSlots = remainingSlots.prefix(2).map { createWalkSlot(from: $0) }
            }
        }

        // If still no walk slot, try to create one based on preferred time (for no-meeting days)
        if needsWalk && result.walkSlot == nil {
            if let preferredSlot = createPreferredTimeWalkSlot(for: date, events: events) {
                result.walkSlot = preferredSlot
            }
        }

        // If still no workout slot, try to create one based on preferred time
        if needsWorkout && result.workoutSlot == nil {
            if let preferredSlot = createPreferredTimeWorkoutSlot(for: date, events: events) {
                result.workoutSlot = preferredSlot
            }
        }

        return result
    }

    /// Select the best slot for workout based on user preference
    private func selectBestSlotForWorkout(from slots: [DateInterval]) -> DateInterval? {
        guard !slots.isEmpty else { return nil }

        let calendar = Calendar.current
        let preferredTime = userPreferences.preferredGymTime

        // Sort by preference match
        let sorted = slots.sorted { slot1, slot2 in
            let hour1 = calendar.component(.hour, from: slot1.start)
            let hour2 = calendar.component(.hour, from: slot2.start)

            let score1 = preferenceScore(hour: hour1, for: preferredTime)
            let score2 = preferenceScore(hour: hour2, for: preferredTime)

            if score1 != score2 {
                return score1 > score2
            }
            return slot1.start < slot2.start
        }

        return sorted.first
    }

    /// Select the best slot for walk based on user preference
    private func selectBestSlotForWalk(from slots: [DateInterval]) -> DateInterval? {
        guard !slots.isEmpty else { return nil }

        let calendar = Calendar.current
        let preferredTime = userPreferences.preferredWalkTime

        // Sort by preference match
        let sorted = slots.sorted { slot1, slot2 in
            let hour1 = calendar.component(.hour, from: slot1.start)
            let hour2 = calendar.component(.hour, from: slot2.start)

            let score1 = walkPreferenceScore(hour: hour1, for: preferredTime)
            let score2 = walkPreferenceScore(hour: hour2, for: preferredTime)

            if score1 != score2 {
                return score1 > score2
            }
            return slot1.start < slot2.start
        }

        return sorted.first
    }

    /// Score a slot hour based on gym preference (higher = better match)
    private func preferenceScore(hour: Int, for preference: PreferredGymTime) -> Int {
        switch preference {
        case .morning:
            if hour >= 5 && hour < 10 { return 3 }
            if hour >= 10 && hour < 12 { return 1 }
            return 0
        case .afternoon:
            if hour >= 12 && hour < 17 { return 3 }
            return 0
        case .evening:
            if hour >= 17 && hour < 21 { return 3 }
            return 0
        case .noPreference:
            // Prefer morning or evening
            if hour >= 6 && hour < 9 { return 2 }
            if hour >= 17 && hour < 20 { return 2 }
            return 1
        }
    }

    /// Score a slot hour based on walk preference (higher = better match)
    private func walkPreferenceScore(hour: Int, for preference: PreferredWalkTime) -> Int {
        switch preference {
        case .morning:
            if hour >= 6 && hour < 10 { return 3 }
            if hour >= 10 && hour < 12 { return 1 }
            return 0
        case .afternoon:
            if hour >= 12 && hour < 17 { return 3 }
            return 0
        case .evening:
            if hour >= 17 && hour < 21 { return 3 }
            return 0
        case .noPreference:
            return 1
        }
    }

    /// Create a WorkoutSlot from a DateInterval
    private func createWorkoutSlot(from interval: DateInterval) -> WorkoutSlot {
        let duration = userPreferences.workoutDuration.rawValue
        let endTime = Calendar.current.date(byAdding: .minute, value: duration, to: interval.start) ?? interval.end

        return WorkoutSlot(
            startTime: interval.start,
            endTime: endTime,
            workoutType: getNextWorkoutType(),
            isRecommended: true
        )
    }

    /// Create a StepSlot (walk) from a DateInterval
    private func createWalkSlot(from interval: DateInterval) -> StepSlot {
        let calendar = Calendar.current
        let duration = min(45, Int(interval.duration / 60)) // Max 45 min walk
        let endTime = calendar.date(byAdding: .minute, value: duration, to: interval.start) ?? interval.end
        let hour = calendar.component(.hour, from: interval.start)

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

        return StepSlot(
            startTime: interval.start,
            endTime: endTime,
            slotType: .freeTime,
            targetSteps: duration * 100,
            source: source
        )
    }

    // MARK: - Preferred Time Slot Creation (Fallback for no-meeting days)

    /// Create a walk slot based on user's preferred walk time
    private func createPreferredTimeWalkSlot(for date: Date, events: [CalendarEvent]) -> StepSlot? {
        let calendar = Calendar.current
        let preferredTime = userPreferences.preferredWalkTime

        // Determine the ideal start hour based on preference
        let idealHour: Int
        let slotDescription: String

        switch preferredTime {
        case .morning:
            // After workout if both morning, or early morning
            if userPreferences.preferredGymTime == .morning && userPreferences.hasWorkoutGoal {
                // Walk after workout: 7 AM workout (1hr) -> 8 AM walk
                idealHour = 8
            } else {
                idealHour = 7
            }
            slotDescription = "Morning walk"
        case .afternoon:
            idealHour = 13 // 1 PM
            slotDescription = "Afternoon walk"
        case .evening:
            idealHour = 18 // 6 PM
            slotDescription = "Evening walk"
        case .noPreference:
            // Default to morning
            idealHour = 8
            slotDescription = "Morning walk"
        }

        // Create the preferred time slot
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = idealHour
        components.minute = 0

        guard let startTime = calendar.date(from: components) else { return nil }

        // Duration for 10k steps goal: ~100 steps/min, so 60-90 min walk
        // But we'll suggest 45 min as a reasonable walk
        let walkDuration = 45
        guard let endTime = calendar.date(byAdding: .minute, value: walkDuration, to: startTime) else { return nil }

        // Check if this conflicts with any event
        let conflictsWithEvent = events.contains { event in
            // Check if walk slot overlaps with event
            (startTime < event.endDate && endTime > event.startDate)
        }

        if conflictsWithEvent {
            // Try to find next available slot in the preferred time range
            return findNextAvailableSlotInPreferredRange(for: date, events: events, preferredTime: preferredTime)
        }

        // Verify within active hours
        guard userPreferences.isWithinBufferedActiveHours(startTime) else { return nil }

        // Skip meal times
        if userPreferences.isDuringMeal(startTime) {
            return findNextAvailableSlotInPreferredRange(for: date, events: events, preferredTime: preferredTime)
        }

        return StepSlot(
            startTime: startTime,
            endTime: endTime,
            slotType: .freeTime,
            targetSteps: walkDuration * 100, // 100 steps per minute
            source: slotDescription
        )
    }

    /// Find next available slot within the preferred time range
    private func findNextAvailableSlotInPreferredRange(for date: Date, events: [CalendarEvent], preferredTime: PreferredWalkTime) -> StepSlot? {
        let calendar = Calendar.current

        // Define the preferred time range
        let (rangeStart, rangeEnd, description): (Int, Int, String)
        switch preferredTime {
        case .morning:
            rangeStart = 6
            rangeEnd = 11
            description = "Morning walk"
        case .afternoon:
            rangeStart = 12
            rangeEnd = 17
            description = "Afternoon walk"
        case .evening:
            rangeStart = 17
            rangeEnd = 21
            description = "Evening walk"
        case .noPreference:
            rangeStart = 7
            rangeEnd = 20
            description = "Walk break"
        }

        // Try each hour in the range
        for hour in rangeStart..<rangeEnd {
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = 0

            guard let startTime = calendar.date(from: components),
                  let endTime = calendar.date(byAdding: .minute, value: 45, to: startTime) else {
                continue
            }

            // Skip if outside active hours
            guard userPreferences.isWithinBufferedActiveHours(startTime) else { continue }

            // Skip meal times
            if userPreferences.isDuringMeal(startTime) { continue }

            // Check for conflicts
            let conflicts = events.contains { event in
                startTime < event.endDate && endTime > event.startDate
            }

            if !conflicts {
                return StepSlot(
                    startTime: startTime,
                    endTime: endTime,
                    slotType: .freeTime,
                    targetSteps: 4500, // 45 min * 100 steps
                    source: description
                )
            }
        }

        return nil
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

    /// Create a workout slot based on user's preferred gym time
    private func createPreferredTimeWorkoutSlot(for date: Date, events: [CalendarEvent]) -> WorkoutSlot? {
        let calendar = Calendar.current
        let preferredTime = userPreferences.preferredGymTime
        let duration = userPreferences.workoutDuration.rawValue
        let nextWorkoutType = getNextWorkoutType()

        // Determine the ideal start hour based on preference
        let idealHour: Int

        switch preferredTime {
        case .morning:
            // Morning workout at 7 AM (before walk if both morning)
            idealHour = 7
        case .afternoon:
            idealHour = 13 // 1 PM
        case .evening:
            idealHour = 18 // 6 PM
        case .noPreference:
            // Default to morning
            idealHour = 7
        }

        // Create the preferred time slot
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = idealHour
        components.minute = 0

        guard let startTime = calendar.date(from: components),
              let endTime = calendar.date(byAdding: .minute, value: duration, to: startTime) else {
            return nil
        }

        // Check if this conflicts with any event
        let conflictsWithEvent = events.contains { event in
            (startTime < event.endDate && endTime > event.startDate)
        }

        if conflictsWithEvent {
            return findNextAvailableWorkoutSlot(for: date, events: events, preferredTime: preferredTime)
        }

        // Verify within active hours
        guard userPreferences.isWithinBufferedActiveHours(startTime) else { return nil }

        // Skip meal times
        if userPreferences.isDuringMeal(startTime) {
            return findNextAvailableWorkoutSlot(for: date, events: events, preferredTime: preferredTime)
        }

        return WorkoutSlot(
            startTime: startTime,
            endTime: endTime,
            workoutType: nextWorkoutType,
            isRecommended: true
        )
    }

    /// Find next available workout slot within the preferred time range
    private func findNextAvailableWorkoutSlot(for date: Date, events: [CalendarEvent], preferredTime: PreferredGymTime) -> WorkoutSlot? {
        let calendar = Calendar.current
        let duration = userPreferences.workoutDuration.rawValue
        let nextWorkoutType = getNextWorkoutType()

        // Define the preferred time range
        let (rangeStart, rangeEnd): (Int, Int)
        switch preferredTime {
        case .morning:
            rangeStart = 5
            rangeEnd = 11
        case .afternoon:
            rangeStart = 12
            rangeEnd = 17
        case .evening:
            rangeStart = 17
            rangeEnd = 21
        case .noPreference:
            rangeStart = 6
            rangeEnd = 21
        }

        // Try each hour in the range
        for hour in rangeStart..<rangeEnd {
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = 0

            guard let startTime = calendar.date(from: components),
                  let endTime = calendar.date(byAdding: .minute, value: duration, to: startTime) else {
                continue
            }

            // Skip if outside active hours
            guard userPreferences.isWithinBufferedActiveHours(startTime) else { continue }

            // Skip meal times
            if userPreferences.isDuringMeal(startTime) { continue }

            // Check for conflicts
            let conflicts = events.contains { event in
                startTime < event.endDate && endTime > event.startDate
            }

            if !conflicts {
                return WorkoutSlot(
                    startTime: startTime,
                    endTime: endTime,
                    workoutType: nextWorkoutType,
                    isRecommended: true
                )
            }
        }

        return nil
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
