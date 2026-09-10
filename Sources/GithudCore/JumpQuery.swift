import Foundation

/// The pure meaning of text typed during a keyboard-summoned island session.
/// It parses the text, narrows the three admitted row arrays, and names the
/// github.com destination used when the island does not hold the target.
public struct JumpQuery: Equatable, Sendable {
    public enum Handle: Equatable, Sendable {
        case number(Int)
        case repo(String)
        case repoNumber(repo: String, number: Int)
        case branch(String)
        case link(String)
        case text(String)
    }

    public struct Narrowed: Equatable, Sendable {
        /// Search renders these arrays directly; browse visibility preferences
        /// never remove a match. Each array keeps its captured source order.
        public let radar: [RadarRow]
        public let inbound: [InboundRow]
        public let pulse: [PulseRow]
        public let matched: Int
        /// Captured source rows before browse gates, not a pill/gauge count.
        public let admitted: Int
    }

    public var text: String

    public init(_ text: String = "") {
        self.text = text
    }

    public var isEmpty: Bool { trimmedText.isEmpty }

    /// Context-free parsing. Use `handle(knownRepos:)` when the island's repo
    /// names are available so a bare repo name such as "githud" can resolve.
    public var handle: Handle { handle(knownRepos: []) }

    public func handle(knownRepos: [String]) -> Handle {
        let query = trimmedText
        guard !query.isEmpty else { return .text("") }

        if let link = Self.githubLink(query) {
            return .link(link)
        }

        if let match = Self.firstMatch(
            in: query,
            pattern: #"^([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)(?:\s*#|\s+)(\d+)$"#),
           let number = Int(match[2]) {
            return .repoNumber(repo: match[1].trimmingCharacters(in: .whitespaces),
                               number: number)
        }

        let numberText = query.hasPrefix("#") ? String(query.dropFirst()) : query
        if !numberText.isEmpty,
           numberText.allSatisfy(\.isNumber),
           let number = Int(numberText) {
            return .number(number)
        }

        if let repo = Self.resolveRepo(query, knownRepos: knownRepos) {
            return .repo(repo)
        }

        if query.contains("/") || query.range(of: #"^[a-z]+-\d+"#,
                                               options: [.regularExpression, .caseInsensitive]) != nil {
            return .branch(query)
        }

        return .text(query)
    }

    /// Narrows the admitted arrays without changing their order. Empty or
    /// whitespace-only input is the identity operation.
    public func narrow(radar: [RadarRow], inbound: [InboundRow], pulse: [PulseRow]) -> Narrowed {
        let admitted = radar.count + inbound.count + pulse.count
        guard !isEmpty else {
            return Narrowed(radar: radar, inbound: inbound, pulse: pulse,
                            matched: admitted, admitted: admitted)
        }

        let knownRepos = Self.knownRepos(radar: radar, inbound: inbound, pulse: pulse)
        let parsed = handle(knownRepos: knownRepos)
        let narrowedRadar = radar.filter { matches($0, handle: parsed) }
        let narrowedInbound = inbound.filter { matches($0, handle: parsed) }
        let narrowedPulse = pulse.filter { matches($0, handle: parsed) }
        return Narrowed(radar: narrowedRadar, inbound: narrowedInbound, pulse: narrowedPulse,
                        matched: narrowedRadar.count + narrowedInbound.count + narrowedPulse.count,
                        admitted: admitted)
    }

    public func destination(selfLogin: String?, knownRepos: [String]) -> String {
        switch handle(knownRepos: knownRepos) {
        case .number(let number):
            var terms = [String(number), "is:pr"]
            if selfLogin?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                terms.append("author:@me")
            }
            return Self.searchURL(terms.joined(separator: " "))

        case .repo(let repo):
            return Self.githubPath(repo)

        case .repoNumber(let rawRepo, let number):
            if let repo = Self.resolveRepo(rawRepo, knownRepos: knownRepos) ??
                (rawRepo.contains("/") ? rawRepo : nil) {
                return Self.githubPath("\(repo)/pull/\(number)")
            }
            return Self.searchURL("\(number) is:pr repo:\(rawRepo)")

        case .branch(let branch):
            return Self.searchURL("is:pr head:\(branch)")

        case .link(let link):
            return link

        case .text(let query):
            return query.isEmpty ? "https://github.com" : Self.searchURL(query)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ row: RadarRow, handle: Handle) -> Bool {
        matches(repo: row.repo, title: row.title, subtitle: row.subtitle,
                url: row.url, headBranch: nil, handle: handle)
    }

    private func matches(_ row: InboundRow, handle: Handle) -> Bool {
        matches(repo: row.repo, title: row.title, subtitle: row.subtitle,
                url: row.url, headBranch: nil, handle: handle)
    }

    private func matches(_ row: PulseRow, handle: Handle) -> Bool {
        matches(repo: row.repo, title: row.title, subtitle: row.subtitle,
                url: row.url, headBranch: row.headBranch, handle: handle)
    }

    private func matches(repo: String, title: String, subtitle: String, url: String?,
                         headBranch: String?, handle: Handle) -> Bool {
        let displayedLine = [title, repo, subtitle].joined(separator: " ")
        switch handle {
        case .number(let number):
            return Self.containsNumber(number, in: repo) ||
                Self.contains(String(number), in: displayedLine)

        case .repo(let expected):
            return Self.repositoryName(from: repo)
                .localizedCaseInsensitiveCompare(expected) == .orderedSame

        case .repoNumber(let expected, let number):
            let actual = Self.repositoryName(from: repo)
            let repoMatches = actual.localizedCaseInsensitiveCompare(expected) == .orderedSame ||
                actual.lowercased().hasSuffix("/\(expected.lowercased())")
            return repoMatches && Self.containsNumber(number, in: repo)

        case .branch(let branch):
            if let headBranch, Self.contains(branch, in: headBranch) { return true }
            // Only Your PRs carry a branch field. Other lanes can still match the
            // same typed text when it is visibly present in their displayed line.
            return Self.contains(branch, in: displayedLine)

        case .link(let link):
            return url.map(Self.normalizedLink) == Self.normalizedLink(link)

        case .text(let query):
            return Self.contains(query, in: displayedLine)
        }
    }

    private static func contains(_ needle: String, in haystack: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func containsNumber(_ number: Int, in string: String) -> Bool {
        string.range(of: "#\(number)(?![0-9])", options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func knownRepos(radar: [RadarRow], inbound: [InboundRow],
                                  pulse: [PulseRow]) -> [String] {
        var seen = Set<String>()
        return (radar.map(\.repo) + inbound.map(\.repo) + pulse.map(\.repo)).compactMap {
            let repo = repositoryName(from: $0)
            return seen.insert(repo.lowercased()).inserted ? repo : nil
        }
    }

    private static func repositoryName(from displayRepo: String) -> String {
        displayRepo.replacingOccurrences(of: #"\s+#\d+\s*$"#, with: "",
                                         options: .regularExpression)
    }

    private static func resolveRepo(_ input: String, knownRepos: [String]) -> String? {
        let candidate = repositoryName(from: input).trimmingCharacters(in: .whitespaces)
        let repos = knownRepos.map(repositoryName(from:))
        if let exact = repos.first(where: {
            $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }) {
            return exact
        }
        guard !candidate.contains("/") else { return nil }
        let suffixMatches = repos.filter { $0.lowercased().hasSuffix("/\(candidate.lowercased())") }
        return suffixMatches.count == 1 ? suffixMatches[0] : nil
    }

    private static func firstMatch(in string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: string,
                                            range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }
        return (0..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: string) else { return nil }
            return String(string[range])
        }
    }

    private static func githubLink(_ input: String) -> String? {
        let candidate: String
        if input.lowercased().hasPrefix("github.com/") {
            candidate = "https://\(input)"
        } else if input.lowercased().hasPrefix("https://github.com/") ||
                    input.lowercased().hasPrefix("http://github.com/") {
            candidate = input.replacingOccurrences(of: "http://", with: "https://",
                                                   options: [.anchored, .caseInsensitive])
        } else {
            return nil
        }
        return URL(string: candidate)?.absoluteString
    }

    private static func normalizedLink(_ input: String) -> String {
        (githubLink(input) ?? input).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func githubPath(_ path: String) -> String {
        let encoded = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return "https://github.com/\(encoded)"
    }

    private static func searchURL(_ query: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? ""
        return "https://github.com/search?q=\(encoded)"
    }
}

/// The immutable rows and display context owned by one native jump-editing session.
/// A poll may replace the model's live arrays while the editor is focused, but the
/// session continues to narrow the rows the user saw when the island was summoned.
public struct JumpSnapshot: Equatable, Sendable {
    public let radar: [RadarRow]
    public let inbound: [InboundRow]
    public let pulse: [PulseRow]
    public let pulsePreferences: PulsePreferences
    public let inboundPreferences: InboundPreferences
    public let lensPreferences: LensPreferences
    public let selfLogin: String?
    public let lensLastOpened: [String: Date]
    public let freshness: Freshness
    public let radarConfirmed: Bool
    public let inboundConfirmed: Bool
    public let reviewsConfirmed: Bool
    public let clearedRows: [ClearedRow]
    public let showJustCleared: Bool

    public init(radar: [RadarRow], inbound: [InboundRow], pulse: [PulseRow],
                pulsePreferences: PulsePreferences = .default,
                inboundPreferences: InboundPreferences = InboundPreferences(),
                lensPreferences: LensPreferences = .default, selfLogin: String? = nil,
                lensLastOpened: [String: Date] = [:], freshness: Freshness = .fresh,
                radarConfirmed: Bool = false, inboundConfirmed: Bool = false,
                reviewsConfirmed: Bool = false, clearedRows: [ClearedRow] = [],
                showJustCleared: Bool = false) {
        self.radar = radar
        self.inbound = inbound
        self.pulse = pulse
        self.pulsePreferences = pulsePreferences
        self.inboundPreferences = inboundPreferences
        self.lensPreferences = lensPreferences
        self.selfLogin = selfLogin
        self.lensLastOpened = lensLastOpened
        self.freshness = freshness
        self.radarConfirmed = radarConfirmed
        self.inboundConfirmed = inboundConfirmed
        self.reviewsConfirmed = reviewsConfirmed
        self.clearedRows = clearedRows
        self.showJustCleared = showJustCleared
    }

    public func narrow(_ query: JumpQuery) -> JumpQuery.Narrowed {
        query.narrow(radar: radar, inbound: inbound, pulse: pulse)
    }

    public var knownRepos: [String] {
        JumpQuery.knownRepos(radar: radar, inbound: inbound, pulse: pulse)
    }
}
