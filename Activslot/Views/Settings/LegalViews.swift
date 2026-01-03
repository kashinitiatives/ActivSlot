import SwiftUI

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Last Updated: January 3, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Group {
                    SectionView(
                        title: "Introduction",
                        content: "Activslot (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our mobile application."
                    )

                    SectionView(
                        title: "Information We Collect",
                        content: """
                        We collect the following types of information:

                        • Health Data: Step counts, active energy, and workout data from Apple HealthKit to track your fitness progress.

                        • Calendar Data: Calendar events to identify walkable meetings and suggest optimal times for physical activity.

                        • Preferences: Your personal settings such as wake/sleep times, meal times, and fitness goals.

                        All data is stored locally on your device and is not transmitted to external servers.
                        """
                    )

                    SectionView(
                        title: "How We Use Your Information",
                        content: """
                        We use your information to:

                        • Track your daily step progress toward your goals
                        • Identify opportunities for walking meetings
                        • Send timely reminders about physical activity
                        • Personalize your experience based on your patterns
                        • Maintain your streak and achievement history
                        """
                    )
                }

                Group {
                    SectionView(
                        title: "Data Storage & Security",
                        content: "All personal data is stored locally on your device using iOS secure storage mechanisms. We do not have access to your personal health or calendar data. Your data is protected by your device's security features including Face ID, Touch ID, or passcode."
                    )

                    SectionView(
                        title: "Third-Party Services",
                        content: "We integrate with Apple HealthKit to read your fitness data. We may integrate with Microsoft Outlook for calendar access if you choose to connect your work calendar. These integrations require your explicit consent."
                    )

                    SectionView(
                        title: "Your Rights",
                        content: """
                        You have the right to:

                        • Access your personal data
                        • Delete your data by uninstalling the app
                        • Revoke permissions at any time in iOS Settings
                        • Export your data (coming soon)
                        """
                    )

                    SectionView(
                        title: "Contact Us",
                        content: "If you have questions about this Privacy Policy, please contact us at privacy@activslot.com"
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Last Updated: January 3, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Group {
                    SectionView(
                        title: "Acceptance of Terms",
                        content: "By downloading, installing, or using Activslot, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the application."
                    )

                    SectionView(
                        title: "Description of Service",
                        content: "Activslot is a fitness planning application that helps busy professionals integrate physical activity into their daily schedules by analyzing calendar data and suggesting optimal times for walks and workouts."
                    )

                    SectionView(
                        title: "Health Disclaimer",
                        content: """
                        Activslot is not a medical device and is not intended to diagnose, treat, cure, or prevent any disease or health condition.

                        Always consult with a qualified healthcare provider before starting any new exercise program. The app's suggestions are based on your calendar availability, not your physical condition.

                        You are solely responsible for your own health decisions and physical activity.
                        """
                    )
                }

                Group {
                    SectionView(
                        title: "User Responsibilities",
                        content: """
                        You agree to:

                        • Provide accurate information about your preferences
                        • Use the app in accordance with all applicable laws
                        • Not attempt to reverse engineer or modify the app
                        • Not use the app for any illegal or unauthorized purpose
                        """
                    )

                    SectionView(
                        title: "Intellectual Property",
                        content: "All content, features, and functionality of Activslot are owned by Activslot and are protected by international copyright, trademark, and other intellectual property laws."
                    )

                    SectionView(
                        title: "Limitation of Liability",
                        content: "To the maximum extent permitted by law, Activslot shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of or inability to use the application."
                    )

                    SectionView(
                        title: "Changes to Terms",
                        content: "We reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms."
                    )

                    SectionView(
                        title: "Contact",
                        content: "For questions about these Terms, contact us at legal@activslot.com"
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper View

private struct SectionView: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Privacy Policy") {
    NavigationStack {
        PrivacyPolicyView()
    }
}

#Preview("Terms of Service") {
    NavigationStack {
        TermsOfServiceView()
    }
}
