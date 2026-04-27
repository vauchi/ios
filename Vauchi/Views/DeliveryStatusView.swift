// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeliveryStatusView.swift
// Delivery status view showing message delivery history
// Based on: features/message_delivery.feature

import SwiftUI

/// Delivery status view accessible from Settings
struct DeliveryStatusView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var isLoading = true
    @State private var selectedTab = 0
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Recent").tag(0)
                Text("Failed").tag(1)
                Text("Pending").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityLabel("Delivery status filter")

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .accessibilityLabel("Loading delivery status")
                Spacer()
            } else {
                switch selectedTab {
                case 0:
                    RecentDeliveriesView(records: viewModel.deliveryRecords)
                case 1:
                    FailedDeliveriesView(records: viewModel.failedRecords, onRetry: retryDelivery)
                case 2:
                    PendingDeliveriesView(entries: viewModel.retryEntries)
                default:
                    RecentDeliveriesView(records: viewModel.deliveryRecords)
                }
            }
        }
        .navigationTitle("Delivery Status")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadData()
        }
        .refreshable {
            await refreshData()
        }
    }

    private func loadData() {
        isLoading = true
        Task {
            await viewModel.loadDeliveryRecords()
            await viewModel.loadRetryEntries()
            isLoading = false
        }
    }

    private func refreshData() async {
        await viewModel.loadDeliveryRecords()
        await viewModel.loadRetryEntries()
    }

    private func retryDelivery(messageId: String) {
        Task {
            let success = await viewModel.retryDelivery(messageId: messageId)
            if success {
                viewModel.showSuccess("Retry Scheduled", message: "The message will be retried shortly.")
            } else {
                viewModel.showError("Retry Failed", message: "Could not schedule retry for this message.")
            }
        }
    }
}

// MARK: - Recent Deliveries

struct RecentDeliveriesView: View {
    let records: [VauchiDeliveryRecord]

    var body: some View {
        if records.isEmpty {
            EmptyDeliveryView(
                icon: "checkmark.circle",
                title: "No Recent Deliveries",
                message: "Messages you send will appear here."
            )
        } else {
            List {
                ForEach(records) { record in
                    DeliveryRecordRow(record: record)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Failed Deliveries

struct FailedDeliveriesView: View {
    let records: [VauchiDeliveryRecord]
    let onRetry: (String) -> Void

    var body: some View {
        if records.isEmpty {
            EmptyDeliveryView(
                icon: "checkmark.circle.fill",
                title: "No Failed Deliveries",
                message: "All messages have been delivered successfully."
            )
        } else {
            List {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        DeliveryRecordRow(record: record)

                        Button(action: { onRetry(record.messageId) }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .accessibilityLabel("Retry delivery")
                        .accessibilityHint("Schedules another delivery attempt for this message")
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Pending Deliveries

struct PendingDeliveriesView: View {
    let entries: [VauchiRetryEntry]

    var body: some View {
        if entries.isEmpty {
            EmptyDeliveryView(
                icon: "clock",
                title: "No Pending Retries",
                message: "No messages are waiting to be retried."
            )
        } else {
            List {
                ForEach(entries) { entry in
                    RetryEntryRow(entry: entry)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Row Views

struct DeliveryRecordRow: View {
    let record: VauchiDeliveryRecord

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: record.status.iconName)
                .foregroundColor(statusColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(record.recipientId.prefix(16) + "...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(record.status.displayName)
                    .font(.body)
                    .foregroundColor(statusColor)

                if case let .failed(reason) = record.status {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                Text(record.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Expiration warning
            if record.isExpired {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
            } else if let expiresAt = record.expiresAt {
                if expiresAt.timeIntervalSinceNow < 86400 { // Less than 1 day
                    VStack(alignment: .trailing) {
                        Text("Expires")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text(expiresAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delivery to \(record.recipientId.prefix(8)), status: \(record.status.displayName)")
    }

    private var statusColor: Color {
        switch record.status {
        case .queued: .gray
        case .sent: .blue
        case .stored: .cyan
        case .delivered: .green
        case .expired: .orange
        case .failed: .red
        }
    }
}

struct RetryEntryRow: View {
    let entry: VauchiRetryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Retry icon
            Image(systemName: "arrow.clockwise.circle")
                .foregroundColor(.orange)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recipientId.prefix(16) + "...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("Attempt \(entry.attempt) of \(entry.maxAttempts)")
                    .font(.body)

                HStack {
                    Text("Next retry:")
                    Text(entry.nextRetry, style: .relative)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Max attempts warning
            if entry.isMaxExceeded {
                Text("Max attempts")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Retry for \(entry.recipientId.prefix(8)), attempt \(entry.attempt) of \(entry.maxAttempts)")
    }
}

struct EmptyDeliveryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - Delivery Status Indicator

/// Small delivery status indicator for contact rows
struct DeliveryStatusIndicator: View {
    let status: VauchiDeliveryStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(status.displayName)
                .font(.caption2)
        }
        .foregroundColor(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delivery status: \(status.displayName)")
    }

    private var color: Color {
        switch status {
        case .queued: .gray
        case .sent: .blue
        case .stored: .cyan
        case .delivered: .green
        case .expired: .orange
        case .failed: .red
        }
    }
}

// MARK: - Multi-Device Delivery Summary

struct DeliverySummaryView: View {
    let summary: VauchiDeliverySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(summary.progressPercent) / 100, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            // Status text
            HStack {
                Text(summary.displayText)
                    .font(.caption)

                Spacer()

                if summary.failedDevices > 0 {
                    Text("\(summary.failedDevices) failed")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delivery progress: \(summary.displayText), \(summary.progressPercent) percent")
        .accessibilityValue("\(summary.progressPercent)%")
    }

    private var progressColor: Color {
        if summary.isFullyDelivered {
            .green
        } else if summary.failedDevices > 0 {
            .orange
        } else {
            .blue
        }
    }
}

#Preview {
    NavigationView {
        DeliveryStatusView()
            .environmentObject(VauchiViewModel())
    }
}
