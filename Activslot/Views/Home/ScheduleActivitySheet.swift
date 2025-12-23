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

    @State private var activityToEdit: ScheduledActivity?
    @State private var activityToDelete: ScheduledActivity?
    @State private var showDeleteConfirmation = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    // Get upcoming 7 days of activities
    private var upcomingActivities: [(date: Date, activities: [ScheduledActivity])] {
        let calendar = Calendar.current
        var result: [(date: Date, activities: [ScheduledActivity])] = []

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) else { continue }

            let activitiesForDay = scheduledActivityManager.activities(for: date)
                .sorted { a, b in
                    if let aRange = a.getTimeRange(for: date), let bRange = b.getTimeRange(for: date) {
                        return aRange.start < bRange.start
                    }
                    return false
                }

            if !activitiesForDay.isEmpty {
                result.append((date: date, activities: activitiesForDay))
            }
        }

        return result
    }

    // Get recurring activities
    private var recurringActivities: [ScheduledActivity] {
        scheduledActivityManager.scheduledActivities
            .filter { $0.recurrence != .once && $0.isActive }
            .sorted { $0.title < $1.title }
    }

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
                    // Upcoming activities by date
                    ForEach(upcomingActivities, id: \.date) { dayData in
                        Section {
                            ForEach(dayData.activities) { activity in
                                ScheduledActivityListRow(
                                    activity: activity,
                                    date: dayData.date,
                                    onEdit: { activityToEdit = activity },
                                    onDelete: {
                                        activityToDelete = activity
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                if Calendar.current.isDateInToday(dayData.date) {
                                    Text("Today")
                                        .fontWeight(.semibold)
                                } else if Calendar.current.isDateInTomorrow(dayData.date) {
                                    Text("Tomorrow")
                                        .fontWeight(.semibold)
                                } else {
                                    Text(dateFormatter.string(from: dayData.date))
                                }
                            }
                        }
                    }

                    // Recurring activities section
                    if !recurringActivities.isEmpty {
                        Section {
                            ForEach(recurringActivities) { activity in
                                RecurringActivityRow(
                                    activity: activity,
                                    onEdit: { activityToEdit = activity },
                                    onDelete: {
                                        activityToDelete = activity
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        } header: {
                            Label("Recurring", systemImage: "repeat")
                        }
                    }
                }
            }
            .navigationTitle("Your Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $activityToEdit) { activity in
                EditScheduledActivitySheet(activity: activity)
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
                        Text("This will remove \"\(activity.title)\".")
                    } else {
                        Text("This will remove all occurrences of \"\(activity.title)\".")
                    }
                }
            }
        }
    }
}

// MARK: - Scheduled Activity List Row (with date context)

struct ScheduledActivityListRow: View {
    let activity: ScheduledActivity
    let date: Date
    var onEdit: () -> Void
    var onDelete: () -> Void

    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    private var isCompleted: Bool {
        scheduledActivityManager.isCompleted(activity: activity, for: date)
    }

    private var timeRange: String {
        if let range = activity.getTimeRange(for: date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
        }
        return activity.timeRangeFormatted
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion checkbox
            Button {
                withAnimation(.spring(response: 0.3)) {
                    scheduledActivityManager.toggleCompletion(activity: activity, for: date)
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Activity icon
            Image(systemName: activity.icon)
                .font(.title3)
                .foregroundColor(isCompleted ? .secondary : activity.color)
                .frame(width: 36, height: 36)
                .background((isCompleted ? Color.secondary : activity.color).opacity(0.1))
                .cornerRadius(8)

            // Activity details
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isCompleted)
                    .foregroundColor(isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(timeRange)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text("\(activity.duration) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions menu
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
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
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

// MARK: - Recurring Activity Row

struct RecurringActivityRow: View {
    let activity: ScheduledActivity
    var onEdit: () -> Void
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

                    Label(activity.recurrence.rawValue, systemImage: "repeat")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
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

// MARK: - Edit Scheduled Activity Sheet

struct EditScheduledActivitySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    let activity: ScheduledActivity

    @State private var selectedTime: Date
    @State private var selectedDuration: Int
    @State private var selectedRecurrence: RecurrenceRule
    @State private var customTitle: String
    @State private var selectedScope: ScheduledActivityManager.UpdateScope = .thisOccurrence
    @State private var showDeleteConfirmation = false

    init(activity: ScheduledActivity) {
        self.activity = activity

        // Set initial values from activity
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = activity.startHour
        components.minute = activity.startMinute
        let initialTime = calendar.date(from: components) ?? Date()

        self._selectedTime = State(initialValue: initialTime)
        self._selectedDuration = State(initialValue: activity.duration)
        self._selectedRecurrence = State(initialValue: activity.recurrence)
        self._customTitle = State(initialValue: activity.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Activity Info Section
                Section {
                    HStack {
                        Image(systemName: activity.icon)
                            .font(.title2)
                            .foregroundColor(activity.color)
                            .frame(width: 44, height: 44)
                            .background(activity.color.opacity(0.1))
                            .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.activityType.rawValue)
                                .font(.headline)

                            if let workoutType = activity.workoutType {
                                Text(workoutType.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Title", text: $customTitle)
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

                // Delete Section
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Activity", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Activity?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    scheduledActivityManager.deleteScheduledActivity(activity)
                    dismiss()
                }
            } message: {
                if activity.recurrence == .once {
                    Text("This will remove the scheduled \(activity.title).")
                } else {
                    Text("This will remove all occurrences of \(activity.title).")
                }
            }
        }
    }

    private func saveChanges() {
        // Update the activity with new values
        scheduledActivityManager.updateScheduledActivity(
            activity,
            newTime: selectedTime,
            newDuration: selectedDuration,
            newTitle: customTitle,
            newRecurrence: selectedRecurrence,
            scope: selectedScope
        )
        dismiss()
    }
}

// MARK: - Quick Workout Sheet (One-Tap Scheduling for Executives)

struct QuickWorkoutSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared
    @ObservedObject var preferences = UserPreferences.shared

    let targetDate: Date
    var onScheduled: (() -> Void)?

    @State private var selectedTimeSlot: QuickTimeSlot = .morning
    @State private var selectedDuration: Int = 45
    @State private var showSuccess = false

    enum QuickTimeSlot: String, CaseIterable {
        case morning = "Morning"
        case lunch = "Lunch"
        case evening = "Evening"

        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .lunch: return "sun.max.fill"
            case .evening: return "sunset.fill"
            }
        }

        var color: Color {
            switch self {
            case .morning: return .orange
            case .lunch: return .yellow
            case .evening: return .purple
            }
        }

        var defaultHour: Int {
            switch self {
            case .morning: return 6
            case .lunch: return 12
            case .evening: return 18
            }
        }

        var defaultMinute: Int {
            switch self {
            case .morning: return 30
            case .lunch: return 0
            case .evening: return 0
            }
        }

        var timeDescription: String {
            switch self {
            case .morning: return "6:30 AM"
            case .lunch: return "12:00 PM"
            case .evening: return "6:00 PM"
            }
        }

        var subtitle: String {
            switch self {
            case .morning: return "Start your day strong"
            case .lunch: return "Midday energy boost"
            case .evening: return "End day with movement"
            }
        }
    }

    private var startTime: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = selectedTimeSlot.defaultHour
        components.minute = selectedTimeSlot.defaultMinute
        return calendar.date(from: components) ?? targetDate
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with date
                VStack(spacing: 4) {
                    Text("Schedule Workout")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(dateFormatter.string(from: targetDate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)

                // Time Slot Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("When")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        ForEach(QuickTimeSlot.allCases, id: \.self) { slot in
                            QuickTimeSlotButton(
                                slot: slot,
                                isSelected: selectedTimeSlot == slot,
                                onTap: { selectedTimeSlot = slot }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)

                // Duration Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        ForEach([30, 45, 60, 90], id: \.self) { duration in
                            QuickDurationButton(
                                duration: duration,
                                isSelected: selectedDuration == duration,
                                isRecommended: duration == preferences.workoutDuration.rawValue,
                                onTap: { selectedDuration = duration }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)

                // Summary Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(width: 44, height: 44)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout")
                                .font(.headline)
                            Text("\(selectedTimeSlot.timeDescription) • \(selectedDuration) min")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: selectedTimeSlot.icon)
                            .font(.title2)
                            .foregroundColor(selectedTimeSlot.color)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer()

                // Schedule Button
                Button {
                    scheduleWorkout()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Schedule Workout")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Make Recurring Option
                Button {
                    scheduleWorkout(recurring: true)
                } label: {
                    HStack {
                        Image(systemName: "repeat")
                        Text("Make it Weekly")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showSuccess {
                    SuccessOverlay(message: "Workout Scheduled!")
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    private func scheduleWorkout(recurring: Bool = false) {
        let activity = ScheduledActivity(
            activityType: .workout,
            workoutType: nil,
            title: "Workout",
            startTime: startTime,
            duration: selectedDuration,
            recurrence: recurring ? .weekly : .once
        )

        scheduledActivityManager.addScheduledActivity(activity)

        // Show success feedback
        withAnimation(.spring(response: 0.3)) {
            showSuccess = true
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Dismiss after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onScheduled?()
            dismiss()
        }
    }
}

// MARK: - Quick Time Slot Button

struct QuickTimeSlotButton: View {
    let slot: QuickWorkoutSheet.QuickTimeSlot
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: slot.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : slot.color)

                Text(slot.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(slot.timeDescription)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? slot.color : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Duration Button

struct QuickDurationButton: View {
    let duration: Int
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(duration)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)

                Text("min")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                if isRecommended && !isSelected {
                    Text("Rec")
                        .font(.system(size: 9))
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Walk Sheet (One-Tap Scheduling for Walks)

struct QuickWalkSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scheduledActivityManager = ScheduledActivityManager.shared

    let targetDate: Date
    let suggestedTime: Date?
    let suggestedDuration: Int
    var onScheduled: (() -> Void)?

    @State private var selectedDuration: Int
    @State private var showSuccess = false

    init(targetDate: Date, suggestedTime: Date? = nil, suggestedDuration: Int = 20, onScheduled: (() -> Void)? = nil) {
        self.targetDate = targetDate
        self.suggestedTime = suggestedTime
        self.suggestedDuration = suggestedDuration
        self.onScheduled = onScheduled
        self._selectedDuration = State(initialValue: suggestedDuration)
    }

    private var startTime: Date {
        suggestedTime ?? targetDate
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Walk Icon
                Image(systemName: "figure.walk")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                    .frame(width: 80, height: 80)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
                    .padding(.top, 20)

                // Time Display
                VStack(spacing: 4) {
                    Text("Walk Break")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(timeFormatter.string(from: startTime))
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }

                // Duration Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        ForEach([15, 20, 30, 45], id: \.self) { duration in
                            Button {
                                selectedDuration = duration
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(duration)")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Text("min")
                                        .font(.caption2)
                                }
                                .foregroundColor(selectedDuration == duration ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedDuration == duration ? Color.green : Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                // Estimated Steps
                HStack {
                    Image(systemName: "shoeprints.fill")
                        .foregroundColor(.green)
                    Text("~\(selectedDuration * 100) steps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Schedule Button
                Button {
                    scheduleWalk()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Schedule Walk")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showSuccess {
                    SuccessOverlay(message: "Walk Scheduled!", color: .green)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    private func scheduleWalk() {
        let activity = ScheduledActivity(
            activityType: .walk,
            workoutType: nil,
            title: "Walk Break",
            startTime: startTime,
            duration: selectedDuration,
            recurrence: .once
        )

        scheduledActivityManager.addScheduledActivity(activity)

        withAnimation(.spring(response: 0.3)) {
            showSuccess = true
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onScheduled?()
            dismiss()
        }
    }
}

// MARK: - Success Overlay

struct SuccessOverlay: View {
    let message: String
    var color: Color = .orange

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(color)

            Text(message)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
}

#Preview {
    ScheduleActivitySheet(
        activityType: .walk,
        suggestedTime: Date(),
        suggestedDuration: 30
    )
}

#Preview("Quick Workout") {
    QuickWorkoutSheet(targetDate: Date())
}

#Preview("Quick Walk") {
    QuickWalkSheet(targetDate: Date(), suggestedTime: Date(), suggestedDuration: 20)
}
