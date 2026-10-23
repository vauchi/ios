// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Network connectivity monitoring service for Vauchi iOS
// Uses NWPathMonitor for reliable network state detection

import Combine
import Foundation
import Network
import VauchiPlatform

/// Monitors network connectivity and provides current connection state
final class NetworkMonitor: ObservableObject {
    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device currently has network connectivity
    @Published private(set) var isConnected = false

    /// The type of network connection currently available
    @Published private(set) var connectionType: ConnectionType = .unknown

    /// What a download costs on the current path, for Core's content
    /// updates (private#733, D6)
    @Published private(set) var cost: MobileNetworkCost = .unknown

    // MARK: - Connection Types

    /// Types of network connections
    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "app.vauchi.networkmonitor")

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        setupMonitor()
    }

    // MARK: - Public Methods

    /// Start monitoring network changes
    func start() {
        monitor.start(queue: queue)
    }

    /// Stop monitoring network changes
    func stop() {
        monitor.cancel()
    }

    /// The cost of the path right now, for a background wakeup that runs
    /// before any update reached the published `cost`
    func currentCost() -> MobileNetworkCost {
        Self.cost(of: monitor.currentPath)
    }

    static func cost(isSatisfied: Bool, isExpensive: Bool, isConstrained: Bool) -> MobileNetworkCost {
        guard isSatisfied else { return .unknown }
        return isExpensive || isConstrained ? .metered : .unmetered
    }

    private static func cost(of path: NWPath) -> MobileNetworkCost {
        cost(
            isSatisfied: path.status == .satisfied,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    // MARK: - Private Methods

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }

        start()
    }

    private func updateConnectionStatus(_ path: NWPath) {
        isConnected = path.status == .satisfied
        cost = Self.cost(of: path)

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wired
        } else {
            connectionType = .unknown
        }
    }
}
