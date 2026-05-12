import Foundation

struct GitService {
    static func initialize(project: Project) throws {
        let snapshotsURL = project.snapshotsURL
        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        // init git repo inside snapshots/
        try run(["init", snapshotsURL.path])
        // configure the worktree
        try run(["--git-dir=\(snapshotsURL.path)/.git", "config", "core.worktree", project.folderURL.path])
        // exclude .ledger from tracking
        let excludesPath = snapshotsURL.appendingPathComponent(".git/info/exclude")
        var excludes = (try? String(contentsOf: excludesPath)) ?? ""
        if !excludes.contains(".ledger") {
            excludes += "\n.ledger\n"
            try excludes.write(to: excludesPath, atomically: true, encoding: .utf8)
        }
        // initial empty commit so we have a HEAD
        let env = ["GIT_DIR": "\(snapshotsURL.path)/.git",
                   "GIT_WORK_TREE": project.folderURL.path,
                   "GIT_AUTHOR_NAME": "Provenance",
                   "GIT_AUTHOR_EMAIL": "provenance@local",
                   "GIT_COMMITTER_NAME": "Provenance",
                   "GIT_COMMITTER_EMAIL": "provenance@local"]
        _ = try? runWithEnv(["commit", "--allow-empty", "-m", "init: project connected"], env: env)
    }

    @discardableResult
    static func commit(message: String, project: Project) throws -> String? {
        let snapshotsURL = project.snapshotsURL
        let gitDir = "\(snapshotsURL.path)/.git"
        let workTree = project.folderURL.path
        let env = ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree,
                   "GIT_AUTHOR_NAME": "Provenance", "GIT_AUTHOR_EMAIL": "provenance@local",
                   "GIT_COMMITTER_NAME": "Provenance", "GIT_COMMITTER_EMAIL": "provenance@local"]
        let args = ["--git-dir=\(gitDir)", "--work-tree=\(workTree)"]
        // Pass the work tree path explicitly so git add -A always stages from
        // the right root regardless of the process's working directory.
        _ = try? runWithEnv(args + ["add", "-A", "--", workTree], env: env)
        // Check if there is anything to commit (staged or untracked changes).
        let statusOut = (try? runWithEnv(args + ["status", "--porcelain"], env: env)) ?? ""
        let hasChanges = !statusOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasChanges else { return nil }
        _ = try? runWithEnv(args + ["commit", "-m", message], env: env)
        let hash = (try? runWithEnv(args + ["rev-parse", "--short", "HEAD"], env: env))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hash
    }

    // MARK: - File content at a specific commit

    /// Returns the full text content of a file at the given commit hash.
    /// `relativePath` is the path relative to the project folder (as returned by git diff-tree).
    static func fileContent(hash: String, relativePath: String, project: Project) -> String? {
        let gitDir = "\(project.snapshotsURL.path)/.git"
        let workTree = project.folderURL.path
        let env = ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree]
        let args = ["--git-dir=\(gitDir)", "--work-tree=\(workTree)"]
        return try? runWithEnv(args + ["show", "\(hash):\(relativePath)"], env: env)
    }

    /// Returns the previous commit's full text content of the same file, for diffing.
    static func fileContentPrevious(hash: String, relativePath: String, project: Project) -> String? {
        let gitDir = "\(project.snapshotsURL.path)/.git"
        let workTree = project.folderURL.path
        let env = ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree]
        let args = ["--git-dir=\(gitDir)", "--work-tree=\(workTree)"]
        // Try parent commit first; if this is the first commit, return nil (no previous).
        return try? runWithEnv(args + ["show", "\(hash)^:\(relativePath)"], env: env)
    }

    static func log(project: Project) throws -> [Snapshot] {
        let snapshotsURL = project.snapshotsURL
        let gitDir = "\(snapshotsURL.path)/.git"
        let workTree = project.folderURL.path
        let env = ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree]
        let args = ["--git-dir=\(gitDir)", "--work-tree=\(workTree)"]
        let format = "--format=%H|%at|%s"
        let output = (try? runWithEnv(args + ["log", format], env: env)) ?? ""
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line -> Snapshot? in
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count >= 3 else { return nil }
            let hash = String(parts[0])
            let shortHash = String(hash.prefix(7))
            guard let epochDouble = Double(parts[1]) else { return nil }
            let timestamp = Date(timeIntervalSince1970: epochDouble)
            let subject = String(parts[2])
            let trigger: SnapshotTrigger
            let snapshotLabel: String?
            if subject.hasPrefix("auto:") {
                trigger = .auto
                // "auto: file saved <filename> <datetime>" → show just the filename
                let body = subject.dropFirst("auto:".count).trimmingCharacters(in: .whitespaces)
                if body.hasPrefix("file saved ") {
                    let afterPrefix = body.dropFirst("file saved ".count)
                    // filename is everything up to the last space-separated datetime
                    // safest: take the first token which is the filename
                    snapshotLabel = afterPrefix.components(separatedBy: " ").first
                } else {
                    snapshotLabel = body.isEmpty ? nil : body
                }
            } else if subject.hasPrefix("scheduled:") {
                trigger = .scheduled
                snapshotLabel = nil
            } else if subject.hasPrefix("manual:") {
                trigger = .manual
                let body = subject.dropFirst("manual:".count).trimmingCharacters(in: .whitespaces)
                snapshotLabel = body.isEmpty ? nil : body
            } else {
                trigger = .manual
                snapshotLabel = subject.isEmpty ? nil : subject
            }
            // get files changed
            let diffOut = (try? runWithEnv(args + ["diff-tree", "--no-commit-id", "-r", "--name-only", hash], env: env)) ?? ""
            let changedFiles = diffOut.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return Snapshot(hash: shortHash, timestamp: timestamp, trigger: trigger,
                            filesChanged: changedFiles.count, label: snapshotLabel, changedFiles: changedFiles)
        }
    }

    static func diff(hash1: String, hash2: String, project: Project) throws -> String {
        let snapshotsURL = project.snapshotsURL
        let gitDir = "\(snapshotsURL.path)/.git"
        let workTree = project.folderURL.path
        let env = ["GIT_DIR": gitDir, "GIT_WORK_TREE": workTree]
        let args = ["--git-dir=\(gitDir)", "--work-tree=\(workTree)"]
        return (try? runWithEnv(args + ["diff", hash1, hash2], env: env)) ?? ""
    }

    // MARK: - Private

    @discardableResult
    private static func run(_ args: [String]) throws -> String {
        return try runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/git"), args: args, env: nil)
    }

    @discardableResult
    private static func runWithEnv(_ args: [String], env: [String: String]) throws -> String {
        return try runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/git"), args: args, env: env)
    }

    private static func runProcess(executableURL: URL, args: [String], env: [String: String]?) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        if let env = env {
            var fullEnv = ProcessInfo.processInfo.environment
            for (k, v) in env { fullEnv[k] = v }
            process.environment = fullEnv
        }
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "GitService", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
