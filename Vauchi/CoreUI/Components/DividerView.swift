// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Renders a core `Component::Divider` as a horizontal line separator.
struct DividerView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 4)
    }
}
