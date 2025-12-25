import SwiftUI

// MARK: - Main Calendar View

struct ActivslotCalendarView: View {
    @StateObject private var activityStore = ActivityStore.shared
    @StateObject private var scheduledActivityManager = ScheduledActivityManager.shared
    @EnvironmentObject var calendarManager: CalendarManager

    // Trigger to reset to today when calendar tab is tapped
    var resetToTodayTrigger: Int = 0

    @State private var selectedDate = Date()
    @State private var showAddActivity = false
    @State private var selectedActivity: PlannedActivity?
    @State private var showActivityDetail = false
    @State private var externalEvents: [CalendarEvent] = []
    @State private var showSyncSheet = false
    @State private var isSyncing = false
    @State private var syncSuccess = false

    // Convert scheduled activities to planned activities for display
    private var scheduledActivitiesAsPlanedForDate: [PlannedActivity] {
        scheduledActivityManager.activities(for: selectedDate).compactMap { scheduled -> PlannedActivity? in
            guard let timeRange = scheduled.getTimeRange(for: selectedDate) else { return nil }
            var activity = PlannedActivity(
                title: scheduled.activityType == .workout ? "Workout" : scheduled.title,
                activityType: scheduled.activityType,
                startTime: timeRange.start,
                duration: scheduled.duration
            )
            // Set completion status based on scheduled activity manager
            if scheduledActivityManager.isCompleted(activity: scheduled, for: selectedDate) {
                activity.isCompleted = true
            }
            return activity
        }
    }

    // Combined activities
    private var allActivitiesForDate: [PlannedActivity] {
        let storeActivities = activityStore.activities(for: selectedDate)
        let scheduledActivities = scheduledActivitiesAsPlanedForDate
        // Combine and sort by start time
        return (storeActivities + scheduledActivities).sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sync Header
                CalendarSyncBar(
                    isSyncing: isSyncing,
                    syncSuccess: syncSuccess,
                    hasActivities: !allActivitiesForDate.isEmpty,
                    onSyncTap: { showSyncSheet = true }
                )

                // Day Calendar View (only view mode)
                DayCalendarView(
                    selectedDate: $selectedDate,
                    activities: allActivitiesForDate,
                    externalEvents: externalEvents,
                    onActivityTap: { activity in
                        selectedActivity = activity
                        showActivityDetail = true
                    },
                    onAddTap: { time in
                        selectedDate = time
                        showAddActivity = true
                    },
                    onActivityTimeChanged: { activity, newTime in
                        updateActivityTime(activity, to: newTime)
                    },
                    onActivityDurationChanged: { activity, newDuration in
                        updateActivityDuration(activity, to: newDuration)
                    }
                )
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedDate = Date()
                    } label: {
                        Text("Today")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Quick add Walk (1 hour)
                        Button {
                            quickAddActivity(type: .walk)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.walk")
                                Text("+")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        }

                        // Quick add Workout (1 hour)
                        Button {
                            quickAddActivity(type: .workout)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                Text("+")
                                    .font(.caption2)
                            }
                            .foregroundColor(.orange)
                        }

                        // Full add sheet
                        Button {
                            showAddActivity = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddActivity) {
                AddActivitySheet(initialDate: selectedDate)
                    .environmentObject(activityStore)
            }
            .sheet(isPresented: $showActivityDetail) {
                if let activity = selectedActivity {
                    ActivityDetailSheet(activity: activity, startInEditMode: true)
                        .environmentObject(activityStore)
                }
            }
            .sheet(isPresented: $showSyncSheet) {
                CalendarSyncToExternalSheet(
                    activities: allActivitiesForDate,
                    selectedDate: selectedDate,
                    onSync: { calendarIDs in
                        Task {
                            await syncToExternalCalendars(calendarIDs)
                        }
                    }
                )
            }
            .task {
                await loadExternalEvents()
            }
            .onAppear {
                // Refresh calendar data when view appears (e.g., switching tabs)
                Task {
                    await calendarManager.refreshEvents()
                    await loadExternalEvents()
                }
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await loadExternalEvents()
                }
            }
            .onChange(of: resetToTodayTrigger) { _, _ in
                // Reset to today when calendar tab is tapped
                selectedDate = Date()
            }
        }
    }

    private func syncToExternalCalendars(_ calendarIDs: [String]) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Convert planned activities to step slots and workout slots for sync
            var stepSlots: [StepSlot] = []
            var workoutSlot: WorkoutSlot? = nil

            for activity in allActivitiesForDate {
                if activity.activityType == .walk {
                    stepSlots.append(StepSlot(
                        startTime: activity.startTime,
                        endTime: Calendar.current.date(byAdding: .minute, value: activity.duration, to: activity.startTime) ?? activity.startTime,
                        slotType: .freeTime,
                        targetSteps: activity.duration * 100,
                        source: activity.title
                    ))
                } else if activity.activityType == .workout && workoutSlot == nil {
                    workoutSlot = WorkoutSlot(
                        startTime: activity.startTime,
                        endTime: Calendar.current.date(byAdding: .minute, value: activity.duration, to: activity.startTime) ?? activity.startTime,
                        workoutType: .fullBody,
                        isRecommended: true
                    )
                }
            }

            try await CalendarSyncService.shared.syncMovementPlan(
                stepSlots: stepSlots,
                workoutSlot: workoutSlot,
                toCalendars: calendarIDs
            )

            await MainActor.run {
                syncSuccess = true
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                syncSuccess = false
            }
        } catch {
            print("Sync failed: \(error)")
        }
    }

    private func quickAddActivity(type: ActivityType) {
        // Find the next available hour (current hour + 1, rounded up)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: selectedDate)

        // If selected date is today, start from current time
        if calendar.isDateInToday(selectedDate) {
            let currentHour = calendar.component(.hour, from: Date())
            components.hour = min(currentHour + 1, 23)
        } else {
            // Default to 9 AM for future dates
            components.hour = 9
        }
        components.minute = 0

        guard let startTime = calendar.date(from: components) else { return }

        let title = type == .walk ? "Walk" : "Workout"
        let duration = 60 // 1 hour default

        // Create and add the activity directly without opening edit sheet
        let activity = PlannedActivity(
            title: title,
            activityType: type,
            startTime: startTime,
            duration: duration
        )

        activityStore.addActivity(activity)

        // Provide haptic feedback to confirm addition
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func loadExternalEvents() async {
        if let events = try? await calendarManager.fetchEvents(for: selectedDate) {
            await MainActor.run {
                externalEvents = events
            }
        }
    }

    private func updateActivityTime(_ activity: PlannedActivity, to newTime: Date) {
        // Find and update the scheduled activity
        if let scheduledActivity = scheduledActivityManager.activities(for: selectedDate)
            .first(where: { scheduled in
                // Match by activity type and approximate time
                guard scheduled.activityType == activity.activityType,
                      let timeRange = scheduled.getTimeRange(for: selectedDate) else {
                    return false
                }
                return abs(timeRange.start.timeIntervalSince(activity.startTime)) < 60
            }) {
            // Update the activity time
            scheduledActivityManager.updateActivityTime(scheduledActivity, to: newTime)
            // Provide haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // Try to update in activity store
            activityStore.updateActivityTime(activity, to: newTime)
        }
    }

    private func updateActivityDuration(_ activity: PlannedActivity, to newDuration: Int) {
        // Find and update the scheduled activity
        if let scheduledActivity = scheduledActivityManager.activities(for: selectedDate)
            .first(where: { scheduled in
                // Match by activity type and approximate time
                guard scheduled.activityType == activity.activityType,
                      let timeRange = scheduled.getTimeRange(for: selectedDate) else {
                    return false
                }
                return abs(timeRange.start.timeIntervalSince(activity.startTime)) < 60
            }) {
            // Update the activity duration
            scheduledActivityManager.updateActivityDuration(scheduledActivity, to: newDuration)
            // Provide haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // Try to update in activity store
            activityStore.updateActivityDuration(activity, to: newDuration)
        }
    }
}

// MARK: - Day Calendar View

struct DayCalendarView: View {
    @Binding var selectedDate: Date
    let activities: [PlannedActivity]
    let externalEvents: [CalendarEvent]
    let onActivityTap: (PlannedActivity) -> Void
    let onAddTap: (Date) -> Void
    var onActivityTimeChanged: ((PlannedActivity, Date) -> Void)? = nil
    var onActivityDurationChanged: ((PlannedActivity, Int) -> Void)? = nil

    private let hourHeight: CGFloat = 60
    private let hours = Array(0..<24)
    private let timeColumnWidth: CGFloat = 50
    private let eventPadding: CGFloat = 4

    // Filter out Activslot-created events to avoid duplicates
    private var filteredExternalEvents: [CalendarEvent] {
        externalEvents.filter { event in
            let lowercaseTitle = event.title.lowercased()
            // Skip events created by Activslot (they're already shown as activities)
            let isActivslotEvent = lowercaseTitle.contains("walk break") ||
                                   lowercaseTitle.contains("morning walk") ||
                                   lowercaseTitle.contains("afternoon walk") ||
                                   lowercaseTitle.contains("evening walk") ||
                                   lowercaseTitle.contains("workout") ||
                                   lowercaseTitle.contains("activslot") ||
                                   (event.notes?.contains("Activslot") ?? false)
            return !isActivslotEvent
        }
    }

    // Separate all-day events from timed events
    private var allDayEvents: [CalendarEvent] {
        filteredExternalEvents.filter { $0.duration >= 1440 } // 24 hours or more
    }

    private var timedEvents: [CalendarEvent] {
        filteredExternalEvents.filter { $0.duration < 1440 }
    }

    // Calculate horizontal positions for overlapping events
    private var eventLayout: [String: (column: Int, totalColumns: Int)] {
        var layout: [String: (column: Int, totalColumns: Int)] = [:]
        let sortedEvents = timedEvents.sorted { $0.startDate < $1.startDate }

        // Group overlapping events
        var groups: [[CalendarEvent]] = []
        for event in sortedEvents {
            var addedToGroup = false
            for i in groups.indices {
                // Check if this event overlaps with any event in the group
                let overlaps = groups[i].contains { existing in
                    event.startDate < existing.endDate && event.endDate > existing.startDate
                }
                if overlaps {
                    groups[i].append(event)
                    addedToGroup = true
                    break
                }
            }
            if !addedToGroup {
                groups.append([event])
            }
        }

        // Assign columns within each group
        for group in groups {
            let sorted = group.sorted { $0.startDate < $1.startDate }
            var columns: [[CalendarEvent]] = []

            for event in sorted {
                var placed = false
                for colIndex in columns.indices {
                    let canPlace = columns[colIndex].allSatisfy { existing in
                        event.startDate >= existing.endDate || event.endDate <= existing.startDate
                    }
                    if canPlace {
                        columns[colIndex].append(event)
                        layout[event.id] = (column: colIndex, totalColumns: 0)
                        placed = true
                        break
                    }
                }
                if !placed {
                    columns.append([event])
                    layout[event.id] = (column: columns.count - 1, totalColumns: 0)
                }
            }

            // Update total columns for all events in group
            for event in group {
                if var entry = layout[event.id] {
                    entry.totalColumns = columns.count
                    layout[event.id] = entry
                }
            }
        }

        return layout
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date Header with navigation
            DateNavigationHeader(selectedDate: $selectedDate)

            // All-day events bar (if any)
            if !allDayEvents.isEmpty {
                AllDayEventsBar(events: allDayEvents)
            }

            ScrollView {
                ScrollViewReader { proxy in
                    ZStack(alignment: .topLeading) {
                        // Hour grid
                        VStack(spacing: 0) {
                            ForEach(hours, id: \.self) { hour in
                                HourRow(hour: hour, hourHeight: hourHeight)
                                    .id(hour)
                            }
                        }

                        // External events (work calendar) - with layout to prevent overlap
                        ForEach(timedEvents) { event in
                            if let layoutInfo = eventLayout[event.id] {
                                ExternalEventBlock(
                                    event: event,
                                    hourHeight: hourHeight,
                                    column: layoutInfo.column,
                                    totalColumns: layoutInfo.totalColumns,
                                    timeColumnWidth: timeColumnWidth
                                )
                            }
                        }

                        // Planned activities (with offset to not overlap with external events)
                        ForEach(activities) { activity in
                            ActivityBlock(
                                activity: activity,
                                hourHeight: hourHeight,
                                offset: calculateActivityOffset(for: activity),
                                onTap: { onActivityTap(activity) },
                                onTimeChanged: { newTime in
                                    onActivityTimeChanged?(activity, newTime)
                                },
                                onDurationChanged: { newDuration in
                                    onActivityDurationChanged?(activity, newDuration)
                                }
                            )
                        }

                        // Current time indicator
                        if Calendar.current.isDateInToday(selectedDate) {
                            CurrentTimeIndicator(hourHeight: hourHeight)
                        }
                    }
                    .onAppear {
                        // Scroll to current hour or 8 AM
                        let targetHour = Calendar.current.isDateInToday(selectedDate)
                            ? max(0, Calendar.current.component(.hour, from: Date()) - 1)
                            : 8
                        proxy.scrollTo(targetHour, anchor: .top)
                    }
                }
            }
        }
    }

    // Calculate offset for activities to avoid overlapping with external events
    private func calculateActivityOffset(for activity: PlannedActivity) -> CGFloat {
        let overlappingEvents = timedEvents.filter { event in
            activity.startTime < event.endDate && activity.endTime > event.startDate
        }
        if overlappingEvents.isEmpty { return 0 }

        // Find max columns used by overlapping events
        var maxColumns = 1
        for event in overlappingEvents {
            if let layout = eventLayout[event.id] {
                maxColumns = max(maxColumns, layout.totalColumns)
            }
        }
        // Activity goes in the last column
        return CGFloat(maxColumns) * 0.15 // 15% offset per column
    }
}

// MARK: - All Day Events Bar

struct AllDayEventsBar: View {
    let events: [CalendarEvent]
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("All Day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("(\(events.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !isExpanded {
                        Text(events.map { $0.title }.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.blue.opacity(0.1))

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        HStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)

                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.05))
            }

            Divider()
        }
    }
}

// MARK: - Date Navigation Header

struct DateNavigationHeader: View {
    @Binding var selectedDate: Date

    var body: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(selectedDate, format: .dateTime.weekday(.wide))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(selectedDate, format: .dateTime.month().day().year())
                    .font(.headline)
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Hour Row

struct HourRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(hourLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
        }
        .frame(height: hourHeight)
    }

    private var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Activity Block (Draggable)

struct ActivityBlock: View {
    let activity: PlannedActivity
    let hourHeight: CGFloat
    var offset: CGFloat = 0
    let onTap: () -> Void
    var onTimeChanged: ((Date) -> Void)? = nil
    var onDurationChanged: ((Int) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var currentDragTime: (hour: Int, minute: Int)? = nil
    @GestureState private var isLongPressing = false

    // Resize state
    @State private var isResizing = false
    @State private var resizeOffset: CGFloat = 0
    @State private var currentResizeDuration: Int? = nil

    var body: some View {
        let baseYOffset = calculateYOffset()
        let yOffset = baseYOffset + dragOffset
        let baseHeight = calculateHeight()
        let height = baseHeight + resizeOffset

        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 82 // 66 leading + 16 trailing
            let activityWidth = availableWidth * (1 - offset)
            let leadingOffset = 66 + (availableWidth * offset)

            ZStack {
                VStack(spacing: 0) {
                    // Activity content
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(activity.color)
                            .frame(width: 4)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.title)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            if height > 35 {
                                if isDragging, let time = currentDragTime {
                                    Text(formatTime(hour: time.hour, minute: time.minute))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                } else if isResizing, let dur = currentResizeDuration {
                                    Text("\(dur) min")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .fontWeight(.medium)
                                } else {
                                    Text(activity.timeRangeFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        if height > 30 {
                            Image(systemName: isDragging ? "arrow.up.and.down" : (isResizing ? "arrow.up.and.down.and.arrow.left.and.right" : activity.icon))
                                .font(.caption2)
                                .foregroundColor(isDragging || isResizing ? .blue : activity.color)
                        }
                    }
                    .padding(6)

                    Spacer(minLength: 0)

                    // Resize handle at bottom
                    Rectangle()
                        .fill(isResizing ? Color.orange : Color.clear)
                        .frame(height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isResizing ? Color.orange : activity.color.opacity(0.5))
                                .frame(width: 30, height: 3)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isResizing {
                                        isResizing = true
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    // Calculate new duration and snap to 15-minute intervals
                                    let newHeightPx = baseHeight + value.translation.height
                                    let newMinutes = Int((newHeightPx / hourHeight) * 60)
                                    let snappedMinutes = max(15, (newMinutes / 15) * 15)
                                    // Snap the visual offset to match the snapped duration
                                    let snappedHeight = CGFloat(snappedMinutes) / 60.0 * hourHeight
                                    resizeOffset = snappedHeight - baseHeight
                                    currentResizeDuration = snappedMinutes
                                }
                                .onEnded { value in
                                    // Use the already snapped value from currentResizeDuration
                                    if let duration = currentResizeDuration {
                                        // Reset visual state first to prevent jump
                                        resizeOffset = 0
                                        isResizing = false
                                        currentResizeDuration = nil
                                        onDurationChanged?(duration)
                                    } else {
                                        withAnimation(.spring(response: 0.3)) {
                                            isResizing = false
                                            resizeOffset = 0
                                            currentResizeDuration = nil
                                        }
                                    }
                                }
                        )
                }
                .frame(width: activityWidth, alignment: .leading)
                .frame(height: max(height - 4, 26))
                .background((isDragging || isResizing) ? activity.color.opacity(0.35) : activity.color.opacity(0.2))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke((isDragging || isResizing) ? Color.blue : activity.color, lineWidth: (isDragging || isResizing) ? 2 : 1)
                )
                .shadow(color: (isDragging || isResizing) ? Color.black.opacity(0.2) : .clear, radius: 4, y: 2)
                .scaleEffect(isDragging ? 1.02 : 1.0)
            }
            .position(x: leadingOffset + activityWidth / 2, y: yOffset + height / 2)
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .updating($isLongPressing) { currentState, gestureState, transaction in
                        gestureState = currentState
                    }
                    .sequenced(before: DragGesture())
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            // Long press started
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDragging = true
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        case .second(true, let drag):
                            // Dragging
                            if let drag = drag {
                                // Snap drag offset to 15-minute intervals for smooth visual feedback
                                let rawNewY = baseYOffset + drag.translation.height
                                let totalMinutes = Int((rawNewY / hourHeight) * 60)
                                let snappedMinutes = max(0, min(23 * 60 + 45, (totalMinutes / 15) * 15))
                                let snappedY = CGFloat(snappedMinutes) / 60.0 * hourHeight
                                dragOffset = snappedY - baseYOffset

                                let snappedHour = snappedMinutes / 60
                                let snappedMinute = snappedMinutes % 60
                                currentDragTime = (hour: snappedHour, minute: snappedMinute)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        if case .second(true, let drag) = value, let drag = drag {
                            // Use the already snapped values from currentDragTime
                            if let time = currentDragTime {
                                var components = Calendar.current.dateComponents([.year, .month, .day], from: activity.startTime)
                                components.hour = time.hour
                                components.minute = time.minute

                                if let newTime = Calendar.current.date(from: components) {
                                    // Update the time - reset dragOffset first to prevent jump
                                    dragOffset = 0
                                    isDragging = false
                                    currentDragTime = nil
                                    onTimeChanged?(newTime)
                                    return
                                }
                            }
                        }

                        withAnimation(.spring(response: 0.3)) {
                            isDragging = false
                            dragOffset = 0
                            currentDragTime = nil
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !isDragging {
                            onTap()
                        }
                    }
            )
        }
        .frame(height: 24 * hourHeight) // Full day height
        .zIndex(isDragging ? 100 : 0)
    }

    private func calculateYOffset() -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: activity.startTime)
        let minute = calendar.component(.minute, from: activity.startTime)
        return CGFloat(hour) * hourHeight + CGFloat(minute) / 60 * hourHeight
    }

    private func calculateHeight() -> CGFloat {
        CGFloat(activity.duration) / 60 * hourHeight
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):\(String(format: "%02d", minute))"
    }
}

// MARK: - External Event Block

struct ExternalEventBlock: View {
    let event: CalendarEvent
    let hourHeight: CGFloat
    var column: Int = 0
    var totalColumns: Int = 1
    var timeColumnWidth: CGFloat = 50

    var body: some View {
        let yOffset = calculateYOffset()
        let height = calculateHeight()

        GeometryReader { geometry in
            let totalWidth = geometry.size.width - timeColumnWidth - 32 // padding
            let columnWidth = totalColumns > 0 ? totalWidth / CGFloat(totalColumns) : totalWidth
            let xOffset = timeColumnWidth + 16 + (CGFloat(column) * columnWidth)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(height > 40 ? 2 : 1)
                            .foregroundColor(.primary)

                        if height > 35 && event.isWalkable {
                            HStack(spacing: 2) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 8))
                                Text("Walkable")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(4)
            }
            .frame(width: columnWidth - 4, alignment: .leading)
            .frame(height: max(height - 2, 24))
            .background(Color.blue.opacity(0.15))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 0.5)
            )
            .position(x: xOffset + (columnWidth - 4) / 2, y: yOffset + height / 2)
        }
        .frame(height: 24 * hourHeight) // Full day height
    }

    private func calculateYOffset() -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: event.startDate)
        let minute = calendar.component(.minute, from: event.startDate)
        return CGFloat(hour) * hourHeight + CGFloat(minute) / 60 * hourHeight
    }

    private func calculateHeight() -> CGFloat {
        CGFloat(event.duration) / 60 * hourHeight
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat

    var body: some View {
        let yOffset = calculateYOffset()

        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .offset(x: 56)

            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .offset(y: yOffset)
    }

    private func calculateYOffset() -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        return CGFloat(hour) * hourHeight + CGFloat(minute) / 60 * hourHeight
    }
}

// MARK: - Week Calendar View

struct WeekCalendarView: View {
    @Binding var selectedDate: Date
    let activities: [PlannedActivity]
    let onDayTap: (Date) -> Void

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Week navigation
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(weekRangeText)
                    .font(.headline)

                Spacer()

                Button {
                    selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding()

            // Week days header
            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    WeekDayHeader(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        activityCount: activities(for: date).count,
                        onTap: { onDayTap(date) }
                    )
                }
            }
            .padding(.horizontal, 8)

            Divider()

            // Activities list for selected date
            List {
                let dayActivities = activities(for: selectedDate)
                if dayActivities.isEmpty {
                    Text("No activities scheduled")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(dayActivities) { activity in
                        WeekActivityRow(activity: activity)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var weekRangeText: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }

    private func activities(for date: Date) -> [PlannedActivity] {
        activities.filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }
}

struct WeekDayHeader: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let activityCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(date, format: .dateTime.day())
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isToday ? .white : (isSelected ? .blue : .primary))
                    .frame(width: 32, height: 32)
                    .background(isToday ? Color.blue : (isSelected ? Color.blue.opacity(0.1) : Color.clear))
                    .clipShape(Circle())

                if activityCount > 0 {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct WeekActivityRow: View {
    let activity: PlannedActivity

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(activity.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(activity.timeRangeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if activity.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let activities: [PlannedActivity]
    let onDayTap: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Spacer()

                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(.headline)

                Spacer()

                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
            }
            .padding(.horizontal)

            // Weekday headers
            HStack {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        MonthDayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: selectedDate, toGranularity: .month),
                            activityCount: activities(for: date).count,
                            onTap: { onDayTap(date) }
                        )
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }

    private func daysInMonth() -> [Date?] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }

        // Pad to complete the last week
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func activities(for date: Date) -> [PlannedActivity] {
        activities.filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
    }
}

struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let activityCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(date, format: .dateTime.day())
                    .font(.subheadline)
                    .fontWeight(isSelected || isToday ? .bold : .regular)
                    .foregroundColor(textColor)

                if activityCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(activityCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(width: 40, height: 44)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        if isToday { return .white }
        if isSelected { return .blue }
        if !isCurrentMonth { return .gray }
        return .primary
    }

    private var backgroundColor: Color {
        if isToday { return .blue }
        if isSelected { return .blue.opacity(0.1) }
        return .clear
    }
}

// MARK: - Calendar Sync Bar

struct CalendarSyncBar: View {
    let isSyncing: Bool
    let syncSuccess: Bool
    let hasActivities: Bool
    let onSyncTap: () -> Void

    var body: some View {
        HStack {
            if syncSuccess {
                Label("Synced!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if hasActivities {
                Text("Scheduled activities")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No activities scheduled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onSyncTap()
            } label: {
                HStack(spacing: 4) {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("Sync")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
            }
            .disabled(isSyncing || !hasActivities)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Calendar Sync To External Sheet

struct CalendarSyncToExternalSheet: View {
    let activities: [PlannedActivity]
    let selectedDate: Date
    let onSync: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var calendarManager: CalendarManager
    @State private var selectedCalendars: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                // Activities to sync
                Section("Activities to Sync") {
                    if activities.isEmpty {
                        Text("No activities for this day")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(activities) { activity in
                            HStack {
                                Image(systemName: activity.icon)
                                    .foregroundColor(activity.color)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(activity.title)
                                        .font(.subheadline)
                                    Text(activity.timeRangeFormatted)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(activity.duration) min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Calendar selection
                Section("Sync To") {
                    ForEach(calendarManager.availableCalendars) { calendar in
                        Button {
                            if selectedCalendars.contains(calendar.id) {
                                selectedCalendars.remove(calendar.id)
                            } else {
                                selectedCalendars.insert(calendar.id)
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 12, height: 12)

                                VStack(alignment: .leading) {
                                    Text(calendar.title)
                                        .foregroundColor(.primary)
                                    Text(calendar.source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedCalendars.contains(calendar.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sync to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sync") {
                        onSync(Array(selectedCalendars))
                        dismiss()
                    }
                    .disabled(selectedCalendars.isEmpty || activities.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ActivslotCalendarView()
        .environmentObject(CalendarManager.shared)
}
