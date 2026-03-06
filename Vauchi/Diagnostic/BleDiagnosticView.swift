// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import CoreBluetooth
    import SwiftUI

    private let diagnosticServiceUUID = CBUUID(string: "a1b2c3d4-e5f6-7890-abcd-ef12345678A0")
    private let diagnosticCharUUID = CBUUID(string: "a1b2c3d4-e5f6-7890-abcd-ef12345678A1")

    struct BleDiagnosticView: View {
        @State private var logLines: [String] = []
        @State private var running = false

        var body: some View {
            VStack(spacing: 16) {
                Text("BLE Diagnostic")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    diagButton("A: Discovery") { testDiscovery() }
                    diagButton("B: MTU") { testMtuNegotiation() }
                    diagButton("C: Throughput") { testThroughput() }
                }

                HStack(spacing: 12) {
                    diagButton("D: Latency") { testLatency() }
                    diagButton("E: RSSI") { testRssiRange() }
                    diagButton("F: Stability") { testConnectionStability() }
                }

                if running {
                    ProgressView("Running...")
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
        }

        // MARK: - UI Helpers

        private func diagButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title) {
                runAsync(action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)
            .font(.caption)
        }

        private func runAsync(_ work: @escaping () -> Void) {
            DispatchQueue.main.async { running = true }
            DispatchQueue.global(qos: .userInitiated).async {
                work()
                DispatchQueue.main.async { running = false }
            }
        }

        private func log(_ msg: String) {
            let timestamped = "[\(timeStamp())] \(msg)"
            NSLog("[BLE Diag] %@", msg)
            DispatchQueue.main.async {
                logLines.append(timestamped)
            }
        }

        private func timeStamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }

        // MARK: - Test A: Discovery

        private func testDiscovery() {
            log("=== Test A: Discovery ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            log("Scanning for peers...")
            let semaphore = DispatchSemaphore(value: 0)
            var found = false

            manager.scan(timeout: 5.0, log: log) { name, rssi, services in
                log("Found: \(name ?? "unknown") RSSI=\(rssi) dBm services=\(services)")
                found = true
                semaphore.signal()
            }

            _ = semaphore.wait(timeout: .now() + 6.0)

            if found {
                log("PASS: peer discovered within 5s")
            } else {
                log("FAIL: no peer found within 5s")
            }

            manager.stopAll()
            log("=== Test A complete ===")
        }

        // MARK: - Test B: MTU Negotiation

        private func testMtuNegotiation() {
            log("=== Test B: MTU Negotiation ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            log("Connecting to peer...")
            let semaphore = DispatchSemaphore(value: 0)

            manager.connectAndDiscoverMtu(timeout: 10.0, log: log) { mtu in
                log("maximumWriteValueLength = \(mtu) bytes")
                if mtu >= 185 {
                    log("PASS: MTU >= 185")
                } else {
                    log("FAIL: MTU \(mtu) < 185")
                }
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 12.0) == .timedOut {
                log("FAIL: connection timed out")
            }

            manager.stopAll()
            log("=== Test B complete ===")
        }

        // MARK: - Test C: Throughput

        private func testThroughput() {
            log("=== Test C: Throughput ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            let semaphore = DispatchSemaphore(value: 0)

            manager.connectForThroughput(timeout: 10.0, log: log) { peripheral, characteristic in
                let sizes = [1024, 5120, 10240]
                for size in sizes {
                    let payload = randomBytes(count: size)
                    let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
                    let chunkSize = max(mtu, 20)

                    let start = CFAbsoluteTimeGetCurrent()
                    var offset = 0
                    while offset < payload.count {
                        let end = min(offset + chunkSize, payload.count)
                        let chunk = Data(payload[offset ..< end])
                        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                        offset = end
                    }
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let kbPerSec = elapsed > 0 ? (Double(size) / 1024.0) / elapsed : 0

                    log("\(size / 1024)KB: \(String(format: "%.1f", elapsed))s = \(String(format: "%.1f", kbPerSec)) KB/s")
                }

                let finalSize = 10240
                let finalPayload = randomBytes(count: finalSize)
                let finalMtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
                let finalChunkSize = max(finalMtu, 20)
                let finalStart = CFAbsoluteTimeGetCurrent()
                var finalOffset = 0
                while finalOffset < finalPayload.count {
                    let end = min(finalOffset + finalChunkSize, finalPayload.count)
                    let chunk = Data(finalPayload[finalOffset ..< end])
                    peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                    finalOffset = end
                }
                let finalElapsed = CFAbsoluteTimeGetCurrent() - finalStart
                let finalKbPerSec = finalElapsed > 0 ? (Double(finalSize) / 1024.0) / finalElapsed : 0

                if finalKbPerSec >= 2.0 {
                    log("PASS: 10KB throughput >= 2 KB/s")
                } else {
                    log("FAIL: 10KB throughput \(String(format: "%.1f", finalKbPerSec)) KB/s < 2 KB/s")
                }

                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 30.0) == .timedOut {
                log("FAIL: throughput test timed out")
            }

            manager.stopAll()
            log("=== Test C complete ===")
        }

        // MARK: - Test D: Latency

        private func testLatency() {
            log("=== Test D: Latency ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            let semaphore = DispatchSemaphore(value: 0)

            manager.connectForLatency(timeout: 10.0, log: log) { peripheral, characteristic in
                let iterations = 10
                var totalMs: Double = 0
                let payload = Data(randomBytes(count: 20))

                for i in 1 ... iterations {
                    let writeSemaphore = DispatchSemaphore(value: 0)
                    let start = CFAbsoluteTimeGetCurrent()

                    manager.writeWithResponse(
                        peripheral: peripheral,
                        characteristic: characteristic,
                        data: payload
                    ) {
                        writeSemaphore.signal()
                    }

                    _ = writeSemaphore.wait(timeout: .now() + 2.0)
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                    totalMs += elapsed
                    log("RTT #\(i): \(String(format: "%.1f", elapsed)) ms")
                }

                let mean = totalMs / Double(iterations)
                log("Mean RTT: \(String(format: "%.1f", mean)) ms")
                if mean < 100.0 {
                    log("PASS: mean RTT < 100ms")
                } else {
                    log("FAIL: mean RTT \(String(format: "%.1f", mean)) ms >= 100ms")
                }

                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 30.0) == .timedOut {
                log("FAIL: latency test timed out")
            }

            manager.stopAll()
            log("=== Test D complete ===")
        }

        // MARK: - Test E: RSSI Range

        private func testRssiRange() {
            log("=== Test E: RSSI Range ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            let semaphore = DispatchSemaphore(value: 0)

            manager.connectForRssi(timeout: 10.0, log: log) { peripheral in
                log("Reading RSSI every 500ms for 10s...")
                var readings: [Int] = []
                let readingsLock = NSLock()

                for i in 0 ..< 20 {
                    let rssiSemaphore = DispatchSemaphore(value: 0)

                    manager.readRssi(peripheral: peripheral) { rssi in
                        readingsLock.lock()
                        readings.append(rssi)
                        readingsLock.unlock()
                        log("RSSI #\(i + 1): \(rssi) dBm")
                        rssiSemaphore.signal()
                    }

                    _ = rssiSemaphore.wait(timeout: .now() + 2.0)
                    Thread.sleep(forTimeInterval: 0.5)
                }

                readingsLock.lock()
                let allReadings = readings
                readingsLock.unlock()

                if allReadings.isEmpty {
                    log("FAIL: no RSSI readings")
                } else {
                    let minRssi = allReadings.min()!
                    let maxRssi = allReadings.max()!
                    let avg = allReadings.reduce(0, +) / allReadings.count
                    log("RSSI: min=\(minRssi) max=\(maxRssi) avg=\(avg) dBm")

                    let stable = allReadings.allSatisfy { $0 > -80 }
                    if stable {
                        log("PASS: all RSSI > -80 dBm")
                    } else {
                        let weak = allReadings.filter { $0 <= -80 }.count
                        log("FAIL: \(weak)/\(allReadings.count) readings <= -80 dBm")
                    }
                }

                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 25.0) == .timedOut {
                log("FAIL: RSSI test timed out")
            }

            manager.stopAll()
            log("=== Test E complete ===")
        }

        // MARK: - Test F: Connection Stability

        private func testConnectionStability() {
            log("=== Test F: Connection Stability ===")
            let manager = BleDiagnosticManager()
            manager.startPeripheral(log: log)
            Thread.sleep(forTimeInterval: 0.5)

            let semaphore = DispatchSemaphore(value: 0)

            manager.connectForStability(timeout: 10.0, log: log) { peripheral, characteristic in
                log("Holding connection for 30s, pinging every 1s...")
                var drops = 0
                let payload = Data(randomBytes(count: 4))

                for i in 1 ... 30 {
                    let pingSemaphore = DispatchSemaphore(value: 0)
                    var pingOk = false

                    manager.writeWithResponse(
                        peripheral: peripheral,
                        characteristic: characteristic,
                        data: payload
                    ) {
                        pingOk = true
                        pingSemaphore.signal()
                    }

                    if pingSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
                        pingOk = false
                    }

                    if !pingOk {
                        drops += 1
                        log("Ping #\(i): DROP")
                    } else if i % 5 == 0 {
                        log("Ping #\(i): OK")
                    }

                    Thread.sleep(forTimeInterval: 1.0)
                }

                log("Drops: \(drops)/30")
                if drops == 0 {
                    log("PASS: 0 drops in 30s")
                } else {
                    log("FAIL: \(drops) drops in 30s")
                }

                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 50.0) == .timedOut {
                log("FAIL: stability test timed out")
            }

            manager.stopAll()
            log("=== Test F complete ===")
        }

        // MARK: - Helpers

        private func randomBytes(count: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: count)
            _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
            return bytes
        }
    }

    // MARK: - BLE Diagnostic Manager

    /// Coordinator that owns CBCentralManager and CBPeripheralManager, conforming
    /// to the required delegates. Lives on the heap so callbacks work correctly.
    private class BleDiagnosticManager: NSObject,
        CBCentralManagerDelegate,
        CBPeripheralDelegate,
        CBPeripheralManagerDelegate {
        private var centralManager: CBCentralManager?
        private var peripheralManager: CBPeripheralManager?
        private var discoveredPeripheral: CBPeripheral?
        private var discoveredCharacteristic: CBCharacteristic?

        private var logFn: ((String) -> Void)?

        // Dedicated queue for CoreBluetooth callbacks — must NOT be blocked by semaphores
        private let cbQueue = DispatchQueue(label: "app.vauchi.ble.diagnostic.cb", qos: .userInitiated)
        private let cbPeripheralQueue = DispatchQueue(label: "app.vauchi.ble.diagnostic.peripheral", qos: .userInitiated)

        // Callbacks
        private var onDiscovered: ((String?, Int, [CBUUID]) -> Void)?
        private var onConnected: (() -> Void)?
        private var onServicesDiscovered: (() -> Void)?
        private var onCharacteristicsDiscovered: (() -> Void)?
        private var onMtuReady: ((Int) -> Void)?
        private var onWriteComplete: (() -> Void)?
        private var onRssiRead: ((Int) -> Void)?
        private var onDisconnected: (() -> Void)?

        // State tracking
        private var centralReady = false
        private var peripheralReady = false
        private let readySemaphore = DispatchSemaphore(value: 0)
        private let peripheralReadySemaphore = DispatchSemaphore(value: 0)

        // MARK: - Peripheral (Advertiser) Setup

        func startPeripheral(log: @escaping (String) -> Void) {
            logFn = log
            peripheralManager = CBPeripheralManager(delegate: self, queue: cbPeripheralQueue)
            _ = peripheralReadySemaphore.wait(timeout: .now() + 3.0)

            guard peripheralReady else {
                log("Peripheral manager not ready")
                return
            }

            let characteristic = CBMutableCharacteristic(
                type: diagnosticCharUUID,
                properties: [.write, .writeWithoutResponse, .read, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )

            let service = CBMutableService(type: diagnosticServiceUUID, primary: true)
            service.characteristics = [characteristic]

            peripheralManager?.add(service)
            peripheralManager?.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [diagnosticServiceUUID],
                CBAdvertisementDataLocalNameKey: "Vauchi-Diag",
            ])
            log("Advertising as Vauchi-Diag")
        }

        // MARK: - Central (Scanner) Operations

        private func ensureCentral() {
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: cbQueue)
                _ = readySemaphore.wait(timeout: .now() + 3.0)
            }
        }

        func scan(timeout: TimeInterval, log: @escaping (String) -> Void, onFound: @escaping (String?, Int, [CBUUID]) -> Void) {
            logFn = log
            ensureCentral()

            guard centralReady else {
                log("Central not ready (Bluetooth off?)")
                return
            }

            onDiscovered = onFound
            centralManager?.scanForPeripherals(
                withServices: [diagnosticServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.centralManager?.stopScan()
            }
        }

        func connectAndDiscoverMtu(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (Int) -> Void) {
            logFn = log
            ensureCentral()

            guard centralReady else {
                log("Central not ready")
                return
            }

            onDiscovered = { [weak self] name, _, _ in
                guard let self, let peripheral = discoveredPeripheral else { return }
                onDiscovered = nil
                log("Connecting to \(name ?? "peer")...")
                onConnected = {
                    peripheral.discoverServices([diagnosticServiceUUID])
                }
                onServicesDiscovered = {
                    if let svc = peripheral.services?.first(where: { $0.uuid == diagnosticServiceUUID }) {
                        peripheral.discoverCharacteristics([diagnosticCharUUID], for: svc)
                    }
                }
                onCharacteristicsDiscovered = {
                    let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
                    DispatchQueue.global(qos: .userInitiated).async {
                        completion(mtu)
                    }
                }
                centralManager?.connect(peripheral, options: nil)
            }

            centralManager?.scanForPeripherals(
                withServices: [diagnosticServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.centralManager?.stopScan()
            }
        }

        func connectForThroughput(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (CBPeripheral, CBCharacteristic) -> Void) {
            connectAndGetCharacteristic(timeout: timeout, log: log, completion: completion)
        }

        func connectForLatency(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (CBPeripheral, CBCharacteristic) -> Void) {
            connectAndGetCharacteristic(timeout: timeout, log: log, completion: completion)
        }

        func connectForRssi(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (CBPeripheral) -> Void) {
            connectAndGetCharacteristic(timeout: timeout, log: log) { peripheral, _ in
                completion(peripheral)
            }
        }

        func connectForStability(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (CBPeripheral, CBCharacteristic) -> Void) {
            connectAndGetCharacteristic(timeout: timeout, log: log, completion: completion)
        }

        private func connectAndGetCharacteristic(timeout: TimeInterval, log: @escaping (String) -> Void, completion: @escaping (CBPeripheral, CBCharacteristic) -> Void) {
            logFn = log
            ensureCentral()

            guard centralReady else {
                log("Central not ready")
                return
            }

            onDiscovered = { [weak self] name, _, _ in
                guard let self, let peripheral = discoveredPeripheral else { return }
                onDiscovered = nil
                log("Connecting to \(name ?? "peer")...")

                onConnected = {
                    peripheral.discoverServices([diagnosticServiceUUID])
                }
                onServicesDiscovered = {
                    if let svc = peripheral.services?.first(where: { $0.uuid == diagnosticServiceUUID }) {
                        peripheral.discoverCharacteristics([diagnosticCharUUID], for: svc)
                    }
                }
                onCharacteristicsDiscovered = { [weak self] in
                    guard let self, let char = discoveredCharacteristic else {
                        log("No characteristic found")
                        return
                    }
                    // Dispatch off the CB queue so semaphore.wait() doesn't block callbacks
                    DispatchQueue.global(qos: .userInitiated).async {
                        completion(peripheral, char)
                    }
                }
                centralManager?.connect(peripheral, options: nil)
            }

            centralManager?.scanForPeripherals(
                withServices: [diagnosticServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.centralManager?.stopScan()
            }
        }

        func writeWithResponse(peripheral: CBPeripheral, characteristic: CBCharacteristic, data: Data, completion: @escaping () -> Void) {
            onWriteComplete = completion
            NSLog("[BLE Diag] writeWithResponse len=%d", data.count)
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }

        func readRssi(peripheral: CBPeripheral, completion: @escaping (Int) -> Void) {
            onRssiRead = completion
            peripheral.readRSSI()
        }

        func stopAll() {
            centralManager?.stopScan()
            if let peripheral = discoveredPeripheral {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            peripheralManager?.stopAdvertising()
            peripheralManager?.removeAllServices()

            centralManager = nil
            peripheralManager = nil
            discoveredPeripheral = nil
            discoveredCharacteristic = nil
            centralReady = false
            peripheralReady = false
        }

        // MARK: - CBCentralManagerDelegate

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            if central.state == .poweredOn {
                centralReady = true
            } else {
                centralReady = false
                logFn?("Central state: \(central.state.rawValue)")
            }
            readySemaphore.signal()
        }

        func centralManager(
            _: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber
        ) {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

            discoveredPeripheral = peripheral
            peripheral.delegate = self
            onDiscovered?(name, RSSI.intValue, serviceUUIDs)
        }

        func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
            NSLog("[BLE Diag] didConnect to %@", peripheral.identifier.uuidString)
            centralManager?.stopScan()
            onConnected?()
        }

        func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
            logFn?("Connection failed: \(error?.localizedDescription ?? "unknown")")
        }

        func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {
            onDisconnected?()
        }

        // MARK: - CBPeripheralDelegate

        func peripheral(_: CBPeripheral, didDiscoverServices _: Error?) {
            onServicesDiscovered?()
        }

        func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error _: Error?) {
            if let char = service.characteristics?.first(where: { $0.uuid == diagnosticCharUUID }) {
                discoveredCharacteristic = char
                NSLog("[BLE Diag] Found characteristic, properties=%lu", char.properties.rawValue)
            }
            onCharacteristicsDiscovered?()
        }

        func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?) {
            NSLog("[BLE Diag] didWriteValueFor called, error=%@", error?.localizedDescription ?? "nil")
            if let error {
                logFn?("Write error: \(error.localizedDescription)")
            }
            onWriteComplete?()
        }

        func peripheral(_: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
            if let error {
                logFn?("RSSI error: \(error.localizedDescription)")
                onRssiRead?(-127)
            } else {
                onRssiRead?(RSSI.intValue)
            }
        }

        // MARK: - CBPeripheralManagerDelegate

        func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            if peripheral.state == .poweredOn {
                peripheralReady = true
            } else {
                peripheralReady = false
                logFn?("Peripheral state: \(peripheral.state.rawValue)")
            }
            peripheralReadySemaphore.signal()
        }

        func peripheralManager(_: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            for request in requests {
                peripheralManager?.respond(to: request, withResult: .success)
            }
        }

        func peripheralManager(_: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            request.value = Data([0x00])
            peripheralManager?.respond(to: request, withResult: .success)
        }
    }

    #Preview {
        NavigationView {
            BleDiagnosticView()
        }
    }
#endif
