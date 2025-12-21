import Foundation
import SwiftUI

// MARK: - Enums

enum GymFrequency: Int, CaseIterable, Codable {
    case none = 0
    case threeDays = 3
    case fourDays = 4
    case fiveDays = 5

    var displayName: String {
        switch self {
        case .none: return "Not set"
        case .threeDays: return "3 days/week"
        case .fourDays: return "4 days/week"
        case .fiveDays: return "5 days/week"
        }
    }
}

enum WorkoutDuration: Int, CaseIterable, Codable {
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case sixtyMinutes = 60
    case ninetyMinutes = 90

    var displayName: String {
        "\(rawValue) min"
    }
}

enum PreferredGymTime: String, CaseIterable, Codable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case noPreference = "No Preference"
}

enum PreferredWalkTime: String, CaseIterable, Codable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case noPreference = "No Preference"
}

enum AgeGroup: String, CaseIterable, Codable {
    case under25 = "Under 25"
    case age25to34 = "25-34"
    case age35to44 = "35-44"
    case age45to54 = "45-54"
    case age55plus = "55+"

    var recommendedSteps: Int {
        switch self {
        case .under25: return 10000
        case .age25to34: return 10000
        case .age35to44: return 8000
        case .age45to54: return 7000
        case .age55plus: return 6000
        }
    }

    var recommendedGymFrequency: GymFrequency {
        switch self {
        case .under25, .age25to34: return .fourDays
        case .age35to44: return .threeDays
        case .age45to54, .age55plus: return .threeDays
        }
    }

    var recommendedWorkoutDuration: WorkoutDuration {
        switch self {
        case .under25, .age25to34: return .sixtyMinutes
        case .age35to44: return .fortyFiveMinutes
        case .age45to54, .age55plus: return .thirtyMinutes
        }
    }
}

// MARK: - Time Helper

struct TimeOfDay: Codable, Equatable {
    var hour: Int
    var minute: Int

    var date: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func from(date: Date) -> TimeOfDay {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 7, minute: components.minute ?? 0)
    }

    // Global average defaults
    static let defaultWakeTime = TimeOfDay(hour: 7, minute: 0)      // 7:00 AM
    static let defaultSleepTime = TimeOfDay(hour: 23, minute: 0)    // 11:00 PM
    static let defaultBreakfastTime = TimeOfDay(hour: 8, minute: 0) // 8:00 AM
    static let defaultLunchTime = TimeOfDay(hour: 12, minute: 30)   // 12:30 PM
    static let defaultDinnerTime = TimeOfDay(hour: 19, minute: 0)   // 7:00 PM
}

// MARK: - User Preferences

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    // MARK: - Workout Preferences
    @AppStorage("gymFrequency") var gymFrequencyRaw: Int = 0  // Default to "not set"
    @AppStorage("workoutDuration") var workoutDurationRaw: Int = 45
    @AppStorage("preferredGymTime") var preferredGymTimeRaw: String = "No Preference"
    @AppStorage("preferredWalkTime") var preferredWalkTimeRaw: String = "No Preference"
    @AppStorage("dailyStepGoal") var dailyStepGoal: Int = 10000

    // MARK: - Time Preferences (stored as JSON)
    @AppStorage("wakeTimeHour") private var wakeTimeHour: Int = 7
    @AppStorage("wakeTimeMinute") private var wakeTimeMinute: Int = 0
    @AppStorage("sleepTimeHour") private var sleepTimeHour: Int = 23
    @AppStorage("sleepTimeMinute") private var sleepTimeMinute: Int = 0
    @AppStorage("breakfastTimeHour") private var breakfastTimeHour: Int = 8
    @AppStorage("breakfastTimeMinute") private var breakfastTimeMinute: Int = 0
    @AppStorage("lunchTimeHour") private var lunchTimeHour: Int = 12
    @AppStorage("lunchTimeMinute") private var lunchTimeMinute: Int = 30
    @AppStorage("dinnerTimeHour") private var dinnerTimeHour: Int = 19
    @AppStorage("dinnerTimeMinute") private var dinnerTimeMinute: Int = 0

    // MARK: - User Profile
    @AppStorage("ageGroup") private var ageGroupRaw: String = ""
    @AppStorage("workoutConfigured") var workoutConfigured: Bool = false

    // MARK: - Computed Properties

    var gymFrequency: GymFrequency {
        get { GymFrequency(rawValue: gymFrequencyRaw) ?? .none }
        set {
            gymFrequencyRaw = newValue.rawValue
            if newValue != .none {
                workoutConfigured = true
            }
        }
    }

    var workoutDuration: WorkoutDuration {
        get { WorkoutDuration(rawValue: workoutDurationRaw) ?? .fortyFiveMinutes }
        set { workoutDurationRaw = newValue.rawValue }
    }

    var preferredGymTime: PreferredGymTime {
        get { PreferredGymTime(rawValue: preferredGymTimeRaw) ?? .noPreference }
        set { preferredGymTimeRaw = newValue.rawValue }
    }

    var preferredWalkTime: PreferredWalkTime {
        get { PreferredWalkTime(rawValue: preferredWalkTimeRaw) ?? .noPreference }
        set { preferredWalkTimeRaw = newValue.rawValue }
    }

    var ageGroup: AgeGroup? {
        get { AgeGroup(rawValue: ageGroupRaw) }
        set { ageGroupRaw = newValue?.rawValue ?? "" }
    }

    // Time preferences
    var wakeTime: TimeOfDay {
        get { TimeOfDay(hour: wakeTimeHour, minute: wakeTimeMinute) }
        set {
            wakeTimeHour = newValue.hour
            wakeTimeMinute = newValue.minute
        }
    }

    var sleepTime: TimeOfDay {
        get { TimeOfDay(hour: sleepTimeHour, minute: sleepTimeMinute) }
        set {
            sleepTimeHour = newValue.hour
            sleepTimeMinute = newValue.minute
        }
    }

    var breakfastTime: TimeOfDay {
        get { TimeOfDay(hour: breakfastTimeHour, minute: breakfastTimeMinute) }
        set {
            breakfastTimeHour = newValue.hour
            breakfastTimeMinute = newValue.minute
        }
    }

    var lunchTime: TimeOfDay {
        get { TimeOfDay(hour: lunchTimeHour, minute: lunchTimeMinute) }
        set {
            lunchTimeHour = newValue.hour
            lunchTimeMinute = newValue.minute
        }
    }

    var dinnerTime: TimeOfDay {
        get { TimeOfDay(hour: dinnerTimeHour, minute: dinnerTimeMinute) }
        set {
            dinnerTimeHour = newValue.hour
            dinnerTimeMinute = newValue.minute
        }
    }

    // MARK: - Computed Helpers

    /// Active hours in the day (from wake to sleep)
    var activeHours: Int {
        let wake = wakeTime.hour
        var sleep = sleepTime.hour
        if sleep < wake {
            sleep += 24 // Handle past midnight
        }
        return sleep - wake
    }

    /// Steps to aim for per active hour
    var stepsPerHour: Int {
        guard activeHours > 0 else { return 0 }
        return dailyStepGoal / activeHours
    }

    /// Whether workout is configured (frequency > 0)
    var hasWorkoutGoal: Bool {
        gymFrequency != .none
    }

    // MARK: - Methods

    /// Apply age-based recommendations
    func applyAgeBasedDefaults() {
        guard let age = ageGroup else { return }
        dailyStepGoal = age.recommendedSteps
        gymFrequency = age.recommendedGymFrequency
        workoutDuration = age.recommendedWorkoutDuration
    }

    /// Get meal times as array for blocking walk suggestions
    var mealTimes: [TimeOfDay] {
        [breakfastTime, lunchTime, dinnerTime]
    }

    /// Check if a time is during a meal (within 30 min buffer)
    func isDuringMeal(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        for meal in mealTimes {
            let mealMinutes = meal.hour * 60 + meal.minute
            // 30 minute buffer before and after meal
            if abs(timeMinutes - mealMinutes) < 30 {
                return true
            }
        }
        return false
    }

    /// Check if time is within active hours
    func isWithinActiveHours(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        let wakeHour = wakeTime.hour
        var sleepHour = sleepTime.hour

        // Handle crossing midnight
        if sleepHour < wakeHour {
            return hour >= wakeHour || hour < sleepHour
        }

        return hour >= wakeHour && hour < sleepHour
    }

    /// Check if time is within active hours WITH 1-hour buffer after wake and before sleep
    /// This is for auto-assigned slots - users can still manually schedule in these buffer times
    func isWithinBufferedActiveHours(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        // Wake time + 1 hour buffer
        let wakeMinutes = wakeTime.hour * 60 + wakeTime.minute
        let bufferedWakeMinutes = wakeMinutes + 60 // 1 hour after wake

        // Sleep time - 1 hour buffer
        var sleepMinutes = sleepTime.hour * 60 + sleepTime.minute
        if sleepMinutes < wakeMinutes {
            sleepMinutes += 24 * 60 // Handle crossing midnight
        }
        let bufferedSleepMinutes = sleepMinutes - 60 // 1 hour before sleep

        // Adjust time if crossing midnight
        var adjustedTimeMinutes = timeMinutes
        if sleepTime.hour < wakeTime.hour && hour < wakeTime.hour {
            adjustedTimeMinutes += 24 * 60
        }

        return adjustedTimeMinutes >= bufferedWakeMinutes && adjustedTimeMinutes < bufferedSleepMinutes
    }

    /// Check if time is in the wake-up buffer zone (first hour after waking)
    func isInWakeUpBuffer(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        let wakeMinutes = wakeTime.hour * 60 + wakeTime.minute
        let bufferEndMinutes = wakeMinutes + 60

        return timeMinutes >= wakeMinutes && timeMinutes < bufferEndMinutes
    }

    /// Check if time is in the sleep buffer zone (hour before sleep)
    func isInSleepBuffer(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        var sleepMinutes = sleepTime.hour * 60 + sleepTime.minute
        if sleepMinutes < wakeTime.hour * 60 {
            sleepMinutes += 24 * 60
        }
        let bufferStartMinutes = sleepMinutes - 60

        var adjustedTimeMinutes = timeMinutes
        if sleepTime.hour < wakeTime.hour && hour < wakeTime.hour {
            adjustedTimeMinutes += 24 * 60
        }

        return adjustedTimeMinutes >= bufferStartMinutes && adjustedTimeMinutes < sleepMinutes
    }

    private init() {}
}
