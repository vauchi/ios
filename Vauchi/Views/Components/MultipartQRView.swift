// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MultipartQRView.swift
// Animated QR display that cycles through multipart QR chunks at ~3fps.

import CoreImage.CIFilterBuiltins
import SwiftUI

/// Animated QR display that cycles through multipart QR chunks.
///
/// Used for payloads too large for a single QR code (e.g., encrypted device link responses).
/// Displays each chunk as a QR code image, cycling at approximately 3 frames per second,
/// with a progress indicator showing the current part.
struct MultipartQRView: View {
    /// The encoded chunk strings to display as QR codes.
    let chunks: [String]

    @State private var currentIndex = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            if chunks.isEmpty {
                Text("No QR data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("No QR data available")
            } else {
                qrCodeImage
                partLabel
                progressIndicator
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var qrCodeImage: some View {
        if let qrImage = generateQRCode(from: chunks[currentIndex]) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .background(Color.white)
                .cornerRadius(12)
                .accessibilityLabel("Animated QR code part \(currentIndex + 1) of \(chunks.count)")
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(width: 250, height: 250)
                .overlay(
                    Text("QR generation failed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
                .accessibilityLabel("QR code generation failed for part \(currentIndex + 1)")
        }
    }

    private var partLabel: some View {
        Text("Part \(currentIndex + 1) of \(chunks.count)")
            .font(.caption)
            .foregroundColor(.secondary)
            .accessibilityHidden(true) // Redundant with QR image label
    }

    private var progressIndicator: some View {
        ProgressView(value: Double(currentIndex + 1), total: Double(chunks.count))
            .padding(.horizontal)
            .accessibilityLabel("Displaying part \(currentIndex + 1) of \(chunks.count)")
    }

    // MARK: - Animation

    private func startAnimation() {
        guard chunks.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 3.0, repeats: true) { _ in
            currentIndex = (currentIndex + 1) % chunks.count
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        return UIImage(ciImage: output.transformed(by: transform))
    }
}

// MARK: - Preview

#Preview {
    MultipartQRView(chunks: [
        "VQ|1|3|SGVsbG8gV29ybGQ=",
        "VQ|2|3|VGhpcyBpcyBwYXJ0IDI=",
        "VQ|3|3|QW5kIHBhcnQgdGhyZWU=",
    ])
}
