//
//  MediaStreamSourceViewController.swift
//  ttaccessible
//
//  "Choose an audio source to stream" sheet: a source button whose menu lists
//  the input devices and VoiceOver at the top level, with the applications in
//  an "Application" submenu, plus the monitor and mute-source options.
//
//  This is a SHEET hosting a plain view controller, not an NSAlert. That is
//  what makes the menu work: the dialog used to be an NSAlert run app-modally,
//  and in a modal session AppKit never delivers an NSMenuItem's action, so no
//  source could be selected at all — the menu opened, highlighted and dismissed
//  while the choice was silently dropped. Outside a modal session the menu, its
//  submenu and their actions all behave normally.
//

import AppKit
import UniformTypeIdentifiers

final class MediaStreamSourceViewController: NSViewController {

    /// Confirmed with the chosen source, which of its channels to broadcast,
    /// whether to monitor it locally, and whether to mute it on this Mac while
    /// streaming.
    var onStream: ((DeviceStreamCaptureSpec, InputChannelPreset, Bool, Bool) -> Void)?

    private let devices: [InputAudioDeviceInfo]
    private var applicationSources: [DeviceStreamCaptureSpec]
    private let voiceOverAvailable: Bool
    private let allowsApplicationBrowsing: Bool
    private let preselectedToken: String?
    private let fallbackDeviceUID: String?
    /// This device's remembered channel routing, asked for as the selection
    /// changes rather than passed up front — the answer depends on which device
    /// the user lands on.
    private let storedChannelPreset: (String?) -> InputChannelPreset

    /// An application picked by browsing that isn't in the running list — kept
    /// so it stays visible and checkable in the submenu.
    private var browsedApplication: DeviceStreamCaptureSpec?
    private var selectedSource: DeviceStreamCaptureSpec?

    private var sourceButton: NSButton!
    private var channelButton: NSButton!
    private var monitorCheckbox: NSButton!
    private var muteSourceCheckbox: NSButton?
    private var streamButton: NSButton!

    /// Channel routing for the selected device. Only devices with more than a
    /// stereo pair have anything to choose between, so for anything else the
    /// button is HIDDEN rather than disabled — VoiceOver still announces a
    /// dimmed control, and there is nothing to say about this one.
    private var channelOptions: [InputChannelPresetOption] = []
    private var channelSelection: InputChannelPreset = .auto

    /// - Parameters:
    ///   - allowsApplicationBrowsing: browsing for a not-yet-running app needs
    ///     the process-tap backend's wait-and-attach (macOS 14.2+); the
    ///     ScreenCaptureKit tier can only capture apps that are already running.
    init(devices: [InputAudioDeviceInfo],
         applicationSources: [DeviceStreamCaptureSpec],
         voiceOverAvailable: Bool,
         allowsApplicationBrowsing: Bool,
         preselectedToken: String?,
         fallbackDeviceUID: String?,
         storedChannelPreset: @escaping (String?) -> InputChannelPreset = { _ in .auto }) {
        self.devices = devices
        self.applicationSources = applicationSources
        self.voiceOverAvailable = voiceOverAvailable
        self.allowsApplicationBrowsing = allowsApplicationBrowsing
        self.preselectedToken = preselectedToken
        self.fallbackDeviceUID = fallbackDeviceUID
        self.storedChannelPreset = storedChannelPreset
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 210))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        selectPreferredSource()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.initialFirstResponder = sourceButton
        view.window?.makeFirstResponder(sourceButton)
        // Return confirms even while the source button holds focus; a key
        // equivalent alone doesn't carry in a sheet.
        view.window?.defaultButtonCell = streamButton.cell as? NSButtonCell
    }

    // MARK: - Sources

    /// Every selectable source, flat, in menu order — used for preselection and
    /// for restoring a remembered choice.
    private var orderedSources: [DeviceStreamCaptureSpec] {
        var specs = devices.map { DeviceStreamCaptureSpec.inputDevice($0) }
        if voiceOverAvailable { specs.append(.voiceOver()) }
        specs.append(contentsOf: applicationSources)
        if let browsedApplication, specs.contains(browsedApplication) == false {
            specs.append(browsedApplication)
        }
        return specs
    }

    // MARK: - Setup

    private func setupLayout() {
        let header = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.title"))
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        header.translatesAutoresizingMaskIntoConstraints = false
        // AXHeading by raw value: the typed constant is macOS 26+, this app
        // targets 12. Same approach as MoveUsersViewController.
        header.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))

        let message = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.message"))
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false

        sourceButton = NSButton(title: "", target: self, action: #selector(showSourceMenu))
        sourceButton.bezelStyle = .rounded
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        // Reads as a pop-up button rather than a plain button: the role can be
        // overridden here, unlike the VALUE, which is why the title carries the
        // selected source.
        sourceButton.setAccessibilityRole(.popUpButton)
        sourceButton.setAccessibilityLabel(L10n.text("mediaStream.device.prompt.sourceLabel"))

        // Which channels of a multi-channel device are broadcast: a 32-channel
        // desk can send 5/6 rather than always 1/2. Same pop-up treatment as the
        // source button, and it sits directly under it.
        channelButton = NSButton(title: "", target: self, action: #selector(showChannelMenu))
        channelButton.bezelStyle = .rounded
        channelButton.translatesAutoresizingMaskIntoConstraints = false
        channelButton.setAccessibilityRole(.popUpButton)
        channelButton.setAccessibilityLabel(L10n.text("mediaStream.device.prompt.channelsLabel"))
        channelButton.isHidden = true

        // Off by default on purpose: the source is usually audible locally
        // already, and hearing it back a second time reads as an echo.
        monitorCheckbox = NSButton(checkboxWithTitle: L10n.text("mediaStream.device.prompt.monitor"),
                                   target: nil, action: nil)
        monitorCheckbox.state = .off
        monitorCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let optionsStack = NSStackView(views: [monitorCheckbox])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 6
        optionsStack.translatesAutoresizingMaskIntoConstraints = false

        // Mute-while-streaming (process taps only, macOS 14.2+): silence the
        // captured app/VoiceOver on this Mac so only the channel hears it.
        // Deliberately never persisted and off by default — an accidentally
        // muted VoiceOver would be catastrophic for a VoiceOver user.
        if #available(macOS 14.2, *) {
            let checkbox = NSButton(checkboxWithTitle: L10n.text("mediaStream.device.prompt.muteSource"),
                                    target: nil, action: nil)
            checkbox.state = .off
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            muteSourceCheckbox = checkbox
            optionsStack.addArrangedSubview(checkbox)
        }

        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        streamButton = NSButton(title: L10n.text("mediaStream.device.prompt.start"),
                                target: self, action: #selector(confirm))
        streamButton.bezelStyle = .rounded
        streamButton.keyEquivalent = "\r"
        streamButton.translatesAutoresizingMaskIntoConstraints = false

        // A stack, so hiding the channel button closes its gap instead of
        // leaving a hole where a control used to be.
        let pickerStack = NSStackView(views: [sourceButton, channelButton])
        pickerStack.orientation = .vertical
        pickerStack.alignment = .leading
        pickerStack.distribution = .fill
        pickerStack.spacing = 8
        pickerStack.translatesAutoresizingMaskIntoConstraints = false

        [header, message, pickerStack, optionsStack, cancelButton, streamButton]
            .forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            message.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            pickerStack.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 12),
            pickerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            pickerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            sourceButton.widthAnchor.constraint(equalTo: pickerStack.widthAnchor),
            channelButton.widthAnchor.constraint(equalTo: pickerStack.widthAnchor),

            optionsStack.topAnchor.constraint(equalTo: pickerStack.bottomAnchor, constant: 12),
            optionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            optionsStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            streamButton.topAnchor.constraint(greaterThanOrEqualTo: optionsStack.bottomAnchor, constant: 14),
            streamButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            streamButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            cancelButton.trailingAnchor.constraint(equalTo: streamButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
    }

    // MARK: - Menu

    @objc private func showSourceMenu() {
        let menu = NSMenu()
        for device in devices {
            menu.addItem(makeSourceItem(for: .inputDevice(device)))
        }

        let hasApplicationMenu = applicationSources.isEmpty == false
            || browsedApplication != nil
            || allowsApplicationBrowsing
        if voiceOverAvailable || hasApplicationMenu {
            if devices.isEmpty == false { menu.addItem(.separator()) }
            if voiceOverAvailable {
                menu.addItem(makeSourceItem(for: .voiceOver()))
            }
            if hasApplicationMenu {
                let submenu = NSMenu(title: L10n.text("mediaStream.device.group.applications"))
                var sources = applicationSources
                if let browsedApplication, sources.contains(browsedApplication) == false {
                    sources.append(browsedApplication)
                }
                for source in sources {
                    submenu.addItem(makeSourceItem(for: source))
                }
                if allowsApplicationBrowsing {
                    // Browse for ANY installed app, running or not: the tap
                    // backend waits for it and attaches when it plays audio.
                    if sources.isEmpty == false { submenu.addItem(.separator()) }
                    let browse = NSMenuItem(title: L10n.text("mediaStream.device.source.chooseApplication"),
                                            action: #selector(browseForApplication),
                                            keyEquivalent: "")
                    browse.target = self
                    submenu.addItem(browse)
                }
                let parent = NSMenuItem(title: L10n.text("mediaStream.device.group.applications"),
                                        action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sourceButton.bounds.height + 2),
                   in: sourceButton)
    }

    private func makeSourceItem(for spec: DeviceStreamCaptureSpec) -> NSMenuItem {
        let item = NSMenuItem(title: spec.displayName, action: #selector(selectSource(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = spec
        item.state = spec == selectedSource ? .on : .off
        return item
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? DeviceStreamCaptureSpec else { return }
        applySelection(spec)
    }

    // MARK: - Selection

    private func applySelection(_ spec: DeviceStreamCaptureSpec) {
        selectedSource = spec
        sourceButton.title = spec.displayName
        updateChannelOptions(for: spec)
        updateMuteAvailability()
        // The button's VALUE can't be overridden, so the selection is announced
        // explicitly — otherwise a VoiceOver user gets no feedback that the
        // choice took.
        NSAccessibility.post(
            element: sourceButton as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: spec.displayName,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    /// Restores the last streamed source, falling back to the default input
    /// device and then to whatever comes first.
    private func selectPreferredSource() {
        if let token = preselectedToken,
           let match = orderedSources.first(where: { $0.persistenceToken == token }) {
            applySelection(match)
            return
        }
        if let fallbackDeviceUID,
           let device = devices.first(where: { $0.uid == fallbackDeviceUID }) {
            applySelection(.inputDevice(device))
            return
        }
        if let first = orderedSources.first { applySelection(first) }
    }

    /// Repopulates the channel picker for the newly-selected source. Only an
    /// input device with more than a stereo pair offers a choice; app and
    /// VoiceOver sources are already a stereo mixdown. A remembered routing that
    /// no longer fits the device (it was swapped for a smaller one) falls back
    /// to Auto rather than silently pointing at channels that aren't there.
    private func updateChannelOptions(for spec: DeviceStreamCaptureSpec) {
        guard case .inputDevice(let device) = spec, device.inputChannels > 2 else {
            channelOptions = []
            channelSelection = .auto
            channelButton.isHidden = true
            return
        }
        channelOptions = InputAudioDeviceResolver.availablePresetOptions(for: device)
        let stored = storedChannelPreset(device.uid)
        channelSelection = InputAudioDeviceResolver.contains(stored, for: device) ? stored : .auto
        channelButton.isHidden = false
        refreshChannelTitle()
    }

    private func refreshChannelTitle() {
        channelButton.title = channelOptions.first { $0.preset == channelSelection }?.title
            ?? InputAudioDeviceResolver.title(for: channelSelection)
    }

    @objc private func showChannelMenu() {
        guard channelOptions.isEmpty == false else { return }
        let menu = NSMenu()
        for option in channelOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectChannelOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.preset
            item.state = option.preset == channelSelection ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: channelButton.bounds.height + 2),
                   in: channelButton)
    }

    @objc private func selectChannelOption(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? InputChannelPreset else { return }
        channelSelection = preset
        refreshChannelTitle()
        // Same reason as the source button: an NSButton's VALUE can't be
        // overridden, so the new routing is announced explicitly.
        NSAccessibility.post(
            element: channelButton as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: channelButton.title,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func updateMuteAvailability() {
        guard let muteSourceCheckbox else { return }
        let isProcessSource: Bool
        if case .processes = selectedSource { isProcessSource = true } else { isProcessSource = false }
        muteSourceCheckbox.isEnabled = isProcessSource
        if isProcessSource == false { muteSourceCheckbox.state = .off }
    }

    // MARK: - Actions

    @objc private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, bundleID.isEmpty == false else {
            NSSound.beep()
            return
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let spec = DeviceStreamCaptureSpec.application(bundleID: bundleID, displayName: name)
        browsedApplication = spec
        applySelection(spec)
    }

    @objc private func confirm() {
        guard let spec = selectedSource else { return }
        dismiss(nil)
        onStream?(spec, channelSelection, monitorCheckbox.state == .on, muteSourceCheckbox?.state == .on)
    }

    @objc private func cancel() {
        dismiss(nil)
    }
}
