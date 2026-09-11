// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
@testable import Vauchi
import XCTest

/// Replays every entry of Core's screen catalog through the app's own
/// host composition and writes one PNG per screen and appearance. No
/// engine and no UI automation: the reducer and the SwiftUI views are
/// the ones the app ships.
///
/// Set `VAUCHI_SCREEN_CATALOG` to the fixture path and
/// `VAUCHI_SCREENSHOT_DIR` to the output directory (falls back to
/// XCTest attachments); the test skips when the catalog is unset.
@MainActor
final class ScreenCatalogRenderTests: XCTestCase {
    private static let canvas = CGSize(width: 390, height: 844)

    func testRendersEveryCatalogScreen() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let catalogPath = environment["VAUCHI_SCREEN_CATALOG"] else {
            throw XCTSkip("VAUCHI_SCREEN_CATALOG is unset")
        }
        let catalog = try ScreenCatalog.load(from: URL(fileURLWithPath: catalogPath))
        let sink = ScreenCatalogScreenshotSink(
            directory: environment["VAUCHI_SCREENSHOT_DIR"],
            test: self
        )

        var lightRenders: Set<Data> = []
        var failures: [String] = []
        for entry in catalog.screens {
            do {
                let state = try entry.reduce()
                for variant in ScreenCatalogRenderVariant.allCases {
                    let png = try render(state, variant: variant)
                    sink.store(png, name: entry.codeID + variant.fileSuffix)
                    if variant == .light {
                        lightRenders.insert(png)
                    }
                }
            } catch {
                failures.append("\(entry.codeID): \(error)")
            }
        }

        XCTAssertEqual(failures, [], "catalog entries that did not render")
        XCTAssertGreaterThanOrEqual(
            lightRenders.count, 3,
            "expected at least three distinct screens, catalog has \(catalog.screens.count)"
        )
        sink.finish()
    }

    /// Hosts the content in a window and snapshots the layer tree.
    /// `ImageRenderer` was tried first and drew every `.scroll` surface
    /// blank: it cannot render the UIKit-backed `ScrollView` the surface
    /// body sits in, so the bar and tab bar came out over an empty card.
    private func render(
        _ state: PresentationState,
        variant: ScreenCatalogRenderVariant
    ) throws -> Data {
        let content = PresentationHostContent(
            state: state,
            useFrontCamera: false,
            onCameraPermissionDenied: {},
            onEvent: { _, _ in },
            onDismissOverlay: {}
        )
        .background(Color(.systemBackground))
        .environment(\.sizeCategory, variant.sizeCategory)
        let host = UIHostingController(rootView: content)
        let window = Self.makeWindow()
        window.overrideUserInterfaceStyle = variant.interfaceStyle
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
            .image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        guard let png = image.pngData() else {
            throw ScreenCatalogRenderError.noImage(variant)
        }
        return png
    }

    private static func makeWindow() -> UIWindow {
        let frame = CGRect(origin: .zero, size: canvas)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else {
            return UIWindow(frame: frame)
        }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }
}

enum ScreenCatalogRenderError: Error {
    case noImage(ScreenCatalogRenderVariant)
}

enum ScreenCatalogRenderVariant: CaseIterable {
    case light
    case dark
    case large

    var fileSuffix: String {
        switch self {
        case .light: ".png"
        case .dark: ".dark.png"
        case .large: ".large.png"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }

    var sizeCategory: ContentSizeCategory {
        self == .large ? .accessibilityLarge : .large
    }
}

/// Writes PNGs to a directory when one is configured and writable; keeps
/// them as XCTest attachments otherwise so a sandboxed runner still
/// carries them out in the xcresult.
final class ScreenCatalogScreenshotSink {
    private let directory: URL?
    private unowned let test: XCTestCase
    private var attachments: [XCTAttachment] = []
    private(set) var written = 0

    init(directory: String?, test: XCTestCase) {
        self.directory = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.test = test
    }

    func store(_ png: Data, name: String) {
        if let directory, write(png, to: directory.appendingPathComponent(name)) {
            written += 1
            return
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        attachments.append(attachment)
    }

    func finish() {
        attachments.forEach(test.add)
        print("screen catalog: wrote \(written) PNG(s), attached \(attachments.count)")
    }

    private func write(_ png: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            print("screen catalog: could not write \(url.path): \(error)")
            return false
        }
    }
}
