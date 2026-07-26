//
//  DeviceStreamSourceTests.swift
//  ttaccessibleTests
//
//  Live-loopback integration check for AudioDeviceStreamSource (device → channel
//  media streaming): starts the real capture + loopback server, verifies the
//  TeamTalk SDK's FFmpeg probe accepts the stream, and confirms the server paces
//  output to realtime — the guarantee that a silent or stalled device never
//  starves the SDK reader (a starved stream ends the broadcast).
//
//  The loopback is an endless Ogg Opus stream (5 ms frames); see
//  OggOpusStreamEncoder for why Opus rather than AAC/WAV.
//

import XCTest
@testable import ttaccessible

final class DeviceStreamSourceTests: XCTestCase {

    func testServesSDKCompatiblePacedStream() throws {
        let devices = InputAudioDeviceResolver.availableInputDevices()
        try XCTSkipIf(devices.isEmpty, "No audio input devices on this machine")

        let source = AudioDeviceStreamSource(device: devices[0])
        let url = try source.start()
        defer { source.stop() }

        // 1. The SDK's own probe (TT_GetMediaFileInfo → FFmpeg) must accept the
        //    endless Ogg Opus stream, see 48 kHz audio, and — the reason the
        //    stream is Opus rather than WAV/AAC — finish its analysis fast.
        //    Everything the analyzer consumes becomes permanent broadcast
        //    latency, so this bound is a real latency budget.
        let controller = TeamTalkConnectionController(preferencesStore: AppPreferencesStore())
        let probeStart = Date()
        let probe = controller.probeMediaFileLocked(path: url.absoluteString)
        let probeSeconds = Date().timeIntervalSince(probeStart)
        XCTAssertTrue(probe.sdkSupported, "SDK/FFmpeg rejected the loopback Ogg Opus stream")
        XCTAssertTrue(probe.hasAudio, "probe found no audio format")
        XCTAssertFalse(probe.hasVideo)
        XCTAssertLessThan(probeSeconds, 2.5,
                          "FFmpeg open consumed \(probeSeconds)s of stream — that much becomes broadcast latency")

        // 2. Realtime pacing: reading for ~3 s must yield roughly 3 s of MEDIA
        //    TIME whether or not the capture device delivers anything (silence
        //    is padded in). Byte counts are useless — Opus encodes silence to a
        //    few bytes per frame — so count Ogg pages instead: the encoder emits
        //    one page per 5 ms Opus frame (240 samples @ 48 kHz), so 3 s of
        //    media time ≈ 600 pages (200/s).
        let counter = OggPageCountingDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: counter, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        task.resume()
        Thread.sleep(forTimeInterval: 3.0)
        task.cancel()

        let pages = counter.oggPageCount
        XCTAssertGreaterThan(pages, 300,
                             "stream is starving — silence padding is not keeping it alive (\(pages) Ogg pages in 3 s)")
        XCTAssertLessThan(pages, 1200,
                          "stream is not paced to realtime — dumping data (\(pages) Ogg pages in 3 s)")
    }
}

/// Counts Ogg pages by scanning the byte stream for the "OggS" capture pattern,
/// tracking a partial match across `didReceive` chunk boundaries.
private final class OggPageCountingDelegate: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var pages = 0
    /// "OggS" capture pattern.
    private let pattern: [UInt8] = [0x4F, 0x67, 0x67, 0x53]
    private var matchLen = 0

    var oggPageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pages
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        for byte in data {
            if byte == pattern[matchLen] {
                matchLen += 1
                if matchLen == pattern.count {
                    pages += 1
                    matchLen = 0
                }
            } else {
                // Reset, but the mismatching byte may itself begin a new match.
                matchLen = (byte == pattern[0]) ? 1 : 0
            }
        }
        lock.unlock()
    }
}
