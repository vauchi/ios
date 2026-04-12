// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import VauchiPlatform

/// TCP server for USB cable exchange (ADR-031).
///
/// The phone acts as the TCP responder: listens on a fixed port for the
/// desktop to connect, exchanges VXCH-framed payloads, then reports the
/// peer payload back to core via the hardware-event callback.
///
/// Uses POSIX BSD sockets (synchronous, run on a background queue) so that
/// the same VXCH framing code can be shared verbatim with the macOS client.
///
/// VXCH wire format: [4 bytes magic "VXCH"] [1 byte version] [4 bytes BE length] [payload]
final class DirectSendService {
    static let defaultPort: UInt16 = 19283

    typealias EventCallback = (MobileExchangeHardwareEvent) -> Void

    private var eventCallback: EventCallback?
    private var listenerSocket: Int32 = -1

    func setEventCallback(_ callback: @escaping EventCallback) {
        eventCallback = callback
    }

    /// Execute exchange -- responder listens for an incoming desktop connection.
    ///
    /// `isInitiator` is reserved for future symmetric use; the phone is
    /// always the TCP responder in the USB-cable exchange flow.
    func exchange(payload: [UInt8], isInitiator: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if isInitiator {
                self?.reportError("DirectSend initiator mode not supported on iOS")
            } else {
                self?.performResponder(payload: payload)
            }
        }
    }

    /// Cancel any in-progress listen by closing the listener socket.
    func cancel() {
        let fd = listenerSocket
        if fd >= 0 {
            listenerSocket = -1
            close(fd)
        }
    }

    // MARK: - Responder (TCP server)

    private func performResponder(payload: [UInt8]) {
        guard !payload.isEmpty else {
            reportError("empty payload")
            return
        }

        // Create listening socket.
        let listenFd = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFd >= 0 else {
            reportError("socket() failed: \(errno)")
            return
        }
        listenerSocket = listenFd
        defer {
            if listenerSocket == listenFd {
                listenerSocket = -1
            }
            close(listenFd)
        }

        // SO_REUSEADDR for quick rebind after previous session.
        var reuseAddr: Int32 = 1
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Bind to any interface on the exchange port.
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.defaultPort.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            reportError("bind() failed: \(errno)")
            return
        }

        guard Darwin.listen(listenFd, 1) == 0 else {
            reportError("listen() failed: \(errno)")
            return
        }

        // Block until desktop connects (or cancel() closes the fd).
        var clientAddr = sockaddr_in()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenFd, $0, &clientAddrLen)
            }
        }
        guard clientFd >= 0 else {
            // accept() returns EBADF / EINVAL when cancel() closes the fd.
            if errno == EBADF || errno == EINVAL {
                return // silently cancelled
            }
            reportError("accept() failed: \(errno)")
            return
        }
        defer { close(clientFd) }

        // 10-second I/O timeout -- prevents hanging on a stalled desktop.
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // VXCH framing: recv desktop payload first, then send ours.
        do {
            let theirPayload = try recvVxch(sock: clientFd)
            try sendVxch(sock: clientFd, payload: payload)

            DispatchQueue.main.async { [weak self] in
                self?.eventCallback?(.directPayloadReceived(data: Data(theirPayload)))
            }
        } catch {
            reportError("exchange failed: \(error.localizedDescription)")
        }
    }

    // MARK: - VXCH framing

    private static let magic: [UInt8] = [0x56, 0x58, 0x43, 0x48] // "VXCH"
    private static let version: UInt8 = 1
    private static let maxPayload: UInt32 = 65_536

    private func sendVxch(sock: Int32, payload: [UInt8]) throws {
        guard !payload.isEmpty else { throw VxchError.emptyPayload }
        var header = Self.magic
        header.append(Self.version)
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { header.append(contentsOf: $0) }

        try sendAll(sock: sock, data: header)
        try sendAll(sock: sock, data: payload)
    }

    private func recvVxch(sock: Int32) throws -> [UInt8] {
        // Header: 4 magic + 1 version + 4 length = 9 bytes
        let header = try recvExact(sock: sock, count: 9)
        guard Array(header[0 ..< 4]) == Self.magic else {
            throw VxchError.invalidMagic
        }
        guard header[4] == Self.version else {
            throw VxchError.unsupportedVersion
        }
        let len = UInt32(bigEndian: header[5 ..< 9].withUnsafeBytes { $0.load(as: UInt32.self) })
        guard len > 0, len <= Self.maxPayload else {
            throw VxchError.invalidLength(len)
        }
        return try recvExact(sock: sock, count: Int(len))
    }

    private func sendAll(sock: Int32, data: [UInt8]) throws {
        var sent = 0
        while sent < data.count {
            let n = data[sent...].withUnsafeBytes {
                Darwin.send(sock, $0.baseAddress!, data.count - sent, 0)
            }
            guard n > 0 else { throw VxchError.sendFailed }
            sent += n
        }
    }

    private func recvExact(sock: Int32, count: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let n = buf[received...].withUnsafeMutableBytes {
                Darwin.recv(sock, $0.baseAddress!, count - received, 0)
            }
            guard n > 0 else { throw VxchError.recvFailed }
            received += n
        }
        return buf
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.eventCallback?(.hardwareError(transport: "USB", error: message))
        }
    }

    private enum VxchError: Error {
        case emptyPayload, invalidMagic, unsupportedVersion
        case invalidLength(UInt32), sendFailed, recvFailed
    }
}
