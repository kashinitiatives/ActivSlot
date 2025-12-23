import Foundation
import EventKit

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let attendeeCount: Int
    let isOrganizer: Bool
    let location: String?
    let notes: String?

    var duration: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    // Keywords that indicate a meeting is NOT walkable
    private static let nonWalkableKeywords = [
        "interview", "presentation", "review", "demo",
        "standup", "stand-up", "all hands", "all-hands",
        "training", "workshop", "onsite", "on-site",
        "out of office", "ooo", "pto", "vacation", "holiday",
        "focus time", "busy", "blocked", "do not disturb"
    ]

    /// Check if this is an all-day event (24 hours or more)
    var isAllDay: Bool {
        duration >= 1440 // 24 hours = 1440 minutes
    }

    /// Keywords that indicate an out-of-office or time-off event
    private static let outOfOfficeKeywords = [
        "out of office", "ooo", "pto", "vacation", "holiday",
        "off", "leave", "away", "time off", "day off", "sick"
    ]

    /// Check if this is an out-of-office or time-off event
    var isOutOfOffice: Bool {
        let lowercaseTitle = title.lowercased()
        for keyword in Self.outOfOfficeKeywords {
            if lowercaseTitle.contains(keyword) {
                return true
            }
        }
        return false
    }

    /// Check if this event should be counted as real meeting time for insights
    /// Excludes all-day events and out-of-office events
    var isRealMeeting: Bool {
        !isAllDay && !isOutOfOffice
    }

    var isWalkable: Bool {
        // All-day events are NOT walkable (e.g., Out of Office, holidays)
        guard !isAllDay else { return false }

        // Duration must be >= 20 minutes
        guard duration >= 20 else { return false }

        // Duration must be <= 120 minutes (2 hours) - no one can walk for longer
        guard duration <= 120 else { return false }

        // Must have 4+ attendees (indicating it's a larger meeting where you can listen)
        guard attendeeCount >= 4 else { return false }

        // User should NOT be the organizer
        guard !isOrganizer else { return false }

        // Check for non-walkable keywords in title
        let lowercaseTitle = title.lowercased()
        for keyword in Self.nonWalkableKeywords {
            if lowercaseTitle.contains(keyword) {
                return false
            }
        }

        return true
    }

    var estimatedSteps: Int {
        // Walking pace: ~100 steps/min
        duration * 100
    }

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "Untitled"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.attendeeCount = ekEvent.attendees?.count ?? 0
        self.isOrganizer = ekEvent.organizer?.isCurrentUser ?? false
        self.location = ekEvent.location
        self.notes = ekEvent.notes
    }

    init(id: String, title: String, startDate: Date, endDate: Date,
         attendeeCount: Int, isOrganizer: Bool, location: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.attendeeCount = attendeeCount
        self.isOrganizer = isOrganizer
        self.location = location
        self.notes = notes
    }
}
