import SwiftUI

struct SmartPlanningSettingsView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var calendarManager: CalendarManager
    @StateObject private var planner = SmartPlannerEngine.shared

    @State private var isAnalyzing = false
    @State private var showingCalendarPicker = false

    var body: some View {
        List {
            // Step Goal Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Daily Step Goal")
                        Spacer()
                        Text("\(userPreferences.dailyStepGoal.formatted())")
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(userPreferences.dailyStepGoal) },
                            set: { userPreferences.dailyStepGoal = Int($0) }
                        ),
                        in: 5000...15000,
                        step: 1000
                    )
                    .tint(.green)

                    // Quick presets
                    HStack(spacing: 12) {
                        ForEach([6000, 8000, 10000, 12000], id: \.self) { goal in
                            Button {
                                userPreferences.dailyStepGoal = goal
                            } label: {
                                Text("\(goal/1000)K")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        userPreferences.dailyStepGoal == goal
                                        ? Color.green
                                        : Color(.secondarySystemBackground)
                                    )
                                    .foregroundColor(
                                        userPreferences.dailyStepGoal == goal
                                        ? .white
                                        : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Your Goal")
            } footer: {
                if let age = userPreferences.ageGroup {
                    Text("Recommended for \(age.rawValue): \(age.recommendedSteps.formatted()) steps/day")
                }
            }

            // Time Preferences
            Section {
                Picker("Preferred Walk Time", selection: $userPreferences.preferredWalkTime) {
                    ForEach(PreferredWalkTime.allCases, id: \.self) { time in
                        Text(time.rawValue).tag(time)
                    }
                }

                Toggle(isOn: Binding(
                    get: { userPreferences.autopilotIncludeMicroWalks },
                    set: { userPreferences.autopilotIncludeMicroWalks = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Micro-Walks")
                        Text("5-10 min walks between meetings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("The planner will prioritize these times when scheduling walks.")
            }

            // Calendar Integration
            Section {
                Toggle(isOn: Binding(
                    get: { userPreferences.autopilotTrustLevel == .fullAuto },
                    set: { newValue in
                        userPreferences.autopilotTrustLevel = newValue ? .fullAuto : .suggestOnly
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Add to Calendar")
                        Text("Automatically add planned walks to your calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if userPreferences.autopilotTrustLevel == .fullAuto {
                    Picker("Add walks to", selection: $userPreferences.autopilotCalendarID) {
                        Text("Select Calendar").tag("")
                        ForEach(calendarManager.ownedCalendars) { calendar in
                            HStack {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                            .tag(calendar.id)
                        }
                    }
                }
            } header: {
                Text("Calendar")
            }

            // Automatic Daily Planning Section
            Section {
                Toggle(isOn: $userPreferences.smartPlanAutoSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Daily Planning")
                        Text("Generate and sync walk plans daily")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if userPreferences.smartPlanAutoSyncEnabled {
                    // Calendar permission warning
                    if !calendarManager.isAuthorized {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Calendar permission required")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Calendar Picker
                    Picker("Sync to Calendar", selection: $userPreferences.smartPlanCalendarID) {
                        Text("Select Calendar").tag("")
                        ForEach(calendarManager.ownedCalendars) { calendar in
                            HStack {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                            .tag(calendar.id)
                        }
                    }

                    // Evening sync time
                    DatePicker(
                        "Evening Plan Time",
                        selection: Binding(
                            get: { userPreferences.smartPlanSyncTime.date },
                            set: { userPreferences.smartPlanSyncTime = TimeOfDay.from(date: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    // Morning refresh toggle
                    Toggle(isOn: $userPreferences.smartPlanMorningRefreshEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Morning Refresh")
                            Text("Update plan when calendar changes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Manual sync button
                    Button {
                        Task {
                            await DailyPlanSyncCoordinator.shared.syncPlan(for: Date())
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }

                    // Last sync info
                    if !userPreferences.smartPlanLastSyncDate.isEmpty {
                        HStack {
                            Text("Last synced")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(userPreferences.smartPlanLastSyncDate)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text("Automatic Daily Planning")
            } footer: {
                if userPreferences.smartPlanAutoSyncEnabled {
                    if userPreferences.smartPlanCalendarID.isEmpty {
                        Text("Select a calendar to sync your walk plans")
                            .foregroundColor(.orange)
                    } else {
                        Text("Plans are generated each evening for tomorrow and refreshed in the morning based on your calendar changes.")
                    }
                } else {
                    Text("Enable to have walk plans automatically created and synced to your calendar each day based on your patterns and preferences.")
                }
            }

            // Learning Insights
            Section {
                if let patterns = planner.userPatterns {
                    VStack(alignment: .leading, spacing: 16) {
                        PatternRow(
                            icon: "chart.bar.fill",
                            title: "Average Daily Steps",
                            value: "\(patterns.averageDailySteps.formatted())"
                        )

                        PatternRow(
                            icon: "target",
                            title: "Goal Achievement",
                            value: "\(Int(patterns.goalAchievementRate * 100))% of days"
                        )

                        PatternRow(
                            icon: "briefcase.fill",
                            title: "Weekday Average",
                            value: "\(patterns.weekdayAverage.formatted())"
                        )

                        PatternRow(
                            icon: "sun.max.fill",
                            title: "Weekend Average",
                            value: "\(patterns.weekendAverage.formatted())"
                        )

                        if let adherence = planner.planAdherence, adherence.totalPlansGenerated > 0 {
                            PatternRow(
                                icon: "checkmark.circle.fill",
                                title: "Plan Completion Rate",
                                value: "\(Int(adherence.averageCompletionRate * 100))%"
                            )
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No patterns learned yet")
                            .foregroundColor(.secondary)
                        Text("Use the app for a few days to see your activity patterns")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }

                Button {
                    reanalyzePatterns()
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Re-analyze Patterns")
                    }
                }
                .disabled(isAnalyzing)
            } header: {
                Text("Your Activity Patterns")
            } footer: {
                Text("Based on your HealthKit data from the last 30 days.")
            }

            // Best Times
            if let adherence = planner.planAdherence, !adherence.bestTimeSlots.isEmpty {
                Section {
                    ForEach(Array(adherence.bestTimeSlots.sorted(by: { $0.value > $1.value })), id: \.key) { timeSlot, rate in
                        HStack {
                            Text(timeSlot.capitalized)
                            Spacer()
                            Text("\(Int(rate * 100))% completion")
                                .foregroundColor(rate > 0.6 ? .green : rate > 0.4 ? .orange : .red)
                        }
                    }
                } header: {
                    Text("Your Best Walk Times")
                } footer: {
                    Text("Times when you're most likely to complete planned walks.")
                }
            }
        }
        .navigationTitle("Smart Planning")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reanalyzePatterns() {
        isAnalyzing = true
        Task {
            await planner.analyzeUserPatterns()
            await MainActor.run {
                isAnalyzing = false
            }
        }
    }
}

struct PatternRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        SmartPlanningSettingsView()
            .environmentObject(UserPreferences.shared)
            .environmentObject(CalendarManager.shared)
    }
}
