//
//  UserInfoViewController.swift
//  ttaccessible
//

import AppKit

final class UserInfoViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: L10n.text("userInfo.empty"))
    private var valueLabels: [String: NSTextField] = [:]

    override func loadView() {
        view = NSVisualEffectView()
        configureUI()
    }

    var userStatisticsProvider: ((Int32) -> UserStatistics?)?

    func update(user: ConnectedServerUser?) {
        titleLabel.stringValue = user?.displayName ?? L10n.text("userInfo.window.title")

        let stats = user.flatMap { userStatisticsProvider?($0.id) }
        let packetLoss: String? = stats.map { s in
            let total = s.nVoicePacketsRecv + s.nVoicePacketsLost
            if total == 0 { return "0%" }
            let percent = Double(s.nVoicePacketsLost) / Double(total) * 100
            return String(format: "%.1f%% (%d / %d)", percent, s.nVoicePacketsLost, total)
        }

        let values: [(String, String?)] = [
            ("id", user.map { String($0.id) }),
            ("nickname", user?.nickname),
            ("username", user?.username.isEmpty == false ? user?.username : nil),
            ("statusMode", user.map { L10n.text($0.statusMode.localizationKey) }),
            ("statusMessage", user?.statusMessage.isEmpty == false ? user?.statusMessage : nil),
            ("gender", user.map { L10n.text($0.gender.localizationKey) }),
            ("userType", user.map { $0.isAdministrator ? L10n.text("userInfo.value.userType.admin") : L10n.text("userInfo.value.userType.default") }),
            ("channelOperator", user.map { $0.isChannelOperator ? L10n.text("common.yes") : L10n.text("common.no") }),
            ("ipAddress", user?.ipAddress.isEmpty == false ? user?.ipAddress : nil),
            ("client", user?.clientName.isEmpty == false ? user?.clientName : nil),
            ("version", user?.clientVersion.isEmpty == false ? user?.clientVersion : nil),
            ("packetLoss", packetLoss)
        ]

        var hasVisibleValues = false
        for (key, value) in values {
            guard let label = valueLabels[key] else {
                continue
            }
            if let value, value.isEmpty == false {
                label.stringValue = value
                label.superview?.isHidden = false
                hasVisibleValues = true
            } else {
                label.stringValue = ""
                label.superview?.isHidden = true
            }
        }

        emptyLabel.isHidden = hasVisibleValues
    }

    private func configureUI() {
        guard let backgroundView = view as? NSVisualEffectView else {
            return
        }
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active

        titleLabel.font = .preferredFont(forTextStyle: .title2)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.maximumNumberOfLines = 2

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        contentView.addSubview(stackView)

        let container = NSStackView(views: [titleLabel, emptyLabel, scrollView])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 14
        container.translatesAutoresizingMaskIntoConstraints = false

        backgroundView.addSubview(container)

        let rows = [
            ("id", "userInfo.field.id"),
            ("nickname", "userInfo.field.nickname"),
            ("username", "userInfo.field.username"),
            ("statusMode", "userInfo.field.statusMode"),
            ("statusMessage", "userInfo.field.statusMessage"),
            ("gender", "userInfo.field.gender"),
            ("userType", "userInfo.field.userType"),
            ("channelOperator", "userInfo.field.channelOperator"),
            ("ipAddress", "userInfo.field.ipAddress"),
            ("client", "userInfo.field.client"),
            ("version", "userInfo.field.version"),
            ("packetLoss", "userInfo.field.packetLoss")
        ]

        for (key, titleKey) in rows {
            let row = makeRow(title: L10n.text(titleKey))
            valueLabels[key] = row.valueLabel
            stackView.addArrangedSubview(row.container)
        }

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 20),
            container.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -20),

            scrollView.widthAnchor.constraint(equalTo: container.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func makeRow(title: String) -> (container: NSStackView, valueLabel: NSTextField) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let valueLabel = NSTextField(wrappingLabelWithString: "")
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.maximumNumberOfLines = 0
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        row.isHidden = true
        return (row, valueLabel)
    }
}
