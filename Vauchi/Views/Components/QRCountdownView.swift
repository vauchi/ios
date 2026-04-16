// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// QRCountdownView.swift
// Shows a QR code with a countdown timer. Calls onExpired when time runs out.

import SwiftUI

/// Displays a QR code image with a live countdown to expiry.
///
/// Used by the device link flow to show remaining validity time and
/// automatically transition to an expired state when the QR expires.
struct QRCountdownView: View {
    @Environment(\.designTokens) private var tokens
    let qrData: String?
    let expiresAt: UInt64
    let generateQRCode: (String) -> UIImage?
    let onExpired: () -> Void

    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            if let qrData, let qrImage = generateQRCode(qrData) {
                Text("Scan this QR code on your new device")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    .accessibilityLabel("Device link QR code")

                // Countdown timer
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundColor(remainingSeconds <= 60 ? .orange : .secondary)
                    Text("Expires in \(formattedTime)")
                        .font(Font.subheadline.weight(.medium))
                        .foregroundColor(remainingSeconds <= 60 ? .orange : .secondary)
                }
                .accessibilityLabel("QR code expires in \(remainingSeconds) seconds")

                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for new device...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(
                    "Open Vauchi on your new device and select "
                        + "\"Join Existing Identity\" to scan this code."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            } else {
                ProgressView("Preparing...")
            }
        }
        .onAppear { startCountdown() }
        .onDisappear { timer?.invalidate() }
    }

    private var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startCountdown() {
        updateRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateRemaining()
        }
    }

    private func updateRemaining() {
        let now = UInt64(Date().timeIntervalSince1970)
        if now >= expiresAt {
            timer?.invalidate()
            remainingSeconds = 0
            onExpired()
        } else {
            remainingSeconds = Int(expiresAt - now)
        }
    }
}
