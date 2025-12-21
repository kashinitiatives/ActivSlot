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

                    Text("Follow these steps to sync your Outlook/Exchange calendar to your iPhone.")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Steps
                VStack(alignment: .leading, spacing: 20) {
                    SetupStep(number: 1, title: "Open Settings", description: "Go to your iPhone's Settings app")

                    SetupStep(number: 2, title: "Tap Calendar", description: "Scroll down and tap 'Calendar'")

                    SetupStep(number: 3, title: "Tap Accounts", description: "Select 'Accounts' at the top")

                    SetupStep(number: 4, title: "Add Account", description: "Tap 'Add Account' and select 'Microsoft Exchange' or 'Outlook.com'")

                    SetupStep(number: 5, title: "Sign In", description: "Enter your work email and password. Your IT department may require additional authentication.")

                    SetupStep(number: 6, title: "Enable Calendars", description: "Make sure 'Calendars' is toggled ON")

                    SetupStep(number: 7, title: "Return to Activslot", description: "Come back here and your Outlook calendar will appear!")
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
        .navigationTitle("Outlook Setup")
        .navigationBarTitleDisplayMode(.inline)
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
