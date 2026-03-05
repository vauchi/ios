// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

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
        case .welcome: "Welcome"
        case .createIdentity: "Your Name"
        case .addFields: "Add Info"
        case .preview: "Preview"
        case .security: "Security"
        case .ready: "Ready"
        }
    }

    /// Total number of user-visible steps (excluding welcome and ready)
    static var userVisibleStepCount: Int {
        4
    }

    /// User-visible step number (1-indexed, excluding welcome)
    var userVisibleStepNumber: Int? {
        switch self {
        case .welcome, .ready: nil
        case .createIdentity: 1
        case .addFields: 2
        case .preview: 3
        case .security: 4
        }
    }
}

/// Data collected during onboarding
///
/// Values are persisted to SettingsService so the card preview (and any
/// resumed onboarding session) sees the name, phone, and email that the
/// user entered in earlier steps — even after an app restart.
class OnboardingData: ObservableObject {
    @Published var displayName: String {
        didSet { SettingsService.shared.onboardingDisplayName = displayName }
    }

    @Published var phone: String {
        didSet { SettingsService.shared.onboardingPhone = phone }
    }

    @Published var email: String {
        didSet { SettingsService.shared.onboardingEmail = email }
    }

    @Published var additionalFields: [(type: String, label: String, value: String)] = []

    var hasMinimumData: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        // Restore any data saved from a previous session
        displayName = SettingsService.shared.onboardingDisplayName
        phone = SettingsService.shared.onboardingPhone
        email = SettingsService.shared.onboardingEmail
    }
}

struct OnboardingView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @StateObject private var onboardingData = OnboardingData()
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isTransitioning = false
    @State private var showRestoreSheet = false

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
                    WelcomeStepView(onContinue: { advanceStep() }, onRestore: { showRestoreSheet = true })
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
        .sheet(isPresented: $showRestoreSheet) {
            RestoreIdentitySheet(onRestoreComplete: {
                // Mark onboarding complete, clear draft data, and go to ready
                SettingsService.shared.hasCompletedOnboarding = true
                SettingsService.shared.onboardingStep = OnboardingStep.ready.rawValue
                SettingsService.shared.onboardingDisplayName = ""
                SettingsService.shared.onboardingPhone = ""
                SettingsService.shared.onboardingEmail = ""
                currentStep = .ready
            })
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

                // Add phone field if provided (non-fatal — validation errors skip the field)
                if !onboardingData.phone.isEmpty {
                    do {
                        try await viewModel.addField(type: "phone", label: "Phone", value: onboardingData.phone)
                    } catch {
                        print("Onboarding: skipping phone field: \(error.localizedDescription)")
                    }
                }

                // Add email field if provided (non-fatal — validation errors skip the field)
                if !onboardingData.email.isEmpty {
                    do {
                        try await viewModel.addField(type: "email", label: "Email", value: onboardingData.email)
                    } catch {
                        print("Onboarding: skipping email field: \(error.localizedDescription)")
                    }
                }

                // Add any additional fields (non-fatal)
                for field in onboardingData.additionalFields {
                    do {
                        try await viewModel.addField(type: field.type, label: field.label, value: field.value)
                    } catch {
                        print("Onboarding: skipping field \(field.label): \(error.localizedDescription)")
                    }
                }

                // Mark onboarding complete and clear persisted draft data
                SettingsService.shared.hasCompletedOnboarding = true
                SettingsService.shared.onboardingStep = OnboardingStep.ready.rawValue
                SettingsService.shared.onboardingDisplayName = ""
                SettingsService.shared.onboardingPhone = ""
                SettingsService.shared.onboardingEmail = ""

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
            ForEach(1 ... totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.cyan : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep) of \(totalSteps)")
        .accessibilityValue("\(currentStep) of \(totalSteps)")
    }
}

// MARK: - Restore Identity Sheet

struct RestoreIdentitySheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var backupData = ""
    @State private var password = ""
    @State private var isRestoring = false
    @State private var errorMessage: String?

    let onRestoreComplete: () -> Void

    var canRestore: Bool {
        !backupData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Enter your backup data and password to restore your identity. This will replace any existing identity on this device.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Backup Data") {
                    TextEditor(text: $backupData)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("restore.backupData")
                }

                Section("Password") {
                    SecureField("Backup password", text: $password)
                        .accessibilityIdentifier("restore.password")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: restoreBackup) {
                        HStack {
                            Spacer()
                            if isRestoring {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Restore Identity")
                            Spacer()
                        }
                    }
                    .disabled(!canRestore || isRestoring)
                }
            }
            .navigationTitle("Restore Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func restoreBackup() {
        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.importBackup(
                    data: backupData.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )

                await MainActor.run {
                    dismiss()
                    onRestoreComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRestoring = false
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(VauchiViewModel())
}
