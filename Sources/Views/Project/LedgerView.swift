import SwiftUI

// MARK: - Filter model

/// Logical filter groups shown in the LedgerView chip bar.
enum LedgerFilter: Hashable {
    case all
    case pastes
    case snapshots
    case checkIns
    case sources
    case other

    var label: String {
        switch self {
        case .all:       return "All"
        case .pastes:    return "Pastes"
        case .snapshots: return "Snapshots"
        case .checkIns:  return "Check-ins"
        case .sources:   return "Sources"
        case .other:     return "Other"
        }
    }

    func matches(_ type: LedgerEventType) -> Bool {
        switch self {
        case .all:       return true
        case .pastes:    return type == .paste
        case .snapshots: return [.snapshotAuto, .snapshotScheduled, .snapshotManual].contains(type)
        case .checkIns:  return type == .checkin
        case .sources:   return type == .sourceAdded
        case .other:     return ![.paste, .snapshotAuto, .snapshotScheduled, .snapshotManual,
                                   .checkin, .sourceAdded].contains(type)
        }
    }
}

// MARK: - LedgerView

struct LedgerView: View {
    @ObservedObject var state: ProjectState
    @State private var selectedFilter: LedgerFilter = .all
    @State private var selectedSeedEvent: LedgerEvent? = nil
    @State private var selectedPasteEvent: LedgerEvent? = nil
    @State private var showIntegritySheet = false

    private let displayFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt
    }()

    /// Index of the first chained event; events before it are pre-chain.
    private var chainBoundaryIndex: Int {
        state.events.firstIndex { $0.type == .chainStarted } ?? state.events.count
    }

    var filteredEvents: [LedgerEvent] {
        if selectedFilter == .all { return state.events }
        return state.events.filter { selectedFilter.matches($0.type) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter + integrity bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([LedgerFilter.all, .pastes, .snapshots, .checkIns, .sources, .other],
                            id: \.self) { filter in
                        FilterButton(label: filter.label, isSelected: selectedFilter == filter) {
                            selectedFilter = (selectedFilter == filter && filter != .all) ? .all : filter
                        }
                    }
                    Spacer()

                    // Integrity status chip
                    IntegrityChipView(status: state.integrityStatus)
                        .onTapGesture { showIntegritySheet = true }

                    Button {
                        state.reloadEvents()
                        state.reloadIntegrity()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            if filteredEvents.isEmpty {
                EmptyStateView(message: selectedFilter == .all
                    ? "No ledger events yet."
                    : "No \(selectedFilter.label.lowercased()) events.")
            } else {
                List {
                    ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { idx, event in
                        let globalIdx = state.events.firstIndex(where: { $0.id == event.id }) ?? idx
                        let isPreChain = globalIdx < chainBoundaryIndex
                        LedgerEventRowView(event: event, displayFmt: displayFmt, isPreChain: isPreChain)
                            .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if event.type == .seedPromoted && event.metadata != nil {
                                    selectedSeedEvent = event
                                } else if event.type == .paste && event.metadata != nil {
                                    selectedPasteEvent = event
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            state.reloadEvents()
        }
        .sheet(item: $selectedSeedEvent) { event in
            SeedTimelineView(event: event)
        }
        .sheet(item: $selectedPasteEvent) { event in
            PasteDetailView(event: event)
        }
        .sheet(isPresented: $showIntegritySheet) {
            IntegrityDetailSheet(state: state, isPresented: $showIntegritySheet)
        }
    }
}

// MARK: - Integrity chip

struct IntegrityChipView: View {
    let status: LedgerIntegrity.IntegrityStatus

    private var label: String {
        switch status {
        case .checking:                return "Checking\u{2026}"
        case .intact(_, let pre):
            return pre > 0 ? "\u{2713} Chain intact" : "\u{2713} Chain intact"
        case .chainBroken(let at, _, _, _): return "\u{26A0} Chain broken at \(at)"
        case .historyRewritten:        return "\u{26A0} History rewritten"
        case .unchecked:               return "◐ Unchained"
        }
    }

    private var color: Color {
        switch status {
        case .checking, .unchecked:    return Brand.textMuted
        case .intact:                  return Brand.statusBreakthrough
        case .chainBroken, .historyRewritten: return Brand.statusStuck
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)

            // Pre-chain pill (shown alongside intact if there are pre-chain events)
            if case .intact(_, let pre) = status, pre > 0 {
                Text("Pre-chain \(pre)")
                    .font(.system(size: 10))
                    .foregroundColor(Brand.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Brand.surfaceSunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.radiusSm)
                            .stroke(Brand.border, lineWidth: 0.5)
                    )
                    .cornerRadius(Brand.radiusSm)
            }
        }
        .padding(.horizontal, Brand.spaceSM)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.radiusMd)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
        .cornerRadius(Brand.radiusMd)
        .contentShape(Rectangle())
    }
}

// MARK: - Integrity Detail sheet

struct IntegrityDetailSheet: View {
    @ObservedObject var state: ProjectState
    @Binding var isPresented: Bool

    @State private var showResetConfirm = false

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.spaceLG) {

            Text("Ledger Integrity")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Brand.textPrimary)

            // Chain status
            VStack(alignment: .leading, spacing: Brand.spaceSM) {
                Text("Chain status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Brand.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.4)

                chainStatusBody
            }

            Divider().overlay(Brand.border)

            // Git status
            VStack(alignment: .leading, spacing: Brand.spaceSM) {
                Text("Git history status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Brand.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.4)
                gitStatusBody
            }

            Divider().overlay(Brand.border)

            // Reset action
            VStack(alignment: .leading, spacing: Brand.spaceSM) {
                Text("Accept current state as new chain baseline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Brand.textPrimary)
                Text("Records a chainReset event and restarts the integrity chain from the current ledger state. This is always recorded — there is no silent reset.")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset Chain\u{2026}", role: .destructive) {
                    showResetConfirm = true
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Brand.spaceXL)
        .frame(width: 480)
        .background(Brand.surfaceBase)
        .confirmationDialog("Reset Chain?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset Chain", role: .destructive) {
                let description = statusDescription
                LedgerIntegrity.resetChain(project: state.project,
                                           previousStatusDescription: description)
                state.reloadIntegrity()
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The reset will be recorded as a chainReset event in the ledger.")
        }
    }

    @ViewBuilder
    private var chainStatusBody: some View {
        switch state.integrityStatus {
        case .checking:
            Label("Checking\u{2026}", systemImage: "clock")
                .font(.system(size: 13))
                .foregroundColor(Brand.textMuted)
        case .intact(let since, let pre):
            VStack(alignment: .leading, spacing: 4) {
                Label("Chain intact since \(dateFmt.string(from: since))",
                      systemImage: "checkmark.shield.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Brand.statusBreakthrough)
                if pre > 0 {
                    Text("\(pre) events predate the chain and are not hash-verified.")
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }
                chainHeadView
            }
        case .chainBroken(let at, let expected, let found, let content):
            VStack(alignment: .leading, spacing: 6) {
                Label("Chain broken at line \(at)", systemImage: "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Brand.statusStuck)
                DetailRow(label: "Expected prefix", value: expected)
                DetailRow(label: "Found prefix",    value: found)
                DetailRow(label: "Line content",    value: String(content.prefix(80)))
            }
        case .historyRewritten:
            Label("Chain intact", systemImage: "checkmark.shield")
                .font(.system(size: 13))
                .foregroundColor(Brand.statusBreakthrough)
        case .unchecked:
            Label("No integrity chain (pre-chain project)",
                  systemImage: "shield.slash")
                .font(.system(size: 13))
                .foregroundColor(Brand.textMuted)
        }
    }

    @ViewBuilder
    private var gitStatusBody: some View {
        switch state.integrityStatus {
        case .historyRewritten(let missing):
            VStack(alignment: .leading, spacing: 6) {
                Label("Git history rewritten — \(missing.count) missing commit\(missing.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Brand.statusStuck)
                ForEach(missing, id: \.hash) { entry in
                    HStack {
                        Text(entry.hash)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Brand.textSecondary)
                        Spacer()
                        Text(dateFmt.string(from: entry.date))
                            .font(.system(size: 10))
                            .foregroundColor(Brand.textMuted)
                    }
                }
            }
        default:
            Label("Git history consistent", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(Brand.statusBreakthrough)
        }
    }

    @ViewBuilder
    private var chainHeadView: some View {
        if let chain = LedgerIntegrity.readChain(from: state.project) {
            Text("Head: \(chain.head)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Brand.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusDescription: String {
        switch state.integrityStatus {
        case .intact:                   return "intact"
        case .chainBroken(let at, _, _, _): return "broken at line \(at)"
        case .historyRewritten:         return "git history rewritten"
        case .checking:                 return "checking"
        case .unchecked:                return "unchecked"
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Brand.textMuted)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Brand.textSecondary)
                .lineLimit(2)
        }
    }
}

struct LedgerEventRowView: View {
    let event: LedgerEvent
    let displayFmt: DateFormatter
    var isPreChain: Bool = false

    var eventColor: Color {
        switch event.type {
        case .projectConnected:    return Brand.statusBreakthrough
        case .fileSaved:           return Brand.textMuted
        case .snapshotAuto:        return Brand.accent.opacity(0.8)
        case .snapshotScheduled:   return Brand.statusStuck
        case .snapshotManual:      return Brand.accent
        case .checkin:             return Color(hex: "5A6480")  // dusty slate
        case .sourceAdded:         return Brand.accent
        case .artifactAdded:       return Color(hex: "5A6480")
        case .folderMoved:         return Brand.statusStuck
        case .projectDisconnected: return Brand.textMuted
        case .githubSync:          return Brand.accent
        case .sceneBoardChange:    return Brand.accent.opacity(0.85)
        case .nestedRepoDetected:  return Brand.statusStuck
        case .seedPromoted:        return Brand.textBrand   // tan-600 — garden/seed themed
        case .paste:               return Color(hex: "7C6F9F")  // muted violet — provenance/origin
        case .bundleExported:      return Brand.accent
        case .promotedToWorks:     return Brand.accentDark
        case .chainStarted:        return Brand.accent
        case .chainReset:          return Brand.statusStuck
        case .manifestMigrated:     return Brand.textMuted
        case .projectsDeduplicated: return Brand.textMuted
        case .error:                return Color.red
        }
    }

    /// seedPromoted and paste events with metadata are tappable — show a chevron indicator.
    private var isTappable: Bool {
        event.metadata != nil && (event.type == .seedPromoted || event.type == .paste)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.type.displayName)
                        .font(.caption.bold())
                        .foregroundColor(isPreChain ? Brand.textMuted : eventColor)
                    if isPreChain {
                        Text("pre-chain")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Brand.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Brand.surfaceSunken)
                            .overlay(
                                RoundedRectangle(cornerRadius: Brand.radiusSm)
                                    .stroke(Brand.border, lineWidth: 0.5)
                            )
                            .cornerRadius(Brand.radiusSm)
                    }
                    Spacer()
                    Text(displayFmt.string(from: event.timestamp))
                        .font(.caption2)
                        .foregroundColor(Brand.textMuted)
                    if isTappable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Brand.textMuted)
                    }
                }
                Text(event.detail)
                    .font(.caption)
                    .foregroundColor(isPreChain ? Brand.textMuted : Brand.textPrimary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        .opacity(isPreChain ? 0.65 : 1.0)
    }
}

struct FilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : Brand.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Brand.accent : Brand.surfaceSunken)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paste detail sheet

struct PasteDetailView: View {
    let event: LedgerEvent
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    private var meta: PasteMetadata? {
        guard let data = event.metadata else { return nil }
        return try? JSONDecoder().decode(PasteMetadata.self, from: data)
    }

    private let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "7C6F9F"))
                        Text("Paste Source")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Brand.textPrimary)
                        if meta?.isAI == true {
                            TypeBadge(label: "AI", color: Color(hex: "7C6F9F"))
                        }
                    }
                    Text(displayFmt.string(from: event.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(Brand.textMuted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.spaceMD) {

                    // Source
                    if let meta {
                        PasteDetailRow(label: "Source") {
                            if let url = meta.sourceURL {
                                Button(url.host ?? url.absoluteString) {
                                    openURL(url)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Brand.accent)
                                .underline()
                            } else if let bundle = meta.sourceBundleID {
                                Text(bundle)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Brand.textPrimary)
                            } else {
                                Text("Unknown")
                                    .font(.system(size: 13))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }

                        PasteDetailRow(label: "App") {
                            Text(meta.sourceBundleID ?? "—")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Brand.textSecondary)
                        }

                        PasteDetailRow(label: "File") {
                            Text(meta.matchedFile)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Brand.textPrimary)
                        }

                        PasteDetailRow(label: "Content") {
                            HStack(spacing: 8) {
                                TypeBadge(label: meta.kind, color: Brand.textMuted)
                                Text("\(meta.contentLength) bytes")
                                    .font(.system(size: 12))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }

                        // Preview block
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Brand.textMuted)
                                .textCase(.uppercase)
                            Text("\u{201C}\(meta.contentPreview)\u{2026}\u{201D}")
                                .font(.system(size: 13))
                                .foregroundColor(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(Brand.spaceSM)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Brand.surfaceSunken)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Brand.radiusMd)
                                        .stroke(Brand.border, lineWidth: 0.5)
                                )
                                .cornerRadius(Brand.radiusMd)
                        }

                        if let hash = meta.snapshotHash {
                            PasteDetailRow(label: "Snapshot") {
                                Text(String(hash.prefix(7)))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Brand.textMuted)
                            }
                        }
                    } else {
                        Text("Paste metadata unavailable.")
                            .font(.caption)
                            .foregroundColor(Brand.textMuted)
                    }
                }
                .padding(Brand.spaceLG)
            }
        }
        .frame(width: 480, height: 400)
        .background(Brand.surfaceBase)
    }
}

private struct PasteDetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Brand.textMuted)
                .textCase(.uppercase)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }
}
