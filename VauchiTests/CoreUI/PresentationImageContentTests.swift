// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core sends an avatar as `PresentationNode::Image` with `data`,
// `fallback_text` and `shape`. When the contact has no picture the shell
// renders `fallback_text`, and the question this file settles is whether
// those initials are drawn *as an avatar* or as loose text on the page.
//
// It cannot be settled by XCUITest. The node's wrapper already applies
// `.frame(minWidth: minimumTarget, minHeight: minimumTarget)`, so the
// accessibility element measures 44 x 44 whether or not anything is
// painted inside it — a UI test asking for the element's frame passes
// either way. The defect is purely visual, so the assertion has to be on
// pixels: render the view and sample a point that lies inside the avatar
// and outside the glyph.
//
// Observed failing before the fix: alpha 0.0 at that point, because
// `clipShape(Circle())` was being applied to a bare `Text` — there was no
// fill for it to clip.

@testable import Vauchi
import SwiftUI
import XCTest

@MainActor
final class PresentationImageContentTests: XCTestCase {
    /// Side of the square the view is rendered into. Any value works; this
    /// one makes the sampled point's geometry easy to check by hand.
    private let side: CGFloat = 96

    private func imageNode(
        data: [UInt8]?,
        fallbackText: String?,
        shape: PresentationImageShape
    ) -> PresentationNode.Image {
        PresentationNode.Image(
            id: nil,
            data: data,
            fallbackText: fallbackText,
            shape: shape,
            brightness: 1,
            activation: nil,
            accessibility: PresentationAccessibility(label: "Avatar", description: nil)
        )
    }

    /// Renders the content view on a transparent ground and returns the
    /// pixel at `point`. Transparent ground matters: against an opaque one
    /// every pixel comes back opaque and the test proves nothing.
    private func pixel(
        of node: PresentationNode.Image,
        at point: CGPoint
    ) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let host = UIHostingController(
            rootView: PresentationImageContent(value: node)
                .frame(width: side, height: side)
        )
        host.view.frame = CGRect(x: 0, y: 0, width: side, height: side)
        host.view.backgroundColor = .clear

        // The view has to be in a real window and through a layout pass
        // before it draws. `layer.render(in:)` off-window returns a blank
        // bitmap for SwiftUI content, which reads as "no fill" for every
        // input and would make these assertions meaningless.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: side, height: side))
        window.rootViewController = host
        window.isHidden = false
        window.backgroundColor = .clear
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        let draw: (UIGraphicsImageRendererContext) -> Void = { _ in
            host.view.drawHierarchy(in: box, afterScreenUpdates: true)
        }
        // The first `afterScreenUpdates` pass on a freshly attached window
        // can return before SwiftUI has committed anything, which reads as a
        // blank avatar. Render once to warm it, then measure.
        _ = renderer.image(actions: draw)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rendered = renderer.image(actions: draw)

        let cgImage = try XCTUnwrap(rendered.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try XCTUnwrap(
            CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(
            cgImage,
            in: CGRect(x: -point.x, y: -(side - point.y), width: side, height: side)
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    /// The fill is a low-opacity secondary grey — enough to read as an
    /// avatar without competing with the initials — so it lands around
    /// alpha 28 rather than near 255. Anything above this is paint;
    /// an unfilled view measures 0.
    private let opaqueEnoughToRead: UInt8 = 10

    /// A point inside the drawn avatar and clear of the centred glyph.
    ///
    /// Calibrated by scanning the rendered row rather than derived from the
    /// frame: a hosting controller lays the content out smaller than the
    /// window it is given, so the avatar spans roughly x 12...84 of the
    /// 96 pt box rather than its full width. A quarter in from the left is
    /// comfortably inside that, and the two initials occupy about the
    /// middle third.
    private var insideTheAvatarOutsideTheGlyph: CGPoint {
        CGPoint(x: side / 4, y: side / 2)
    }

    func testCircularFallbackInitialsAreDrawnOnAFilledShape() throws {
        let node = imageNode(data: nil, fallbackText: "TU", shape: .circle)

        let sampled = try pixel(of: node, at: insideTheAvatarOutsideTheGlyph)

        XCTAssertGreaterThan(
            sampled.a,
            opaqueEnoughToRead,
            """
            The avatar has no fill: initials render as loose text on the page \
            rather than inside a circle. Sampled alpha \(sampled.a) at \
            \(insideTheAvatarOutsideTheGlyph).
            """
        )
    }

    /// The same defect, without the circle. A natural-shaped image whose
    /// data is missing still needs a body; otherwise the alt text floats.
    func testNaturalFallbackInitialsAreDrawnOnAFilledShape() throws {
        let node = imageNode(data: nil, fallbackText: "TU", shape: .natural)

        let sampled = try pixel(of: node, at: insideTheAvatarOutsideTheGlyph)

        XCTAssertGreaterThan(sampled.a, opaqueEnoughToRead, "natural-shaped fallback has no fill")
    }

    /// Guards the test itself: the sampled point must be transparent when
    /// nothing is expected there, or the two assertions above would pass on
    /// any view at all. An empty fallback draws nothing and must stay clear.
    func testTheSampledPointIsTransparentWhenThereIsNothingToDraw() throws {
        let node = imageNode(data: nil, fallbackText: nil, shape: .natural)

        let sampled = try pixel(of: node, at: insideTheAvatarOutsideTheGlyph)

        XCTAssertLessThan(
            sampled.a,
            opaqueEnoughToRead,
            "the sampler reports paint where the view draws none"
        )
    }
}
