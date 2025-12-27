import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @StateObject private var notificationManager = NotificationManager.shared

    @State private var showResetConfirmation = false
    @State private var showCalendarSelection = false
    @State private var showOutlookError = false
    @State private var outlookErrorMessage = ""

    // Time picker states
    @State private var wakeTime: Date = Date()
    @State private var sleepTime: Date = Date()
    @State private var breakfastTime: Date = Date()
    @State private var lunchTime: Date = Date()
    @State private var dinnerTime: Date = Date()

    var body: some View {
        NavigationStack {
            List {
                // Daily Schedule Section
                Section {
                    TimePickerRow(
                        title: "Wake Up",
                        icon: "sunrise.fill",
                        iconColor: .orange,
                        time: $wakeTime
                    )
                    .onChange(of: wakeTime) { _, newValue in
                        userPreferences.wakeTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Sleep",
                        icon: "moon.fill",
                        iconColor: .indigo,
                        time: $sleepTime
                    )
                    .onChange(of: sleepTime) { _, newValue in
                        userPreferences.sleepTime = TimeOfDay.from(date: newValue)
                    }
                } header: {
                    Text("Daily Schedule")
                } footer: {
                    Text("Active hours: \(userPreferences.activeHours)h - Target \(userPreferences.stepsPerHour) steps/hour")
                }

                // Meal Times Section
                Section {
                    TimePickerRow(
                        title: "Breakfast",
                        icon: "cup.and.saucer.fill",
                        iconColor: .brown,
                        time: $breakfastTime
                    )
                    .onChange(of: breakfastTime) { _, newValue in
                        userPreferences.breakfastTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Lunch",
                        icon: "fork.knife",
                        iconColor: .green,
                        time: $lunchTime
                    )
                    .onChange(of: lunchTime) { _, newValue in
                        userPreferences.lunchTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Dinner",
                        icon: "fork.knife.circle.fill",
                        iconColor: .red,
                        time: $dinnerTime
                    )
                    .onChange(of: dinnerTime) { _, newValue in
                        userPreferences.dinnerTime = TimeOfDay.from(date: newValue)
                    }
                } header: {
                    Text("Meal Times")
                } footer: {
                    Text("Walk suggestions are avoided during meal times")
                }

                // Work Calendar Section - Generic for all providers
                Section {
                    // Show connected work calendars
                    if calendarManager.hasOutlookCalendar || calendarManager.hasGoogleCalendar || outlookManager.isSignedIn {
                        if outlookManager.isSignedIn {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Outlook Connected")
                                        .font(.subheadline)
                                    if let email = outlookManager.userEmail {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        if calendarManager.hasOutlookCalendar && !outlookManager.isSignedIn {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Outlook via iOS")
                                        .font(.subheadline)
                                    Text("Synced through iOS Calendar")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        if calendarManager.hasGoogleCalendar {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Google Calendar")
                                        .font(.subheadline)
                                    Text("Synced through iOS Calendar")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    // Add work calendar options
                    NavigationLink {
                        WorkCalendarSetupView()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect Work Calendar")
                                    .font(.subheadline)
                                Text("Outlook, Google, Exchange, or other SSO")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Work Calendar")
                } footer: {
                    Text("Connect your work calendar to see meetings and find walking opportunities")
                }

                // iOS Calendars Section
                Section {
                    Button {
                        showCalendarSelection = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manage All Calendars")
                                    .foregroundColor(.primary)

                                if calendarManager.isAuthorized {
                                    let selectedCount = calendarManager.selectedCalendarIDs.count
                                    let totalCount = calendarManager.availableCalendars.count
                                    Text("\(selectedCount) of \(totalCount) calendars selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Not connected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Calendar Selection")
                } footer: {
                    Text("Choose which calendars to include when finding walking opportunities")
                }

                // Calendar Sync Section
                Section {
                    NavigationLink {
                        CalendarSyncSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export to Calendar")
                                    .foregroundColor(.primary)
                                Text("Add fitness plans to your calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Export Settings")
                } footer: {
                    Text("Add your walk breaks and workouts to Google, iCloud, or Outlook calendars")
                }

                // Step Goal with Age-Based Suggestions
                Section {
                    Picker("Your Age Group", selection: Binding(
                        get: { userPreferences.ageGroup },
                        set: { userPreferences.ageGroup = $0 }
                    )) {
                        Text("Not set").tag(nil as AgeGroup?)
                        ForEach(AgeGroup.allCases, id: \.self) { age in
                            Text(age.rawValue).tag(age as AgeGroup?)
                        }
                    }

                    Stepper(
                        "Daily step goal: \(userPreferences.dailyStepGoal.formatted())",
                        value: Binding(
                            get: { userPreferences.dailyStepGoal },
                            set: { userPreferences.dailyStepGoal = $0 }
                        ),
                        in: 3000...20000,
                        step: 500
                    )

                    if let age = userPreferences.ageGroup {
                        Button("Apply Recommended: \(age.recommendedSteps.formatted()) steps") {
                            userPreferences.dailyStepGoal = age.recommendedSteps
                        }
                        .font(.caption)
                    }

                    Picker("Preferred walk time", selection: Binding(
                        get: { userPreferences.preferredWalkTime },
                        set: { userPreferences.preferredWalkTime = $0 }
                    )) {
                        ForEach(PreferredWalkTime.allCases, id: \.self) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                } header: {
                    Text("Step Goal")
                } footer: {
                    if let age = userPreferences.ageGroup {
                        Text("Recommended for \(age.rawValue): \(age.recommendedSteps.formatted()) steps/day. Walk suggestions will prioritize your preferred time.")
                    } else {
                        Text("Walk suggestions will prioritize your preferred time of day")
                    }
                }

                // Workout Preferences
                Section {
                    Picker("Gym frequency", selection: Binding(
                        get: { userPreferences.gymFrequency },
                        set: { userPreferences.gymFrequency = $0 }
                    )) {
                        ForEach(GymFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }

                    if userPreferences.gymFrequency != .none {
                        Picker("Workout duration", selection: Binding(
                            get: { userPreferences.workoutDuration },
                            set: { userPreferences.workoutDuration = $0 }
                        )) {
                            ForEach(WorkoutDuration.allCases, id: \.self) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }

                        Picker("Preferred gym time", selection: Binding(
                            get: { userPreferences.preferredGymTime },
                            set: { userPreferences.preferredGymTime = $0 }
                        )) {
                            ForEach(PreferredGymTime.allCases, id: \.self) { time in
                                Text(time.rawValue).tag(time)
                            }
                        }
                    }
                } header: {
                    Text("Workout Preferences")
                } footer: {
                    if let age = userPreferences.ageGroup, userPreferences.gymFrequency != .none {
                        Text("Recommended for \(age.rawValue): \(age.recommendedGymFrequency.displayName), \(age.recommendedWorkoutDuration.displayName)")
                    }
                }

                // Auto Walk Mode
                Section {
                    Toggle(isOn: Binding(
                        get: { userPreferences.autoWalkEnabled },
                        set: { userPreferences.autoWalkEnabled = $0 }
                    )) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto Walk Mode")
                                Text("Automatically schedule daily walk")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if userPreferences.autoWalkEnabled {
                        // Duration picker
                        Picker("Walk Duration", selection: Binding(
                            get: { userPreferences.autoWalkDuration },
                            set: { userPreferences.autoWalkDuration = $0 }
                        )) {
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("60 min").tag(60)
                            Text("90 min").tag(90)
                        }
                        .padding(.leading, 36)

                        // Preferred time picker
                        Picker("Preferred Time", selection: Binding(
                            get: { userPreferences.autoWalkPreferredTime },
                            set: { userPreferences.autoWalkPreferredTime = $0 }
                        )) {
                            ForEach(PreferredWalkTime.allCases, id: \.self) { time in
                                Text(time.rawValue).tag(time)
                            }
                        }
                        .padding(.leading, 36)

                        // Calendar sync toggle
                        Toggle(isOn: Binding(
                            get: { userPreferences.autoWalkSyncToCalendar },
                            set: { userPreferences.autoWalkSyncToCalendar = $0 }
                        )) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("Add to Calendar")
                            }
                        }
                        .padding(.leading, 8)

                        // Calendar selection
                        if userPreferences.autoWalkSyncToCalendar {
                            Picker("Sync to", selection: Binding(
                                get: { userPreferences.autoWalkCalendarID },
                                set: { userPreferences.autoWalkCalendarID = $0 }
                            )) {
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
                            .padding(.leading, 36)
                        }

                        // Status display
                        if let lastTime = AutoWalkManager.shared.lastScheduledWalkTimeFormatted,
                           let dayName = AutoWalkManager.shared.lastScheduledDayName {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Next auto walk")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(dayName) at \(lastTime)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                } header: {
                    Text("Auto Walk")
                } footer: {
                    if userPreferences.autoWalkEnabled {
                        Text("Each evening, a \(userPreferences.autoWalkDuration)-minute walk will be automatically scheduled for tomorrow based on your meetings.")
                    } else {
                        Text("When enabled, a daily walk will be automatically added to your calendar in your preferred time slot.")
                    }
                }

                // Full Autopilot Mode
                Section {
                    NavigationLink {
                        AutopilotSettingsView()
                            .environmentObject(userPreferences)
                            .environmentObject(calendarManager)
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autopilot Mode")
                                    .foregroundColor(.primary)
                                Text(userPreferences.autopilotEnabled ? "Active" : "Off")
                                    .font(.caption)
                                    .foregroundColor(userPreferences.autopilotEnabled ? .green : .secondary)
                            }
                            Spacer()
                            if userPreferences.autopilotEnabled {
                                Text(userPreferences.autopilotTrustLevel.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Invisible Fitness")
                } footer: {
                    Text("Let the app schedule your walks automatically. Zero decisions needed.")
                }

                // Your Journey / Identity
                Section {
                    NavigationLink {
                        IdentityProfileView()
                            .environmentObject(userPreferences)
                    } label: {
                        HStack {
                            Image(systemName: userPreferences.identityLevel.icon)
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Journey")
                                    .foregroundColor(.primary)
                                Text(userPreferences.identityLevel.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if userPreferences.currentStreak > 0 {
                                HStack(spacing: 4) {
                                    Text("\(userPreferences.currentStreak)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: "flame.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Progress")
                } footer: {
                    let total = userPreferences.totalWalksCompleted + userPreferences.totalWorkoutsCompleted
                    Text("\(total) total activities completed")
                }

                // Notifications
                Section {
                    if notificationManager.isAuthorized {
                        // Evening Briefing
                        Toggle(isOn: $notificationManager.eveningBriefingEnabled) {
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundColor(.indigo)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Evening Briefing")
                                    Text("Preview tomorrow's schedule")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if notificationManager.eveningBriefingEnabled {
                            DatePicker(
                                "Briefing Time",
                                selection: $notificationManager.eveningBriefingTime,
                                displayedComponents: .hourAndMinute
                            )
                            .padding(.leading, 36)
                        }

                        // Walkable Meeting Reminders
                        Toggle(isOn: $notificationManager.walkableMeetingRemindersEnabled) {
                            HStack {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Walk-This-Call Alerts")
                                    Text("Reminder before walkable meetings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if notificationManager.walkableMeetingRemindersEnabled {
                            Picker("Remind me", selection: $notificationManager.walkableMeetingLeadTime) {
                                Text("5 min before").tag(5)
                                Text("10 min before").tag(10)
                                Text("15 min before").tag(15)
                            }
                            .padding(.leading, 36)
                        }

                        // Workout Reminders
                        Toggle(isOn: $notificationManager.workoutRemindersEnabled) {
                            HStack {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundColor(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Workout Reminders")
                                    Text("Alert before scheduled workouts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        // Request Notification Permission
                        Button {
                            Task {
                                _ = try? await notificationManager.requestAuthorization()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Notifications")
                                        .foregroundColor(.primary)
                                    Text("Get timely alerts for walks & workouts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if notificationManager.isAuthorized {
                        Text("Evening briefings help you plan tomorrow. Walk-this-call alerts remind you before walkable meetings.")
                    } else {
                        Text("Enable notifications to receive smart reminders about your fitness schedule")
                    }
                }

                // Permissions Status
                Section {
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                        Spacer()
                        if healthKitManager.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not connected")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Label("Calendar", systemImage: "calendar")
                        Spacer()
                        if calendarManager.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not connected")
                                .foregroundColor(.secondary)
                        }
                    }

                    if !healthKitManager.isAuthorized || !calendarManager.isAuthorized {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Permissions")
                }

                // Feedback & Support
                Section {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send Feedback")
                                    .foregroundColor(.primary)
                                Text("Help us improve Activslot")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        requestAppStoreReview()
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 28)
                            Text("Rate on App Store")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Feedback & Support")
                } footer: {
                    Text("Your feedback helps us build a better app for busy professionals")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Button("Reset Onboarding") {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadTimeValues()
            }
            .alert("Reset Onboarding?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
            } message: {
                Text("This will show the onboarding screens again next time you open the app.")
            }
            .alert("Outlook Error", isPresented: $showOutlookError) {
                Button("OK") {}
            } message: {
                Text(outlookErrorMessage)
            }
            .sheet(isPresented: $showCalendarSelection) {
                CalendarSelectionView()
                    .environmentObject(calendarManager)
            }
        }
    }

    private func loadTimeValues() {
        wakeTime = userPreferences.wakeTime.date
        sleepTime = userPreferences.sleepTime.date
        breakfastTime = userPreferences.breakfastTime.date
        lunchTime = userPreferences.lunchTime.date
        dinnerTime = userPreferences.dinnerTime.date
    }

    private func requestAppStoreReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Time Picker Row

struct TimePickerRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var time: Date

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 28)

            Text(title)

            Spacer()

            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserPreferences.shared)
        .environmentObject(HealthKitManager.shared)
        .environmentObject(CalendarManager.shared)
        .environmentObject(OutlookManager.shared)
}
