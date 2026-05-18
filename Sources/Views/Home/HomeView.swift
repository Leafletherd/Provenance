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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Brand.textPrimary)
                Text("Connect a project folder to start tracking\nyour creative history.")
                    .font(.system(size: 13))
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

                // ── Greeting + prompt + composer locked together in a centered 560pt column ──
                // All four elements (greeting, prompt, text box, project picker) share a single
                // VStack so they reposition as a unit on window resize.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: Brand.spaceMD) {
                        // PR-18 §2a — greeting in Palatino italic light (the
                        // in-app stand-in for Fraunces, which is web-only and
                        // intentionally NOT bundled per §3). Matches Seed's
                        // SeedHomeView greeting treatment exactly so the two
                        // home screens read as obvious siblings.
                        Text(greeting)
                            .font(.custom("Palatino-Italic", size: 34))
                            .fontWeight(.light)
                            .foregroundColor(Brand.textPrimary)

                        Text(contextualPrompt)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Brand.textSecondary)

                        composerSection
                    }
                    .frame(maxWidth: 560)
                    Spacer(minLength: 0)
                }

                // All subsequent sections share the SAME centered 560pt column so
                // they reposition together with the greeting/composer on resize.
                centeredColumn {
                    Divider().overlay(Brand.border)
                    projectStrip
                    Divider().overlay(Brand.border)
                    weekStats
                }
            }
            .padding(Brand.spaceXL)
        }
        .background(Brand.surfaceBase)
        .onAppear {
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

                HStack(spacing: 4) {
                    ForEach(CheckInStatus.allCases, id: \.self) { status in
                        StatusChip(status: status, isSelected: checkInStatus == status) {
                            checkInStatus = status
                        }
                    }
                }

                Spacer()

                // PR-18 §2c — primary action button mirrors Seed's Plant
                // button: filled Brand.accent (prov/accent #1D9E75) capsule
                // with cream (surfaceBase #FAF6EF) label. Manual styling so
                // both colors stay pinned regardless of system bordered-
                // prominent rendering.
                let saveDisabled = checkInText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || targetProjectID == nil
                    || isSaving
                Button {
                    saveCheckIn()
                } label: {
                    Group {
                        if savedFeedback {
                            Label("Saved", systemImage: "checkmark")
                                .font(.system(size: 13, weight: .medium))
                        } else {
                            Text("Save")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .foregroundColor(Brand.surfaceBase)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Brand.accent)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(saveDisabled)
                .opacity(saveDisabled ? 0.4 : 1.0)
            }

            // Text input
            // Placeholder and TextEditor use identical padding so the first typed
            // character lands at the exact same x,y as the placeholder's first letter.
            ZStack(alignment: .topLeading) {
                if checkInText.isEmpty {
                    Text("Ready to check in? Type a sentence or two.")
                        .font(.system(size: 13).italic())
                        .foregroundColor(Brand.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $checkInText)
                    .font(.system(size: 13))
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
                        ProjectHomeCard(state: state) {
                            // Single-click: navigate into the project's tabs
                            appState.isHomeSelected = false
                            appState.selectedProjectID = state.project.id
                        }
                    }
                }
                .padding(.bottom, 2)
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

    // Wrap any content in the same centered 560pt column used by the greeting
    // block, so all sections of the Home page reposition as a unit on resize.
    @ViewBuilder
    private func centeredColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Brand.spaceXL) {
                content()
            }
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
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

    /// Reflects whichever project is currently selected as the check-in target.
    private var contextualPrompt: String {
        if let id = targetProjectID,
           let state = appState.projectStates.first(where: { $0.project.id == id }) {
            return "How\u{2019}s \(state.project.name) going?"
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
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.spaceSM) {
            // Header: status dot + name
            HStack(spacing: 6) {
                Circle()
                    .fill(state.isWatching ? Brand.accent : Brand.textMuted)
                    .frame(width: 7, height: 7)
                Text(state.project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
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
        .onTapGesture { onOpen() }
        .help("Open \(state.project.name)")
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
            // PR-18 §2b — stat numbers in Palatino roman 28pt (editorial
            // values, not dashboard numbers). Mirrors Seed SeedHomeView's
            // HomeStatView so the two home screens stay structurally
            // identical. Label stays system UI.
            Text("\(value)")
                .font(.custom("Palatino", size: 28))
                .fontWeight(.regular)
                .foregroundColor(Brand.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Brand.textMuted)
        }
    }
}
