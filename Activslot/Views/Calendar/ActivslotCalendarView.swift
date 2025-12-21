import SwiftUI

// MARK: - Calendar View Mode

enum CalendarViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
}

// MARK: - Main Calendar View

struct ActivslotCalendarView: View {
    @StateObject private var activityStore = ActivityStore.shared
    @EnvironmentObject var calendarManager: CalendarManager

    @State private var selectedDate = Date()
    @State private var viewMode: CalendarViewMode = .day
    @State private var showAddActivity = false
    @State private var selectedActivity: PlannedActivity?
    @State private var showActivityDetail = false
    @State private var externalEvents: [CalendarEvent] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View Mode Picker
                Picker("View", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Calendar Content
                switch viewMode {
                case .day:
                    DayCalendarView(
                        selectedDate: $selectedDate,
                        activities: activitiesForSelectedDate,
                        externalEvents: externalEvents,
                        onActivityTap: { activity in
                            selectedActivity = activity
                            showActivityDetail = true
                        },
                        onAddTap: { time in
                            selectedDate = time
                            showAddActivity = true
                        }
                    )
                case .week:
                    WeekCalendarView(
                        selectedDate: $selectedDate,
                        activities: activityStore.activities,
                        onDayTap: { date in
                            selectedDate = date
                            viewMode = .day
                        }
                    )
                case .month:
                    MonthCalendarView(
                        selectedDate: $selectedDate,
                        activities: activityStore.activities,
                        onDayTap: { date in
                            selectedDate = date
                            viewMode = .day
                        }
                    )
                }
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
                    Button {
                        showAddActivity = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddActivity) {
                AddActivitySheet(initialDate: selectedDate)
                    .environmentObject(activityStore)
            }
            .sheet(isPresented: $showActivityDetail) {
                if let activity = selectedActivity {
                    ActivityDetailSheet(activity: activity)
                        .environmentObject(activityStore)
                }
            }
            .task {
                await loadExternalEvents()
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await loadExternalEvents()
                }
            }
        }
    }

    private var activitiesForSelectedDate: [PlannedActivity] {
        activityStore.activities(for: selectedDate)
    }

    private func loadExternalEvents() async {
        if let events = try? await calendarManager.fetchEvents(for: selectedDate) {
            await MainActor.run {
                externalEvents = events
            }
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

    private let hourHeight: CGFloat = 60
    private let hours = Array(0..<24)

    var body: some View {
        VStack(spacing: 0) {
            // Date Header with navigation
            DateNavigationHeader(selectedDate: $selectedDate)

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

                        // External events (work calendar)
                        ForEach(externalEvents) { event in
                            ExternalEventBlock(
                                event: event,
                                hourHeight: hourHeight
                            )
                        }

                        // Planned activities
                        ForEach(activities) { activity in
                            ActivityBlock(
                                activity: activity,
                                hourHeight: hourHeight,
                                onTap: { onActivityTap(activity) }
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

// MARK: - Activity Block

struct ActivityBlock: View {
    let activity: PlannedActivity
    let hourHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        let yOffset = calculateYOffset()
        let height = calculateHeight()

        Button(action: onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(activity.color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(activity.timeRangeFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: activity.icon)
                    .font(.caption)
                    .foregroundColor(activity.color)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(height - 4, 30))
            .background(activity.color.opacity(0.15))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(activity.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.leading, 66)
        .padding(.trailing, 16)
        .offset(y: yOffset)
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
}

// MARK: - External Event Block

struct ExternalEventBlock: View {
    let event: CalendarEvent
    let hourHeight: CGFloat

    var body: some View {
        let yOffset = calculateYOffset()
        let height = calculateHeight()

        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if event.isWalkable {
                    Label("Walkable", systemImage: "figure.walk")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(height - 4, 30))
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.leading, 66)
        .padding(.trailing, 16)
        .offset(y: yOffset)
        .opacity(0.7)
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

#Preview {
    ActivslotCalendarView()
        .environmentObject(CalendarManager.shared)
}
