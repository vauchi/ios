// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NfcExchangeView.swift
// NFC tap exchange flow driven by NFCExchangeService + MobileNfcHandshake

import CoreNFC
import SwiftUI
import VauchiPlatform

struct NfcExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    var switchToContacts: (() -> Void)?
    @ObservedObject private var localizationService = LocalizationService.shared

    @State private var state: NfcState = .idle
    private let nfcService = NFCExchangeService()

    private enum NfcState {
        case idle
        case exchanging
        case success(contactName: String)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch state {
            case .idle:
                idleContent
            case .exchanging:
                exchangingContent
            case let .success(name):
                successContent(contactName: name)
            case let .error(msg):
                errorContent(message: msg)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle(localizationService.t("exchange.mode.nfc"))
        .onAppear { startExchange() }
        .onDisappear { nfcService.cancel() }
    }

    // MARK: - States

    @ViewBuilder
    private var idleContent: some View {
        Image(systemName: "wave.3.right")
            .font(.system(size: 64))
            .foregroundStyle(.blue)
        Text(localizationService.t("exchange.mode.nfc_description"))
            .font(.title3)
            .multilineTextAlignment(.center)
        Button(localizationService.t("action.start")) {
            startExchange()
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var exchangingContent: some View {
        ProgressView()
            .scaleEffect(1.5)
        Text("Hold phones together…")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func successContent(contactName: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(localizationService.t("exchange.success"))
                .font(.title2)
                .fontWeight(.semibold)
            Text(contactName)
                .font(.body)
                .foregroundStyle(.secondary)
            Button(localizationService.t("action.done")) {
                switchToContacts?()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text(localizationService.t("exchange.failed"))
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(localizationService.t("action.retry")) {
                startExchange()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func startExchange() {
        guard NFCTagReaderSession.readingAvailable else {
            state = .error("NFC not available on this device")
            return
        }

        do {
            let handshake = try viewModel.createNfcInitiator()
            state = .exchanging
            nfcService.startExchange(session: handshake) { result in
                switch result {
                case let .success(exchangeResult):
                    state = .success(contactName: exchangeResult.remoteDisplayName)
                case .relayFallback:
                    state = .error("NFC interrupted — try again or use QR")
                case let .error(msg):
                    state = .error(msg)
                }
            }
        } catch {
            state = .error("Failed to create NFC session: \(error.localizedDescription)")
        }
    }
}
