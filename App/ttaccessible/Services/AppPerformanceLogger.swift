//
//  AppPerformanceLogger.swift
//  ttaccessible
//

import Foundation

final class AppPerformanceLogger {
    static let shared = AppPerformanceLogger()

    private let lock = NSLock()
    private var counters = [String: Int]()

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

    func increment(_ name: String) {
        lock.lock()
        counters[name, default: 0] += 1
        let count = counters[name] ?? 0
        lock.unlock()
        log("\(name) count=\(count)")
    }

    func mark(_ message: String) {
        log(message)
    }

    private func log(_ message: String) {
        lock.lock()
        NSLog("AppPerformance: \(message)")
        lock.unlock()
    }
}
