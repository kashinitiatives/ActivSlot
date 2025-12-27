import SwiftUI

// MARK: - Personal Why Selection View

struct PersonalWhyView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @State private var selectedWhy: PersonalWhy?
    @State private var customReason: String = ""
    @State private var showCustomInput = false

    var onContinue: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What Matters to You?")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Choose the reason that resonates most. We'll remind you of this when it matters.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Why Options Grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(PersonalWhy.allCases.filter { $0 != .custom }, id: \.self) { why in
                            WhyOptionCard(
                                why: why,
                                isSelected: selectedWhy == why,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedWhy = why
                                        showCustomInput = false
                                    }
                                }
                            )
                        }

                        // Custom option
                        WhyOptionCard(
                            why: .custom,
                            isSelected: selectedWhy == .custom,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedWhy = .custom
                                    showCustomInput = true
                                }
                            }
                        )
                    }

                    // Custom input
                    if showCustomInput {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Reason")
                                .font(.headline)

                            TextField("What motivates you to move?", text: $customReason)
                                .textFieldStyle(.roundedBorder)
                                .padding(.bottom, 8)

                            Text("This will be your personal reminder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Motivational preview
                    if let why = selectedWhy, why != .custom {
                        MotivationPreviewCard(message: why.motivationalMessage)
                            .transition(.opacity.combined(with: .scale))
                    } else if selectedWhy == .custom && !customReason.isEmpty {
                        MotivationPreviewCard(message: customReason)
                            .transition(.opacity.combined(with: .scale))
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal)
            }

            // Continue Button
            VStack(spacing: 16) {
                Button {
                    saveSelection()
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedWhy != nil ? Color.blue : Color.gray)
                        .cornerRadius(14)
                }
                .disabled(selectedWhy == nil || (selectedWhy == .custom && customReason.isEmpty))

                Button("Skip for now") {
                    onContinue()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    private func saveSelection() {
        userPreferences.personalWhy = selectedWhy
        if selectedWhy == .custom {
            userPreferences.personalWhyCustom = customReason
        }
    }
}

// MARK: - Why Option Card

struct WhyOptionCard: View {
    let why: PersonalWhy
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: why.icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? .white : .blue)

                Text(why.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Motivation Preview Card

struct MotivationPreviewCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your motivation")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    PersonalWhyView(onContinue: {})
        .environmentObject(UserPreferences.shared)
}
