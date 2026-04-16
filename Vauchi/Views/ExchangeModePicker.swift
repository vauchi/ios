// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ExchangeModePicker.swift
// Mode picker for exchange: QR (default), NFC, Bluetooth.

import CoreNFC
import SwiftUI

enum ExchangeMode: String, Hashable, Identifiable, CaseIterable {
    case qr, nfc, ble

    var id: String {
        rawValue
    }
}

struct ExchangeModePicker: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let switchToContacts: () -> Void
    @ObservedObject private var localizationService = LocalizationService.shared

    @State private var selectedMode: ExchangeMode?

    private var hasNfc: Bool {
        NFCTagReaderSession.readingAvailable
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text(localizationService.t("exchange.choose_method"))
                    .font(.title2)
                    .padding(.bottom, 8)

                modeCard(
                    icon: "qrcode",
                    title: localizationService.t("exchange.mode.qr"),
                    subtitle: localizationService.t("exchange.mode.qr_description"),
                    enabled: true,
                    destination: FaceToFaceExchangeView(switchToContacts: switchToContacts)
                )

                modeCard(
                    icon: "wave.3.right",
                    title: localizationService.t("exchange.mode.nfc"),
                    subtitle: localizationService.t("exchange.mode.nfc_description"),
                    enabled: hasNfc,
                    destination: NfcExchangeView(switchToContacts: switchToContacts)
                )

                modeCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: localizationService.t("exchange.mode.ble"),
                    subtitle: localizationService.t("exchange.mode.ble_description"),
                    enabled: true,
                    destination: BleExchangeView(switchToContacts: switchToContacts)
                )

                Spacer()
            }
            .padding(24)
            .navigationTitle(localizationService.t("nav.exchange"))
        }
        .navigationViewStyle(.stack)
    }

    private func modeCard(
        icon: String, title: String, subtitle: String,
        enabled: Bool, destination: some View
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .frame(width: 40)
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(enabled ? subtitle : localizationService.t("exchange.mode.unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.4)
    }
}
