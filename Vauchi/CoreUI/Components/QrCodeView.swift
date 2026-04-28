// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// QrCodeView.swift
// Renders a QrCode component from core UI

import CoreUIModels
import SwiftUI
import VauchiPlatform

/// Renders a core `Component::QrCode`.
///
/// Display mode: encodes `data` to a QR bitmap via the rxing-backed
/// `generateQrBitmap` UniFFI helper and shows it inline. The `data`
/// string is the full payload core wants the peer to scan (typically
/// rotates every ~300 ms during multipart exchange).
///
/// Scan mode: opens an inline AVCaptureSession preview via the existing
/// `MultipartCameraPreview` helper. Each detected QR payload is emitted
/// as `UserAction.textChanged(componentId: component.id, value: code)`
/// — `core/vauchi-app/src/ui/exchange_qr.rs` interprets this as
/// `QrActionOutcome::QrScanned { data }` for the legacy single-stage
/// ScanQr step, and `core/vauchi-platform/src/platform_app_engine.rs`
/// auto-routes it into the live cycle-thread session when the
/// multi-stage screen is active. Replaces the long-standing "Tap to
/// Scan" no-op placeholder which was unimplemented when the
/// core-driven exchange flow first landed.
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
                qrScannerView()
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

    private func qrScannerView() -> some View {
        // Forward every detected QR payload to core. `exchange_qr.rs`
        // pattern-matches on TextChanged with the QR component id and
        // routes the payload through QrScanned for the single-stage
        // engine; the multi-stage screen relies on
        // `PlatformAppEngine.handle_action_json`'s peer_scan auto-route
        // to feed the cycle-thread session.
        MultipartCameraPreview { code in
            onAction(.textChanged(componentId: component.id, value: code))
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxWidth: 250)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.md)))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.md))
                .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
        )
        .accessibilityLabel(component.a11y?.label ?? "QR code scanner")
        .accessibilityHint(component.a11y?.hint ?? "Point the camera at a Vauchi QR code to scan it")
    }

    /// Generates a QR code image using the Rust qrcode crate via UniFFI.
    /// Replaces CoreImage CIFilter.qrCodeGenerator() for cross-platform consistency.
    private func generateQRCode(from string: String) -> UIImage? {
        guard let qr = try? generateQrBitmap(
            data: string, size: 512, ecc: .medium, dark: 0, light: 255, margin: 4
        ) else { return nil }
        let imageSize = Int(qr.size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(qr.pixels) as CFData),
              let cgImage = CGImage(
                  width: imageSize, height: imageSize,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: imageSize,
                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
