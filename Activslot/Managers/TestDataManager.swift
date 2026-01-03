import Foundation
import HealthKit
import EventKit
import SwiftUI

#if DEBUG
/// A comprehensive test data manager for generating sample data across all app systems
/// Use this to test the app with realistic data scenarios
@MainActor
class TestDataManager: ObservableObject {
    static let shared = TestDataManager()

    private let healthStore = HKHealthStore()
    private let eventStore = EKEventStore()

    @Published var isGenerating = false
    @Published var lastGenerationStatus: String = ""
    @Published var generationLog: [String] = []

    private init() {}

    // MARK: - Main Test Data Generation

    /// Generates a complete test scenario with calendar events, HealthKit data, and scheduled activities
    func generateFullTestScenario() async {
        isGenerating = true
        generationLog = []

        log("Starting full test scenario generation...")

        // 1. Generate calendar events
        await generateCalendarEvents()

        // 2. Generate HealthKit step data
        await generateHealthKitData()

        // 3. Generate scheduled activities
        await generateScheduledActivities()

        // 4. Refresh all managers
        await refreshManagers()

        log("Test scenario generation complete!")
        lastGenerationStatus = "Generated: Calendar events, HealthKit data, Scheduled activities"
        isGenerating = false
    }

    /// Clears all test data
    func clearAllTestData() async {
        isGenerating = true
        generationLog = []

        log("Clearing all test data...")

        await clearCalendarEvents()
        await clearScheduledActivities()
        // Note: HealthKit data cannot be deleted programmatically

        await refreshManagers()

        log("Test data cleared!")
        lastGenerationStatus = "Cleared all test data"
        isGenerating = false
    }

    // MARK: - Calendar Events

    /// Generates a realistic executive calendar with meetings and gaps for walks
    func generateCalendarEvents() async {
        log("Generating calendar events...")

        do {
            try await CalendarManager.shared.createSampleEventsForTesting()
            log("  Created sample calendar events")
        } catch {
            log("  Failed to create calendar events: \(error.localizedDescription)")
        }
    }

    /// Generates calendar events for multiple days (today and tomorrow)
    func generateMultiDayCalendarEvents() async {
        log("Generating multi-day calendar events...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        // Today's events
        createEvent(on: today, calendar: calendar, title: "Morning Standup", startHour: 9, duration: 15, attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Product Planning", startHour: 9, startMinute: 30, duration: 60, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "1:1 with Manager", startHour: 11, duration: 30, attendeeCount: 2)
        createEvent(on: today, calendar: calendar, title: "Lunch Break", startHour: 12, duration: 60, attendeeCount: 0)
        createEvent(on: today, calendar: calendar, title: "Team Sync", startHour: 14, duration: 45, attendeeCount: 12)
        createEvent(on: today, calendar: calendar, title: "Code Review", startHour: 15, duration: 30, attendeeCount: 4)
        createEvent(on: today, calendar: calendar, title: "Engineering All-Hands", startHour: 16, duration: 60, attendeeCount: 50)

        // Tomorrow's events
        createEvent(on: tomorrow, calendar: calendar, title: "Sprint Planning", startHour: 9, duration: 90, attendeeCount: 10)
        createEvent(on: tomorrow, calendar: calendar, title: "Design Review", startHour: 11, duration: 45, attendeeCount: 6)
        createEvent(on: tomorrow, calendar: calendar, title: "Investor Call", startHour: 14, duration: 60, attendeeCount: 4)
        createEvent(on: tomorrow, calendar: calendar, title: "Focus Time", startHour: 15, startMinute: 30, duration: 120, attendeeCount: 0)

        log("  Created events for today and tomorrow")
    }

    /// Generates a heavy meeting day (for testing "too many meetings" scenario)
    func generateHeavyMeetingDay() async {
        log("Generating heavy meeting day...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Back-to-back meetings with minimal gaps
        createEvent(on: today, calendar: calendar, title: "Executive Standup", startHour: 8, duration: 30, attendeeCount: 6)
        createEvent(on: today, calendar: calendar, title: "Board Prep", startHour: 8, startMinute: 30, duration: 60, attendeeCount: 3)
        createEvent(on: today, calendar: calendar, title: "Investor Meeting", startHour: 9, startMinute: 30, duration: 90, attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Lunch & Learn", startHour: 11, duration: 60, attendeeCount: 20)
        createEvent(on: today, calendar: calendar, title: "Product Strategy", startHour: 12, duration: 90, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "Engineering Review", startHour: 13, startMinute: 30, duration: 60, attendeeCount: 15)
        createEvent(on: today, calendar: calendar, title: "Customer Call", startHour: 14, startMinute: 30, duration: 60, attendeeCount: 4)
        createEvent(on: today, calendar: calendar, title: "Team Retrospective", startHour: 15, startMinute: 30, duration: 60, attendeeCount: 10)
        createEvent(on: today, calendar: calendar, title: "Planning Poker", startHour: 16, startMinute: 30, duration: 60, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "End of Day Sync", startHour: 17, startMinute: 30, duration: 30, attendeeCount: 5)

        log("  Created heavy meeting schedule (8+ hours of meetings)")
    }

    /// Generates a light meeting day (for testing "plenty of walk time" scenario)
    func generateLightMeetingDay() async {
        log("Generating light meeting day...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Just a few meetings with lots of free time
        createEvent(on: today, calendar: calendar, title: "Morning Check-in", startHour: 9, duration: 15, attendeeCount: 3)
        createEvent(on: today, calendar: calendar, title: "1:1 with Report", startHour: 14, duration: 30, attendeeCount: 2)
        createEvent(on: today, calendar: calendar, title: "Team Update", startHour: 16, duration: 30, attendeeCount: 6)

        log("  Created light meeting schedule (~1 hour of meetings)")
    }

    /// Creates events with walkable meetings (large attendee count, not organizer)
    func generateWalkableMeetings() async {
        log("Generating walkable meetings...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Create meetings that qualify as "walkable" (4+ attendees, 20-120 min, not organizer)
        createEvent(on: today, calendar: calendar, title: "All-Hands Meeting", startHour: 10, duration: 60, attendeeCount: 50)
        createEvent(on: today, calendar: calendar, title: "Department Sync", startHour: 14, duration: 45, attendeeCount: 15)
        createEvent(on: today, calendar: calendar, title: "Training Session", startHour: 16, duration: 90, attendeeCount: 25)

        log("  Created 3 walkable meetings")
    }

    private func createEvent(on date: Date, calendar: EKCalendar, title: String, startHour: Int, startMinute: Int = 0, duration: Int, attendeeCount: Int) {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = calendar

        var startComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = startHour
        startComponents.minute = startMinute

        event.startDate = Calendar.current.date(from: startComponents)!
        event.endDate = Calendar.current.date(byAdding: .minute, value: duration, to: event.startDate)!

        // Note: We can't add attendees programmatically, but the title affects walkability

        try? eventStore.save(event, span: .thisEvent)
    }

    func clearCalendarEvents() async {
        log("Clearing calendar events...")

        do {
            try await CalendarManager.shared.clearTodayEvents()
            log("  Cleared today's calendar events")
        } catch {
            log("  Failed to clear events: \(error.localizedDescription)")
        }
    }

    // MARK: - HealthKit Data

    /// Generates sample step data for the past week and today
    func generateHealthKitData() async {
        log("Generating HealthKit data...")

        guard HKHealthStore.isHealthDataAvailable() else {
            log("  HealthKit not available")
            return
        }

        // Request write authorization
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        do {
            try await healthStore.requestAuthorization(toShare: [stepType], read: [stepType])
        } catch {
            log("  HealthKit authorization failed: \(error.localizedDescription)")
            return
        }

        let calendar = Calendar.current

        // Generate historical data for the past 7 days
        for dayOffset in 1...7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                // Vary steps by day (weekends lower, weekdays higher)
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7
                let baseSteps = isWeekend ? 5000 : 8000
                let variation = Int.random(in: -2000...3000)
                let steps = max(3000, baseSteps + variation)

                await saveSteps(steps, for: date)
            }
        }

        // Generate today's steps (partial day)
        let hour = calendar.component(.hour, from: Date())
        let todaySteps = Int(Double(hour) / 24.0 * 8000.0) + Int.random(in: 0...1500)
        await saveStepsForToday(todaySteps)

        log("  Generated step data for 7 days + today (\(todaySteps) steps so far)")
    }

    /// Generates step data for a specific scenario
    func generateStepScenario(_ scenario: StepScenario) async {
        log("Generating \(scenario.rawValue) step scenario...")

        switch scenario {
        case .goalAlmostReached:
            await saveStepsForToday(8500) // Just 1500 from 10k goal
        case .goalReached:
            await saveStepsForToday(10500) // Over the goal
        case .lowSteps:
            await saveStepsForToday(2000) // Very few steps
        case .midDay:
            await saveStepsForToday(5000) // Half way there
        case .activeWalker:
            await saveStepsForToday(15000) // Very active
        }

        log("  Set today's steps to \(scenario.targetSteps)")
    }

    enum StepScenario: String, CaseIterable {
        case goalAlmostReached = "Goal Almost Reached"
        case goalReached = "Goal Reached"
        case lowSteps = "Low Steps"
        case midDay = "Mid Day Progress"
        case activeWalker = "Active Walker"

        var targetSteps: Int {
            switch self {
            case .goalAlmostReached: return 8500
            case .goalReached: return 10500
            case .lowSteps: return 2000
            case .midDay: return 5000
            case .activeWalker: return 15000
            }
        }
    }

    private func saveSteps(_ steps: Int, for date: Date) async {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let quantity = HKQuantity(unit: .count(), doubleValue: Double(steps))

        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .hour, value: 23, to: startOfDay)!

        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: startOfDay, end: endOfDay)

        do {
            try await healthStore.save(sample)
        } catch {
            log("  Failed to save steps for \(date): \(error.localizedDescription)")
        }
    }

    private func saveStepsForToday(_ steps: Int) async {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        // Check authorization status
        let authStatus = healthStore.authorizationStatus(for: stepType)
        log("  HealthKit write auth status: \(authStatus.rawValue)")

        // Request authorization if needed
        do {
            try await healthStore.requestAuthorization(toShare: [stepType], read: [stepType])
            log("  HealthKit authorization requested")
        } catch {
            log("  HealthKit authorization failed: \(error.localizedDescription)")
            return
        }

        let quantity = HKQuantity(unit: .count(), doubleValue: Double(steps))

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now = Date()

        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: startOfDay, end: now)

        do {
            try await healthStore.save(sample)
            log("  Saved \(steps) steps to HealthKit")
        } catch {
            log("  Failed to save today's steps: \(error.localizedDescription)")
        }
    }

    /// Generates walking workout data
    func generateWalkWorkouts() async {
        log("Generating walk workout data...")

        guard HKHealthStore.isHealthDataAvailable() else {
            log("  HealthKit not available")
            return
        }

        let workoutType = HKQuantityType.workoutType()

        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType])
        } catch {
            log("  HealthKit workout authorization failed")
            return
        }

        let calendar = Calendar.current

        // Create some past walking workouts
        for dayOffset in [1, 3, 5] {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                var startComps = calendar.dateComponents([.year, .month, .day], from: date)
                startComps.hour = 12
                startComps.minute = 30

                let startDate = calendar.date(from: startComps)!
                let endDate = calendar.date(byAdding: .minute, value: 30, to: startDate)!

                let workout = HKWorkout(
                    activityType: .walking,
                    start: startDate,
                    end: endDate,
                    duration: 30 * 60, // 30 minutes
                    totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 150),
                    totalDistance: HKQuantity(unit: .mile(), doubleValue: 1.5),
                    metadata: nil
                )

                try? await healthStore.save(workout)
            }
        }

        log("  Created 3 walking workouts for past week")
    }

    // MARK: - Scheduled Activities

    /// Generates sample scheduled activities (walks and workouts)
    func generateScheduledActivities() async {
        log("Generating scheduled activities...")

        let manager = ScheduledActivityManager.shared

        // Clear existing test activities
        await clearScheduledActivities()

        let calendar = Calendar.current
        let today = Date()

        // Create a morning walk scheduled for today
        var morningComponents = calendar.dateComponents([.year, .month, .day], from: today)
        morningComponents.hour = 7
        morningComponents.minute = 30
        if let morningTime = calendar.date(from: morningComponents) {
            let morningWalk = ScheduledActivity(
                activityType: .walk,
                title: "Morning Walk",
                startTime: morningTime,
                duration: 20,
                recurrence: .weekdays
            )
            manager.addScheduledActivity(morningWalk)
        }

        // Create a lunch walk for today
        var lunchComponents = calendar.dateComponents([.year, .month, .day], from: today)
        lunchComponents.hour = 12
        lunchComponents.minute = 0
        if let lunchTime = calendar.date(from: lunchComponents) {
            let lunchWalk = ScheduledActivity(
                activityType: .walk,
                title: "Lunch Walk",
                startTime: lunchTime,
                duration: 30,
                recurrence: .once
            )
            manager.addScheduledActivity(lunchWalk)
        }

        // Create an afternoon workout
        var workoutComponents = calendar.dateComponents([.year, .month, .day], from: today)
        workoutComponents.hour = 17
        workoutComponents.minute = 30
        if let workoutTime = calendar.date(from: workoutComponents) {
            let workout = ScheduledActivity(
                activityType: .workout,
                workoutType: .push,
                title: "Gym Session - Push Day",
                startTime: workoutTime,
                duration: 45,
                recurrence: .weekly
            )
            manager.addScheduledActivity(workout)
        }

        log("  Created 2 walks and 1 workout")
    }

    /// Generates activities that conflict with calendar events
    func generateConflictingActivities() async {
        log("Generating conflicting activities...")

        let manager = ScheduledActivityManager.shared
        let calendar = Calendar.current
        let today = Date()

        // Create a walk that conflicts with the 10 AM meeting slot
        var conflictComponents = calendar.dateComponents([.year, .month, .day], from: today)
        conflictComponents.hour = 10
        conflictComponents.minute = 0
        if let conflictTime = calendar.date(from: conflictComponents) {
            let conflictingWalk = ScheduledActivity(
                activityType: .walk,
                title: "Walk (Conflicts with Meeting!)",
                startTime: conflictTime,
                duration: 30,
                recurrence: .once
            )
            manager.addScheduledActivity(conflictingWalk)
        }

        log("  Created 1 conflicting activity")
    }

    func clearScheduledActivities() async {
        log("Clearing scheduled activities...")

        let manager = ScheduledActivityManager.shared

        // For test scenarios, clear ALL activities to prevent duplicates
        // This includes both one-time and recurring activities
        let allActivities = manager.scheduledActivities
        for activity in allActivities {
            manager.deleteScheduledActivity(activity)
        }

        log("  Cleared all scheduled activities (\(allActivities.count) total)")
    }

    // MARK: - Preset Test Scenarios

    /// Scenario: Busy executive with back-to-back meetings
    func setupBusyExecutiveScenario() async {
        log("Setting up Busy Executive scenario...")

        await clearAllTestData()
        await generateHeavyMeetingDay()
        await generateStepScenario(.lowSteps)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Busy Executive scenario ready")
        lastGenerationStatus = "Busy Executive: Heavy meetings, few steps"
    }

    /// Scenario: Light day with lots of walking opportunities
    func setupLightDayScenario() async {
        log("Setting up Light Day scenario...")

        await clearAllTestData()
        await generateLightMeetingDay()
        await generateStepScenario(.midDay)
        await generateScheduledActivities()

        // Refresh managers after generating new data
        await refreshManagers()

        log("Light Day scenario ready")
        lastGenerationStatus = "Light Day: Few meetings, walking opportunities"
    }

    /// Scenario: Goal almost reached, needs one more walk
    func setupAlmostThereScenario() async {
        log("Setting up Almost There scenario...")

        await clearAllTestData()
        await generateCalendarEvents()
        await generateStepScenario(.goalAlmostReached)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Almost There scenario ready")
        lastGenerationStatus = "Almost There: 8,500 steps, need 1,500 more"
    }

    /// Scenario: Active day with goal already reached
    func setupGoalReachedScenario() async {
        log("Setting up Goal Reached scenario...")

        await clearAllTestData()
        await generateCalendarEvents()
        await generateStepScenario(.goalReached)
        await generateWalkWorkouts()

        // Refresh managers after generating new data
        await refreshManagers()

        log("Goal Reached scenario ready")
        lastGenerationStatus = "Goal Reached: Over 10,000 steps"
    }

    /// Scenario: Multiple walkable meetings available
    func setupWalkableMeetingsScenario() async {
        log("Setting up Walkable Meetings scenario...")

        await clearAllTestData()
        await generateWalkableMeetings()
        await generateStepScenario(.lowSteps)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Walkable Meetings scenario ready")
        lastGenerationStatus = "Walkable Meetings: 3 meetings good for walking"
    }

    // MARK: - Manager Refresh

    private func refreshManagers() async {
        log("Refreshing managers...")

        // Refresh calendar
        try? await CalendarManager.shared.refreshEvents()

        // Refresh health data
        _ = try? await HealthKitManager.shared.fetchTodaySteps()

        // Regenerate plans
        await MovementPlanManager.shared.generatePlans()

        // Update insights
        await PersonalInsightsManager.shared.analyzePatterns()

        log("  All managers refreshed")
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("TestDataManager: \(message)")
        generationLog.append(message)
    }
}

// MARK: - Test Data View for Debug Menu

struct TestDataGeneratorView: View {
    @StateObject private var testManager = TestDataManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section("Status") {
                    if testManager.isGenerating {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Generating...")
                        }
                    } else if !testManager.lastGenerationStatus.isEmpty {
                        Text(testManager.lastGenerationStatus)
                            .foregroundColor(.green)
                    }
                }

                // Quick Scenarios
                Section("Quick Scenarios") {
                    Button("Busy Executive Day") {
                        Task { await testManager.setupBusyExecutiveScenario() }
                    }

                    Button("Light Day (Lots of Walk Time)") {
                        Task { await testManager.setupLightDayScenario() }
                    }

                    Button("Almost at Goal (8,500 steps)") {
                        Task { await testManager.setupAlmostThereScenario() }
                    }

                    Button("Goal Reached (10,500 steps)") {
                        Task { await testManager.setupGoalReachedScenario() }
                    }

                    Button("Walkable Meetings Available") {
                        Task { await testManager.setupWalkableMeetingsScenario() }
                    }
                }

                // Individual Data Generation
                Section("Calendar Events") {
                    Button("Create Standard Day Events") {
                        Task { await testManager.generateCalendarEvents() }
                    }

                    Button("Create Multi-Day Events") {
                        Task { await testManager.generateMultiDayCalendarEvents() }
                    }

                    Button("Create Heavy Meeting Day") {
                        Task { await testManager.generateHeavyMeetingDay() }
                    }

                    Button("Create Light Meeting Day") {
                        Task { await testManager.generateLightMeetingDay() }
                    }

                    Button("Create Walkable Meetings") {
                        Task { await testManager.generateWalkableMeetings() }
                    }

                    Button("Clear Today's Events", role: .destructive) {
                        Task { await testManager.clearCalendarEvents() }
                    }
                }

                Section("HealthKit Data") {
                    Button("Generate Week of Step Data") {
                        Task { await testManager.generateHealthKitData() }
                    }

                    Button("Generate Walk Workouts") {
                        Task { await testManager.generateWalkWorkouts() }
                    }

                    ForEach(TestDataManager.StepScenario.allCases, id: \.self) { scenario in
                        Button("Set Steps: \(scenario.rawValue)") {
                            Task { await testManager.generateStepScenario(scenario) }
                        }
                    }
                }

                Section("Scheduled Activities") {
                    Button("Create Sample Activities") {
                        Task { await testManager.generateScheduledActivities() }
                    }

                    Button("Create Conflicting Activity") {
                        Task { await testManager.generateConflictingActivities() }
                    }

                    Button("Clear Scheduled Activities", role: .destructive) {
                        Task { await testManager.clearScheduledActivities() }
                    }
                }

                // Full Operations
                Section("Full Operations") {
                    Button("Generate Full Test Data") {
                        Task { await testManager.generateFullTestScenario() }
                    }
                    .foregroundColor(.blue)

                    Button("Clear All Test Data", role: .destructive) {
                        Task { await testManager.clearAllTestData() }
                    }
                }

                // Log Output
                if !testManager.generationLog.isEmpty {
                    Section("Log") {
                        ForEach(testManager.generationLog.indices, id: \.self) { index in
                            Text(testManager.generationLog[index])
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Test Data Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .disabled(testManager.isGenerating)
        }
    }
}

#Preview {
    TestDataGeneratorView()
}
#endif
