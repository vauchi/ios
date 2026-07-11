// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for `ExchangeHardwareScreen.Flow.wrapperHint`, the mechanical map from
// a wrapper flow to the `NativeWrapperHint` core stamps on its `ScreenModel`.
// The on-dismiss `cancel` guard compares this hint against the current screen's
// hint, so the flow must mirror core's discriminant exactly. Which `screen_id`s
// belong to which flow is core's decision (it stamps `native_wrapper_hint`), so
// that domain knowledge is asserted in core, not re-tested here (CC-24).

import CoreUIModels
@testable import Vauchi
import XCTest

final class ExchangeHardwareScreenTests: XCTestCase {
    func testWrapperHintMirrorsCoreDiscriminant() {
        XCTAssertEqual(ExchangeHardwareScreen.Flow.multiStage.wrapperHint, .multiStageExchange)
        XCTAssertEqual(ExchangeHardwareScreen.Flow.nfc.wrapperHint, .nfcExchange)
    }
}
