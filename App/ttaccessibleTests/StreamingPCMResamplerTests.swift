import XCTest
@testable import ttaccessible

final class StreamingPCMResamplerTests: XCTestCase {
    func testChangingCallbackSizesPreservesTimeAndWaveform() {
        for (inputRate, outputRate) in [(44_100.0, 48_000.0), (48_000.0, 44_100.0), (48_000.0, 16_000.0)] {
            for channels in [1, 2] {
                let frames = 102_400
                let source: [Int16] = (0..<frames).flatMap { frame in
                    (0..<channels).map { channel in
                        Int16((sin(2 * .pi * Double(1000 + channel * 250) * Double(frame) / inputRate) * 16_000).rounded())
                    }
                }
                let whole = AudioPCMResampler.Stream().process(source, frameCount: frames,
                    channels: channels, inputRate: inputRate, outputRate: outputRate)
                let stream = AudioPCMResampler.Stream()
                var split: [Int16] = []
                var offset = 0, callback = 0
                let sizes = [1, 137, 512, 1024, 1764]
                while offset < frames {
                    let count = min(sizes[callback % sizes.count], frames - offset)
                    let result = stream.process(Array(source[(offset * channels)..<((offset + count) * channels)]),
                        frameCount: count, channels: channels, inputRate: inputRate, outputRate: outputRate)
                    XCTAssertEqual(result.samples.count, result.frameCount * channels)
                    split += result.samples
                    offset += count; callback += 1
                }
                XCTAssertEqual(split.count, whole.samples.count, "No rounding drift across callbacks")
                let maximumDifference = zip(split, whole.samples).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(maximumDifference, 1, "No phase resets at callback boundaries")
            }
        }
    }

    func testResetRemovesPreviousStreamHistory() {
        let samples: [Int16] = [0, 1000, -1000, 2000, -2000]
        let stream = AudioPCMResampler.Stream()
        let first = stream.process(samples, frameCount: 5, channels: 1, inputRate: 44_100, outputRate: 48_000)
        _ = stream.process(samples, frameCount: 5, channels: 1, inputRate: 44_100, outputRate: 48_000)
        stream.reset()
        XCTAssertEqual(stream.process(samples, frameCount: 5, channels: 1,
            inputRate: 44_100, outputRate: 48_000).samples, first.samples)
    }

    func testSameRatePreservesSamplesAndInvalidInputProducesNoAudio() {
        let stream = AudioPCMResampler.Stream()
        let samples: [Int16] = [.min, 0, .max, 42]
        XCTAssertEqual(stream.process(samples, frameCount: 2, channels: 2,
            inputRate: 48_000, outputRate: 48_000).samples, samples)
        XCTAssertEqual(stream.process(samples, frameCount: 3, channels: 2,
            inputRate: 48_000, outputRate: 48_000).frameCount, 0)
        XCTAssertEqual(stream.process(samples, frameCount: 2, channels: 2,
            inputRate: .nan, outputRate: 48_000).frameCount, 0)
    }
}
