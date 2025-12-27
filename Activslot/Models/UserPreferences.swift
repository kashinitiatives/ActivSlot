import Foundation
import SwiftUI

// MARK: - Enums

// MARK: Autopilot Trust Level
enum AutopilotTrustLevel: String, CaseIterable, Codable {
    case fullAuto = "fullAuto"           // Schedule without asking
    case confirmFirst = "confirmFirst"    // Send notification to approve
    case suggestOnly = "suggestOnly"      // Just show in app, don't create events

    var displayName: String {
        switch self {
        case .fullAuto: return "Full Autopilot"
        case .confirmFirst: return "Ask Me First"
        case .suggestOnly: return "Suggest Only"
        }
    }

    var description: String {
        switch self {
        case .fullAuto: return "Walks appear on your calendar automatically"
        case .confirmFirst: return "Get a notification to approve each walk"
        case .suggestOnly: return "See suggestions in app, schedule manually"
        }
    }

    var icon: String {
        switch self {
        case .fullAuto: return "bolt.fill"
        case .confirmFirst: return "bell.badge.fill"
        case .suggestOnly: return "lightbulb.fill"
        }
    }
}

// MARK: Personal Why (Motivation Anchors)
enum PersonalWhy: String, CaseIterable, Codable {
    case energy = "energy"               // More energy throughout the day
    case longevity = "longevity"         // Live longer, healthier
    case mentalClarity = "mentalClarity" // Better focus and thinking
    case stressRelief = "stressRelief"   // Reduce stress and anxiety
    case familyTime = "familyTime"       // Be active for family
    case backPain = "backPain"           // Reduce back/body pain
    case weightManagement = "weight"     // Manage weight
    case sleepBetter = "sleep"           // Sleep better at night
    case custom = "custom"               // Custom reason

    var displayName: String {
        switch self {
        case .energy: return "More Energy"
        case .longevity: return "Live Longer"
        case .mentalClarity: return "Mental Clarity"
        case .stressRelief: return "Stress Relief"
        case .familyTime: return "Family Time"
        case .backPain: return "Reduce Pain"
        case .weightManagement: return "Weight Management"
        case .sleepBetter: return "Better Sleep"
        case .custom: return "My Own Reason"
        }
    }

    var icon: String {
        switch self {
        case .energy: return "bolt.fill"
        case .longevity: return "heart.fill"
        case .mentalClarity: return "brain.head.profile"
        case .stressRelief: return "leaf.fill"
        case .familyTime: return "figure.2.and.child.holdinghands"
        case .backPain: return "figure.stand"
        case .weightManagement: return "scalemass.fill"
        case .sleepBetter: return "moon.zzz.fill"
        case .custom: return "star.fill"
        }
    }

    var motivationalMessage: String {
        switch self {
        case .energy: return "This walk = more energy for your afternoon"
        case .longevity: return "Every walk adds minutes to your life"
        case .mentalClarity: return "Walking boosts focus for your next meeting"
        case .stressRelief: return "A quick walk melts away stress"
        case .familyTime: return "Stay active for the ones you love"
        case .backPain: return "Movement is medicine for your body"
        case .weightManagement: return "Every step counts toward your goal"
        case .sleepBetter: return "Today's walks = tonight's better sleep"
        case .custom: return "You've got this!"
        }
    }
}

// MARK: Identity Levels
enum IdentityLevel: Int, CaseIterable, Codable {
    case newcomer = 0      // 0-4 activities
    case beginner = 1      // 5-19 activities
    case explorer = 2      // 20-49 activities
    case committed = 3     // 50-99 activities
    case champion = 4      // 100-199 activities
    case master = 5        // 200-499 activities
    case legend = 6        // 500+ activities

    var title: String {
        switch self {
        case .newcomer: return "Newcomer"
        case .beginner: return "Beginner Mover"
        case .explorer: return "Active Explorer"
        case .committed: return "Committed Walker"
        case .champion: return "Movement Champion"
        case .master: return "Fitness Master"
        case .legend: return "Walking Legend"
        }
    }

    var description: String {
        switch self {
        case .newcomer: return "Starting your journey"
        case .beginner: return "Building the habit"
        case .explorer: return "Finding your rhythm"
        case .committed: return "Movement is part of you"
        case .champion: return "Inspiring others"
        case .master: return "Leading by example"
        case .legend: return "A true role model"
        }
    }

    var icon: String {
        switch self {
        case .newcomer: return "leaf.fill"
        case .beginner: return "figure.walk"
        case .explorer: return "figure.run"
        case .committed: return "flame.fill"
        case .champion: return "trophy.fill"
        case .master: return "crown.fill"
        case .legend: return "star.circle.fill"
        }
    }

    var nextLevel: IdentityLevel? {
        switch self {
        case .newcomer: return .beginner
        case .beginner: return .explorer
        case .explorer: return .committed
        case .committed: return .champion
        case .champion: return .master
        case .master: return .legend
        case .legend: return nil
        }
    }

    var activitiesRequired: Int {
        switch self {
        case .newcomer: return 0
        case .beginner: return 5
        case .explorer: return 20
        case .committed: return 50
        case .champion: return 100
        case .master: return 200
        case .legend: return 500
        }
    }
}

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
    @AppStorage("preferredGymTime") var preferredGymTimeRaw: String = "Morning"
    @AppStorage("preferredWalkTime") var preferredWalkTimeRaw: String = "Morning"
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

    // MARK: - Auto Walk Mode
    @AppStorage("autoWalkEnabled") var autoWalkEnabled: Bool = false
    @AppStorage("autoWalkDuration") var autoWalkDuration: Int = 60 // minutes
    @AppStorage("autoWalkPreferredTime") var autoWalkPreferredTimeRaw: String = "Morning"
    @AppStorage("autoWalkSyncToCalendar") var autoWalkSyncToCalendar: Bool = true
    @AppStorage("autoWalkCalendarID") var autoWalkCalendarID: String = ""

    var autoWalkPreferredTime: PreferredWalkTime {
        get { PreferredWalkTime(rawValue: autoWalkPreferredTimeRaw) ?? .morning }
        set { autoWalkPreferredTimeRaw = newValue.rawValue }
    }

    // MARK: - Full Autopilot Mode
    @AppStorage("autopilotEnabled") var autopilotEnabled: Bool = false
    @AppStorage("autopilotTrustLevel") var autopilotTrustLevelRaw: String = "confirmFirst"
    @AppStorage("autopilotWalksPerDay") var autopilotWalksPerDay: Int = 2
    @AppStorage("autopilotMinWalkDuration") var autopilotMinWalkDuration: Int = 5  // Micro walks
    @AppStorage("autopilotMaxWalkDuration") var autopilotMaxWalkDuration: Int = 30
    @AppStorage("autopilotIncludeMicroWalks") var autopilotIncludeMicroWalks: Bool = true
    @AppStorage("autopilotCalendarID") var autopilotCalendarID: String = ""

    var autopilotTrustLevel: AutopilotTrustLevel {
        get { AutopilotTrustLevel(rawValue: autopilotTrustLevelRaw) ?? .confirmFirst }
        set { autopilotTrustLevelRaw = newValue.rawValue }
    }

    // MARK: - Personal Why (Motivation)
    @AppStorage("personalWhyRaw") var personalWhyRaw: String = ""
    @AppStorage("personalWhyCustom") var personalWhyCustom: String = ""

    var personalWhy: PersonalWhy? {
        get { PersonalWhy(rawValue: personalWhyRaw) }
        set { personalWhyRaw = newValue?.rawValue ?? "" }
    }

    // MARK: - Identity & Progression
    @AppStorage("totalWalksCompleted") var totalWalksCompleted: Int = 0
    @AppStorage("totalWorkoutsCompleted") var totalWorkoutsCompleted: Int = 0
    @AppStorage("currentStreak") var currentStreak: Int = 0
    @AppStorage("longestStreak") var longestStreak: Int = 0
    @AppStorage("lastActivityDateString") var lastActivityDateString: String = ""
    @AppStorage("identityLevel") var identityLevelRaw: Int = 0

    var identityLevel: IdentityLevel {
        IdentityLevel(rawValue: identityLevelRaw) ?? .newcomer
    }

    func recordActivityCompleted(isWalk: Bool) {
        let today = formatDateString(Date())

        if isWalk {
            totalWalksCompleted += 1
        } else {
            totalWorkoutsCompleted += 1
        }

        // Update streak
        if lastActivityDateString == formatDateString(Calendar.current.date(byAdding: .day, value: -1, to: Date())!) {
            // Continued streak
            currentStreak += 1
        } else if lastActivityDateString != today {
            // Streak broken or first activity
            currentStreak = 1
        }

        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }

        lastActivityDateString = today

        // Update identity level
        updateIdentityLevel()
    }

    private func updateIdentityLevel() {
        let total = totalWalksCompleted + totalWorkoutsCompleted
        if total >= 500 {
            identityLevelRaw = IdentityLevel.legend.rawValue
        } else if total >= 200 {
            identityLevelRaw = IdentityLevel.master.rawValue
        } else if total >= 100 {
            identityLevelRaw = IdentityLevel.champion.rawValue
        } else if total >= 50 {
            identityLevelRaw = IdentityLevel.committed.rawValue
        } else if total >= 20 {
            identityLevelRaw = IdentityLevel.explorer.rawValue
        } else if total >= 5 {
            identityLevelRaw = IdentityLevel.beginner.rawValue
        } else {
            identityLevelRaw = IdentityLevel.newcomer.rawValue
        }
    }

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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
