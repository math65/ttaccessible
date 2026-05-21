//
//  VideoFrameView.swift
//  ttaccessible
//

import AppKit

final class VideoFrameView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.text("video.panel.placeholder"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func update(frame payload: VideoFramePayload?) {
        guard let payload, payload.isEmpty == false else {
            imageLayer.contents = nil
            return
        }

        let width = payload.width
        let height = payload.height
        let bytesPerRow = width * 4
        guard payload.pixels.count >= bytesPerRow * height else { return }

        guard let provider = CGDataProvider(data: payload.pixels as CFData) else { return }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return
        }

        imageLayer.contents = image
    }

    func setAccessibilitySourceLabel(_ label: String) {
        if label.isEmpty {
            setAccessibilityLabel(L10n.text("video.panel.placeholder"))
        } else {
            setAccessibilityLabel(label)
        }
    }
}
