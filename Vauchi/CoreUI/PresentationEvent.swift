// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PresentationInputValue {
    case text(String)
    case boolean(Bool)
    case choice(String?)
    case number(Double)
}

enum PresentationEvent: Encodable {
    case surfaceActivated(surfaceID: String)
    case actionActivated(surfaceID: String, interactionID: String)
    case valueChanged(
        surfaceID: String,
        bindingID: String,
        value: PresentationInputValue
    )
    case backRequested(surfaceID: String)
    case overlayDismissed(surfaceID: String, kind: PresentationOverlayKind)
    case environmentChanged(
        availableWidth: UInt32,
        availableHeight: UInt32,
        inputModes: [PresentationInputMode],
        motion: PresentationMotion
    )
    case deepLinkOpened(uri: String)
    case appBackgrounded
    case presentationInvalidated

    fileprivate struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    private struct SurfacePayload: Encodable {
        let surfaceID: String

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
        }
    }

    private struct ActionPayload: Encodable {
        let surfaceID: String
        let interactionID: String

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case interactionID = "interaction_id"
        }
    }

    private struct ValuePayload: Encodable {
        let surfaceID: String
        let bindingID: String
        let value: PresentationInputValue

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case bindingID = "binding_id"
            case value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(surfaceID, forKey: .surfaceID)
            try container.encode(bindingID, forKey: .bindingID)
            try value.encode(to: container.superEncoder(forKey: .value))
        }
    }

    private struct OverlayPayload: Encodable {
        let surfaceID: String
        let kind: PresentationOverlayKind

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case kind
        }
    }

    private struct EnvironmentPayload: Encodable {
        let availableWidth: UInt32
        let availableHeight: UInt32
        let inputModes: [PresentationInputMode]
        let motion: PresentationMotion

        private enum CodingKeys: String, CodingKey {
            case availableWidth = "available_width"
            case availableHeight = "available_height"
            case inputModes = "input_modes"
            case motion
        }
    }

    private struct DeepLinkPayload: Encodable {
        let uri: String
    }

    func encode(to encoder: Encoder) throws {
        if case .appBackgrounded = self {
            var container = encoder.singleValueContainer()
            try container.encode("AppBackgrounded")
            return
        }
        if case .presentationInvalidated = self {
            var container = encoder.singleValueContainer()
            try container.encode("PresentationInvalidated")
            return
        }

        var container = encoder.container(keyedBy: DynamicKey.self)
        switch self {
        case let .surfaceActivated(surfaceID):
            try container.encode(
                SurfacePayload(surfaceID: surfaceID),
                forKey: .init(stringValue: "SurfaceActivated")!
            )
        case let .actionActivated(surfaceID, interactionID):
            try container.encode(
                ActionPayload(
                    surfaceID: surfaceID,
                    interactionID: interactionID
                ),
                forKey: .init(stringValue: "ActionActivated")!
            )
        case let .valueChanged(surfaceID, bindingID, value):
            try container.encode(
                ValuePayload(
                    surfaceID: surfaceID,
                    bindingID: bindingID,
                    value: value
                ),
                forKey: .init(stringValue: "ValueChanged")!
            )
        case let .backRequested(surfaceID):
            try container.encode(
                SurfacePayload(surfaceID: surfaceID),
                forKey: .init(stringValue: "BackRequested")!
            )
        case let .overlayDismissed(surfaceID, kind):
            try container.encode(
                OverlayPayload(surfaceID: surfaceID, kind: kind),
                forKey: .init(stringValue: "OverlayDismissed")!
            )
        case let .environmentChanged(width, height, inputModes, motion):
            try container.encode(
                EnvironmentPayload(
                    availableWidth: width,
                    availableHeight: height,
                    inputModes: inputModes,
                    motion: motion
                ),
                forKey: .init(stringValue: "PresentationEnvironmentChanged")!
            )
        case let .deepLinkOpened(uri):
            try container.encode(
                DeepLinkPayload(uri: uri),
                forKey: .init(stringValue: "DeepLinkOpened")!
            )
        case .appBackgrounded, .presentationInvalidated:
            break
        }
    }
}

private extension PresentationInputValue {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PresentationEvent.DynamicKey.self)
        switch self {
        case let .text(value):
            try container.encode(
                value,
                forKey: .init(stringValue: "Text")!
            )
        case let .boolean(value):
            try container.encode(
                value,
                forKey: .init(stringValue: "Boolean")!
            )
        case let .choice(value):
            try container.encode(
                value,
                forKey: .init(stringValue: "Choice")!
            )
        case let .number(value):
            try container.encode(
                value,
                forKey: .init(stringValue: "Number")!
            )
        }
    }
}
