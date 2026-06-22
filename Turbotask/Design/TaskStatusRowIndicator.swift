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
