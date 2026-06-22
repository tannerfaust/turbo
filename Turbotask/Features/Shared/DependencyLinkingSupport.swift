//
//  DependencyLinkingSupport.swift
//  Turbotask
//
//  iOS-style wobble selection mode for linking task prerequisites.
//

import SwiftUI

enum DependencyLinkingRole: Equatable {
    case inactive
    case source
    case validTarget
    case invalidTarget
}

// MARK: - Wobble

private struct DependencyLinkingWobbleModifier: ViewModifier {
    let isActive: Bool
    let phaseOffset: Double

    @State private var wobbling = false

    private var angle: Double {
        guard isActive else { return 0 }
        return wobbling ? 1.35 : -1.35
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .animation(
                isActive
                    ? .easeInOut(duration: 0.13)
                        .repeatForever(autoreverses: true)
                        .delay(phaseOffset * 0.17)
                    : .default,
                value: wobbling
            )
            .onAppear {
                wobbling = isActive
            }
            .onChange(of: isActive) { _, active in
                wobbling = active
            }
    }
}

// MARK: - Card chrome

struct DependencyLinkingCardModifier: ViewModifier {
    @EnvironmentObject private var store: TurboTaskStore

    let taskID: UUID
    var accentTint: Color = Color(red: 0.52, green: 0.38, blue: 0.96)

    private var role: DependencyLinkingRole {
        store.linkingRole(for: taskID)
    }

    private var isLinking: Bool {
        store.dependencyLinkingSourceTaskID != nil
    }

    func body(content: Content) -> some View {
        content
            .modifier(
                DependencyLinkingWobbleModifier(
                    isActive: isLinking,
                    phaseOffset: dependencyLinkingPhaseOffset(for: taskID)
                )
            )
            .opacity(role == .invalidTarget ? 0.36 : 1)
            .overlay {
                if role == .source {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(accentTint.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if role == .source {
                    Text("Linking from here")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accentTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(accentTint.opacity(0.14))
                        )
                        .offset(x: 6, y: -10)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if role == .validTarget {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accentTint.opacity(0.55), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func dependencyLinkingCard(taskID: UUID, accentTint: Color? = nil) -> some View {
        modifier(
            DependencyLinkingCardModifier(
                taskID: taskID,
                accentTint: accentTint ?? Color(red: 0.52, green: 0.38, blue: 0.96)
            )
        )
    }
}

func dependencyLinkingPhaseOffset(for taskID: UUID) -> Double {
    var hasher = Hasher()
    hasher.combine(taskID)
    return Double(abs(hasher.finalize() % 1000)) / 1000.0
}

// MARK: - Hint bar

struct DependencyLinkingHintBar: View {
    @EnvironmentObject private var store: TurboTaskStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.52, green: 0.38, blue: 0.96))

            Text("Choose a task that must finish first")
                .font(.caption.weight(.medium))
                .foregroundStyle(TurboTheme.ink)

            Spacer(minLength: 4)

            Button("Cancel") {
                store.cancelDependencyLinking()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TurboTheme.mutedInk)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(TurboTheme.cardFill)
                .shadow(color: TurboTheme.shadow.opacity(0.35), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color(red: 0.52, green: 0.38, blue: 0.96).opacity(0.45), lineWidth: 1.5)
        )
        .allowsHitTesting(true)
    }
}
