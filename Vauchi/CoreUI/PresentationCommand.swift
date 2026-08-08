// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct PresentationCommandEnvelope: Decodable {
    let commands: [PresentationCommand]
}

struct RevisionedContextBar: Equatable {
    let revision: UInt64
    let bar: PresentationContextBar
}

struct RevisionedOverlay: Equatable {
    let surfaceID: String
    let revision: UInt64
    let overlay: PresentationOverlay
}

struct PresentationAlert: Decodable {
    let title: String
    let message: String
}

struct PresentationToast: Decodable {
    let message: String
}

struct PresentationExportFile: Decodable {
    let suggestedName: String
    let mimeType: String
    let data: [UInt8]

    private enum CodingKeys: String, CodingKey {
        case suggestedName = "suggested_name"
        case mimeType = "mime_type"
        case data
    }
}

indirect enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = try .array(container.decode([JSONValue].self))
        }
    }
}

enum PresentationCommand: Decodable {
    case replaceSurface(PresentationSurface)
    case setContextBar(RevisionedContextBar, surfaceID: String)
    case presentOverlay(RevisionedOverlay)
    case dismissOverlay(surfaceID: String, revision: UInt64, kind: PresentationOverlayKind)
    case setPresentationProfile(PresentationProfile)
    case presentAlert(PresentationAlert)
    case showToast(PresentationToast)
    case openExternalURL(String)
    case exportFile(PresentationExportFile)
    case performNativeBack
    case resetApplication
    case postNotification(JSONValue)
    case platformEffect(variant: String, payload: JSONValue?)

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    private struct SurfacePayload: Decodable {
        let surface: PresentationSurface
    }

    private struct BarPayload: Decodable {
        let surfaceID: String
        let revision: UInt64
        let bar: PresentationContextBar

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case revision
            case bar
        }
    }

    private struct OverlayPayload: Decodable {
        let surfaceID: String
        let revision: UInt64
        let overlay: PresentationOverlay

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case revision
            case overlay
        }
    }

    private struct DismissOverlayPayload: Decodable {
        let surfaceID: String
        let revision: UInt64
        let kind: PresentationOverlayKind

        private enum CodingKeys: String, CodingKey {
            case surfaceID = "surface_id"
            case revision
            case kind
        }
    }

    private struct ProfilePayload: Decodable {
        let profile: PresentationProfile
    }

    private struct AlertPayload: Decodable {
        let alert: PresentationAlert
    }

    private struct ToastPayload: Decodable {
        let toast: PresentationToast
    }

    private struct URLPayload: Decodable {
        let url: String
    }

    private struct FilePayload: Decodable {
        let file: PresentationExportFile
    }

    private struct NotificationPayload: Decodable {
        let notification: JSONValue
    }

    private static func decodeStringVariant(_ variant: String) -> Self {
        switch variant {
        case "PerformNativeBack": .performNativeBack
        case "ResetApplication": .resetApplication
        default: .platformEffect(variant: variant, payload: nil)
        }
    }

    init(from decoder: Decoder) throws {
        if let variant = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.decodeStringVariant(variant)
            return
        }

        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Empty command")
            )
        }
        self = try Self.decodeKeyedVariant(key: key, from: container)
    }

    private static func decodeKeyedVariant(
        key: DynamicKey,
        from container: KeyedDecodingContainer<DynamicKey>
    ) throws -> Self {
        switch key.stringValue {
        case "ReplaceSurface":
            return try .replaceSurface(
                container.decode(SurfacePayload.self, forKey: key).surface
            )
        case "SetContextBar":
            let value = try container.decode(BarPayload.self, forKey: key)
            return .setContextBar(
                .init(revision: value.revision, bar: value.bar),
                surfaceID: value.surfaceID
            )
        case "PresentOverlay":
            let value = try container.decode(OverlayPayload.self, forKey: key)
            return .presentOverlay(
                .init(
                    surfaceID: value.surfaceID,
                    revision: value.revision,
                    overlay: value.overlay
                )
            )
        case "DismissOverlay":
            let value = try container.decode(DismissOverlayPayload.self, forKey: key)
            return .dismissOverlay(
                surfaceID: value.surfaceID,
                revision: value.revision,
                kind: value.kind
            )
        case "SetPresentationProfile":
            return try .setPresentationProfile(
                container.decode(ProfilePayload.self, forKey: key).profile
            )
        case "PresentAlert":
            return try .presentAlert(
                container.decode(AlertPayload.self, forKey: key).alert
            )
        case "ShowToast":
            return try .showToast(
                container.decode(ToastPayload.self, forKey: key).toast
            )
        case "OpenExternalUrl":
            return try .openExternalURL(
                container.decode(URLPayload.self, forKey: key).url
            )
        case "ExportFile":
            return try .exportFile(
                container.decode(FilePayload.self, forKey: key).file
            )
        case "PostNotification":
            return try .postNotification(
                container.decode(NotificationPayload.self, forKey: key).notification
            )
        default:
            return .platformEffect(
                variant: key.stringValue,
                payload: try? container.decode(JSONValue.self, forKey: key)
            )
        }
    }
}
