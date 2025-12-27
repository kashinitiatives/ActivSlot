import SwiftUI

struct OnboardingContainerView: View {
    @StateObject private var userPreferences = UserPreferences.shared
    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let totalPages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ValuePropositionView(onContinue: { currentPage = 1 })
                    .tag(0)

                PersonalWhyView(onContinue: { currentPage = 2 })
                    .environmentObject(userPreferences)
                    .tag(1)

                PermissionsView(onContinue: {
                    hasCompletedOnboarding = true
                })
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    OnboardingContainerView()
}
