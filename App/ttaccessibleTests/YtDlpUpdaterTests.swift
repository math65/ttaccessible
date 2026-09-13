//
//  YtDlpUpdaterTests.swift
//  ttaccessibleTests
//
//  yt-dlp keeps itself current inside the app. These pin the rules (which release is newer,
//  which checksum line belongs to the zipapp, once a day), prove that switching yt-dlp works
//  inside the sandboxed app, including a broken update that must leave the working copy loaded,
//  and download the current release for real, verified against its published checksum. That last
//  test needs the network and writes only to a throwaway folder.
//

import XCTest
@testable import ttaccessible

final class YtDlpUpdaterTests: XCTestCase {

    // MARK: Rules

    func testLaterReleasesAreNewer() {
        XCTAssertTrue(YtDlpUpdater.isNewer("2026.09.02", than: "2026.08.19"))
        XCTAssertTrue(YtDlpUpdater.isNewer("2026.08.19.1", than: "2026.08.19"), "a hotfix")
        XCTAssertTrue(YtDlpUpdater.isNewer("2027.01.01", than: "2026.12.31"))
        XCTAssertFalse(YtDlpUpdater.isNewer("2026.08.19", than: "2026.08.19"))
        XCTAssertFalse(YtDlpUpdater.isNewer("2026.07.30", than: "2026.08.19"))
    }

    /// Lines from yt-dlp 2026.08.19's real SHA2-256SUMS.
    private let sums = """
        1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6  yt-dlp
        66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a  yt-dlp.exe
        072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1  yt-dlp.tar.gz
        """

    func testTheChecksumIsTakenForExactlyTheZipapp() {
        XCTAssertEqual(YtDlpUpdater.checksum(for: "yt-dlp", in: sums),
                       "1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6")
        XCTAssertNil(YtDlpUpdater.checksum(for: "yt-dlp_macos", in: sums))
    }

    func testABinaryModeMarkerIsIgnored() {
        XCTAssertEqual(YtDlpUpdater.checksum(for: "yt-dlp", in: "ABCDEF *yt-dlp"), "abcdef")
    }

    func testChecksAtMostOnceADay() {
        let now = Date()
        XCTAssertTrue(YtDlpUpdater.isCheckDue(lastCheck: nil, now: now), "never checked")
        XCTAssertFalse(YtDlpUpdater.isCheckDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(YtDlpUpdater.isCheckDue(lastCheck: now.addingTimeInterval(-25 * 3_600), now: now))
        XCTAssertTrue(YtDlpUpdater.isCheckDue(lastCheck: now.addingTimeInterval(3_600), now: now), "clock moved back")
    }

    // MARK: Switching inside the app

    func testSwitchingYtDlpWorksInsideTheApp() async throws {
        let bundled = try XCTUnwrap(EmbeddedPython.bundledYtDlp)
        _ = await EmbeddedPython.shared.ytdlpVersion()
        let result = await EmbeddedPython.shared.switchYtDlp(to: bundled)
        XCTAssertEqual(result, .switched(try XCTUnwrap(EmbeddedPython.bundledYtDlpVersion)))
    }

    func testABrokenUpdateLeavesTheWorkingYtDlpLoaded() async throws {
        _ = await EmbeddedPython.shared.ytdlpVersion()
        let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("not-yt-dlp-\(UUID()).zip")
        try Data("not a zip".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        let result = await EmbeddedPython.shared.switchYtDlp(to: bogus)
        guard case .failed = result else { return XCTFail("expected a failure, got \(result)") }
        let version = await EmbeddedPython.shared.ytdlpVersion()
        XCTAssertEqual(version, EmbeddedPython.bundledYtDlpVersion)
    }

    // MARK: The real release (network)

    func testTheCurrentReleaseDownloadsAndVerifies() async throws {
        let release = try await YtDlpUpdater.fetchLatestRelease()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yt-dlp-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }

        let zip = try await YtDlpUpdater.download(release, into: folder)
        XCTAssertEqual(zip.deletingLastPathComponent().lastPathComponent, release.version)
        let size = try XCTUnwrap(try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(size, 1_000_000, "the zipapp is about 3 MB")
    }
}
