// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Hosts the SwiftUI `.fileImporter` for the ADR-031 file-picker
// `ExchangeCommand`. Applied at ContentView root so the system document
// picker is reachable from any flow that emits
// `ExchangeCommand::FilePickFromUser` — Onboarding `restore_backup`,
// the More-tab "Import Contacts" rewire, and any future caller.
//
// Previously the modifier lived on CoreScreenView only, which
// silently dropped the picker for custom-view tabs (MoreView,
// HomeView, ContactsView) and for the entire Onboarding flow
// (which rendered through its own view, not CoreScreenView).
// Hoisting closes that reachability gap (see commit message for
// problem record refs).

import CoreUIModels
import SwiftUI
import UniformTypeIdentifiers

/// View modifier that presents the ADR-031 file importer when
/// `coreVM.pendingFilePick` becomes non-nil. Self-clears the pending
/// state on selection / cancel via `coreVM.sendFilePicked` /
/// `sendFilePickCancelled`.
struct FilePickerModifier: ViewModifier {
    @ObservedObject var coreVM: AppViewModel

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: filePickerBinding,
            allowedContentTypes: filePickerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                coreVM.sendFilePickCancelled()
                return
            }
            // Per Apple's file-coordination contract for security-scoped
            // resource URLs returned by `.fileImporter`: hold the access
            // for the read, then release. Without this, sandboxed builds
            // raise `NSCocoaErrorDomain 257` on `Data(contentsOf:)`.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                coreVM.sendFilePicked(bytes: Array(data), filename: url.lastPathComponent)
            } catch {
                #if DEBUG
                    print("FilePickerModifier: file read failed: \(error)")
                #endif
                coreVM.sendFilePickCancelled()
            }
        case .failure:
            coreVM.sendFilePickCancelled()
        }
    }

    private var filePickerBinding: Binding<Bool> {
        Binding(
            get: { coreVM.pendingFilePick != nil },
            set: { isPresented in
                // SwiftUI sets this to false when the importer dismisses.
                // If `pendingFilePick` is still set when that happens, the
                // user dismissed without our handler running (system back-
                // gesture, app backgrounding) — surface the cancel so core
                // doesn't sit forever waiting for a hardware event.
                if !isPresented, coreVM.pendingFilePick != nil {
                    coreVM.sendFilePickCancelled()
                }
            }
        )
    }

    private var filePickerContentTypes: [UTType] {
        guard let pending = coreVM.pendingFilePick else { return [.data] }
        return Self.contentTypes(forAcceptedExtensions: pending.acceptedExtensions)
    }

    /// Maps core's lowercase, dot-less extension filter (core!1582
    /// `accepted_extensions`) to `UTType`s. Falls back to `.data` — the
    /// universal "any file" type — when the list is empty (an
    /// any-file purpose) or absent (the pinned core build predates the
    /// field): the picker still opens, just without a filter.
    static func contentTypes(forAcceptedExtensions extensions: [String]) -> [UTType] {
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }
}

extension View {
    /// Attach the ADR-031 file-picker host to this view tree.
    /// Tolerates a `nil` `coreVM` (returned from
    /// `viewModel.coreViewModel` before the platform finishes
    /// initialisation) by becoming a no-op until the AppViewModel
    /// exists.
    @ViewBuilder
    func corePendingFilePick(_ coreVM: AppViewModel?) -> some View {
        if let coreVM {
            modifier(FilePickerModifier(coreVM: coreVM))
        } else {
            self
        }
    }
}
