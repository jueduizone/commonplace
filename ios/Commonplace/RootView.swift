import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: ResearchStore
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { AskView() }.tabItem { Label("Ask", systemImage: "text.bubble") }.tag(0)
            NavigationStack { LibraryView(onAsk: { id, title in store.newTopic(packID: id, title: title); tab = 0 }) }
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(1)
            NavigationStack { HistoryView(onOpen: { store.open($0); tab = 0 }) }
                .tabItem { Label("History", systemImage: "clock") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(3)
        }
    }
}

struct AskView: View {
    @EnvironmentObject private var store: ResearchStore
    @State private var source: SourceRecord?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.conversation.turns.isEmpty { introduction }
                    if let scope = store.conversation.scopeTitle {
                        HStack {
                            Label(scope, systemImage: "doc.text")
                            Spacer()
                            Button("Clear") { store.newTopic() }.disabled(store.busy)
                        }.font(.subheadline).padding().background(PaperTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(Array(store.conversation.turns.enumerated()), id: \.element.id) { index, turn in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(turn.question).font(PaperTheme.title).textSelection(.enabled)
                            if index == store.conversation.turns.count - 1, let card = store.card, let best = card.top {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("From your library").font(.headline)
                                    Text(card.highlight.isEmpty ? card.topText : card.highlight).font(PaperTheme.reading()).lineSpacing(5).lineLimit(8)
                                    Button { source = SourceRecord(best) } label: { Label(best.title, systemImage: "book.closed") }.frame(minHeight: 44)
                                    ForEach(Array(card.facts.enumerated()), id: \.offset) { _, fact in
                                        Text("\(fact.entity) · \(fact.label): \(fact.value)").font(.subheadline)
                                    }
                                    ForEach(card.computed, id: \.self) { Text($0).font(.body).monospacedDigit() }
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(PaperTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                            }
                            if !turn.thinking.isEmpty { DisclosureGroup("Reasoning") { Text(turn.thinking).font(.body).foregroundStyle(PaperTheme.secondary).textSelection(.enabled) } }
                            if !turn.answer.isEmpty {
                                Text(answer(turn)).font(PaperTheme.reading()).lineSpacing(7).textSelection(.enabled)
                                    .environment(\.openURL, OpenURLAction { url in
                                        guard url.scheme == "commonplace-source", let n = UInt32(url.host ?? ""), let item = turn.sources.first(where: { $0.number == n }) else { return .discarded }
                                        source = item; return .handled
                                    })
                            }
                            if turn.segments.contains(where: { $0.kind == .unverified }) {
                                Label("Underlined text is unverified against these sources.", systemImage: "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(PaperTheme.unverified)
                            }
                            if turn.stopped { Text("Stopped").font(.caption).foregroundStyle(PaperTheme.secondary) }
                            if let error = turn.error { Text(error).foregroundStyle(.red).font(.callout) }
                            if !turn.sources.isEmpty {
                                DisclosureGroup("Sources · \(turn.sources.count)") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(turn.sources) { item in
                                            Button { source = item } label: {
                                                HStack(alignment: .firstTextBaseline) { Text("[\(item.number)]").monospacedDigit(); Text(item.title); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                                    .frame(minHeight: 44)
                                            }.buttonStyle(.plain).foregroundStyle(PaperTheme.rubric)
                                        }
                                    }
                                }
                            }
                            if !store.busy {
                                HStack {
                                    ShareLink(item: shareText(turn)) { Label("Share", systemImage: "square.and.arrow.up") }
                                    Spacer()
                                    Button("Check again") { store.ask("Are you sure?") }
                                }.font(.subheadline).frame(minHeight: 44)
                            }
                        }
                        Divider().overlay(PaperTheme.rule)
                    }
                    if store.busy { HStack { ProgressView(); Text(store.status).font(.callout).foregroundStyle(PaperTheme.secondary) }.accessibilityElement(children: .combine) }
                    Color.clear.frame(height: 1).id("latest")
                }.padding(20).frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .background(PaperTheme.paper)
            .onChange(of: store.conversation.turns.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .foregroundStyle(PaperTheme.ink)
        .navigationTitle("Commonplace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.newTopic() } label: { Label("New topic", systemImage: "square.and.pencil") }.disabled(store.busy) } }
        .sheet(item: $source) { SourceView(source: $0).environmentObject(store) }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(PaperTheme.rubric).accessibilityHidden(true)
            Text("A little library.\nA better question.").font(PaperTheme.title)
            Text("Ask about the books and reference works on your phone. Open a citation to read the evidence yourself.")
                .font(PaperTheme.reading()).lineSpacing(5).foregroundStyle(PaperTheme.secondary)
            if store.library?.packs.isEmpty != false {
                Text("Start in Library: import a downloaded pack or add a PDF, text or Markdown document.").font(.callout)
            } else {
                ForEach(["Why is the sky blue?", "How do tides work?"], id: \.self) { question in
                    Button { store.ask(question) } label: { HStack { Text(question); Spacer(); Image(systemName: "arrow.up.left") }.frame(minHeight: 44) }.disabled(!store.ready || store.busy)
                    Divider()
                }
            }
        }.padding(.vertical, 22)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask your library", text: $store.input, axis: .vertical)
                    .lineLimit(1...5).focused($focused).submitLabel(.send).onSubmit { focused = false; store.ask() }
                    .accessibilityIdentifier("ask-input")
                if store.busy && !store.cancellable {
                    ProgressView().frame(minWidth: 44, minHeight: 44)
                } else if store.busy {
                    Button { store.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                        .accessibilityLabel("Stop answer").frame(minWidth: 44, minHeight: 44)
                } else {
                    Button { focused = false; store.ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(!store.ready || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Ask question").accessibilityIdentifier("ask-send").frame(minWidth: 44, minHeight: 44)
                }
            }
            Toggle("Think it through", isOn: $store.thinking).font(.caption).disabled(store.busy)
            if !store.busy { Text(store.status).font(.caption).foregroundStyle(PaperTheme.secondary).lineLimit(2) }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
    }

    private func answer(_ turn: TurnRecordData) -> AttributedString {
        if turn.segments.isEmpty { return AttributedString(turn.answer) }
        var result = AttributedString()
        for part in turn.segments {
            var text = AttributedString(part.text)
            if part.kind == .citation, let n = part.number {
                text.link = URL(string: "commonplace-source://\(n)"); text.foregroundColor = PaperTheme.rubric
            } else if part.kind == .unverified { text.underlineStyle = .single; text.foregroundColor = PaperTheme.unverified }
            result.append(text)
        }
        return result
    }

    private func shareText(_ turn: TurnRecordData) -> String {
        ([turn.question, "", turn.answer, ""] + turn.sources.map { "[\($0.number)] \($0.title) · \($0.license)\n\($0.sourceURL)" }).joined(separator: "\n")
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: ResearchStore
    let onOpen: (ConversationRecord) -> Void
    var body: some View {
        List {
            if store.history.isEmpty { ContentUnavailableView("Your research starts here", systemImage: "clock", description: Text("Questions and their sources are saved on this device.")) }
            ForEach(store.history) { conversation in
                Button { onOpen(conversation) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(conversation.title).font(.headline).foregroundStyle(PaperTheme.ink).lineLimit(3)
                        Text(conversation.updated, style: .date).font(.caption).foregroundStyle(PaperTheme.secondary)
                    }.padding(.vertical, 5)
                }.disabled(store.busy)
            }.onDelete { indices in for index in indices { store.delete(store.history[index].id) } }
        }.disabled(store.busy).scrollContentBackground(.hidden).background(PaperTheme.paper).navigationTitle("History")
    }
}

struct OfflineWelcome: View {
    let proceed: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(PaperTheme.rubric).accessibilityHidden(true)
                    Text("Your library,\nwherever you are.").font(PaperTheme.title)
                    Text("Commonplace reads local reference works and writes answers on your iPhone. The app has no network code, analytics or crash-reporting SDKs.").font(PaperTheme.reading()).lineSpacing(5)
                    Text("What offline means on iOS").font(.headline)
                    Text("Unlike Android, iOS does not let an app deny itself all network access. This app requests no network entitlements. App Privacy Report lets you inspect reported activity; it is not a network blocker.")
                    Text("For a hard offline check, turn on Airplane Mode and also turn Wi-Fi off. Then ask a question and open its sources.")
                    Text("Get started").font(.headline)
                    Text("Download packs with your browser, then import them from Files. Begin with MiniCPM5-2B or a Gemma E2B GGUF pack. The Tensor G5 .litertlm pack is for Pixel phones.")
                    Text("Keep your sources").font(.headline)
                    Text("Answers can be wrong. Citations open the evidence; underlined text is unverified. Your history stays on this device and is excluded from iCloud backup.")
                    Button("Open my library", action: proceed).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(PaperTheme.paper).foregroundStyle(PaperTheme.ink).interactiveDismissDisabled()
        }.tint(PaperTheme.rubric)
    }
}
