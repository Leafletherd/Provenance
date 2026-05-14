import Foundation
import CryptoKit
import AppKit

// MARK: - Chain model

/// Sidecar that stores the full SHA256 hash for every chained ledger line.
/// Written to .ledger/ledger.chain.json.
struct LedgerChain: Codable {
    var version: Int
    var chainStartedAt: Date
    var genesisHash: String
    var lineHashes: [String]
    var head: String
    /// Number of ledger.md lines that existed before the chain was started
    /// (pre-chain events). They are displayed differently in the Ledger tab.
    var preChainEventCount: Int
    /// Reserved for future external timestamp anchors (OpenTimestamps, etc.).
    /// Always written as an empty array in v1; consumers must tolerate it.
    var externalAnchors: [ExternalAnchor]

    struct ExternalAnchor: Codable {
        let type: String
        let anchoredAt: Date
        let lineIndex: Int
        let ots: String
    }
}

// MARK: - LedgerIntegrity

struct LedgerIntegrity {

    // MARK: - Result types

    enum ChainResult {
        case intact
        case brokenAt(line: Int, expected: String, found: String, content: String)
        case missingChainFile
    }

    enum GitResult {
        case consistent
        case historyRewritten(missing: [(hash: String, date: Date)])
    }

    /// Combined project-level status exposed via `ProjectState.integrityStatus`.
    enum IntegrityStatus: Equatable {
        case checking
        case intact(chainSince: Date, preChainCount: Int)
        case chainBroken(at: Int, expected: String, found: String, content: String)
        case historyRewritten(missing: [(hash: String, date: Date)])
        case unchecked   // pre-chain project where migration hasn't run yet

        static func == (lhs: IntegrityStatus, rhs: IntegrityStatus) -> Bool {
            switch (lhs, rhs) {
            case (.checking, .checking),
                 (.unchecked, .unchecked):
                return true
            case let (.intact(a, b), .intact(c, d)):
                return a == c && b == d
            case let (.chainBroken(a, b, c, d), .chainBroken(e, f, g, h)):
                return a == e && b == f && c == g && d == h
            case let (.historyRewritten(a), .historyRewritten(b)):
                return a.map(\.hash) == b.map(\.hash)
            default:
                return false
            }
        }
    }

    // MARK: - Genesis constant

    static let genesisInput = "provenance-ledger-v1-genesis"

    static var genesisHash: String { sha256hex(genesisInput) }

    // MARK: - SHA256 helper

    static func sha256hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Chain file I/O

    static func readChain(from project: Project) -> LedgerChain? {
        guard let data = try? Data(contentsOf: project.chainURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LedgerChain.self, from: data)
    }

    static func writeChain(_ chain: LedgerChain, to project: Project) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(chain) else { return }
        try? data.write(to: project.chainURL, options: .atomic)
    }

    /// Returns the current chain head hash (or genesis if no chain file yet).
    static func currentHead(project: Project) -> String {
        readChain(from: project)?.head ?? genesisHash
    }

    /// Appends a new hash to the chain file after each successful ledger write.
    /// Creates the chain file on first call (using genesis as the starting head).
    static func appendHash(_ hash: String, to project: Project) {
        var chain: LedgerChain
        if let existing = readChain(from: project) {
            chain = existing
        } else {
            chain = LedgerChain(
                version: 2,
                chainStartedAt: Date(),
                genesisHash: genesisHash,
                lineHashes: [],
                head: genesisHash,
                preChainEventCount: 0,
                externalAnchors: []
            )
        }
        chain.lineHashes.append(hash)
        chain.head = hash
        writeChain(chain, to: project)
    }

    // MARK: - Migration

    /// Called once per project on first launch after PR-8.
    /// Idempotent — no-ops if the chain file already exists.
    static func migrateIfNeeded(project: Project) {
        guard !FileManager.default.fileExists(atPath: project.chainURL.path) else { return }

        // Count existing pre-chain ledger lines (those without ·h: suffix).
        let preChainCount = countUnchamedLines(project: project)

        // Append chainStarted — LedgerWriter will create the chain file from genesis.
        LedgerWriter.appendEvent(
            type: .chainStarted,
            detail: "Integrity chain initialized. Earlier history is not chain-verified.",
            to: project
        )

        // Backfill preChainEventCount in the newly-created chain file.
        if var chain = readChain(from: project) {
            chain.preChainEventCount = preChainCount
            writeChain(chain, to: project)
        }
    }

    private static func countUnchamedLines(project: Project) -> Int {
        guard let content = try? String(contentsOf: project.ledgerMDURL, encoding: .utf8) else {
            return 0
        }
        return content.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("[") && !$0.contains("  ·h: ") }
            .count
    }

    // MARK: - Verify chain

    static func verify(project: Project) -> ChainResult {
        guard let chain = readChain(from: project) else { return .missingChainFile }
        guard let content = try? String(contentsOf: project.ledgerMDURL, encoding: .utf8) else {
            return .missingChainFile
        }

        let sep = "  ·h: "
        let chainedLines = content.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.contains(sep) }

        if chainedLines.count != chain.lineHashes.count {
            let lineNum = min(chainedLines.count, chain.lineHashes.count) + 1
            return .brokenAt(
                line: lineNum,
                expected: "\(chain.lineHashes.count) chained lines",
                found: "\(chainedLines.count) in ledger.md",
                content: "Line count mismatch"
            )
        }

        var prevHash = chain.genesisHash
        for (i, line) in chainedLines.enumerated() {
            guard let sepRange = line.range(of: sep) else {
                return .brokenAt(line: i + 1, expected: "hash suffix",
                                 found: "none", content: String(line.prefix(80)))
            }
            let lineContent  = String(line[..<sepRange.lowerBound])
            let inlinePrefix = String(line[sepRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            let computed = sha256hex(prevHash + lineContent)
            let stored   = chain.lineHashes[i]

            if computed != stored {
                return .brokenAt(
                    line: i + 1,
                    expected: String(stored.prefix(12)),
                    found: inlinePrefix,
                    content: String(lineContent.prefix(80))
                )
            }
            if !computed.hasPrefix(inlinePrefix) {
                return .brokenAt(
                    line: i + 1,
                    expected: String(computed.prefix(12)),
                    found: inlinePrefix,
                    content: String(lineContent.prefix(80))
                )
            }
            prevHash = computed
        }
        return .intact
    }

    // MARK: - Verify git consistency

    static func verifyGitConsistency(project: Project, snapshots: [Snapshot]) -> GitResult {
        var missing: [(hash: String, date: Date)] = []
        for snap in snapshots where !snap.hash.isEmpty {
            if !gitObjectExists(hash: snap.hash, project: project) {
                missing.append((hash: snap.hash, date: snap.timestamp))
            }
        }
        return missing.isEmpty ? .consistent : .historyRewritten(missing: missing)
    }

    private static func gitObjectExists(hash: String, project: Project) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        let gitDir = project.snapshotsURL.appendingPathComponent(".git").path
        proc.arguments = ["--git-dir=\(gitDir)", "--work-tree=\(project.folderURL.path)",
                          "cat-file", "-e", hash]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    // MARK: - Combine results

    static func combine(_ chain: ChainResult, _ git: GitResult, project: Project) -> IntegrityStatus {
        switch chain {
        case .missingChainFile:
            return .unchecked
        case .brokenAt(let line, let exp, let found, let content):
            return .chainBroken(at: line, expected: exp, found: found, content: content)
        case .intact:
            if case .historyRewritten(let missing) = git {
                return .historyRewritten(missing: missing)
            }
            let c = readChain(from: project)
            return .intact(
                chainSince: c?.chainStartedAt ?? Date(),
                preChainCount: c?.preChainEventCount ?? 0
            )
        }
    }

    // MARK: - Reset chain (destructive, always recorded)

    /// Accepts the current state as a new chain baseline.
    /// Records a `chainReset` event (never silent) and rebuilds chain from genesis.
    static func resetChain(project: Project, previousStatusDescription: String) {
        // Count all current lines (including broken ones) as the pre-reset baseline.
        let preResetCount: Int
        if let content = try? String(contentsOf: project.ledgerMDURL, encoding: .utf8) {
            preResetCount = content.split(separator: "\n", omittingEmptySubsequences: true)
                .filter { $0.hasPrefix("[") }
                .count
        } else {
            preResetCount = 0
        }

        // Remove the old chain file so appendEvent re-initialises from genesis.
        try? FileManager.default.removeItem(at: project.chainURL)

        // Append the reset marker — this becomes the new chain's first entry.
        LedgerWriter.appendEvent(
            type: .chainReset,
            detail: "Chain reset. Previous state: \(previousStatusDescription). " +
                    "New baseline established from \(preResetCount) pre-reset events.",
            to: project
        )

        // Record how many lines existed before the reset.
        if var chain = readChain(from: project) {
            chain.preChainEventCount = preResetCount
            writeChain(chain, to: project)
        }
    }
}
