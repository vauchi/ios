// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
import SwiftUI
import VauchiPlatform

/// Renders a core `Component::QrCode`.
///
/// Display mode: encodes `data` to a QR bitmap via the rxing-backed
/// `generateQrBitmap` UniFFI helper and shows it inline. The `data`
/// string is the full payload core wants the peer to scan (typically
/// rotates every ~300 ms during multipart exchange). The optional
/// `label` doubles as the exchange status ("Show this" → "Transferring
/// 3/5" → "Almost done"), folded in by core so the screen needs no
/// separate status row.
///
/// Scan mode: opens an inline AVCaptureSession preview via the existing
/// `MultipartCameraPreview` helper. Each detected QR payload is emitted
/// as `UserAction.textChanged(componentId: component.id, value: code)`
/// — `core/vauchi-app/src/ui/exchange/qr.rs` interprets this as
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
    @EnvironmentObject private var viewModel: VauchiViewModel

    var body: some View {
        VStack(spacing: CGFloat(tokens.spacing.sm)) {
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
        .padding(CGFloat(tokens.spacing.sm))
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityLabel(component.a11y?.label ?? component.label ?? "QR code")
        .accessibilityHint(component.a11y?.hint ?? "")
    }

    @ViewBuilder
    private func qrDisplayView() -> some View {
        if let qrImage = generateQRCode(from: component.data) {
            // The display QR is the prominent element (the peer scans it).
            // Aspect-fit sizes it from whichever dimension the parent
            // actually proposes: on the non-scrolling `multi_stage_exchange`
            // screen it fills the height left after the small fixed scan
            // camera (the ResponsiveSquare lineage, d247571/5378fab); inside
            // a ScrollView (`ScreenLayout.scroll` screens like
            // `exchange_ble_glance`) the height proposal is nil, where the
            // old GeometryReader collapsed to its ~10 pt ideal — an
            // icon-sized, unscannable QR (device-confirmed 2026-07-02,
            // `2026-07-02-ios-qr-display-collapses-in-scroll-layout`) — so
            // the width drives instead, matching Android's
            // `fillMaxWidth().aspectRatio(1f)`.
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 400)
                // Greedy centering container — pixel-parity with the old
                // ResponsiveSquare on definite-height (Fixed) screens, where
                // the QR's card must keep absorbing the leftover viewport
                // (CI baseline testMultiStageExchangeCompactViewport). Under
                // a nil height proposal it collapses to the fitted image, so
                // the scroll fix above is unaffected.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // TODO(HUMBLE): [W, P2] hardcoded English a11y label names domain concept (`QR code`)
                // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                .accessibilityLabel("QR code")
        } else {
            // TODO(HUMBLE): [W, P2] hardcoded English error copy
            // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
            Text("Failed to generate QR code")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func qrScannerView() -> some View {
        // The scanner reads the active camera selector (`Command::SwitchCamera`)
        // from `AppViewModel.useFrontCamera`. `AppViewModel` is a nested
        // ObservableObject inside `VauchiViewModel` — SwiftUI does not
        // propagate inner-object publishes up to the outer @EnvironmentObject,
        // so a body that read `viewModel.coreViewModel?.useFrontCamera`
        // directly would not re-render when core flipped the value. Delegate
        // to an inner view that holds the AppViewModel via `@ObservedObject`
        // when it exists; the inner view re-renders on the published change
        // and propagates a fresh `.id(useFrontCamera)` into the
        // `MultipartCameraPreview` representable, which tears down and
        // rebuilds the underlying `AVCaptureSession` on the chosen device.
        if let coreVM = viewModel.coreViewModel {
            QrScannerObservingView(
                component: component,
                onAction: onAction,
                coreVM: coreVM
            )
        } else {
            // Pre-bootstrap fallback: no AppViewModel yet, so default to the
            // back camera. The scanner is unreachable from screens that
            // render before AppViewModel exists, so this branch is a
            // defensive default rather than a live code path.
            QrScannerStaticView(
                component: component,
                onAction: onAction,
                useFrontCamera: false
            )
        }
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

/// Inner view that observes [AppViewModel] directly so changes to its
/// nested `@Published useFrontCamera` re-render the camera preview.
/// Always proxies to [QrScannerStaticView] with the resolved Bool so
/// the layout side stays free of view-model knowledge.
private struct QrScannerObservingView: View {
    let component: QrCodeComponent
    let onAction: (UserAction) -> Void
    @ObservedObject var coreVM: AppViewModel

    var body: some View {
        QrScannerStaticView(
            component: component,
            onAction: onAction,
            useFrontCamera: coreVM.useFrontCamera,
            // T0.5: forward a camera-permission denial to core so the exchange
            // QR leg fails fast (grant affordance) instead of waiting forever.
            onPermissionDenied: { coreVM.sendCameraPermissionDenied() }
        )
    }
}

/// Stateless layout for the scan-mode QR preview. Pure-renderer:
/// no view-model access, just position + chunk callback. Recreate-on-flip
/// of the underlying `MultipartCameraPreview` is driven by
/// `.id(useFrontCamera)`, mirroring Android's `key(useFrontCamera)`
/// pattern in `QrCodeComponent.kt`.
private struct QrScannerStaticView: View {
    let component: QrCodeComponent
    let onAction: (UserAction) -> Void
    let useFrontCamera: Bool
    var onPermissionDenied: () -> Void = {}
    @Environment(\.designTokens) private var tokens

    /// The scan preview is the secondary element — a small fixed square so the
    /// display QR above it stays the focus and gets the rest of the viewport,
    /// with the camera/cancel buttons stacked beside it in the same row
    /// (matching Android). A definite frame is also required for
    /// `MultipartCameraPreview` (a `UIViewRepresentable` with no
    /// intrinsicContentSize): an earlier flexible `.aspectRatio(1.0)
    /// .frame(maxWidth:)` left it at 0×0 and the AVCaptureSession previewed
    /// into `.zero` bounds (F2-NEW-3).
    private let cameraSide: CGFloat = 110

    var body: some View {
        MultipartCameraPreview(
            onChunkScanned: { code in
                onAction(.textChanged(componentId: component.id, value: code))
            },
            useFrontCamera: useFrontCamera,
            onPermissionDenied: onPermissionDenied
        )
        .id(useFrontCamera)
        .frame(width: cameraSide, height: cameraSide)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.md)))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.md))
                .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
        )
        // TODO(HUMBLE): [W, P2] hardcoded English a11y label/hint name domain concept (`QR code`)
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        .accessibilityLabel(component.a11y?.label ?? "QR code scanner")
        .accessibilityHint(component.a11y?.hint ?? "Point the camera at a Vauchi QR code to scan it")
    }
}
