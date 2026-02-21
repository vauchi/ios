// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ValidationBadgeView.swift
// Displays crowd-sourced field validation trust indicators

import SwiftUI
import VauchiMobile

/// Displays the validation trust level for a contact field.
///
/// Shows a colored badge with the validation count and trust level,
/// plus a button to validate or revoke your validation.
struct ValidationBadgeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let contactId: String
    let field: FieldInfo

    @State private var status: MobileValidationStatus?
    @State private var isLoading = false
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        HStack(spacing: 6) {
            if let status {
                // Trust level badge
                HStack(spacing: 3) {
                    if status.count > 0 {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                        Text("\(status.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "shield")
                            .font(.caption2)
                    }
                }
                .foregroundColor(trustColor(status.color))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(trustColor(status.color).opacity(0.15))
                .cornerRadius(4)
                .help(status.displayText)
                .accessibilityLabel("Trust level: \(status.trustLevelLabel). \(status.displayText)")

                // Validate / Revoke button
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if status.validatedByMe {
                    Button(action: { revokeValidation() }) {
                        Text("Revoke")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Revoke your validation of \(field.label)")
                } else {
                    Button(action: { validateFieldAction() }) {
                        Text("Validate")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Validate \(field.label)")
                }
            }
        }
        .onAppear {
            loadStatus()
        }
    }

    private func trustColor(_ color: String) -> Color {
        switch color {
        case "green": .green
        case "light_green": Color.green.opacity(0.7)
        case "yellow": .yellow
        default: .gray
        }
    }

    private func loadStatus() {
        Task {
            do {
                let result = try await viewModel.getFieldValidationStatus(
                    contactId: contactId,
                    fieldId: field.id,
                    fieldValue: field.value
                )
                status = result
            } catch {
                // Status unavailable — badge stays hidden
            }
        }
    }

    private func validateFieldAction() {
        isLoading = true
        Task {
            do {
                _ = try await viewModel.validateField(
                    contactId: contactId,
                    fieldId: field.id,
                    fieldValue: field.value
                )
                loadStatus()
            } catch {
                viewModel.showError("Validation Failed", message: error.localizedDescription)
            }
            isLoading = false
        }
    }

    private func revokeValidation() {
        isLoading = true
        Task {
            do {
                _ = try await viewModel.revokeFieldValidation(
                    contactId: contactId,
                    fieldId: field.id
                )
                loadStatus()
            } catch {
                viewModel.showError("Revoke Failed", message: error.localizedDescription)
            }
            isLoading = false
        }
    }
}
