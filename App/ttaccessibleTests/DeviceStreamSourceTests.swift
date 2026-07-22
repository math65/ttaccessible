//
//  DeviceStreamSourceTests.swift
//  ttaccessibleTests
//
//  Live-loopback integration check for AudioDeviceStreamSource (device → channel
//  media streaming): starts the real capture + loopback Ogg Opus server, verifies
//  the TeamTalk SDK's FFmpeg probe accepts the stream, and confirms the server
//  paces output to realtime — the guarantee that a silent or stalled device never
//  starves the SDK reader (a starved stream ends the broadcast).
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
        //    stream is small-packet Opus rather than WAV/AAC — finish its
        //    analysis fast. Everything the analyzer consumes becomes permanent
        //    broadcast latency, so this bound is a real latency budget
        //    (PCM measured ~4.3 s here, AAC ~2 s, Opus ~0.4 s).
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
        //    few bytes per packet — so count Ogg pages instead: the encoder
        //    emits one 5 ms Opus packet per page, so 3 s ≈ 600 pages (+2
        //    header pages). Bounds are wide for scheduler jitter and the
        //    operating-buffer startup credit.
        let counter = ByteCountingDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: counter, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        task.resume()
        Thread.sleep(forTimeInterval: 3.0)
        task.cancel()

        let pages = counter.oggPageCount
        XCTAssertGreaterThan(pages, 250,
                             "stream is starving — silence padding is not keeping it alive (\(pages) Ogg pages in 3 s)")
        XCTAssertLessThan(pages, 1200,
                          "stream is not paced to realtime — dumping data (\(pages) Ogg pages in 3 s)")
    }
}

private final class ByteCountingDelegate: NSObject, URLSessionDataDelegate {
    private static let capturePattern: [UInt8] = Array("OggS".utf8)

    private let lock = NSLock()
    private var bytes = 0
    private var pages = 0
    private var matchIndex = 0

    var receivedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    /// Ogg pages seen so far ("OggS" capture patterns, matched across chunk
    /// boundaries).
    var oggPageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pages
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        bytes += data.count
        for byte in data {
            if byte == Self.capturePattern[matchIndex] {
                matchIndex += 1
                if matchIndex == Self.capturePattern.count {
                    pages += 1
                    matchIndex = 0
                }
            } else {
                matchIndex = byte == Self.capturePattern[0] ? 1 : 0
            }
        }
        lock.unlock()
    }
}
