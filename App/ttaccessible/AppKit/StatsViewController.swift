//
//  StatsViewController.swift
//  ttaccessible
//

import AppKit

final class StatsViewController: NSViewController {
    private let grid = NSGridView()
    private var refreshTimer: Timer?

    var onRefreshNeeded: (() -> Void)?

    override func loadView() {
        view = NSView()
        configureUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.onRefreshNeeded?()
        }
        onRefreshNeeded?()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func update(stats: ServerStatistics) {
        let rows = buildRows(from: stats)
        for (i, row) in rows.enumerated() {
            guard i < grid.numberOfRows else { break }
            (grid.cell(atColumnIndex: 1, rowIndex: i).contentView as? NSTextField)?.stringValue = row.value
        }
    }

    // MARK: - Private

    private struct Row {
        let label: String
        let value: String
    }

    private func buildRows(from stats: ServerStatistics) -> [Row] {
        [
            Row(label: L10n.text("stats.uptime"),        value: formatUptime(stats.nUptimeMSec)),
            Row(label: L10n.text("stats.usersServed"),   value: "\(stats.nUsersServed)"),
            Row(label: L10n.text("stats.usersPeak"),     value: "\(stats.nUsersPeak)"),
            Row(label: L10n.text("stats.totalTX"),       value: formatBytes(stats.nTotalBytesTX)),
            Row(label: L10n.text("stats.totalRX"),       value: formatBytes(stats.nTotalBytesRX)),
            Row(label: L10n.text("stats.voiceTX"),       value: formatBytes(stats.nVoiceBytesTX)),
            Row(label: L10n.text("stats.voiceRX"),       value: formatBytes(stats.nVoiceBytesRX)),
        ]
    }

    private func configureUI() {
        let placeholder = ServerStatistics()
        let rows = buildRows(from: placeholder)

        for row in rows {
            let labelField = NSTextField(labelWithString: row.label + " :")
            labelField.alignment = .right
            labelField.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

            let valueField = NSTextField(labelWithString: "—")
            valueField.alignment = .left

            grid.addRow(with: [labelField, valueField])
        }

        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            grid.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
        ])
    }

    private func formatUptime(_ ms: Int64) -> String {
        guard ms > 0 else { return "—" }
        let totalSeconds = Int(ms / 1000)
        let days    = totalSeconds / 86400
        let hours   = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return "\(days)j \(hours)h \(minutes)min" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes) min"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 o" }
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.1f Go", gb) }
        if mb >= 1 { return String(format: "%.1f Mo", mb) }
        return String(format: "%.1f Ko", kb)
    }
}
