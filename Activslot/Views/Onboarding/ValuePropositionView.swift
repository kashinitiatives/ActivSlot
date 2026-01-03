import SwiftUI

struct ValuePropositionView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false
    @State private var animateBenefits = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated App Icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.green.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(animateIcon ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)

                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 110, height: 110)
                    .shadow(color: .green.opacity(0.4), radius: 20, y: 10)

                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, options: .repeating, value: animateIcon)
            }
            .padding(.bottom, 40)
            .onAppear {
                animateIcon = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    animateBenefits = true
                }
            }

            // Title with gradient
            Text("Back-to-back meetings?")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("We'll find your walking moments.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Subtitle for target audience
            Text("Built for busy professionals who want to move more")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)

            // Benefits with staggered animation
            VStack(alignment: .leading, spacing: 24) {
                BenefitRow(
                    icon: "calendar.badge.clock",
                    iconColor: .blue,
                    text: "Turn 1:1s into walking meetings"
                )
                .opacity(animateBenefits ? 1 : 0)
                .offset(x: animateBenefits ? 0 : -20)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: animateBenefits)

                BenefitRow(
                    icon: "target",
                    iconColor: .green,
                    text: "Hit your step goal without extra time"
                )
                .opacity(animateBenefits ? 1 : 0)
                .offset(x: animateBenefits ? 0 : -20)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: animateBenefits)

                BenefitRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    text: "Build streaks that keep you moving"
                )
                .opacity(animateBenefits ? 1 : 0)
                .offset(x: animateBenefits ? 0 : -20)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: animateBenefits)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Premium CTA Button
            Button(action: onContinue) {
                HStack {
                    Text("Get Started")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
        .background(Color(.systemBackground))
    }
}

struct BenefitRow: View {
    let icon: String
    var iconColor: Color = .green
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            Text(text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ValuePropositionView(onContinue: {})
}
