//
//  ServerPropertiesViewController.swift
//  ttaccessible
//

import AppKit

final class ServerPropertiesViewController: NSViewController {

    var onSave: ((ServerPropertiesData) -> Void)?

    private var properties: ServerPropertiesData

    private var nameField: NSTextField!
    private var motdView: NSTextView!
    private var maxUsersField: NSTextField!
    private var userTimeoutField: NSTextField!
    private var loginDelayField: NSTextField!
    private var maxLoginAttemptsField: NSTextField!
    private var maxLoginsPerIPField: NSTextField!
    private var autoSaveCheck: NSButton!
    private var maxVoiceTxField: NSTextField!
    private var maxVideoTxField: NSTextField!
    private var maxMediaFileTxField: NSTextField!
    private var maxDesktopTxField: NSTextField!
    private var maxTotalTxField: NSTextField!

    init(properties: ServerPropertiesData) {
        self.properties = properties
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 540))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFields()
        setupLayout()
        setupButtons()
        populate()
    }

    // MARK: - Setup

    private func setupFields() {
        nameField = NSTextField()
        nameField.setAccessibilityLabel(L10n.text("serverProperties.form.name"))

        motdView = NSTextView()
        motdView.isRichText = false
        motdView.isAutomaticQuoteSubstitutionEnabled = false
        motdView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        motdView.setAccessibilityLabel(L10n.text("serverProperties.form.motd"))

        maxUsersField = numericField(label: "serverProperties.form.maxUsers")
        userTimeoutField = numericField(label: "serverProperties.form.userTimeout")
        loginDelayField = numericField(label: "serverProperties.form.loginDelayMSec")
        maxLoginAttemptsField = numericField(label: "serverProperties.form.maxLoginAttempts")
        maxLoginsPerIPField = numericField(label: "serverProperties.form.maxLoginsPerIPAddress")

        autoSaveCheck = NSButton(checkboxWithTitle: L10n.text("serverProperties.form.autoSave"), target: nil, action: nil)

        maxVoiceTxField = numericField(label: "serverProperties.form.maxVoiceTx")
        maxVideoTxField = numericField(label: "serverProperties.form.maxVideoTx")
        maxMediaFileTxField = numericField(label: "serverProperties.form.maxMediaFileTx")
        maxDesktopTxField = numericField(label: "serverProperties.form.maxDesktopTx")
        maxTotalTxField = numericField(label: "serverProperties.form.maxTotalTx")
    }

    private func setupLayout() {
        // Scroll container
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // Section Général
        contentStack.addArrangedSubview(sectionHeader(L10n.text("serverProperties.form.section.general")))

        let motdScrollView = NSScrollView()
        motdScrollView.documentView = motdView
        motdScrollView.hasVerticalScroller = true
        motdScrollView.borderType = .bezelBorder

        let generalRows: [(String, NSView)] = [
            ("serverProperties.form.name", nameField),
            ("serverProperties.form.motd", motdScrollView),
            ("serverProperties.form.maxUsers", maxUsersField),
            ("serverProperties.form.userTimeout", userTimeoutField),
            ("serverProperties.form.loginDelayMSec", loginDelayField),
            ("serverProperties.form.maxLoginAttempts", maxLoginAttemptsField),
            ("serverProperties.form.maxLoginsPerIPAddress", maxLoginsPerIPField),
        ]

        for (key, field) in generalRows {
            contentStack.addArrangedSubview(makeRow(labelKey: key, field: field, fieldHeight: key == "serverProperties.form.motd" ? 60 : 22))
        }
        // autoSave checkbox (full width)
        autoSaveCheck.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(autoSaveCheck)

        // Section Limites de débit
        contentStack.addArrangedSubview(sectionHeader(L10n.text("serverProperties.form.section.bandwidth")))

        let bwRows: [(String, NSView)] = [
            ("serverProperties.form.maxVoiceTx", maxVoiceTxField),
            ("serverProperties.form.maxVideoTx", maxVideoTxField),
            ("serverProperties.form.maxMediaFileTx", maxMediaFileTxField),
            ("serverProperties.form.maxDesktopTx", maxDesktopTxField),
            ("serverProperties.form.maxTotalTx", maxTotalTxField),
        ]
        for (key, field) in bwRows {
            contentStack.addArrangedSubview(makeRow(labelKey: key, field: field, fieldHeight: 22))
        }

        // Scroll wrap
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        let clipView = scrollView.contentView
        scrollView.documentView = contentStack

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -52),
            contentStack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])
    }

    private func setupButtons() {
        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: L10n.text("common.save"), target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(cancelButton)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Populate

    private func populate() {
        nameField.stringValue = properties.name
        motdView.string = properties.motdRaw
        maxUsersField.stringValue = String(properties.maxUsers)
        userTimeoutField.stringValue = String(properties.userTimeout)
        loginDelayField.stringValue = String(properties.loginDelayMSec)
        maxLoginAttemptsField.stringValue = String(properties.maxLoginAttempts)
        maxLoginsPerIPField.stringValue = String(properties.maxLoginsPerIPAddress)
        autoSaveCheck.state = properties.autoSave ? .on : .off
        maxVoiceTxField.stringValue = String(properties.maxVoiceTxPerSecond)
        maxVideoTxField.stringValue = String(properties.maxVideoCaptureTxPerSecond)
        maxMediaFileTxField.stringValue = String(properties.maxMediaFileTxPerSecond)
        maxDesktopTxField.stringValue = String(properties.maxDesktopTxPerSecond)
        maxTotalTxField.stringValue = String(properties.maxTotalTxPerSecond)
    }

    // MARK: - Actions

    @objc private func save() {
        var updated = properties
        updated.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.motdRaw = motdView.string
        updated.maxUsers = Int32(maxUsersField.stringValue) ?? properties.maxUsers
        updated.userTimeout = Int32(userTimeoutField.stringValue) ?? properties.userTimeout
        updated.loginDelayMSec = Int32(loginDelayField.stringValue) ?? properties.loginDelayMSec
        updated.maxLoginAttempts = Int32(maxLoginAttemptsField.stringValue) ?? properties.maxLoginAttempts
        updated.maxLoginsPerIPAddress = Int32(maxLoginsPerIPField.stringValue) ?? properties.maxLoginsPerIPAddress
        updated.autoSave = autoSaveCheck.state == .on
        updated.maxVoiceTxPerSecond = Int32(maxVoiceTxField.stringValue) ?? properties.maxVoiceTxPerSecond
        updated.maxVideoCaptureTxPerSecond = Int32(maxVideoTxField.stringValue) ?? properties.maxVideoCaptureTxPerSecond
        updated.maxMediaFileTxPerSecond = Int32(maxMediaFileTxField.stringValue) ?? properties.maxMediaFileTxPerSecond
        updated.maxDesktopTxPerSecond = Int32(maxDesktopTxField.stringValue) ?? properties.maxDesktopTxPerSecond
        updated.maxTotalTxPerSecond = Int32(maxTotalTxField.stringValue) ?? properties.maxTotalTxPerSecond

        dismiss(nil)
        onSave?(updated)
    }

    @objc private func cancel() {
        dismiss(nil)
    }

    // MARK: - Helpers

    private func numericField(label: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "0"
        field.setAccessibilityLabel(L10n.text(label))
        return field
    }

    private func sectionHeader(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let stack = NSStackView(views: [spacer, label])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        return stack
    }

    private func makeRow(labelKey: String, field: NSView, fieldHeight: CGFloat) -> NSView {
        let lbl = NSTextField(labelWithString: L10n.text(labelKey))
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(lbl)
        row.addSubview(field)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: fieldHeight + 4),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            lbl.widthAnchor.constraint(equalToConstant: 200),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: fieldHeight),
        ])

        return row
    }
}
