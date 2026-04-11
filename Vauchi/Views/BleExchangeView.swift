// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// BleExchangeView.swift
// Bluetooth Low Energy exchange flow.
//
// BLE exchange uses the same QR-bootstrap multi-stage protocol as face-to-face,
// with BLE transport enabled for proximity verification after the QR handshake.
// This view wraps FaceToFaceExchangeView — the core exchange engine handles
// BLE command/event dispatch via ExchangeCommandHandler automatically.

import SwiftUI

struct BleExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    var switchToContacts: (() -> Void)?
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Info banner explaining BLE mode
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text("Bluetooth proximity active — exchange will use BLE when available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))

            // Reuse the face-to-face exchange which drives the full
            // command/event protocol including BLE via ExchangeCommandHandler.
            FaceToFaceExchangeView(switchToContacts: switchToContacts)
        }
    }
}
