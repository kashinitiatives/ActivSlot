import SwiftUI

struct PreferencesView: View {
    let onFinish: () -> Void

    @EnvironmentObject var userPreferences: UserPreferences

    @State private var selectedFrequency: GymFrequency = .threeDays
    @State private var selectedDuration: WorkoutDuration = .fortyFiveMinutes
    @State private var selectedTime: PreferredGymTime = .noPreference

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 32)

            // Title
            Text("Your Preferences")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 8)

            Text("Help us personalize your movement plan")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)

            // Preferences
            VStack(spacing: 24) {
                // Gym frequency
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gym frequency")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(GymFrequency.allCases, id: \.self) { frequency in
                            SelectableChip(
                                title: frequency.displayName,
                                isSelected: selectedFrequency == frequency
                            ) {
                                selectedFrequency = frequency
                            }
                        }
                    }
                }

                // Workout duration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Workout duration")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(WorkoutDuration.allCases, id: \.self) { duration in
                            SelectableChip(
                                title: duration.displayName,
                                isSelected: selectedDuration == duration
                            ) {
                                selectedDuration = duration
                            }
                        }
                    }
                }

                // Preferred gym time
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferred gym time")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(PreferredGymTime.allCases, id: \.self) { time in
                            SelectableChip(
                                title: time.rawValue,
                                isSelected: selectedTime == time
                            ) {
                                selectedTime = time
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // CTA Button
            Button(action: saveAndFinish) {
                Text("Finish Setup")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func saveAndFinish() {
        userPreferences.gymFrequency = selectedFrequency
        userPreferences.workoutDuration = selectedDuration
        userPreferences.preferredGymTime = selectedTime
        onFinish()
    }
}

struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .cornerRadius(20)
        }
    }
}

#Preview {
    PreferencesView(onFinish: {})
        .environmentObject(UserPreferences.shared)
}
