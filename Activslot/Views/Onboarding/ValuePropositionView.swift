import SwiftUI

struct ValuePropositionView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)

                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 32)

            // Title
            Text("Plan your steps & workouts\naround your real schedule")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)

            // Benefits
            VStack(alignment: .leading, spacing: 20) {
                BenefitRow(
                    icon: "figure.walk",
                    text: "Hit 10k steps even on busy days"
                )

                BenefitRow(
                    icon: "calendar.badge.clock",
                    text: "Find walkable meetings"
                )

                BenefitRow(
                    icon: "dumbbell.fill",
                    text: "Plan gym sessions that actually happen"
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // CTA Button
            Button(action: onContinue) {
                Text("Continue")
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
}

struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    ValuePropositionView(onContinue: {})
}
