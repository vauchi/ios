// QRScannerView.swift
// Camera-based QR code scanning

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var scannedCode: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var exchangeResult: ExchangeResultInfo?
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                // Camera view
                CameraPreview(scannedCode: $scannedCode)
                    .ignoresSafeArea()

                // Overlay
                VStack {
                    Spacer()

                    // Scan frame
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .background(Color.clear)

                    Spacer()

                    // Status
                    VStack(spacing: 12) {
                        if let error = errorMessage {
                            VStack(spacing: 8) {
                                Text(error)
                                    .foregroundColor(.red)
                                Button("Try Again") {
                                    errorMessage = nil
                                    scannedCode = nil
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        } else if isProcessing {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Processing exchange...")
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        } else {
                            Text("Point camera at a Vauchi QR code")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .onChange(of: scannedCode) { newValue in
                if let code = newValue {
                    processScannedCode(code)
                }
            }
            .alert("Contact Added", isPresented: $showSuccessAlert) {
                Button("OK") { dismiss() }
            } message: {
                if let result = exchangeResult {
                    Text("Successfully added \(result.contactName) as a contact!")
                }
            }
        }
    }

    private func processScannedCode(_ code: String) {
        guard !isProcessing else { return }

        // Validate it's a Vauchi QR code
        guard code.hasPrefix("wb://") else {
            errorMessage = "Not a valid Vauchi QR code"
            scannedCode = nil
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let result = try await viewModel.completeExchange(qrData: code)
                exchangeResult = result

                if result.success {
                    showSuccessAlert = true
                } else {
                    errorMessage = result.errorMessage ?? "Exchange failed"
                    scannedCode = nil
                }
            } catch {
                // Check for duplicate contact error
                if error.localizedDescription.contains("already exists") {
                    errorMessage = "You already have this contact"
                } else {
                    errorMessage = error.localizedDescription
                }
                scannedCode = nil
            }
            isProcessing = false
        }
    }
}

// Camera preview using AVFoundation
struct CameraPreview: UIViewRepresentable {
    @Binding var scannedCode: String?

    func makeUIView(context: Context) -> UIView {
        let view = CameraView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedCode: $scannedCode)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String?
        private var lastScannedCode: String?
        private var lastScanTime: Date?

        init(scannedCode: Binding<String?>) {
            _scannedCode = scannedCode
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                           didOutput metadataObjects: [AVMetadataObject],
                           from connection: AVCaptureConnection) {
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = metadataObject.stringValue else {
                return
            }

            // Debounce: don't re-scan the same code within 2 seconds
            if let lastCode = lastScannedCode,
               let lastTime = lastScanTime,
               lastCode == code,
               Date().timeIntervalSince(lastTime) < 2.0 {
                return
            }

            lastScannedCode = code
            lastScanTime = Date()

            DispatchQueue.main.async {
                self.scannedCode = code
            }
        }
    }
}

class CameraView: UIView {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds

        if captureSession == nil {
            setupCamera()
        }
    }

    private func setupCamera() {
        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.initializeCamera()
                    }
                }
            }
        default:
            // Show permission denied message
            showPermissionDenied()
        }
    }

    private func initializeCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func showPermissionDenied() {
        let label = UILabel()
        label.text = "Camera access required.\nPlease enable in Settings."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])

        backgroundColor = .black
    }

    deinit {
        captureSession?.stopRunning()
    }
}

#Preview {
    QRScannerView()
        .environmentObject(VauchiViewModel())
}
