// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactMergeView.swift
// Placeholder for duplicate contact detection and merge UI.
//
// TODO: Wire up once findDuplicates(), mergeContacts(primaryId:secondaryId:),
// and dismissDuplicate(id1:id2:) are available in the VauchiPlatform UniFFI bindings.
// These methods exist in vauchi-core but have not yet been exported via UniFFI.

import SwiftUI

struct ContactMergeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("Find Duplicates")
                .font(.title2)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            Text("Duplicate detection is coming soon. This will help you identify and merge contacts that may refer to the same person.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Find Duplicates")
        .accessibilityIdentifier("contact_merge.placeholder")
    }
}

#Preview {
    NavigationView {
        ContactMergeView()
    }
}
