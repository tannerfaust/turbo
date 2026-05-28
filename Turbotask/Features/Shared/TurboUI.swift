//
//  TurboUI.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct TurboPageHeader: View {
    let title: String
    let trailing: AnyView?

    init(title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TurboTheme.ink)
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct TurboTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(TurboTheme.nestedCardFill)
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

struct TurboMetricPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(TurboTheme.mutedInk)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TurboTheme.nestedCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TurboTheme.cardStroke.opacity(0.9), lineWidth: 1)
                )
        )
    }
}

struct TurboInfoButton: View {
    let title: String
    let message: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TurboTheme.mutedInk)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TurboTheme.ink)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 250, alignment: .leading)
        }
        .trainingWheelsTooltip(title)
    }
}

struct TurboEmptyState: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TurboTheme.ink)
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(TurboTheme.ink)
            }
            Spacer()
        }
        .turboCard()
    }
}

struct TurboProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TurboTheme.cardStroke.opacity(0.7))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * value, value > 0 ? 8 : 0))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Job accent & project emoji

struct JobPaletteSwatchRow: View {
    @Binding var selection: JobPalette

    private let columns = [GridItem(.adaptive(minimum: 30, maximum: 36), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(JobPalette.allCases) { palette in
                Button {
                    selection = palette
                } label: {
                    ZStack {
                        Circle()
                            .fill(palette.color)
                            .frame(width: 28, height: 28)
                        if selection == palette {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(palette.title))
            }
        }
        .padding(.vertical, 2)
    }
}

private let projectEmojiChoices: [String] = [
    "📁", "📌", "🎯", "✨", "🚀", "💼", "🏠", "📣", "🛠️", "📊", "🎨", "🔧", "📝", "💡", "🧪",
    "⚡️", "🌐", "🔒", "📱", "💬", "🗂️", "✅", "🔥", "⭐️", "🎵", "🏃", "🧭", "📈", "🤝", "💰",
    "☕️", "🌱", "🤖", "📮", "🔔", "🎬", "💳", "🧾", "📅", "🛡️", "🔑"
]

struct EmojiPickButton: View {
    @EnvironmentObject private var store: TurboTaskStore
    @Binding var emoji: String
    @State private var pickerOpen = false

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 6)]

    var body: some View {
        Button {
            pickerOpen = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TurboTheme.nestedCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TurboTheme.divider, lineWidth: 1)
                    )
                if emoji.isEmpty {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TurboTheme.mutedInk)
                } else {
                    Text(emoji)
                        .font(.system(size: 26))
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $pickerOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Project icon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TurboTheme.mutedInk)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(projectEmojiChoices, id: \.self) { choice in
                            Button {
                                emoji = choice
                                pickerOpen = false
                            } label: {
                                Text(choice)
                                    .font(.system(size: 26))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
                Button("Clear icon") {
                    emoji = ""
                    pickerOpen = false
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(TurboTheme.mutedInk)
            }
            .padding(12)
            .frame(width: 268)
        }
        .trainingWheelsTooltip("Choose project emoji")
    }
}
