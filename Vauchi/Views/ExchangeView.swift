// ExchangeView.swift
// QR code display for contact exchange

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showScanner = false
    @State private var exchangeData: ExchangeDataInfo?
    @State private var qrImage: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // QR Code section
                    VStack(spacing: 16) {
                        Text("Your QR Code")
                            .font(.headline)

                        Text("Have someone scan this to add you as a contact")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if isLoading {
                            ProgressView()
                                .frame(width: 200, height: 200)
                        } else if hasError {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                Text("Failed to generate QR code")
                                    .foregroundColor(.secondary)
                                Button("Retry") {
                                    loadExchangeData()
                                }
                                .buttonStyle(.bordered)
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

                                // Expiration timer
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text("Expires in \(formatTime(timeRemaining))")
                                        .font(.caption)
                                }
                                .foregroundColor(timeRemaining < 60 ? .orange : .secondary)

                                // Refresh button
                                Button(action: { loadExchangeData() }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(timeRemaining > 240) // Only allow refresh when < 4 min left
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
                        Text("Scan a Code")
                            .font(.headline)

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
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Exchange")
            .onAppear { loadExchangeData() }
            .onDisappear { stopTimer() }
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
