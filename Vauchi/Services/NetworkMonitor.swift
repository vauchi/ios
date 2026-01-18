// NetworkMonitor.swift
// Network connectivity monitoring service for Vauchi iOS
// Uses NWPathMonitor for reliable network state detection

import Foundation
import Network
import Combine

/// Monitors network connectivity and provides current connection state
final class NetworkMonitor: ObservableObject {
    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device currently has network connectivity
    @Published private(set) var isConnected = false

    /// The type of network connection currently available
    @Published private(set) var connectionType: ConnectionType = .unknown

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

    // MARK: - Private Methods

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }

        // Start monitoring immediately
        start()
    }

    private func updateConnectionStatus(_ path: NWPath) {
        isConnected = path.status == .satisfied

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
