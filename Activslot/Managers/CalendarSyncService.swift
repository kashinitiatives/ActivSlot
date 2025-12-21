import Foundation
import EventKit
import SwiftUI

// MARK: - Calendar Sync Service

class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [String] = []

    // Settings
    @AppStorage("autoSyncEnabled") var autoSyncEnabled = false
    @AppStorage("defaultSyncCalendarID") var defaultSyncCalendarID: String = ""

    private init() {}

    // MARK: - Sync Single Activity

    func syncActivity(_ activity: PlannedActivity, toCalendars calendarIDs: [String]) async {
        guard !calendarIDs.isEmpty else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { await MainActor.run { isSyncing = false } } }

        for calendarID in calendarIDs {
            do {
                try await createEventInCalendar(activity: activity, calendarID: calendarID)
            } catch {
                await MainActor.run {
                    syncErrors.append("Failed to sync to calendar: \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run { lastSyncDate = Date() }
    }

    // MARK: - Create Event in External Calendar

    private func createEventInCalendar(activity: PlannedActivity, calendarID: String) async throws {
        let calendars = eventStore.calendars(for: .event)
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID }) else {
            throw SyncError.calendarNotFound
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = activity.title
        event.startDate = activity.startTime
        event.endDate = activity.endTime
        event.notes = buildEventNotes(for: activity)

        // Set alert
        if let minutesBefore = activity.alertOption.minutesBefore {
            let alarm = EKAlarm(relativeOffset: TimeInterval(-minutesBefore * 60))
            event.addAlarm(alarm)
        }

        // Set recurrence rule
        if let recurrenceRule = activity.repeatOption.calendarRecurrenceRule {
            if let rule = parseRecurrenceRule(recurrenceRule) {
                event.addRecurrenceRule(rule)
            }
        }

        try eventStore.save(event, span: activity.repeatOption != .never ? .futureEvents : .thisEvent)

        // Update activity with external ID
        var updatedActivity = activity
        updatedActivity.externalCalendarId = event.eventIdentifier
        updatedActivity.syncStatus = .synced
        ActivityStore.shared.updateActivity(updatedActivity)
    }

    private func buildEventNotes(for activity: PlannedActivity) -> String {
        var notes = activity.notes

        if notes.isEmpty {
            notes = "Activslot \(activity.activityType.rawValue)"
        }

        if let workoutType = activity.workoutType {
            notes += "\n\nWorkout: \(workoutType.rawValue)\n\(workoutType.description)"
        }

        notes += "\n\n---\nCreated by Activslot"

        return notes
    }

    private func parseRecurrenceRule(_ ruleString: String) -> EKRecurrenceRule? {
        // Parse common recurrence patterns
        if ruleString.contains("FREQ=DAILY") {
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: EKRecurrenceEnd(occurrenceCount: 52)
            )
        } else if ruleString.contains("FREQ=WEEKLY") {
            let interval = ruleString.contains("INTERVAL=2") ? 2 : 1

            if ruleString.contains("BYDAY=MO,TU,WE,TH,FR") {
                // Weekdays only
                let weekdays = [
                    EKRecurrenceDayOfWeek(.monday),
                    EKRecurrenceDayOfWeek(.tuesday),
                    EKRecurrenceDayOfWeek(.wednesday),
                    EKRecurrenceDayOfWeek(.thursday),
                    EKRecurrenceDayOfWeek(.friday)
                ]
                return EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    daysOfTheWeek: weekdays,
                    daysOfTheMonth: nil,
                    monthsOfTheYear: nil,
                    weeksOfTheYear: nil,
                    daysOfTheYear: nil,
                    setPositions: nil,
                    end: EKRecurrenceEnd(occurrenceCount: 52)
                )
            }

            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: interval,
                end: EKRecurrenceEnd(occurrenceCount: 52)
            )
        } else if ruleString.contains("FREQ=MONTHLY") {
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                end: EKRecurrenceEnd(occurrenceCount: 12)
            )
        }

        return nil
    }

    // MARK: - Update Synced Activity

    func updateSyncedActivity(_ activity: PlannedActivity) async {
        guard let eventID = activity.externalCalendarId else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { await MainActor.run { isSyncing = false } } }

        do {
            if let event = eventStore.event(withIdentifier: eventID) {
                event.title = activity.title
                event.startDate = activity.startTime
                event.endDate = activity.endTime
                event.notes = buildEventNotes(for: activity)

                try eventStore.save(event, span: .thisEvent)

                var updated = activity
                updated.syncStatus = .synced
                await MainActor.run {
                    ActivityStore.shared.updateActivity(updated)
                }
            }
        } catch {
            await MainActor.run {
                syncErrors.append("Failed to update: \(error.localizedDescription)")
                var updated = activity
                updated.syncStatus = .error
                ActivityStore.shared.updateActivity(updated)
            }
        }
    }

    // MARK: - Delete from External Calendars

    func deleteFromExternalCalendars(_ activity: PlannedActivity) async {
        guard let eventID = activity.externalCalendarId else { return }

        do {
            if let event = eventStore.event(withIdentifier: eventID) {
                try eventStore.remove(event, span: .thisEvent)
            }
        } catch {
            await MainActor.run {
                syncErrors.append("Failed to delete from calendar: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Batch Sync

    func syncAllPendingActivities() async {
        let pendingActivities = ActivityStore.shared.activitiesNeedingSync()

        for activity in pendingActivities {
            if !activity.syncedCalendars.isEmpty {
                await syncActivity(activity, toCalendars: activity.syncedCalendars)
            }
        }
    }

    // MARK: - Sync Today's Plan

    func syncTodaysPlan(toCalendars calendarIDs: [String]) async {
        let today = Date()
        let activities = ActivityStore.shared.activities(for: today)

        for activity in activities {
            await syncActivity(activity, toCalendars: calendarIDs)
        }
    }

    // MARK: - Sync by Day of Week

    func syncByDayOfWeek(weekday: Int, toCalendars calendarIDs: [String]) async {
        let calendar = Calendar.current
        let activities = ActivityStore.shared.activities.filter {
            calendar.component(.weekday, from: $0.startTime) == weekday
        }

        for activity in activities {
            await syncActivity(activity, toCalendars: calendarIDs)
        }
    }

    // MARK: - Clear Sync Errors

    func clearErrors() {
        syncErrors = []
    }

    // MARK: - Error Types

    enum SyncError: Error, LocalizedError {
        case calendarNotFound
        case noPermission
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .calendarNotFound:
                return "Calendar not found"
            case .noPermission:
                return "No permission to access calendar"
            case .saveFailed:
                return "Failed to save event"
            }
        }
    }
}

// MARK: - Sync Settings View

struct CalendarSyncSettingsView: View {
    @StateObject private var syncService = CalendarSyncService.shared
    @StateObject private var calendarManager = CalendarManager.shared
    @StateObject private var activityStore = ActivityStore.shared

    @State private var selectedCalendars: Set<String> = []
    @State private var showSyncConfirmation = false
    @State private var syncScope: SyncScope = .today

    enum SyncScope: String, CaseIterable {
        case today = "Today's Plan"
        case thisWeek = "This Week"
        case allPending = "All Pending"
    }

    var body: some View {
        List {
            // Auto Sync
            Section {
                Toggle("Auto-sync New Activities", isOn: $syncService.autoSyncEnabled)

                if syncService.autoSyncEnabled {
                    Picker("Default Calendar", selection: $syncService.defaultSyncCalendarID) {
                        Text("None").tag("")
                        ForEach(calendarManager.availableCalendars) { calendar in
                            HStack {
                                Circle()
                                    .fill(calendar.color)
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                            .tag(calendar.id)
                        }
                    }
                }
            } header: {
                Text("Automatic Sync")
            } footer: {
                Text("When enabled, new activities will automatically sync to your selected calendar.")
            }

            // Manual Sync
            Section {
                Button {
                    syncScope = .today
                    showSyncConfirmation = true
                } label: {
                    Label("Sync Today's Plan", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    syncScope = .thisWeek
                    showSyncConfirmation = true
                } label: {
                    Label("Sync This Week", systemImage: "calendar.badge.clock")
                }

                Button {
                    syncScope = .allPending
                    showSyncConfirmation = true
                } label: {
                    Label("Sync All Pending", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(activityStore.activitiesNeedingSync().isEmpty)
            } header: {
                Text("Manual Sync")
            }

            // Sync Status
            Section {
                if syncService.isSyncing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing...")
                            .foregroundColor(.secondary)
                    }
                } else if let lastSync = syncService.lastSyncDate {
                    LabeledContent("Last Sync", value: lastSync, format: .dateTime)
                }

                if !syncService.syncErrors.isEmpty {
                    DisclosureGroup {
                        ForEach(syncService.syncErrors, id: \.self) { error in
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } label: {
                        Label("\(syncService.syncErrors.count) Sync Error(s)", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }

                    Button("Clear Errors") {
                        syncService.clearErrors()
                    }
                    .foregroundColor(.red)
                }
            } header: {
                Text("Status")
            }

            // Synced Calendars Overview
            if !calendarManager.availableCalendars.isEmpty {
                Section {
                    ForEach(calendarManager.availableCalendars) { calendar in
                        HStack {
                            Circle()
                                .fill(calendar.color)
                                .frame(width: 12, height: 12)

                            Text(calendar.title)

                            Spacer()

                            Text(calendar.source)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Image(systemName: calendar.sourceIcon)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Available Calendars")
                }
            }
        }
        .navigationTitle("Calendar Sync")
        .sheet(isPresented: $showSyncConfirmation) {
            SyncScopeSheet(
                scope: syncScope,
                availableCalendars: calendarManager.availableCalendars,
                selectedCalendars: $selectedCalendars,
                onSync: { performSync() }
            )
        }
    }

    private func performSync() {
        Task {
            let calendarIDs = Array(selectedCalendars)
            switch syncScope {
            case .today:
                await syncService.syncTodaysPlan(toCalendars: calendarIDs)
            case .thisWeek:
                // Sync all days this week
                let calendar = Calendar.current
                let today = Date()
                for dayOffset in 0..<7 {
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: today) {
                        let activities = activityStore.activities(for: date)
                        for activity in activities {
                            await syncService.syncActivity(activity, toCalendars: calendarIDs)
                        }
                    }
                }
            case .allPending:
                await syncService.syncAllPendingActivities()
            }
        }
    }
}

// MARK: - Sync Scope Sheet

struct SyncScopeSheet: View {
    @Environment(\.dismiss) var dismiss

    let scope: CalendarSyncSettingsView.SyncScope
    let availableCalendars: [CalendarInfo]
    @Binding var selectedCalendars: Set<String>
    let onSync: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(availableCalendars) { calendar in
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

                                Text(calendar.title)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedCalendars.contains(calendar.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Calendars")
                } footer: {
                    Text("Your fitness activities will be added to the selected calendars.")
                }
            }
            .navigationTitle("Sync \(scope.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sync") {
                        onSync()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedCalendars.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
