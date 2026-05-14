import SwiftUI
import AppKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    // Check-in composer state
    @State private var checkInText: String = ""
    @State private var checkInStatus: CheckInStatus = .working
    @State private var targetProjectID: UUID? = nil
    @State private var isSaving: Bool = false
    @State private var savedFeedback: Bool = false

    var body: some View {
        if appState.projectStates.isEmpty {
            emptyState
        } else {
            mainContent
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Brand.spaceLG) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundColor(Brand.textMuted)
            VStack(spacing: Brand.spaceSM) {
                Text("Welcome to Provenance.")
                    .font(.title2.bold())
                    .foregroundColor(Brand.textPrimary)
                Text("Connect a project folder to start tracking\nyour creative history.")
                    .font(.body)
                    .foregroundColor(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Connect Project Folder\u{2026}") {
                NotificationCenter.default.post(name: .connectProjectRequested, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.surfaceBase)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.spaceXL) {

                // Greeting + prompt
                VStack(alignment: .leading, spacing: Brand.spaceSM) {
                    Text(greeting)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Brand.textPrimary)

                    Text(contextualPrompt)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Brand.textSecondary)
                }

                // Check-in composer
                composerSection

                Divider()
                    .overlay(Brand.border)

                // Project cards strip
                projectStrip

                Divider()
                    .overlay(Brand.border)

                // This-week stats
                weekStats
            }
            .padding(Brand.spaceXL)
        }
        .background(Brand.surfaceBase)
        .onAppear {
            // Default target project = contextual project, or first project
            if targetProjectID == nil {
                targetProjectID = contextualProject?.project.id
                    ?? appState.projectStates.first?.project.id
            }
        }
    }

    // MARK: - Composer section

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: Brand.spaceMD) {
            // Project picker + status row
            HStack(spacing: Brand.spaceSM) {
                // Project picker
                Menu {
                    ForEach(appState.projectStates) { state in
                        Button(state.project.name) {
                            targetProjectID = state.project.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedProjectName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Brand.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Brand.textMuted)
                    }
                    .padding(.horizontal, Brand.spaceSM)
                    .padding(.vertical, 4)
                    .background(Brand.surfaceSunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.radiusMd)
                            .stroke(Brand.border, lineWidth: 0.5)
                    )
                    .cornerRadius(Brand.radiusMd)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Status chips
                HStack(spacing: 4) {
                    ForEach(CheckInStatus.allCases, id: \.self) { status in
                        StatusChip(status: status, isSelected: checkInStatus == status) {
                            checkInStatus = status
                        }
                    }
                }

                Spacer()

                // Save button
                Button {
                    saveCheckIn()
                } label: {
                    if savedFeedback {
                        Label("Saved", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(checkInText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || targetProjectID == nil
                          || isSaving)
            }

            // Text input
            ZStack(alignment: .topLeading) {
                if checkInText.isEmpty {
                    Text("What did you work on? How does it feel?")
                        .font(.system(size: 14))
                        .foregroundColor(Brand.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $checkInText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 80, maxHeight: 200)
            .background(Brand.surfaceSunken)
            .overlay(
                RoundedRectangle(cornerRadius: Brand.radiusMd)
                    .stroke(Brand.border, lineWidth: 0.5)
            )
            .cornerRadius(Brand.radiusMd)
        }
    }

    // MARK: - Project strip

    private var projectStrip: some View {
        VStack(alignment: .leading, spacing: Brand.spaceSM) {
            Text("Projects")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Brand.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Brand.spaceMD) {
                    ForEach(appState.projectStates) { state in
                        ProjectHomeCard(state: state)
                            .onTapGesture {
                                appState.isHomeSelected = false
                                appState.selectedProjectID = state.project.id
                            }
                    }
                }
                .padding(.bottom, 2) // room for card shadow border
            }
        }
    }

    // MARK: - Week stats

    private var weekStats: some View {
        let (checkIns, sources, snapshots) = weeklyStats
        return HStack(spacing: Brand.spaceLG) {
            HomeStatView(value: checkIns, label: "Check-ins this week")
            HomeStatView(value: sources,  label: "Sources added")
            HomeStatView(value: snapshots, label: "Snapshots saved")
            Spacer()
        }
    }

    // MARK: - Computed helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<21: return "Good evening."
        default:      return "Good night."
        }
    }

    /// Most recent project that has activity but no check-in in the last hour.
    private var contextualProject: ProjectState? {
        let cutoff = Date().addingTimeInterval(-3600)
        return appState.projectStates
            .sorted { $0.project.lastActivity > $1.project.lastActivity }
            .first { state in
                state.project.lastActivity > cutoff
                    && (state.checkIns.last?.timestamp ?? .distantPast) < state.project.lastActivity
            }
    }

    private var contextualPrompt: String {
        if let proj = contextualProject {
            return "How\u{2019}s \(proj.project.name) going?"
        }
        return "What are you working on?"
    }

    private var selectedProjectName: String {
        guard let id = targetProjectID,
              let state = appState.projectStates.first(where: { $0.project.id == id })
        else { return "Select project" }
        return state.project.name
    }

    private var weeklyStats: (Int, Int, Int) {
        let cutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        )
        var checkIns = 0, sources = 0, snapshots = 0
        for state in appState.projectStates {
            checkIns  += state.checkIns.filter  { $0.timestamp >= cutoff }.count
            sources   += state.sources.filter   { $0.timestamp >= cutoff }.count
            snapshots += state.snapshots.filter { $0.timestamp >= cutoff }.count
        }
        return (checkIns, sources, snapshots)
    }

    // MARK: - Save action

    private func saveCheckIn() {
        guard let id = targetProjectID,
              let state = appState.projectStates.first(where: { $0.project.id == id })
        else { return }

        let trimmed = checkInText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        let checkIn = CheckIn(status: checkInStatus, text: trimmed)
        state.addCheckIn(checkIn)

        checkInText = ""
        isSaving = false
        savedFeedback = true

        // Re-default project to contextual on next open
        targetProjectID = contextualProject?.project.id
            ?? appState.projectStates.first?.project.id

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFeedback = false }
        }
    }
}

// MARK: - Status chip

private struct StatusChip: View {
    let status: CheckInStatus
    let isSelected: Bool
    let action: () -> Void

    private var color: Color {
        switch status {
        case .working:      return Brand.statusWorking
        case .stuck:        return Brand.statusStuck
        case .breakthrough: return Brand.statusBreakthrough
        case .paused:       return Brand.statusPaused
        case .done:         return Brand.statusDone
        }
    }

    var body: some View {
        Button(action: action) {
            Text(status.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? color : Brand.textMuted)
                .padding(.horizontal, Brand.spaceSM)
                .padding(.vertical, 3)
                .background(isSelected ? color.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.radiusSm)
                        .stroke(isSelected ? color.opacity(0.35) : Brand.border, lineWidth: 0.5)
                )
                .cornerRadius(Brand.radiusSm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project home card

private struct ProjectHomeCard: View {
    @ObservedObject var state: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.spaceSM) {
            // Header: name + status dot
            HStack(spacing: 6) {
                Circle()
                    .fill(state.isWatching ? Brand.accent : Brand.textMuted)
                    .frame(width: 7, height: 7)
                Text(state.project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.textPrimary)
                    .lineLimit(1)
            }

            // Sparkline or placeholder
            if let ms = state.manuscripts.max(by: { $0.history.count < $1.history.count }),
               ms.history.count >= 2 {
                SparklineView(values: ms.history.map { $0.wordCount })
                    .frame(width: 100, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Brand.border.opacity(0.5))
                    .frame(width: 100, height: 28)
            }

            Spacer(minLength: 0)

            // Stats row
            HStack(spacing: Brand.spaceSM) {
                CardStat(value: state.checkIns.count, label: "check-ins")
                CardStat(value: state.snapshots.count, label: "snaps")
                CardStat(value: state.sources.count, label: "sources")
            }

            // Last activity
            Text(state.project.lastActivity, style: .relative)
                .font(.caption2)
                .foregroundColor(Brand.textMuted)
        }
        .padding(Brand.spaceMD)
        .frame(width: 200, height: 120, alignment: .topLeading)
        .background(Brand.surfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusLg)
                .stroke(Brand.border, lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusLg)
        .contentShape(Rectangle())
    }
}

private struct CardStat: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Brand.textSecondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Brand.textMuted)
        }
    }
}

// MARK: - Home stat

private struct HomeStatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Brand.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Brand.textMuted)
        }
    }
}
