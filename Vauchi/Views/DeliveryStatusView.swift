// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeliveryStatusView.swift
// Thin Humble-UI shell — delegates to CoreScreenView, which renders the
// ScreenModel emitted by `DeliveryStatusEngine` in core. The bespoke
// 3-tab SwiftUI layout (Recent / Failed / Pending) was retired as part
// of the Pure Humble UI retirement work
// (_private/docs/problems/2026-04-28-pure-humble-ui-retire-native-screens/).
// Sections are now emitted by core as Text(section_*) headers + Divider
// + StatusIndicator components.

import SwiftUI

struct DeliveryStatusView: View {
    var body: some View {
        CoreScreenView(screenName: "DeliveryStatus")
    }
}

#Preview {
    NavigationView {
        DeliveryStatusView()
            .environmentObject(VauchiViewModel())
    }
}
