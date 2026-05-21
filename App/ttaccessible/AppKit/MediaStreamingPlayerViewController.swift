//
//  MediaStreamingPlayerViewController.swift
//  ttaccessible
//

import AppKit

@MainActor
protocol MediaStreamingPlayerActions: AnyObject {
    func mediaStreamingPlayerDidTogglePlayPause()
    func mediaStreamingPlayerDidStop()
    func mediaStreamingPlayerDidSeek(toMSec offsetMSec: UInt32)
    func mediaStreamingPlayerDidChangeBroadcastGainPercent(_ percent: Int)
}

final class MediaStreamingPlayerViewController: NSViewController {
    weak var actions: MediaStreamingPlayerActions?

    private let fileNameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let positionSlider = AccessibleSlider()
    private let playPauseButton = NSButton()
    private let stopButton = NSButton()
    private let broadcastGainSlider = AccessibleSlider()
    private let broadcastGainValueLabel = NSTextField(labelWithString: "")

    private var displayTimer: Timer?
    private var lastProgress = MediaStreamingProgress.inactive
    private var isUserDraggingPosition = false
    private var suppressGainAction = false

    override func loadView() {
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        view = visualEffectView
        configureUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startDisplayTimer()
        view.window?.makeFirstResponder(view)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopDisplayTimer()
    }

    func update(with progress: MediaStreamingProgress) {
        lastProgress = progress

        if let fileName = progress.fileName {
            fileNameLabel.stringValue = L10n.format("mediaPlayer.fileName.format", fileName)
        } else {
            fileNameLabel.stringValue = L10n.text("mediaPlayer.fileName.empty")
        }

        playPauseButton.title = progress.isPaused
            ? L10n.text("mediaPlayer.play")
            : L10n.text("mediaPlayer.pause")
        playPauseButton.setAccessibilityLabel(playPauseButton.title)

        if !isUserDraggingPosition {
            positionSlider.maxValue = max(1, Double(progress.durationMSec))
            positionSlider.doubleValue = Double(progress.elapsedMSec)
            positionSlider.isEnabled = progress.durationMSec > 0
        }

        suppressGainAction = true
        broadcastGainSlider.doubleValue = Double(progress.broadcastGainPercent)
        suppressGainAction = false
        broadcastGainValueLabel.stringValue = "\(progress.broadcastGainPercent)%"
        broadcastGainSlider.setAccessibilityValueDescription("\(progress.broadcastGainPercent)%")

        refreshTimeLabel()
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let noModifiers = modifiers.isDisjoint(with: [.command, .option, .control, .shift])

        switch event.keyCode {
        case 49: // Space
            if noModifiers {
                actions?.mediaStreamingPlayerDidTogglePlayPause()
                return
            }
        case 53: // Escape
            if noModifiers {
                actions?.mediaStreamingPlayerDidStop()
                return
            }
        case 123: // Left arrow
            if noModifiers {
                seekDelta(seconds: -5)
                return
            }
        case 124: // Right arrow
            if noModifiers {
                seekDelta(seconds: +5)
                return
            }
        case 126: // Up arrow
            if noModifiers {
                adjustBroadcastGain(delta: +5)
                return
            }
        case 125: // Down arrow
            if noModifiers {
                adjustBroadcastGain(delta: -5)
                return
            }
        default:
            break
        }

        super.keyDown(with: event)
    }

    private func seekDelta(seconds: Int) {
        guard lastProgress.isActive, lastProgress.durationMSec > 0 else { return }
        let currentMS = Int(currentEstimatedElapsedMSec())
        let durationMS = Int(lastProgress.durationMSec)
        let newMS = max(0, min(currentMS + seconds * 1000, durationMS - 1))
        actions?.mediaStreamingPlayerDidSeek(toMSec: UInt32(newMS))
    }

    private func adjustBroadcastGain(delta: Int) {
        guard lastProgress.isActive else { return }
        let newValue = max(0, min(100, lastProgress.broadcastGainPercent + delta))
        actions?.mediaStreamingPlayerDidChangeBroadcastGainPercent(newValue)
    }

    // MARK: - Actions (controls)

    @objc private func playPauseButtonClicked() {
        actions?.mediaStreamingPlayerDidTogglePlayPause()
    }

    @objc private func stopButtonClicked() {
        actions?.mediaStreamingPlayerDidStop()
    }

    @objc private func positionSliderAction(_ sender: NSSlider) {
        let isDragging = NSApp.currentEvent?.type == .leftMouseDragged
        if isDragging {
            isUserDraggingPosition = true
            updatePositionLabelPreview(forSliderValue: sender.doubleValue)
            return
        }
        isUserDraggingPosition = false
        let target = UInt32(max(0, sender.doubleValue))
        actions?.mediaStreamingPlayerDidSeek(toMSec: target)
    }

    @objc private func broadcastGainSliderAction(_ sender: NSSlider) {
        guard !suppressGainAction else { return }
        actions?.mediaStreamingPlayerDidChangeBroadcastGainPercent(Int(sender.doubleValue.rounded()))
    }

    // MARK: - Display refresh

    private func startDisplayTimer() {
        stopDisplayTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTimeLabel()
                self?.refreshPositionSliderIfNeeded()
            }
        }
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func refreshTimeLabel() {
        let elapsed = currentEstimatedElapsedMSec()
        timeLabel.stringValue = "\(formatMSec(elapsed)) / \(formatMSec(lastProgress.durationMSec))"
    }

    private func refreshPositionSliderIfNeeded() {
        guard lastProgress.isActive, lastProgress.durationMSec > 0, !isUserDraggingPosition else { return }
        positionSlider.doubleValue = Double(currentEstimatedElapsedMSec())
    }

    private func currentEstimatedElapsedMSec() -> UInt32 {
        guard lastProgress.isActive else { return 0 }
        guard !lastProgress.isPaused, let sampledAt = lastProgress.elapsedSampleAt else {
            return lastProgress.elapsedMSec
        }
        let delta = Date().timeIntervalSince(sampledAt) * 1000
        let projected = Double(lastProgress.elapsedMSec) + max(0, delta)
        let capped = lastProgress.durationMSec > 0
            ? min(projected, Double(lastProgress.durationMSec))
            : projected
        return UInt32(capped)
    }

    private func updatePositionLabelPreview(forSliderValue value: Double) {
        let elapsed = UInt32(max(0, value))
        timeLabel.stringValue = "\(formatMSec(elapsed)) / \(formatMSec(lastProgress.durationMSec))"
    }

    private func formatMSec(_ msec: UInt32) -> String {
        let totalSec = Int(msec / 1000)
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - UI

    private func configureUI() {
        fileNameLabel.font = .preferredFont(forTextStyle: .title3)
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.maximumNumberOfLines = 1
        fileNameLabel.setAccessibilityRole(.staticText)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor

        positionSlider.target = self
        positionSlider.action = #selector(positionSliderAction(_:))
        positionSlider.minValue = 0
        positionSlider.maxValue = 1
        positionSlider.doubleValue = 0
        positionSlider.isContinuous = true
        positionSlider.isEnabled = false
        positionSlider.pageStep = 10_000 // 10 seconds per Page Up / Page Down
        positionSlider.setAccessibilityLabel(L10n.text("mediaPlayer.position.label"))

        playPauseButton.bezelStyle = .rounded
        playPauseButton.title = L10n.text("mediaPlayer.pause")
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseButtonClicked)
        playPauseButton.keyEquivalent = ""

        stopButton.bezelStyle = .rounded
        stopButton.title = L10n.text("mediaPlayer.stop")
        stopButton.target = self
        stopButton.action = #selector(stopButtonClicked)

        broadcastGainSlider.target = self
        broadcastGainSlider.action = #selector(broadcastGainSliderAction(_:))
        broadcastGainSlider.minValue = 0
        broadcastGainSlider.maxValue = 100
        broadcastGainSlider.doubleValue = 50
        broadcastGainSlider.isContinuous = true
        broadcastGainSlider.setAccessibilityLabel(L10n.text("mediaPlayer.broadcastGain.label"))

        let controlsRow = NSStackView(views: [playPauseButton, stopButton])
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 8

        let broadcastGainTitle = NSTextField(labelWithString: L10n.text("mediaPlayer.broadcastGain.label"))
        broadcastGainTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let broadcastGainRow = NSStackView(views: [broadcastGainSlider, broadcastGainValueLabel])
        broadcastGainRow.orientation = .horizontal
        broadcastGainRow.spacing = 8
        broadcastGainRow.distribution = .fill
        broadcastGainSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        broadcastGainValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        broadcastGainValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let hint = NSTextField(labelWithString: L10n.text("mediaPlayer.shortcuts.hint"))
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0

        let stack = NSStackView(views: [
            fileNameLabel,
            timeLabel,
            positionSlider,
            controlsRow,
            broadcastGainTitle,
            broadcastGainRow,
            hint
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),

            positionSlider.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            positionSlider.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            broadcastGainRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            broadcastGainRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }
}
