import Foundation

/// Read-only access to a local codebase for scenario generation. Exposed to the
/// model as three tools (`code_list`, `code_search`, `code_read`); every path is
/// resolved inside the chosen root and anything outside it is refused.
nonisolated struct CodebaseTools: Sendable {
    let root: URL

    static let toolNames: Set<String> = ["code_list", "code_search", "code_read"]

    private static let ignoredDirs: Set<String> = [
        ".git", "node_modules", "build", "dist", "DerivedData", ".next", ".nuxt", ".venv", "venv", "__pycache__",
        "Pods", ".build", "target", "vendor", "coverage", ".gradle", ".idea", ".turbo", ".cache", "out", ".svelte-kit",
    ]
    private static let maxFileBytes = 512 * 1024
    private static let maxFilesScanned = 30_000
    private static let maxMatches = 150
    private static let maxReadLines = 600

    /// Tool definitions in the same shape as MCP tools, so both engines can offer them.
    static var tools: [MCPClient.Tool] {
        [
            .init(name: "code_list",
                  description: "List files and folders in the product's codebase (read-only). Paths are relative to the repo root.",
                  inputSchema: ["type": "object", "properties": [
                      "path": ["type": "string", "description": "Folder relative to the repo root; empty for the root."],
                      "depth": ["type": "integer", "description": "How many levels to list (1–3). Default 1."],
                  ], "required": []]),
            .init(name: "code_search",
                  description: "Search the codebase for text (case-insensitive). Returns path:line: text matches. Use it to find screens, routes, permission checks and validations related to the ticket.",
                  inputSchema: ["type": "object", "properties": [
                      "query": ["type": "string", "description": "Text to find, e.g. a component, route, label or error message."],
                      "path": ["type": "string", "description": "Optional folder to limit the search to."],
                      "extensions": ["type": "array", "items": ["type": "string"], "description": "Optional file extensions, e.g. [\"tsx\",\"ts\"]."],
                  ], "required": ["query"]]),
            .init(name: "code_read",
                  description: "Read part of a file from the codebase with line numbers.",
                  inputSchema: ["type": "object", "properties": [
                      "path": ["type": "string", "description": "File path relative to the repo root."],
                      "startLine": ["type": "integer", "description": "First line (1-based). Default 1."],
                      "endLine": ["type": "integer", "description": "Last line. Default startLine + 300."],
                  ], "required": ["path"]]),
        ]
    }

    func call(_ name: String, _ input: JSONValue) -> (text: String, isError: Bool) {
        do {
            switch name {
            case "code_list": return (try list(input["path"]?.stringValue ?? "", depth: int(input["depth"]) ?? 1), false)
            case "code_search":
                guard let q = input["query"]?.stringValue, !q.isEmpty else { return ("query is required", true) }
                let exts = (input["extensions"]?.arrayValue ?? []).compactMap(\.stringValue)
                return (try search(q, in: input["path"]?.stringValue ?? "", extensions: exts), false)
            case "code_read":
                guard let p = input["path"]?.stringValue else { return ("path is required", true) }
                return (try read(p, start: int(input["startLine"]) ?? 1, end: int(input["endLine"])), false)
            default: return ("Unknown code tool \(name)", true)
            }
        } catch {
            return (error.localizedDescription, true)
        }
    }

    // MARK: - Tools

    private func list(_ path: String, depth: Int) throws -> String {
        let dir = try resolve(path)
        let depth = min(max(depth, 1), 3)
        var lines: [String] = []
        func walk(_ url: URL, level: Int) {
            guard level <= depth, lines.count < 400,
                  let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                           options: [.skipsHiddenFiles]) else { return }
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir && Self.ignoredDirs.contains(item.lastPathComponent) { continue }
                lines.append(String(repeating: "  ", count: level - 1) + relative(item) + (isDir ? "/" : ""))
                if isDir { walk(item, level: level + 1) }
            }
        }
        walk(dir, level: 1)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n") + (lines.count >= 400 ? "\n… (truncated)" : "")
    }

    private func search(_ query: String, in path: String, extensions: [String]) throws -> String {
        let base = try resolve(path)
        let needle = query.lowercased()
        let exts = Set(extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        var matches: [String] = []
        var scanned = 0
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                        options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL, matches.count < Self.maxMatches, scanned < Self.maxFilesScanned {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if Self.ignoredDirs.contains(url.lastPathComponent) { enumerator?.skipDescendants() }
                continue
            }
            if !exts.isEmpty && !exts.contains(url.pathExtension.lowercased()) { continue }
            guard (values?.fileSize ?? 0) <= Self.maxFileBytes, let text = textContents(url) else { continue }
            scanned += 1
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.lowercased().contains(needle) {
                matches.append("\(relative(url)):\(i + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(200))")
                if matches.count >= Self.maxMatches { break }
            }
        }
        if matches.isEmpty { return "No matches for \"\(query)\"." }
        return matches.joined(separator: "\n") + (matches.count >= Self.maxMatches ? "\n… (more matches; narrow the search)" : "")
    }

    private func read(_ path: String, start: Int, end: Int?) throws -> String {
        let url = try resolve(path)
        guard let text = textContents(url) else { throw ToolError("\(path) is not a readable text file (or is over 512 KB).") }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let from = max(1, start)
        let to = min(lines.count, end ?? (from + 300), from + Self.maxReadLines - 1)
        guard from <= lines.count else { return "(file has \(lines.count) lines)" }
        let body = (from...to).map { "\($0)\t\(lines[$0 - 1])" }.joined(separator: "\n")
        return "\(relative(url)) — lines \(from)–\(to) of \(lines.count)\n" + body
    }

    // MARK: - Safety

    struct ToolError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    /// Resolves a repo-relative path, refusing anything (incl. symlinks) that escapes the root.
    private func resolve(_ path: String) throws -> URL {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let url = (trimmed.isEmpty ? root : root.appending(path: trimmed)).standardizedFileURL.resolvingSymlinksInPath()
        // Existence first: symlinks (e.g. /tmp → /private/tmp) only resolve for paths that exist.
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No such path: \(path)") }
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            throw ToolError("Path is outside the codebase: \(path)")
        }
        return url
    }

    private func relative(_ url: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        return p.hasPrefix(rootPath + "/") ? String(p.dropFirst(rootPath.count + 1)) : url.lastPathComponent
    }

    /// UTF-8 text under the size cap, skipping binaries (NUL bytes in the first 8 KB).
    private func textContents(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= Self.maxFileBytes,
              !data.prefix(8192).contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func int(_ v: JSONValue?) -> Int? {
        if case .number(let n) = v ?? .null { return Int(n) }
        return nil
    }
}
