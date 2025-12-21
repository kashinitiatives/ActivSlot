import Foundation

// MARK: - Workout Type

enum WorkoutType: String, CaseIterable, Codable {
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case cardio = "Cardio"
    case fullBody = "Full Body"

    var description: String {
        switch self {
        case .push: return "Chest, Shoulders, Triceps"
        case .pull: return "Back, Biceps"
        case .legs: return "Quads, Hamstrings, Glutes"
        case .cardio: return "Running, Cycling, Swimming"
        case .fullBody: return "Compound movements"
        }
    }

    var icon: String {
        switch self {
        case .push: return "figure.strengthtraining.traditional"
        case .pull: return "figure.rowing"
        case .legs: return "figure.run"
        case .cardio: return "figure.run.circle"
        case .fullBody: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Step Slot (time-based walking suggestion)

struct StepSlot: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let slotType: SlotType
    let targetSteps: Int
    let source: String? // Meeting title or "Free time"

    enum SlotType: String {
        case walkableMeeting = "Walkable Meeting"
        case freeTime = "Free Time"
        case breakTime = "Break"
    }

    var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var targetStepsFormatted: String {
        "~\(targetSteps.formatted()) steps"
    }
}

// MARK: - Workout Slot

struct WorkoutSlot: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let workoutType: WorkoutType
    let isRecommended: Bool

    var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}

// MARK: - Legacy Support (for existing code)

struct WalkSuggestion: Identifiable {
    let id = UUID()
    let meetingTitle: String
    let startTime: Date
    let duration: Int // minutes
    let estimatedSteps: Int
    let isWalkable: Bool

    var estimatedStepsFormatted: String {
        "~\(estimatedSteps.formatted()) steps"
    }
}

struct GymSuggestion: Identifiable {
    let id = UUID()
    let suggestedTime: Date
    let duration: Int // minutes
    let workoutType: WorkoutType

    var timeRangeFormatted: String {
        let endTime = Calendar.current.date(byAdding: .minute, value: duration, to: suggestedTime) ?? suggestedTime
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: suggestedTime)) - \(formatter.string(from: endTime))"
    }

    func toWorkoutSlot() -> WorkoutSlot {
        WorkoutSlot(
            startTime: suggestedTime,
            endTime: Calendar.current.date(byAdding: .minute, value: duration, to: suggestedTime) ?? suggestedTime,
            workoutType: workoutType,
            isRecommended: true
        )
    }
}

// MARK: - Day Movement Plan

struct DayMovementPlan: Identifiable {
    let id = UUID()
    let date: Date

    // Step slots throughout the day
    var stepSlots: [StepSlot]

    // Workout suggestions
    var workoutSlot: WorkoutSlot?

    // Progress tracking
    var targetSteps: Int
    var currentSteps: Int

    // Legacy support
    var walkSuggestions: [WalkSuggestion]
    var gymSuggestion: GymSuggestion?
    var projectedSteps: Int

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(date)
    }

    var stepsRemaining: Int {
        max(0, targetSteps - currentSteps)
    }

    var stepProgress: Double {
        guard targetSteps > 0 else { return 0 }
        return min(1.0, Double(currentSteps) / Double(targetSteps))
    }

    var totalSlotSteps: Int {
        stepSlots.reduce(0) { $0 + $1.targetSteps }
    }

    // Initialize with new structure
    init(date: Date, stepSlots: [StepSlot], workoutSlot: WorkoutSlot?, targetSteps: Int, currentSteps: Int) {
        self.date = date
        self.stepSlots = stepSlots
        self.workoutSlot = workoutSlot
        self.targetSteps = targetSteps
        self.currentSteps = currentSteps

        // Legacy support
        self.walkSuggestions = stepSlots.filter { $0.slotType == .walkableMeeting }.map {
            WalkSuggestion(
                meetingTitle: $0.source ?? "Meeting",
                startTime: $0.startTime,
                duration: $0.duration,
                estimatedSteps: $0.targetSteps,
                isWalkable: true
            )
        }
        self.gymSuggestion = workoutSlot.map {
            GymSuggestion(
                suggestedTime: $0.startTime,
                duration: $0.duration,
                workoutType: $0.workoutType
            )
        }
        // Calculate directly instead of using computed property
        self.projectedSteps = stepSlots.reduce(0) { $0 + $1.targetSteps } + currentSteps
    }

    // Legacy initializer for backward compatibility
    init(date: Date, walkSuggestions: [WalkSuggestion], gymSuggestion: GymSuggestion?, projectedSteps: Int, currentSteps: Int) {
        self.date = date
        self.walkSuggestions = walkSuggestions
        self.gymSuggestion = gymSuggestion
        self.projectedSteps = projectedSteps
        self.currentSteps = currentSteps
        self.targetSteps = UserPreferences.shared.dailyStepGoal

        // Convert to new structure
        self.stepSlots = walkSuggestions.map {
            StepSlot(
                startTime: $0.startTime,
                endTime: Calendar.current.date(byAdding: .minute, value: $0.duration, to: $0.startTime) ?? $0.startTime,
                slotType: .walkableMeeting,
                targetSteps: $0.estimatedSteps,
                source: $0.meetingTitle
            )
        }
        self.workoutSlot = gymSuggestion?.toWorkoutSlot()
    }
}

// MARK: - Calendar Display Event

struct CalendarDisplayEvent: Identifiable {
    let id = UUID()
    let title: String
    let startTime: Date
    let endTime: Date
    let eventType: EventType
    let color: String

    enum EventType {
        case meeting
        case walkableSlot
        case workoutSlot
        case freeTime
    }

    var duration: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}
