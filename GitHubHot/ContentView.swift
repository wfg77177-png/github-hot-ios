import SwiftUI
import WebKit

// MARK: - Models

struct RepoOwner: Decodable {
    let login: String
    let avatarUrl: String
    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

struct Repo: Identifiable, Decodable {
    let id: Int
    let fullName: String
    let name: String
    let owner: RepoOwner
    let description: String?
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let htmlUrl: String
    let createdAt: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, name, owner, description, language
        case fullName = "full_name"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SearchResponse: Decodable {
    let totalCount: Int
    let items: [Repo]
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今日"
    case week = "本周"
    case month = "本月"
    case all = "总榜"
    var id: String { rawValue }
}

let languages = ["全部", "Swift", "Python", "JavaScript", "TypeScript", "Go", "Rust", "Java", "C++", "Kotlin", "Dart", "Ruby", "C", "Shell", "Vue", "HTML"]

func languageColor(_ lang: String?) -> Color {
    guard let lang = lang else { return .gray }
    switch lang {
    case "Swift": return Color(red: 0.95, green: 0.45, blue: 0.2)
    case "Python": return Color(red: 0.2, green: 0.45, blue: 0.7)
    case "JavaScript": return Color(red: 0.95, green: 0.85, blue: 0.2)
    case "TypeScript": return Color(red: 0.2, green: 0.5, blue: 0.85)
    case "Go": return Color(red: 0.0, green: 0.65, blue: 0.75)
    case "Rust": return Color(red: 0.85, green: 0.4, blue: 0.15)
    case "Java": return Color(red: 0.75, green: 0.3, blue: 0.15)
    case "C++": return Color(red: 0.95, green: 0.4, blue: 0.55)
    case "Kotlin": return Color(red: 0.55, green: 0.35, blue: 0.8)
    case "Dart": return Color(red: 0.1, green: 0.6, blue: 0.75)
    case "Ruby": return Color(red: 0.85, green: 0.15, blue: 0.2)
    case "C": return Color(red: 0.35, green: 0.35, blue: 0.55)
    case "Shell": return Color(red: 0.5, green: 0.75, blue: 0.3)
    case "Vue": return Color(red: 0.25, green: 0.75, blue: 0.5)
    case "HTML": return Color(red: 0.9, green: 0.35, blue: 0.2)
    default: return .gray
    }
}

func dateString(daysAgo: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

func formatCount(_ n: Int) -> String {
    if n >= 1000 {
        let v = Double(n) / 1000.0
        return String(format: "%.1fk", v)
    }
    return "\(n)"
}

// MARK: - WebView

struct RepoWebView: UIViewRepresentable {
    let url: String
    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        if let u = URL(string: url) {
            wv.load(URLRequest(url: u))
        }
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct RepoDetailView: View {
    let repo: Repo
    var body: some View {
        RepoWebView(url: repo.htmlUrl)
            .navigationTitle(repo.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let url = URL(string: repo.htmlUrl) {
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
    }
}

// MARK: - Main View

struct ContentView: View {
    @State private var range: TimeRange = .today
    @State private var language: String = "全部"
    @State private var repos: [Repo] = []
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var searchText = ""
    @State private var searchResults: [Repo] = []
    @State private var isSearching = false
    @State private var lastUpdated: String = ""
    @State private var translations: [Int: String] = [:]
    @State private var autoTranslate = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("时间", selection: $range) {
                    ForEach(TimeRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: range) { _ in Task { await load() } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(languages, id: \.self) { lang in
                            Button(action: {
                                language = lang
                                Task { await load() }
                            }) {
                                Text(lang)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(language == lang ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(language == lang ? .white : .primary)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                if isLoading && repos.isEmpty {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                } else if let err = errorText, repos.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("重新加载") { Task { await load() } }
                    }
                    Spacer()
                } else {
                    List {
                        if !lastUpdated.isEmpty {
                            Text(lastUpdated)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(Array(repos.enumerated()), id: \.element.id) { idx, repo in
                            NavigationLink(destination: RepoDetailView(repo: repo)) {
                                RepoRow(rank: idx + 1, repo: repo, translated: translations[repo.id])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("GitHub 热榜")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        autoTranslate.toggle()
                        if autoTranslate {
                            Task { await translateAll() }
                        }
                    }) {
                        Image(systemName: autoTranslate ? "character.bubble.fill" : "character.bubble")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索仓库、作者…")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: searchText) { newValue in
                if newValue.isEmpty {
                    searchResults = []
                    isSearching = false
                }
            }
            .task { await load() }
            .overlay {
                if isSearching {
                    SearchResultsView(results: searchResults, isLoading: isLoading, translations: translations)
                }
            }
        }
    }

    func buildQuery() -> String {
        var q = ""
        switch range {
        case .today: q = "created:>" + dateString(daysAgo: 1)
        case .week: q = "created:>" + dateString(daysAgo: 7)
        case .month: q = "created:>" + dateString(daysAgo: 30)
        case .all: q = "stars:>5000"
        }
        if language != "全部" {
            q += "+language:" + language
        }
        return q
    }

    func load() async {
        isLoading = true
        errorText = nil
        var comps = URLComponents(string: "https://api.github.com/search/repositories")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: buildQuery()),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "30"),
        ]
        guard let url = comps?.url else {
            isLoading = false
            errorText = "地址构造失败"
            return
        }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 403 {
                errorText = "GitHub 限流了，稍后再试（每小时 10 次搜索）"
                isLoading = false
                return
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            repos = decoded.items
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            lastUpdated = "更新于 " + f.string(from: Date()) + " · 共 " + formatCount(decoded.totalCount) + " 个结果"
        } catch {
            errorText = "加载失败：" + error.localizedDescription
        }
        isLoading = false
        if autoTranslate && errorText == nil {
            await translateAll()
        }
    }

    func translateOne(_ text: String, for repoId: Int) async {
        guard !text.isEmpty else { return }
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|zh-CN"),
            URLQueryItem(name: "de", value: "6173396@gmail.com"),
        ]
        guard let url = comps?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["responseData"] as? [String: Any],
               let translated = responseData["translatedText"] as? String,
               !translated.isEmpty, translated != text {
                await MainActor.run {
                    translations[repoId] = translated
                }
            }
        } catch {
        }
    }

    func translateAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repo in repos {
                if let desc = repo.description, !desc.isEmpty, translations[repo.id] == nil {
                    group.addTask {
                        await translateOne(desc, for: repo.id)
                    }
                }
            }
        }
    }

    func search() async {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearching = true
        isLoading = true
        var comps = URLComponents(string: "https://api.github.com/search/repositories")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "30"),
        ]
        guard let url = comps?.url else {
            isLoading = false
            return
        }
        do {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            searchResults = decoded.items
        } catch {
            searchResults = []
        }
        isLoading = false
        if autoTranslate {
            await withTaskGroup(of: Void.self) { group in
                for repo in searchResults {
                    if let desc = repo.description, !desc.isEmpty, translations[repo.id] == nil {
                        group.addTask {
                            await translateOne(desc, for: repo.id)
                        }
                    }
                }
            }
        }
    }
}

struct RepoRow: View {
    let rank: Int
    let repo: Repo
    let translated: String?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if rank > 0 {
                Text("\(rank)")
                    .font(.headline)
                    .foregroundColor(rank <= 3 ? .orange : .secondary)
                    .frame(width: 28, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.fullName)
                    .font(.headline)
                    .lineLimit(1)
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if let zh = translated, !zh.isEmpty {
                    Text(zh)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                HStack(spacing: 12) {
                    Label(formatCount(repo.stargazersCount), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label(formatCount(repo.forksCount), systemImage: "tuningfork")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let lang = repo.language {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(languageColor(lang))
                                .frame(width: 10, height: 10)
                            Text(lang)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchResultsView: View {
    let results: [Repo]
    let isLoading: Bool
    let translations: [Int: String]
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("搜索中…")
                    .padding(.top, 40)
            } else if results.isEmpty {
                Text("没有找到相关仓库")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                List(results) { repo in
                    NavigationLink(destination: RepoDetailView(repo: repo)) {
                        RepoRow(rank: 0, repo: repo, translated: translations[repo.id])
                    }
                }
                .listStyle(.plain)
            }
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}
