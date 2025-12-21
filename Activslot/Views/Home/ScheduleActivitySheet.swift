import SwiftUI

// MARK: - Schedule Activity Sheet

struct ScheduleActivitySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    let activityType: ActivityType
    let suggestedTime: Date
    let suggestedDuration: Int
    let workoutType: WorkoutType?
    var onScheduled: (() -> Void)?

    @State private var selectedTime: Date
    @State private var selectedDuration: Int
    @State private var selectedRecurrence: RecurrenceRule = .once
    @State private var syncToCalendar: Bool = true
    @State private var customTitle: String = ""

    init(
        activityType: ActivityType,
        suggestedTime: Date,
        suggestedDuration: Int,
        workoutType: WorkoutType? = nil,
        onScheduled: (() -> Void)? = nil
    ) {
        self.activityType = activityType
        self.suggestedTime = suggestedTime
        self.suggestedDuration = suggestedDuration
        self.workoutType = workoutType
        self.onScheduled = onScheduled
        self._selectedTime = State(initialValue: suggestedTime)
        self._selectedDuration = State(initialValue: suggestedDuration)
    }

    private var defaultTitle: String {
        if let workoutType = workoutType {
            return "\(workoutType.rawValue) Workout"
        }
        return activityType == .walk ? "Walk Break" : activityType.rawValue
    }

    private var activityTitle: String {
        customTitle.isEmpty ? defaultTitle : customTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                // Activity Info Section
                Section {
                    HStack {
                        Image(systemName: workoutType?.icon ?? activityType.icon)
                            .font(.title2)
                            .foregroundColor(activityType == .workout ? .orange : activityType.color)
                            .frame(width: 44, height: 44)
                            .background((activityType == .workout ? Color.orange : activityType.color).opacity(0.1))
                            .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activityTitle)
                                .font(.headline)

                            if let workoutType = workoutType {
                                Text(workoutType.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Custom title (optional)", text: $customTitle)
                }

                // Time Selection
                Section {
                    DatePicker(
                        "Start Time",
                        selection: $selectedTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("Duration", selection: $selectedDuration) {
                        ForEach([15, 20, 30, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                } header: {
                    Text("Time")
                }

                // Recurrence Options
                Section {
                    ForEach(RecurrenceRule.allCases, id: \.self) { rule in
                        Button {
                            selectedRecurrence = rule
                        } label: {
                            HStack {
                                Image(systemName: rule.icon)
                                    .foregroundColor(.blue)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.rawValue)
                                        .foregroundColor(.primary)
                                    Text(rule.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedRecurrence == rule {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Repeat")
                } footer: {
                    if selectedRecurrence != .once {
                        Text("This will create a recurring schedule for your \(activityType.rawValue.lowercased()).")
                    }
                }

                // Sync Options
                Section {
                    Toggle("Add to Calendar", isOn: $syncToCalendar)
                } footer: {
                    Text("Syncs this activity to your selected calendars")
                }

                // Preview
                Section {
                    SchedulePreviewCard(
                        title: activityTitle,
                        time: selectedTime,
                        duration: selectedDuration,
                        recurrence: selectedRecurrence,
                        activityType: activityType,
                        workoutType: workoutType
                    )
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Schedule \(activityType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schedule") {
                        scheduleActivity()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func scheduleActivity() {
        let activity = ScheduledActivity(
            activityType: activityType,
            workoutType: workoutType,
            title: activityTitle,
            startTime: selectedTime,
            duration: selectedDuration,
            recurrence: selectedRecurrence
        )

        scheduledActivityManager.addScheduledActivity(activity)

        // TODO: Sync to external calendar if enabled

        onScheduled?()
        dismiss()
    }
}

// MARK: - Schedule Preview Card

struct SchedulePreviewCard: View {
    let title: String
    let time: Date
    let duration: Int
    let recurrence: RecurrenceRule
    let activityType: ActivityType
    let workoutType: WorkoutType?

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }

    private var endTime: Date {
        Calendar.current.date(byAdding: .minute, value: duration, to: time) ?? time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: workoutType?.icon ?? activityType.icon)
                    .foregroundColor(activityType == .workout ? .orange : activityType.color)

                Text(title)
                    .fontWeight(.medium)

                Spacer()

                Text("\(duration) min")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Divider()

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("\(timeFormatter.string(from: time)) - \(timeFormatter.string(from: endTime))")
            }
            .font(.subheadline)

            if recurrence == .once {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(dateFormatter.string(from: time))
                }
                .font(.subheadline)
            } else {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundColor(.blue)
                    Text(recurrence.rawValue)
                        .foregroundColor(.blue)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Reschedule Activity Sheet

struct RescheduleActivitySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    let activity: ScheduledActivity
    let conflictDescription: String?
    var onRescheduled: (() -> Void)?

    @State private var selectedTime: Date
    @State private var selectedScope: ScheduledActivityManager.UpdateScope = .thisOccurrence

    init(
        activity: ScheduledActivity,
        conflictDescription: String? = nil,
        onRescheduled: (() -> Void)? = nil
    ) {
        self.activity = activity
        self.conflictDescription = conflictDescription
        self.onRescheduled = onRescheduled

        // Set initial time to activity's time today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = activity.startHour
        components.minute = activity.startMinute
        let initialTime = calendar.date(from: components) ?? Date()
        self._selectedTime = State(initialValue: initialTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Conflict Alert (if any)
                if let conflict = conflictDescription {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(conflict)
                                .font(.subheadline)
                        }
                    }
                }

                // Current Schedule Info
                Section {
                    HStack {
                        Image(systemName: activity.icon)
                            .foregroundColor(activity.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .fontWeight(.medium)
                            Text("Currently: \(activity.timeRangeFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Activity")
                }

                // New Time Selection
                Section {
                    DatePicker(
                        "New Time",
                        selection: $selectedTime,
                        displayedComponents: [.hourAndMinute]
                    )
                } header: {
                    Text("Reschedule To")
                }

                // Scope Selection (for recurring activities)
                if activity.recurrence != .once {
                    Section {
                        Picker("Apply Changes", selection: $selectedScope) {
                            Text("Just Today").tag(ScheduledActivityManager.UpdateScope.thisOccurrence)
                            Text("This & Future").tag(ScheduledActivityManager.UpdateScope.thisAndFuture)
                            Text("All Occurrences").tag(ScheduledActivityManager.UpdateScope.allOccurrences)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Update Scope")
                    } footer: {
                        switch selectedScope {
                        case .thisOccurrence:
                            Text("Only changes today's schedule")
                        case .thisAndFuture:
                            Text("Changes this and all future occurrences")
                        case .allOccurrences:
                            Text("Changes all occurrences including past")
                        }
                    }
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Update") {
                        rescheduleActivity()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func rescheduleActivity() {
        scheduledActivityManager.updateScheduledActivity(
            activity,
            newTime: selectedTime,
            scope: selectedScope
        )
        onRescheduled?()
        dismiss()
    }
}

// MARK: - Scheduled Activities List Sheet

struct ScheduledActivitiesListSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    @State private var activityToReschedule: ScheduledActivity?
    @State private var activityToDelete: ScheduledActivity?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if scheduledActivityManager.scheduledActivities.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("No Scheduled Activities")
                                .font(.headline)

                            Text("Schedule a walk or workout from your daily plan to see them here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                } else {
                    // Walks Section
                    let walks = scheduledActivityManager.scheduledActivities.filter { $0.activityType == .walk }
                    if !walks.isEmpty {
                        Section {
                            ForEach(walks) { activity in
                                ScheduledActivityRow(
                                    activity: activity,
                                    onReschedule: { activityToReschedule = activity },
                                    onDelete: {
                                        activityToDelete = activity
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        } header: {
                            Label("Walks", systemImage: "figure.walk")
                        }
                    }

                    // Workouts Section
                    let workouts = scheduledActivityManager.scheduledActivities.filter { $0.activityType == .workout }
                    if !workouts.isEmpty {
                        Section {
                            ForEach(workouts) { activity in
                                ScheduledActivityRow(
                                    activity: activity,
                                    onReschedule: { activityToReschedule = activity },
                                    onDelete: {
                                        activityToDelete = activity
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        } header: {
                            Label("Workouts", systemImage: "dumbbell.fill")
                        }
                    }
                }
            }
            .navigationTitle("Scheduled Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $activityToReschedule) { activity in
                RescheduleActivitySheet(activity: activity)
            }
            .alert("Delete Activity?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let activity = activityToDelete {
                        scheduledActivityManager.deleteScheduledActivity(activity)
                    }
                }
            } message: {
                if let activity = activityToDelete {
                    if activity.recurrence == .once {
                        Text("This will remove the scheduled \(activity.title).")
                    } else {
                        Text("This will remove all occurrences of \(activity.title).")
                    }
                }
            }
        }
    }
}

// MARK: - Scheduled Activity Row

struct ScheduledActivityRow: View {
    let activity: ScheduledActivity
    var onReschedule: () -> Void
    var onDelete: () -> Void

    var body: some View {
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

                HStack(spacing: 8) {
                    Text(activity.timeRangeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if activity.recurrence != .once {
                        Text("•")
                            .foregroundColor(.secondary)
                        Label(activity.recurrence.rawValue, systemImage: "repeat")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            Menu {
                Button {
                    onReschedule()
                } label: {
                    Label("Reschedule", systemImage: "clock.arrow.circlepath")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ScheduleActivitySheet(
        activityType: .walk,
        suggestedTime: Date(),
        suggestedDuration: 30
    )
}
