//
//  ActiveTasksStatusBarController.swift
//  Turbotask
//
//  Persistent menu bar extra for the Day Battery plus in-progress shortcuts.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ActiveTasksStatusBarController: NSObject {
    static let shared = ActiveTasksStatusBarController()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusLineItem: NSMenuItem?
    private var windowLineItem: NSMenuItem?
    private var nextLineItem: NSMenuItem?
    private var activeSeparatorItem: NSMenuItem?
    private var activeHeaderItem: NSMenuItem?
    private var activeTaskItems: [NSMenuItem] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var store: TurboTaskStore?
    private var lastRenderSignature = ""
    private let calendar = Calendar.autoupdatingCurrent
    private let clock = DayBatteryClock.shared

    private override init() {
        super.init()
    }

    func startObserving(_ store: TurboTaskStore) {
        guard self.store !== store else { return }
        self.store = store
        cancellables.removeAll()

        store.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        clock.start()

        clock.$now
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        guard let store else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            statusMenu = nil
            statusLineItem = nil
            windowLineItem = nil
            nextLineItem = nil
            activeSeparatorItem = nil
            activeHeaderItem = nil
            activeTaskItems.removeAll()
            lastRenderSignature = ""
            return
        }

        let active = store.activeTasks
        let battery = DayBatteryStatus(
            now: clock.now,
            startMinutes: store.dayBatteryStartMinutes,
            endMinutes: store.dayBatteryEndMinutes,
            calendar: calendar
        )

        let activeSignature = active.map(\.task.title).joined(separator: "|")
        let renderSignature = [
            battery.chargePercentLabel,
            battery.primaryLine,
            battery.nextBoundaryLabel,
            battery.windowLabel,
            String(store.dayBatteryShowsPercentageInMenuBar),
            String(store.dayBatteryUsesWideMenuBarItem),
            activeSignature
        ].joined(separator: "||")

        let item = statusItem ?? makeStatusItem()
        statusItem = item
        item.isVisible = true
        if item.menu == nil {
            item.menu = makeMenu()
        }

        configureButton(
            item.button,
            battery: battery,
            active: active,
            showsPercentage: store.dayBatteryShowsPercentageInMenuBar,
            usesWideLayout: store.dayBatteryUsesWideMenuBarItem
        )

        guard renderSignature != lastRenderSignature else { return }
        lastRenderSignature = renderSignature
        updateMenu(battery: battery, active: active)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        statusMenu = menu

        let header = NSMenuItem(title: "Day Battery", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusLineItem = statusLine

        let windowLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        windowLine.isEnabled = false
        menu.addItem(windowLine)
        windowLineItem = windowLine

        let nextLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        nextLine.isEnabled = false
        menu.addItem(nextLine)
        nextLineItem = nextLine

        let activeSeparator = NSMenuItem.separator()
        menu.addItem(activeSeparator)
        activeSeparatorItem = activeSeparator

        let activeHeader = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        activeHeader.isEnabled = false
        menu.addItem(activeHeader)
        activeHeaderItem = activeHeader

        menu.addItem(.separator())

        let openBatteryItem = NSMenuItem(title: "Open Day Battery", action: #selector(openBattery), keyEquivalent: "")
        openBatteryItem.target = self
        menu.addItem(openBatteryItem)

        let openItem = NSMenuItem(title: "Open Turbo…", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        return menu
    }

    private func updateMenu(battery: DayBatteryStatus, active: [TaskContext]) {
        statusLineItem?.title = "\(battery.chargePercentLabel)  \(battery.primaryLine)"
        windowLineItem?.title = "Window: \(battery.windowLabel)"
        nextLineItem?.title = "Next marker: \(battery.nextBoundaryLabel)"

        activeTaskItems.forEach { item in
            statusMenu?.removeItem(item)
        }
        activeTaskItems.removeAll()

        let hasActiveTasks = !active.isEmpty
        activeSeparatorItem?.isHidden = !hasActiveTasks
        activeHeaderItem?.isHidden = !hasActiveTasks
        activeHeaderItem?.title = active.count == 1 ? "In progress" : "In progress (\(active.count))"

        guard hasActiveTasks,
              let statusMenu,
              let activeHeaderItem,
              let insertionIndex = statusMenu.items.firstIndex(of: activeHeaderItem)
        else {
            return
        }

        var nextIndex = insertionIndex + 1
        for context in active {
            let item = NSMenuItem(title: context.task.title, action: #selector(openApp), keyEquivalent: "")
            item.target = self
            statusMenu.insertItem(item, at: nextIndex)
            activeTaskItems.append(item)
            nextIndex += 1
        }
    }

    private func configureButton(
        _ button: NSStatusBarButton?,
        battery: DayBatteryStatus,
        active: [TaskContext],
        showsPercentage: Bool,
        usesWideLayout: Bool
    ) {
        guard let button else { return }

        button.image = batteryImage(
            charge: battery.charge,
            tint: menuTint(for: battery),
            isWide: usesWideLayout
        )
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(
            string: showsPercentage ? battery.chargePercentLabel : "",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.contentTintColor = nil
        button.appearsDisabled = false
        button.toolTip = batteryTooltip(battery: battery, active: active)
    }

    private func batteryTooltip(battery: DayBatteryStatus, active: [TaskContext]) -> String {
        if active.isEmpty {
            return "\(battery.primaryLine)\nWindow: \(battery.windowLabel)\nNext: \(battery.nextBoundaryLabel)"
        }

        let activeTitles = active.map(\.task.title).joined(separator: ", ")
        return "\(battery.primaryLine)\nWindow: \(battery.windowLabel)\nActive: \(activeTitles)"
    }

    private func batteryImage(charge: Double, tint: NSColor, isWide: Bool) -> NSImage {
        let size = isWide ? NSSize(width: 42, height: 15) : NSSize(width: 28, height: 15)

        let image = NSImage(size: size, flipped: false) { _ in
            let bodyWidth = isWide ? 36.0 : 22.0
            let body = NSRect(x: 0.75, y: 2, width: bodyWidth, height: 11)
            let tip = NSRect(x: body.maxX + 1.25, y: 5, width: 3, height: 5)
            let shellColor = NSColor.labelColor.withAlphaComponent(0.08)
            let strokeColor = tint.withAlphaComponent(0.96)
            let fillColor = tint.withAlphaComponent(0.88)

            shellColor.setFill()
            NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2).fill()

            strokeColor.setStroke()
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
            bodyPath.lineWidth = 1.35
            bodyPath.stroke()

            fillColor.setFill()
            NSBezierPath(roundedRect: tip, xRadius: 1.6, yRadius: 1.6).fill()

            let inset = body.insetBy(dx: 1.8, dy: 1.8)
            let fillWidth = min(
                inset.width,
                max(inset.width * charge, charge > 0.01 ? 2.4 : 0)
            )

            if fillWidth > 0 {
                NSBezierPath(
                    roundedRect: NSRect(x: inset.minX, y: inset.minY, width: fillWidth, height: inset.height),
                    xRadius: 2,
                    yRadius: 2
                ).fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func menuTint(for battery: DayBatteryStatus) -> NSColor {
        switch battery.phase {
        case .upcoming:
            return .controlAccentColor
        case .active:
            switch battery.charge {
            case 0.6...:
                return .systemGreen
            case 0.3...:
                return .systemOrange
            default:
                return .systemRed
            }
        case .ended:
            return .secondaryLabelColor
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        return item
    }

    @objc private func openBattery() {
        store?.selectedScreen = .battery
        openApp()
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
