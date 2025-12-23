import SwiftUI

struct CalendarSelectionView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @Environment(\.dismiss) private var dismiss
    @State private var showEmailInput = false
    @State private var newEmail = ""

    var body: some View {
        NavigationStack {
            List {
                if calendarManager.availableCalendars.isEmpty {
                    NoCalendarsSection()
                } else {
                    // Your email section - for filtering
                    Section {
                        if calendarManager.userEmailAddresses.isEmpty {
                            Button {
                                showEmailInput = true
                            } label: {
                                HStack {
                                    Image(systemName: "envelope.badge.fill")
                                        .foregroundColor(.orange)
                                    Text("Add Your Email Address")
                                        .foregroundColor(.primary)
                                }
                            }
                        } else {
                            ForEach(Array(calendarManager.userEmailAddresses).sorted(), id: \.self) { email in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(email)
                                        .foregroundColor(.primary)
                                }
                            }
                            Button {
                                showEmailInput = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Add Another Email")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    } header: {
                        Text("Your Email Addresses")
                    } footer: {
                        Text("Calendars matching these emails will be marked as yours. Others will be marked as shared.")
                    }

                    // Quick actions section
                    Section {
                        Button {
                            calendarManager.selectOnlyOwnedCalendars()
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                                Text("Show Only My Calendars")
                                    .foregroundColor(.primary)
                            }
                        }

                        Button {
                            calendarManager.selectAllCalendars()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Select All")
                                    .foregroundColor(.primary)
                            }
                        }

                        Button {
                            calendarManager.deselectAllCalendars()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Deselect All")
                                    .foregroundColor(.primary)
                            }
                        }
                    } footer: {
                        Text("Excludes shared and subscribed calendars from other people")
                    }

                    // My calendars (owned)
                    if !calendarManager.ownedCalendars.isEmpty {
                        OwnedCalendarsSection()
                    }

                    // Subscribed/shared calendars (if any)
                    if !calendarManager.subscribedCalendars.isEmpty {
                        SubscribedCalendarsSection()
                    }

                    // Setup guides
                    if !calendarManager.hasOutlookCalendar || !calendarManager.hasGoogleCalendar {
                        SetupGuidesSection()
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Add Your Email", isPresented: $showEmailInput) {
                TextField("email@example.com", text: $newEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Button("Cancel", role: .cancel) {
                    newEmail = ""
                }
                Button("Add") {
                    if !newEmail.isEmpty && newEmail.contains("@") {
                        calendarManager.addUserEmail(newEmail.lowercased())
                        newEmail = ""
                    }
                }
            } message: {
                Text("Enter your email address to help identify which calendars belong to you.")
            }
        }
    }
}

// MARK: - Owned Calendars Section (User's own calendars)

struct OwnedCalendarsSection: View {
    @EnvironmentObject var calendarManager: CalendarManager

    var groupedCalendars: [(String, [CalendarInfo])] {
        Dictionary(grouping: calendarManager.ownedCalendars) { $0.source }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        ForEach(groupedCalendars, id: \.0) { source, calendars in
            Section {
                ForEach(calendars) { calendar in
                    CalendarRow(calendar: calendar)
                }
            } header: {
                HStack {
                    Image(systemName: calendars.first?.sourceIcon ?? "calendar")
                    Text(source)
                }
            }
        }
    }
}

// MARK: - Subscribed Calendars Section (Shared/other people's calendars)

struct SubscribedCalendarsSection: View {
    @EnvironmentObject var calendarManager: CalendarManager

    var groupedCalendars: [(String, [CalendarInfo])] {
        Dictionary(grouping: calendarManager.subscribedCalendars) { $0.source }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        Section {
            ForEach(groupedCalendars, id: \.0) { source, calendars in
                ForEach(calendars) { calendar in
                    CalendarRow(calendar: calendar, isSubscribed: true)
                }
            }
        } header: {
            HStack {
                Image(systemName: "person.2.fill")
                Text("Shared Calendars")
            }
        } footer: {
            Text("These calendars belong to other people. Events from these calendars will show as busy time but won't be used for activity suggestions.")
        }
    }
}

struct CalendarRow: View {
    let calendar: CalendarInfo
    var isSubscribed: Bool = false
    @EnvironmentObject var calendarManager: CalendarManager

    var body: some View {
        HStack {
            // Calendar color indicator
            Circle()
                .fill(calendar.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .foregroundColor(.primary)

                if isSubscribed {
                    Text("Shared")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // iOS Calendar-style toggle
            Toggle("", isOn: Binding(
                get: { calendarManager.isCalendarSelected(calendar.id) },
                set: { _ in calendarManager.toggleCalendarSelection(calendar.id) }
            ))
            .labelsHidden()
            .tint(calendar.color)
        }
    }
}

// MARK: - No Calendars Section

struct NoCalendarsSection: View {
    var body: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No Calendars Found")
                    .font(.headline)

                Text("Add your work calendar to your iPhone to see your meetings here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }

        SetupGuidesSection()
    }
}

// MARK: - Setup Guides Section

struct SetupGuidesSection: View {
    @EnvironmentObject var calendarManager: CalendarManager

    var body: some View {
        Section {
            if !calendarManager.hasOutlookCalendar {
                NavigationLink {
                    OutlookSetupGuideView()
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading) {
                            Text("Add Outlook Calendar")
                                .font(.subheadline)
                            Text("Sync your work meetings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if !calendarManager.hasGoogleCalendar {
                NavigationLink {
                    GoogleSetupGuideView()
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 28)

                        VStack(alignment: .leading) {
                            Text("Add Google Calendar")
                                .font(.subheadline)
                            Text("Sync your personal meetings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Add More Calendars")
        } footer: {
            Text("Syncing calendars to your iPhone lets Activslot find walkable meetings automatically.")
        }
    }
}

// MARK: - Outlook Setup Guide

struct OutlookSetupGuideView: View {
    @State private var selectedMethod: OutlookSetupMethod = .iosCalendar

    enum OutlookSetupMethod: String, CaseIterable {
        case iosCalendar = "iOS Calendar"
        case outlookApp = "Outlook App"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)

                    Text("Add Outlook Calendar")
                        .font(.title2)
                        .bold()

                    Text("Choose how to sync your Outlook/Exchange calendar.")
                        .foregroundColor(.secondary)
                }

                // Admin Permission Warning
                AdminPermissionWarningCard()

                Divider()

                // Method Picker
                Picker("Setup Method", selection: $selectedMethod) {
                    ForEach(OutlookSetupMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                if selectedMethod == .iosCalendar {
                    IOSCalendarSyncGuide()
                } else {
                    OutlookAppSyncGuide()
                }
            }
            .padding()
        }
        .navigationTitle("Outlook Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Admin Permission Warning Card

struct AdminPermissionWarningCard: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Work Account Requires Admin Approval?")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Tap for alternative setup options")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If your organization requires admin approval for third-party apps, you can still sync your calendar!")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Use **iOS Calendar** method below - no admin approval needed")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Your IT already approved iOS Calendar access")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Activslot reads from iOS Calendar, not Outlook directly")
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - iOS Calendar Sync Guide (Recommended)

struct IOSCalendarSyncGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Recommendation badge
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Recommended - Works without admin approval")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            Text("Sync Outlook to iOS Calendar")
                .font(.headline)

            Text("This method syncs your Outlook calendar to the built-in iOS Calendar app. Activslot then reads from iOS Calendar - no direct Outlook connection needed.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                SetupStepWithIcon(
                    number: 1,
                    icon: "gear",
                    title: "Open iPhone Settings",
                    description: "Go to your iPhone's Settings app"
                )

                SetupStepWithIcon(
                    number: 2,
                    icon: "calendar",
                    title: "Tap Calendar",
                    description: "Scroll down and tap 'Calendar'"
                )

                SetupStepWithIcon(
                    number: 3,
                    icon: "person.crop.circle",
                    title: "Tap Accounts",
                    description: "Select 'Accounts' at the top"
                )

                SetupStepWithIcon(
                    number: 4,
                    icon: "plus.circle.fill",
                    title: "Add Account",
                    description: "Tap 'Add Account' → Select 'Microsoft Exchange'"
                )

                SetupStepWithIcon(
                    number: 5,
                    icon: "envelope.fill",
                    title: "Enter Work Email",
                    description: "Type your work email address and tap 'Next'"
                )

                SetupStepWithIcon(
                    number: 6,
                    icon: "lock.shield.fill",
                    title: "Sign In with SSO",
                    description: "Your company's login page will appear. Sign in with your work credentials."
                )

                SetupStepWithIcon(
                    number: 7,
                    icon: "calendar.badge.checkmark",
                    title: "Enable Calendars",
                    description: "Toggle ON 'Calendars' (you can disable Mail, Contacts, etc. if you prefer)"
                )

                SetupStepWithIcon(
                    number: 8,
                    icon: "arrow.uturn.backward.circle.fill",
                    title: "Return to Activslot",
                    description: "Come back here - your Outlook calendar will appear automatically!"
                )
            }

            Divider()

            // Open Settings buttons
            VStack(spacing: 12) {
                Button {
                    // Try to open Calendar settings directly
                    if let url = URL(string: "App-prefs:CALENDAR") {
                        UIApplication.shared.open(url)
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Open Calendar Settings")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Text("After adding the account, return here and tap 'Done' to refresh.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Outlook App Sync Guide

struct OutlookAppSyncGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Warning badge
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("May require IT admin approval")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            Text("Use Outlook App Calendar Sync")
                .font(.headline)

            Text("If you have the Outlook app installed, you can sync its calendar to iOS Calendar.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                SetupStepWithIcon(
                    number: 1,
                    icon: "app.badge.fill",
                    title: "Install Outlook App",
                    description: "Download Microsoft Outlook from the App Store if not installed"
                )

                SetupStepWithIcon(
                    number: 2,
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Sign In to Outlook",
                    description: "Open Outlook and sign in with your work account"
                )

                SetupStepWithIcon(
                    number: 3,
                    icon: "gearshape.fill",
                    title: "Open Outlook Settings",
                    description: "Tap your profile icon → Settings (gear icon)"
                )

                SetupStepWithIcon(
                    number: 4,
                    icon: "envelope.fill",
                    title: "Select Your Account",
                    description: "Tap on your work email account"
                )

                SetupStepWithIcon(
                    number: 5,
                    icon: "calendar.badge.plus",
                    title: "Sync Calendars",
                    description: "Toggle ON 'Sync Calendars' to sync with iOS Calendar"
                )

                SetupStepWithIcon(
                    number: 6,
                    icon: "arrow.uturn.backward.circle.fill",
                    title: "Return to Activslot",
                    description: "Your Outlook calendar will appear in the list!"
                )
            }

            Divider()

            // Open Outlook button
            VStack(spacing: 12) {
                Button {
                    // Try to open Outlook app
                    if let url = URL(string: "ms-outlook://") {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else {
                            // Open App Store to Outlook
                            if let appStoreURL = URL(string: "https://apps.apple.com/app/microsoft-outlook/id951937596") {
                                UIApplication.shared.open(appStoreURL)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Open Outlook App")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Text("If Outlook is not installed, this will open the App Store.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Setup Step With Icon

struct SetupStepWithIcon: View {
    let number: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Google Setup Guide

struct GoogleSetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.red)

                    Text("Add Google Calendar")
                        .font(.title2)
                        .bold()

                    Text("Follow these steps to sync your Google calendar to your iPhone.")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Steps
                VStack(alignment: .leading, spacing: 20) {
                    SetupStep(number: 1, title: "Open Settings", description: "Go to your iPhone's Settings app")

                    SetupStep(number: 2, title: "Tap Calendar", description: "Scroll down and tap 'Calendar'")

                    SetupStep(number: 3, title: "Tap Accounts", description: "Select 'Accounts' at the top")

                    SetupStep(number: 4, title: "Add Account", description: "Tap 'Add Account' and select 'Google'")

                    SetupStep(number: 5, title: "Sign In", description: "Enter your Google email and password")

                    SetupStep(number: 6, title: "Enable Calendars", description: "Make sure 'Calendars' is toggled ON")

                    SetupStep(number: 7, title: "Return to Activslot", description: "Come back here and your Google calendar will appear!")
                }

                Divider()

                // Open Settings button
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open iPhone Settings")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Google Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Setup Step Component

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    CalendarSelectionView()
        .environmentObject(CalendarManager.shared)
}
