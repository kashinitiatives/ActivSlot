import SwiftUI

// MARK: - Add Activity Sheet

struct AddActivitySheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var activityStore: ActivityStore

    let initialDate: Date

    @State private var title = ""
    @State private var activityType: ActivityType = .walk
    @State private var workoutType: WorkoutType = .fullBody
    @State private var startTime: Date
    @State private var duration: Int = 30
    @State private var notes = ""
    @State private var repeatOption: RepeatOption = .never
    @State private var alertOption: AlertOption = .fifteenMinutes

    @State private var showSyncConfirmation = false
    @State private var syncOption: SyncOption = .today

    init(initialDate: Date) {
        self.initialDate = initialDate
        // Default to next hour
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: initialDate)
        components.hour = (components.hour ?? 9) + 1
        components.minute = 0
        _startTime = State(initialValue: calendar.date(from: components) ?? initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Activity Type
                Section {
                    Picker("Activity Type", selection: $activityType) {
                        ForEach(ActivityType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }

                    if activityType == .workout {
                        Picker("Workout Type", selection: $workoutType) {
                            ForEach(WorkoutType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }

                    TextField("Title", text: $title)
                        .onChange(of: activityType) { _, newType in
                            if title.isEmpty || isDefaultTitle(title) {
                                title = defaultTitle(for: newType)
                            }
                        }
                } header: {
                    Text("Activity")
                }

                // Time & Duration
                Section {
                    DatePicker("Start Time", selection: $startTime)

                    Picker("Duration", selection: $duration) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("1 hour").tag(60)
                        Text("1.5 hours").tag(90)
                        Text("2 hours").tag(120)
                    }
                } header: {
                    Text("Time")
                }

                // Repeat
                Section {
                    Picker("Repeat", selection: $repeatOption) {
                        ForEach(RepeatOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Picker("Alert", selection: $alertOption) {
                        ForEach(AlertOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } header: {
                    Text("Repeat & Alerts")
                }

                // Notes
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        showSyncConfirmation = true
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty)
                }
            }
            .sheet(isPresented: $showSyncConfirmation) {
                SyncConfirmationSheet(
                    activity: createActivity(),
                    syncOption: $syncOption,
                    onConfirm: { syncToCalendars in
                        saveActivity(syncToCalendars: syncToCalendars)
                    }
                )
            }
            .onAppear {
                title = defaultTitle(for: activityType)
                duration = activityType.defaultDuration
            }
        }
    }

    private func defaultTitle(for type: ActivityType) -> String {
        switch type {
        case .walk: return "Walk Break"
        case .workout: return "\(workoutType.rawValue) Workout"
        case .stretching: return "Stretching Session"
        case .meditation: return "Meditation"
        case .custom: return ""
        }
    }

    private func isDefaultTitle(_ title: String) -> Bool {
        ActivityType.allCases.contains { defaultTitle(for: $0) == title }
        || WorkoutType.allCases.contains { "\($0.rawValue) Workout" == title }
    }

    private func createActivity() -> PlannedActivity {
        PlannedActivity(
            title: title,
            activityType: activityType,
            workoutType: activityType == .workout ? workoutType : nil,
            startTime: startTime,
            duration: duration,
            notes: notes,
            repeatOption: repeatOption,
            alertOption: alertOption
        )
    }

    private func saveActivity(syncToCalendars: [String]) {
        var activity = createActivity()
        activity.syncedCalendars = syncToCalendars
        activityStore.addActivity(activity)

        // If repeat is set, create future occurrences
        if repeatOption != .never {
            createRepeatingActivities(baseActivity: activity)
        }

        // Sync to external calendars if requested
        if !syncToCalendars.isEmpty {
            Task {
                await CalendarSyncService.shared.syncActivity(activity, toCalendars: syncToCalendars)
            }
        }

        dismiss()
    }

    private func createRepeatingActivities(baseActivity: PlannedActivity) {
        let calendar = Calendar.current
        var futureDate = baseActivity.startTime

        // Create up to 12 occurrences
        for _ in 0..<12 {
            switch repeatOption {
            case .daily:
                futureDate = calendar.date(byAdding: .day, value: 1, to: futureDate) ?? futureDate
            case .weekdays:
                repeat {
                    futureDate = calendar.date(byAdding: .day, value: 1, to: futureDate) ?? futureDate
                } while calendar.isDateInWeekend(futureDate)
            case .weekly:
                futureDate = calendar.date(byAdding: .weekOfYear, value: 1, to: futureDate) ?? futureDate
            case .biweekly:
                futureDate = calendar.date(byAdding: .weekOfYear, value: 2, to: futureDate) ?? futureDate
            case .monthly:
                futureDate = calendar.date(byAdding: .month, value: 1, to: futureDate) ?? futureDate
            case .never:
                return
            }

            var futureActivity = baseActivity
            futureActivity.id = UUID()
            futureActivity.startTime = futureDate
            futureActivity.endTime = calendar.date(byAdding: .minute, value: baseActivity.duration, to: futureDate) ?? futureDate
            activityStore.addActivity(futureActivity)
        }
    }
}

// MARK: - Sync Confirmation Sheet

enum SyncOption: String, CaseIterable {
    case today = "Today Only"
    case thisWeekday = "Every Same Day"
    case alternating = "Alternating Days"
    case allFuture = "All Future Events"
}

struct SyncConfirmationSheet: View {
    @Environment(\.dismiss) var dismiss
    let activity: PlannedActivity
    @Binding var syncOption: SyncOption

    @StateObject private var calendarManager = CalendarManager.shared
    @State private var selectedCalendars: Set<String> = []
    @State private var showCalendarPicker = false

    let onConfirm: ([String]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Activity Preview
                ActivityPreviewCard(activity: activity)
                    .padding()

                Divider()

                Form {
                    // Sync to calendars section
                    Section {
                        Toggle("Sync to External Calendars", isOn: .init(
                            get: { !selectedCalendars.isEmpty },
                            set: { enabled in
                                if enabled {
                                    showCalendarPicker = true
                                } else {
                                    selectedCalendars = []
                                }
                            }
                        ))

                        if !selectedCalendars.isEmpty {
                            Button {
                                showCalendarPicker = true
                            } label: {
                                HStack {
                                    Text("Selected Calendars")
                                    Spacer()
                                    Text("\(selectedCalendars.count)")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    } header: {
                        Text("Calendar Sync")
                    } footer: {
                        Text("Add this activity to your work or personal calendars so it shows up alongside your other events.")
                    }

                    // Sync scope (only show if syncing)
                    if !selectedCalendars.isEmpty && activity.repeatOption != .never {
                        Section {
                            Picker("Sync Scope", selection: $syncOption) {
                                ForEach(SyncOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } header: {
                            Text("Sync Future Events")
                        } footer: {
                            Text(syncOptionDescription)
                        }
                    }
                }
            }
            .navigationTitle("Confirm Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") {
                        onConfirm(Array(selectedCalendars))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                CalendarPickerSheet(
                    selectedCalendars: $selectedCalendars,
                    availableCalendars: calendarManager.availableCalendars
                )
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var syncOptionDescription: String {
        switch syncOption {
        case .today:
            return "Only sync today's event to your calendars."
        case .thisWeekday:
            let weekday = Calendar.current.component(.weekday, from: activity.startTime)
            let weekdayName = DateFormatter().weekdaySymbols[weekday - 1]
            return "Sync all \(weekdayName) events to your calendars."
        case .alternating:
            return "Sync events on alternating days (e.g., Mon, Wed, Fri)."
        case .allFuture:
            return "Sync all future recurring events to your calendars."
        }
    }
}

// MARK: - Activity Preview Card

struct ActivityPreviewCard: View {
    let activity: PlannedActivity

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: activity.icon)
                .font(.title2)
                .foregroundColor(activity.color)
                .frame(width: 50, height: 50)
                .background(activity.color.opacity(0.15))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.headline)

                Text(activity.dateFormatted)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(activity.timeRangeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if activity.repeatOption != .never {
                Label(activity.repeatOption.rawValue, systemImage: "repeat")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Calendar Picker Sheet

struct CalendarPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCalendars: Set<String>
    let availableCalendars: [CalendarInfo]

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedCalendars.keys.sorted(), id: \.self) { source in
                    Section {
                        ForEach(groupedCalendars[source] ?? []) { calendar in
                            SyncCalendarRow(
                                calendar: calendar,
                                isSelected: selectedCalendars.contains(calendar.id),
                                onToggle: {
                                    if selectedCalendars.contains(calendar.id) {
                                        selectedCalendars.remove(calendar.id)
                                    } else {
                                        selectedCalendars.insert(calendar.id)
                                    }
                                }
                            )
                        }
                    } header: {
                        Text(source)
                    }
                }
            }
            .navigationTitle("Select Calendars")
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

    private var groupedCalendars: [String: [CalendarInfo]] {
        Dictionary(grouping: availableCalendars) { $0.source }
    }
}

struct SyncCalendarRow: View {
    let calendar: CalendarInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(calendar.color)
                    .frame(width: 12, height: 12)

                Text(calendar.title)
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Activity Detail Sheet

struct ActivityDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var activityStore: ActivityStore

    let activity: PlannedActivity

    @State private var isEditing = false
    @State private var editedActivity: PlannedActivity
    @State private var showDeleteConfirmation = false

    init(activity: PlannedActivity) {
        self.activity = activity
        _editedActivity = State(initialValue: activity)
    }

    var body: some View {
        NavigationStack {
            if isEditing {
                editView
            } else {
                detailView
            }
        }
    }

    private var detailView: some View {
        List {
            // Activity Info
            Section {
                HStack {
                    Label(activity.activityType.rawValue, systemImage: activity.icon)
                        .foregroundColor(activity.color)
                    Spacer()
                    if activity.isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                if let workoutType = activity.workoutType {
                    LabeledContent("Workout Type", value: workoutType.rawValue)
                }
            }

            // Time
            Section {
                LabeledContent("Date", value: activity.dateFormatted)
                LabeledContent("Time", value: activity.timeRangeFormatted)
                LabeledContent("Duration", value: "\(activity.duration) minutes")
            }

            // Repeat & Alert
            Section {
                LabeledContent("Repeat", value: activity.repeatOption.rawValue)
                LabeledContent("Alert", value: activity.alertOption.rawValue)
            }

            // Notes
            if !activity.notes.isEmpty {
                Section("Notes") {
                    Text(activity.notes)
                        .foregroundColor(.secondary)
                }
            }

            // Sync Status
            Section {
                HStack {
                    Text("Sync Status")
                    Spacer()
                    Label(activity.syncStatus.rawValue, systemImage: syncStatusIcon)
                        .foregroundColor(syncStatusColor)
                        .font(.caption)
                }

                if !activity.syncedCalendars.isEmpty {
                    LabeledContent("Synced to", value: "\(activity.syncedCalendars.count) calendar(s)")
                }
            }

            // Actions
            Section {
                if !activity.isCompleted {
                    Button {
                        markCompleted()
                    } label: {
                        Label("Mark as Completed", systemImage: "checkmark.circle")
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Activity", systemImage: "trash")
                }
            }
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .confirmationDialog("Delete Activity", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteActivity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this activity?")
        }
    }

    private var editView: some View {
        Form {
            Section {
                TextField("Title", text: $editedActivity.title)

                Picker("Activity Type", selection: $editedActivity.activityType) {
                    ForEach(ActivityType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }

                if editedActivity.activityType == .workout {
                    Picker("Workout Type", selection: Binding(
                        get: { editedActivity.workoutType ?? .fullBody },
                        set: { editedActivity.workoutType = $0 }
                    )) {
                        ForEach(WorkoutType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
            }

            Section {
                DatePicker("Start Time", selection: $editedActivity.startTime)

                Picker("Duration", selection: Binding(
                    get: { editedActivity.duration },
                    set: { newDuration in
                        editedActivity.endTime = Calendar.current.date(
                            byAdding: .minute,
                            value: newDuration,
                            to: editedActivity.startTime
                        ) ?? editedActivity.startTime
                    }
                )) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                    Text("2 hours").tag(120)
                }
            }

            Section {
                Picker("Repeat", selection: $editedActivity.repeatOption) {
                    ForEach(RepeatOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }

                Picker("Alert", selection: $editedActivity.alertOption) {
                    ForEach(AlertOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            Section {
                TextField("Notes", text: $editedActivity.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Edit Activity")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    editedActivity = activity
                    isEditing = false
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveChanges()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var syncStatusIcon: String {
        switch activity.syncStatus {
        case .notSynced: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch activity.syncStatus {
        case .notSynced: return .secondary
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }

    private func markCompleted() {
        var updated = activity
        updated.markCompleted()
        activityStore.updateActivity(updated)
        dismiss()
    }

    private func saveChanges() {
        activityStore.updateActivity(editedActivity)
        isEditing = false

        // Re-sync if needed
        if editedActivity.syncStatus == .synced && !editedActivity.syncedCalendars.isEmpty {
            Task {
                await CalendarSyncService.shared.updateSyncedActivity(editedActivity)
            }
        }
    }

    private func deleteActivity() {
        // Delete from external calendars first
        if !activity.syncedCalendars.isEmpty {
            Task {
                await CalendarSyncService.shared.deleteFromExternalCalendars(activity)
            }
        }
        activityStore.deleteActivity(activity)
        dismiss()
    }
}
