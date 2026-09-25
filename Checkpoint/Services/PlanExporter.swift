import Foundation

/// Turns a saved plan into a shareable Markdown document or a self-contained,
/// Liquid Glass–styled HTML page (light/dark, printable, tickable in the browser).
nonisolated enum PlanExporter {
    struct Context: Sendable {
        var saved: SavedPlan
        var generatedAt: Date = .now
        /// Export only the smoke subset (IDEA-001).
        var smokeOnly: Bool = false
    }

    private static func exportTasks(_ ctx: Context) -> [TestPlan.Task] {
        ctx.smokeOnly ? ctx.saved.plan.smokeSubset : ctx.saved.plan.tasks
    }

    // MARK: - Markdown

    static func markdown(_ ctx: Context) -> String {
        let s = ctx.saved, p = s.plan
        let doneTasks = s.tasksDone, met = s.criteriaMet
        var md = "# \(p.ticket.key) — \(p.ticket.title)\n\n"
        md += "> **\(s.mode == .qa ? "QA" : "Dev") test plan** · \(p.ticket.type) · \(p.ticket.status)"
        if let url = URL(string: p.ticket.url), url.scheme != nil { md += " · [Open ticket](\(p.ticket.url))" }
        md += "\n>\n> ✅ **\(doneTasks)/\(p.tasks.count)** tasks tested"
        if s.failedCount > 0 { md += " · ❌ **\(s.failedCount)** failed" }
        if s.blockedCount > 0 { md += " · ⛔ **\(s.blockedCount)** blocked" }
        let elapsed = s.testingSeconds + (s.timerRunningSince.map { Date().timeIntervalSince($0) } ?? 0)
        if elapsed >= 60 { md += " · ⏱ **\(formatDuration(elapsed))** testing" }
        if !p.acceptanceCriteria.isEmpty { md += " · 🎯 **\(met)/\(p.acceptanceCriteria.count)** acceptance criteria met" }
        if !p.scenarios.isEmpty {
            md += " · 🎭 **\(p.scenarios.filter { s.done.contains("scenario:" + $0.id) }.count)/\(p.scenarios.count)** scenarios run"
        }
        md += "\n\n\(p.summary)\n"

        if !p.preconditions.isEmpty {
            md += "\n## 🧰 Before you start\n\n" + p.preconditions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !p.acceptanceCriteria.isEmpty {
            md += "\n## 🎯 Acceptance criteria\n\n"
            for ac in p.acceptanceCriteria {
                let src = ac.source == "derived" ? "_derived_" : "`\(ac.source)`"
                md += "- [\(s.metCriteria.contains(ac.id) ? "x" : " ")] **\(ac.id)** \(ac.text) — \(src)\n"
            }
        }
        md += "\n## ☑️ Test tasks\n"
        let exportList = exportTasks(ctx)
        var lastTicket = ""
        for t in exportList {
            if t.ticketKey != lastTicket, Set(exportList.map(\.ticketKey)).count > 1 {
                md += "\n### \(t.ticketKey)\n"
                lastTicket = t.ticketKey
            }
            md += "\n- [\(s.done.contains(t.id) ? "x" : " ")] **\(t.title)**"
            md += " · \(priorityEmoji(t.priority)) \(t.priority.rawValue)"
            if !t.area.isEmpty { md += " · \(t.area)" }
            if let mins = t.estimateMin { md += " · ⏱ ~\(mins) min" }
            if let actual = s.failed[t.id] {
                md += " · ❌ **FAIL**" + (actual.isEmpty ? "" : ": \(actual)")
            } else if let reason = s.blocked[t.id] {
                md += " · ⛔ **BLOCKED**" + (reason.isEmpty ? "" : ": \(reason)")
            }
            md += "\n"
            for (i, step) in t.steps.enumerated() { md += "    \(i + 1). \(step)\n" }
            md += "    - **Expected:** \(t.expected)\n"
            if !t.testData.isEmpty { md += "    - Data: \(t.testData.joined(separator: " · "))\n" }
            if !t.covers.isEmpty { md += "    - Covers: \(t.covers.joined(separator: ", "))\n" }
            if !t.sources.isEmpty {
                md += "    - From: " + t.sources.map { "\($0.ticketKey)/\($0.kind):\($0.ref)" }.joined(separator: ", ") + "\n"
            }
            if let note = s.notes[t.id], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                md += "    - Note: \(note)\n"
            }
            if let files = s.evidence[t.id], !files.isEmpty {
                md += "    - Evidence: \(files.joined(separator: ", "))\n"
            }
        }
        if !p.scenarios.isEmpty {
            md += "\n## 🎭 Scenarios\n"
            for sc in p.scenarios {
                md += "\n- [\(s.done.contains("scenario:" + sc.id) ? "x" : " ")] **\(sc.title)** — _\(sc.role)_\n"
                md += "    - **Goal:** \(sc.goal)\n"
                for (i, step) in sc.steps.enumerated() { md += "    \(i + 1). \(step)\n" }
                md += "    - **End result:** \(sc.expected)\n"
                if !sc.relatedTickets.isEmpty { md += "    - Based on: \(sc.relatedTickets.map { "`\($0)`" }.joined(separator: ", "))\n" }
            }
        }
        if !p.edgeCases.isEmpty {
            md += "\n## ⚠️ Edge cases worth poking\n\n" + p.edgeCases.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !p.openQuestions.isEmpty {
            md += "\n## ❓ Open questions\n\n" + p.openQuestions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !p.sources.isEmpty {
            md += "\n## 📚 Sources\n\n" + p.sources.map { src in
                let label = "\(src.key) — \(src.title)"
                return URL(string: src.url)?.scheme != nil ? "- [\(label)](\(src.url)) · \(src.relation)" : "- \(label) · \(src.relation)"
            }.joined(separator: "\n") + "\n"
        }
        md += "\n---\n_Generated by [Checkpoint](https://checkpoint.guide) on \(stamp(ctx.generatedAt))._\n"
        return md
    }

    private static func priorityEmoji(_ p: TestPlan.Priority) -> String {
        switch p { case .high: "🔴"; case .medium: "🟠"; case .low: "⚪️" }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    // MARK: - Automation skeletons (IDEA-014)

    enum SkeletonFramework { case playwright, xctest }

    /// Test names + steps-as-todos + AC links. Deliberately unrunnable stubs.
    static func automation(_ ctx: Context, framework: SkeletonFramework) -> String {
        let p = ctx.saved.plan
        func testName(_ t: TestPlan.Task) -> String {
            let words = t.title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.prefix(8).joined(separator: "_")
            return words.isEmpty ? "task_\(t.id)" : words
        }
        switch framework {
        case .playwright:
            var out = "// \(p.ticket.key) — \(p.ticket.title)\n// Generated by Checkpoint. Fill in selectors and assertions.\n"
            out += "import { test, expect } from '@playwright/test';\n"
            for t in p.tasks {
                out += "\ntest('\(testName(t))', async ({ page }) => {\n"
                out += "  // AC: \(t.covers.isEmpty ? "—" : t.covers.joined(separator: ", "))\n"
                for (i, step) in t.steps.enumerated() { out += "  // \(i + 1). \(step)\n" }
                out += "  // Expected: \(t.expected)\n  test.fixme();\n});\n"
            }
            return out
        case .xctest:
            var out = "// \(p.ticket.key) — \(p.ticket.title)\n// Generated by Checkpoint. Fill in selectors and assertions.\n"
            out += "import XCTest\n\nfinal class \(p.ticket.key.replacingOccurrences(of: "-", with: "_"))Tests: XCTestCase {\n"
            for t in p.tasks {
                let fn = "test" + testName(t).split(separator: "_").map(\.capitalized).joined()
                out += "\n    func \(fn)() throws {\n"
                out += "        // AC: \(t.covers.isEmpty ? "—" : t.covers.joined(separator: ", "))\n"
                for (i, step) in t.steps.enumerated() { out += "        // \(i + 1). \(step)\n" }
                out += "        // Expected: \(t.expected)\n        XCTFail(\"TODO\");\n    }\n"
            }
            return out + "}\n"
        }
    }

    // MARK: - HTML

    static func html(_ ctx: Context) -> String {
        let s = ctx.saved, p = s.plan
        let tasksPct = p.tasks.isEmpty ? 0 : Int(Double(s.tasksDone) / Double(p.tasks.count) * 100)
        let acPct = p.acceptanceCriteria.isEmpty ? 0 : Int(Double(s.criteriaMet) / Double(p.acceptanceCriteria.count) * 100)
        let multiTicket = Set(p.tasks.map(\.ticketKey)).count > 1

        var body = ""
        // Header card
        body += """
        <header class="card glass hero">
          <div class="hero-text">
            <div class="chips">
              \(link(p.ticket.url, "<span class=\"key\">\(e(p.ticket.key))</span>"))
              <span class="chip \(s.mode == .qa ? "qa" : "dev")">\(s.mode == .qa ? "QA" : "Dev")</span>
              <span class="chip">\(e(p.ticket.type))</span>
              <span class="chip blue">\(e(p.ticket.status))</span>
            </div>
            <h1>\(e(p.ticket.title))</h1>
            <p class="summary">\(e(p.summary))</p>
          </div>
          <div class="rings">
            \(ring(tasksPct, "\(s.tasksDone)/\(p.tasks.count)", "tested", "#4B3FD1", id: "ring-tasks"))
            \(p.acceptanceCriteria.isEmpty ? "" : ring(acPct, "\(s.criteriaMet)/\(p.acceptanceCriteria.count)", "AC met", "#2BB5A8", id: "ring-ac"))
          </div>
        </header>
        """

        if !p.preconditions.isEmpty {
            body += section("🧰", "Before you start", "<ul>" + p.preconditions.map { "<li>\(e($0))</li>" }.joined() + "</ul>")
        }
        if !p.acceptanceCriteria.isEmpty {
            let rows = p.acceptanceCriteria.map { ac -> String in
                let met = s.metCriteria.contains(ac.id)
                let src = ac.source == "derived" ? "<span class=\"chip warn\">derived</span>" : "<span class=\"mono faint\">\(e(ac.source))</span>"
                return "<label class=\"ac\"><input type=\"checkbox\" data-kind=\"ac\"\(met ? " checked" : "")><span class=\"id mono\">\(e(ac.id))</span><span class=\"t\">\(e(ac.text))</span>\(src)</label>"
            }.joined()
            body += section("🎯", "Acceptance criteria", rows)
        }

        var tasksHTML = ""
        var lastTicket = ""
        let htmlTasks = exportTasks(ctx)
        for t in htmlTasks {
            if multiTicket && t.ticketKey != lastTicket {
                tasksHTML += "<h3 class=\"group\">\(e(t.ticketKey))</h3>"
                lastTicket = t.ticketKey
            }
            let done = s.done.contains(t.id)
            let verdictBadge: String
            let verdictNote: String
            if let actual = s.failed[t.id] {
                verdictBadge = "<span class=\"chip fail\">FAIL</span>"
                verdictNote = actual.isEmpty ? "" : "<div class=\"failnote fail\">❌ \(e(actual))</div>"
            } else if let reason = s.blocked[t.id] {
                verdictBadge = "<span class=\"chip blocked\">BLOCKED</span>"
                verdictNote = reason.isEmpty ? "" : "<div class=\"failnote blocked\">⛔ \(e(reason))</div>"
            } else {
                verdictBadge = ""
                verdictNote = ""
            }
            tasksHTML += """
            <details class="task" open>
              <summary><input type="checkbox" data-kind="task"\(done ? " checked" : "")><span class="ttl">\(e(t.title))</span>\(verdictBadge)\(t.area.isEmpty ? "" : "<span class=\"chip\">\(e(t.area))</span>")\(t.estimateMin.map { "<span class=\"chip\">⏱ ~\($0) min</span>" } ?? "")<span class="dot \(t.priority.rawValue)" title="\(t.priority.rawValue) priority"></span></summary>
              \(verdictNote)
              <ol>\(t.steps.map { "<li>\(e($0))</li>" }.joined())</ol>
              <div class="expected">✓ \(e(t.expected))</div>
              \(t.testData.isEmpty ? "" : "<div class=\"covers\">Data: \(e(t.testData.joined(separator: " · ")))</div>")
              \(noteHTML(s.notes[t.id]))
              \(evidenceHTML(ctx: ctx, taskID: t.id))
              \(t.covers.isEmpty ? "" : "<div class=\"covers\">Covers \(e(t.covers.joined(separator: ", ")))</div>")
            </details>
            """
        }
        body += section("☑️", "Test tasks", tasksHTML)

        if !p.scenarios.isEmpty {
            let cards = p.scenarios.map { sc -> String in
                let done = s.done.contains("scenario:" + sc.id)
                return """
                <details class="task scenario" open>
                  <summary><input type="checkbox" data-kind="scenario"\(done ? " checked" : "")><span class="ttl">\(e(sc.title))</span><span class="chip purple">\(e(sc.basis))</span></summary>
                  <div class="role">👤 \(e(sc.role)) — \(e(sc.goal))</div>
                  <ol>\(sc.steps.map { "<li>\(e($0))</li>" }.joined())</ol>
                  <div class="expected purple">🏁 \(e(sc.expected))</div>
                  \(sc.relatedTickets.isEmpty ? "" : "<div class=\"covers\">Based on \(e(sc.relatedTickets.joined(separator: ", ")))</div>")
                </details>
                """
            }.joined()
            body += section("🎭", "Scenarios", cards)
        }
        if !p.edgeCases.isEmpty {
            body += section("⚠️", "Edge cases worth poking", "<ul>" + p.edgeCases.map { "<li>\(e($0))</li>" }.joined() + "</ul>")
        }
        if !p.openQuestions.isEmpty {
            body += section("❓", "Open questions", "<ul>" + p.openQuestions.map { "<li>\(e($0))</li>" }.joined() + "</ul>")
        }
        if !p.sources.isEmpty {
            let chips = p.sources.map { src in
                link(src.url, "<span class=\"src glass\"><b class=\"mono\">\(e(src.key))</b> \(e(src.relation))</span>", title: src.title)
            }.joined()
            body += section("📚", "Sources", "<div class=\"sources\">\(chips)</div>")
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Checkpoint">
        <title>\(e(p.ticket.key)) — \(e(p.ticket.title)) · Test plan</title>
        <style>\(css)</style>
        </head>
        <body>
        <div class="backdrop" aria-hidden="true"><i class="b1"></i><i class="b2"></i><i class="b3"></i></div>
        <main>
        \(body)
        <footer>Generated by <a href="https://checkpoint.guide">Checkpoint</a> · \(e(stamp(ctx.generatedAt))) · \(s.mode == .qa ? "QA" : "Dev") plan · Ticks here are saved in this browser only</footer>
        </main>
        <script>\(script(storageKey: "checkpoint:" + p.ticket.key + ":" + s.mode.rawValue))</script>
        </body>
        </html>
        """
    }

    // MARK: - HTML helpers

    private static func e(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func noteHTML(_ note: String?) -> String {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "<div class=\"note\">📝 \(e(note))</div>"
    }

    /// Embeds small images as data URIs, lists anything bigger.
    /// Path mirrors PlanStore's evidence folder (sandbox Application Support).
    private static func evidenceHTML(ctx: Context, taskID: String) -> String {
        guard let files = ctx.saved.evidence[taskID], !files.isEmpty else { return "" }
        let root = URL.applicationSupportDirectory
            .appending(path: "Checkpoint/evidence/\(ctx.saved.id)/\(taskID)")
        var imgs = "", listed: [String] = []
        for name in files {
            let lower = name.lowercased()
            let isImage = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"].contains { lower.hasSuffix($0) }
            let url = root.appending(path: name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max
            if isImage, size <= 2 * 1024 * 1024, let data = try? Data(contentsOf: url) {
                let mime = lower.hasSuffix(".png") ? "image/png" : lower.hasSuffix(".gif") ? "image/gif" : "image/jpeg"
                imgs += "<img class=\"ev\" src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(e(name))\" title=\"\(e(name))\">"
            } else {
                listed.append(name)
            }
        }
        var out = ""
        if !imgs.isEmpty { out += "<div class=\"evrow\">\(imgs)</div>" }
        if !listed.isEmpty { out += "<div class=\"covers\">Evidence: \(e(listed.joined(separator: ", ")))</div>" }
        return out
    }

    private static func link(_ url: String, _ inner: String, title: String? = nil) -> String {
        guard let u = URL(string: url), u.scheme == "https" || u.scheme == "http" else { return inner }
        return "<a href=\"\(e(url))\"\(title.map { " title=\"\(e($0))\"" } ?? "") target=\"_blank\" rel=\"noopener\">\(inner)</a>"
    }

    private static func section(_ icon: String, _ title: String, _ inner: String) -> String {
        "<section class=\"card glass\"><h2><span>\(icon)</span> \(e(title))</h2>\(inner)</section>"
    }

    private static func ring(_ pct: Int, _ value: String, _ label: String, _ color: String, id: String) -> String {
        "<div class=\"ring\" id=\"\(id)\" style=\"--p:\(pct);--c:\(color)\"><b>\(e(value))</b><small>\(e(label))</small></div>"
    }

    private static func stamp(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    private static let css = """
    :root{--bg:#F5F4FB;--text:#16151F;--muted:#5F5C73;--faint:#8E8BA3;--glass:rgba(255,255,255,.58);--border:rgba(255,255,255,.8);
      --card:rgba(255,255,255,.66);--line:rgba(40,30,90,.08);--shadow:0 1px 0 rgba(255,255,255,.8) inset,0 18px 50px -20px rgba(45,35,130,.28)}
    @media (prefers-color-scheme:dark){:root{--bg:#0B0A12;--text:#F2F1F8;--muted:#A6A3BC;--faint:#75728C;--glass:rgba(34,32,52,.55);
      --border:rgba(255,255,255,.1);--card:rgba(30,28,46,.62);--line:rgba(255,255,255,.07);--shadow:0 1px 0 rgba(255,255,255,.06) inset,0 20px 60px -20px rgba(0,0,0,.7)}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
    a{color:inherit;text-decoration:none}
    .mono{font-family:ui-monospace,"SF Mono",Menlo,monospace}.faint{color:var(--faint)}
    .backdrop{position:fixed;inset:0;z-index:-1;overflow:hidden}
    .backdrop i{position:absolute;border-radius:50%;filter:blur(90px)}
    .b1{width:55vw;height:55vw;left:-15vw;top:-20vw;background:rgba(75,63,209,.3)}
    .b2{width:50vw;height:50vw;right:-18vw;top:15vh;background:rgba(43,181,168,.24)}
    .b3{width:45vw;height:45vw;left:25vw;bottom:-25vw;background:rgba(201,184,255,.4)}
    main{width:min(900px,100% - 32px);margin:32px auto 48px;display:grid;gap:16px}
    .glass{background:var(--glass);backdrop-filter:blur(26px) saturate(180%);-webkit-backdrop-filter:blur(26px) saturate(180%);border:1px solid var(--border);box-shadow:var(--shadow)}
    .card{border-radius:22px;padding:20px 22px}
    .hero{display:flex;gap:20px;align-items:flex-start;border-radius:28px;padding:24px}
    .hero-text{flex:1;min-width:0}
    h1{font-size:26px;line-height:1.2;margin:10px 0 8px;letter-spacing:-.02em}
    h2{font-size:16px;margin:0 0 12px;display:flex;gap:8px;align-items:center}
    h3.group{font-size:13px;font-family:ui-monospace,Menlo,monospace;color:var(--muted);margin:16px 0 6px}
    .summary{color:var(--muted);margin:0}
    .chips{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
    .key{font:700 14px ui-monospace,Menlo,monospace}
    .chip{padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600;background:var(--card);border:1px solid var(--border)}
    .chip.qa{color:#1E9C90;background:rgba(43,181,168,.15);border-color:transparent}
    .chip.dev{color:#4B3FD1;background:rgba(75,63,209,.14);border-color:transparent}
    .chip.blue{color:#2F6BD8;background:rgba(47,107,216,.12);border-color:transparent}
    .chip.warn{color:#C0721F;background:rgba(242,154,56,.16);border-color:transparent}
    .chip.fail{color:#D33F49;background:rgba(229,72,77,.14);border-color:transparent}
    .chip.blocked{color:#C0721F;background:rgba(242,154,56,.16);border-color:transparent}
    .failnote{margin:8px 0 0 26px;padding:7px 11px;border-radius:10px;font-size:14px}
    .failnote.fail{background:rgba(229,72,77,.1)}
    .failnote.blocked{background:rgba(242,154,56,.12)}
    .chip.purple{color:#7B4FD0;background:rgba(123,79,208,.14);border-color:transparent}
    .rings{display:flex;gap:14px}
    .ring{width:78px;height:78px;border-radius:50%;display:grid;place-content:center;text-align:center;position:relative;
      background:radial-gradient(closest-side,var(--bg) 78%,transparent 80% 100%),conic-gradient(var(--c) calc(var(--p)*1%),rgba(128,128,160,.22) 0)}
    .ring b{font-size:15px}.ring small{font-size:10px;color:var(--faint)}
    ul{margin:0;padding-left:20px}li{margin:3px 0}
    .ac{display:flex;gap:10px;align-items:baseline;padding:5px 0;cursor:pointer}
    .ac .id{font-weight:700;color:var(--faint);font-size:12px}.ac .t{flex:1}
    .ac:has(input:checked) .t{text-decoration:line-through;color:var(--faint)}
    input[type=checkbox]{accent-color:#30C26B;width:16px;height:16px;flex:none;transform:translateY(2px);cursor:pointer}
    .task{background:var(--card);border-radius:14px;padding:10px 14px;margin-top:8px;border:1px solid var(--line)}
    .task summary{list-style:none;display:flex;gap:10px;align-items:center;cursor:pointer}
    .task summary::-webkit-details-marker{display:none}
    .task .ttl{font-weight:600;flex:1}
    .task:has(summary input:checked) .ttl{text-decoration:line-through;color:var(--faint)}
    .task ol{margin:8px 0 0 26px;padding-left:18px;color:var(--muted)}
    .expected{margin:8px 0 0 26px;padding:7px 11px;border-radius:10px;background:rgba(48,194,107,.1);font-size:14px}
    .expected.purple{background:rgba(123,79,208,.1)}
    .role{margin:8px 0 0 26px;color:var(--muted);font-size:14px}
    .note{margin:8px 0 0 26px;padding:7px 11px;border-radius:10px;background:rgba(242,201,76,.12);font-size:14px}
    .evrow{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 0 26px}
    .ev{max-height:120px;border-radius:10px;border:1px solid var(--line)}
    .covers{margin:6px 0 0 26px;font-size:12px;color:var(--faint)}
    .dot{width:8px;height:8px;border-radius:50%;flex:none}.dot.high{background:#E5484D}.dot.medium{background:#F29A38}.dot.low{background:#9A98AE}
    .sources{display:flex;flex-wrap:wrap;gap:8px}
    .src{padding:6px 12px;border-radius:999px;font-size:13px;display:inline-block}
    footer{text-align:center;color:var(--faint);font-size:12px;margin-top:8px}
    footer a{text-decoration:underline}
    @media (max-width:640px){.hero{flex-direction:column}.rings{align-self:flex-start}}
    @media print{body{background:#fff}.backdrop{display:none}.glass{background:#fff;box-shadow:none;border:1px solid #ddd;backdrop-filter:none}
      .task{break-inside:avoid}main{margin:0 auto}}
    """

    /// Remembers browser ticks per plan and keeps the rings in sync.
    private static func script(storageKey: String) -> String {
        """
        (function(){
          var key = \(jsonString(storageKey));
          var boxes = Array.prototype.slice.call(document.querySelectorAll('input[type=checkbox]'));
          try { var saved = JSON.parse(localStorage.getItem(key) || 'null'); if (saved && saved.length === boxes.length) boxes.forEach(function(b,i){ b.checked = saved[i]; }); } catch (e) {}
          function ring(id, kind){ var el = document.getElementById(id); if (!el) return;
            var all = boxes.filter(function(b){ return b.dataset.kind === kind; }), on = all.filter(function(b){ return b.checked; }).length;
            el.style.setProperty('--p', all.length ? Math.round(on / all.length * 100) : 0); el.querySelector('b').textContent = on + '/' + all.length; }
          function update(){ ring('ring-tasks','task'); ring('ring-ac','ac');
            try { localStorage.setItem(key, JSON.stringify(boxes.map(function(b){ return b.checked; }))); } catch (e) {} }
          boxes.forEach(function(b){ b.addEventListener('click', function(ev){ ev.stopPropagation(); }); b.addEventListener('change', update); });
          update();
        })();
        """
    }

    private static func jsonString(_ s: String) -> String {
        (try? String(decoding: JSONEncoder().encode(s), as: UTF8.self)) ?? "\"checkpoint\""
    }
}
