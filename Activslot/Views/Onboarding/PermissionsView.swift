import SwiftUI

struct PermissionsView: View {
    let onContinue: () -> Void

    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @State private var isRequestingPermissions = false
    @State private var healthPermissionGranted = false
    @State private var calendarPermissionGranted = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCalendarSetup = false
    @State private var showOutlookSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 32)

            // Title
            Text("Connect Your Data")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 12)

            // Subtitle
            Text("We use your calendar to suggest better\ntimes to walk or work out.\nWe never modify your calendar.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)

            // Permission items
            VStack(spacing: 16) {
                PermissionItem(
                    icon: "heart.fill",
                    title: "Apple Health",
                    subtitle: "Steps, Workouts, Active energy",
                    isGranted: healthPermissionGranted
                )

                PermissionItem(
                    icon: "calendar",
                    title: "Calendar",
                    subtitle: "Read-only access to find free time",
                    isGranted: calendarPermissionGranted
                )
            }
            .padding(.horizontal, 32)

            // Outlook sign-in option
            if calendarPermissionGranted && !outlookManager.isSignedIn {
                OutlookSignInPrompt(showOutlookSignIn: $showOutlookSignIn)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)
            } else if outlookManager.isSignedIn {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Outlook connected: \(outlookManager.userEmail ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
            }

            Spacer()

            // CTA Button
            Button(action: requestPermissions) {
                HStack {
                    if isRequestingPermissions {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Text("Allow & Continue")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(14)
            }
            .disabled(isRequestingPermissions)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Skip button
            Button(action: onContinue) {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
        .alert("Permission Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showCalendarSetup) {
            CalendarSetupSheet(onDone: {
                showCalendarSetup = false
                onContinue()
            })
        }
        .sheet(isPresented: $showOutlookSignIn) {
            OutlookSignInSheet(onDone: {
                showOutlookSignIn = false
                onContinue()
            })
            .environmentObject(outlookManager)
            .environmentObject(calendarManager)
        }
    }

    private func requestPermissions() {
        isRequestingPermissions = true

        Task {
            // Request HealthKit permissions
            do {
                let healthGranted = try await healthKitManager.requestAuthorization()
                await MainActor.run {
                    healthPermissionGranted = healthGranted
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to access Health data: \(error.localizedDescription)"
                    showError = true
                }
            }

            // Request Calendar permissions
            do {
                let calendarGranted = try await calendarManager.requestAuthorization()
                await MainActor.run {
                    calendarPermissionGranted = calendarGranted

                    // Check if Outlook calendar is missing - prompt to sign in directly
                    if calendarGranted && !calendarManager.hasOutlookCalendar && !outlookManager.isSignedIn {
                        showOutlookSignIn = true
                        isRequestingPermissions = false
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to access Calendar: \(error.localizedDescription)"
                    showError = true
                }
            }

            await MainActor.run {
                isRequestingPermissions = false
                onContinue()
            }
        }
    }
}

// MARK: - Calendar Sync Hint

struct CalendarSyncHint: View {
    @Binding var showCalendarSetup: Bool
    @EnvironmentObject var calendarManager: CalendarManager

    var body: some View {
        if calendarManager.hasOutlookCalendar || calendarManager.hasGoogleCalendar {
            // Show connected sources
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text("Connected: \(calendarManager.connectedSources.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            // Prompt to add work calendar
            Button {
                showCalendarSetup = true
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text("Add your work calendar for best results")
                        .font(.caption)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Calendar Setup Sheet

struct CalendarSetupSheet: View {
    let onDone: () -> Void
    @EnvironmentObject var calendarManager: CalendarManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 56))
                            .foregroundColor(.blue)

                        Text("Add Your Work Calendar")
                            .font(.title2)
                            .bold()

                        Text("Sync your Outlook or Google calendar to see your meetings and find walkable time slots.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)

                    Divider()
                        .padding(.horizontal)

                    // Setup options
                    VStack(spacing: 16) {
                        NavigationLink {
                            OutlookSetupGuideView()
                        } label: {
                            CalendarSetupOption(
                                icon: "envelope.fill",
                                iconColor: .blue,
                                title: "Outlook / Exchange",
                                subtitle: "For work & corporate calendars"
                            )
                        }

                        NavigationLink {
                            GoogleSetupGuideView()
                        } label: {
                            CalendarSetupOption(
                                icon: "g.circle.fill",
                                iconColor: .red,
                                title: "Google Calendar",
                                subtitle: "For personal & workspace calendars"
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Already synced section
                    if !calendarManager.availableCalendars.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Already Connected")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(calendarManager.availableCalendars.prefix(5)) { calendar in
                                HStack {
                                    Circle()
                                        .fill(calendar.color)
                                        .frame(width: 10, height: 10)

                                    Text(calendar.title)
                                        .font(.subheadline)

                                    Spacer()

                                    Text(calendar.source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }

                            if calendarManager.availableCalendars.count > 5 {
                                Text("+\(calendarManager.availableCalendars.count - 5) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Calendar Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") {
                        onDone()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CalendarSetupOption: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(iconColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Permission Item

struct PermissionItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Outlook Sign In Prompt

struct OutlookSignInPrompt: View {
    @Binding var showOutlookSignIn: Bool
    @EnvironmentObject var outlookManager: OutlookManager

    var body: some View {
        Button {
            showOutlookSignIn = true
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)

                Text("Connect your work calendar")
                    .font(.caption)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - Outlook Sign In Sheet

struct OutlookSignInSheet: View {
    let onDone: () -> Void
    @EnvironmentObject var outlookManager: OutlookManager
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedOption: CalendarOption = .iosSync

    enum CalendarOption {
        case iosSync
        case microsoftSignIn
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 56))
                        .foregroundColor(.blue)
                        .padding(.top, 24)

                    // Title
                    Text("Connect Work Calendar")
                        .font(.title2)
                        .bold()

                    // Description
                    Text("See your meetings to find the best times for walks and workouts.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Show detected calendars from iOS
                    if !calendarManager.availableCalendars.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Calendars Found on Device")
                                .font(.headline)

                            ForEach(calendarManager.availableCalendars) { calendar in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(calendar.color)
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.title)
                                            .font(.subheadline)
                                        Text(calendar.source)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: calendarManager.selectedCalendarIDs.contains(calendar.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(calendarManager.selectedCalendarIDs.contains(calendar.id) ? .green : .gray)
                                }
                                .padding(.vertical, 4)
                            }

                            if calendarManager.hasOutlookCalendar {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Outlook calendar detected!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                    }

                    // Options
                    VStack(spacing: 12) {
                        // Option 1: Use iOS Calendar (Recommended)
                        CalendarOptionCard(
                            isSelected: selectedOption == .iosSync,
                            icon: "iphone",
                            title: "Use iPhone Calendar",
                            subtitle: "Works with any Outlook account synced to your iPhone. No IT approval needed.",
                            badge: "Recommended"
                        ) {
                            selectedOption = .iosSync
                        }

                        // Option 2: Microsoft Sign In (May require IT)
                        CalendarOptionCard(
                            isSelected: selectedOption == .microsoftSignIn,
                            icon: "person.badge.key",
                            title: "Sign in with Microsoft",
                            subtitle: "Direct API access. May require IT admin approval for work accounts.",
                            badge: nil
                        ) {
                            selectedOption = .microsoftSignIn
                        }
                    }
                    .padding(.horizontal, 24)

                    // Setup instructions for iOS sync
                    if selectedOption == .iosSync && !calendarManager.hasOutlookCalendar {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How to add Outlook to iPhone")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            VStack(alignment: .leading, spacing: 8) {
                                SetupStepRow(number: 1, text: "Open iPhone Settings")
                                SetupStepRow(number: 2, text: "Tap Calendar → Accounts")
                                SetupStepRow(number: 3, text: "Add Account → Microsoft Exchange")
                                SetupStepRow(number: 4, text: "Enter your work email")
                            }

                            Button {
                                if let url = URL(string: "App-Prefs:root=ACCOUNTS_AND_PASSWORDS") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Open Settings")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 20)

                    // CTA Button
                    Button {
                        if selectedOption == .iosSync {
                            // Just use iOS calendars - already have permission
                            onDone()
                        } else {
                            // Try Microsoft sign in
                            Task {
                                do {
                                    try await outlookManager.signIn()
                                    onDone()
                                } catch OutlookError.userCancelled {
                                    // User cancelled
                                } catch OutlookError.notConfigured {
                                    errorMessage = "Microsoft sign-in requires IT admin setup. We recommend using the iPhone Calendar option instead."
                                    showError = true
                                } catch {
                                    errorMessage = "\(error.localizedDescription)\n\nTip: If your organization blocks this, use the iPhone Calendar option instead."
                                    showError = true
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if outlookManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text(selectedOption == .iosSync ? "Continue" : "Sign in with Microsoft")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                    }
                    .disabled(outlookManager.isLoading)
                    .padding(.horizontal, 24)

                    // Skip Button
                    Button("Skip for now") {
                        onDone()
                    }
                    .foregroundColor(.secondary)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Work Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onDone()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .alert("Sign In Issue", isPresented: $showError) {
                Button("Use iPhone Calendar") {
                    selectedOption = .iosSync
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}

// MARK: - Calendar Option Card

struct CalendarOptionCard: View {
    let isSelected: Bool
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Setup Step Row

struct SetupStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .cornerRadius(10)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    PermissionsView(onContinue: {})
        .environmentObject(HealthKitManager.shared)
        .environmentObject(CalendarManager.shared)
        .environmentObject(OutlookManager.shared)
}
