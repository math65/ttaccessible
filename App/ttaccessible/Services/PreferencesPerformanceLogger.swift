//
//  PreferencesPerformanceLogger.swift
//  ttaccessible
//

import Foundation

final class PreferencesPerformanceLogger {
    static let shared = PreferencesPerformanceLogger()

    private let lock = NSLock()
    private init() {}

    func beginInterval(_ name: String) -> CFAbsoluteTime {
        let startedAt = CFAbsoluteTimeGetCurrent()
        log("\(name) begin")
        return startedAt
    }

    func endInterval(_ name: String, _ startedAt: CFAbsoluteTime) {
        let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded())
        log("\(name) end elapsed_ms=\(elapsedMS)")
    }

    func mark(_ message: String) {
        log(message)
    }

    private func log(_ message: String) {
        lock.lock()
        NSLog("PreferencesPerformance: \(message)")
        lock.unlock()
    }
}
