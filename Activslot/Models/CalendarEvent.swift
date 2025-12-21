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
        "training", "workshop", "onsite", "on-site"
    ]

    var isWalkable: Bool {
        // Duration must be >= 20 minutes
        guard duration >= 20 else { return false }

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
