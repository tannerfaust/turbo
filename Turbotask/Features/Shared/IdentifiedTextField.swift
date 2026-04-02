//
//  IdentifiedTextField.swift
//  Turbotask
//
//  NSTextField with a stable identifier so type-ahead monitors know which search is active.
//

import AppKit
import SwiftUI

struct IdentifiedTextField: NSViewRepresentable {
    let identifier: String
    @Binding var text: String
    var placeholder: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.placeholderString = placeholder.isEmpty ? nil : placeholder
        tf.identifier = NSUserInterfaceItemIdentifier(identifier)
        tf.delegate = context.coordinator
        tf.isBordered = true
        tf.isBezeled = true
        tf.drawsBackground = true
        tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        tf.cell?.sendsActionOnEndEditing = true
        // Avoid system blue focus ring; contrast comes from bezel + TurboTheme.tint on the shell.
        tf.focusRingType = .none
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder.isEmpty ? nil : placeholder
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }
    }
}

enum TypeaheadFieldID {
    static let tasksSearch = "turbotask.search.tasks"
    static let jobsSearch = "turbotask.search.jobs"
    static let projectsRailSearch = "turbotask.search.projects.rail"
    static let projectsTasksSearch = "turbotask.search.projects.tasks"
    static let toolsPickerSearch = "turbotask.search.toolsPicker"
}

extension TypeaheadListKeyboard {
    /// Walks the responder chain from the key window’s first responder. While an `NSTextField` is editing, focus is usually the field editor (`NSTextView`), not the field itself—without this walk, type-ahead never activates.
    static func firstResponderFieldID() -> String? {
        let windows: [NSWindow] = {
            if let key = NSApp.keyWindow { return [key] }
            if let main = NSApp.mainWindow { return [main] }
            return NSApp.windows
        }()
        for window in windows {
            guard let start = window.firstResponder else { continue }
            var responder: NSResponder? = start
            var safety = 0
            while let current = responder, safety < 40 {
                safety += 1
                if let tf = current as? NSTextField,
                   let raw = tf.identifier?.rawValue,
                   !raw.isEmpty {
                    return raw
                }
                responder = current.nextResponder
            }
        }
        return nil
    }

    static func firstResponderMatchesFieldID(_ id: String) -> Bool {
        firstResponderFieldID() == id
    }
}
