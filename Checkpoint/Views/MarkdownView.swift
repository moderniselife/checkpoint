import SwiftUI

/// Block-level markdown renderer for Jira content (headings, lists, task lists,
/// tables, code, quotes). Inline styling and links use AttributedString.
struct MarkdownView: View {
    let markdown: String
    var font: Font = .callout

    private enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, indent: Int)
        case numbered(String, String)
        case task(Bool, String)
        case quote(String)
        case code(String)
        case table([[String]])
        case image
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .paragraph(let text):
            Text(inline(text)).font(font).fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.tertiary)
                Text(inline(text)).font(font).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).font(font.monospacedDigit()).foregroundStyle(.secondary)
                Text(inline(text)).font(font).fixedSize(horizontal: false, vertical: true)
            }
        case .task(let done, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                Text(inline(text)).font(font).fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let text):
            Text(inline(text))
                .font(font)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tint.opacity(0.5)).frame(width: 3) }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.caption.monospaced()).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(inline(cell))
                                    .font(i == 0 ? .caption.weight(.semibold) : .caption)
                            }
                        }
                        if i == 0 { Divider() }
                    }
                }
                .padding(10)
            }
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        case .image:
            Label("Inline image — see Attachments", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: .capsule)
        case .rule:
            Divider()
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    private static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var table: [[String]] = []
        var code: [String]? = nil

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)); table = [] }
        }

        for rawLine in md.components(separatedBy: "\n") {
            if code != nil {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(code!.joined(separator: "\n"))); code = nil
                } else { code!.append(rawLine) }
                continue
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = (rawLine.prefix { $0 == " " }.count) / 2

            if line.hasPrefix("```") { flushParagraph(); flushTable(); code = []; continue }
            if line.hasPrefix("|") {
                flushParagraph()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(cells) }
                continue
            }
            flushTable()

            if line.isEmpty { flushParagraph(); continue }
            if line.hasPrefix("![") { flushParagraph(); blocks.append(.image); continue }
            if line == "---" || line == "***" { flushParagraph(); blocks.append(.rule); continue }
            if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flushParagraph(); blocks.append(.heading(m.1.count, String(m.2))); continue
            }
            if let m = line.firstMatch(of: /^[-*]\s+\[([ xX])\]\s+(.*)$/) {
                flushParagraph(); blocks.append(.task(m.1 != " ", String(m.2))); continue
            }
            if let m = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flushParagraph(); blocks.append(.bullet(String(m.1), indent: indent)); continue
            }
            if let m = line.firstMatch(of: /^(\d+[.)])\s+(.*)$/) {
                flushParagraph(); blocks.append(.numbered(String(m.1), String(m.2))); continue
            }
            if line.hasPrefix(">") {
                flushParagraph(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue
            }
            paragraph.append(line)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flushParagraph()
        flushTable()
        return blocks
    }
}
