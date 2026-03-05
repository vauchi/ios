// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NfcTestView.swift
// Minimal test view for NFC encrypted exchange (iOS reader only).

import SwiftUI
import VauchiMobile

struct NfcTestView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var status = "Tap Start to begin"
    @State private var result: String?
    @State private var nfcState = "—"
    @State private var isScanning = false

    private let nfcService = NFCExchangeService()

    var body: some View {
        VStack(spacing: 20) {
            Text("NFC Exchange Test")
                .font(.title)

            Text("Mode: iOS Reader (Initiator)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Status: \(status)")
            Text("State: \(nfcState)")
                .font(.caption)

            if let result {
                GroupBox("Result") {
                    Text(result)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            if !isScanning {
                Button("Start NFC Exchange") {
                    startExchange()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Cancel") {
                    nfcService.cancel()
                    isScanning = false
                    status = "Cancelled"
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    private func startExchange() {
        do {
            let session = try viewModel.createNfcInitiator()
            isScanning = true
            status = "Hold phone near Android device..."
            nfcState = "\(session.state())"

            nfcService.startExchange(session: session) { outcome in
                isScanning = false
                switch outcome {
                case let .success(exchangeResult):
                    let keyHex = exchangeResult.remoteIdentityKey
                        .prefix(8)
                        .map { String(format: "%02x", UInt8(bitPattern: $0)) }
                        .joined()
                    result = "Exchange complete!\n" +
                        "Remote: \(exchangeResult.remoteDisplayName)\n" +
                        "Identity key: \(keyHex)..."
                    status = "Success"
                    nfcState = "\(session.state())"

                case let .relayFallback(exchangeId):
                    let idHex = exchangeId
                        .prefix(8)
                        .map { String(format: "%02x", $0) }
                        .joined()
                    result = "Relay fallback\nExchange ID: \(idHex)..."
                    status = "Relay fallback"
                    nfcState = "\(session.state())"

                case let .error(message):
                    result = "Error: \(message)"
                    status = "Failed"
                }
            }
        } catch {
            status = "Failed: \(error)"
        }
    }
}
