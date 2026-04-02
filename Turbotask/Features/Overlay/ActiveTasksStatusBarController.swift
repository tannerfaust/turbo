//
//  ActiveTasksStatusBarController.swift
//  Turbotask
//
//  Menu bar extra when at least one task is in progress (active).
//

import AppKit
import Combine

@MainActor
final class ActiveTasksStatusBarController: NSObject {
    static let shared = ActiveTasksStatusBarController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private weak var store: TurboTaskStore?
    private var lastActiveTaskIDs: [UUID] = []

    private override init() {
        super.init()
    }

    func startObserving(_ store: TurboTaskStore) {
        guard self.store !== store else { return }
        self.store = store
        cancellables.removeAll()

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        guard let store else { return }
        let active = store.activeTasks
        let activeTaskIDs = active.map(\.task.id)

        if active.isEmpty {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            lastActiveTaskIDs = []
            return
        }

        guard activeTaskIDs != lastActiveTaskIDs || statusItem == nil else { return }
        lastActiveTaskIDs = activeTaskIDs

        let item = statusItem ?? makeStatusItem()
        statusItem = item

        item.isVisible = true
        item.button?.toolTip = active.count == 1
            ? "Active: \(active[0].task.title)"
            : "\(active.count) active tasks"

        let menu = NSMenu()
        let header = NSMenuItem(
            title: active.count == 1 ? "In progress" : "In progress (\(active.count))",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        for context in active {
            let title = context.task.title
            let mi = NSMenuItem(title: title, action: #selector(openApp), keyEquivalent: "")
            mi.target = self
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open Turbo…", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        item.menu = menu
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let side: CGFloat = 16
        if let base = NSImage(named: "AppLogo") {
            let logo = (base.copy() as? NSImage) ?? base
            logo.size = NSSize(width: side, height: side)
            item.button?.image = logo
            item.button?.symbolConfiguration = nil
            item.button?.contentTintColor = nil
        } else {
            item.button?.image = NSImage(
                systemSymbolName: "bolt.circle.fill",
                accessibilityDescription: "Active tasks"
            )
            item.button?.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            item.button?.contentTintColor = NSColor.systemGreen
        }
        item.button?.imagePosition = .imageOnly
        return item
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
