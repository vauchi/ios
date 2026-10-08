// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The app's Documents and Library are excluded from iCloud/iTunes backup.
// The exclusion used `try?`, so a failure left the data eligible for backup
// with nothing reported (vauchi/private#287, P1.I1). The step now returns the
// errors it meets, and a clean run returns none.

@testable import Vauchi
import XCTest

final class BackupExclusionTests: XCTestCase {
    private struct SetFailed: Error {}

    private let urls = [
        URL(fileURLWithPath: "/tmp/vauchi-documents"),
        URL(fileURLWithPath: "/tmp/vauchi-library"),
    ]

    func testEveryDirectoryIsAskedToBeExcluded() {
        var excluded: [URL] = []

        let errors = VauchiApp.excludeFromBackup(urls) { url, values in
            XCTAssertEqual(values.isExcludedFromBackup, true)
            excluded.append(url)
        }

        XCTAssertEqual(excluded, urls)
        XCTAssertTrue(errors.isEmpty)
    }

    func testAFailedExclusionIsReturnedNotSwallowed() {
        let errors = VauchiApp.excludeFromBackup(urls) { url, _ in
            if url == self.urls[1] {
                throw SetFailed()
            }
        }

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first is SetFailed)
    }
}
