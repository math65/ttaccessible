//
//  OggOpusStreamEncoder.swift
//  ttaccessible
//
//  Encodes interleaved int16 PCM into an Ogg Opus byte stream for the device
//  loopback. WHY Opus instead of AAC: the SDK's FFmpeg analyzes a fixed batch
//  of packets when it opens the loopback (holding the audio lock — the channel
//  voice freeze). Opus at tiny frames (5 ms vs AAC's ~21 ms) puts far less audio
//  in that batch, so the analysis — and thus the freeze AND the standing
//  latency — shrink proportionally, while it stays a real (separate) media
//  stream.
//

import Foundation

final class OggOpusStreamEncoder {
    /// 5 ms frames at 48 kHz. Small frames = less media per analysis packet.
    static let frameSamplesPerChannel = 240
    private let sampleRate: Int
    private let channels: Int

    private let encoder: OpaquePointer
    private let preSkip: UInt16
    private var pending: [Int16] = []
    private var encodeBuffer = [UInt8](repeating: 0, count: 4096)

    // Ogg stream state.
    private let serial: UInt32
    private var pageSeq: UInt32 = 0
    private var granule: UInt64 = 0

    init?(sampleRate: Int, channels: Int, bitrate: Int32, serial: UInt32) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.serial = serial
        var error: Int32 = 0
        guard let enc = ttac_opus_create(Int32(sampleRate), Int32(channels), &error), error == 0 else {
            return nil
        }
        self.encoder = enc
        _ = ttac_opus_set_bitrate(enc, bitrate)
        self.preSkip = UInt16(clamping: ttac_opus_lookahead(enc))
    }

    deinit {
        ttac_opus_destroy(encoder)
    }

    /// The two Ogg header pages (OpusHead + OpusTags) that must precede audio.
    func streamHeaders() -> Data {
        var head = Data()
        head.append(contentsOf: Array("OpusHead".utf8))      // magic
        head.append(1)                                        // version
        head.append(UInt8(channels))                          // channel count
        head.appendLE(preSkip)                                // pre-skip
        head.appendLE(UInt32(sampleRate))                     // input sample rate
        head.appendLE(UInt16(0))                              // output gain
        head.append(0)                                        // channel mapping family

        var tags = Data()
        tags.append(contentsOf: Array("OpusTags".utf8))
        let vendor = Array("ttaccessible".utf8)
        tags.appendLE(UInt32(vendor.count))
        tags.append(contentsOf: vendor)
        tags.appendLE(UInt32(0))                              // 0 user comments

        var out = Data()
        out.append(makeOggPage(headerType: 0x02, granule: 0, packet: head))  // BOS
        out.append(makeOggPage(headerType: 0x00, granule: 0, packet: tags))
        return out
    }

    /// Encode interleaved int16 PCM; returns whatever complete Ogg audio pages
    /// the accumulated audio produced (possibly empty).
    func encode(_ samples: [Int16]) -> Data {
        pending.append(contentsOf: samples)
        let frameInterleaved = Self.frameSamplesPerChannel * channels
        var out = Data()
        while pending.count >= frameInterleaved {
            let frame = Array(pending.prefix(frameInterleaved))
            pending.removeFirst(frameInterleaved)
            let byteCount: Int32 = frame.withUnsafeBufferPointer { pcm in
                encodeBuffer.withUnsafeMutableBufferPointer { buf in
                    ttac_opus_encode(encoder, pcm.baseAddress,
                                     Int32(Self.frameSamplesPerChannel),
                                     buf.baseAddress, Int32(buf.count))
                }
            }
            guard byteCount > 0 else { continue }
            granule += UInt64(Self.frameSamplesPerChannel)
            let packet = Data(encodeBuffer[0..<Int(byteCount)])
            out.append(makeOggPage(headerType: 0x00, granule: granule, packet: packet))
        }
        return out
    }

    // MARK: - Ogg framing

    /// One Ogg page carrying a single Opus packet (simplest lacing — packets are
    /// small, so one per page never spans).
    private func makeOggPage(headerType: UInt8, granule: UInt64, packet: Data) -> Data {
        // Lacing: full 255-byte segments then a final remainder byte.
        var segments = [UInt8]()
        var remaining = packet.count
        while remaining >= 255 { segments.append(255); remaining -= 255 }
        segments.append(UInt8(remaining))

        var page = Data()
        page.append(contentsOf: Array("OggS".utf8))
        page.append(0)                       // stream structure version
        page.append(headerType)
        page.appendLE(granule)               // granule position (8)
        page.appendLE(serial)                // bitstream serial (4)
        page.appendLE(pageSeq)               // page sequence (4)
        let crcOffset = page.count
        page.appendLE(UInt32(0))             // CRC placeholder (4)
        page.append(UInt8(segments.count))   // number of page segments
        page.append(contentsOf: segments)    // segment table
        page.append(packet)                  // packet body

        let crc = Self.oggCRC(page)
        page[crcOffset]     = UInt8(crc & 0xFF)
        page[crcOffset + 1] = UInt8((crc >> 8) & 0xFF)
        page[crcOffset + 2] = UInt8((crc >> 16) & 0xFF)
        page[crcOffset + 3] = UInt8((crc >> 24) & 0xFF)

        pageSeq &+= 1
        return page
    }

    // Ogg CRC-32: polynomial 0x04c11db7, no reflection, init 0.
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var r = UInt32(i) << 24
            for _ in 0..<8 {
                r = (r & 0x8000_0000) != 0 ? (r << 1) ^ 0x04c1_1db7 : (r << 1)
            }
            table[i] = r
        }
        return table
    }()

    private static func oggCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            crc = (crc << 8) ^ crcTable[Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)]
        }
        return crc
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
    }
    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
    mutating func appendLE(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) { append(UInt8((value >> UInt64(shift)) & 0xFF)) }
    }
}
