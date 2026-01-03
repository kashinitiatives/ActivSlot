import SwiftUI

struct HomeView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var calendarManager: CalendarManager
    @StateObject private var planManager = MovementPlanManager.shared
    @StateObject private var insightsManager = PersonalInsightsManager.shared
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared
    @StateObject private var activityStore = ActivityStore.shared
    @StateObject private var streakManager = StreakManager.shared

    // Trigger to reset to Today tab when bottom tab is tapped
    var resetToTodayTrigger: Int = 0

    @State private var isRefreshing = false
    @State private var showWorkoutSetup = false
    @State private var showCalendarView = false
    @State private var showScheduleWalk = false
    @State private var showScheduleWorkout = false
    @State private var showScheduledActivities = false
    @State private var customTimeRequest: CustomTimeRequest?
    @State private var conflictToResolve: ScheduleConflict?
    @State private var selectedDay: SelectedDay = .today
    @State private var slotToSchedule: StepSlot?
    @State private var workoutToSchedule: WorkoutSlot?

    enum SelectedDay {
        case today, tomorrow
    }

    struct CustomTimeRequest: Identifiable {
        let id = UUID()
        let activityType: ActivityType
        let date: Date
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Day Selector
                    DaySelector(selectedDay: $selectedDay)

                    // Step Progress Card
                    StepProgressCard(
                        currentSteps: healthKitManager.todaySteps,
                        goalSteps: userPreferences.dailyStepGoal,
                        isToday: selectedDay == .today
                    )

                    // Streak Card (only for Today)
                    if selectedDay == .today {
                        StreakCard(
                            streakManager: streakManager,
                            currentSteps: healthKitManager.todaySteps,
                            goalSteps: userPreferences.dailyStepGoal
                        )
                    }

                    // Conflicts Alert (if any)
                    if selectedDay == .today && !planManager.todayConflicts.isEmpty {
                        ConflictsAlertSection(
                            conflicts: planManager.todayConflicts,
                            onResolve: { conflict in
                                conflictToResolve = conflict
                            },
                            onDismiss: { conflict in
                                scheduledActivityManager.dismissConflict(conflict, for: Date())
                            }
                        )
                    }

                    // Scheduled Activities Section (includes both ScheduledActivity and PlannedActivity)
                    let currentDate = selectedDay == .today ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    let scheduledForDay = scheduledActivityManager.activities(for: currentDate)
                    let calendarActivitiesForDay = activityStore.activities(for: currentDate)
                    if !scheduledForDay.isEmpty || !calendarActivitiesForDay.isEmpty {
                        ScheduledActivitiesSection(
                            activities: scheduledForDay,
                            calendarActivities: calendarActivitiesForDay,
                            date: currentDate,
                            onViewAll: { showScheduledActivities = true }
                        )
                    }

                    // Personal Insights Section (only for Today)
                    if selectedDay == .today {
                        PersonalInsightsSection(
                            insightsManager: insightsManager,
                            showWorkoutSetup: $showWorkoutSetup
                        )
                    }

                    // Workout Setup Prompt (if not configured)
                    if !userPreferences.hasWorkoutGoal {
                        WorkoutSetupPrompt(showSetup: $showWorkoutSetup)
                    }

                    // Suggested Slots Section (always visible to allow adding more activities)
                    let currentPlan = selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                    // Get the primary suggestion (first slot) and walkable meetings separately
                    // Filter out past times for today and already scheduled slots
                    let now = Date()
                    let isToday = selectedDay == .today

                    // Get scheduled activity times to filter them out from suggestions
                    // Include both ScheduledActivity times and PlannedActivity (calendar) times
                    let scheduledTimes = scheduledForDay.compactMap { activity -> Date? in
                        activity.getTimeRange(for: currentDate)?.start
                    }
                    let calendarTimes = calendarActivitiesForDay.map { $0.startTime }
                    let allBookedTimes = scheduledTimes + calendarTimes

                    // Helper to check if a slot overlaps with any scheduled or calendar activity
                    let isSlotScheduled: (Date) -> Bool = { slotTime in
                        allBookedTimes.contains { bookedTime in
                            abs(slotTime.timeIntervalSince(bookedTime)) < 60 * 30 // Within 30 min
                        }
                    }

                    // Filter walkable meetings: future only, not already scheduled
                    let walkableMeetings = (currentPlan?.stepSlots.filter { $0.slotType == .walkableMeeting } ?? [])
                        .filter { !isToday || $0.startTime > now }
                        .filter { !isSlotScheduled($0.startTime) }

                    // Filter free time slots: future only, not already scheduled
                    let freeTimeSlots = (currentPlan?.stepSlots.filter { $0.slotType == .freeTime } ?? [])
                        .filter { !isToday || $0.startTime > now }
                        .filter { !isSlotScheduled($0.startTime) }

                    // Consolidate slots at the same time
                    let consolidatedWalkSlots = consolidateSlots(freeTimeSlots)
                    let consolidatedMeetingSlots = consolidateSlots(walkableMeetings)
                    let primaryWalkSlot = consolidatedWalkSlots.first ?? consolidatedMeetingSlots.first

                    // Filter workout slot for future time and not already scheduled
                    let workoutSlot = currentPlan?.workoutSlot
                    let futureWorkoutSlot = workoutSlot.flatMap { slot -> WorkoutSlot? in
                        // Skip if in the past (for today)
                        guard !isToday || slot.startTime > now else { return nil }
                        // Skip if already scheduled
                        guard !isSlotScheduled(slot.startTime) else { return nil }
                        return slot
                    }

                    // All walk slots are shown here with selection and scheduling capability
                    // This replaces the old MovementPlanSection which showed non-selectable slots
                    SuggestedSlotsSection(
                        suggestedWalk: primaryWalkSlot,
                        suggestedWorkout: futureWorkoutSlot,
                        walkableMeetings: consolidatedMeetingSlots,
                        allWalkSlots: consolidatedWalkSlots,
                        hasWorkoutGoal: userPreferences.hasWorkoutGoal,
                        isToday: isToday,
                        onScheduleSlot: { walkSlot, workoutSlot, activityType in
                            if activityType == .walk, let slot = walkSlot {
                                slotToSchedule = slot
                                showScheduleWalk = true
                            } else if activityType == .workout, let slot = workoutSlot {
                                workoutToSchedule = slot
                                showScheduleWorkout = true
                            }
                        },
                        onScheduleConsolidatedWalks: { ranges in
                            // Directly schedule each consolidated walk range without showing a sheet
                            for range in ranges {
                                let duration = Int(range.end.timeIntervalSince(range.start) / 60)
                                let activity = ScheduledActivity(
                                    activityType: .walk,
                                    title: "Walk",
                                    startTime: range.start,
                                    duration: duration,
                                    recurrence: .once
                                )
                                scheduledActivityManager.addScheduledActivity(activity)
                            }
                            // Provide haptic feedback
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        },
                        onCustomTime: { activityType in
                            let targetDate = selectedDay == .today ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                            customTimeRequest = CustomTimeRequest(activityType: activityType, date: targetDate)
                        }
                    )

                    // Show loading or empty state if no plan available
                    if selectedDay == .today {
                        if planManager.todayPlan == nil {
                            if planManager.isLoading {
                                LoadingCard()
                            } else if consolidatedWalkSlots.isEmpty && consolidatedMeetingSlots.isEmpty {
                                EmptyPlanCard(message: "Pull down to refresh your plan")
                            }
                        }
                    } else {
                        if planManager.tomorrowPlan == nil {
                            if planManager.isLoading {
                                LoadingCard()
                            } else if consolidatedWalkSlots.isEmpty && consolidatedMeetingSlots.isEmpty {
                                EmptyPlanCard(message: "Tomorrow's plan is not ready yet")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(selectedDay == .today ? "Today, \(currentDayOfWeek)" : "Tomorrow, \(tomorrowDayOfWeek)")
            .refreshable {
                await refreshData()
            }
            .task {
                await loadInitialData()
            }
            .onAppear {
                // Refresh calendar data when view appears (e.g., switching tabs)
                Task {
                    await calendarManager.refreshEvents()
                    await planManager.generatePlans()
                }
            }
            .sheet(isPresented: $showWorkoutSetup) {
                WorkoutSetupSheet()
                    .environmentObject(userPreferences)
            }
            .sheet(isPresented: $showCalendarView) {
                CombinedCalendarView(
                    plan: selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                )
                .environmentObject(calendarManager)
            }
            .sheet(isPresented: $showScheduleWalk) {
                let currentPlan = selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                let walkSlot = slotToSchedule ?? currentPlan?.stepSlots.first
                if let slot = walkSlot {
                    ScheduleActivitySheet(
                        activityType: .walk,
                        suggestedTime: slot.startTime,
                        suggestedDuration: slot.duration,
                        onScheduled: {
                            slotToSchedule = nil
                            // Don't regenerate plans - keep slots visible for user to add more
                        }
                    )
                }
            }
            .sheet(isPresented: $showScheduleWorkout) {
                let currentPlan = selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                let workout = workoutToSchedule ?? currentPlan?.workoutSlot
                if let slot = workout {
                    ScheduleActivitySheet(
                        activityType: .workout,
                        suggestedTime: slot.startTime,
                        suggestedDuration: slot.duration,
                        workoutType: slot.workoutType,
                        onScheduled: {
                            workoutToSchedule = nil
                            // Don't regenerate plans - keep slots visible for user to add more
                        }
                    )
                }
            }
            .sheet(item: $customTimeRequest) { request in
                CustomTimeSlotSheet(
                    activityType: request.activityType,
                    date: request.date,
                    onScheduled: {
                        // Don't regenerate plans - keep slots visible for user to add more
                    }
                )
            }
            .sheet(isPresented: $showScheduledActivities) {
                ScheduledActivitiesListSheet()
            }
            .sheet(item: $conflictToResolve) { conflict in
                RescheduleActivitySheet(
                    activity: conflict.scheduledActivity,
                    conflictDescription: conflict.description,
                    onRescheduled: {
                        // Dismiss the conflict so it doesn't reappear
                        scheduledActivityManager.dismissConflict(conflict, for: Date())
                        Task { await planManager.generatePlans() }
                    }
                )
            }
            .onChange(of: resetToTodayTrigger) { _, _ in
                // Reset to Today tab when bottom tab bar "Today" is tapped
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDay = .today
                }
            }
        }
    }

    private func loadInitialData() async {
        _ = try? await healthKitManager.fetchTodaySteps()

        healthKitManager.observeStepChanges { _ in }

        await planManager.generatePlans()
        await insightsManager.analyzePatterns()
    }

    private func refreshData() async {
        isRefreshing = true
        _ = try? await healthKitManager.fetchTodaySteps()
        await planManager.generatePlans()
        await insightsManager.analyzePatterns()
        isRefreshing = false
    }

    private var currentDayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var tomorrowDayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return formatter.string(from: tomorrow)
    }

    /// Consolidates slots that start at the same time into a single slot
    /// by picking the one with the most steps/longest duration
    private func consolidateSlots(_ slots: [StepSlot]) -> [StepSlot] {
        guard !slots.isEmpty else { return [] }

        // Group slots by their start time (rounded to the nearest 5 minutes)
        let calendar = Calendar.current
        var groupedSlots: [Date: [StepSlot]] = [:]

        for slot in slots {
            // Round to nearest 5 minutes for grouping
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot.startTime)
            let minute = components.minute ?? 0
            let roundedMinute = (minute / 5) * 5
            var roundedComponents = components
            roundedComponents.minute = roundedMinute
            let roundedTime = calendar.date(from: roundedComponents) ?? slot.startTime

            if groupedSlots[roundedTime] == nil {
                groupedSlots[roundedTime] = []
            }
            groupedSlots[roundedTime]?.append(slot)
        }

        // For each group, pick the best slot (most steps or longest duration)
        var consolidatedSlots: [StepSlot] = []
        for (_, slotsAtTime) in groupedSlots {
            if let bestSlot = slotsAtTime.max(by: { $0.targetSteps < $1.targetSteps }) {
                consolidatedSlots.append(bestSlot)
            }
        }

        return consolidatedSlots.sorted { $0.startTime < $1.startTime }
    }
}

// MARK: - Personal Insights Section

struct PersonalInsightsSection: View {
    @ObservedObject var insightsManager: PersonalInsightsManager
    @Binding var showWorkoutSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Your Patterns")
                    .font(.headline)
                Spacer()
                if insightsManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Current Day Pattern Card
            if let pattern = insightsManager.currentDayPattern {
                DayPatternCard(pattern: pattern)
            }

            // Best Day Trophy Card
            if let bestDay = insightsManager.bestRecentDay {
                BestDayCard(bestDay: bestDay, replicablePlan: insightsManager.replicablePlan)
            }

            // Today's Insights Carousel
            if !insightsManager.todayInsights.isEmpty {
                InsightsCarousel(insights: insightsManager.todayInsights)
            }
        }
    }
}

// MARK: - Day Pattern Card

struct DayPatternCard: View {
    let pattern: DayPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                    .font(.title3)

                Text("Your \(pattern.weekdayName) Pattern")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("12 weeks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 20) {
                // Average Steps
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg Steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.averageSteps.formatted())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Divider()
                    .frame(height: 40)

                // Workouts
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workouts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(pattern.workoutCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }

                Divider()
                    .frame(height: 40)

                // Goal Rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal Hit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(pattern.goalAchievementRate * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(pattern.goalAchievementRate >= 0.5 ? .green : .orange)
                }

                Spacer()
            }

            // Personal best for this day
            if pattern.bestSteps > 0 {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Best: \(pattern.bestSteps.formatted()) steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Best Day Card

struct BestDayCard: View {
    let bestDay: BestDayRecord
    let replicablePlan: ReplicableDayPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Best Recent Day")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(bestDay.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if bestDay.goalAchieved {
                    Label("Goal Met", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Divider()

            // Stats Row
            HStack(spacing: 16) {
                StatBadge(
                    icon: "figure.walk",
                    value: bestDay.steps.formatted(),
                    label: "steps",
                    color: .green
                )

                if bestDay.workoutDuration > 0 {
                    StatBadge(
                        icon: "dumbbell.fill",
                        value: "\(bestDay.workoutDuration)",
                        label: "min workout",
                        color: .orange
                    )
                }

                if bestDay.activeCalories > 0 {
                    StatBadge(
                        icon: "flame.fill",
                        value: "\(Int(bestDay.activeCalories))",
                        label: "cal",
                        color: .red
                    )
                }
            }

            // Replicability Section
            if let plan = replicablePlan {
                Divider()

                if plan.canReplicate {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.green)
                        Text("You can replicate this today!")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                } else if !plan.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("Today's challenges:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(plan.blockers, id: \.self) { blocker in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 4, height: 4)
                                Text(blocker)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let adjustedPlan = plan.adjustedPlan {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text(adjustedPlan)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(8)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.1), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Insights Carousel

struct InsightsCarousel: View {
    let insights: [TodayInsight]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: TodayInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: insight.icon)
                    .foregroundColor(insight.color)

                Spacer()

                Image(systemName: insight.trend.icon)
                    .foregroundColor(insight.trend.color)
                    .font(.caption)
            }

            Text(insight.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            Text(insight.value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(insight.color)

            Text(insight.subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 140)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Day Selector

struct DaySelector: View {
    @Binding var selectedDay: HomeView.SelectedDay

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedDay = .today }
            } label: {
                Text("Today")
                    .font(.subheadline)
                    .fontWeight(selectedDay == .today ? .semibold : .regular)
                    .foregroundColor(selectedDay == .today ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedDay == .today ? Color.blue : Color.clear)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedDay = .tomorrow }
            } label: {
                Text("Tomorrow")
                    .font(.subheadline)
                    .fontWeight(selectedDay == .tomorrow ? .semibold : .regular)
                    .foregroundColor(selectedDay == .tomorrow ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedDay == .tomorrow ? Color.blue : Color.clear)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Step Progress Card

struct StepProgressCard: View {
    let currentSteps: Int
    let goalSteps: Int
    let isToday: Bool

    @State private var showCelebration = false
    @State private var previousSteps: Int = 0
    @AppStorage("lastCelebrationDate") private var lastCelebrationDateString: String = ""

    private var progress: Double {
        guard goalSteps > 0 else { return 0 }
        return min(1.0, Double(currentSteps) / Double(goalSteps))
    }

    private var stepsRemaining: Int {
        max(0, goalSteps - currentSteps)
    }

    private var goalReached: Bool {
        currentSteps >= goalSteps
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isToday ? "Steps Today" : "Projected Steps")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()

                if goalReached {
                    Label("Goal reached!", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        goalReached ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)

                VStack(spacing: 4) {
                    Text("\(currentSteps.formatted())")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(goalReached ? .green : .primary)

                    Text("/ \(goalSteps.formatted())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 160, height: 160)

            if stepsRemaining > 0 && isToday {
                Text("\(stepsRemaining.formatted()) steps to go")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if goalReached && isToday {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Exceeded by \((currentSteps - goalSteps).formatted()) steps!")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
        .onAppear {
            previousSteps = currentSteps
        }
        .onChange(of: currentSteps) { oldValue, newValue in
            checkForCelebration(oldSteps: oldValue, newSteps: newValue)
        }
        .overlay {
            GoalCelebrationOverlay(
                isShowing: $showCelebration,
                stepCount: currentSteps,
                goalSteps: goalSteps
            )
        }
    }

    private func checkForCelebration(oldSteps: Int, newSteps: Int) {
        // Only celebrate if:
        // 1. It's today
        // 2. Steps just crossed the goal threshold
        // 3. We haven't celebrated today yet
        guard isToday else { return }
        guard oldSteps < goalSteps && newSteps >= goalSteps else { return }

        let todayString = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        guard lastCelebrationDateString != todayString else { return }

        // Show celebration
        lastCelebrationDateString = todayString
        showCelebration = true
    }
}

// MARK: - Workout Setup Prompt

struct WorkoutSetupPrompt: View {
    @Binding var showSetup: Bool

    var body: some View {
        Button {
            showSetup = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Up Workout Goals")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Get personalized gym time suggestions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - Workout Setup Sheet

struct WorkoutSetupSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userPreferences: UserPreferences

    @State private var selectedFrequency: GymFrequency = .threeDays
    @State private var selectedDuration: WorkoutDuration = .fortyFiveMinutes
    @State private var selectedTime: PreferredGymTime = .noPreference
    @State private var selectedAge: AgeGroup?

    var body: some View {
        NavigationStack {
            Form {
                // Age-based suggestions
                Section {
                    Picker("Your Age Group", selection: $selectedAge) {
                        Text("Select").tag(nil as AgeGroup?)
                        ForEach(AgeGroup.allCases, id: \.self) { age in
                            Text(age.rawValue).tag(age as AgeGroup?)
                        }
                    }
                    .onChange(of: selectedAge) { _, newValue in
                        if let age = newValue {
                            selectedFrequency = age.recommendedGymFrequency
                            selectedDuration = age.recommendedWorkoutDuration
                        }
                    }
                } header: {
                    Text("Get Personalized Recommendations")
                } footer: {
                    if let age = selectedAge {
                        Text("Recommended: \(age.recommendedGymFrequency.displayName), \(age.recommendedWorkoutDuration.displayName) workouts, \(age.recommendedSteps.formatted()) daily steps")
                    }
                }

                Section {
                    Picker("Gym Frequency", selection: $selectedFrequency) {
                        ForEach(GymFrequency.allCases.filter { $0 != .none }, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    Picker("Workout Duration", selection: $selectedDuration) {
                        ForEach(WorkoutDuration.allCases, id: \.self) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }

                    Picker("Preferred Time", selection: $selectedTime) {
                        ForEach(PreferredGymTime.allCases, id: \.self) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                } header: {
                    Text("Workout Preferences")
                }

                Section {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Text("Save Workout Goals")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Workout Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveAndDismiss() {
        userPreferences.gymFrequency = selectedFrequency
        userPreferences.workoutDuration = selectedDuration
        userPreferences.preferredGymTime = selectedTime
        if let age = selectedAge {
            userPreferences.ageGroup = age
            userPreferences.dailyStepGoal = age.recommendedSteps
        }
        dismiss()
    }
}

// MARK: - Movement Plan Section

struct MovementPlanSection: View {
    let plan: DayMovementPlan
    @Binding var showCalendar: Bool
    let hasWorkoutGoal: Bool
    @Binding var showScheduleWalk: Bool
    @Binding var showScheduleWorkout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(plan.isToday ? "Walk Slots" : "Tomorrow's Walk Slots")
                .font(.headline)

            // Step Slots (walkable meetings and free time)
            if !plan.stepSlots.isEmpty {
                VStack(spacing: 12) {
                    ForEach(plan.stepSlots.prefix(5)) { slot in
                        StepSlotCard(slot: slot)
                    }

                    if plan.stepSlots.count > 5 {
                        Text("+\(plan.stepSlots.count - 5) more slots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Workout Slot (only show if there's a suggestion)
            if hasWorkoutGoal, let workout = plan.workoutSlot {
                WorkoutSlotCard(slot: workout)
            }
        }
    }
}

// MARK: - Conflicts Alert Section (Collapsible with Swipe to Dismiss)

struct ConflictsAlertSection: View {
    let conflicts: [ScheduleConflict]
    var onResolve: (ScheduleConflict) -> Void
    var onDismiss: (ScheduleConflict) -> Void
    @State private var isExpanded = false

    var body: some View {
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header - tap to expand/collapse
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("Schedule Conflicts")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("(\(conflicts.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Collapsed summary
                if !isExpanded {
                    HStack {
                        Text(conflicts.map { $0.scheduledActivity.title }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text("Tap to view")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                // Expanded list with swipe to dismiss
                if isExpanded {
                    ForEach(conflicts) { conflict in
                        ConflictRow(
                            conflict: conflict,
                            onResolve: { onResolve(conflict) },
                            onDismiss: {
                                withAnimation {
                                    onDismiss(conflict)
                                }
                            }
                        )
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
}

// MARK: - Conflict Row with Swipe to Dismiss

struct ConflictRow: View {
    let conflict: ScheduleConflict
    var onResolve: () -> Void
    var onDismiss: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Dismiss background
            HStack {
                Spacer()
                Text("Dismiss")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray)
            .cornerRadius(10)

            // Main content
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.scheduledActivity.title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(conflict.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Resolve") {
                    onResolve()
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(8)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                            isSwiping = true
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -100 {
                            withAnimation {
                                offset = -500
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onDismiss()
                            }
                        } else {
                            withAnimation {
                                offset = 0
                            }
                        }
                        isSwiping = false
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Custom Time Slot Sheet

struct CustomTimeSlotSheet: View {
    let activityType: ActivityType
    let date: Date
    var onScheduled: () -> Void

    @Environment(\.dismiss) var dismiss
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared
    @EnvironmentObject var userPreferences: UserPreferences

    @State private var selectedTime = Date()
    @State private var duration: Int = 30

    private var durationOptions: [Int] {
        if activityType == .walk {
            return [15, 20, 30, 45, 60]
        } else {
            return [30, 45, 60, 90, 120]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start Time",
                        selection: $selectedTime,
                        displayedComponents: [.hourAndMinute]
                    )

                    Picker("Duration", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: activityType == .walk ? "figure.walk" : "figure.strengthtraining.traditional")
                            .foregroundColor(activityType == .walk ? .green : .orange)
                        Text(activityType == .walk ? "Walk" : "Workout")
                    }
                }

                if activityType == .walk {
                    Section {
                        HStack {
                            Text("Estimated Steps")
                            Spacer()
                            Text("~\((duration * 100).formatted())")
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }

                Section {
                    Button {
                        scheduleActivity()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Schedule")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Custom \(activityType == .walk ? "Walk" : "Workout")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Set default time based on date
                var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                let hour = Calendar.current.component(.hour, from: Date())
                components.hour = max(hour + 1, 8) // At least 1 hour from now or 8 AM
                components.minute = 0
                if let defaultTime = Calendar.current.date(from: components) {
                    selectedTime = defaultTime
                }
                duration = activityType == .walk ? 30 : 60
            }
        }
    }

    private func scheduleActivity() {
        // Combine date and time
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute

        guard let startTime = Calendar.current.date(from: components) else { return }

        let activity = ScheduledActivity(
            activityType: activityType,
            workoutType: activityType == .workout ? .fullBody : nil,
            title: activityType == .walk ? "Walk" : "Workout",
            startTime: startTime,
            duration: duration,
            recurrence: .once
        )

        scheduledActivityManager.addScheduledActivity(activity)
        onScheduled()
        dismiss()
    }
}

// MARK: - Scheduled Activities Section (Committed List with Checkboxes)

struct ScheduledActivitiesSection: View {
    let activities: [ScheduledActivity]
    var calendarActivities: [PlannedActivity] = []
    let date: Date
    var onViewAll: () -> Void
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared
    @ObservedObject var activityStore = ActivityStore.shared
    @State private var activityToEdit: ScheduledActivity?
    @State private var calendarActivityToEdit: PlannedActivity?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    // Combined and sorted list of all activities for the day
    private var allActivitiesSorted: [(type: ActivityItemType, scheduledActivity: ScheduledActivity?, calendarActivity: PlannedActivity?, startTime: Date)] {
        var combined: [(type: ActivityItemType, scheduledActivity: ScheduledActivity?, calendarActivity: PlannedActivity?, startTime: Date)] = []

        // Add scheduled activities
        for activity in activities {
            if let timeRange = activity.getTimeRange(for: date) {
                combined.append((type: .scheduled, scheduledActivity: activity, calendarActivity: nil, startTime: timeRange.start))
            }
        }

        // Add calendar/planned activities (avoiding duplicates based on time and type)
        for calActivity in calendarActivities {
            // Check if this activity doesn't overlap with an existing scheduled activity
            let isDuplicate = activities.contains { scheduled in
                guard let timeRange = scheduled.getTimeRange(for: date) else { return false }
                // Consider duplicate if same type and overlapping time
                return scheduled.activityType == calActivity.activityType &&
                    abs(timeRange.start.timeIntervalSince(calActivity.startTime)) < 60 * 15 // Within 15 min
            }
            if !isDuplicate {
                combined.append((type: .calendar, scheduledActivity: nil, calendarActivity: calActivity, startTime: calActivity.startTime))
            }
        }

        return combined.sorted { $0.startTime < $1.startTime }
    }

    private var totalCount: Int {
        allActivitiesSorted.count
    }

    private var completedCount: Int {
        var count = 0
        for item in allActivitiesSorted {
            if item.type == .scheduled, let activity = item.scheduledActivity {
                if scheduledActivityManager.isCompleted(activity: activity, for: date) {
                    count += 1
                }
            } else if item.type == .calendar, let activity = item.calendarActivity {
                if activity.isCompleted {
                    count += 1
                }
            }
        }
        return count
    }

    enum ActivityItemType {
        case scheduled
        case calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Schedule")
                    .font(.headline)

                Spacer()

                if isToday && totalCount > 0 {
                    Text("\(completedCount)/\(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    onViewAll()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            ForEach(Array(allActivitiesSorted.enumerated()), id: \.offset) { index, item in
                if item.type == .scheduled, let activity = item.scheduledActivity,
                   let timeRange = activity.getTimeRange(for: date) {
                    CommittedActivityRow(
                        activity: activity,
                        timeRange: timeRange,
                        isCompleted: scheduledActivityManager.isCompleted(activity: activity, for: date),
                        isToday: isToday,
                        onToggle: {
                            withAnimation(.spring(response: 0.3)) {
                                scheduledActivityManager.toggleCompletion(activity: activity, for: date)
                            }
                        },
                        onTap: {
                            activityToEdit = activity
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.3)) {
                                scheduledActivityManager.deleteScheduledActivity(activity)
                            }
                        }
                    )
                } else if item.type == .calendar, let calActivity = item.calendarActivity {
                    CalendarActivityRow(
                        activity: calActivity,
                        isToday: isToday,
                        onToggle: {
                            withAnimation(.spring(response: 0.3)) {
                                var updated = calActivity
                                if calActivity.isCompleted {
                                    updated.isCompleted = false
                                } else {
                                    updated.markCompleted()
                                }
                                activityStore.updateActivity(updated)
                            }
                        },
                        onTap: {
                            calendarActivityToEdit = calActivity
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.3)) {
                                activityStore.deleteActivity(calActivity)
                            }
                        }
                    )
                }
            }
        }
        .sheet(item: $activityToEdit) { activity in
            EditScheduledActivitySheet(activity: activity)
        }
        .sheet(item: $calendarActivityToEdit) { activity in
            ActivityDetailSheet(activity: activity)
                .environmentObject(activityStore)
        }
    }
}

// MARK: - Calendar Activity Row (for PlannedActivity from calendar)

struct CalendarActivityRow: View {
    let activity: PlannedActivity
    let isToday: Bool
    var onToggle: () -> Void
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showDeleteButton = false

    private let deleteThreshold: CGFloat = -80

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                }
                .background(Color.red)
                .cornerRadius(12)
            }
            .opacity(showDeleteButton ? 1 : 0)

            // Main content
            HStack(spacing: 12) {
                // Checkbox for today
                if isToday {
                    Button {
                        onToggle()
                    } label: {
                        Image(systemName: activity.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(activity.isCompleted ? .green : .gray)
                    }
                }

                Image(systemName: activity.icon)
                    .font(.title3)
                    .foregroundColor(activity.isCompleted ? .gray : activity.color)
                    .frame(width: 36, height: 36)
                    .background((activity.isCompleted ? Color.gray : activity.color).opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(activity.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .strikethrough(activity.isCompleted, color: .gray)
                            .foregroundColor(activity.isCompleted ? .secondary : .primary)

                        // Calendar badge to distinguish from scheduled activities
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }

                    HStack(spacing: 6) {
                        Text("\(timeFormatter.string(from: activity.startTime)) - \(timeFormatter.string(from: activity.endTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if activity.repeatOption != .never {
                            Text("•")
                                .foregroundColor(.secondary)
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                if activity.isCompleted && isToday {
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else {
                    Text("\(activity.duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .opacity(activity.isCompleted ? 0.8 : 1.0)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                            showDeleteButton = offset < deleteThreshold
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            if value.translation.width < deleteThreshold * 1.5 {
                                // Full swipe - delete
                                onDelete()
                            } else if value.translation.width < deleteThreshold {
                                // Partial swipe - show delete button
                                offset = deleteThreshold
                                showDeleteButton = true
                            } else {
                                // Reset
                                offset = 0
                                showDeleteButton = false
                            }
                        }
                    }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if showDeleteButton {
                    withAnimation(.spring(response: 0.3)) {
                        offset = 0
                        showDeleteButton = false
                    }
                } else {
                    onTap()
                }
            }
        }
    }
}

// MARK: - Committed Activity Row

struct CommittedActivityRow: View {
    let activity: ScheduledActivity
    let timeRange: (start: Date, end: Date)
    let isCompleted: Bool
    let isToday: Bool
    var onToggle: () -> Void
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showDeleteButton = false

    private let deleteThreshold: CGFloat = -80

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    // Simplified title for workout
    private var displayTitle: String {
        if activity.activityType == .workout {
            return "Workout"
        }
        return activity.title
    }

    // Simplified icon for workout
    private var displayIcon: String {
        if activity.activityType == .workout {
            return "figure.strengthtraining.traditional"
        }
        return activity.icon
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                }
                .background(Color.red)
                .cornerRadius(12)
            }
            .opacity(showDeleteButton ? 1 : 0)

            // Main content
            HStack(spacing: 12) {
                // Checkbox for today
                if isToday {
                    Button {
                        onToggle()
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(isCompleted ? .green : .gray)
                    }
                }

                Image(systemName: displayIcon)
                    .font(.title3)
                    .foregroundColor(isCompleted ? .gray : activity.color)
                    .frame(width: 36, height: 36)
                    .background((isCompleted ? Color.gray : activity.color).opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .strikethrough(isCompleted, color: .gray)
                        .foregroundColor(isCompleted ? .secondary : .primary)

                    HStack(spacing: 6) {
                        Text("\(timeFormatter.string(from: timeRange.start)) - \(timeFormatter.string(from: timeRange.end))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if activity.recurrence != .once {
                            Text("•")
                                .foregroundColor(.secondary)
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                if isCompleted && isToday {
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else {
                    Text("\(activity.duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .opacity(isCompleted ? 0.8 : 1.0)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                            showDeleteButton = offset < deleteThreshold
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            if value.translation.width < deleteThreshold * 1.5 {
                                // Full swipe - delete
                                onDelete()
                            } else if value.translation.width < deleteThreshold {
                                // Partial swipe - show delete button
                                offset = deleteThreshold
                                showDeleteButton = true
                            } else {
                                // Reset
                                offset = 0
                                showDeleteButton = false
                            }
                        }
                    }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if showDeleteButton {
                    withAnimation(.spring(response: 0.3)) {
                        offset = 0
                        showDeleteButton = false
                    }
                } else {
                    onTap()
                }
            }
        }
    }
}

// MARK: - Suggested Slots Section

struct SuggestedSlotsSection: View {
    let suggestedWalk: StepSlot?
    let suggestedWorkout: WorkoutSlot?
    let walkableMeetings: [StepSlot]
    let allWalkSlots: [StepSlot]
    let hasWorkoutGoal: Bool
    var isToday: Bool = true
    var onScheduleSlot: (StepSlot?, WorkoutSlot?, ActivityType) -> Void
    var onScheduleConsolidatedWalks: ([(start: Date, end: Date, steps: Int)]) -> Void // Array of consolidated ranges
    var onCustomTime: (ActivityType) -> Void
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared
    @EnvironmentObject var userPreferences: UserPreferences

    @State private var selectedWalkSlots: Set<UUID> = []
    @State private var selectedWorkoutSlot: WorkoutSlot?
    @State private var showConflictsExpanded = false

    // Check if we have historical patterns for this weekday
    private var hasWalkHistory: Bool {
        let patterns = scheduledActivityManager.getTimeSuggestions(for: .walk, on: Date())
        return !patterns.isEmpty
    }

    private var hasWorkoutHistory: Bool {
        let patterns = scheduledActivityManager.getTimeSuggestions(for: .workout, on: currentDate)
        return !patterns.isEmpty
    }

    private var workoutHistoryMessage: String? {
        scheduledActivityManager.getWorkoutHistoryMessage(for: currentDate)
    }

    private var currentDate: Date {
        isToday ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }

    // Get consolidated time ranges from selected walk slots (groups overlapping/adjacent slots)
    private var consolidatedWalkTimeRanges: [(start: Date, end: Date, steps: Int)] {
        guard !selectedWalkSlots.isEmpty else { return [] }

        let allAvailableSlots = allWalkSlots + walkableMeetings
        let selectedSlots = allAvailableSlots.filter { selectedWalkSlots.contains($0.id) }

        guard !selectedSlots.isEmpty else { return [] }

        // Sort slots by start time
        let sortedSlots = selectedSlots.sorted { $0.startTime < $1.startTime }

        // Group overlapping or adjacent slots (within 30 min gap)
        var groups: [[(start: Date, end: Date, steps: Int)]] = []
        let maxGap: TimeInterval = 30 * 60 // 30 minutes

        for slot in sortedSlots {
            let slotRange = (start: slot.startTime, end: slot.endTime, steps: slot.targetSteps)

            if groups.isEmpty {
                groups.append([slotRange])
            } else {
                // Check if this slot overlaps or is adjacent to the last group
                let lastGroupEnd = groups[groups.count - 1].map { $0.end }.max() ?? Date.distantPast

                if slot.startTime.timeIntervalSince(lastGroupEnd) <= maxGap {
                    // Overlaps or adjacent - add to current group
                    groups[groups.count - 1].append(slotRange)
                } else {
                    // Gap too large - start new group
                    groups.append([slotRange])
                }
            }
        }

        // Consolidate each group into a single range
        return groups.map { group in
            let start = group.map { $0.start }.min() ?? Date()
            let end = group.map { $0.end }.max() ?? Date()
            let steps = group.reduce(0) { $0 + $1.steps }
            return (start: start, end: end, steps: steps)
        }
    }

    // Format the consolidated time ranges for display
    private var consolidatedTimeRangesFormatted: String {
        let ranges = consolidatedWalkTimeRanges
        guard !ranges.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        return ranges.map { range in
            let duration = Int(range.end.timeIntervalSince(range.start) / 60)
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end)) (\(duration) min)"
        }.joined(separator: ", ")
    }

    private var walkPreferenceLabel: String {
        switch userPreferences.preferredWalkTime {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .noPreference: return "Available"
        }
    }

    private var workoutPreferenceLabel: String {
        switch userPreferences.preferredGymTime {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .noPreference: return "Available"
        }
    }

    // Calculate total estimated steps from selected walk slots (including walkable meetings)
    private var totalSelectedSteps: Int {
        let allAvailableSlots = allWalkSlots + walkableMeetings
        return allAvailableSlots
            .filter { selectedWalkSlots.contains($0.id) }
            .reduce(0) { $0 + $1.targetSteps }
    }

    // Check if any selections have been made
    private var hasSelections: Bool {
        !selectedWalkSlots.isEmpty || selectedWorkoutSlot != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with selection summary
            HStack {
                Text("Suggested Slots")
                    .font(.headline)

                Spacer()

                if hasSelections {
                    Text("\(totalSelectedSteps.formatted()) steps")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Walk Slots Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.green)
                    Text("Walk Slots")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    // Custom time button
                    Button {
                        onCustomTime(.walk)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Custom")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }

                // Show all available walk slots with selection
                ForEach(allWalkSlots) { slot in
                    SelectableSlotCard(
                        slot: slot,
                        isSelected: selectedWalkSlots.contains(slot.id),
                        isBestTime: slot.id == suggestedWalk?.id,
                        hasHistory: hasWalkHistory && slot.id == suggestedWalk?.id,
                        activityType: .walk,
                        onToggle: {
                            if selectedWalkSlots.contains(slot.id) {
                                selectedWalkSlots.remove(slot.id)
                            } else {
                                selectedWalkSlots.insert(slot.id)
                            }
                        },
                        onSchedule: {
                            onScheduleSlot(slot, nil, .walk)
                        }
                    )
                }

                // Walkable meetings as additional walk options
                if !walkableMeetings.isEmpty {
                    Text("During Meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ForEach(walkableMeetings.prefix(3)) { meeting in
                        SelectableSlotCard(
                            slot: meeting,
                            isSelected: selectedWalkSlots.contains(meeting.id),
                            isBestTime: false,
                            hasHistory: false,
                            activityType: .walk,
                            onToggle: {
                                if selectedWalkSlots.contains(meeting.id) {
                                    selectedWalkSlots.remove(meeting.id)
                                } else {
                                    selectedWalkSlots.insert(meeting.id)
                                }
                            },
                            onSchedule: {
                                onScheduleSlot(meeting, nil, .walk)
                            }
                        )
                    }
                }
            }

            // Workout Slots Section (only if user has workout goal)
            if hasWorkoutGoal {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundColor(.orange)
                        Text("Workout Slot")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        // Custom time button
                        Button {
                            onCustomTime(.workout)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                Text("Custom")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }

                    if let workout = suggestedWorkout {
                        SelectableWorkoutCard(
                            slot: workout,
                            isSelected: selectedWorkoutSlot?.id == workout.id,
                            isBestTime: true,
                            hasHistory: hasWorkoutHistory,
                            historyMessage: workoutHistoryMessage,
                            onToggle: {
                                if selectedWorkoutSlot?.id == workout.id {
                                    selectedWorkoutSlot = nil
                                } else {
                                    selectedWorkoutSlot = workout
                                }
                            },
                            onSchedule: {
                                onScheduleSlot(nil, workout, .workout)
                            }
                        )
                    } else {
                        // No workout slot available - show prompt to add custom
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No available slot. Tap Custom to set your own time.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 8)
            }

            // Schedule selected button (if multiple selections)
            if hasSelections {
                VStack(spacing: 8) {
                    // Show consolidated time ranges preview (may be multiple groups)
                    let ranges = consolidatedWalkTimeRanges
                    if !ranges.isEmpty {
                        ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                            let formatter = DateFormatter()
                            let _ = formatter.timeStyle = .short
                            let duration = Int(range.end.timeIntervalSince(range.start) / 60)
                            HStack {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(.green)
                                Text("Walk: \(formatter.string(from: range.start)) - \(formatter.string(from: range.end)) (\(duration) min)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(range.steps.formatted()) steps")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    if let workout = selectedWorkoutSlot {
                        HStack {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .foregroundColor(.orange)
                            Text("Workout: \(workout.timeRangeFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(workout.duration) min")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Button {
                        // Schedule all consolidated walk slots (may be multiple groups)
                        let ranges = consolidatedWalkTimeRanges
                        if !ranges.isEmpty {
                            onScheduleConsolidatedWalks(ranges)
                        }
                        // Schedule workout if selected
                        if let workout = selectedWorkoutSlot {
                            onScheduleSlot(nil, workout, .workout)
                        }
                        // Clear selections after scheduling
                        selectedWalkSlots.removeAll()
                        selectedWorkoutSlot = nil
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text("Add to Your Schedule")
                            Spacer()
                            Text("\(totalSelectedSteps.formatted()) steps")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Selectable Slot Card

struct SelectableSlotCard: View {
    let slot: StepSlot
    let isSelected: Bool
    let isBestTime: Bool
    let hasHistory: Bool
    let activityType: ActivityType
    var onToggle: () -> Void
    var onSchedule: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .green : .gray)
            }

            // Slot icon
            Image(systemName: slot.slotType == .walkableMeeting ? "phone.fill" : "figure.walk")
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)

            // Slot info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(slot.source ?? "Walk")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if isBestTime {
                        Text(hasHistory ? "Your Best" : "Best")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }

                Text(slot.timeRangeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Steps estimate
            VStack(alignment: .trailing, spacing: 2) {
                Text("~\(slot.targetSteps)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                Text("steps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Quick schedule button
            Button {
                onSchedule()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(isSelected ? Color.green.opacity(0.08) : Color(.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Selectable Workout Card

struct SelectableWorkoutCard: View {
    let slot: WorkoutSlot
    let isSelected: Bool
    let isBestTime: Bool
    let hasHistory: Bool
    var historyMessage: String?
    var onToggle: () -> Void
    var onSchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Selection checkbox
                Button {
                    onToggle()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .orange : .gray)
                }

                // Workout icon
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)

                // Slot info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Workout")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if isBestTime && hasHistory {
                            Text("Same Time")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text(slot.timeRangeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Duration
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(slot.duration)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    Text("min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Quick schedule button
                Button {
                    onSchedule()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }

            // History message
            if let message = historyMessage {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.leading, 44)
            }
        }
        .padding(10)
        .background(isSelected ? Color.orange.opacity(0.08) : Color(.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Available Slot Card (for same preference time)

struct AvailableSlotCard: View {
    let time: String
    let duration: Int
    let steps: Int?
    let source: String?
    let hasWalkHistory: Bool
    let hasWorkoutHistory: Bool
    let hasWorkoutGoal: Bool
    var onAddWalk: (() -> Void)?
    var onAddWorkout: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)

                Text(time)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(duration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let source = source {
                Text(source)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                if let onAddWalk = onAddWalk {
                    Button {
                        onAddWalk()
                    } label: {
                        HStack {
                            Image(systemName: "figure.walk")
                            Text("Add Walk")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                }

                if let onAddWorkout = onAddWorkout, hasWorkoutGoal {
                    Button {
                        onAddWorkout()
                    } label: {
                        HStack {
                            Image(systemName: "figure.strengthtraining.traditional")
                            Text("Add Workout")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Walkable Meeting Row

struct WalkableMeetingRow: View {
    let meeting: StepSlot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.source ?? "Meeting")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(meeting.timeRangeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("~\(meeting.targetSteps) steps")
                .font(.caption2)
                .foregroundColor(.green)
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let icon: String
    let color: Color
    let title: String
    let time: String
    let subtitle: String
    var badgeText: String?
    var reasonText: String? = nil
    var onSchedule: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let badge = badgeText {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color)
                                .cornerRadius(4)
                        }
                    }

                    Text(time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let reason = reasonText {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                            Text(reason)
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }

                Spacer()
            }

            Button {
                onSchedule()
            } label: {
                Text("Schedule This")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(color)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Step Slot Card

struct StepSlotCard: View {
    let slot: StepSlot

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: slotIcon)
                .font(.system(size: 20))
                .foregroundColor(.green)
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(slot.slotType.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(slot.timeRangeFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let source = slot.source {
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(slot.targetStepsFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)

                Text("\(slot.duration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    private var slotIcon: String {
        switch slot.slotType {
        case .walkableMeeting: return "figure.walk"
        case .freeTime: return "figure.walk.circle"
        case .breakTime: return "cup.and.saucer"
        }
    }
}

// MARK: - Workout Slot Card

struct WorkoutSlotCard: View {
    let slot: WorkoutSlot

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 20))
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Workout")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if slot.isRecommended {
                        Text("Best Time")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }

                Text(slot.timeRangeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(slot.duration) min")
                .font(.subheadline)
                .foregroundColor(.orange)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

// MARK: - Combined Calendar View

struct CombinedCalendarView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var calendarManager: CalendarManager
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared
    let plan: DayMovementPlan?

    @State private var events: [CalendarEvent] = []
    @State private var isLoading = true
    @State private var showCalendarSync = false
    @State private var isSyncing = false
    @State private var syncSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sync Header
                CalendarSyncHeader(
                    isSyncing: isSyncing,
                    syncSuccess: syncSuccess,
                    onSyncTap: { showCalendarSync = true }
                )

                ScrollView {
                    if isLoading {
                        ProgressView("Loading calendar...")
                            .padding(.top, 100)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(timelineItems, id: \.time) { item in
                                TimelineRow(item: item)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(plan?.isToday == true ? "Today's Schedule" : "Tomorrow's Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCalendarSync) {
                CalendarSyncSheet(
                    plan: plan,
                    onSync: { calendars in
                        Task {
                            await syncToCalendars(calendars)
                        }
                    }
                )
                .environmentObject(calendarManager)
            }
            .task {
                await loadEvents()
            }
        }
    }

    private func loadEvents() async {
        guard let plan = plan else {
            isLoading = false
            return
        }

        if let fetchedEvents = try? await calendarManager.fetchEvents(for: plan.date) {
            events = fetchedEvents
        }
        isLoading = false
    }

    private var timelineItems: [TimelineItem] {
        guard let plan = plan else { return [] }

        var items: [TimelineItem] = []

        // Add calendar events
        for event in events {
            items.append(TimelineItem(
                time: event.startDate,
                title: event.title,
                duration: event.duration,
                type: .meeting,
                isWalkable: event.isWalkable
            ))
        }

        // Add step slots
        for slot in plan.stepSlots {
            // Only add if not overlapping with an event
            let overlaps = events.contains { event in
                slot.startTime >= event.startDate && slot.startTime < event.endDate
            }
            if !overlaps {
                items.append(TimelineItem(
                    time: slot.startTime,
                    title: slot.source ?? "Walk Time",
                    duration: slot.duration,
                    type: .stepSlot,
                    steps: slot.targetSteps
                ))
            }
        }

        // Add workout slot
        if let workout = plan.workoutSlot {
            items.append(TimelineItem(
                time: workout.startTime,
                title: "\(workout.workoutType.rawValue) Workout",
                duration: workout.duration,
                type: .workout,
                workoutType: workout.workoutType
            ))
        }

        return items.sorted { $0.time < $1.time }
    }

    private func syncToCalendars(_ calendarIDs: [String]) async {
        guard let plan = plan else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Use CalendarSyncService to sync the plan's activities
            try await CalendarSyncService.shared.syncMovementPlan(
                stepSlots: plan.stepSlots,
                workoutSlot: plan.workoutSlot,
                toCalendars: calendarIDs
            )

            await MainActor.run {
                syncSuccess = true
            }

            // Reset success state after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                syncSuccess = false
            }
        } catch {
            #if DEBUG
            print("Sync failed: \(error)")
            #endif
            // Reset state on error
            await MainActor.run {
                syncSuccess = false
            }
        }
    }
}

// MARK: - Calendar Sync Header

struct CalendarSyncHeader: View {
    let isSyncing: Bool
    let syncSuccess: Bool
    var onSyncTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync to Calendar")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Add your activities to external calendars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onSyncTap()
            } label: {
                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if syncSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(10)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Calendar Sync Sheet

struct CalendarSyncSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var calendarManager: CalendarManager
    let plan: DayMovementPlan?
    var onSync: ([String]) -> Void

    @State private var selectedCalendarIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                // Items to sync section
                Section {
                    if let plan = plan {
                        ForEach(plan.stepSlots.prefix(3)) { slot in
                            HStack {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(.green)
                                Text(slot.source ?? "Walk")
                                Spacer()
                                Text(slot.timeRangeFormatted)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let workout = plan.workoutSlot {
                            HStack {
                                Image(systemName: workout.workoutType.icon)
                                    .foregroundColor(.orange)
                                Text("\(workout.workoutType.rawValue) Workout")
                                Spacer()
                                Text(workout.timeRangeFormatted)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Activities to Sync")
                }

                // Calendar selection section
                Section {
                    ForEach(calendarManager.ownedCalendars.filter { $0.allowsModifications }) { calendar in
                        Button {
                            if selectedCalendarIDs.contains(calendar.id) {
                                selectedCalendarIDs.remove(calendar.id)
                            } else {
                                selectedCalendarIDs.insert(calendar.id)
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 12, height: 12)

                                Text(calendar.title)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedCalendarIDs.contains(calendar.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Calendars")
                } footer: {
                    Text("Your activities will be added to the selected calendars")
                }
            }
            .navigationTitle("Sync to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sync") {
                        onSync(Array(selectedCalendarIDs))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedCalendarIDs.isEmpty)
                }
            }
        }
    }
}

struct TimelineItem {
    let time: Date
    let title: String
    let duration: Int
    let type: ItemType
    var isWalkable: Bool = false
    var steps: Int = 0
    var workoutType: WorkoutType?

    enum ItemType {
        case meeting, stepSlot, workout
    }
}

struct TimelineRow: View {
    let item: TimelineItem

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time
            Text(timeFormatter.string(from: item.time))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2)
                    .frame(minHeight: 50)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("\(item.duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if item.isWalkable {
                        Label("Walkable", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    if item.steps > 0 {
                        Text("~\(item.steps) steps")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(8)

            Spacer()
        }
    }

    private var indicatorColor: Color {
        switch item.type {
        case .meeting: return item.isWalkable ? .green : .blue
        case .stepSlot: return .green
        case .workout: return .orange
        }
    }

    private var backgroundColor: Color {
        switch item.type {
        case .meeting: return item.isWalkable ? Color.green.opacity(0.1) : Color.blue.opacity(0.1)
        case .stepSlot: return Color.green.opacity(0.1)
        case .workout: return Color.orange.opacity(0.1)
        }
    }
}

// MARK: - Helper Views

struct LoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your movement plan...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct EmptyPlanCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    HomeView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserPreferences.shared)
        .environmentObject(CalendarManager.shared)
}
