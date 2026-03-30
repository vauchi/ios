// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// View for importing contacts from a vCard (.vcf) file.
struct ImportContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showFilePicker = false
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 24) {
            if let result = importResult {
                resultView(result)
            } else if isImporting {
                ProgressView("Importing...")
            } else {
                promptView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Import Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "vcf") ?? .data,
                .vCard,
                .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Subviews

    private var promptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("Import contacts from a vCard (.vcf) file.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showFilePicker = true
            } label: {
                Label("Choose File", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("import.chooseFile")

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private func resultView(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: result.imported > 0 ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(result.imported > 0 ? .green : .orange)
                .accessibilityHidden(true)

            Text("\(result.imported) contact(s) imported")
                .font(.headline)

            if result.skipped > 0 {
                Text("\(result.skipped) skipped (duplicates or invalid)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.warnings.prefix(5), id: \.self) { warning in
                        Text("- \(warning)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if result.warnings.count > 5 {
                        Text("... and \(result.warnings.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            Button {
                importResult = nil
                errorMessage = nil
            } label: {
                Label("Import More", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Logic

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                importVcf(data)
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }

        case let .failure(error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func importVcf(_ data: Data) {
        isImporting = true
        errorMessage = nil

        Task {
            do {
                let result = try await viewModel.importContactsFromVcf(data)
                await MainActor.run {
                    importResult = result
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
}

/// Result of a contact import operation (mirrors MobileImportResult).
struct ImportResult {
    let imported: Int
    let skipped: Int
    let warnings: [String]
}
