import SwiftUI

// MARK: - Confetti Particle

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let color: Color
    let rotation: Double
    let scale: CGFloat
    let shape: ConfettiShape

    enum ConfettiShape: CaseIterable {
        case circle, square, triangle, star
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @Binding var isActive: Bool
    let particleCount: Int

    @State private var particles: [ConfettiParticle] = []
    @State private var timer: Timer?

    private let colors: [Color] = [
        .green, .blue, .orange, .pink, .purple, .yellow, .red, .cyan
    ]

    init(isActive: Binding<Bool>, particleCount: Int = 100) {
        self._isActive = isActive
        self.particleCount = particleCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle)
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startConfetti(in: geometry.size)
                } else {
                    stopConfetti()
                }
            }
            .onAppear {
                if isActive {
                    startConfetti(in: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func startConfetti(in size: CGSize) {
        particles = []

        // Create particles
        for _ in 0..<particleCount {
            let particle = ConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: -20,
                color: colors.randomElement() ?? .green,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.2),
                shape: ConfettiParticle.ConfettiShape.allCases.randomElement() ?? .circle
            )
            particles.append(particle)
        }

        // Animate particles falling
        withAnimation(.easeOut(duration: 3.0)) {
            for i in particles.indices {
                particles[i].y = size.height + 50
                particles[i].x += CGFloat.random(in: -100...100)
            }
        }

        // Clear after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            particles = []
            isActive = false
        }
    }

    private func stopConfetti() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Confetti Piece

struct ConfettiPiece: View {
    let particle: ConfettiParticle

    var body: some View {
        Group {
            switch particle.shape {
            case .circle:
                Circle()
                    .fill(particle.color)
            case .square:
                Rectangle()
                    .fill(particle.color)
            case .triangle:
                Triangle()
                    .fill(particle.color)
            case .star:
                Image(systemName: "star.fill")
                    .foregroundColor(particle.color)
            }
        }
        .frame(width: 10 * particle.scale, height: 10 * particle.scale)
        .rotationEffect(.degrees(particle.rotation))
        .position(x: particle.x, y: particle.y)
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Goal Celebration Overlay

struct GoalCelebrationOverlay: View {
    @Binding var isShowing: Bool
    let stepCount: Int
    let goalSteps: Int

    @State private var showConfetti = false
    @State private var animateCheckmark = false
    @State private var animateText = false
    @State private var animateRings = false
    @State private var pulseScale: CGFloat = 1.0

    private var exceededSteps: Int {
        max(0, stepCount - goalSteps)
    }

    var body: some View {
        ZStack {
            // Semi-transparent background with blur
            Color.black.opacity(isShowing ? 0.6 : 0)
                .ignoresSafeArea()
                .blur(radius: isShowing ? 0 : 10)
                .onTapGesture {
                    dismissCelebration()
                }

            // Celebration content
            if isShowing {
                VStack(spacing: 32) {
                    // Animated checkmark with rings
                    ZStack {
                        // Outer pulsing rings
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(Color.green.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                                .frame(width: 120 + CGFloat(index * 30), height: 120 + CGFloat(index * 30))
                                .scaleEffect(animateRings ? 1.3 : 0.8)
                                .opacity(animateRings ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.3),
                                    value: animateRings
                                )
                        }

                        // Main circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .scaleEffect(animateCheckmark ? 1.0 : 0.3)
                            .opacity(animateCheckmark ? 1.0 : 0)
                            .shadow(color: .green.opacity(0.5), radius: 20, y: 10)

                        // Checkmark
                        Image(systemName: "checkmark")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(animateCheckmark ? 1.0 : 0.3)
                            .opacity(animateCheckmark ? 1.0 : 0)
                    }

                    // Celebration text
                    VStack(spacing: 12) {
                        Text("Goal Reached!")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("\(stepCount.formatted()) steps")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        if exceededSteps > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Exceeded by \(exceededSteps.formatted()) steps!")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .font(.subheadline)
                        }
                    }
                    .opacity(animateText ? 1.0 : 0)
                    .offset(y: animateText ? 0 : 30)

                    // Motivational message
                    Text(motivationalMessage)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(animateText ? 1.0 : 0)

                    // Dismiss button
                    Button {
                        dismissCelebration()
                    } label: {
                        HStack {
                            Text("Keep Moving")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .white.opacity(0.3), radius: 10)
                        )
                    }
                    .opacity(animateText ? 1.0 : 0)
                    .scaleEffect(animateText ? 1.0 : 0.8)
                }
                .onAppear {
                    triggerCelebration()
                }
            }

            // Confetti overlay
            ConfettiView(isActive: $showConfetti, particleCount: 200)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isShowing)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animateCheckmark)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateText)
    }

    private var motivationalMessage: String {
        let messages = [
            "Your consistency is paying off!",
            "Every step counts toward a healthier you!",
            "You're building something amazing!",
            "Champions are made one step at a time!",
            "Your future self will thank you!"
        ]
        return messages.randomElement() ?? messages[0]
    }

    private func triggerCelebration() {
        // Haptic feedback sequence
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Trigger animations
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            animateCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            animateRings = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.5)) {
                animateText = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showConfetti = true
        }

        // Additional haptic at confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func dismissCelebration() {
        withAnimation(.easeOut(duration: 0.3)) {
            animateCheckmark = false
            animateText = false
            animateRings = false
            isShowing = false
        }
    }
}

#Preview {
    GoalCelebrationOverlay(
        isShowing: .constant(true),
        stepCount: 10500,
        goalSteps: 10000
    )
}
