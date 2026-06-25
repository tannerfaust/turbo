//
//  TaskStatusRowIndicator.swift
//  Turbotask
//

import SwiftUI

/// Compact status glyph for task rows: light motion (active ring, soft pulses) and color per status.
struct TaskStatusRowIndicator: View {
    let status: TaskStatus
    var jobColor: Color
    var diameter: CGFloat = 17

    @State private var transitionScale: CGFloat = 1

    private var lineWidth: CGFloat { max(1.35, diameter * 0.10) }

    var body: some View {
        ZStack {
            switch status {
            case .queued:
                Circle()
                    .stroke(TurboTheme.mutedInk.opacity(0.62), lineWidth: lineWidth)
            case .active:
                ActiveIndeterminateRing(color: jobColor, lineWidth: lineWidth, diameter: diameter)
            case .waiting:
                WaitingGlyph(color: status.accent, fontSize: diameter * 0.72)
            case .paused:
                PausedGlyph(color: status.accent, fontSize: diameter * 0.58)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: diameter * 0.92, weight: .regular))
                    .foregroundStyle(status.accent.opacity(0.92))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(transitionScale)
        .onChange(of: status) { _, _ in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.52)) {
                transitionScale = 1.11
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    transitionScale = 1
                }
            }
        }
    }
}

// MARK: - Status picker popover (circle stays as-is; panel uses icons)

struct TaskStatusMenuGlyph: View {
    let status: TaskStatus
    var jobColor: Color

    var body: some View {
        Group {
            switch status {
            case .queued:
                Image(systemName: "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TurboTheme.mutedInk)
            case .active:
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(jobColor)
            case .waiting:
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.accent)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(status.accent)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(status.accent.opacity(0.92))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: 16, height: 16)
    }
}

struct TaskStatusPickerPanel: View {
    let selection: TaskStatus
    var jobColor: Color
    let onSelect: (TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    onSelect(status)
                } label: {
                    HStack(spacing: 10) {
                        TaskStatusMenuGlyph(status: status, jobColor: jobColor)
                        Text(status.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TurboTheme.ink)
                        Spacer(minLength: 20)
                        if selection == status {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(TurboTheme.mutedInk)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == status ? TurboTheme.nestedCardFill : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 190)
    }
}

struct TaskStatusPickerPopover<Label: View>: View {
    let selection: TaskStatus
    var jobColor: Color
    var helpText: String?
    var trainingWheelsTooltip: String?
    var accessibilityHint: String?
    let onSelect: (TaskStatus) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .help(helpText ?? "Status: \(selection.title)")
        .modifier(OptionalTrainingWheelsTooltip(trainingWheelsTooltip))
        .accessibilityLabel("Task status: \(selection.title)")
        .accessibilityHint(accessibilityHint ?? "Opens status menu")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            TaskStatusPickerPanel(selection: selection, jobColor: jobColor) { status in
                onSelect(status)
                isPresented = false
            }
        }
        .animation(.snappy(duration: 0.12), value: isPresented)
    }
}

private struct OptionalTrainingWheelsTooltip: ViewModifier {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    func body(content: Content) -> some View {
        if let text {
            content.trainingWheelsTooltip(text)
        } else {
            content
        }
    }
}

// MARK: - Active ring (Linear-style indeterminate arc)

private struct ActiveIndeterminateRing: View {
    var color: Color
    var lineWidth: CGFloat
    var diameter: CGFloat

    @State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.27)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(rotating ? 270 : -90))
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.linear(duration: 2.15).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }
}

// MARK: - Waiting / paused (soft, low-frequency)

private struct WaitingGlyph: View {
    let color: Color
    let fontSize: CGFloat

    @State private var pulsing = false

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color.opacity(pulsing ? 0.76 : 0.52))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

private struct PausedGlyph: View {
    let color: Color
    let fontSize: CGFloat

    @State private var pulsing = false

    var body: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(color)
            .scaleEffect(pulsing ? 1.0 : 0.94)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
