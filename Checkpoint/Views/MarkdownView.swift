import SwiftUI
import AppKit

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
        case image(alt: String, url: String)
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
            ScrollView(.horizontal) {
                Text(text).font(.caption.monospaced()).padding(10)
            }
            .scrollIndicators(.never)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        case .table(let rows):
            ScrollView(.horizontal) {
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
            .scrollIndicators(.never)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        case .image(let alt, let url):
            InlineImage(alt: alt, url: url)
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
            if let m = line.firstMatch(of: /^!\[([^\]]*)\]\(([^)\s]+)[^)]*\)$/) {
                flushParagraph(); blocks.append(.image(alt: String(m.1), url: String(m.2))); continue
            }
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

extension EnvironmentValues {
    /// Attachments of the ticket being rendered, so `attachment:ID` images can load.
    @Entry var ticketAttachments: [String: TicketDetail.Attachment] = [:]
}

/// Image inside a description/comment: a Jira attachment (`attachment:ID`,
/// loaded with Jira auth) or a plain external URL.
private struct InlineImage: View {
    let alt: String
    let url: String
    @Environment(\.ticketAttachments) private var attachments
    @Environment(AppSettings.self) private var settings
    @State private var image: NSImage?
    @State private var failed = false
    @State private var zoomed = false

    private var attachment: TicketDetail.Attachment? {
        url.hasPrefix("attachment:") ? attachments[String(url.dropFirst("attachment:".count))] : nil
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(image.size.width, 560), alignment: .leading)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.5)))
                    .onTapGesture { zoomed = true }
                    .help("\(alt) — click to enlarge")
            } else if url.hasPrefix("http"), !isLinearUpload {
                AsyncImage(url: URL(string: url)) { $0.resizable().scaledToFit() } placeholder: { placeholder }
                    .frame(maxWidth: 560, alignment: .leading)
            } else {
                placeholder
            }
        }
        .task(id: url) { await load() }
        .sheet(isPresented: $zoomed) {
            if let image { ZoomedImage(image: image, title: alt) }
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            if failed || attachment == nil && !url.hasPrefix("http") {
                Image(systemName: "photo.badge.exclamationmark")
            } else {
                ProgressView().controlSize(.small)
            }
            Text(alt).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .help(failed ? "Couldn't load — add an Atlassian API token in Settings for image access." : alt)
    }

    private var isLinearUpload: Bool { URL(string: url)?.host()?.hasSuffix("uploads.linear.app") == true }

    private func load() async {
        if isLinearUpload {
            // Linear's uploads are private; they take the API key or OAuth bearer.
            guard let target = URL(string: url), let auth = await settings.linearUploadAuth() else { failed = true; return }
            var req = URLRequest(url: target)
            req.setValue(auth, forHTTPHeaderField: "Authorization")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200, let img = NSImage(data: data) {
                image = img
            } else {
                failed = true
            }
            return
        }
        guard let attachment else { return }
        // Prefer the full image; inline images are usually screenshots worth reading.
        if let data = await AttachmentLoader.shared.data(for: attachment, full: true, creds: settings.attachmentCredentials),
           let img = NSImage(data: data) {
            image = img
        } else {
            failed = true
        }
    }
}

struct ZoomedImage: View {
    let image: NSImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: max(image.size.width, 400))
            }
        }
        .frame(minWidth: 640, idealWidth: min(image.size.width + 40, 1400), minHeight: 480, idealHeight: min(image.size.height + 80, 1000))
    }
}
