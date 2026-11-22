import SwiftUI

struct SourceView: View {
    @EnvironmentObject private var store: ResearchStore
    @Environment(\.dismiss) private var dismiss
    let source: SourceRecord
    @State private var passage: PassageView?
    @State private var article: ArticleView?
    @State private var failure: String?
    @State private var loadingArticle = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text(source.title).font(PaperTheme.title)
                    if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(PaperTheme.unverified) }
                    if let article {
                        ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            if !paragraph.section.isEmpty { Text(paragraph.section).font(.headline) }
                            Text(paragraph.text).font(PaperTheme.reading()).lineSpacing(7).textSelection(.enabled)
                        }
                    } else {
                        if !source.section.isEmpty { Text(source.section).font(.subheadline).foregroundStyle(PaperTheme.secondary) }
                        Text(passage?.text ?? source.snippet).font(PaperTheme.reading()).lineSpacing(7).textSelection(.enabled)
                        Button("Read the full article") {
                            loadingArticle = true
                            Task {
                                defer { loadingArticle = false }
                                do { article = try await store.worker.article(source) } catch { failure = error.localizedDescription }
                            }
                        }.disabled(loadingArticle || store.busy).frame(minHeight: 44)
                        if loadingArticle { ProgressView() }
                    }
                    Divider()
                    Text("Credit & license").font(.headline)
                    Text(passage?.attribution ?? "").font(.caption).textSelection(.enabled)
                    Text(passage?.license ?? source.license).font(.caption)
                    if !source.sourceURL.isEmpty { Text(source.sourceURL).font(.caption).foregroundStyle(PaperTheme.secondary).textSelection(.enabled) }
                }.padding(22).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity)
            }.background(PaperTheme.paper).foregroundStyle(PaperTheme.ink)
                .navigationTitle(source.number == 0 ? "Source" : "Source [\(source.number)]").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { do { passage = try await store.worker.passage(source) } catch { failure = "The installed source could not be opened. The saved excerpt is shown below. \(error.localizedDescription)" } }
        }
    }
}
