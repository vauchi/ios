// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import CoreNFC
    import SwiftUI

    /// NFC diagnostic view for testing NFC transport capabilities.
    ///
    /// iOS acts as reader (initiator) — sends APDUs to Android HCE responder.
    /// Tests: Discovery, AID Selection, APDU Latency, Max Payload, Throughput.
    ///
    /// Launch via devicectl:
    ///   xcrun devicectl device process launch --device <UDID> app.vauchi.ios -- --nfc-test discovery
    ///   xcrun devicectl device process launch --device <UDID> app.vauchi.ios -- --nfc-test aid_select
    ///   xcrun devicectl device process launch --device <UDID> app.vauchi.ios -- --nfc-test apdu_latency
    ///   xcrun devicectl device process launch --device <UDID> app.vauchi.ios -- --nfc-test max_payload
    ///   xcrun devicectl device process launch --device <UDID> app.vauchi.ios -- --nfc-test throughput
    struct NfcDiagnosticView: View {
        /// Set to run a specific test on appear
        var autoTest: String?

        @State private var logLines: [String] = []
        @State private var running = false
        @State private var nfcManager: NfcDiagnosticManager?

        var body: some View {
            VStack(spacing: 16) {
                Text("NFC Diagnostic")
                    .font(Font.title2.weight(.bold))

                Text("iOS Reader → Android HCE")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    diagButton("A: Discovery") { runNfcTest("discovery") }
                    diagButton("B: AID Select") { runNfcTest("aid_select") }
                    diagButton("C: APDU Latency") { runNfcTest("apdu_latency") }
                }

                HStack(spacing: 12) {
                    diagButton("D: Max Payload") { runNfcTest("max_payload") }
                    diagButton("E: Throughput") { runNfcTest("throughput") }
                }

                if running {
                    ProgressView("Waiting for NFC tap...")
                        .padding(.vertical, 4)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: logLines.count) { _ in
                        if let last = logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let test = autoTest {
                    runNfcTest(test)
                }
            }
        }

        // MARK: - UI Helpers

        private func diagButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title) { action() }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                .font(.caption)
        }

        private static let logFileURL: URL = {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent("nfc-diagnostic.log")
        }()

        private func log(_ msg: String) {
            let timestamped = "[\(timeStamp())] \(msg)"
            NSLog("[NFC Diag] %@", msg)
            let line = timestamped + "\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: Self.logFileURL)
                }
            }
            DispatchQueue.main.async {
                logLines.append(timestamped)
            }
        }

        private func timeStamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }

        private func clearLogFile() {
            try? "".write(to: Self.logFileURL, atomically: true, encoding: .utf8)
        }

        // MARK: - Test Runner

        private func runNfcTest(_ name: String) {
            guard NFCTagReaderSession.readingAvailable else {
                log("NFC not available on this device")
                return
            }

            running = true
            clearLogFile()

            let manager = NfcDiagnosticManager()
            nfcManager = manager
            manager.runTest(name: name, log: log) {
                DispatchQueue.main.async {
                    running = false
                    nfcManager = nil
                }
            }
        }
    }

    // MARK: - NFC Diagnostic Manager

    /// Manages CoreNFC sessions for diagnostic tests.
    /// Each test starts an NFCTagReaderSession, connects to the first ISO7816 tag,
    /// and runs APDU commands against the Android diagnostic HCE service.
    private class NfcDiagnosticManager: NSObject, NFCTagReaderSessionDelegate {
        /// Diagnostic AID: F0564155434849D1 (Vauchi AID + D1 suffix)
        private static let diagnosticAID = Data([0xF0, 0x56, 0x41, 0x55, 0x43, 0x48, 0x49, 0xD1])
        private static let insEcho: UInt8 = 0xD0
        private static let insPayloadTest: UInt8 = 0xD1

        private var nfcSession: NFCTagReaderSession?
        private var logFn: ((String) -> Void)?
        private var completionFn: (() -> Void)?
        private var currentTest: String?
        private var connectedTag: NFCISO7816Tag?

        func runTest(name: String, log: @escaping (String) -> Void, completion: @escaping () -> Void) {
            logFn = log
            completionFn = completion
            currentTest = name

            let session = NFCTagReaderSession(
                pollingOption: .iso14443,
                delegate: self,
                queue: nil
            )
            session?.alertMessage = "Hold near Android HCE device"
            nfcSession = session
            session?.begin()
        }

        // MARK: - NFCTagReaderSessionDelegate

        func tagReaderSessionDidBecomeActive(_: NFCTagReaderSession) {
            logFn?("NFC session active, waiting for tap...")
        }

        func tagReaderSession(_: NFCTagReaderSession, didInvalidateWithError error: Error) {
            let nsError = error as NSError
            if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue { return }
            if nsError.code == NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue { return }
            logFn?("Session error: \(error.localizedDescription)")
            completionFn?()
        }

        func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
            guard let tag = tags.first, case let .iso7816(iso7816Tag) = tag else {
                session.invalidate(errorMessage: "No ISO7816 tag found")
                completionFn?()
                return
            }

            session.connect(to: tag) { [weak self] error in
                if let error {
                    session.invalidate(errorMessage: "Connect failed: \(error.localizedDescription)")
                    self?.completionFn?()
                    return
                }
                self?.connectedTag = iso7816Tag
                self?.executeTest(tag: iso7816Tag, session: session)
            }
        }

        // MARK: - Test Dispatch

        private func executeTest(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            guard let test = currentTest else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                switch test {
                case "discovery":
                    testDiscovery(tag: tag, session: session)
                case "aid_select":
                    testAidSelection(tag: tag, session: session)
                case "apdu_latency":
                    testApduLatency(tag: tag, session: session)
                case "max_payload":
                    testMaxPayload(tag: tag, session: session)
                case "throughput":
                    testThroughput(tag: tag, session: session)
                default:
                    logFn?("Unknown test: \(test)")
                    session.invalidate()
                    completionFn?()
                }
            }
        }

        // MARK: - Test A: Discovery

        private func testDiscovery(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            logFn?("=== Test A: NFC Discovery ===")
            logFn?("Tag connected: \(tag.identifier.map { String(format: "%02x", $0) }.joined())")

            // Try SELECT diagnostic AID
            let result = sendApduSync(tag: tag, ins: 0xA4, p1: 0x04, p2: 0x00, data: Self.diagnosticAID)

            switch result {
            case let .success(_, sw1, sw2):
                if sw1 == 0x90, sw2 == 0x00 {
                    logFn?("PASS: Diagnostic HCE service found")
                } else {
                    logFn?("FAIL: AID rejected (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                }
            case let .failure(error):
                logFn?("FAIL: \(error)")
            }

            session.alertMessage = "Discovery complete"
            session.invalidate()
            completionFn?()
        }

        // MARK: - Test B: AID Selection Latency

        private func testAidSelection(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            logFn?("=== Test B: AID Selection ===")

            var times: [Double] = []

            for i in 1 ... 5 {
                let start = CFAbsoluteTimeGetCurrent()
                let result = sendApduSync(tag: tag, ins: 0xA4, p1: 0x04, p2: 0x00, data: Self.diagnosticAID)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

                switch result {
                case let .success(_, sw1, sw2):
                    if sw1 == 0x90, sw2 == 0x00 {
                        times.append(elapsed)
                        logFn?("  SELECT #\(i): \(String(format: "%.1f", elapsed))ms OK")
                    } else {
                        logFn?("  SELECT #\(i): FAIL (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                    }
                case let .failure(error):
                    logFn?("  SELECT #\(i): ERROR (\(error))")
                }
            }

            if !times.isEmpty {
                let mean = times.reduce(0, +) / Double(times.count)
                let pass = mean < 50
                logFn?("Mean SELECT: \(String(format: "%.1f", mean))ms \(pass ? "PASS" : "FAIL")")
            } else {
                logFn?("FAIL: No successful SELECT commands")
            }

            session.alertMessage = "AID Selection complete"
            session.invalidate()
            completionFn?()
        }

        // MARK: - Test C: APDU Round-Trip Latency

        private func testApduLatency(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            logFn?("=== Test C: APDU Latency ===")

            // SELECT diagnostic AID
            guard selectDiagnosticAid(tag: tag) else {
                session.invalidate(errorMessage: "AID selection failed")
                completionFn?()
                return
            }

            let payload = Data(repeating: 0x42, count: 20)
            var rtts: [Double] = []

            for i in 1 ... 10 {
                let start = CFAbsoluteTimeGetCurrent()
                let result = sendApduSync(tag: tag, ins: Self.insEcho, data: payload)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

                switch result {
                case let .success(data, sw1, sw2):
                    if sw1 == 0x90, sw2 == 0x00 {
                        rtts.append(elapsed)
                        logFn?("  RTT #\(i): \(String(format: "%.1f", elapsed))ms (resp=\(data.count) bytes)")
                    } else {
                        logFn?("  RTT #\(i): FAIL (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                    }
                case let .failure(error):
                    logFn?("  RTT #\(i): ERROR (\(error))")
                }
            }

            if !rtts.isEmpty {
                let mean = rtts.reduce(0, +) / Double(rtts.count)
                let pass = mean < 100
                logFn?("Mean RTT: \(String(format: "%.1f", mean))ms (\(rtts.count)/10 ok) \(pass ? "PASS" : "FAIL")")
            } else {
                logFn?("FAIL: No successful APDUs")
            }

            session.alertMessage = "Latency test complete"
            session.invalidate()
            completionFn?()
        }

        // MARK: - Test D: Max Payload

        private func testMaxPayload(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            logFn?("=== Test D: Max Payload ===")

            guard selectDiagnosticAid(tag: tag) else {
                session.invalidate(errorMessage: "AID selection failed")
                completionFn?()
                return
            }

            let sizes = [16, 64, 128, 200, 255]
            var maxSuccess = 0

            for size in sizes {
                var payload = Data(count: size)
                for i in 0 ..< size {
                    payload[i] = UInt8(i % 256)
                }

                let start = CFAbsoluteTimeGetCurrent()
                let result = sendApduSync(tag: tag, ins: Self.insPayloadTest, data: payload)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

                switch result {
                case let .success(data, sw1, sw2):
                    if sw1 == 0x90, sw2 == 0x00 {
                        let match = data == payload
                        logFn?("  \(size)B: \(String(format: "%.1f", elapsed))ms echo=\(match ? "match" : "MISMATCH(\(data.count))")")
                        if match { maxSuccess = size }
                    } else {
                        logFn?("  \(size)B: REJECTED (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                    }
                case let .failure(error):
                    logFn?("  \(size)B: ERROR (\(error))")
                }
            }

            let pass = maxSuccess >= 200
            logFn?("Max successful: \(maxSuccess)B \(pass ? "PASS" : "FAIL")")

            session.alertMessage = "Payload test complete"
            session.invalidate()
            completionFn?()
        }

        // MARK: - Test E: Throughput

        private func testThroughput(tag: NFCISO7816Tag, session: NFCTagReaderSession) {
            logFn?("=== Test E: Throughput ===")

            guard selectDiagnosticAid(tag: tag) else {
                session.invalidate(errorMessage: "AID selection failed")
                completionFn?()
                return
            }

            let chunkSize = 200
            let totalSizes = [1024, 5120, 10240]

            for totalSize in totalSizes {
                let chunks = (totalSize + chunkSize - 1) / chunkSize
                var sent = 0
                var failed = 0
                let start = CFAbsoluteTimeGetCurrent()

                for _ in 0 ..< chunks {
                    let remaining = totalSize - sent
                    let thisChunk = min(remaining, chunkSize)
                    var payload = Data(count: thisChunk)
                    for j in 0 ..< thisChunk {
                        payload[j] = UInt8(j % 256)
                    }

                    let result = sendApduSync(tag: tag, ins: Self.insPayloadTest, data: payload)
                    switch result {
                    case let .success(_, sw1, sw2):
                        if sw1 == 0x90, sw2 == 0x00 {
                            sent += thisChunk
                        } else {
                            failed += 1
                        }
                    case .failure:
                        failed += 1
                    }
                }

                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                let kbPerSec = elapsed > 0 ? (Double(sent) / elapsed) : 0

                logFn?("  \(totalSize / 1024)KB: \(String(format: "%.0f", elapsed))ms (\(String(format: "%.1f", kbPerSec)) KB/s, \(failed) failed)")
            }

            session.alertMessage = "Throughput test complete"
            session.invalidate()
            completionFn?()
        }

        // MARK: - APDU Helpers

        private func selectDiagnosticAid(tag: NFCISO7816Tag) -> Bool {
            let result = sendApduSync(tag: tag, ins: 0xA4, p1: 0x04, p2: 0x00, data: Self.diagnosticAID)
            switch result {
            case let .success(_, sw1, sw2):
                return sw1 == 0x90 && sw2 == 0x00
            case .failure:
                return false
            }
        }

        private enum ApduResult {
            case success(Data, UInt8, UInt8)
            case failure(String)
        }

        private func sendApduSync(
            tag: NFCISO7816Tag,
            ins: UInt8,
            p1: UInt8 = 0x00,
            p2: UInt8 = 0x00,
            data: Data
        ) -> ApduResult {
            let apdu = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: ins,
                p1Parameter: p1,
                p2Parameter: p2,
                data: data,
                expectedResponseLength: -1
            )

            let semaphore = DispatchSemaphore(value: 0)
            var resultData = Data()
            var resultSw1: UInt8 = 0
            var resultSw2: UInt8 = 0
            var resultError: String?

            tag.sendCommand(apdu: apdu) { data, sw1, sw2, error in
                if let error {
                    resultError = error.localizedDescription
                } else {
                    resultData = data
                    resultSw1 = sw1
                    resultSw2 = sw2
                }
                semaphore.signal()
            }

            _ = semaphore.wait(timeout: .now() + 5.0)

            if let error = resultError {
                return .failure(error)
            }
            return .success(resultData, resultSw1, resultSw2)
        }
    }

    #Preview {
        NavigationView {
            NfcDiagnosticView(autoTest: nil)
        }
    }
#endif
