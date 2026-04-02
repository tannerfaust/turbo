//
//  TaskMacTools.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Scan installed apps (icons only; no launch / automation)

struct InstalledMacApp: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
}

enum MacInstalledAppsScanner {
    /// Folders that hold `.app` bundles on typical macOS installs (requires matching sandbox read entitlements).
    private static var roots: [URL] {
        var list: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Developer/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        // De-dupe while preserving order.
        var seen = Set<String>()
        list = list.filter { seen.insert($0.path).inserted }
        return list
    }

    /// Bundle IDs Launch Services can resolve even when a bundle lives in a sealed/cryptex path the scanner might miss.
    private static let launchServicesHints: [String] = [
        // Apple — browsing & comms
        "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.FaceTime",
        "com.apple.Maps", "com.apple.news", "com.apple.stocks", "com.apple.weather",
        "com.apple.Passwords", "com.apple.findmy", "com.apple.Home", "com.apple.AppStore",
        // Media & creativity
        "com.apple.Music", "com.apple.TV", "com.apple.podcasts", "com.apple.Photos", "com.apple.iBooksX",
        "com.apple.freeform", "com.apple.VoiceMemos", "com.apple.GarageBand10", "com.apple.iMovieApp",
        "com.apple.FinalCut", "com.apple.logic10", "com.apple.motionapp", "com.apple.Compressor",
        // Productivity
        "com.apple.Notes", "com.apple.reminders", "com.apple.iCal", "com.apple.AddressBook",
        "com.apple.TextEdit", "com.apple.Preview", "com.apple.Numbers", "com.apple.Pages", "com.apple.Keynote",
        "com.apple.shortcuts", "com.apple.clock", "com.apple.calculator", "com.apple.ScreenTimeAgent",
        // System & dev tools
        "com.apple.systempreferences", "com.apple.systemsettings", "com.apple.Settings", "com.apple.Terminal", "com.apple.Console",
        "com.apple.ActivityMonitor", "com.apple.DiskUtility", "com.apple.ScriptEditor2", "com.apple.grapher",
        "com.apple.dt.Xcode", "com.apple.dt.Simulator", "com.apple.Instruments", "com.apple.AccessibilityInspector",
        "com.apple.FileMerge", "com.apple.InstallAssistant", "com.apple.BootCampAssistant",
        "com.apple.keychainaccess", "com.apple.DigitalColorMeter", "com.apple.AudioMIDISetup",
        "com.apple.ImageCapture", "com.apple.FontBook", "com.apple.ColorSyncUtility",
        "com.apple.BluetoothFileExchange", "com.apple.QuickTimePlayerX",
        // Browsers & common third‑party (no‑op if not installed)
        "com.google.Chrome", "com.google.Chrome.beta", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.openai.chat", "notion.id", "md.obsidian", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "com.spotify.client", "com.microsoft.teams", "com.microsoft.teams2", "us.zoom.xos",
        "com.adobe.acrobat.AcrobatDC", "com.adobe.Photoshop", "com.adobe.illustrator",
        "com.figma.Desktop", "com.postmanlabs.mac", "com.docker.docker",
    ]

    /// Scans Application folders for `.app` bundles, then merges apps Launch Services knows about (first call may take a moment).
    static func scanInstalledApps() -> [InstalledMacApp] {
        var byID: [String: InstalledMacApp] = [:]

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()

                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bid.isEmpty
                else { continue }

                let display =
                    (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let shortName =
                    (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = [display, shortName].compactMap(\.self).first(where: { !$0.isEmpty }) ?? bid

                if byID[bid] == nil {
                    byID[bid] = InstalledMacApp(bundleIdentifier: bid, name: name)
                }
            }
        }

        mergeLaunchServicesHints(into: &byID)

        return byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func mergeLaunchServicesHints(into byID: inout [String: InstalledMacApp]) {
        let ws = NSWorkspace.shared
        for hint in launchServicesHints {
            guard byID[hint] == nil else { continue }
            guard let url = ws.urlForApplication(withBundleIdentifier: hint) else { continue }
            guard let bundle = Bundle(url: url) else { continue }
            let bid = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? hint
            guard !bid.isEmpty, byID[bid] == nil else { continue }

            let display =
                (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortName =
                (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = [display, shortName].compactMap(\.self).first(where: { !$0.isEmpty }) ?? bid
            byID[bid] = InstalledMacApp(bundleIdentifier: bid, name: name)
        }
    }
}

enum MacAppIcon {
    static func nsImage(bundleIdentifier: String, pointSize: CGFloat) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: pointSize, height: pointSize)
            return icon
        }
        let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        fallback.size = NSSize(width: pointSize, height: pointSize)
        return fallback
    }
}

// MARK: - Icon strip (task rows, focus card)

struct TaskToolsIconRow: View {
    let bundleIDs: [String]
    var iconSize: CGFloat = 17
    var maxIcons: Int = 8

    var body: some View {
        let shown = Array(bundleIDs.prefix(maxIcons))
        let overflow = max(0, bundleIDs.count - maxIcons)

        if !shown.isEmpty {
            HStack(spacing: 4) {
                ForEach(shown, id: \.self) { bid in
                    Image(nsImage: MacAppIcon.nsImage(bundleIdentifier: bid, pointSize: iconSize * 2))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(TurboTheme.divider.opacity(0.45), lineWidth: 0.5)
                        )
                        .accessibilityHidden(true)
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TurboTheme.mutedInk.opacity(0.75))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tools: \(bundleIDs.count) apps")
        }
    }
}

// MARK: - Picker sheet

/// Keeps the filtered app list in a reference type so the key monitor always sees the current rows (same pattern as `TypeaheadLiveCount`).
private final class TaskToolsPickerLiveRows: ObservableObject {
    @Published private(set) var rows: [InstalledMacApp] = []

    func update(all: [InstalledMacApp], query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let next: [InstalledMacApp]
        if q.isEmpty {
            next = all
        } else {
            next = all.filter {
                $0.name.localizedCaseInsensitiveContains(q) || $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
            }
        }
        if next != rows {
            rows = next
        }
    }
}

struct TaskToolsPickerSheet: View {
    @Binding var bundleIDs: [String]
    @EnvironmentObject private var store: TurboTaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var apps: [InstalledMacApp] = []
    @State private var isLoading = true
    @StateObject private var rowHighlight = TypeaheadRowHighlight()
    @StateObject private var liveRows = TaskToolsPickerLiveRows()
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tools needed")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Text("Choose Mac apps for reference (icons only).")
                .font(.caption)
                .foregroundStyle(TurboTheme.mutedInk)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            IdentifiedTextField(
                identifier: TypeaheadFieldID.toolsPickerSearch,
                text: $search,
                placeholder: "Search apps"
            )
            .frame(height: 24)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            TrainingWheelsHint(text: "↑ ↓ to move · Return to add or remove the highlighted app (when search is focused).")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if isLoading {
                ProgressView("Scanning Applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(liveRows.rows.enumerated()), id: \.element.id) { index, app in
                                appRow(index: index, app: app)
                                    .id(app.id)
                            }
                        }
                    }
                    .onReceive(rowHighlight.$index) { newValue in
                        guard liveRows.rows.indices.contains(newValue) else { return }
                        proxy.scrollTo(liveRows.rows[newValue].id, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .background(TurboTheme.backgroundRaised)
        .onAppear {
            liveRows.update(all: apps, query: search)
            keyMonitor = TypeaheadListKeyboard.install(
                store: store,
                isSearchFocused: {
                    TypeaheadListKeyboard.firstResponderMatchesFieldID(TypeaheadFieldID.toolsPickerSearch)
                },
                itemCount: { liveRows.rows.count },
                highlight: rowHighlight,
                onActivate: { idx in
                    guard liveRows.rows.indices.contains(idx) else { return }
                    toggle(liveRows.rows[idx].bundleIdentifier)
                }
            )
        }
        .onDisappear {
            TypeaheadListKeyboard.remove(keyMonitor)
            keyMonitor = nil
        }
        .onChange(of: search) { _, _ in
            liveRows.update(all: apps, query: search)
            rowHighlight.reset()
            rowHighlight.clamp(count: liveRows.rows.count)
        }
        .onChange(of: apps) { _, _ in
            liveRows.update(all: apps, query: search)
            rowHighlight.clamp(count: liveRows.rows.count)
        }
        .onChange(of: liveRows.rows.count) { _, newCount in
            rowHighlight.clamp(count: newCount)
        }
        .task {
            apps = await withCheckedContinuation { (cont: CheckedContinuation<[InstalledMacApp], Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: MacInstalledAppsScanner.scanInstalledApps())
                }
            }
            isLoading = false
            liveRows.update(all: apps, query: search)
        }
    }

    private func appRow(index: Int, app: InstalledMacApp) -> some View {
        let isHi = index == rowHighlight.index
        return HStack(spacing: 10) {
            Image(nsImage: MacAppIcon.nsImage(bundleIdentifier: app.bundleIdentifier, pointSize: 36))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if bundleIDs.contains(app.bundleIdentifier) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(TurboTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHi ? TurboTheme.accentSoft.opacity(0.45) : Color.clear)
        .contentShape(Rectangle())
        .trainingWheelsTooltip(
            bundleIDs.contains(app.bundleIdentifier)
                ? "Click or Return to remove from tools"
                : "Click or Return to add (max \(Task.maxToolAppsPerTask) apps)"
        )
        .onTapGesture {
            toggle(app.bundleIdentifier)
        }
    }

    private func toggle(_ id: String) {
        if let idx = bundleIDs.firstIndex(of: id) {
            bundleIDs.remove(at: idx)
        } else if bundleIDs.count < Task.maxToolAppsPerTask {
            bundleIDs.append(id)
        }
    }
}
