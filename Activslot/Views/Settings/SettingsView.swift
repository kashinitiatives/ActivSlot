import SwiftUI

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

                // Outlook Calendar Section
                Section {
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

                        Button(role: .destructive) {
                            Task {
                                await outlookManager.signOut()
                            }
                        } label: {
                            Text("Sign Out of Outlook")
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await outlookManager.signIn()
                                } catch OutlookError.userCancelled {
                                    // User cancelled
                                } catch OutlookError.notConfigured {
                                    outlookErrorMessage = "Outlook integration needs to be configured."
                                    showOutlookError = true
                                } catch {
                                    outlookErrorMessage = error.localizedDescription
                                    showOutlookError = true
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connect Outlook Calendar")
                                        .font(.subheadline)
                                    Text("Sign in with your work account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if outlookManager.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(outlookManager.isLoading)
                    }
                } header: {
                    Text("Work Calendar")
                }

                // iOS Calendars Section
                Section {
                    Button {
                        showCalendarSelection = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manage iOS Calendars")
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
                    Text("iOS Calendars")
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
                                Text("Calendar Sync")
                                    .foregroundColor(.primary)
                                Text("Sync fitness plans to external calendars")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sync Settings")
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

                // Notifications
                Section {
                    Toggle("Evening plan reminder", isOn: .constant(notificationManager.isAuthorized))
                        .disabled(!notificationManager.isAuthorized)

                    Toggle("Walkable meeting alerts", isOn: .constant(notificationManager.isAuthorized))
                        .disabled(!notificationManager.isAuthorized)

                    if !notificationManager.isAuthorized {
                        Button("Enable Notifications") {
                            Task {
                                _ = try? await notificationManager.requestAuthorization()
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
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
