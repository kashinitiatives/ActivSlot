import SwiftUI

struct SmartPlanView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @StateObject private var planner = SmartPlannerEngine.shared

    @State private var selectedDate = Date()
    @State private var isRefreshing = false
    @State private var showingActivityDetail: SmartPlannerEngine.PlannedActivity?
    @State private var showingWalkableMeetings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Step Goal Progress Card
                    if let plan = planner.currentDayPlan {
                        SmartStepProgressCard(plan: plan)
                    }

                    // Today's Plan
                    if let plan = planner.currentDayPlan {
                        DailyPlanSection(
                            plan: plan,
                            onActivityTap: { activity in
                                showingActivityDetail = activity
                            },
                            onComplete: { activity in
                                planner.recordActivityCompleted(activity.id)
                                refreshPlan()
                            },
                            onSkip: { activity in
                                planner.recordActivitySkipped(activity.id)
                                refreshPlan()
                            }
                        )

                        // Walkable Meetings
                        if !plan.walkableMeetings.isEmpty {
                            WalkableMeetingsSection(meetings: plan.walkableMeetings)
                        }

                        // Plan Insights
                        PlanInsightsCard(plan: plan, patterns: planner.userPatterns)
                    } else {
                        LoadingPlanView()
                    }
                }
                .padding()
            }
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshPlan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(planner.isAnalyzing)
                }
            }
            .refreshable {
                await refreshPlanAsync()
            }
            .task {
                await initialLoad()
            }
            .sheet(item: $showingActivityDetail) { activity in
                SmartActivityDetailSheet(
                    activity: activity,
                    onAddToCalendar: {
                        Task {
                            _ = try? await planner.addToCalendar(activity)
                        }
                    }
                )
            }
        }
    }

    private func initialLoad() async {
        // Analyze patterns if not done recently
        if planner.userPatterns == nil {
            await planner.analyzeUserPatterns()
        }

        #if DEBUG
        // Auto-create sample events for testing if none exist
        let calendarManager = CalendarManager.shared
        if calendarManager.isAuthorized {
            let events = try? await calendarManager.fetchEvents(for: Date())
            if events?.isEmpty ?? true {
                print("DEBUG: No events found, creating sample schedule...")
                try? await calendarManager.createSampleEventsForTesting()
            }
        }
        #endif

        _ = await planner.generateDailyPlan(for: Date())
    }

    private func refreshPlan() {
        Task {
            await refreshPlanAsync()
        }
    }

    private func refreshPlanAsync() async {
        _ = await planner.generateDailyPlan(for: selectedDate)
    }
}

// MARK: - Step Goal Progress Card

struct SmartStepProgressCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan

    private var progress: Double {
        guard plan.targetSteps > 0 else { return 0 }
        return min(1.0, Double(plan.estimatedCurrentSteps) / Double(plan.targetSteps))
    }

    private var plannedProgress: Double {
        guard plan.targetSteps > 0 else { return 0 }
        return min(1.0, Double(plan.estimatedCurrentSteps + plan.totalPlannedSteps) / Double(plan.targetSteps))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step Goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(plan.estimatedCurrentSteps.formatted())")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(plan.stepsNeeded == 0 ? .green : .primary)
                            .contentTransition(.numericText())
                        Text("/ \(plan.targetSteps.formatted())")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Confidence indicator with label
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Plan Confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < Int(plan.confidence * 5) ? Color.green : Color.gray.opacity(0.2))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            // Progress ring with gradient
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 14)

                // Planned progress (lighter)
                Circle()
                    .trim(from: 0, to: plannedProgress)
                    .stroke(
                        Color.green.opacity(0.25),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Current progress with gradient
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [.green.opacity(0.7), .green],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)

                // Center content
                VStack(spacing: 6) {
                    if plan.stepsNeeded > 0 {
                        Text("\(plan.stepsNeeded.formatted())")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("steps to go")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce, value: plan.stepsNeeded)
                        Text("Goal reached!")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(height: 160)
            .padding(.vertical, 8)

            // Plan summary
            HStack(spacing: 16) {
                // Scheduled walks
                VStack {
                    Text("\(plan.activities.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Walks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Steps from scheduled walks
                VStack {
                    let walkSteps = plan.activities.reduce(0) { $0 + $1.estimatedSteps }
                    Text("~\(walkSteps.formatted())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("From walks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Walking meetings
                VStack {
                    let walkingMeetings = plan.walkableMeetings.filter { $0.isRecommended }.count
                    Text("\(walkingMeetings)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Walk meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Steps from walking meetings
                VStack {
                    let meetingSteps = plan.walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }
                    Text("~\(meetingSteps.formatted())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("From meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Reasoning
            Text(plan.reasoning)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Daily Plan Section

struct DailyPlanSection: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let onActivityTap: (SmartPlannerEngine.PlannedActivity) -> Void
    let onComplete: (SmartPlannerEngine.PlannedActivity) -> Void
    let onSkip: (SmartPlannerEngine.PlannedActivity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Movement Plan")
                .font(.headline)

            if plan.activities.isEmpty {
                let meetingSteps = plan.walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }
                let goalCoveredByMeetings = plan.stepsNeeded > 0 && meetingSteps >= plan.stepsNeeded

                VStack(spacing: 12) {
                    if plan.stepsNeeded == 0 {
                        // User already hit their step goal
                        Image(systemName: "trophy.fill")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text("Goal achieved!")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("You've already hit your step goal today. Keep up the great work!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if goalCoveredByMeetings && meetingSteps > 0 {
                        // Walking meetings can cover remaining goal
                        Image(systemName: "figure.walk.motion")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Walking meetings can cover your goal!")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Take your \(plan.walkableMeetings.filter { $0.isRecommended }.count) recommended meetings as walking calls to hit ~\(meetingSteps.formatted()) steps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if !plan.walkableMeetings.isEmpty {
                        // Has walkable meetings but not enough
                        Image(systemName: "figure.walk")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("No walks scheduled")
                            .foregroundColor(.secondary)
                        Text("Your calendar is packed, but consider the walking meetings below!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        // No walks and no walkable meetings
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No walks scheduled")
                            .foregroundColor(.secondary)
                        Text("Your calendar is very busy today. Try to find small gaps for quick walks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(plan.activities) { activity in
                    ActivityRow(
                        activity: activity,
                        onTap: { onActivityTap(activity) },
                        onComplete: { onComplete(activity) },
                        onSkip: { onSkip(activity) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct ActivityRow: View {
    let activity: SmartPlannerEngine.PlannedActivity
    let onTap: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var icon: String {
        switch activity.type {
        case .microWalk: return "figure.walk"
        case .morningWalk: return "sunrise.fill"
        case .lunchWalk: return "fork.knife"
        case .eveningWalk: return "sunset.fill"
        case .scheduledWalk: return "figure.walk.motion"
        case .postMeetingWalk: return "arrow.right.circle"
        case .gymWorkout: return "dumbbell.fill"
        }
    }

    private var priorityColor: Color {
        switch activity.priority {
        case .critical: return .red
        case .recommended: return .orange
        case .optional: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status/Type indicator
            ZStack {
                Circle()
                    .fill(activity.status == .completed ? Color.green : priorityColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                if activity.status == .completed {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(priorityColor)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activityTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .strikethrough(activity.status == .skipped)

                    if activity.priority == .critical {
                        Text("KEY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                Text(timeFormatter.string(from: activity.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("~\(activity.estimatedSteps) steps • \(activity.duration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            if activity.status == .planned {
                HStack(spacing: 8) {
                    Button {
                        onComplete()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }

                    Button {
                        onSkip()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: activity.status == .completed ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundColor(activity.status == .completed ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var activityTitle: String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning Walk"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening Walk"
        case .scheduledWalk: return "Scheduled Walk"
        case .postMeetingWalk: return "Post-Meeting Walk"
        case .gymWorkout: return "Gym Workout"
        }
    }
}

// MARK: - Walkable Meetings Section

struct WalkableMeetingsSection: View {
    let meetings: [SmartPlannerEngine.WalkableMeeting]

    private var recommendedMeetings: [SmartPlannerEngine.WalkableMeeting] {
        meetings.filter { $0.isRecommended }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.wave.2")
                    .foregroundColor(.blue)
                Text("Walking Meeting Opportunities")
                    .font(.headline)
            }

            if recommendedMeetings.isEmpty {
                Text("No ideal walking meetings today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(recommendedMeetings) { meeting in
                    SmartWalkableMeetingRow(meeting: meeting)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct SmartWalkableMeetingRow: View {
    let meeting: SmartPlannerEngine.WalkableMeeting

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "phone.and.waveform")
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack {
                    Text(timeFormatter.string(from: meeting.startTime))
                    Text("•")
                    Text("\(meeting.duration) min")
                    if meeting.isOneOnOne {
                        Text("• 1:1")
                            .foregroundColor(.green)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("+\(meeting.estimatedSteps)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Text("steps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Plan Insights Card

struct PlanInsightsCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let patterns: SmartPlannerEngine.UserActivityPatterns?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Insights")
                    .font(.headline)
            }

            if let patterns = patterns {
                VStack(alignment: .leading, spacing: 8) {
                    InsightRow(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Your average: \(patterns.averageDailySteps.formatted()) steps/day"
                    )

                    InsightRow(
                        icon: "target",
                        text: "Goal hit rate: \(Int(patterns.goalAchievementRate * 100))% of days"
                    )

                    if patterns.weekdayAverage < patterns.weekendAverage {
                        InsightRow(
                            icon: "briefcase",
                            text: "Weekdays are harder - \(patterns.weekdayAverage.formatted()) vs \(patterns.weekendAverage.formatted()) steps"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct InsightRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Loading View

struct LoadingPlanView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your calendar...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Smart Activity Detail Sheet

struct SmartActivityDetailSheet: View {
    let activity: SmartPlannerEngine.PlannedActivity
    let onAddToCalendar: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text(activityTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(timeFormatter.string(from: activity.startTime))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Stats
                HStack(spacing: 30) {
                    VStack {
                        Text("\(activity.duration)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("minutes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("~\(activity.estimatedSteps)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Reason
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why this time?")
                        .font(.headline)
                    Text(activity.reason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                // Add to calendar button
                Button {
                    onAddToCalendar()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Add to Calendar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .navigationTitle("Activity Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var activityTitle: String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning Walk"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening Walk"
        case .scheduledWalk: return "Scheduled Walk"
        case .postMeetingWalk: return "Post-Meeting Walk"
        case .gymWorkout: return "Gym Workout"
        }
    }
}

#Preview {
    SmartPlanView()
        .environmentObject(UserPreferences.shared)
}
