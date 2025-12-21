import SwiftUI

struct HomeView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var calendarManager: CalendarManager
    @StateObject private var planManager = MovementPlanManager.shared
    @StateObject private var insightsManager = PersonalInsightsManager.shared
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared

    @State private var isRefreshing = false
    @State private var showWorkoutSetup = false
    @State private var showCalendarView = false
    @State private var showScheduleWalk = false
    @State private var showScheduleWorkout = false
    @State private var showScheduledActivities = false
    @State private var conflictToResolve: ScheduleConflict?
    @State private var selectedDay: SelectedDay = .today

    enum SelectedDay {
        case today, tomorrow
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

                    // Conflicts Alert (if any)
                    if selectedDay == .today && !planManager.todayConflicts.isEmpty {
                        ConflictsAlertSection(
                            conflicts: planManager.todayConflicts,
                            onResolve: { conflict in
                                conflictToResolve = conflict
                            }
                        )
                    }

                    // Scheduled Activities Section
                    let currentDate = selectedDay == .today ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    let scheduledForDay = scheduledActivityManager.activities(for: currentDate)
                    if !scheduledForDay.isEmpty {
                        ScheduledActivitiesSection(
                            activities: scheduledForDay,
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

                    // Suggested Slots Section (only if no scheduled activities)
                    if scheduledForDay.isEmpty {
                        let currentPlan = selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                        SuggestedSlotsSection(
                            suggestedWalk: currentPlan?.stepSlots.first,
                            suggestedWorkout: currentPlan?.workoutSlot,
                            hasWorkoutGoal: userPreferences.hasWorkoutGoal,
                            isToday: selectedDay == .today,
                            onScheduleWalk: { showScheduleWalk = true },
                            onScheduleWorkout: { showScheduleWorkout = true }
                        )
                    }

                    // Movement Plan Section (walkable meetings and free time slots)
                    if selectedDay == .today {
                        if let todayPlan = planManager.todayPlan {
                            MovementPlanSection(
                                plan: todayPlan,
                                showCalendar: $showCalendarView,
                                hasWorkoutGoal: userPreferences.hasWorkoutGoal,
                                showScheduleWalk: $showScheduleWalk,
                                showScheduleWorkout: $showScheduleWorkout
                            )
                        } else if planManager.isLoading {
                            LoadingCard()
                        } else {
                            EmptyPlanCard(message: "Pull down to refresh your plan")
                        }
                    } else {
                        if let tomorrowPlan = planManager.tomorrowPlan {
                            MovementPlanSection(
                                plan: tomorrowPlan,
                                showCalendar: $showCalendarView,
                                hasWorkoutGoal: userPreferences.hasWorkoutGoal,
                                showScheduleWalk: $showScheduleWalk,
                                showScheduleWorkout: $showScheduleWorkout
                            )
                        } else if planManager.isLoading {
                            LoadingCard()
                        } else {
                            EmptyPlanCard(message: "Tomorrow's plan is not ready yet")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(selectedDay == .today ? "Today" : "Tomorrow")
            .refreshable {
                await refreshData()
            }
            .task {
                await loadInitialData()
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
                if let walkSlot = currentPlan?.stepSlots.first {
                    ScheduleActivitySheet(
                        activityType: .walk,
                        suggestedTime: walkSlot.startTime,
                        suggestedDuration: walkSlot.duration,
                        onScheduled: {
                            Task { await planManager.generatePlans() }
                        }
                    )
                }
            }
            .sheet(isPresented: $showScheduleWorkout) {
                let currentPlan = selectedDay == .today ? planManager.todayPlan : planManager.tomorrowPlan
                if let workoutSlot = currentPlan?.workoutSlot {
                    ScheduleActivitySheet(
                        activityType: .workout,
                        suggestedTime: workoutSlot.startTime,
                        suggestedDuration: workoutSlot.duration,
                        workoutType: workoutSlot.workoutType,
                        onScheduled: {
                            Task { await planManager.generatePlans() }
                        }
                    )
                }
            }
            .sheet(isPresented: $showScheduledActivities) {
                ScheduledActivitiesListSheet()
            }
            .sheet(item: $conflictToResolve) { conflict in
                RescheduleActivitySheet(
                    activity: conflict.scheduledActivity,
                    conflictDescription: conflict.description,
                    onRescheduled: {
                        Task { await planManager.generatePlans() }
                    }
                )
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
                withAnimation { selectedDay = .today }
            } label: {
                Text("Today")
                    .font(.subheadline)
                    .fontWeight(selectedDay == .today ? .semibold : .regular)
                    .foregroundColor(selectedDay == .today ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedDay == .today ? Color.blue : Color.clear)
                    .cornerRadius(8)
            }

            Button {
                withAnimation { selectedDay = .tomorrow }
            } label: {
                Text("Tomorrow")
                    .font(.subheadline)
                    .fontWeight(selectedDay == .tomorrow ? .semibold : .regular)
                    .foregroundColor(selectedDay == .tomorrow ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedDay == .tomorrow ? Color.blue : Color.clear)
                    .cornerRadius(8)
            }
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

    private var progress: Double {
        guard goalSteps > 0 else { return 0 }
        return min(1.0, Double(currentSteps) / Double(goalSteps))
    }

    private var stepsRemaining: Int {
        max(0, goalSteps - currentSteps)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isToday ? "Steps Today" : "Projected Steps")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()

                if currentSteps >= goalSteps {
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
                        currentSteps >= goalSteps ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)

                VStack(spacing: 4) {
                    Text("\(currentSteps.formatted())")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

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
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
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
            HStack {
                Text(plan.isToday ? "Available Slots" : "Tomorrow's Slots")
                    .font(.headline)

                Spacer()

                Button {
                    showCalendar = true
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

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

// MARK: - Conflicts Alert Section

struct ConflictsAlertSection: View {
    let conflicts: [ScheduleConflict]
    var onResolve: (ScheduleConflict) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Schedule Conflicts")
                    .font(.headline)
            }

            ForEach(conflicts) { conflict in
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
                        onResolve(conflict)
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
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Scheduled Activities Section

struct ScheduledActivitiesSection: View {
    let activities: [ScheduledActivity]
    let date: Date
    var onViewAll: () -> Void

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Schedule")
                    .font(.headline)

                Spacer()

                Button {
                    onViewAll()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            ForEach(activities) { activity in
                if let timeRange = activity.getTimeRange(for: date) {
                    HStack(spacing: 12) {
                        Image(systemName: activity.icon)
                            .font(.title3)
                            .foregroundColor(activity.color)
                            .frame(width: 36, height: 36)
                            .background(activity.color.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.subheadline)
                                .fontWeight(.medium)

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

                        Text("\(activity.duration) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }
}

// MARK: - Suggested Slots Section

struct SuggestedSlotsSection: View {
    let suggestedWalk: StepSlot?
    let suggestedWorkout: WorkoutSlot?
    let hasWorkoutGoal: Bool
    var isToday: Bool = true
    var onScheduleWalk: () -> Void
    var onScheduleWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isToday ? "Suggested for Today" : "Suggested for Tomorrow")
                .font(.headline)

            // Suggested Walk
            if let walk = suggestedWalk {
                SuggestionCard(
                    icon: "figure.walk",
                    color: .green,
                    title: walk.source ?? "Walk Break",
                    time: walk.timeRangeFormatted,
                    subtitle: walk.targetStepsFormatted,
                    badgeText: "Best Time",
                    onSchedule: onScheduleWalk
                )
            }

            // Suggested Workout
            if hasWorkoutGoal, let workout = suggestedWorkout {
                SuggestionCard(
                    icon: workout.workoutType.icon,
                    color: .orange,
                    title: "\(workout.workoutType.rawValue) Workout",
                    time: workout.timeRangeFormatted,
                    subtitle: workout.workoutType.description,
                    badgeText: workout.isRecommended ? "Recommended" : nil,
                    onSchedule: onScheduleWorkout
                )
            }
        }
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
            Image(systemName: slot.workoutType.icon)
                .font(.system(size: 20))
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Workout")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(slot.workoutType.rawValue) - \(slot.workoutType.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
            print("Sync failed: \(error)")
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
