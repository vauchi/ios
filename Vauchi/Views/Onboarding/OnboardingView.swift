// OnboardingView.swift
// Multi-step onboarding flow for new users
// Based on: features/onboarding.feature

import SwiftUI

/// Onboarding step enum
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case createIdentity = 1
    case addFields = 2
    case preview = 3
    case security = 4
    case ready = 5

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .createIdentity: return "Your Name"
        case .addFields: return "Add Info"
        case .preview: return "Preview"
        case .security: return "Security"
        case .ready: return "Ready"
        }
    }

    /// Total number of user-visible steps (excluding welcome and ready)
    static var userVisibleStepCount: Int { 4 }

    /// User-visible step number (1-indexed, excluding welcome)
    var userVisibleStepNumber: Int? {
        switch self {
        case .welcome, .ready: return nil
        case .createIdentity: return 1
        case .addFields: return 2
        case .preview: return 3
        case .security: return 4
        }
    }
}

/// Data collected during onboarding
class OnboardingData: ObservableObject {
    @Published var displayName: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    @Published var additionalFields: [(type: String, label: String, value: String)] = []

    var hasMinimumData: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct OnboardingView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @StateObject private var onboardingData = OnboardingData()
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isTransitioning = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator (hidden on welcome and ready)
            if let stepNumber = currentStep.userVisibleStepNumber {
                OnboardingProgressView(
                    currentStep: stepNumber,
                    totalSteps: OnboardingStep.userVisibleStepCount
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(onContinue: { advanceStep() }, onRestore: { /* TODO: implement restore */ })
                case .createIdentity:
                    CreateIdentityStepView(
                        displayName: $onboardingData.displayName,
                        onContinue: { advanceStep() },
                        onBack: { goBack() }
                    )
                case .addFields:
                    AddFieldsStepView(
                        phone: $onboardingData.phone,
                        email: $onboardingData.email,
                        onContinue: { advanceStep() },
                        onBack: { goBack() },
                        onSkip: { advanceStep() }
                    )
                case .preview:
                    PreviewCardStepView(
                        onboardingData: onboardingData,
                        onContinue: { advanceStep() },
                        onBack: { goBack() }
                    )
                case .security:
                    SecurityStepView(
                        onContinue: { completeOnboarding() },
                        onBack: { goBack() }
                    )
                case .ready:
                    ReadyStepView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .onAppear {
            // Resume from saved step if applicable
            let savedStep = SettingsService.shared.onboardingStep
            if savedStep > 0, let step = OnboardingStep(rawValue: savedStep) {
                currentStep = step
            }
        }
    }

    private func advanceStep() {
        guard !isTransitioning else { return }
        isTransitioning = true

        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
            SettingsService.shared.onboardingStep = nextStep.rawValue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }

    private func goBack() {
        guard !isTransitioning else { return }
        isTransitioning = true

        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
            SettingsService.shared.onboardingStep = prevStep.rawValue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }

    private func completeOnboarding() {
        Task {
            do {
                // Create identity
                try await viewModel.createIdentity(name: onboardingData.displayName)

                // Add phone field if provided
                if !onboardingData.phone.isEmpty {
                    try await viewModel.addField(type: "phone", label: "Phone", value: onboardingData.phone)
                }

                // Add email field if provided
                if !onboardingData.email.isEmpty {
                    try await viewModel.addField(type: "email", label: "Email", value: onboardingData.email)
                }

                // Add any additional fields
                for field in onboardingData.additionalFields {
                    try await viewModel.addField(type: field.type, label: field.label, value: field.value)
                }

                // Mark onboarding complete
                SettingsService.shared.hasCompletedOnboarding = true
                SettingsService.shared.onboardingStep = OnboardingStep.ready.rawValue

                // Transition to ready step briefly, then main app will take over
                currentStep = .ready
            } catch {
                viewModel.showError("Setup Failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.cyan : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(VauchiViewModel())
}
