import SwiftUI

// MARK: - Autopilot Settings View

struct AutopilotSettingsView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var calendarManager: CalendarManager
    @StateObject private var autopilotManager = AutopilotManager.shared

    @State private var showTrustLevelInfo = false

    var body: some View {
        Form {
            // Main Toggle
            Section {
                Toggle(isOn: $userPreferences.autopilotEnabled) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Autopilot Mode")
                                .font(.headline)
                            Text("Automatically schedule walks for you")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .tint(.blue)
            } header: {
                Text("Invisible Fitness")
            } footer: {
                Text("When enabled, walks appear on your calendar automatically. No decisions needed.")
            }

            if userPreferences.autopilotEnabled {
                // Trust Level
                Section {
                    ForEach(AutopilotTrustLevel.allCases, id: \.self) { level in
                        TrustLevelRow(
                            level: level,
                            isSelected: userPreferences.autopilotTrustLevel == level,
                            onTap: {
                                withAnimation {
                                    userPreferences.autopilotTrustLevel = level
                                }
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("Trust Level")
                        Spacer()
                        Button {
                            showTrustLevelInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text(userPreferences.autopilotTrustLevel.description)
                }

                // Walk Settings
                Section {
                    Stepper(value: $userPreferences.autopilotWalksPerDay, in: 1...5) {
                        HStack {
                            Text("Walks per day")
                            Spacer()
                            Text("\(userPreferences.autopilotWalksPerDay)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $userPreferences.autopilotIncludeMicroWalks) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Micro-Walks")
                            Text("5-10 min walks between meetings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Walk Duration")
                        Spacer()
                        Text("\(userPreferences.autopilotMinWalkDuration)-\(userPreferences.autopilotMaxWalkDuration) min")
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum: \(userPreferences.autopilotMinWalkDuration) min")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { Double(userPreferences.autopilotMinWalkDuration) },
                                set: { userPreferences.autopilotMinWalkDuration = Int($0) }
                            ),
                            in: 5...20,
                            step: 5
                        )

                        Text("Maximum: \(userPreferences.autopilotMaxWalkDuration) min")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { Double(userPreferences.autopilotMaxWalkDuration) },
                                set: { userPreferences.autopilotMaxWalkDuration = Int($0) }
                            ),
                            in: 15...60,
                            step: 5
                        )
                    }
                } header: {
                    Text("Walk Preferences")
                }

                // Calendar Selection
                Section {
                    Picker("Add walks to", selection: $userPreferences.autopilotCalendarID) {
                        Text("Don't add to calendar").tag("")
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
                } header: {
                    Text("Calendar")
                } footer: {
                    if userPreferences.autopilotTrustLevel == .fullAuto {
                        Text("Walks will appear as events on your selected calendar. Others can see when you're walking.")
                    } else {
                        Text("Choose where to add walks once you approve them.")
                    }
                }

                // Status
                if !autopilotManager.lastScheduledWalks.isEmpty {
                    Section {
                        ForEach(autopilotManager.lastScheduledWalks) { walk in
                            ScheduledWalkRow(walk: walk)
                        }
                    } header: {
                        Text("Upcoming Scheduled Walks")
                    }
                }

                // Pending Approvals
                if !autopilotManager.pendingApprovals.isEmpty {
                    Section {
                        ForEach(autopilotManager.pendingApprovals) { walk in
                            PendingApprovalRow(
                                walk: walk,
                                onApprove: {
                                    Task {
                                        await autopilotManager.approveWalk(walk.id)
                                    }
                                },
                                onReject: {
                                    Task {
                                        await autopilotManager.rejectWalk(walk.id)
                                    }
                                }
                            )
                        }
                    } header: {
                        Text("Pending Approval")
                    }
                }
            }
        }
        .navigationTitle("Autopilot")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTrustLevelInfo) {
            TrustLevelInfoSheet()
        }
    }
}

// MARK: - Trust Level Row

struct TrustLevelRow: View {
    let level: AutopilotTrustLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: level.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scheduled Walk Row

struct ScheduledWalkRow: View {
    let walk: AutopilotManager.ScheduledWalk

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: walk.type.icon)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(walk.type.displayName)
                    .font(.subheadline)

                Text("\(timeFormatter.string(from: walk.startTime)) • \(walk.duration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if walk.isApproved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Pending Approval Row

struct PendingApprovalRow: View {
    let walk: AutopilotManager.ScheduledWalk
    let onApprove: () -> Void
    let onReject: () -> Void

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: walk.type.icon)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(walk.type.displayName)
                        .font(.subheadline)

                    Text("\(timeFormatter.string(from: walk.startTime)) • \(walk.duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Text("Approve")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                Button(action: onReject) {
                    Text("Skip")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trust Level Info Sheet

struct TrustLevelInfoSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(AutopilotTrustLevel.allCases, id: \.self) { level in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: level.icon)
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text(level.displayName)
                                    .font(.headline)
                            }

                            Text(level.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(detailedDescription(for: level))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Trust Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailedDescription(for level: AutopilotTrustLevel) -> String {
        switch level {
        case .fullAuto:
            return "Best for: People who want zero friction. Walks appear on your calendar overnight. You wake up and your day is planned."
        case .confirmFirst:
            return "Best for: People who want control but don't want to think about timing. You get a notification to approve or adjust."
        case .suggestOnly:
            return "Best for: People who prefer to manually schedule. Suggestions appear in the app for you to action."
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AutopilotSettingsView()
            .environmentObject(UserPreferences.shared)
            .environmentObject(CalendarManager.shared)
    }
}
