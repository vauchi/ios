// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreBluetooth
import VauchiMobile

/// iOS implementation of the core BLE delegate interface.
///
/// Core calls these methods to instruct the platform to perform BLE operations.
/// The iOS app pushes events back to core via `MobileBleExchangeSession`.
class IOSBleDelegate: MobileBleDelegate {
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripheralManager: CBPeripheralManager?
    private let onStateChangedCallback: (MobileBleState) -> Void
    private let onCompleteCallback: (MobileBleExchangeResult) -> Void
    private let onFailedCallback: (String) -> Void

    init(
        centralManager: CBCentralManager?,
        peripheral: CBPeripheral?,
        peripheralManager: CBPeripheralManager?,
        onStateChanged: @escaping (MobileBleState) -> Void,
        onComplete: @escaping (MobileBleExchangeResult) -> Void,
        onFailed: @escaping (String) -> Void
    ) {
        self.centralManager = centralManager
        self.peripheral = peripheral
        self.peripheralManager = peripheralManager
        onStateChangedCallback = onStateChanged
        onCompleteCallback = onComplete
        onFailedCallback = onFailed
    }

    func sendData(characteristicUuid: String, data: Data) throws {
        guard let peripheral else {
            throw MobileBleTransportError.connectionLost
        }
        let uuid = CBUUID(string: characteristicUuid)

        guard let service = peripheral.services?.first(where: { svc in
            svc.characteristics?.contains(where: { $0.uuid == uuid }) ?? false
        }),
            let characteristic = service.characteristics?.first(where: { $0.uuid == uuid }) else {
            throw MobileBleTransportError.transportFailed(msg: "Characteristic \(characteristicUuid) not found")
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        NSLog("[Vauchi] [BLE] Sent \(data.count) bytes to \(characteristicUuid)")
    }

    func subscribeNotify(characteristicUuid: String) throws {
        guard let peripheral else {
            throw MobileBleTransportError.connectionLost
        }
        let uuid = CBUUID(string: characteristicUuid)

        guard let service = peripheral.services?.first(where: { svc in
            svc.characteristics?.contains(where: { $0.uuid == uuid }) ?? false
        }),
            let characteristic = service.characteristics?.first(where: { $0.uuid == uuid }) else {
            throw MobileBleTransportError.transportFailed(msg: "Characteristic \(characteristicUuid) not found")
        }

        peripheral.setNotifyValue(true, for: characteristic)
    }

    func disconnect() throws {
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    func onStateChanged(state: MobileBleState) {
        DispatchQueue.main.async { self.onStateChangedCallback(state) }
    }

    func onExchangeComplete(result: MobileBleExchangeResult) {
        DispatchQueue.main.async { self.onCompleteCallback(result) }
    }

    func onExchangeFailed(error: String) {
        NSLog("[Vauchi] [BLE] Exchange failed: \(error)")
        DispatchQueue.main.async { self.onFailedCallback(error) }
    }
}
