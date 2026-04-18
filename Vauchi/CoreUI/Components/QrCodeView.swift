// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// QrCodeView.swift
// Renders a QrCode component from core UI

import SwiftUI

/// Renders a core `Component::QrCode` as a QR code display or scan placeholder.
struct QrCodeView: View {
    let component: QrCodeComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: CGFloat(tokens.spacing.md)) {
            switch component.mode {
            case .display:
                qrDisplayView()

            case .scan:
                qrScanPlaceholder()
            }

            if let label = component.label {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(CGFloat(tokens.spacing.md))
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityLabel(component.a11y?.label ?? component.label ?? "QR code")
        .accessibilityHint(component.a11y?.hint ?? "")
    }

    @ViewBuilder
    private func qrDisplayView() -> some View {
        if let qrImage = generateQRCode(from: component.data) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 250, maxHeight: 250)
                .accessibilityLabel("QR code")
        } else {
            Text("Failed to generate QR code")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func qrScanPlaceholder() -> some View {
        VStack(spacing: CGFloat(tokens.spacing.md)) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.cyan)
                .accessibilityHidden(true)

            Button {
                onAction(.actionPressed(actionId: "scan"))
            } label: {
                Text("Tap to Scan")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, CGFloat(tokens.spacing.lg))
                    .padding(.vertical, CGFloat(tokens.spacing.smMd))
                    .background(Color.cyan)
                    .cornerRadius(CGFloat(tokens.borderRadius.md))
            }
            .accessibilityLabel("Tap to scan QR code")
        }
    }

    /// Generates a QR code image using the Rust qrcode crate via UniFFI.
    /// Replaces CoreImage CIFilter.qrCodeGenerator() for cross-platform consistency.
    private func generateQRCode(from string: String) -> UIImage? {
        guard let qr = try? generateQrModules(
            data: string,
            errorCorrection: .m
        ) else { return nil }

        let width = Int(qr.width)
        let scale = 10
        let imageSize = width * scale

        var pixels = [UInt8](repeating: 255, count: imageSize * imageSize)
        for (index, isDark) in qr.modules.enumerated() where isDark {
            let row = index / width
            let col = index % width
            for py in (row * scale) ..< ((row + 1) * scale) {
                for px in (col * scale) ..< ((col + 1) * scale) {
                    pixels[py * imageSize + px] = 0
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: imageSize, height: imageSize,
                  bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: imageSize,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider,
                  decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
