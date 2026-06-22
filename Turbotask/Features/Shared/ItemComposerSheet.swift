//
//  ItemComposerSheet.swift
//  Turbotask
//
//  Created by Codex on 01.04.2026.
//

import SwiftUI

struct ItemComposerSheet: View {
    @EnvironmentObject private var store: TurboTaskStore

    let context: TurboTaskStore.ComposerContext

    @AppStorage("composer_create_more") private var createMore = false
    @FocusState private var titleFocused: Bool

    @State private var jobTitle = ""
    @State private var jobSummary = ""
    @State private var selectedPalette: JobPalette = .forest

    @State private var selectedJobID: UUID?
    @State private var projectTitle = ""
    @State private var projectOutcome = ""
    @State private var projectEmoji = ""

    init(context: TurboTaskStore.ComposerContext) {
        self.context = context
        _selectedJobID = State(initialValue: context.preferredJobID)
    }

    var body: some View {
        Group {
            switch context.kind {
            case .task:
                TaskComposerView(
                    preferredJobID: context.preferredJobID,
                    preferredProjectID: context.preferredProjectID,
                    preferredStatus: context.preferredStatus,
                    scheduleForNow: context.scheduleForNow
                )
            case .job:
                jobComposer
            case .project:
                projectComposer
            }
        }
        .environmentObject(store)
    }

    // MARK: - Field composer

    private var jobComposer: some View {
        ComposerChrome(
            breadcrumb: "New field",
            onClose: { store.clearComposer() },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Field name", text: $jobTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(TurboTheme.ink)
                            .focused($titleFocused)
                            .padding(.bottom, 10)

                        TextField("What this field is for…", text: $jobSummary, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(TurboTheme.ink)
                            .lineLimit(2...5)
                            .padding(.bottom, 16)

                        FlowLayout(spacing: 8) {
                            ComposerCapturePill(
                                icon: "paintpalette",
                                iconColor: selectedPalette.color,
                                title: selectedPalette.title,
                                isActive: selectedPalette != .forest
                            ) {
                                ForEach(JobPalette.allCases) { palette in
                                    Button {
                                        selectedPalette = palette
                                    } label: {
                                        HStack {
                                            Text(palette.title)
                                            if selectedPalette == palette {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            },
            footerLeading: { Color.clear.frame(width: 28, height: 28) },
            createMore: $createMore,
            createTitle: "Create field",
            canCreate: !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCreate: saveJob
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                titleFocused = true
            }
        }
    }

    // MARK: - Project composer

    @ViewBuilder
    private var projectComposer: some View {
        if store.jobs.isEmpty {
            ComposerChrome(
                breadcrumb: "New project",
                onClose: { store.clearComposer() },
                content: { prerequisiteMessage },
                footerLeading: { Color.clear.frame(width: 28, height: 28) },
                createMore: .constant(false),
                createTitle: "Create project",
                canCreate: false,
                onCreate: {}
            )
        } else {
            ComposerChrome(
                breadcrumb: projectBreadcrumb,
                onClose: { store.clearComposer() },
                content: { projectComposerBody },
                footerLeading: { Color.clear.frame(width: 28, height: 28) },
                createMore: $createMore,
                createTitle: "Create project",
                canCreate: selectedJobID != nil && !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCreate: saveProject
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            }
        }
    }

    private var projectComposerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Project title", text: $projectTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TurboTheme.ink)
                    .focused($titleFocused)
                    .padding(.bottom, 10)

                TextField("What outcome this project should create…", text: $projectOutcome, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(TurboTheme.ink)
                    .lineLimit(2...5)
                    .padding(.bottom, 16)

                FlowLayout(spacing: 8) {
                    fieldPickerPill
                    ComposerCapturePill(
                        icon: "face.smiling",
                        title: projectEmoji.isEmpty ? "Icon" : projectEmoji,
                        isActive: !projectEmoji.isEmpty
                    ) {
                        Button("Clear icon") {
                            projectEmoji = ""
                        }
                        Divider()
                        ForEach(projectEmojiQuickPicks, id: \.self) { emoji in
                            Button(emoji) {
                                projectEmoji = emoji
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var fieldPickerPill: some View {
        ComposerCapturePill(
            icon: "briefcase",
            title: selectedJobTitle,
            isActive: selectedJobID != nil
        ) {
            ForEach(store.jobs) { job in
                Button {
                    selectedJobID = job.id
                } label: {
                    HStack {
                        Text(job.title)
                        if selectedJobID == job.id { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var prerequisiteMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create a field first")
                .font(.title3.weight(.semibold))
                .foregroundStyle(TurboTheme.ink)
            Text("Projects need a parent field before they can exist.")
                .font(.body)
                .foregroundStyle(TurboTheme.mutedInk)

            Button("Create Field") {
                store.clearComposer()
                store.openComposer(.job)
            }
            .buttonStyle(.borderedProminent)
            .trainingWheelsTooltip("Start with a field, then add projects and tasks")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }

    private var projectBreadcrumb: String {
        if let selectedJobID,
           let job = store.jobs.first(where: { $0.id == selectedJobID }) {
            return "\(job.title) › New project"
        }
        return "New project"
    }

    private var selectedJobTitle: String {
        guard let selectedJobID,
              let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
            return "Field"
        }
        return job.title
    }

    private var projectEmojiQuickPicks: [String] {
        ["📁", "🎯", "🚀", "💼", "📊", "✨", "🔥", "📝", "🎨", "🛠️"]
    }

    // MARK: - Save

    private func saveJob() {
        let trimmed = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.addJob(
            title: trimmed,
            summary: jobSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            palette: selectedPalette
        )

        if createMore {
            jobTitle = ""
            jobSummary = ""
            titleFocused = true
        } else {
            store.clearComposer()
        }
    }

    private func saveProject() {
        guard let selectedJobID else { return }
        let trimmed = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.addProject(
            title: trimmed,
            outcome: projectOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
            iconEmoji: projectEmoji,
            jobID: selectedJobID
        )

        if createMore {
            projectTitle = ""
            projectOutcome = ""
            titleFocused = true
        } else {
            store.clearComposer()
        }
    }
}
