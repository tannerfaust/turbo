//
//  DayBatteryClock.swift
//  Turbotask
//
//  Shared time source for all Day Battery surfaces so the menu bar and
//  in-app screen always render the same snapshot.
//

import AppKit
import Combine
import Foundation

@MainActor
final class DayBatteryClock: NSObject, ObservableObject {
    static let shared = DayBatteryClock()

    @Published private(set) var now = Date()

    private let tickInterval: TimeInterval = 30
    private var timer: Timer?
    private var hasStarted = false
    private var notificationObservers: [(NotificationCenter, NSObjectProtocol)] = []

    private override init() {
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        installObservers()
        DispatchQueue.main.async { [weak self] in
            self?.refreshNow()
        }
    }

    func refreshNow() {
        now = Date()
        scheduleNextTick(after: now)
    }

    private func installObservers() {
        let appCenter = NotificationCenter.default
        notificationObservers.append((
            appCenter,
            appCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.refreshNow()
                }
            }
        ))
        notificationObservers.append((
            appCenter,
            appCenter.addObserver(
                forName: NSNotification.Name.NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.refreshNow()
                }
            }
        ))
        notificationObservers.append((
            appCenter,
            appCenter.addObserver(
                forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.refreshNow()
                }
            }
        ))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationObservers.append((
            workspaceCenter,
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.refreshNow()
                }
            }
        ))
    }

    private func scheduleNextTick(after date: Date) {
        timer?.invalidate()

        let reference = date.timeIntervalSinceReferenceDate
        let nextBoundary = (floor(reference / tickInterval) + 1) * tickInterval
        let fireDate = Date(timeIntervalSinceReferenceDate: nextBoundary)
        let timer = Timer(fireAt: fireDate, interval: 0, target: self, selector: #selector(handleTick), userInfo: nil, repeats: false)
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func handleTick() {
        refreshNow()
    }
}
