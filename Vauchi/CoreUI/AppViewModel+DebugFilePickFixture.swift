// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import CoreUIModels
    import Foundation

    /// `--import-backup <path>` stands in for the user's backup pick, so the
    /// store-screenshot UI test can restore a fixture without driving the
    /// system document picker (CC-23). Core still receives the ordinary
    /// `filePickedFromUser` event; only where the bytes came from differs.
    extension AppViewModel {
        static var debugFilePickFixture: URL? =
            debugFilePickFixture(fromArguments: ProcessInfo.processInfo.arguments)

        static func debugFilePickFixture(fromArguments arguments: [String]) -> URL? {
            guard let flag = arguments.firstIndex(of: "--import-backup"),
                  flag + 1 < arguments.count
            else { return nil }
            return URL(fileURLWithPath: arguments[flag + 1])
        }

        /// Returns false, leaving the picker to be shown, when the pick is
        /// not a backup import or the fixture cannot be read.
        func answerFilePickFromFixture(purpose: FilePickPurpose) -> Bool {
            guard purpose == .importBackup,
                  let fixture = Self.debugFilePickFixture,
                  let data = try? Data(contentsOf: fixture)
            else { return false }
            sendFilePicked(bytes: [UInt8](data), filename: fixture.lastPathComponent)
            return true
        }
    }
#endif
