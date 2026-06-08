// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreBluetooth
import Foundation
import VauchiPlatform

/// CoreBluetooth BLE exchange service for the ADR-031 command/event protocol.
///
/// Executes BLE `ExchangeCommand`s as **both** central (initiator) and
/// peripheral (responder) and reports `MobileEvent`s back via a callback. Core
/// owns the protocol, crypto and role tiebreak (P1–P4); this service is a thin
/// transport bridge. P5c: the role token rides as a 32-bit service UUID (see
/// `BleUuids`), since iOS can't advertise service/manufacturer data.
final class BleExchangeService: NSObject {
    /// Callback to report hardware events back to the exchange session.
    typealias EventCallback = (MobileEvent) -> Void

    private var eventCallback: EventCallback?

    // MARK: Central (initiator)

    private var centralManager: CBCentralManager?
    private var targetService: CBUUID?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredCharacteristics: [String: CBCharacteristic] = [:]
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var pendingWrite: (uuid: String, data: Data)?
    private var pendingRead: String?

    // MARK: Peripheral (responder)

    private var peripheralManager: CBPeripheralManager?
    private var gattCharacteristics: [String: CBMutableCharacteristic] = [:]
    private var subscribedCentrals: Set<UUID> = []
    private var pendingAdvertise: (service: String, token: Data)?

    /// Initialize and start the central manager. The peripheral manager is
    /// created lazily on the first advertise command.
    func activate(callback: @escaping EventCallback) {
        eventCallback = callback
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Command dispatch

    func startScanning(serviceUuid: String) {
        let service = CBUUID(string: serviceUuid)
        targetService = service
        // Re-armed by `centralManagerDidUpdateState` once powered on.
        guard let cm = centralManager, cm.state == .poweredOn else { return }
        cm.scanForPeripherals(
            withServices: [service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager?.stopScan()
    }

    func startAdvertising(serviceUuid: String, payload: Data) {
        pendingAdvertise = (service: serviceUuid, token: payload)
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: .global(qos: .userInitiated))
        } else if peripheralManager?.state == .poweredOn {
            startAdvertisingNow()
        }
    }

    func connect(deviceId: String) {
        guard let peripheral = discoveredPeripherals[deviceId] else {
            eventCallback?(.hardwareError(transport: "BLE", error: "Device \(deviceId) not found"))
            return
        }
        centralManager?.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    /// Route a `BleWriteCharacteristic`: a responder-notify characteristic is a
    /// peripheral push (`updateValue`); anything else is a central GATT write.
    /// Mirrors Android's `MainActivity` write routing.
    func writeCharacteristic(uuid: String, data: Data) {
        let normalized = uuid.lowercased()
        if BleUuids.peripheralNotifyChars.contains(uuid), let ch = gattCharacteristics[normalized] {
            ch.value = data
            _ = peripheralManager?.updateValue(data, for: ch, onSubscribedCentrals: nil)
            return
        }
        guard let peripheral = connectedPeripheral else {
            eventCallback?(.hardwareError(transport: "BLE", error: "No connected device"))
            return
        }
        guard let characteristic = discoveredCharacteristics[normalized] else {
            pendingWrite = (uuid: normalized, data: data)
            return
        }
        let type: CBCharacteristicWriteType =
            BleUuids.writeWithResponse.contains(uuid) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    func readCharacteristic(uuid: String) {
        guard let peripheral = connectedPeripheral else {
            eventCallback?(.hardwareError(transport: "BLE", error: "No connected device"))
            return
        }
        let normalized = uuid.lowercased()
        guard let characteristic = discoveredCharacteristics[normalized] else {
            pendingRead = normalized
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.stopAdvertising()
        cleanup()
    }

    // MARK: - Private

    /// Build the responder GATT server (all exchange characteristics) and
    /// advertise the 128-bit service UUID + the 32-bit role-token UUID.
    private func startAdvertisingNow() {
        guard let pm = peripheralManager, pm.state == .poweredOn, let pending = pendingAdvertise else {
            return
        }
        pm.stopAdvertising()
        pm.removeAllServices()
        gattCharacteristics.removeAll()

        let serviceUUID = CBUUID(string: pending.service)
        let service = CBMutableService(type: serviceUUID, primary: true)
        var chars: [CBMutableCharacteristic] = []
        for uuid in BleUuids.allCharacteristics {
            var props: CBCharacteristicProperties = []
            var perms: CBAttributePermissions = []
            if uuid == BleUuids.exchangePayload {
                props.insert(.read); perms.insert(.readable)
            }
            if BleUuids.writeWithResponse.contains(uuid) {
                props.insert(.write); perms.insert(.writeable)
            }
            if uuid == BleUuids.dataWrite {
                props.insert(.writeWithoutResponse); perms.insert(.writeable)
            }
            if BleUuids.notifyCharacteristics.contains(uuid) {
                props.insert(.notify)
            }
            let ch = CBMutableCharacteristic(
                type: CBUUID(string: uuid), properties: props, value: nil, permissions: perms
            )
            chars.append(ch)
            gattCharacteristics[uuid.lowercased()] = ch
        }
        service.characteristics = chars
        pm.add(service)
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [
                serviceUUID, BleUuids.tokenToServiceUUID(pending.token),
            ],
        ])
    }

    private func cleanup() {
        connectedPeripheral = nil
        discoveredCharacteristics.removeAll()
        pendingWrite = nil
        pendingRead = nil
        subscribedCentrals.removeAll()
    }
}

// MARK: - CBCentralManagerDelegate

extension BleExchangeService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let service = targetService {
                central.scanForPeripherals(
                    withServices: [service],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        case .unauthorized:
            targetService = nil
            cleanup()
            eventCallback?(.permissionDenied(transport: "BLE"))
        case .poweredOff, .unsupported:
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

        // P5c: the peer advertises its role token as a 32-bit service UUID
        // alongside the 128-bit service UUID. Deliver its bytes as the
        // discovery event's adv_data; core compares and decides who connects.
        // Wait for an advert that carries the token UUID.
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        guard let token = uuids.lazy.compactMap({ BleUuids.tokenFromServiceUUID($0) }).first else {
            return
        }
        eventCallback?(.bleDeviceDiscovered(
            id: id, rssi: Int16(truncatingIfNeeded: RSSI.intValue), advData: token
        ))
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        eventCallback?(.bleConnected(deviceId: peripheral.identifier.uuidString))
        peripheral.discoverServices(nil)
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        eventCallback?(.hardwareError(
            transport: "BLE", error: error?.localizedDescription ?? "Connection failed"
        ))
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error: Error?) {
        eventCallback?(.bleDisconnected(reason: error?.localizedDescription ?? "disconnected"))
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate (central side — talking to the peer's GATT)

extension BleExchangeService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            eventCallback?(.hardwareError(transport: "BLE", error: "Service discovery failed: \(error!)"))
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.lowercased()
            discoveredCharacteristics[uuid] = characteristic
            if characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if let pending = pendingWrite, let char = discoveredCharacteristics[pending.uuid] {
            let type: CBCharacteristicWriteType =
                BleUuids.writeWithResponse.contains(pending.uuid) ? .withResponse : .withoutResponse
            peripheral.writeValue(pending.data, for: char, type: type)
            pendingWrite = nil
        }
        if let uuid = pendingRead, let char = discoveredCharacteristics[uuid] {
            peripheral.readValue(for: char)
            pendingRead = nil
        }
    }

    func peripheral(
        _: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.lowercased()
        if characteristic.isNotifying {
            eventCallback?(.bleCharacteristicNotified(uuid: uuid, data: value))
        } else {
            eventCallback?(.bleCharacteristicRead(uuid: uuid, data: value))
        }
    }

    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?) {
        if let error {
            eventCallback?(.hardwareError(transport: "BLE", error: "Write failed: \(error.localizedDescription)"))
        }
    }
}

// MARK: - CBPeripheralManagerDelegate (responder side — our GATT server)

extension BleExchangeService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            startAdvertisingNow()
        case .unauthorized:
            eventCallback?(.permissionDenied(transport: "BLE"))
        case .poweredOff, .unsupported:
            eventCallback?(.hardwareUnavailable(transport: "BLE"))
        default:
            break
        }
    }

    /// A central subscribed to one of our NOTIFY characteristics — for the
    /// exchange this is effectively "connected". Mirrors Android's
    /// peripheral-side `onConnected` on the first subscription.
    func peripheralManager(
        _: CBPeripheralManager, central: CBCentral, didSubscribeTo _: CBCharacteristic
    ) {
        let id = central.identifier
        if subscribedCentrals.insert(id).inserted {
            eventCallback?(.bleConnected(deviceId: id.uuidString))
        }
    }

    func peripheralManager(
        _: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom _: CBCharacteristic
    ) {
        subscribedCentrals.remove(central.identifier)
    }

    /// The initiator wrote to one of our characteristics — surface it as
    /// received data for core's responder machine.
    func peripheralManager(
        _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            if let value = request.value {
                eventCallback?(.bleCharacteristicNotified(
                    uuid: request.characteristic.uuid.uuidString.lowercased(), data: value
                ))
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    /// The initiator read our EXCHANGE_PAYLOAD characteristic (legacy path).
    func peripheralManager(
        _ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest
    ) {
        let uuid = request.characteristic.uuid.uuidString.lowercased()
        request.value = gattCharacteristics[uuid]?.value ?? Data()
        peripheral.respond(to: request, withResult: .success)
    }
}
