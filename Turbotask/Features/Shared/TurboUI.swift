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

// MARK: - Liquid glass chip surfaces

struct GlassChipFill<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(TurboTheme.nestedCardFill.opacity(0.45))
            .background(shape.fill(.ultraThinMaterial))
    }
}

struct GlassIconChip: View {
    let systemName: String
    var iconSize: CGFloat = 9
    var dimension: CGFloat = 20
    var cornerRadius: CGFloat = 5

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(TurboTheme.mutedInk)
            .frame(width: dimension, height: dimension)
            .background { GlassChipFill(shape: shape) }
            .overlay(shape.stroke(TurboTheme.divider.opacity(0.72), lineWidth: 1))
            .contentShape(shape)
    }
}

extension View {
    /// Inline capsule glass chrome for menu/button pills.
    /// Solid rounded capsule with visible fill and border.
    func glassCapsulePillChrome() -> some View {
        background(
            Capsule()
                .fill(TurboTheme.nestedCardFill)
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(TurboTheme.cardStroke.opacity(0.85), lineWidth: 1))
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

// MARK: - Field accent & project emoji

/// Inline editor for a field’s display name and accent color.
struct FieldAppearanceEditor: View {
    @EnvironmentObject private var store: TurboTaskStore

    let jobID: UUID
    var showsSummary: Bool = false
    var titleFont: Font = .title3.weight(.semibold)

    private var job: Job? { store.job(id: jobID) }

    var body: some View {
        if let job {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    "Field name",
                    text: Binding(
                        get: { job.title },
                        set: { value in
                            store.updateJob(jobID: jobID) { $0.title = value }
                        }
                    )
                )
                .font(titleFont)
                .textFieldStyle(.plain)
                .foregroundStyle(TurboTheme.ink)

                if showsSummary {
                    TextField(
                        "Summary — what this field is for",
                        text: Binding(
                            get: { job.summary },
                            set: { value in
                                store.updateJob(jobID: jobID) { $0.summary = value }
                            }
                        ),
                        axis: .vertical
                    )
                    .font(.subheadline)
                    .foregroundStyle(TurboTheme.mutedInk)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Accent color")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TurboTheme.mutedInk)
                    JobPaletteSwatchRow(selection: paletteBinding)
                }
            }
        }
    }

    private var paletteBinding: Binding<JobPalette> {
        Binding(
            get: { store.job(id: jobID)?.palette ?? .forest },
            set: { palette in
                store.updateJob(jobID: jobID) { $0.palette = palette }
            }
        )
    }
}

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
    // Folders & files
    "📁", "📂", "🗂️", "📋", "📎", "📌", "📍", "📝", "✏️", "✍️", "📄", "📃", "🗒️", "📑",
    // Goals & status
    "🎯", "✅", "✔️", "⭐️", "🌟", "🏆", "🥇", "🔥", "⚡️", "💡", "✨", "🚀",
    // Work & business
    "💼", "🏢", "📊", "📈", "📉", "💰", "💵", "💳", "🧾", "🤝", "👥", "👤",
    // Communication
    "💬", "🗣️", "📣", "📢", "📧", "📮", "📞", "📱", "💻", "🖥️", "⌨️", "🖱️",
    // Creative
    "🎨", "🖌️", "🎬", "🎵", "🎧", "🎮", "📷", "🎤", "🎭", "📚", "📖",
    // Tools & tech
    "🛠️", "🔧", "🔩", "⚙️", "🤖", "🧪", "🔬", "🧬", "🌐", "🔗", "🔒", "🔑", "🛡️",
    // Home & life
    "🏠", "🏡", "🛒", "🧹", "🍳", "☕️", "🍎", "🌱", "🌿", "🌸", "🐾", "❤️",
    // Travel & places
    "✈️", "🚗", "🚲", "🧭", "🗺️", "🌍", "🏖️", "⛰️",
    // Time & planning
    "📅", "🗓️", "⏰", "⏱️", "🔔", "📆",
    // Sports & health
    "🏃", "💪", "🧘", "⚽️", "🏀", "🎾", "🧠", "💊",
    // Misc
    "🎁", "🎉", "🧩", "🪴", "☀️", "🌙", "🌊", "🍀", "🦄", "🎲", "🏷️", "🔖"
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
                .frame(maxHeight: 320)
                Button("Clear icon") {
                    emoji = ""
                    pickerOpen = false
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(TurboTheme.mutedInk)
            }
            .padding(12)
            .frame(width: 300)
        }
        .trainingWheelsTooltip("Choose project emoji")
    }
}
