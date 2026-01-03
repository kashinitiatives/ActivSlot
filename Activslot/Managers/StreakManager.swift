import Foundation
import SwiftUI

/// Manages step goal streaks - consecutive days of hitting daily step goal
class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var lastGoalDate: Date?

    // UserDefaults keys
    private let currentStreakKey = "streak_current"
    private let longestStreakKey = "streak_longest"
    private let lastGoalDateKey = "streak_lastGoalDate"
    private let streakHistoryKey = "streak_history"

    private init() {
        loadStreakData()
    }

    // MARK: - Public Methods

    /// Call this when user hits their step goal for today
    func recordGoalHit() {
        let today = Calendar.current.startOfDay(for: Date())

        // Check if already recorded today
        if let lastDate = lastGoalDate, Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return // Already recorded for today
        }

        // Check if this continues a streak or starts a new one
        if let lastDate = lastGoalDate,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) {
            if Calendar.current.isDate(lastDate, inSameDayAs: yesterday) {
                // Continuing streak
                currentStreak += 1
            } else {
                // Streak broken, start new one
                currentStreak = 1
            }
        } else {
            // First goal ever
            currentStreak = 1
        }

        // Update longest streak if needed
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }

        lastGoalDate = today
        saveStreakData()
    }

    /// Check if streak is still valid (called on app launch)
    func validateStreak() {
        guard let lastDate = lastGoalDate else { return }

        let today = Calendar.current.startOfDay(for: Date())
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else { return }

        // If last goal was not today or yesterday, streak is broken
        if !Calendar.current.isDate(lastDate, inSameDayAs: today) &&
           !Calendar.current.isDate(lastDate, inSameDayAs: yesterday) {
            currentStreak = 0
            saveStreakData()
        }
    }

    /// Calculate streak asynchronously from HealthKit data
    func calculateStreakFromHistory(healthKitManager: HealthKitManager, goalSteps: Int) async {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Check backwards from today
        for _ in 0..<365 { // Max 1 year lookback
            do {
                let steps = try await healthKitManager.fetchSteps(for: checkDate)
                if steps >= goalSteps {
                    streak += 1
                    guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                        break
                    }
                    checkDate = previousDay
                } else {
                    break
                }
            } catch {
                break
            }
        }

        await MainActor.run {
            self.currentStreak = streak
            if streak > self.longestStreak {
                self.longestStreak = streak
            }
            self.saveStreakData()
        }
    }

    // MARK: - Persistence

    private func loadStreakData() {
        currentStreak = UserDefaults.standard.integer(forKey: currentStreakKey)
        longestStreak = UserDefaults.standard.integer(forKey: longestStreakKey)

        if let dateData = UserDefaults.standard.data(forKey: lastGoalDateKey),
           let date = try? JSONDecoder().decode(Date.self, from: dateData) {
            lastGoalDate = date
        }

        validateStreak()
    }

    private func saveStreakData() {
        UserDefaults.standard.set(currentStreak, forKey: currentStreakKey)
        UserDefaults.standard.set(longestStreak, forKey: longestStreakKey)

        if let date = lastGoalDate,
           let dateData = try? JSONEncoder().encode(date) {
            UserDefaults.standard.set(dateData, forKey: lastGoalDateKey)
        }
    }
}

// MARK: - Streak Card View

struct StreakCard: View {
    @ObservedObject var streakManager: StreakManager
    let currentSteps: Int
    let goalSteps: Int

    private var goalReachedToday: Bool {
        currentSteps >= goalSteps
    }

    /// Display streak including today if goal is reached
    private var displayStreak: Int {
        // If goal reached today and streak hasn't been updated yet, show +1
        if goalReachedToday && !streakRecordedToday {
            return streakManager.currentStreak + 1
        }
        return streakManager.currentStreak
    }

    private var streakRecordedToday: Bool {
        guard let lastDate = streakManager.lastGoalDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Streak flame icon
            ZStack {
                Circle()
                    .fill(displayStreakColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: goalReachedToday ? "flame.fill" : "flame")
                    .font(.title2)
                    .foregroundColor(displayStreakColor)
                    .symbolEffect(.bounce, value: displayStreak)
            }

            // Streak info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(displayStreak)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(displayStreakColor)
                        .contentTransition(.numericText())

                    Text(displayStreak == 1 ? "day streak" : "day streak")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if goalReachedToday {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Goal hit today!")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
                } else if streakManager.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Hit your goal to keep it going!")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                } else {
                    Text("Hit your goal to start a streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Longest streak badge
            if streakManager.longestStreak > 0 {
                VStack(spacing: 2) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text("Best: \(streakManager.longestStreak)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            // Record streak if goal is already met when view loads
            if currentSteps >= goalSteps {
                streakManager.recordGoalHit()
            }
        }
        .onChange(of: currentSteps) { _, newSteps in
            if newSteps >= goalSteps {
                streakManager.recordGoalHit()
            }
        }
    }

    private var displayStreakColor: Color {
        let streak = displayStreak
        if streak >= 30 {
            return .purple
        } else if streak >= 14 {
            return .red
        } else if streak >= 7 {
            return .orange
        } else if streak >= 3 {
            return .yellow
        } else if streak >= 1 {
            return .green
        } else {
            return .gray
        }
    }
}

// MARK: - Compact Streak Badge

struct StreakBadge: View {
    let streak: Int

    var body: some View {
        if streak > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundColor(streakColor)

                Text("\(streak)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(streakColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(streakColor.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private var streakColor: Color {
        if streak >= 30 {
            return .purple
        } else if streak >= 14 {
            return .red
        } else if streak >= 7 {
            return .orange
        } else if streak >= 3 {
            return .yellow
        } else {
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StreakCard(
            streakManager: StreakManager.shared,
            currentSteps: 8500,
            goalSteps: 10000
        )

        StreakBadge(streak: 7)
        StreakBadge(streak: 14)
        StreakBadge(streak: 30)
    }
    .padding()
}
