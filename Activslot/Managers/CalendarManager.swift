import Foundation
import EventKit
import SwiftUI

enum CalendarError: Error {
    case accessDenied
    case noCalendars
    case fetchFailed
}

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let color: Color
    let calendarIdentifier: String
    let isOwned: Bool  // true if user owns this calendar, false if subscribed/shared
    let allowsModifications: Bool
    let ownerEmail: String?  // Email of calendar owner (if available)

    var sourceType: CalendarSourceType {
        let lowercaseSource = source.lowercased()
        let lowercaseTitle = title.lowercased()

        // Check both source and title for better detection
        if lowercaseSource.contains("outlook") || lowercaseSource.contains("microsoft") || lowercaseSource.contains("exchange") ||
           lowercaseTitle.contains("outlook") {
            return .outlook
        } else if lowercaseSource.contains("google") || lowercaseSource.contains("gmail") ||
                  lowercaseSource.contains("@gmail.com") || lowercaseSource.contains("@googlemail.com") ||
                  lowercaseTitle.contains("google") || lowercaseTitle.contains("gmail") {
            return .google
        } else if lowercaseSource.contains("icloud") || lowercaseSource.contains("apple") ||
                  lowercaseTitle.contains("icloud") {
            return .icloud
        } else {
            // Check if source looks like a Google email account
            if lowercaseSource.contains("@") && (lowercaseSource.hasSuffix("gmail.com") || lowercaseSource.hasSuffix("googlemail.com")) {
                return .google
            }
            return .other
        }
    }

    var sourceIcon: String {
        switch sourceType {
        case .outlook: return "envelope.fill"
        case .google: return "g.circle.fill"
        case .icloud: return "icloud.fill"
        case .other: return "calendar"
        }
    }
}

enum CalendarSourceType {
    case outlook
    case google
    case icloud
    case other
}

class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()

    @Published var isAuthorized = false
    @Published var todayEvents: [CalendarEvent] = []
    @Published var tomorrowEvents: [CalendarEvent] = []
    @Published var availableCalendars: [CalendarInfo] = []

    // Selected calendar IDs stored in UserDefaults
    @AppStorage("selectedCalendarIDs") private var selectedCalendarIDsData: Data = Data()
    // Version 4: Filter by user's email address
    @AppStorage("calendarFilterVersion") private var calendarFilterVersion: Int = 0
    private let currentFilterVersion = 4

    // User's email addresses (from calendar accounts)
    @AppStorage("userEmailAddresses") private var userEmailAddressesData: Data = Data()

    var userEmailAddresses: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: userEmailAddressesData)) ?? []
        }
        set {
            userEmailAddressesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var selectedCalendarIDs: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: selectedCalendarIDsData)) ?? []
        }
        set {
            selectedCalendarIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                self.isAuthorized = granted
                if granted {
                    self.loadAvailableCalendars()
                }
            }
            return granted
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    DispatchQueue.main.async {
                        self.isAuthorized = granted
                        if granted {
                            self.loadAvailableCalendars()
                        }
                    }
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            isAuthorized = status == .fullAccess
        } else {
            isAuthorized = status == .authorized
        }

        if isAuthorized {
            loadAvailableCalendars()
        }
    }

    // MARK: - Calendar Management

    func loadAvailableCalendars() {
        let calendars = eventStore.calendars(for: .event)

        // First, extract user's email addresses from calendar sources
        // These are emails from accounts the user has signed into
        var detectedUserEmails = Set<String>()
        for source in eventStore.sources {
            // The source title often contains the email for Exchange/Google accounts
            let sourceTitle = source.title.lowercased()
            if sourceTitle.contains("@") {
                detectedUserEmails.insert(sourceTitle)
            }
        }

        // Store detected emails for future reference
        if !detectedUserEmails.isEmpty {
            userEmailAddresses = userEmailAddresses.union(detectedUserEmails)
        }

        availableCalendars = calendars.compactMap { calendar -> CalendarInfo? in
            // Get calendar owner email if available
            let ownerEmail = extractOwnerEmail(from: calendar)

            // Determine if this is an owned calendar vs subscribed/shared
            let isSubscription = calendar.type == .subscription
            let isBirthday = calendar.type == .birthday
            let isReadOnly = !calendar.allowsContentModifications
            let titleLower = calendar.title.lowercased()
            let sourceTitle = calendar.source.title.lowercased()

            // Check if the calendar belongs to the user by email matching
            let isOwnedByEmail: Bool
            if let ownerEmail = ownerEmail {
                // If we have an owner email, check if it matches any of user's emails
                let ownerLower = ownerEmail.lowercased()
                isOwnedByEmail = userEmailAddresses.contains { userEmail in
                    ownerLower == userEmail || ownerLower.contains(userEmail) || userEmail.contains(ownerLower)
                }
            } else if sourceTitle.contains("@") {
                // The source title contains an email - this is the user's account
                isOwnedByEmail = userEmailAddresses.contains(sourceTitle)
            } else {
                // No email info available, use other heuristics
                isOwnedByEmail = true // Assume owned if we can't determine
            }

            // Common patterns for shared/other people's calendars
            let looksShared = titleLower.contains("'s calendar") ||
                              titleLower.contains("'s calendar") ||
                              titleLower.contains("shared") ||
                              titleLower.hasPrefix("calendar - ") ||
                              titleLower.contains(" - calendar") ||
                              looksLikePersonName(titleLower)

            // A calendar is owned if:
            // 1. It's not a subscription or birthday calendar
            // 2. It allows modifications (not read-only)
            // 3. It doesn't look like a shared calendar
            // 4. The owner email matches user's email (if available)
            let isOwned = !isSubscription && !isBirthday && !isReadOnly && !looksShared && isOwnedByEmail

            return CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                source: calendar.source.title,
                color: Color(cgColor: calendar.cgColor),
                calendarIdentifier: calendar.calendarIdentifier,
                isOwned: isOwned,
                allowsModifications: calendar.allowsContentModifications,
                ownerEmail: ownerEmail
            )
        }.sorted { $0.title < $1.title }

        // If no calendars selected yet, select only owned calendars by default
        if selectedCalendarIDs.isEmpty && !availableCalendars.isEmpty {
            let ownedCalendars = availableCalendars.filter { $0.isOwned }
            selectedCalendarIDs = Set(ownedCalendars.map { $0.id })
            calendarFilterVersion = currentFilterVersion
        }

        // For existing users with an older filter version, re-apply the enhanced filter
        // This ensures users get the improved owned calendar detection
        if calendarFilterVersion < currentFilterVersion && !availableCalendars.isEmpty {
            let ownedCalendars = availableCalendars.filter { $0.isOwned }
            selectedCalendarIDs = Set(ownedCalendars.map { $0.id })
            calendarFilterVersion = currentFilterVersion
        }
    }

    /// Extracts the owner email from a calendar if available
    private func extractOwnerEmail(from calendar: EKCalendar) -> String? {
        // For Exchange/CalDAV calendars, try to get the owner from the source
        let sourceTitle = calendar.source.title

        // If source title looks like an email, that's the owner
        if sourceTitle.contains("@") {
            return sourceTitle.lowercased()
        }

        // For some calendars, the title might contain the owner's email or name
        let title = calendar.title
        if title.contains("@") {
            // Extract email from title
            let components = title.components(separatedBy: CharacterSet.whitespaces)
            for component in components {
                if component.contains("@") && component.contains(".") {
                    return component.lowercased()
                }
            }
        }

        return nil
    }

    /// Checks if a calendar title looks like a person's name (e.g., "John Smith", "Mary Jane")
    /// These are typically shared calendars from coworkers
    private func looksLikePersonName(_ title: String) -> Bool {
        let words = title.split(separator: " ").map { String($0) }

        // Skip common calendar names that aren't person names
        let commonCalendarNames = ["calendar", "work", "personal", "home", "family", "reminders",
                                   "holidays", "birthdays", "tasks", "meetings", "events"]
        if words.count == 1 && commonCalendarNames.contains(words[0].lowercased()) {
            return false
        }

        // If it's exactly 2 words and both start with uppercase (First Last pattern)
        // and doesn't contain common calendar keywords
        if words.count == 2 {
            let first = words[0]
            let second = words[1]

            // Check if both words start with uppercase and are likely names
            let firstIsCapitalized = first.first?.isUppercase == true
            let secondIsCapitalized = second.first?.isUppercase == true
            let noCalendarKeywords = !title.lowercased().contains("calendar") &&
                                     !title.lowercased().contains("work") &&
                                     !title.lowercased().contains("personal")

            // Both words should be 2+ characters and capitalized
            if firstIsCapitalized && secondIsCapitalized &&
               first.count >= 2 && second.count >= 2 && noCalendarKeywords {
                return true
            }
        }

        return false
    }

    func toggleCalendarSelection(_ calendarID: String) {
        if selectedCalendarIDs.contains(calendarID) {
            selectedCalendarIDs.remove(calendarID)
        } else {
            selectedCalendarIDs.insert(calendarID)
        }
    }

    func isCalendarSelected(_ calendarID: String) -> Bool {
        selectedCalendarIDs.contains(calendarID)
    }

    func selectAllCalendars() {
        selectedCalendarIDs = Set(availableCalendars.map { $0.id })
    }

    func deselectAllCalendars() {
        selectedCalendarIDs = []
    }

    /// Selects only calendars owned by the user (excludes subscribed/shared calendars)
    func selectOnlyOwnedCalendars() {
        let ownedCalendars = availableCalendars.filter { $0.isOwned }
        selectedCalendarIDs = Set(ownedCalendars.map { $0.id })
    }

    /// Adds a user email address and reloads calendars to re-evaluate ownership
    func addUserEmail(_ email: String) {
        var emails = userEmailAddresses
        emails.insert(email.lowercased())
        userEmailAddresses = emails

        // Reload calendars to re-evaluate which are owned
        loadAvailableCalendars()

        // Re-select only owned calendars
        selectOnlyOwnedCalendars()
    }

    /// Removes a user email address
    func removeUserEmail(_ email: String) {
        var emails = userEmailAddresses
        emails.remove(email.lowercased())
        userEmailAddresses = emails

        // Reload calendars to re-evaluate which are owned
        loadAvailableCalendars()
    }

    /// Returns calendars owned by the user
    var ownedCalendars: [CalendarInfo] {
        availableCalendars.filter { $0.isOwned }
    }

    /// Returns subscribed/shared calendars (from other people)
    var subscribedCalendars: [CalendarInfo] {
        availableCalendars.filter { !$0.isOwned }
    }

    private func getSelectedEKCalendars() -> [EKCalendar]? {
        guard !selectedCalendarIDs.isEmpty else { return nil }

        let allCalendars = eventStore.calendars(for: .event)
        let selected = allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }

        return selected.isEmpty ? nil : selected
    }

    // MARK: - Calendar Source Detection

    var hasOutlookCalendar: Bool {
        // Check both availableCalendars and raw EKSources
        if availableCalendars.contains(where: { $0.sourceType == .outlook }) {
            return true
        }
        // Also check EKSources directly
        return eventStore.sources.contains { source in
            let title = source.title.lowercased()
            return title.contains("outlook") || title.contains("exchange") || title.contains("microsoft")
        }
    }

    var hasGoogleCalendar: Bool {
        // Check both availableCalendars and raw EKSources
        if availableCalendars.contains(where: { $0.sourceType == .google }) {
            return true
        }
        // Also check EKSources directly for Gmail accounts
        return eventStore.sources.contains { source in
            let title = source.title.lowercased()
            return title.contains("google") || title.contains("gmail") ||
                   title.hasSuffix("@gmail.com") || title.hasSuffix("@googlemail.com")
        }
    }

    var connectedSources: [String] {
        var sources: [String] = []
        if hasOutlookCalendar { sources.append("Outlook") }
        if hasGoogleCalendar { sources.append("Google") }
        if availableCalendars.contains(where: { $0.sourceType == .icloud }) ||
           eventStore.sources.contains(where: { $0.title.lowercased().contains("icloud") }) {
            sources.append("iCloud")
        }
        return sources
    }

    // MARK: - Fetch Events

    func fetchEvents(for date: Date) async throws -> [CalendarEvent] {
        guard isAuthorized else {
            throw CalendarError.accessDenied
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Only fetch from selected calendars
        let calendarsToUse = getSelectedEKCalendars()
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendarsToUse)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { CalendarEvent(from: $0) }
    }

    func fetchTodayEvents() async throws {
        let events = try await fetchEvents(for: Date())
        await MainActor.run {
            self.todayEvents = events
        }
    }

    func fetchTomorrowEvents() async throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let events = try await fetchEvents(for: tomorrow)
        await MainActor.run {
            self.tomorrowEvents = events
        }
    }

    // MARK: - Walkable Meetings

    func getWalkableMeetings(for date: Date) async throws -> [CalendarEvent] {
        let events = try await fetchEvents(for: date)
        return events.filter { $0.isWalkable }
    }

    func getTodayWalkableMeetings() async throws -> [CalendarEvent] {
        try await getWalkableMeetings(for: Date())
    }

    func getTomorrowWalkableMeetings() async throws -> [CalendarEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return try await getWalkableMeetings(for: tomorrow)
    }

    // MARK: - Find Free Slots

    func findFreeSlots(for date: Date, minimumDuration: Int = 45) async throws -> [DateInterval] {
        let events = try await fetchEvents(for: date)
        let calendar = Calendar.current

        // Define working hours (7 AM to 10 PM)
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = 7
        startComponents.minute = 0
        let dayStart = calendar.date(from: startComponents)!

        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)
        endComponents.hour = 22
        endComponents.minute = 0
        let dayEnd = calendar.date(from: endComponents)!

        // Sort events by start time
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }

        var freeSlots: [DateInterval] = []
        var currentTime = dayStart

        for event in sortedEvents {
            if event.startDate > currentTime {
                let gap = DateInterval(start: currentTime, end: event.startDate)
                let gapMinutes = Int(gap.duration / 60)
                if gapMinutes >= minimumDuration {
                    freeSlots.append(gap)
                }
            }
            if event.endDate > currentTime {
                currentTime = event.endDate
            }
        }

        // Check for free time after last event
        if currentTime < dayEnd {
            let gap = DateInterval(start: currentTime, end: dayEnd)
            let gapMinutes = Int(gap.duration / 60)
            if gapMinutes >= minimumDuration {
                freeSlots.append(gap)
            }
        }

        return freeSlots
    }

    // MARK: - Meeting Load

    func getMeetingLoad(for date: Date) async throws -> Int {
        let events = try await fetchEvents(for: date)
        return events.reduce(0) { $0 + $1.duration }
    }

    func isDayHeavyWithMeetings(for date: Date, threshold: Int = 360) async throws -> Bool {
        let totalMinutes = try await getMeetingLoad(for: date)
        return totalMinutes >= threshold // 6+ hours of meetings
    }
}
