// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ExchangeView.swift
// QR code display for contact exchange

import CoreImage.CIFilterBuiltins
import SwiftUI

struct ExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showScanner = false
    @State private var exchangeData: ExchangeDataInfo?
    @State private var qrImage: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isEmittingAudio = false
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // QR Code section
                    VStack(spacing: 16) {
                        Text(localizationService.t("exchange.your_qr"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Text("Have someone scan this to add you as a contact")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("exchange.instructions")

                        if isLoading {
                            ProgressView()
                                .frame(width: 200, height: 200)
                        } else if hasError {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                    .accessibilityHidden(true)
                                Text(localizationService.t("exchange.qr_error"))
                                    .foregroundColor(.secondary)
                                Button(localizationService.t("action.retry")) {
                                    loadExchangeData()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityHint("Attempts to regenerate your QR code")
                            }
                            .frame(width: 200, height: 200)
                        } else if let image = qrImage {
                            VStack(spacing: 8) {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .accessibilityIdentifier("exchange.qrcode")
                                    .accessibilityLabel("Your contact exchange QR code")
                                    .accessibilityHint("Show this to someone to let them scan and add you as a contact")

                                // Expiration timer
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                        .accessibilityHidden(true)
                                    Text(localizationService.t("exchange.expires_in", args: ["time": formatTime(timeRemaining)]))
                                        .font(.caption)
                                }
                                .foregroundColor(timeRemaining < 60 ? .orange : .secondary)
                                .accessibilityElement(children: .combine)

                                // Refresh button
                                Button(action: { loadExchangeData() }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(timeRemaining > 240) // Only allow refresh when < 4 min left

                                // Proximity verification status
                                if viewModel.proximitySupported {
                                    HStack(spacing: 6) {
                                        Image(systemName: isEmittingAudio ? "waveform" : "waveform.circle")
                                            .foregroundColor(isEmittingAudio ? .green : .blue)
                                            .accessibilityHidden(true)
                                        Text(isEmittingAudio ? "Emitting audio..." : "Ultrasonic ready")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 4)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(
                                        isEmittingAudio
                                            ? "Ultrasonic proximity verification: emitting audio"
                                            : "Ultrasonic proximity verification: ready"
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Scan section
                    VStack(spacing: 16) {
                        Text(localizationService.t("exchange.scan"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Text("Scan someone else's QR code to add them")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { showScanner = true }) {
                            Label("Open Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.cyan)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .accessibilityIdentifier("exchange.scan.button")
                        .accessibilityLabel("Scan QR code")
                        .accessibilityHint("Opens the camera to scan someone else's QR code and add them as a contact")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // BLE Exchange stub
                    VStack(spacing: 16) {
                        Text("Bluetooth Exchange")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)

                        Text("Coming soon")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Exchange contact cards via Bluetooth when both devices are nearby. Requires Bluetooth hardware.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(localizationService.t("nav.exchange"))
            .onAppear { loadExchangeData() }
            .onDisappear {
                stopTimer()
                viewModel.stopProximityVerification()
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView()
            }
        }
    }

    private func loadExchangeData() {
        isLoading = true
        hasError = false
        stopTimer()

        do {
            exchangeData = try viewModel.generateExchangeData()
            if let data = exchangeData {
                qrImage = generateQRCode(from: data.qrData)
                timeRemaining = data.timeRemaining
                startTimer()
            }
            hasError = exchangeData == nil
        } catch {
            hasError = true
        }

        isLoading = false
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // QR expired, regenerate
                loadExchangeData()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for better quality
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ExchangeView()
        .environmentObject(VauchiViewModel())
}
