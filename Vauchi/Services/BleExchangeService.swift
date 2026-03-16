// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreBluetooth
import Foundation

/// CoreBluetooth BLE exchange service for the ADR-031 command/event protocol.
///
/// Executes BLE ExchangeCommands (scan, connect, GATT read/write) using
/// CoreBluetooth and reports results back via a callback. The callback
/// creates MobileExchangeHardwareEvents for the session.
final class BleExchangeService: NSObject {
    /// Callback to report hardware events back to the exchange session.
    typealias EventCallback = (MobileExchangeHardwareEvent) -> Void

    private var centralManager: CBCentralManager?
    private var targetServiceUuid: CBUUID?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredCharacteristics: [String: CBCharacteristic] = [:]
    private var eventCallback: EventCallback?
    private var pendingWrite: (uuid: String, data: Data)?
    private var pendingRead: String?

    /// Initialize and start CoreBluetooth.
    func activate(callback: @escaping EventCallback) {
        eventCallback = callback
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Command Dispatch

    func startScanning(serviceUuid: String) {
        targetServiceUuid = CBUUID(string: serviceUuid)
        guard let cm = centralManager, cm.state == .poweredOn else {
            eventCallback?(.hardwareError(transport: "BLE", error: "Bluetooth not powered on"))
            return
        }
        cm.scanForPeripherals(withServices: [targetServiceUuid!], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
    }

    func startAdvertising(serviceUuid _: String) {
        // iOS apps cannot advertise as BLE peripherals in the background.
        // For exchange, we rely on one device scanning and the other advertising.
        // Peripheral mode requires CBPeripheralManager — defer for now.
        eventCallback?(.hardwareUnavailable(transport: "BLE-advertise"))
    }

    func connect(deviceId: String) {
        guard let peripheral = findPeripheral(id: deviceId) else {
            eventCallback?(.hardwareError(transport: "BLE", error: "Device \(deviceId) not found"))
            return
        }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    func writeCharacteristic(uuid: String, data: [UInt8]) {
        guard let peripheral = connectedPeripheral else {
            eventCallback?(.hardwareError(transport: "BLE", error: "No connected device"))
            return
        }
        let normalizedUuid = uuid.lowercased()
        guard let characteristic = discoveredCharacteristics[normalizedUuid] else {
            // Characteristic may not be discovered yet — queue the write
            pendingWrite = (uuid: normalizedUuid, data: Data(data))
            return
        }
        peripheral.writeValue(Data(data), for: characteristic, type: .withResponse)
    }

    func readCharacteristic(uuid: String) {
        guard let peripheral = connectedPeripheral else {
            eventCallback?(.hardwareError(transport: "BLE", error: "No connected device"))
            return
        }
        let normalizedUuid = uuid.lowercased()
        guard let characteristic = discoveredCharacteristics[normalizedUuid] else {
            pendingRead = normalizedUuid
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    // MARK: - Private

    private var discoveredPeripherals: [String: CBPeripheral] = [:]

    private func findPeripheral(id: String) -> CBPeripheral? {
        discoveredPeripherals[id]
    }

    private func cleanup() {
        connectedPeripheral = nil
        discoveredCharacteristics.removeAll()
        pendingWrite = nil
        pendingRead = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BleExchangeService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Ready — if we have a pending scan, start it
            if let uuid = targetServiceUuid {
                central.scanForPeripherals(withServices: [uuid], options: nil)
            }
        case .poweredOff, .unauthorized, .unsupported:
            eventCallback?(.hardwareUnavailable(transport: "BLE"))
        default:
            break
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier.uuidString
        discoveredPeripherals[id] = peripheral

        // Extract manufacturer data if available
        let advData: [UInt8] = if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            Array(mfgData)
        } else {
            []
        }

        eventCallback?(.bleDeviceDiscovered(
            id: id,
            rssi: Int16(RSSI.intValue),
            advData: advData
        ))
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        eventCallback?(.bleConnected(deviceId: peripheral.identifier.uuidString))
        // Discover GATT services
        peripheral.discoverServices(nil)
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        eventCallback?(.hardwareError(
            transport: "BLE",
            error: error?.localizedDescription ?? "Connection failed"
        ))
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error: Error?) {
        eventCallback?(.bleDisconnected(reason: error?.localizedDescription ?? "disconnected"))
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate

extension BleExchangeService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            eventCallback?(.hardwareError(transport: "BLE", error: "Service discovery failed: \(error!)"))
            return
        }
        // Discover characteristics for all services
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.lowercased()
            discoveredCharacteristics[uuid] = characteristic

            // Subscribe to notifications if supported
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        // Execute any pending operations now that characteristics are available
        if let pending = pendingWrite, let char = discoveredCharacteristics[pending.uuid] {
            peripheral.writeValue(pending.data, for: char, type: .withResponse)
            pendingWrite = nil
        }
        if let uuid = pendingRead, let char = discoveredCharacteristics[uuid] {
            peripheral.readValue(for: char)
            pendingRead = nil
        }
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.lowercased()
        let data = Array(value)

        if characteristic.isNotifying {
            eventCallback?(.bleCharacteristicNotified(uuid: uuid, data: data))
        } else {
            eventCallback?(.bleCharacteristicRead(uuid: uuid, data: data))
        }
    }

    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?) {
        if let error {
            eventCallback?(.hardwareError(
                transport: "BLE",
                error: "Write failed: \(error.localizedDescription)"
            ))
        }
    }
}
