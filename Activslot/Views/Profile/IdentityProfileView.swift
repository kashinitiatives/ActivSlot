import SwiftUI

// MARK: - Identity Profile View

struct IdentityProfileView: View {
    @EnvironmentObject var userPreferences: UserPreferences

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Identity Card
                IdentityCard(
                    level: userPreferences.identityLevel,
                    totalActivities: userPreferences.totalWalksCompleted + userPreferences.totalWorkoutsCompleted,
                    currentStreak: userPreferences.currentStreak
                )

                // Stats Grid
                StatsGridView(
                    walks: userPreferences.totalWalksCompleted,
                    workouts: userPreferences.totalWorkoutsCompleted,
                    currentStreak: userPreferences.currentStreak,
                    longestStreak: userPreferences.longestStreak
                )

                // Progress to Next Level
                if let nextLevel = userPreferences.identityLevel.nextLevel {
                    ProgressToNextLevelView(
                        currentLevel: userPreferences.identityLevel,
                        nextLevel: nextLevel,
                        currentActivities: userPreferences.totalWalksCompleted + userPreferences.totalWorkoutsCompleted
                    )
                }

                // Personal Why
                if let why = userPreferences.personalWhy {
                    PersonalWhyCard(why: why, customReason: userPreferences.personalWhyCustom)
                }

                // Journey Timeline
                JourneyMilestonesView(
                    currentLevel: userPreferences.identityLevel,
                    totalActivities: userPreferences.totalWalksCompleted + userPreferences.totalWorkoutsCompleted
                )
            }
            .padding()
        }
        .navigationTitle("Your Journey")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Identity Card

struct IdentityCard: View {
    let level: IdentityLevel
    let totalActivities: Int
    let currentStreak: Int

    var body: some View {
        VStack(spacing: 16) {
            // Level Icon
            ZStack {
                Circle()
                    .fill(levelGradient)
                    .frame(width: 100, height: 100)

                Image(systemName: level.icon)
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }
            .shadow(color: levelColor.opacity(0.4), radius: 10, y: 5)

            // Title
            Text(level.title)
                .font(.title)
                .fontWeight(.bold)

            Text(level.description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Quick Stats
            HStack(spacing: 32) {
                VStack {
                    Text("\(totalActivities)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Activities")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                VStack {
                    HStack(spacing: 4) {
                        Text("\(currentStreak)")
                            .font(.title2)
                            .fontWeight(.bold)
                        if currentStreak > 0 {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    Text("Day Streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var levelColor: Color {
        switch level {
        case .newcomer: return .green
        case .beginner: return .blue
        case .explorer: return .purple
        case .committed: return .orange
        case .champion: return .red
        case .master: return .indigo
        case .legend: return .yellow
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [levelColor, levelColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Stats Grid

struct StatsGridView: View {
    let walks: Int
    let workouts: Int
    let currentStreak: Int
    let longestStreak: Int

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatCard(icon: "figure.walk", title: "Walks", value: "\(walks)", color: .green)
            StatCard(icon: "dumbbell.fill", title: "Workouts", value: "\(workouts)", color: .blue)
            StatCard(icon: "flame.fill", title: "Current Streak", value: "\(currentStreak) days", color: .orange)
            StatCard(icon: "trophy.fill", title: "Best Streak", value: "\(longestStreak) days", color: .yellow)
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Progress to Next Level

struct ProgressToNextLevelView: View {
    let currentLevel: IdentityLevel
    let nextLevel: IdentityLevel
    let currentActivities: Int

    private var progress: Double {
        let current = currentActivities - currentLevel.activitiesRequired
        let needed = nextLevel.activitiesRequired - currentLevel.activitiesRequired
        return min(1.0, Double(current) / Double(needed))
    }

    private var activitiesRemaining: Int {
        nextLevel.activitiesRequired - currentActivities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next: \(nextLevel.title)")
                    .font(.headline)

                Spacer()

                Text("\(activitiesRemaining) to go")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 12)
                }
            }
            .frame(height: 12)

            // Level icons
            HStack {
                Image(systemName: currentLevel.icon)
                    .foregroundColor(.blue)

                Spacer()

                Image(systemName: nextLevel.icon)
                    .foregroundColor(.gray)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Personal Why Card

struct PersonalWhyCard: View {
    let why: PersonalWhy
    let customReason: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: why.icon)
                .font(.title)
                .foregroundColor(.blue)
                .frame(width: 50, height: 50)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Why")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(why == .custom ? customReason : why.displayName)
                    .font(.headline)

                Text(why == .custom ? "Your personal motivation" : why.motivationalMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Journey Milestones

struct JourneyMilestonesView: View {
    let currentLevel: IdentityLevel
    let totalActivities: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Journey")
                .font(.headline)

            ForEach(IdentityLevel.allCases, id: \.self) { level in
                MilestoneRow(
                    level: level,
                    isAchieved: totalActivities >= level.activitiesRequired,
                    isCurrent: level == currentLevel
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MilestoneRow: View {
    let level: IdentityLevel
    let isAchieved: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Milestone indicator
            ZStack {
                Circle()
                    .fill(isAchieved ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                if isAchieved {
                    Image(systemName: level.icon)
                        .font(.caption)
                        .foregroundColor(.white)
                } else {
                    Image(systemName: level.icon)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .bold : .regular)
                    .foregroundColor(isAchieved ? .primary : .secondary)

                Text("\(level.activitiesRequired) activities")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isCurrent {
                Text("Current")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(8)
            } else if isAchieved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IdentityProfileView()
            .environmentObject(UserPreferences.shared)
    }
}
