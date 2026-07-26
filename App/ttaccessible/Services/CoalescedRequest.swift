//
//  CoalescedRequest.swift
//  ttaccessible
//

import Foundation

/// Thread-safe latest-value-wins box for high-frequency absolute-value requests
/// (key-repeat or slider-drag floods aimed at a serial work queue).
///
/// `submit` stores the newest value and returns true only when no apply pass is
/// currently queued — the caller schedules exactly one. Values submitted while
/// that pass is still waiting just overwrite the pending target, so a slow
/// consumer can never build a backlog that keeps applying stale steps after the
/// user stops adjusting.
///
/// Shaped as a struct facade over non-generic storage: a generic *class* here
/// crashes the Swift 6.3.2 release-mode optimizer (EarlyPerfInliner on the
/// generated deinit), so don't fold the two types back together.
struct CoalescedRequest<Value> {
    private let storage = CoalescedRequestStorage()

    /// Store `newValue` as the pending target. Returns true when the caller
    /// must schedule an apply pass (none is queued yet).
    func submit(_ newValue: Value) -> Bool {
        storage.submit(newValue)
    }

    /// Consume the newest pending value and allow the next submit to schedule
    /// again. The scheduled apply pass must always call this exactly once, even
    /// when it ends up not applying anything.
    func take() -> Value? {
        storage.take() as? Value
    }
}

private final class CoalescedRequestStorage {
    private let lock = NSLock()
    private var value: Any?
    private var applyScheduled = false

    func submit(_ newValue: Any) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
        if applyScheduled {
            return false
        }
        applyScheduled = true
        return true
    }

    func take() -> Any? {
        lock.lock()
        defer {
            value = nil
            applyScheduled = false
            lock.unlock()
        }
        return value
    }
}
