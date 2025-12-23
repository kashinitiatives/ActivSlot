import Foundation
import HealthKit
import SwiftUI

// MARK: - Data Models

struct DayPattern: Identifiable {
    let id = UUID()
    let weekday: Int // 1 = Sunday, 2 = Monday, etc.
    let weekdayName: String
    let averageSteps: Int
    let workoutCount: Int
    let goalAchievementRate: Double // % of days goal was hit
    let totalDaysAnalyzed: Int
    let bestSteps: Int
    let bestDate: Date?
}

struct BestDayRecord: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
    let workoutDuration: Int // minutes
    let activeCalories: Double
    let weekday: Int
    let goalAchieved: Bool

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var weeksAgo: Int {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: date, to: Date()).weekOfYear ?? 0
        return weeks
    }
}

struct TodayInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let title: String
    let subtitle: String
    let value: String
    let trend: Trend
    let icon: String
    let color: Color

    enum InsightType {
        case streak
        case pattern
        case comparison
        case achievement
        case motivation
    }

    enum Trend {
        case up, down, neutral

        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .secondary
            }
        }
    }
}

struct ReplicableDayPlan {
    let bestDay: BestDayRecord
    let canReplicate: Bool
    let blockers: [String]
    let adjustedPlan: String?
    let confidence: Double // 0-1, how likely to replicate
}

// MARK: - Personal Insights Manager

class PersonalInsightsManager: ObservableObject {
    static let shared = PersonalInsightsManager()

    private let healthStore = HKHealthStore()
    private let userPreferences = UserPreferences.shared
    private let calendar = Calendar.current

    @Published var todayInsights: [TodayInsight] = []
    @Published var currentDayPattern: DayPattern?
    @Published var bestRecentDay: BestDayRecord?
    @Published var weekdayPatterns: [DayPattern] = []
    @Published var replicablePlan: ReplicableDayPlan?
    @Published var isLoading = false

    // Cached data
    @AppStorage("workoutStreakDays") private var workoutStreakDays: Int = 0
    @AppStorage("stepStreakDays") private var stepStreakDays: Int = 0
    @AppStorage("lastAnalysisDate") private var lastAnalysisDateTimestamp: Double = 0

    private init() {}

    // MARK: - Main Analysis

    @MainActor
    func analyzePatterns() async {
        isLoading = true
        defer { isLoading = false }

        // Get current weekday
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)

        // Run all analyses in parallel
        async let patternsTask = analyzeWeekdayPatterns()
        async let bestDayTask = findBestRecentDayForWeekday(weekday)
        async let insightsTask = generateTodayInsights(weekday: weekday)

        weekdayPatterns = await patternsTask
        currentDayPattern = weekdayPatterns.first { $0.weekday == weekday }
        bestRecentDay = await bestDayTask
        todayInsights = await insightsTask

        // Check if best day can be replicated
        if let bestDay = bestRecentDay {
            replicablePlan = await checkReplicability(of: bestDay)
        }
    }

    // MARK: - Weekday Pattern Analysis

    private func analyzeWeekdayPatterns() async -> [DayPattern] {
        var patterns: [DayPattern] = []
        let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

        for weekday in 1...7 {
            let pattern = await analyzeWeekday(weekday, name: weekdayNames[weekday])
            patterns.append(pattern)
        }

        return patterns
    }

    private func analyzeWeekday(_ weekday: Int, name: String) async -> DayPattern {
        // Get all days of this weekday in the past 12 weeks
        let dates = getDatesForWeekday(weekday, weeks: 12)

        var totalSteps = 0
        var workoutCount = 0
        var goalHitCount = 0
        var bestSteps = 0
        var bestDate: Date?

        for date in dates {
            // Fetch steps
            if let steps = try? await fetchSteps(for: date) {
                totalSteps += steps
                if steps > bestSteps {
                    bestSteps = steps
                    bestDate = date
                }
                if steps >= userPreferences.dailyStepGoal {
                    goalHitCount += 1
                }
            }

            // Fetch workouts
            if let workouts = try? await fetchWorkouts(for: date), !workouts.isEmpty {
                workoutCount += 1
            }
        }

        let daysAnalyzed = dates.count
        let avgSteps = daysAnalyzed > 0 ? totalSteps / daysAnalyzed : 0
        let goalRate = daysAnalyzed > 0 ? Double(goalHitCount) / Double(daysAnalyzed) : 0

        return DayPattern(
            weekday: weekday,
            weekdayName: name,
            averageSteps: avgSteps,
            workoutCount: workoutCount,
            goalAchievementRate: goalRate,
            totalDaysAnalyzed: daysAnalyzed,
            bestSteps: bestSteps,
            bestDate: bestDate
        )
    }

    // MARK: - Best Day Analysis

    private func findBestRecentDayForWeekday(_ weekday: Int) async -> BestDayRecord? {
        let dates = getDatesForWeekday(weekday, weeks: 8)

        var bestRecord: BestDayRecord?
        var bestScore = 0.0

        for date in dates {
            guard let steps = try? await fetchSteps(for: date) else { continue }
            let workouts = (try? await fetchWorkouts(for: date)) ?? []
            let workoutMinutes = workouts.reduce(0) { $0 + Int($1.duration / 60) }
            let calories = (try? await fetchActiveCalories(for: date)) ?? 0

            // Score: steps + workout bonus
            let goalMet = steps >= userPreferences.dailyStepGoal
            let workoutBonus = workoutMinutes > 0 ? 5000 : 0
            let score = Double(steps) + Double(workoutBonus) + (goalMet ? 3000 : 0)

            if score > bestScore {
                bestScore = score
                bestRecord = BestDayRecord(
                    date: date,
                    steps: steps,
                    workoutDuration: workoutMinutes,
                    activeCalories: calories,
                    weekday: weekday,
                    goalAchieved: goalMet && workoutMinutes > 0
                )
            }
        }

        return bestRecord
    }

    // MARK: - Today's Insights

    private func generateTodayInsights(weekday: Int) async -> [TodayInsight] {
        var insights: [TodayInsight] = []
        let weekdayName = getWeekdayName(weekday)

        // 1. This day pattern insight
        if let pattern = weekdayPatterns.first(where: { $0.weekday == weekday }) {
            let goalPercent = Int(pattern.goalAchievementRate * 100)
            insights.append(TodayInsight(
                type: .pattern,
                title: "Your \(weekdayName) Pattern",
                subtitle: "Based on last 12 weeks",
                value: "\(pattern.averageSteps.formatted()) avg steps",
                trend: pattern.averageSteps >= userPreferences.dailyStepGoal ? .up : .down,
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            ))

            if pattern.workoutCount > 0 {
                insights.append(TodayInsight(
                    type: .pattern,
                    title: "\(weekdayName) Workouts",
                    subtitle: "This year",
                    value: "\(pattern.workoutCount) workouts",
                    trend: .neutral,
                    icon: "dumbbell.fill",
                    color: .orange
                ))
            }

            insights.append(TodayInsight(
                type: .achievement,
                title: "Goal Achievement",
                subtitle: "On \(weekdayName)s",
                value: "\(goalPercent)% success rate",
                trend: goalPercent >= 50 ? .up : .down,
                icon: "target",
                color: goalPercent >= 50 ? .green : .orange
            ))
        }

        // 2. Best day motivation
        if let bestDay = bestRecentDay {
            let weeksAgo = bestDay.weeksAgo
            insights.append(TodayInsight(
                type: .motivation,
                title: "Your Best \(weekdayName)",
                subtitle: weeksAgo == 0 ? "This week!" : "\(weeksAgo) weeks ago",
                value: "\(bestDay.steps.formatted()) steps",
                trend: .up,
                icon: "trophy.fill",
                color: .yellow
            ))
        }

        // 3. Streak info
        let stepStreak = await calculateStepStreak()
        if stepStreak > 1 {
            insights.append(TodayInsight(
                type: .streak,
                title: "Step Goal Streak",
                subtitle: "Keep it going!",
                value: "\(stepStreak) days",
                trend: .up,
                icon: "flame.fill",
                color: .red
            ))
        }

        // 4. Comparison to last week same day
        if let lastWeekSteps = try? await fetchSteps(for: calendar.date(byAdding: .day, value: -7, to: Date())!) {
            let currentSteps = (try? await fetchTodaySteps()) ?? 0
            let comparison = currentSteps - lastWeekSteps
            insights.append(TodayInsight(
                type: .comparison,
                title: "vs Last \(weekdayName)",
                subtitle: "Same time comparison",
                value: comparison >= 0 ? "+\(comparison.formatted())" : "\(comparison.formatted())",
                trend: comparison >= 0 ? .up : .down,
                icon: "arrow.left.arrow.right",
                color: comparison >= 0 ? .green : .orange
            ))
        }

        return insights
    }

    // MARK: - Replicability Check

    private func checkReplicability(of bestDay: BestDayRecord) async -> ReplicableDayPlan {
        var blockers: [String] = []
        var opportunities: [String] = []
        var confidence = 1.0

        // Check calendar for today
        let calendarManager = CalendarManager.shared
        let todayEvents = (try? await calendarManager.fetchEvents(for: Date())) ?? []
        // Filter out all-day events and out-of-office events - only count real meetings
        let realMeetings = todayEvents.filter { $0.isRealMeeting }
        let meetingMinutes = realMeetings.reduce(0) { $0 + $1.duration }

        // If heavy meeting day, reduce confidence
        if meetingMinutes > 360 { // > 6 hours
            blockers.append("Heavy meeting day (\(meetingMinutes/60)h of meetings)")
            confidence -= 0.3
        } else if meetingMinutes < 120 { // < 2 hours - light day is an opportunity!
            opportunities.append("Light meeting day - more time for walks!")
            confidence += 0.1
        }

        // Check if workout time is available
        let workoutDuration = userPreferences.workoutDuration.rawValue
        let freeSlots = (try? await calendarManager.findFreeSlots(for: Date(), minimumDuration: workoutDuration)) ?? []

        if freeSlots.isEmpty && bestDay.workoutDuration > 0 {
            blockers.append("No \(workoutDuration)+ min free slot for workout")
            confidence -= 0.3
        } else if freeSlots.count >= 3 {
            // Multiple free slots is great - not a blocker
            opportunities.append("Multiple workout slots available")
            confidence += 0.1
        }

        // Check walkable meetings - fewer meetings is actually good for dedicated walks
        // Use realMeetings to exclude all-day/OOO events from this calculation too
        let walkableMeetings = realMeetings.filter { $0.isWalkable }
        let walkableSteps = walkableMeetings.reduce(0) { $0 + $1.estimatedSteps }

        // Only flag as a blocker if we have many real meetings but none are walkable
        if realMeetings.count > 5 && walkableMeetings.isEmpty {
            blockers.append("Busy day with no walkable meetings")
            confidence -= 0.2
        } else if realMeetings.count <= 3 {
            // Few meetings means more free time for dedicated walks - this is positive!
            opportunities.append("Free calendar - schedule dedicated walk breaks")
        }

        // Generate adjusted plan
        var adjustedPlan: String? = nil
        if !blockers.isEmpty {
            adjustedPlan = generateAdjustedPlan(bestDay: bestDay, meetingMinutes: meetingMinutes, walkableSteps: walkableSteps, freeSlots: freeSlots)
        } else if !opportunities.isEmpty {
            // Even with no blockers, suggest how to use the opportunities
            adjustedPlan = generateOpportunityPlan(bestDay: bestDay, opportunities: opportunities, freeSlots: freeSlots)
        }

        return ReplicableDayPlan(
            bestDay: bestDay,
            canReplicate: blockers.isEmpty,
            blockers: blockers,
            adjustedPlan: adjustedPlan,
            confidence: min(1.0, max(0, confidence))
        )
    }

    private func generateAdjustedPlan(bestDay: BestDayRecord, meetingMinutes: Int, walkableSteps: Int, freeSlots: [DateInterval]) -> String {
        let stepsNeeded = bestDay.steps - walkableSteps
        let additionalWalkMinutes = stepsNeeded / 100 // ~100 steps/min

        if meetingMinutes > 360 {
            return "Take walking breaks between meetings to hit \(bestDay.steps.formatted()) steps"
        } else if additionalWalkMinutes > 30 {
            // Suggest using early free slots
            if let earliestSlot = freeSlots.first {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "Start with a \(additionalWalkMinutes) min walk at \(formatter.string(from: earliestSlot.start))"
            }
            return "Add a \(additionalWalkMinutes) min walk to match your best"
        } else {
            return "Stay active and you can match your best \(getWeekdayName(bestDay.weekday))!"
        }
    }

    private func generateOpportunityPlan(bestDay: BestDayRecord, opportunities: [String], freeSlots: [DateInterval]) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        // Light day - suggest using free time effectively
        if freeSlots.count >= 2 {
            let firstSlot = freeSlots[0]
            let walkTime = formatter.string(from: firstSlot.start)

            // Check workout preference
            if userPreferences.hasWorkoutGoal {
                if userPreferences.preferredGymTime == .evening || userPreferences.preferredGymTime == .afternoon {
                    // Find an afternoon/evening slot for workout
                    let afternoonSlot = freeSlots.first { interval in
                        let hour = calendar.component(.hour, from: interval.start)
                        return hour >= 14 // 2 PM or later
                    }
                    if let workoutSlot = afternoonSlot {
                        return "Walk at \(walkTime), workout at \(formatter.string(from: workoutSlot.start))"
                    }
                } else if userPreferences.preferredGymTime == .morning {
                    // Morning workout, afternoon walk
                    return "Workout at \(walkTime), walk in the afternoon"
                }
            }

            return "Great day! Start with a walk at \(walkTime)"
        } else if let slot = freeSlots.first {
            return "Use your free time at \(formatter.string(from: slot.start)) for activity"
        }

        return "Light day ahead - perfect for hitting your goals!"
    }

    // MARK: - Helper Methods

    private func getDatesForWeekday(_ weekday: Int, weeks: Int) -> [Date] {
        var dates: [Date] = []
        var currentDate = Date()

        // Go back to find the most recent occurrence of this weekday
        while calendar.component(.weekday, from: currentDate) != weekday {
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        // Collect dates going back
        for _ in 0..<weeks {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: -7, to: currentDate)!
        }

        return dates
    }

    private func getWeekdayName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[weekday]
    }

    private func calculateStepStreak() async -> Int {
        var streak = 0
        var date = calendar.date(byAdding: .day, value: -1, to: Date())!

        while streak < 365 { // Max 1 year
            if let steps = try? await fetchSteps(for: date) {
                if steps >= userPreferences.dailyStepGoal {
                    streak += 1
                    date = calendar.date(byAdding: .day, value: -1, to: date)!
                } else {
                    break
                }
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - HealthKit Queries

    private func fetchSteps(for date: Date) async throws -> Int {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodaySteps() async throws -> Int {
        try await fetchSteps(for: Date())
    }

    private func fetchWorkouts(for date: Date) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 10, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveCalories(for date: Date) async throws -> Double {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let energy = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: energy)
            }
            healthStore.execute(query)
        }
    }
}
