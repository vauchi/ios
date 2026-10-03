// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PresentationAxis: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.vertical

    case horizontal
    case vertical
}

enum PresentationTextStyle: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.body

    case heading
    case body
    case caption
    case monospace
    case muted
}

enum PresentationInputKind: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.text

    case text
    case email
    case phone
    case url
    case password
    case number
    case search
    case pin
}

enum PresentationTone: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.neutral

    case neutral
    case accent
    case success
    case warning
    case error
}

enum PresentationImageShape: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.natural

    case natural
    case circle
}

enum PresentationQRPurpose: String, Codable, PresentationTolerantEnum {
    static let decodingFallback = Self.display

    case display
    case capture
}

struct PresentationChoiceOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
}

struct PresentationPaging: Codable, Equatable {
    let totalCount: Int
    let offset: Int
    let window: Int

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case offset
        case window
    }
}

struct PresentationRow: Codable, Equatable, Identifiable {
    let title: String
    let subtitle: String?
    let detail: String?
    let iconToken: String?
    let imageData: [UInt8]?
    let fallbackText: String?
    let selected: Bool
    let enabled: Bool
    let activation: PresentationAction?
    let secondaryActions: [PresentationAction]
    let controls: [PresentationNode]
    let accessibility: PresentationAccessibility

    var id: String {
        activation?.interactionID
            ?? "\(title):\(subtitle ?? ""):\(detail ?? "")"
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case detail
        case iconToken = "icon_token"
        case imageData = "image_data"
        case fallbackText = "fallback_text"
        case selected
        case enabled
        case activation
        case secondaryActions = "secondary_actions"
        case controls
        case accessibility
    }
}

struct PresentationSurface: Codable, Equatable, Identifiable {
    let surfaceID: String
    let revision: UInt64
    let title: String
    let subtitle: String?
    let accessibilityLabel: String
    let layout: PresentationSurfaceLayout
    let tokens: PresentationTokens
    let nodes: [PresentationNode]

    var id: String {
        surfaceID
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceID = "surface_id"
        case revision
        case title
        case subtitle
        case accessibilityLabel = "accessibility_label"
        case layout
        case tokens
        case nodes
    }
}

indirect enum PresentationNode: Codable, Equatable {
    case text(Text)
    case input(Input)
    case toggle(Toggle)
    case choice(Choice)
    case group(Group)
    case list(ListNode)
    case image(Image)
    case status(Status)
    case qr(QrCode)
    case confirmation(Confirmation)
    case slider(Slider)
    case progress(Progress)
    case divider

    var identityID: String? {
        switch self {
        case let .text(value): value.id.map { "text:\($0)" }
        case let .input(value): "binding:\(value.bindingID)"
        case let .toggle(value): "binding:\(value.bindingID)"
        case let .choice(value): "binding:\(value.bindingID)"
        case let .group(value): value.id.map { "group:\($0)" }
        case let .list(value): "list:\(value.id)"
        case let .image(value): value.id.map { "image:\($0)" }
        case let .status(value): value.id.map { "status:\($0)" }
        // A camera's id is a per-revision binding, so as an identity it
        // rebuilt the preview and its capture session on every surface
        // update (issue #9, D14); its position is stable instead.
        case let .qr(value): value.purpose == .capture ? nil : "qr:\(value.id)"
        case let .confirmation(value): "confirmation:\(value.id)"
        case let .slider(value): "binding:\(value.bindingID)"
        case .progress, .divider: nil
        }
    }

    var focusIdentity: String? {
        guard case let .input(value) = self else { return nil }
        return value.bindingID
    }

    struct Text: Codable, Equatable {
        let id: String?
        let content: String
        let style: PresentationTextStyle
        let accessibility: PresentationAccessibility
    }

    struct Input: Codable, Equatable {
        let bindingID: String
        let label: String
        let value: String
        let placeholder: String?
        let inputKind: PresentationInputKind
        let maxLength: Int?
        let validationError: String?
        let enabled: Bool
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case bindingID = "binding_id"
            case label
            case value
            case placeholder
            case inputKind = "input_kind"
            case maxLength = "max_length"
            case validationError = "validation_error"
            case enabled
            case accessibility
        }
    }

    struct Toggle: Codable, Equatable {
        let bindingID: String
        let label: String
        let value: Bool
        let enabled: Bool
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case bindingID = "binding_id"
            case label
            case value
            case enabled
            case accessibility
        }
    }

    struct Choice: Codable, Equatable {
        let bindingID: String
        let label: String
        let selected: String?
        let options: [PresentationChoiceOption]
        let enabled: Bool
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case bindingID = "binding_id"
            case label
            case selected
            case options
            case enabled
            case accessibility
        }
    }

    struct Group: Codable, Equatable {
        let id: String?
        let label: String?
        let axis: PresentationAxis
        let children: [PresentationNode]
        let accessibility: PresentationAccessibility
    }

    struct ListNode: Codable, Equatable {
        let id: String
        let label: String?
        let rows: [PresentationRow]
        let searchable: Bool
        let paging: PresentationPaging?
        let accessibility: PresentationAccessibility
        /// Absent for an ordinary list. Kept as a string so a style this
        /// build does not know still draws as rows instead of failing the
        /// whole surface.
        var style: String?

        /// Core asked for these rows as native buttons: a short set of
        /// commands that must read as tappable at a glance.
        var drawsButtons: Bool {
            style == "buttons"
        }
    }

    struct Image: Codable, Equatable {
        let id: String?
        let data: [UInt8]?
        let fallbackText: String?
        let shape: PresentationImageShape
        let brightness: Float
        /// Absent for every avatar, where sizing stays the shell's call
        /// (`minimumTarget`); Core sets it only where it needs an exact
        /// square, currently just the onboarding mark (88). Pure
        /// presentation data passed through, never interpreted (ADR-066).
        let size: UInt16?
        let activation: PresentationAction?
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case id
            case data
            case fallbackText = "fallback_text"
            case shape
            case brightness
            case size
            case activation
            case accessibility
        }
    }

    struct Status: Codable, Equatable {
        let id: String?
        let title: String
        let detail: String?
        let iconToken: String?
        let badge: String?
        let tone: PresentationTone
        let activation: PresentationAction?
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case detail
            case iconToken = "icon_token"
            case badge
            case tone
            case activation
            case accessibility
        }
    }

    struct QrCode: Codable, Equatable {
        let id: String
        let payloads: [String]
        let purpose: PresentationQRPurpose
        let label: String?
        /// Where in the node's square a display code is drawn; absent
        /// means the full square.
        let placement: QrPlacement?
        /// Core's error-correction level for a display code; absent leaves
        /// it to the shell.
        let errorCorrection: String?
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case id, payloads, purpose, label, placement, accessibility
            case errorCorrection = "error_correction"
        }
    }

    struct Confirmation: Codable, Equatable {
        let id: String
        let warning: String
        let confirm: PresentationAction
        let cancel: PresentationAction
        let accessibility: PresentationAccessibility
    }

    struct Slider: Codable, Equatable {
        let bindingID: String
        let label: String
        let value: Double
        let minimum: Double
        let maximum: Double
        let step: Double?
        let minimumIcon: String?
        let maximumIcon: String?
        let accessibility: PresentationAccessibility

        private enum CodingKeys: String, CodingKey {
            case bindingID = "binding_id"
            case label
            case value
            case minimum
            case maximum
            case step
            case minimumIcon = "minimum_icon"
            case maximumIcon = "maximum_icon"
            case accessibility
        }
    }

    struct Progress: Codable, Equatable {
        let label: String?
        let value: Double?
        let accessibility: PresentationAccessibility
    }

    private struct VariantKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self),
           value == "Divider" {
            self = .divider
            return
        }
        let container = try decoder.container(keyedBy: VariantKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Empty node")
            )
        }
        switch key.stringValue {
        case "Text": self = try .text(container.decode(Text.self, forKey: key))
        case "Input": self = try .input(container.decode(Input.self, forKey: key))
        case "Toggle": self = try .toggle(container.decode(Toggle.self, forKey: key))
        case "Choice": self = try .choice(container.decode(Choice.self, forKey: key))
        case "Group": self = try .group(container.decode(Group.self, forKey: key))
        case "List": self = try .list(container.decode(ListNode.self, forKey: key))
        case "Image": self = try .image(container.decode(Image.self, forKey: key))
        case "Status": self = try .status(container.decode(Status.self, forKey: key))
        case "Qr": self = try .qr(container.decode(QrCode.self, forKey: key))
        case "Confirmation":
            self = try .confirmation(container.decode(Confirmation.self, forKey: key))
        case "Slider": self = try .slider(container.decode(Slider.self, forKey: key))
        case "Progress": self = try .progress(container.decode(Progress.self, forKey: key))
        default:
            // A node kind newer than this shell renders as a labelled
            // placeholder rather than failing the surface around it.
            self = .text(Self.unsupportedPlaceholder(kind: key.stringValue))
        }
    }
}

extension PresentationNode {
    static func unsupportedPlaceholder(kind: String) -> Text {
        let content = "Unsupported node: \(kind)"
        return Text(
            id: nil,
            content: content,
            style: .muted,
            accessibility: PresentationAccessibility(label: content, description: nil)
        )
    }
}

struct IdentifiedPresentationNode: Identifiable {
    let id: String
    let node: PresentationNode
}

func identifyPresentationNodes(
    _ nodes: [PresentationNode]
) -> [IdentifiedPresentationNode] {
    nodes.enumerated().map { index, node in
        IdentifiedPresentationNode(
            id: node.identityID ?? "position:\(index)",
            node: node
        )
    }
}

/// Where Core asks a display code to be drawn inside its square: the
/// code's side and the offset of its top-left corner, in permille of the
/// square's side.
struct QrPlacement: Codable, Equatable {
    let size: Int
    let x: Int
    let y: Int
}

/// A code's side and top-left corner inside a square, in points. Pure, so
/// `PresentationQrPlacementTests` can assert the numbers without rendering.
struct QrFrameSpec: Equatable {
    let side: CGFloat
    let left: CGFloat
    let top: CGFloat

    init(side: CGFloat, left: CGFloat, top: CGFloat) {
        self.side = side
        self.left = left
        self.top = top
    }

    /// No placement is the full square. Core only sends placements inside
    /// the square; a value outside it is pulled back in, so the code is
    /// never drawn past its node.
    init(placement: QrPlacement?, squareSide: CGFloat) {
        guard let placement, placement.size > 0 else {
            self.init(side: squareSide, left: 0, top: 0)
            return
        }
        let full = 1000
        let size = min(placement.size, full)
        let room = full - size
        // Multiply before dividing: 650 × 320 / 1000 is exact.
        let scaled = { (permille: Int) -> CGFloat in
            CGFloat(permille) * squareSide / CGFloat(full)
        }
        self.init(
            side: scaled(size),
            left: scaled(min(max(placement.x, 0), room)),
            top: scaled(min(max(placement.y, 0), room))
        )
    }
}

/// The `CIQRCodeGenerator` correction level for Core's error-correction
/// name. Only "low" changes anything: Core asks for it during an exchange,
/// where fewer, larger modules read from closer. Anything else, absent
/// included, is the default.
func qrCorrectionLevel(_ errorCorrection: String?) -> String {
    errorCorrection == "low" ? "L" : "M"
}
