// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreImage
import CoreVideo
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Saves diagnostic JPEG snapshots and JSON sidecar metadata from camera frames.
enum DiagnosticCapture {
    private static let logger = Logger(
        subsystem: "com.vauchi.qrtuner",
        category: "capture"
    )

    /// Save a JPEG snapshot from a pixel buffer with optional redaction.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The `CVPixelBuffer` from the video output.
    ///   - frameIndex: Index of this frame in the sweep.
    ///   - decodeResult: Whether the QR code was decoded in this frame.
    ///   - configId: Camera configuration ID being tested.
    ///   - sessionId: Unique session identifier for directory naming.
    ///   - redactionRect: Optional `CGRect` to black out (e.g., face region).
    static func saveSnapshot(
        pixelBuffer: CVPixelBuffer,
        frameIndex: Int,
        decodeResult: Bool,
        configId: UInt32,
        sessionId: String,
        redactionRect: CGRect? = nil
    ) {
        let ciImage: CIImage
        let raw = CIImage(cvPixelBuffer: pixelBuffer)

        if let rect = redactionRect {
            let blackRect = CIImage(color: .black).cropped(to: rect)
            ciImage = blackRect.composited(over: raw)
        } else {
            ciImage = raw
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            logger.error("Failed to create CGImage from pixel buffer")
            return
        }

        let dir = snapshotDirectory(sessionId: sessionId)
        createDirectoryIfNeeded(dir)

        let filename = String(format: "config_%04d_frame_%04d.jpg", configId, frameIndex)
        let filePath = dir.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(
            filePath as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            logger.error("Failed to create image destination at \(filePath.path)")
            return
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            logger.error("Failed to finalize JPEG at \(filePath.path)")
            return
        }

        // JSON sidecar
        let sidecar: [String: Any] = [
            "config_id": configId,
            "frame_index": frameIndex,
            "decoded": decodeResult,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        let sidecarPath = dir.appendingPathComponent(
            String(format: "config_%04d_frame_%04d.json", configId, frameIndex)
        )

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: sidecar, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? jsonData.write(to: sidecarPath)
        }

        logger.debug("Saved snapshot: \(filename) decoded=\(decodeResult)")
    }

    // MARK: - Private

    private static func snapshotDirectory(sessionId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
            .appendingPathComponent("diagnostic")
            .appendingPathComponent("tuner")
            .appendingPathComponent("session_\(sessionId)")
            .appendingPathComponent("snapshots")
    }

    private static func createDirectoryIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
    }
}
