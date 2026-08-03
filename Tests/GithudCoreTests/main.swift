// Zero-dependency test runner for GithudCore.
//
// XCTest and swift-testing both ship with full Xcode, which the githud stack
// decision rules out (SwiftPM, Command Line Tools only). So tests are a plain
// executable that asserts and exits non-zero on failure. Run via scripts/test.sh
// (`swift run GithudCoreTests`). This is the canonical test command — `swift test`
// is unavailable under CLT-only.
import CoreGraphics
import Foundation
import GithudCore

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)  (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String, file: StaticString = #file, line: UInt = #line) {
    expect(lhs == rhs, "\(message)  [\(lhs) == \(rhs)]", file: file, line: line)
}

func expectClose(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat, _ message: String, file: StaticString = #file, line: UInt = #line) {
    expect(abs(lhs - rhs) <= tolerance, "\(message)  [\(lhs) ≈ \(rhs) ±\(tolerance)]", file: file, line: line)
}

func suite(_ name: String, _ body: () -> Void) {
    print("• \(name)")
    body()
}

// MARK: - IslandGeometry

suite("IslandGeometry — collapsed frame is centered just under the menu bar") {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    let frame = IslandGeometry.collapsedFrame(in: screen)
    expectEqual(frame.width, IslandGeometry.collapsedSize.width, "collapsed width")
    expectEqual(frame.height, IslandGeometry.collapsedSize.height, "collapsed height")
    expectClose(frame.midX, screen.midX, 0.5, "horizontally centered")
    expectClose(frame.maxY, screen.maxY - IslandGeometry.menuBarGap, 0.5, "menu-bar gap below top")
    expect(screen.contains(frame), "fully on screen")
}

suite("IslandGeometry — placement respects an offset (second-monitor) origin") {
    let screen = CGRect(x: 1728, y: 0, width: 1512, height: 982)
    let frame = IslandGeometry.collapsedFrame(in: screen)
    expectClose(frame.midX, screen.midX, 0.5, "centered on the offset screen")
    expect(screen.contains(frame), "fully on the offset screen")
}

suite("IslandGeometry — size-class classification") {
    expectEqual(IslandGeometry.sizeClass(of: IslandGeometry.collapsedSize), .collapsed, "collapsed size class")
    expectEqual(IslandGeometry.sizeClass(of: IslandGeometry.expandedSize), .expanded, "expanded size class")
    expectEqual(IslandGeometry.sizeClass(of: CGSize(width: 900, height: 600)), .other, "other size class")
}

// MARK: - SignalClassifier (the reframed moat — criteria 4 & 11)

struct LabeledFixture: Decodable {
    let expected: String
    let note: String
    let thread: NotificationThread
}

func loadFixture() -> [LabeledFixture] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/GithudCoreTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures/notifications.json")
    guard let data = try? Data(contentsOf: url) else {
        failures += 1
        print("  ✗ could not read fixture at \(url.path)")
        return []
    }
    do {
        return try JSONDecoder().decode([LabeledFixture].self, from: data)
    } catch {
        failures += 1
        print("  ✗ fixture decode failed: \(error)")
        return []
    }
}

let fixture = loadFixture()

suite("SignalClassifier — decodes the real /notifications schema") {
    expect(!fixture.isEmpty, "fixture loaded")
    expectEqual(fixture.count, 16, "fixture thread count")
    // spot-check decoding of nested + snake_case + enrichment fields
    if let prComment = fixture.first(where: { $0.thread.id == "1006" }) {
        expectEqual(prComment.thread.subject.type, "PullRequest", "subject.type decoded")
        expectEqual(prComment.thread.repository.fullName, "acme/api", "repository.full_name decoded")
        expectEqual(prComment.thread.repository.isPrivate, true, "repository.private decoded")
        expectEqual(prComment.thread.latestCommentAuthorLogin, "alice", "enrichment login decoded")
    } else {
        expect(false, "thread 1006 present")
    }
}

suite("SignalClassifier — per-thread classification matches human ground truth") {
    for f in fixture {
        let actual = SignalClassifier.classify(f.thread).actionClass.rawValue
        expectEqual(actual, f.expected, "thread \(f.thread.id) (\(f.note.prefix(38))…)")
    }
}

suite("SignalClassifier — trust metrics (misses are fatal, false alarms are budgeted)") {
    // Positive class = actionRequired. Confusion matrix over the labeled set.
    var tp = 0, fp = 0, fn = 0, tn = 0
    for f in fixture {
        let predictedAR = SignalClassifier.classify(f.thread).actionClass == .actionRequired
        let expectedAR = f.expected == "actionRequired"
        switch (expectedAR, predictedAR) {
        case (true, true): tp += 1
        case (false, true): fp += 1
        case (true, false): fn += 1
        case (false, false): tn += 1
        }
    }
    let precision = (tp + fp) == 0 ? 1.0 : Double(tp) / Double(tp + fp)
    let recall = (tp + fn) == 0 ? 1.0 : Double(tp) / Double(tp + fn)
    print(String(format: "    confusion: TP=%d FP=%d FN=%d TN=%d | precision=%.2f recall=%.2f", tp, fp, fn, tn, precision, recall))
    print("    (FP = false alarms; FN = misses. On a curated fixture; the live trust experiment is RUBRIC #11's top-of-range.)")

    // Safety property: NEVER drop an action-required thread. Misses are fatal.
    expect(fn == 0, "zero misses (recall == 1.0)")
    // False alarms must stay within the curated-set bound (budget proxy ≤ 1).
    expect(fp <= 1, "false alarms within bound (FP=\(fp) ≤ 1)")
}

suite("SignalClassifier — radar filters to unread action-required, ranked by urgency") {
    let radar = SignalClassifier.radar(fixture.map { $0.thread })
    // 6 unread surfaced: 1001-1005 + 1015 (policy-b: a direct @you mention surfaces even
    // from a bot). 1016 is read → dropped; 1006 is activity on YOUR OWN PR → routed to the
    // "Your PRs" lane (filtered from "Needs you", still in the auditable suppressed set).
    expectEqual(radar.count, 6, "radar item count")
    expect(!radar.contains { $0.thread.id == "1016" }, "read thread 1016 excluded from radar")
    expect(radar.allSatisfy { $0.classification.actionClass == .actionRequired }, "radar is all action-required")
    if let top = radar.first {
        // critical-first (color doctrine): the security_alert floats above review_requested
        // (urgency 95) despite its lower urgency (92). See the dedicated doctrine suite.
        expectEqual(top.thread.id, "1005", "critical-first: the security_alert is on top")
        expect(SignalClassifier.isCritical(top.thread), "the top item is the critical emergency")
    }
    // Within the ordinary tier (everything after the one critical), urgency is non-increasing.
    let ordinaryUrgencies = radar.filter { !SignalClassifier.isCritical($0.thread) }.map { $0.classification.urgency }
    expect(ordinaryUrgencies == ordinaryUrgencies.sorted(by: >), "ordinary radar items ranked by urgency desc")
    // The ONLY automation allowed on the radar is a direct @you mention (policy-b).
    expect(radar.filter { SignalClassifier.isLikelyAutomated($0.thread) }.allSatisfy { $0.thread.reason == "mention" },
           "the only bot on the radar is a direct @you mention (policy-b); no other automation leaks in")
}

suite("SignalClassifier — color doctrine: critical salience is its own sort dimension (consult 008)") {
    // The criticality POLICY: exactly one categorical emergency (act-now-or-contain).
    expectEqual(SignalClassifier.criticalReasons, ["security_alert"], "criticalReasons = {security_alert} only")

    func one(_ reason: String) -> NotificationThread? {
        let json = "[{\"id\":\"x\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"t\",\"subject\":{\"title\":\"x\",\"type\":\"Issue\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))?.first
    }
    if let sec = one("security_alert") { expect(SignalClassifier.isCritical(sec), "security_alert is critical") }
    if let rev = one("review_requested") { expect(!SignalClassifier.isCritical(rev), "review_requested is NOT critical") }
    if let men = one("mention") { expect(!SignalClassifier.isCritical(men), "mention is NOT critical") }

    // THE BUG THE DOCTRINE FIXES: on the real fixture, security_alert (urgency 92) must sort
    // ABOVE review_requested (urgency 95) — else the lone red glyph strands below a calm row.
    let radar = SignalClassifier.radar(fixture.map { $0.thread })
    let secIdx = radar.firstIndex { $0.thread.id == "1005" }   // security_alert (urgency 92)
    let revIdx = radar.firstIndex { $0.thread.id == "1001" }   // review_requested (urgency 95)
    expect(secIdx != nil && revIdx != nil, "both the security_alert and the review_requested are on the radar")
    if let s = secIdx, let r = revIdx {
        expect(s < r, "security_alert sorts ABOVE review_requested — critical-first, not urgency")
        expectEqual(radar[s].classification.urgency, 92, "urgency stays 92 (salience drives the sort, NOT a magic-100 bump)")
    }

    // The criticality flag rides onto the presented row (so the view stays dumb).
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    if let sec = radar.first(where: { $0.thread.id == "1005" }) {
        expect(RadarPresenter.row(for: sec, now: now).isCritical, "RadarRow.isCritical carries the emergency flag")
    }
    if let rev = radar.first(where: { $0.thread.id == "1001" }) {
        expect(!RadarPresenter.row(for: rev, now: now).isCritical, "an ordinary row is not critical")
    }
}

suite("SignalClassifier — suppressed partitions the unread set (miss-audit, consult 004)") {
    let threads = fixture.map { $0.thread }
    let radar = SignalClassifier.radar(threads)
    let suppressed = SignalClassifier.suppressed(threads)
    let unread = threads.filter { $0.unread }.count
    expectEqual(radar.count + suppressed.count, unread, "radar + suppressed = all unread (nothing falls through)")
}

suite("SurfacePreferences — toggling which reason-types surface (default auto)") {
    let threads = fixture.map { $0.thread }
    let auto = SignalClassifier.radar(threads)               // .auto default
    expect(SurfacePreferences.auto.isAuto, "default preferences are auto")

    let noReviews = SurfacePreferences.auto.toggling("review_requested")
    let r2 = SignalClassifier.radar(threads, preferences: noReviews)
    expect(!noReviews.isAuto, "toggled-off preferences are not auto")
    expect(!r2.contains { $0.thread.reason == "review_requested" }, "disabling review_requested drops them from the radar")
    expect(r2.count < auto.count, "fewer surfaced after disabling a reason")
    // radar + suppressed still partitions the unread set under custom prefs
    let s2 = SignalClassifier.suppressed(threads, preferences: noReviews)
    expectEqual(r2.count + s2.count, threads.filter { $0.unread }.count, "partition holds under custom prefs")

    let withCI = SurfacePreferences.auto.toggling("ci_activity")
    let r3 = SignalClassifier.radar(threads, preferences: withCI)
    expect(r3.count > auto.count, "enabling ci_activity surfaces a normally-hidden reason")
}

suite("SurfacePreferences — novel/unknown reasons surface by default (never-miss, review iter 24)") {
    let json = """
    [{"id":"n1","unread":true,"reason":"approval_requested_brand_new","updated_at":"2026-06-16T09:00:00Z","subject":{"title":"x","type":"PullRequest","latest_comment_url":null},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}}]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    expect(SignalClassifier.radar(threads).contains { $0.thread.id == "n1" }, "a novel reason surfaces under auto (never silently dropped)")
    let emptyPrefs = SignalClassifier.radar(threads, preferences: SurfacePreferences(enabledReasons: []))
    expect(emptyPrefs.contains { $0.thread.id == "n1" }, "a novel reason surfaces even with an empty enabled set")
    // a KNOWN reason the user disabled stays hidden
    let knownJSON = """
    [{"id":"k1","unread":true,"reason":"subscribed","updated_at":"2026-06-16T09:00:00Z","subject":{"title":"x","type":"Issue","latest_comment_url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}]
    """
    let known = (try? NotificationThread.list(from: Data(knownJSON.utf8))) ?? []
    expect(!SignalClassifier.radar(known, preferences: SurfacePreferences(enabledReasons: [])).contains { $0.thread.id == "k1" }, "a known reason left disabled stays hidden")
}

// MARK: - PollPlan (RUBRIC #8 — polling discipline)

suite("PollPlan — 200 adopts fresh validators and honors the poll interval") {
    let plan = PollPlan.from(status: 200, etag: "W/\"abc\"",
                             lastModified: "Mon, 16 Jun 2026 09:00:00 GMT", pollInterval: 60)
    expect(!plan.notModified, "200 is not notModified")
    expectEqual(plan.nextValidators.etag, "W/\"abc\"", "etag adopted")
    expectEqual(plan.nextValidators.lastModified, "Mon, 16 Jun 2026 09:00:00 GMT", "last-modified adopted")
    expectEqual(plan.nextPollAfterSeconds, 60, "poll interval honored")
}

suite("PollPlan — 304 is no-cost and retains previous validators") {
    let prev = PollValidators(etag: "W/\"abc\"", lastModified: "Mon, 16 Jun 2026 09:00:00 GMT")
    let plan = PollPlan.from(status: 304, etag: nil, lastModified: nil,
                             pollInterval: nil, previousValidators: prev)
    expect(plan.notModified, "304 is notModified (no primary-rate cost)")
    expectEqual(plan.nextValidators.etag, "W/\"abc\"", "etag retained across 304")
    expectEqual(plan.nextValidators.lastModified, prev.lastModified, "last-modified retained across 304")
    expectEqual(plan.nextPollAfterSeconds, PollPlan.defaultMinInterval, "default interval when header absent")
}

suite("PollPlan — X-Poll-Interval is a floor") {
    expectEqual(PollPlan.from(status: 200, etag: nil, lastModified: nil, pollInterval: 30).nextPollAfterSeconds,
                60, "30 floored to 60")
    expectEqual(PollPlan.from(status: 200, etag: nil, lastModified: nil, pollInterval: 120).nextPollAfterSeconds,
                120, "120 honored")
}

suite("PollValidators — conditional headers") {
    let validators = PollValidators(etag: "W/\"x\"", lastModified: "T")
    expectEqual(validators.conditionalHeaders["If-None-Match"], "W/\"x\"", "etag → If-None-Match")
    expectEqual(validators.conditionalHeaders["If-Modified-Since"], "T", "last-modified → If-Modified-Since")
    expect(PollValidators().isEmpty, "empty validators are empty")
}

// MARK: - KeychainPAT (RUBRIC #9 — credential safety, pure helpers)

suite("Freshness — degraded reading confidence (the sanctioned caution use, iter 33)") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    func at(_ s: String) -> Date { iso.date(from: s)! }

    // not polled yet → fresh (loading state, not an accusation about the reading)
    expectEqual(FreshnessModel.status(lastSuccess: nil, now: now, consecutiveFailures: 0), .fresh, "no poll yet → fresh (loading)")
    // a recent success (200 OR 304) → fresh, no chrome
    let recent = FreshnessModel.status(lastSuccess: at("2026-06-16T09:59:30Z"), now: now, consecutiveFailures: 0)
    expectEqual(recent, .fresh, "30s-old success → fresh")
    expect(FreshnessModel.label(for: recent) == nil, "fresh → no label (normal operation is quiet)")
    // old success, no tracked failures (e.g. resumed from sleep) → stale
    let stale = FreshnessModel.status(lastSuccess: at("2026-06-16T09:55:00Z"), now: now, consecutiveFailures: 0)  // 300s
    expectEqual(stale, .stale(ageSeconds: 300), "5m-old success, no failures → stale")
    expectEqual(FreshnessModel.label(for: stale), "Updated 5m ago", "stale label")
    // 2 consecutive failures → failing, even though age (60s) is under staleAfter
    let failing = FreshnessModel.status(lastSuccess: at("2026-06-16T09:59:00Z"), now: now, consecutiveFailures: 2)
    expectEqual(failing, .failing(consecutive: 2, ageSeconds: 60), "2 failures → failing (fires before staleAfter)")
    expectEqual(FreshnessModel.label(for: failing), "Reconnecting — last update 1m ago", "failing label")
    expect(stale.isDegraded && failing.isDegraded && !recent.isDegraded, "isDegraded gates the cue")
    // boundary: exactly staleAfter (180s) is NOT yet stale (strictly greater)
    expectEqual(FreshnessModel.status(lastSuccess: at("2026-06-16T09:57:00Z"), now: now, consecutiveFailures: 0), .fresh, "exactly 180s → still fresh")
    expectEqual(FreshnessModel.ageText(45), "45s", "ageText seconds")
    expectEqual(FreshnessModel.ageText(600), "10m", "ageText minutes")
}

suite("KeychainPAT — classic-PAT shape + redaction never leaks the secret") {
    let classic = "ghp_" + String(repeating: "A", count: 36)   // 40 chars
    expect(KeychainPAT.looksLikeClassicPAT(classic), "ghp_+36 is a classic PAT")
    expect(!KeychainPAT.looksLikeClassicPAT("github_pat_" + String(repeating: "B", count: 60)),
           "fine-grained token rejected")
    expect(!KeychainPAT.looksLikeClassicPAT("ghp_short"), "short token rejected")
    // review: the length gate is the FULL 40 chars — a truncated 39-char paste must NOT
    // pass the "classic PAT ✓" gate and then fail at the API.
    expect(!KeychainPAT.looksLikeClassicPAT("ghp_" + String(repeating: "A", count: 35)), "39-char (truncated) classic PAT rejected")
    expect(KeychainPAT.looksLikeClassicPAT("ghp_" + String(repeating: "A", count: 36)), "exactly 40 chars accepted")
    let red = KeychainPAT.redacted(classic)
    expect(!red.contains(String(repeating: "A", count: 36)), "redaction omits the secret body")
    expect(red.contains("ghp_") && red.contains("(40)"), "redaction shows prefix + length only")
}

suite("KeychainPAT — store/read/delete round-trip on a THROWAWAY service (WP-4e write path)") {
    // keychain-headless-prompt: the DEFAULT test run touches NO Keychain — this whole block is
    // OPT-IN via GITHUD_KEYCHAIN_TEST=1 — so `scripts/test.sh` can never block on a GUI Keychain
    // prompt on a headless box. When enabled it uses a THROWAWAY service/account (NEVER the real
    // KeychainPAT.service/account) and deletes in teardown, so no cross-build item lingers to
    // trigger a later Always-Allow prompt. Token values are `ghp_`-shape fillers only — never a
    // real-looking secret.
    guard ProcessInfo.processInfo.environment["GITHUD_KEYCHAIN_TEST"] != nil else {
        print("  … skipped (set GITHUD_KEYCHAIN_TEST=1 to exercise the real Keychain round-trip)")
        return
    }
    let svc = "githud.test.keychain.throwaway"
    let acct = "wp4e-roundtrip"
    // WALL against clobbering the real credential: the throwaway identity must differ.
    expect(svc != KeychainPAT.service, "throwaway service is NOT the real service")
    expect(acct != KeychainPAT.account, "throwaway account is NOT the real account")

    func isOK(_ r: Result<Void, KeychainPAT.WriteError>) -> Bool { if case .success = r { return true }; return false }
    func readBack() -> Result<String, KeychainPAT.ReadError> { KeychainPAT.read(service: svc, account: acct) }

    _ = KeychainPAT.delete(service: svc, account: acct)   // clean slate before the run

    let tokenA = "ghp_" + String(repeating: "0", count: 36)   // 40 chars, classic shape, not real
    let tokenB = "ghp_" + String(repeating: "1", count: 36)

    // ADD (item absent → SecItemAdd)
    expect(isOK(KeychainPAT.store(tokenA, service: svc, account: acct)), "store ADDS when absent")
    if case .success(let read) = readBack() { expectEqual(read, tokenA, "read returns the stored token") }
    else { expect(false, "read after add succeeds") }

    // UPDATE (item present → SecItemUpdate; proves add-or-update semantics)
    expect(isOK(KeychainPAT.store(tokenB, service: svc, account: acct)), "store UPDATES when present")
    if case .success(let read) = readBack() { expectEqual(read, tokenB, "read returns the UPDATED token") }
    else { expect(false, "read after update succeeds") }

    // Paste artifacts: store trims surrounding whitespace/newlines
    expect(isOK(KeychainPAT.store("  \(tokenA)\n", service: svc, account: acct)), "store accepts a padded paste")
    if case .success(let read) = readBack() { expectEqual(read, tokenA, "store TRIMS whitespace/newlines on write") }
    else { expect(false, "read after padded store succeeds") }

    // DELETE + verify gone
    expect(isOK(KeychainPAT.delete(service: svc, account: acct)), "delete removes the item")
    if case .failure(let err) = readBack() { expectEqual(err, KeychainPAT.ReadError.notFound, "read after delete → notFound") }
    else { expect(false, "read after delete fails as notFound") }

    // Delete is idempotent (already absent → still success)
    expect(isOK(KeychainPAT.delete(service: svc, account: acct)), "delete is idempotent (absent → success)")

    // TEARDOWN — belt-and-suspenders: leave nothing behind on the throwaway service.
    _ = KeychainPAT.delete(service: svc, account: acct)
}

// MARK: - Enrichment targeting (iter 5)

suite("NotificationThread — needsEnrichment targets comment-driven, un-enriched threads") {
    let json = """
    [
      {"id":"a","unread":true,"reason":"author","updated_at":"t","subject":{"title":"x","type":"Issue","latest_comment_url":"https://api/c/1"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"b","unread":true,"reason":"author","updated_at":"t","subject":{"title":"x","type":"PullRequest","latest_comment_url":"https://api/c/2"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}},"latest_comment_author_login":"alice"},
      {"id":"c","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","latest_comment_url":"https://api/c/3"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"d","unread":true,"reason":"author","updated_at":"t","subject":{"title":"x","type":"Issue","latest_comment_url":null},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    expectEqual(threads.count, 4, "decoded 4 threads")
    if threads.count == 4 {
        expect(threads[0].needsEnrichment, "author ISSUE + comment-url + no login → needs enrichment (a PR would route to Your PRs instead)")
        expect(!threads[1].needsEnrichment, "already has author login → skip")
        expect(!threads[2].needsEnrichment, "review_requested → not comment-driven → skip")
        expect(!threads[3].needsEnrichment, "no latest_comment_url → skip")
    }
}

// MARK: - Self-activity demotion (iter 6)

suite("SignalClassifier — your own latest comment is demoted off the radar") {
    let json = """
    [
      {"id":"s1","unread":true,"reason":"author","updated_at":"t","subject":{"title":"my issue","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}},"latest_comment_author_login":"me"},
      {"id":"s2","unread":true,"reason":"author","updated_at":"t","subject":{"title":"my issue","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}},"latest_comment_author_login":"colleague"},
      {"id":"s3","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"their PR","type":"PullRequest","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}},"latest_comment_author_login":"me"}
    ]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    expectEqual(threads.count, 3, "decoded 3 threads")
    if threads.count == 3 {
        expectEqual(SignalClassifier.classify(threads[0], selfLogin: "me").actionClass, .fyi, "your own latest comment → fyi")
        expectEqual(SignalClassifier.classify(threads[0]).actionClass, .actionRequired, "no selfLogin → not demoted")
        expectEqual(SignalClassifier.classify(threads[0], selfLogin: "ME").actionClass, .fyi, "self match is case-insensitive")
        expectEqual(SignalClassifier.classify(threads[1], selfLogin: "me").actionClass, .actionRequired, "colleague's comment → action-required")
        expectEqual(SignalClassifier.classify(threads[2], selfLogin: "me").actionClass, .actionRequired, "review_requested stays action-required (structural)")
        let radar = SignalClassifier.radar(threads, selfLogin: "me")
        expect(!radar.contains { $0.thread.id == "s1" }, "self-comment thread off the radar")
        expect(radar.contains { $0.thread.id == "s2" }, "colleague thread on the radar")
        expect(radar.contains { $0.thread.id == "s3" }, "review_requested on the radar")
    }
}

// MARK: - RadarPresenter (iter 7 — island rows)

suite("RadarPresenter — relative age (deterministic)") {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let base = iso.date(from: "2026-06-16T10:00:00Z")!
    expectEqual(RadarPresenter.age(fromISO8601: "2026-06-16T10:00:00Z", now: base), "now", "0s → now")
    expectEqual(RadarPresenter.age(fromISO8601: "2026-06-16T09:30:00Z", now: base), "30m", "30 min")
    expectEqual(RadarPresenter.age(fromISO8601: "2026-06-16T07:00:00Z", now: base), "3h", "3 hours")
    expectEqual(RadarPresenter.age(fromISO8601: "2026-06-13T10:00:00Z", now: base), "3d", "3 days")
    expectEqual(RadarPresenter.age(fromISO8601: "2026-06-01T10:00:00Z", now: base), "2w", "15 days → 2w")
    expectEqual(RadarPresenter.age(fromISO8601: "garbage", now: base), "", "unparseable → empty")
}

suite("RadarPresenter — row formatting from a classified thread") {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let json = """
    [{"id":"r1","unread":true,"reason":"review_requested","updated_at":"2026-06-16T08:00:00Z","subject":{"title":"Add retry/backoff","type":"PullRequest","latest_comment_url":"u"},"repository":{"full_name":"acme/web","private":true,"owner":{"login":"acme","type":"Organization"}},"latest_comment_author_login":"alice"}]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    let radar = SignalClassifier.radar(threads)
    expectEqual(radar.count, 1, "1 action-required")
    if let row = radar.first.map({ RadarPresenter.row(for: $0, now: now) }) {
        expectEqual(row.repo, "acme/web", "repo")
        expectEqual(row.title, "Add retry/backoff", "title")
        expectEqual(row.subtitle, "@alice · review requested", "subtitle composed WITHOUT a baked age")
        expectEqual(row.timestamp, "2026-06-16T08:00:00Z", "row carries the raw ISO timestamp (age formatted at render)")
        expectEqual(row.urgency, 95, "urgency")
        expectEqual(row.symbolName, "arrow.triangle.pull", "review_requested → pull-request symbol")
        expectEqual(RadarPresenter.displaySubtitle(for: row, now: now), "acme/web · @alice · review requested · 2h",
                    "displaySubtitle appends the render-time age (repo · subtitle · age)")
    }
    expectEqual(RadarPresenter.symbolName(for: "mention"), "at", "mention → at")
    expectEqual(RadarPresenter.symbolName(for: "assign"), "person.crop.circle.badge.checkmark", "assign symbol")
    expectEqual(RadarPresenter.symbolName(for: "weird"), "bell.fill", "unknown → bell")
}

// MARK: - Live ages (WP-1c — format at render, re-render on a coarse age-bucket flip)

suite("Live ages — the SAME row shows the correct age at any render `now` (no baked staleness) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    // A thread last touched at 08:00 — the longest-stuck-item case the baked "· 2h" got wrong.
    let json = "[{\"id\":\"old\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"2026-06-16T08:00:00Z\",\"subject\":{\"title\":\"Stuck PR\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
    let radar = SignalClassifier.radar((try? NotificationThread.list(from: Data(json.utf8))) ?? [])
    let row = RadarPresenter.row(for: radar[0], now: iso.date(from: "2026-06-16T10:00:00Z")!)
    // THE PROOF: one row struct, three different render clocks → three correct ages. The row's
    // stored `subtitle` never changes; only the render-time formatting moves. A baked "· 2h"
    // could not do this — it would read "2h" forever (the exact bug this package removes).
    expectEqual(RadarPresenter.displaySubtitle(for: row, now: iso.date(from: "2026-06-16T10:00:00Z")!), "o/r · review requested · 2h", "at +2h → 2h")
    expectEqual(RadarPresenter.displaySubtitle(for: row, now: iso.date(from: "2026-06-16T13:00:00Z")!), "o/r · review requested · 5h", "SAME row, +5h → 5h (expand-after-simulated-hours proof)")
    expectEqual(RadarPresenter.displaySubtitle(for: row, now: iso.date(from: "2026-06-19T08:00:00Z")!), "o/r · review requested · 3d", "SAME row, +3d → 3d")
    expectEqual(row.subtitle, "review requested", "the stored subtitle is unchanged and ageless (no actor here)")
}

suite("Live ages — ageSignature flips exactly at each bucket boundary, and only then ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let base = "2026-06-16T10:00:00Z"
    func rowAt(_ updated: String) -> RadarRow {
        let json = "[{\"id\":\"x\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"\(updated)\",\"subject\":{\"title\":\"t\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        let radar = SignalClassifier.radar((try? NotificationThread.list(from: Data(json.utf8))) ?? [])
        return RadarPresenter.row(for: radar[0], now: iso.date(from: base)!)
    }
    func sig(_ row: RadarRow, _ now: String) -> [String] { RadarPresenter.ageSignature(for: [row], now: iso.date(from: now)!) }
    let r = rowAt("2026-06-16T09:59:30Z")   // 30s old at base → "now"
    // now → 1m boundary (60s): NO flip at 59s, flip at 60s.
    expectEqual(sig(r, "2026-06-16T10:00:29Z"), ["now"], "59s old → still now (no flip)")
    expect(sig(r, "2026-06-16T10:00:29Z") == sig(r, "2026-06-16T10:00:00Z"), "within the 'now' bucket the signature is stable → no re-render")
    expect(sig(r, "2026-06-16T10:00:30Z") != sig(r, "2026-06-16T10:00:00Z"), "crossing 60s (now→1m) flips the signature → re-render")
    expectEqual(sig(r, "2026-06-16T10:00:30Z"), ["1m"], "60s → 1m")
    // 1m → 2m (a minute boundary within the minutes tier is still an honest flip).
    let r2 = rowAt("2026-06-16T09:58:00Z")   // 2m old at base
    expect(sig(r2, "2026-06-16T10:00:59Z") != sig(r2, "2026-06-16T10:01:00Z"), "2m→3m across the minute boundary flips")
    // minutes → hours boundary.
    let r3 = rowAt("2026-06-16T09:01:00Z")   // 59m at base
    expect(sig(r3, "2026-06-16T10:00:59Z") != sig(r3, "2026-06-16T10:01:00Z"), "59m→1h flips at the hour boundary")
    expectEqual(sig(r3, "2026-06-16T10:01:00Z"), ["1h"], "60m → 1h")
    // within an hour once past it: 1h stays 1h for the whole hour → no churn.
    expect(sig(r3, "2026-06-16T10:30:00Z") == sig(r3, "2026-06-16T11:00:59Z"), "1h holds across the hour (no re-render until 2h)")
    expect(sig(r3, "2026-06-16T11:01:00Z") != sig(r3, "2026-06-16T11:00:59Z"), "…then flips to 2h")
}

// MARK: - Comment excerpt (iter 21)

suite("RadarPresenter — comment excerpt (1-line, truncated)") {
    expectEqual(RadarPresenter.excerpt(from: "LGTM, ship it"), "LGTM, ship it", "short body passes through")
    expectEqual(RadarPresenter.excerpt(from: "line one\nline two\n\n  line three"), "line one line two line three", "newlines + extra spaces collapsed")
    expectEqual(RadarPresenter.excerpt(from: nil), nil, "nil body → nil")
    expectEqual(RadarPresenter.excerpt(from: "   \n  "), nil, "whitespace-only → nil")
    let truncated = RadarPresenter.excerpt(from: String(repeating: "ab ", count: 100), maxLength: 40)
    expect(truncated != nil && truncated!.count <= 40 && truncated!.hasSuffix("…"), "long body truncated with ellipsis")
}

// MARK: - Open-on-GitHub URL mapping (iter 13)

suite("RadarPresenter — htmlURL maps API → web (Open-on-GitHub)") {
    func thread(_ json: String) -> NotificationThread? { try? NotificationThread.list(from: Data(json.utf8)).first }
    let pr = thread("""
    [{"id":"u1","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"https://api.github.com/repos/acme/web/pulls/812"},"repository":{"full_name":"acme/web","private":true,"owner":{"login":"acme","type":"Organization"}}}]
    """)
    let issue = thread("""
    [{"id":"u2","unread":true,"reason":"mention","updated_at":"t","subject":{"title":"x","type":"Issue","url":"https://api.github.com/repos/acme/api/issues/77"},"repository":{"full_name":"acme/api","private":true,"owner":{"login":"acme","type":"Organization"}}}]
    """)
    let noURL = thread("""
    [{"id":"u3","unread":true,"reason":"security_alert","updated_at":"t","subject":{"title":"x","type":"RepositoryVulnerabilityAlert","url":null},"repository":{"full_name":"acme/api","private":true,"owner":{"login":"acme","type":"Organization"}}}]
    """)
    expectEqual(pr.map { RadarPresenter.htmlURL(for: $0) } ?? nil, "https://github.com/acme/web/pull/812", "PR api→web (pulls→pull)")
    expectEqual(issue.map { RadarPresenter.htmlURL(for: $0) } ?? nil, "https://github.com/acme/api/issues/77", "issue api→web")
    expectEqual(noURL.map { RadarPresenter.htmlURL(for: $0) } ?? nil, "https://github.com/acme/api", "no subject url → repo page")
}

// MARK: - Signal taxonomy hardening v2 (iter 26 — second-opinion recalibration)

suite("SignalClassifier v2 — urgency recalibration + direct-mention + unknown floor") {
    let json = """
    [
      {"id":"sec","unread":true,"reason":"security_alert","updated_at":"t","subject":{"title":"x","type":"RepositoryVulnerabilityAlert","latest_comment_url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"asg","unread":true,"reason":"assign","updated_at":"t","subject":{"title":"x","type":"Issue","latest_comment_url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"mnB","unread":true,"reason":"mention","updated_at":"t","latest_comment_author_login":"pagerduty[bot]","subject":{"title":"x","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"tmB","unread":true,"reason":"team_mention","updated_at":"t","latest_comment_author_login":"github-actions[bot]","subject":{"title":"x","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"nov","unread":true,"reason":"approval_requested_2027","updated_at":"t","subject":{"title":"x","type":"PullRequest","latest_comment_url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    func by(_ id: String) -> NotificationThread? { threads.first { $0.id == id } }
    expectEqual(threads.count, 5, "decoded 5 threads")
    if let sec = by("sec"), let asg = by("asg") {
        expectEqual(SignalClassifier.classify(sec).urgency, 92, "security_alert raised to 92")
        expect(SignalClassifier.classify(sec).urgency > SignalClassifier.classify(asg).urgency, "security_alert outranks assign")
    }
    if let mnB = by("mnB") {
        expectEqual(SignalClassifier.classify(mnB).actionClass, .actionRequired, "a bot's DIRECT @you mention is NOT demoted (PagerDuty case)")
        expect(SurfacePreferences.auto.surfaces(mnB, selfLogin: nil), "and it actually SURFACES (surfaces() exempts direct mentions)")
    }
    if let tmB = by("tmB") {
        expectEqual(SignalClassifier.classify(tmB).actionClass, .noise, "a bot team_mention is STILL demoted (diffuse, not direct)")
        expect(!SurfacePreferences.auto.surfaces(tmB, selfLogin: nil), "and stays suppressed")
    }
    if let nov = by("nov") {
        expectEqual(SignalClassifier.classify(nov).urgency, 60, "a novel reason surfaces at urgency 60 (not buried at 10)")
        expectEqual(SignalClassifier.classify(nov).actionClass, .fyi, "novel reason stays fyi (honest — we don't KNOW it's action-required)")
        expect(SignalClassifier.radar(threads).contains { $0.thread.id == "nov" }, "novel reason is ON the radar (never-miss)")
    }
}

suite("SignalClassifier — a merged/closed subject drops off 'Needs you' (stale-notification fix, iter 43)") {
    func mk(_ id: String, _ state: String?) -> NotificationThread {
        let s = state.map { ",\"subject_state\":\"\($0)\"" } ?? ""
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"t\","
            + "\"subject\":{\"title\":\"x\",\"type\":\"PullRequest\",\"url\":\"https://api.github.com/repos/o/r/pulls/1\"}\(s),"
            + "\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!.first!
    }
    let merged = mk("merged", "merged"), closed = mk("closed", "closed")
    let open = mk("open", "open"), unknown = mk("unknown", nil)

    // surfaces(): a resolved subject is demoted; open / unknown still surface (never-miss).
    expect(!SurfacePreferences.auto.surfaces(merged, selfLogin: nil), "a MERGED PR's review-request does NOT surface")
    expect(!SurfacePreferences.auto.surfaces(closed, selfLogin: nil), "a CLOSED PR's review-request does NOT surface")
    expect(SurfacePreferences.auto.surfaces(open, selfLogin: nil), "an OPEN PR's review-request still surfaces (needs you)")
    expect(SurfacePreferences.auto.surfaces(unknown, selfLogin: nil), "an UNKNOWN-state subject still surfaces (never-miss on missing data)")

    // radar drops resolved → suppressed catches them (auditable, not a silent drop).
    let all = [merged, closed, open, unknown]
    let radar = SignalClassifier.radar(all), supp = SignalClassifier.suppressed(all)
    expect(!radar.contains { $0.thread.id == "merged" }, "merged PR is OFF the radar")
    expect(supp.contains { $0.thread.id == "merged" }, "merged PR is in the SUPPRESSED set (recoverable)")
    expect(radar.contains { $0.thread.id == "open" }, "open PR stays on the radar")
    expectEqual(radar.count + supp.count, all.count, "radar + suppressed still partitions every unread thread")

    expect(SignalClassifier.isSubjectResolved(merged) && SignalClassifier.isSubjectResolved(closed), "merged & closed → resolved")
    expect(!SignalClassifier.isSubjectResolved(open) && !SignalClassifier.isSubjectResolved(unknown), "open & unknown → not resolved")

    // needsSubjectState: pay the extra GET only for an unresolved action-required PR/Issue.
    expect(unknown.needsSubjectState, "an unresolved review-requested PR warrants the subject-state fetch")
    expect(!merged.needsSubjectState, "an already-resolved thread does NOT re-fetch")
}

suite("SurfacePreferences — a READ-me ask survives resolution (dogfood 2026-07-18)") {
    func mk(_ id: String, reason: String, state: String?, commenter: String? = nil) -> NotificationThread {
        let s = state.map { ",\"subject_state\":\"\($0)\"" } ?? ""
        let c = commenter.map { ",\"latest_comment_author_login\":\"\($0)\"" } ?? ""
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"t\","
            + "\"subject\":{\"title\":\"x\",\"type\":\"PullRequest\",\"url\":\"https://api.github.com/repos/o/r/pulls/1\"}\(s)\(c),"
            + "\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!.first!
    }
    // THE case: a colleague's post-merge correction — unread human comment on a MERGED
    // PR, with the `comment` reason ENABLED (default-off; the dogfood user enabled it in
    // the settings card — that's how the row reached the glass to flash at all). The old
    // reason-blind verdict gate ate it after one tick; it must surface.
    let withComment = SurfacePreferences.auto.toggling("comment")
    let postMerge = mk("c1", reason: "comment", state: "merged", commenter: "patanet7")
    expect(withComment.surfaces(postMerge, selfLogin: "pro-vi"),
           "an unanswered human comment on a MERGED PR still surfaces (the read-me ask survives)")
    // A mention on a closed subject: deliberately-routed AND read-me — surfaces.
    expect(SurfacePreferences.auto.surfaces(mk("m1", reason: "mention", state: "closed"), selfLogin: nil),
           "an @mention on a CLOSED subject still surfaces")
    // The asks that DIE with the subject stay discharged (#416 unchanged) — pinned with
    // the reason ENABLED, so it is the VERDICT gate doing the work, not the preference.
    expect(!SurfacePreferences.auto.surfaces(mk("r1", reason: "review_requested", state: "merged"), selfLogin: nil),
           "a review request on a merged PR stays suppressed (its ask died)")
    expect(!SurfacePreferences.auto.toggling("subscribed")
            .surfaces(mk("s1", reason: "subscribed", state: "closed"), selfLogin: "pro-vi"),
           "subscribed/inbound on a closed subject stays suppressed even when enabled (no fake merge-history rows)")
    // The answered discharge still governs read-me noise: your OWN latest comment on the
    // merged PR means the ball is in others' court.
    expect(!withComment.surfaces(mk("c2", reason: "comment", state: "merged", commenter: "pro-vi"),
                                 selfLogin: "pro-vi"),
           "…but your own answered comment thread stays discharged even on a merged PR")
}

suite("SurfacePreferences — activity on your OWN PR is filtered from 'Needs you' (it lives in Your PRs, iter 43)") {
    func mk(_ id: String, _ type: String) -> NotificationThread {
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"author\",\"updated_at\":\"t\","
            + "\"subject\":{\"title\":\"x\",\"type\":\"\(type)\",\"url\":\"https://api.github.com/repos/o/r/pulls/1\",\"latest_comment_url\":\"u\"},"
            + "\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!.first!
    }
    let ownPR = mk("pr", "PullRequest"), ownIssue = mk("iss", "Issue")
    expect(ownPR.isOwnAuthoredPR, "author + PullRequest → own-authored PR")
    expect(!ownIssue.isOwnAuthoredPR, "author + Issue → NOT (issues have no dedicated lane)")
    expect(!SurfacePreferences.auto.surfaces(ownPR, selfLogin: nil), "your own PR's activity does NOT surface in Needs you (Your PRs covers it)")
    expect(SurfacePreferences.auto.surfaces(ownIssue, selfLogin: nil), "an issue you authored still surfaces (no dedicated lane)")
    expect(!ownPR.needsEnrichment, "a filtered own-PR is NOT enriched (frees budget for the surfacing threads)")
    expect(ownIssue.needsEnrichment, "an authored issue IS enriched (it surfaces → show its latest-comment author)")
    let all = [ownPR, ownIssue]
    let radar = SignalClassifier.radar(all), supp = SignalClassifier.suppressed(all)
    expect(!radar.contains { $0.thread.id == "pr" } && supp.contains { $0.thread.id == "pr" }, "own PR → off the radar, into suppressed (auditable)")
    expect(radar.contains { $0.thread.id == "iss" }, "own issue → stays on the radar")
}

suite("SignalClassifier v2 — invitation + your_activity + enumeration completeness") {
    func one(_ reason: String) -> NotificationThread? {
        let json = "[{\"id\":\"k\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"t\",\"subject\":{\"title\":\"x\",\"type\":\"Issue\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))?.first
    }
    if let inv = one("invitation") {
        expectEqual(SignalClassifier.classify(inv).actionClass, .actionRequired, "invitation → action-required (accept/decline)")
        expectEqual(SignalClassifier.classify(inv).urgency, 85, "invitation urgency 85")
    }
    if let ya = one("your_activity") {
        expectEqual(SignalClassifier.classify(ya).actionClass, .fyi, "your_activity → fyi")
    }
    expect(SurfacePreferences.autoReasons.contains("invitation"), "invitation is default-ON")
    expect(!SurfacePreferences.autoReasons.contains("your_activity"), "your_activity is default-OFF")
    expect(SurfacePreferences.allReasons.contains("your_activity"), "your_activity is toggleable")
    expectEqual(SignalClassifier.knownReasons.count, 13, "13 reasons enumerated")
    expectEqual(Set(SurfacePreferences.allReasons),
                SignalClassifier.knownReasons.union([SignalClassifier.inboundReason]),
                "the toggle set == the GitHub enumeration + the ONE derived reason (inbound)")
    expect(!SignalClassifier.knownReasons.contains(SignalClassifier.inboundReason),
           "the derived reason never masquerades as a GitHub value (novelty checks stay raw)")
    // every KNOWN reason has an explicit classify case (none falls to the novel default)
    for reason in SignalClassifier.knownReasons {
        if let th = one(reason) {
            expect(!SignalClassifier.classify(th).rationale.contains("surfaced for triage"),
                   "known reason '\(reason)' has an explicit case (not the novel default)")
        } else {
            expect(false, "decode \(reason)")
        }
    }
    expectEqual(RadarPresenter.symbolName(for: "invitation"), "envelope.fill", "invitation symbol")
    expectEqual(RadarPresenter.reasonLabel("your_activity"), "your activity", "your_activity label")
}

// MARK: - Inbound (derived reason) — opened on a repo you OWN (user call 2026-07-09)

suite("SignalClassifier — inbound derivation (subscribed ∧ PR/Issue ∧ owner == you)") {
    func mk(_ id: String, reason: String = "subscribed", type: String = "PullRequest",
            owner: String = "provi", ownerType: String = "User", state: String? = nil,
            title: String = "Add dark theme", commenter: String? = nil,
            url: String? = nil, commentUrl: String? = nil) -> NotificationThread {
        let s = state.map { ",\"subject_state\":\"\($0)\"" } ?? ""
        let c = commenter.map { ",\"latest_comment_author_login\":\"\($0)\"" } ?? ""
        let u = url.map { "\"\($0)\"" } ?? "null"
        let cu = commentUrl.map { "\"\($0)\"" } ?? "null"
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"t\"\(c),"
            + "\"subject\":{\"title\":\"\(title)\",\"type\":\"\(type)\",\"url\":\(u),\"latest_comment_url\":\(cu)}\(s),"
            + "\"repository\":{\"full_name\":\"\(owner)/githud\",\"private\":false,\"owner\":{\"login\":\"\(owner)\",\"type\":\"\(ownerType)\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!.first!
    }

    // The predicate — deliberately narrow.
    expect(SignalClassifier.isInboundOnOwnRepo(mk("pr"), selfLogin: "provi"), "PR opened on your repo → inbound")
    expect(SignalClassifier.isInboundOnOwnRepo(mk("is", type: "Issue"), selfLogin: "provi"), "issue too")
    expect(SignalClassifier.isInboundOnOwnRepo(mk("cs"), selfLogin: "Provi"), "login match is case-insensitive")
    expect(!SignalClassifier.isInboundOnOwnRepo(mk("rl", type: "Release"), selfLogin: "provi"), "a Release on your repo stays firehose")
    expect(!SignalClassifier.isInboundOnOwnRepo(mk("fo", owner: "acme", ownerType: "Organization"), selfLogin: "provi"), "someone else's repo is never inbound (org scope = future config)")
    expect(!SignalClassifier.isInboundOnOwnRepo(mk("nl"), selfLogin: nil), "no resolved selfLogin → never inbound (ownership is not guessed)")
    expect(!SignalClassifier.isInboundOnOwnRepo(mk("mn", reason: "mention"), selfLogin: "provi"), "only the subscribed firehose derives")

    // Classification: action-required, slotted just under `author` activity.
    let pr = SignalClassifier.classify(mk("pr"), selfLogin: "provi")
    let issue = SignalClassifier.classify(mk("is", type: "Issue"), selfLogin: "provi")
    expectEqual(pr.actionClass, .actionRequired, "inbound PR is action-required (triage is a needs-you fact)")
    expectEqual(pr.urgency, 62, "inbound PR at 62 — just under `author` PR activity (65)")
    expectEqual(issue.urgency, 52, "inbound issue at 52 — just under `author` issue activity (55)")
    expectEqual(pr.rationale, "new PR opened on your repo", "plainspoken rationale (PR)")
    let bot = SignalClassifier.classify(mk("bt", commenter: "dependabot[bot]"), selfLogin: "provi")
    expectEqual(bot.actionClass, .noise, "automation opening on your repo stays demoted (security_alert covers the critical path)")
    let foreign = SignalClassifier.classify(mk("fo", owner: "acme", ownerType: "Organization"), selfLogin: "provi")
    expectEqual(foreign.urgency, 0, "subscribed on a foreign repo keeps the firehose demotion")

    // Surfacing: default ON; honest when the login is unresolved; user choice honored.
    expect(SurfacePreferences.autoReasons.contains(SignalClassifier.inboundReason), "inbound is default-ON (user call)")
    expect(SurfacePreferences.auto.surfaces(mk("pr"), selfLogin: "provi"), "auto surfaces an inbound PR")
    expect(!SurfacePreferences.auto.surfaces(mk("pr"), selfLogin: nil), "unresolved login → still suppressed (auditable, not fabricated)")
    expect(!SurfacePreferences.auto.surfaces(mk("cl", state: "closed"), selfLogin: "provi"), "a closed inbound PR is already handled → suppressed")
    expect(!SurfacePreferences.auto.surfaces(mk("bt", commenter: "renovate[bot]"), selfLogin: "provi"), "bot-opened inbound stays suppressed")
    let noInbound = SurfacePreferences(enabledReasons: ["review_requested", "mention"])
    expect(!noInbound.surfaces(mk("pr"), selfLogin: "provi"), "a custom set without inbound is honored (toggle just appears unchecked)")
    let firehose = SurfacePreferences(enabledReasons: ["subscribed"])
    expect(firehose.surfaces(mk("pr"), selfLogin: "provi"), "the raw-subscribed door still admits inbound (derivation only ADDS surface)")
    expect(firehose.surfaces(mk("fo", owner: "acme", ownerType: "Organization"), selfLogin: "provi"), "…and the plain firehose it always admitted")

    // The radar carries the derived reason; the row displays it (never \"subscribed\").
    let ranked = SignalClassifier.radar([mk("pr")], selfLogin: "provi")
    expectEqual(ranked.first?.effectiveReason, "inbound", "RankedThread carries the effective reason")
    if let item = ranked.first {
        let row = RadarPresenter.row(for: item, now: Date(timeIntervalSince1970: 1_800_000_000))
        expect(row.subtitle.contains("opened on your repo"), "row subtitle speaks the derived reason")
        expectEqual(row.symbolName, "tray.and.arrow.down.fill", "inbound glyph — an arriving tray, ink like every non-critical row")
    }
    let suppressed = SignalClassifier.suppressed([mk("pr")], selfLogin: nil)
    expectEqual(suppressed.first?.effectiveReason, "subscribed", "unresolved login: the suppressed set shows the honest raw reason")

    // Store rehydration: yesterday's persisted auto-defaults follow auto forward.
    expectEqual(SurfacePreferences.fromStored(SurfacePreferences.legacyAutoReasonsV1), .auto,
                "a stored pre-inbound auto set migrates to auto (inbound arrives default-on)")
    expect(SurfacePreferences.fromStored(SurfacePreferences.legacyAutoReasonsV1).isEnabled("inbound"), "…with inbound enabled")
    let custom: Set<String> = ["review_requested", "security_alert"]
    expectEqual(SurfacePreferences.fromStored(custom).enabledReasons, custom, "a real custom set is honored verbatim")
    expectEqual(SurfacePreferences.fromStored([]).enabledReasons, [], "an everything-off choice stays everything-off")
    expectEqual(SurfacePreferences.autoReasons,
                SurfacePreferences.legacyAutoReasonsV1.union([SignalClassifier.inboundReason]),
                "auto = the legacy auto set + inbound, exactly (nothing else rode along)")

    // Enrichment gates (fix round 1, trust MAJOR): inbound joins BOTH honesty passes
    // through the REAL pipeline predicates — not fixture-injected fields.
    let fresh = mk("en1", url: "https://api.github.com/repos/provi/githud/pulls/7",
                   commentUrl: "https://api.github.com/repos/provi/githud/issues/comments/1")
    expect(SignalClassifier.needsSubjectState(fresh, selfLogin: "provi"),
           "an inbound thread EARNS subject-state enrichment (merged/closed must drop it off)")
    expect(SignalClassifier.needsCommentAuthor(fresh, selfLogin: "provi"),
           "…and comment-author enrichment (bot demotion beyond the title heuristic)")
    expect(!SignalClassifier.needsSubjectState(fresh, selfLogin: nil),
           "no resolved login → no inbound enrichment spend")
    let foreignFresh = mk("en2", owner: "acme", ownerType: "Organization",
                          url: "https://api.github.com/repos/acme/x/pulls/7",
                          commentUrl: "https://api.github.com/repos/acme/x/issues/comments/1")
    expect(!SignalClassifier.needsSubjectState(foreignFresh, selfLogin: "provi"),
           "the foreign subscribed firehose still never spends the budget")
    expect(!SignalClassifier.needsSubjectState(
               mk("en3", state: "merged", url: "https://api.github.com/repos/provi/githud/pulls/8"),
               selfLogin: "provi"),
           "already-resolved subject state → no re-fetch")
    expect(!SignalClassifier.needsCommentAuthor(
               mk("en4", commenter: "alice",
                  commentUrl: "https://api.github.com/repos/provi/githud/issues/comments/2"),
               selfLogin: "provi"),
           "already-known comment author → no re-fetch")

    // The change key rides the EFFECTIVE reason (fix round 1): a subscribed→inbound flip
    // (self-login resolving) is a display change and must move the key.
    let sameThread = mk("ck1")
    let keyWithoutLogin = RadarPresenter.changeKey(for: SignalClassifier.suppressed([sameThread], selfLogin: nil))
    let keyWithLogin = RadarPresenter.changeKey(for: SignalClassifier.radar([sameThread], selfLogin: "provi"))
    expect(keyWithoutLogin != keyWithLogin, "subscribed→inbound flip moves the change key (repaint guaranteed)")

    // Novelty stays judged against GitHub's OWN enumeration (fix round 1): a hypothetical
    // raw GitHub reason spelled "inbound" walks the novel door even with the toggle off.
    let rawInbound = mk("nv1", reason: "inbound", owner: "acme", ownerType: "Organization")
    let inboundOff = SurfacePreferences(enabledReasons: ["review_requested"])
    expect(inboundOff.surfaces(rawInbound, selfLogin: nil),
           "a raw novel reason can never hide behind the derived toggle (never-miss)")
}

// MARK: - Inbound sweep (standing "at your door" lane — WP 2026-07-09-001)

suite("InboundItem — decode the REAL search response (committed fixture)") {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/inbound-search.json")
    guard let data = try? Data(contentsOf: url),
          let reading = try? InboundItem.reading(fromSearchData: data) else {
        expect(false, "decode Fixtures/inbound-search.json"); return
    }
    expectEqual(reading.items.count, 8, "8 items decoded (5 human + 3 bot, live-cut 2026-07-09)")
    expectEqual(reading.totalCount, 8, "total_count carried")
    expect(!reading.incomplete, "the live cut was a complete reading")
    if let dec = reading.items.first(where: { $0.number == 1 && $0.repo == "pro-vi/mcp-filter" }) {
        expect(dec.isPR, "mcp-filter#1 is a PR (pull_request key present)")
        expectEqual(dec.authorLogin, "arun", "opener decoded")
        expect(!dec.isBot, "a human opener")
        expect(dec.createdAt.hasPrefix("2025-12-29"), "the December PR — the founding story")
    } else { expect(false, "mcp-filter#1 present") }
    if let iss = reading.items.first(where: { !$0.isPR }) {
        expect(!iss.isDraft, "issues are never drafts (absent field → false)")
        expectEqual(InboundPresenter.symbolName(isPR: iss.isPR), "dot.circle", "issue glyph")
    } else { expect(false, "at least one issue in the fixture") }
    expectEqual(reading.items.filter(\.isBot).count, 3, "3 bot-opened (dependabot ×2 + actions)")
    expect(reading.items.allSatisfy { $0.repo.hasPrefix("pro-vi/") }, "repos derived from repository_url")
}

suite("InboundReading — the honest-adoption rule (incomplete never removes)") {
    func item(_ n: Int) -> InboundItem {
        InboundItem(repo: "o/r", number: n, title: "t\(n)", url: "u", authorLogin: "a",
                    authorType: "User", isPR: true, isDraft: false,
                    createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-01T00:00:00Z")
    }
    let full = InboundReading(items: [item(1), item(2)], incomplete: false, totalCount: 2)
    let partial = InboundReading(items: [item(1)], incomplete: true, totalCount: 1)
    let closedOne = InboundReading(items: [item(2)], incomplete: false, totalCount: 1)
    expectEqual(InboundReading.adopt(previous: full, new: partial), full,
                "a timed-out search never removes items (dropping a row would fabricate 'handled')")
    expectEqual(InboundReading.adopt(previous: full, new: closedOne), closedOne,
                "a COMPLETE reading removes what genuinely closed")
    expectEqual(InboundReading.adopt(previous: nil, new: partial), partial,
                "partial beats blank when there is nothing prior (each item is still a true fact)")
}

suite("InboundPresenter — triage-queue order, held-back split, honest ages") {
    func item(_ n: Int, created: String, author: String = "human", type: String = "User",
              pr: Bool = true, draft: Bool = false) -> InboundItem {
        InboundItem(repo: "pro-vi/x", number: n, title: "Title \(n)", url: "https://github.com/pro-vi/x/pull/\(n)",
                    authorLogin: author, authorType: type, isPR: pr, isDraft: draft,
                    createdAt: created, updatedAt: "2026-07-09T00:00:00Z")
    }
    let items = [
        item(3, created: "2026-07-01T00:00:00Z"),
        item(1, created: "2025-12-29T00:00:00Z"),                        // waited longest
        item(4, created: "2026-07-06T00:00:00Z", author: "dependabot[bot]", type: "Bot"),
        item(2, created: "2026-01-14T00:00:00Z"),
        item(5, created: "2026-07-08T00:00:00Z", draft: true),           // human draft → held back
    ]
    let s = InboundPresenter.sections(for: items)
    expectEqual(s.active.map(\.id), ["pro-vi/x#1", "pro-vi/x#2", "pro-vi/x#3"],
                "active = human non-draft, WAITING-LONGEST first (a queue, not a feed)")
    expectEqual(s.heldBack.map(\.id), ["pro-vi/x#4", "pro-vi/x#5"],
                "bots + drafts held back to the quiet caption group")
    let flat = InboundPresenter.rows(for: items)
    expectEqual(InboundPresenter.sections(for: flat).active.map(\.id), s.active.map(\.id),
                "presented rows regroup by their carried flag (flat spine round-trips)")

    let dec = s.active[0]
    expectEqual(dec.timestamp, "2025-12-29T00:00:00Z", "row age keys off WAITING-SINCE (createdAt)")
    let now = ISO8601DateFormatter().date(from: "2026-07-09T00:00:00Z")!
    let line = InboundPresenter.displaySubtitle(for: dec, now: now)
    expect(line.hasPrefix("pro-vi/x #1 · @human · "), "rendered line: repo · opener · age")
    expect(line.hasSuffix("w"), "a December opener reads in WEEKS — the honest debt")
    expect(!dec.subtitle.contains("PR"), "kind is NOT restated in text — the glyph carries it")
    expectEqual(s.heldBack.last?.subtitle, "@human · draft", "draft named in the subtitle")

    // Change key: DISPLAYED facts only — updatedAt is deliberately excluded (fix round:
    // nothing rendered reads it; including it repainted identical lanes + dropped peeks).
    let k1 = InboundPresenter.changeKey(for: items)
    let touched = items.map { i in
        InboundItem(repo: i.repo, number: i.number, title: i.title, url: i.url,
                    authorLogin: i.authorLogin, authorType: i.authorType, isPR: i.isPR,
                    isDraft: i.isDraft, createdAt: i.createdAt, updatedAt: "2099-01-01T00:00:00Z")
    }
    expectEqual(InboundPresenter.changeKey(for: touched), k1, "updatedAt alone never moves the key")
    expect(InboundPresenter.row(for: items[0]).changeSignature ==
           InboundPresenter.row(for: touched[0]).changeSignature,
           "…and never collapses an open peek (signature is displayed-text only)")
}

suite("PollReducer.sweptInbound — the lane's spine contract (render on change, last-good on failure)") {
    func item(_ n: Int, updated: String = "2026-07-09T00:00:00Z") -> InboundItem {
        InboundItem(repo: "pro-vi/x", number: n, title: "T\(n)", url: "u", authorLogin: "a",
                    authorType: "User", isPR: true, isDraft: false,
                    createdAt: "2026-07-01T00:00:00Z", updatedAt: updated)
    }
    func reading(_ items: [InboundItem], incomplete: Bool = false) -> InboundReading {
        InboundReading(items: items, incomplete: incomplete, totalCount: items.count)
    }
    let now = ISO8601DateFormatter().date(from: "2026-07-09T12:00:00Z")!
    // First sweep renders + adopts the key + stamps the confirmation fact.
    let (s1, e1) = PollReducer.reduce(.sweptInbound(.success(reading([item(1)]))), state: PollReducer.PollState(), now: now)
    expectEqual(e1, [.renderInbound(InboundPresenter.rows(for: [item(1)]))], "first sweep renders the lane")
    expect(s1.lastInboundKey != nil, "key adopted")
    expectEqual(s1.lastInboundSuccessAt, now, "a COMPLETE sweep stamps the confirmation fact")
    // An INCOMPLETE sweep shows its true items but never confirms (the affirmation's gate).
    let (sInc, _) = PollReducer.reduce(.sweptInbound(.success(reading([item(9)], incomplete: true))),
                                       state: PollReducer.PollState(), now: now)
    expect(sInc.lastInboundSuccessAt == nil, "an incomplete sweep withholds confirmation")
    expect(sInc.lastRenderedInbound != nil, "…while its true items still render")
    // Identical sweep: silent (idle-footprint).
    let (s2, e2) = PollReducer.reduce(.sweptInbound(.success(reading([item(1)]))), state: s1, now: now)
    expect(e2.isEmpty, "identical sweep renders nothing")
    // Upstream ACTIVITY alone (updatedAt) changes nothing displayed → stays silent
    // (fix round: updatedAt is out of the change key — no invisible repaints, no
    // silently-collapsed peeks on a change the user cannot see).
    let (_, e3) = PollReducer.reduce(.sweptInbound(.success(reading([item(1, updated: "2026-07-09T06:00:00Z")]))), state: s2, now: now)
    expect(e3.isEmpty, "activity that changes nothing displayed does NOT re-render")
    // A displayed change (title) still re-renders.
    var renamed = item(1); _ = renamed
    let titled = InboundItem(repo: "pro-vi/x", number: 1, title: "Renamed", url: "u", authorLogin: "a",
                             authorType: "User", isPR: true, isDraft: false,
                             createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-09T00:00:00Z")
    let (_, e3b) = PollReducer.reduce(.sweptInbound(.success(reading([titled]))), state: s2, now: now)
    expectEqual(e3b.count, 1, "a title edit re-renders")
    // Failure: keep last-good, render nothing (never flicker-to-empty).
    let (s4, e4) = PollReducer.reduce(.sweptInbound(.failure(.transport("x"))), state: s2, now: now)
    expect(e4.isEmpty && s4.lastRenderedInbound == s2.lastRenderedInbound, "failure keeps the last-good lane whole")
    // Age-bucket flip: re-renders ONLY while expanded (a collapsed flip is invisible churn).
    var expanded = s2; expanded.expanded = true
    let muchLater = ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!
    let (_, e5) = PollReducer.reduce(.sweptInbound(.success(reading([item(1)]))), state: expanded, now: muchLater)
    expectEqual(e5.count, 1, "expanded + age bucket flipped → re-render same rows")
    let (_, e6) = PollReducer.reduce(.sweptInbound(.success(reading([item(1)]))), state: s2, now: muchLater)
    expect(e6.isEmpty, "collapsed age flip stays silent")
}

suite("CaughtUp × Inbound — the affirmation never claims caught-up over a standing queue") {
    let display = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                            freshness: .fresh, inboundActive: 1, inboundConfirmed: true, reviewsConfirmed: true)
    expectEqual(display, .none, "one waiting contributor gates BOTH affirmation forms")
    let clear = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                          freshness: .fresh, inboundActive: 0, inboundConfirmed: true, reviewsConfirmed: true)
    expect(clear != .none, "a CONFIRMED-empty queue leaves the affirmation as ratified")
    let unswept = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                            freshness: .fresh, inboundActive: 0, inboundConfirmed: false)
    expectEqual(unswept, .none, "an empty-LOOKING queue that was never fully read cannot affirm (fail-closed)")
    // Reviews gate (WP 2026-07-17-002): same fail-closed shape as inbound — the
    // affirmation is withheld until the reviews-owed sweep has ACTUALLY completed.
    // The default is false, so every pre-WP call site went silent, not falsely clear.
    let reviewsUnswept = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                                   freshness: .fresh, inboundActive: 0, inboundConfirmed: true)
    expectEqual(reviewsUnswept, .none, "an unswept reviews lane cannot affirm (fail-closed default)")
    // Held-back-only inbound (bots/drafts) does NOT gate — the ACTIVE count is the fact.
    // (The caller passes sections.active.count; this pins the contract's input meaning.)
    let ids = KeySession.actionableIDs(
        radar: [], pulse: [], showDrafts: false, showStale: false,
        inbound: InboundPresenter.rows(for: [
            InboundItem(repo: "o/r", number: 1, title: "t", url: "u", authorLogin: "h",
                        authorType: "User", isPR: true, isDraft: false,
                        createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-01T00:00:00Z"),
            InboundItem(repo: "o/r", number: 2, title: "t", url: "u", authorLogin: "dependabot[bot]",
                        authorType: "Bot", isPR: true, isDraft: false,
                        createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T00:00:00Z"),
        ]), showHeldBackInbound: false)
    expectEqual(ids, ["o/r#1"], "ink bar walks the active inbound queue; held-back only when revealed")

    // The PILL (fix round, drift BLOCKER): the queue outranks the all-clear on the
    // most-visible surface too — drawn (tray + count via the ratified radar-glyph cell)
    // and spoken in parity. The STANDING queue now draws the still-life `tray.fill`
    // (D-pill tense split — the arriving-knock radar reason keeps `tray.and.arrow.down.fill`).
    let waiting = PillMorph.fingerprint(rows: [], pulse: [], loading: false,
                                        freshness: .fresh, inboundActive: 3)
    expectEqual(waiting.glyph, .radar(symbol: "tray.fill", critical: false),
                "a waiting queue draws the standing tray (tray.fill), never the check")
    expectEqual(waiting.value, .count("3"), "…with the count")
    let clearPill = PillMorph.fingerprint(rows: [], pulse: [], loading: false,
                                          freshness: .fresh, inboundActive: 0, clearConfirmed: true)
    expectEqual(clearPill.glyph, .check, "an empty queue keeps the ratified check")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], loading: false, inboundActive: 3),
                "3 waiting at your door", "spoken parity with the drawn tray+count")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], loading: false, inboundActive: 0,
                                                 clearConfirmed: true),
                CaughtUpPresenter.caughtUpLine, "an empty queue keeps the shared caught-up line")
}

// MARK: - PullRequestPulse (H2 — the ambient pulse lane, iter 25)

func pulse(ci: CIState = .passing, review: ReviewState = .approved, merge: MergeState = .mergeable,
           draft: Bool = false, created: String = "2026-06-16T10:00:00Z",
           updated: String = "2026-06-16T10:00:00Z") -> PullRequestPulse {
    PullRequestPulse(repo: "o/r", number: 1, title: "t", url: "u", isDraft: draft,
                     createdAt: created, updatedAt: updated, ci: ci, review: review, merge: merge)
}

suite("PullRequestPulse — honest enum mappers (null/unknown never fabricate green)") {
    expectEqual(PullRequestPulse.ciState(fromRollup: "SUCCESS"), .passing, "SUCCESS → passing")
    expectEqual(PullRequestPulse.ciState(fromRollup: "FAILURE"), .failing, "FAILURE → failing")
    expectEqual(PullRequestPulse.ciState(fromRollup: "ERROR"), .failing, "ERROR → failing")
    expectEqual(PullRequestPulse.ciState(fromRollup: "PENDING"), .pending, "PENDING → pending")
    expectEqual(PullRequestPulse.ciState(fromRollup: nil), CIState.none, "null rollup → none (NOT passing)")
    expectEqual(PullRequestPulse.reviewState(fromDecision: "APPROVED"), .approved, "APPROVED")
    expectEqual(PullRequestPulse.reviewState(fromDecision: "CHANGES_REQUESTED"), .changesRequested, "CHANGES_REQUESTED")
    expectEqual(PullRequestPulse.reviewState(fromDecision: "REVIEW_REQUIRED"), .reviewRequired, "REVIEW_REQUIRED")
    expectEqual(PullRequestPulse.reviewState(fromDecision: nil), ReviewState.none, "null decision → none (NOT approved)")
    // review F10: an UNRECOGNIZED non-null decision (API drift) must fail safe to
    // reviewRequired — NOT none (which is ready-eligible). Mirrors the CI mapper.
    expectEqual(PullRequestPulse.reviewState(fromDecision: "DISMISSED"), .reviewRequired, "drift review decision → reviewRequired (NOT none) [F10]")
    expectEqual(PullRequestPulse.reviewState(fromDecision: "WAT_2027"), .reviewRequired, "any unrecognized non-null review → reviewRequired (fail safe)")
    expectEqual(PullRequestPulse.mergeState(fromMergeable: "MERGEABLE"), .mergeable, "MERGEABLE")
    expectEqual(PullRequestPulse.mergeState(fromMergeable: "CONFLICTING"), .conflicting, "CONFLICTING")
    expectEqual(PullRequestPulse.mergeState(fromMergeable: "UNKNOWN"), .unknown, "UNKNOWN → unknown (NEVER ready)")
    expectEqual(PullRequestPulse.mergeState(fromMergeable: nil), .unknown, "null mergeable → unknown")
}

suite("PullRequestPulse — PulseState priority lattice (the composition matrix, per cell)") {
    expectEqual(pulse(ci: .passing, review: .approved, merge: .mergeable).state, .ready, "passing·approved·mergeable → ready")
    expectEqual(pulse(ci: .failing, review: .approved, merge: .mergeable).state, .blocked, "failing CI → blocked")
    expectEqual(pulse(ci: .passing, review: .changesRequested, merge: .mergeable).state, .blocked, "changes requested → blocked")
    expectEqual(pulse(ci: .passing, review: .approved, merge: .conflicting).state, .blocked, "conflicting → blocked")
    expectEqual(pulse(ci: .passing, review: .reviewRequired, merge: .mergeable).state, .waiting, "review required → waiting")
    expectEqual(pulse(ci: .pending, review: .approved, merge: .mergeable).state, .waiting, "CI pending → waiting")
    expectEqual(pulse(ci: .passing, review: .approved, merge: .unknown).state, .waiting, "merge unknown → waiting (NOT ready)")
    expectEqual(pulse(ci: CIState.none, review: .approved, merge: .mergeable).state, .ready, "no checks + approved + mergeable → ready")
    expectEqual(pulse(ci: .passing, review: ReviewState.none, merge: .mergeable).state, .ready, "no review required → ready")
    expectEqual(pulse(ci: .passing, review: .approved, merge: .mergeable, draft: true).state, .draft, "draft → draft")
    expectEqual(pulse(ci: .failing, review: .approved, merge: .mergeable, draft: true).state, .blocked, "draft + failing → blocked (blocked beats draft)")
}

suite("PullRequestPulse — GraphQL decode (nested response → flat model; errors surface)") {
    let ok = """
    {"data":{"viewer":{"pullRequests":{"nodes":[
      {"number":7,"title":"Add caching","url":"https://github.com/o/r/pull/7","isDraft":false,"updatedAt":"2026-06-16T09:00:00Z","reviewDecision":"APPROVED","mergeable":"MERGEABLE","repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
      {"number":8,"title":"WIP","url":"https://github.com/o/r/pull/8","isDraft":true,"updatedAt":"2026-06-16T08:00:00Z","reviewDecision":null,"mergeable":"UNKNOWN","repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
    ]}}}}
    """
    let pulses = (try? PullRequestPulse.list(fromGraphQLData: Data(ok.utf8))) ?? []
    expectEqual(pulses.count, 2, "decoded 2 PRs")
    if pulses.count == 2 {
        expectEqual(pulses[0].number, 7, "number decoded")
        expectEqual(pulses[0].repo, "o/r", "nameWithOwner → repo")
        expectEqual(pulses[0].ci, .passing, "SUCCESS rollup → passing")
        expectEqual(pulses[0].state, .ready, "first PR ready")
        expectEqual(pulses[1].ci, CIState.none, "null rollup → none")
        expectEqual(pulses[1].merge, .unknown, "UNKNOWN mergeable decoded")
        expectEqual(pulses[1].state, .draft, "second PR draft")
    }
    let empty = """
    {"data":{"viewer":{"pullRequests":{"nodes":[]}}}}
    """
    expectEqual((try? PullRequestPulse.list(fromGraphQLData: Data(empty.utf8)))?.count ?? -1, 0, "empty nodes → []")
    let errBody = """
    {"errors":[{"message":"Bad credentials"}]}
    """
    var threw = false
    do { _ = try PullRequestPulse.list(fromGraphQLData: Data(errBody.utf8)) } catch { threw = true }
    expect(threw, "GraphQL errors body throws (not a silent zero-PR result)")
    // review: GitHub can return BOTH partial data AND errors[] (HTTP 200). The partial set
    // must NOT render as authoritative — any top-level error degrades the whole pulse.
    let partial = """
    {"data":{"viewer":{"pullRequests":{"nodes":[
      {"number":7,"title":"t","url":"u","isDraft":false,"updatedAt":"t","reviewDecision":"APPROVED","mergeable":"MERGEABLE","repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}
    ]}}},"errors":[{"message":"timeout resolving another field"}]}
    """
    var partialThrew = false
    do { _ = try PullRequestPulse.list(fromGraphQLData: Data(partial.utf8)) } catch { partialThrew = true }
    expect(partialThrew, "data + errors[] (partial failure) throws — never renders partial as authoritative truth")
}

suite("changeKey — redraw on any real change, not on age tick (locks review F3/F4)") {
    // RADAR: same id but an in-place escalation (newer updatedAt, or changed title) must
    // change the key so the island re-renders. Identical input → identical key (no churn).
    func radarKey(id: String, updated: String, title: String = "t") -> [String] {
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"\(updated)\",\"subject\":{\"title\":\"\(title)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
        return RadarPresenter.changeKey(for: SignalClassifier.radar(threads))
    }
    expect(radarKey(id: "a", updated: "2026-06-16T09:00:00Z") == radarKey(id: "a", updated: "2026-06-16T09:00:00Z"), "identical thread → identical key (no needless redraw)")
    expect(radarKey(id: "a", updated: "2026-06-16T09:00:00Z") != radarKey(id: "a", updated: "2026-06-16T10:00:00Z"), "same id, newer updatedAt (in-place escalation) → key differs → redraws")
    expect(radarKey(id: "a", updated: "t", title: "old") != radarKey(id: "a", updated: "t", title: "new"), "same id, changed title → key differs")

    // PULSE: the exact silent-miss — a blocked DRAFT becoming a blocked NON-draft keeps
    // state == .blocked, so the old repo#num:state key was identical. The full key must differ.
    let blockedDraft = pulse(ci: .failing, review: .approved, merge: .mergeable, draft: true)   // state .blocked, isDraft true
    let blockedLive  = pulse(ci: .failing, review: .approved, merge: .mergeable, draft: false)  // state .blocked, isDraft false
    expectEqual(blockedDraft.state, blockedLive.state, "both are .blocked (blocked beats draft) — state alone can't tell them apart")
    expect(PulsePresenter.changeKey(for: [blockedDraft]) != PulsePresenter.changeKey(for: [blockedLive]), "blocked-draft → blocked-live (isDraft flip, same state) → key differs → redraws")
    expect(PulsePresenter.changeKey(for: [blockedLive]) == PulsePresenter.changeKey(for: [blockedLive]), "identical pulse → identical key (no churn)")
}

suite("PullRequestPulse v2 — CI honesty: API drift never false-certifies green (iter 26)") {
    expectEqual(PullRequestPulse.ciState(fromRollup: nil), CIState.none, "null rollup → none (genuinely no checks)")
    expectEqual(PullRequestPulse.ciState(fromRollup: "SUCCESS"), .passing, "SUCCESS unchanged → passing")
    expectEqual(PullRequestPulse.ciState(fromRollup: "NEUTRAL"), .pending, "drift NEUTRAL → pending (NOT none)")
    expectEqual(PullRequestPulse.ciState(fromRollup: "SKIPPED"), .pending, "drift SKIPPED → pending (fail safe)")
    expectEqual(PullRequestPulse.ciState(fromRollup: "WAT_NEW_2027"), .pending, "any unrecognized non-null → pending")
    // the rollup: a drift CI + approved + mergeable must NOT be ready
    let drift = PullRequestPulse(repo: "o/r", number: 1, title: "t", url: "u", isDraft: false,
        createdAt: "2026-06-16T10:00:00Z", updatedAt: "2026-06-16T10:00:00Z",
        ci: PullRequestPulse.ciState(fromRollup: "NEUTRAL"), review: .approved, merge: .mergeable)
    expectEqual(drift.state, .waiting, "drift CI + approved + mergeable → waiting, NOT ready (no false green)")
    // contrast: genuinely no checks IS ready-eligible (honest)
    let noChecks = PullRequestPulse(repo: "o/r", number: 2, title: "t", url: "u", isDraft: false,
        createdAt: "2026-06-16T10:00:00Z", updatedAt: "2026-06-16T10:00:00Z",
        ci: PullRequestPulse.ciState(fromRollup: nil), review: .approved, merge: .mergeable)
    expectEqual(noChecks.state, .ready, "null rollup (no checks) + approved + mergeable → ready (honest)")
    // review F10: a drift review decision + passing CI + mergeable must NOT be ready either.
    let driftReview = PullRequestPulse(repo: "o/r", number: 3, title: "t", url: "u", isDraft: false,
        createdAt: "2026-06-16T10:00:00Z", updatedAt: "2026-06-16T10:00:00Z",
        ci: .passing, review: PullRequestPulse.reviewState(fromDecision: "DISMISSED"), merge: .mergeable)
    expectEqual(driftReview.state, .waiting, "drift review + passing + mergeable → waiting, NOT ready (no false green)")
}

suite("GitHubClient — Link rel=next pagination (never-miss: page 2+ is not dropped) [F1]") {
    let two = "<https://api.github.com/notifications?page=2&per_page=50>; rel=\"next\", <https://api.github.com/notifications?page=5&per_page=50>; rel=\"last\""
    expectEqual(GitHubClient.parseNextLink(two), "https://api.github.com/notifications?page=2&per_page=50", "extracts the rel=next URL")
    // last page: only prev/first/last, NO next → nil (stop paginating)
    let lastPage = "<https://api.github.com/notifications?page=4&per_page=50>; rel=\"prev\", <https://api.github.com/notifications?page=1&per_page=50>; rel=\"first\""
    expect(GitHubClient.parseNextLink(lastPage) == nil, "no rel=next on the last page → nil")
    expect(GitHubClient.parseNextLink(nil) == nil, "no Link header → nil")
    expect(GitHubClient.parseNextLink("") == nil, "empty Link header → nil")
}

// MARK: - PulsePresenter (H2 lane rows, iter 25)

suite("PulsePresenter — subtitle names the salient members (composition is visible; age NOT baked)") {
    // The subtitle is now AGELESS (age formatted at render from `timestamp`); this suite pins the
    // composition members. The render-time age is proven by the displaySubtitle suite below.
    func sub(_ ci: CIState, _ r: ReviewState, _ m: MergeState, draft: Bool = false) -> String {
        PulsePresenter.subtitle(for: PullRequestPulse(repo: "o/r", number: 1, title: "t", url: "u",
            isDraft: draft, createdAt: "2026-06-16T08:00:00Z", updatedAt: "2026-06-16T08:00:00Z",
            ci: ci, review: r, merge: m))
    }
    expectEqual(sub(.passing, .approved, .mergeable), "CI passing · approved", "ready PR: CI + review (mergeable implied); no baked age")
    expectEqual(sub(.failing, .approved, .mergeable), "CI failing · approved", "failing CI named")
    expectEqual(sub(CIState.none, .approved, .mergeable), "no checks · approved", "no checks ≠ passing")
    expectEqual(sub(.passing, .changesRequested, .mergeable), "CI passing · changes requested", "changes requested named")
    expectEqual(sub(.passing, .approved, .conflicting), "CI passing · approved · conflicts", "conflicts always surfaced")
    expectEqual(sub(.passing, .approved, .unknown), "CI passing · approved · checking…", "unknown merge → checking…")
    expectEqual(sub(.passing, ReviewState.none, .mergeable), "CI passing", "no-review-required omits the review part")
    expectEqual(sub(.passing, .approved, .mergeable, draft: true), "CI passing · approved · draft", "draft labeled")
}

suite("PulsePresenter — displaySubtitle appends the render-time age; row carries the raw timestamp (WP-1c) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let pr = PullRequestPulse(repo: "o/r", number: 7, title: "Add caching", url: "u", isDraft: false,
        createdAt: "2026-06-16T08:00:00Z", updatedAt: "2026-06-16T08:00:00Z", ci: .passing, review: .approved, merge: .mergeable)
    let row = PulsePresenter.row(for: pr, now: now)
    expectEqual(row.timestamp, "2026-06-16T08:00:00Z", "pulse row carries the raw ISO timestamp")
    expectEqual(row.subtitle, "CI passing · approved", "stored subtitle is ageless")
    expectEqual(PulsePresenter.displaySubtitle(for: row, now: now), "o/r #7 · CI passing · approved · 2h", "displaySubtitle appends age (repo#n · subtitle · age)")
    // Same row, +6h → 8h: no baked-string staleness (mirrors the radar proof).
    expectEqual(PulsePresenter.displaySubtitle(for: row, now: iso.date(from: "2026-06-16T16:00:00Z")!), "o/r #7 · CI passing · approved · 8h", "SAME row, +6h → 8h")
    // ageSignature flips across the pulse lane's hour boundary too.
    expect(PulsePresenter.ageSignature(for: [row], now: iso.date(from: "2026-06-16T10:59:59Z")!)
        != PulsePresenter.ageSignature(for: [row], now: iso.date(from: "2026-06-16T11:00:00Z")!), "2h→3h flips the pulse signature")
}

suite("PulsePresenter — symbols + rows sort blocked > ready > waiting > draft") {
    expectEqual(PulsePresenter.symbolName(for: .blocked), "exclamationmark.triangle.fill", "blocked glyph")
    expectEqual(PulsePresenter.symbolName(for: .ready), "checkmark.circle.fill", "ready glyph")
    expectEqual(PulsePresenter.symbolName(for: .waiting), "clock.fill", "waiting glyph")
    expectEqual(PulsePresenter.symbolName(for: .draft), "pencil.circle", "draft glyph")

    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    // created defaults OLD (a month back) so these are SETTLED PRs — this suite tests the
    // pure state ordering; the fresh-boost + stale partition get their own suite below.
    func p(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState, draft: Bool = false,
           at: String, created: String = "2026-05-16T10:00:00Z") -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: created, updatedAt: at, ci: ci, review: r, merge: m)
    }
    let pulses = [
        p(1, .passing, .approved, .mergeable, at: "2026-06-16T09:00:00Z"),       // ready
        p(2, .failing, .approved, .mergeable, at: "2026-06-16T08:00:00Z"),       // blocked
        p(3, .passing, .reviewRequired, .mergeable, at: "2026-06-16T07:00:00Z"), // waiting
        p(4, .passing, .approved, .mergeable, draft: true, at: "2026-06-16T06:00:00Z"), // draft
    ]
    let rows = PulsePresenter.rows(for: pulses, now: now)
    expectEqual(rows.map { $0.state }, [.blocked, .ready, .waiting, .draft], "sorted worst-first")
    expectEqual(rows.first?.repo, "o/r #2", "blocked PR leads, repo carries the number")

    let gauge = PulsePresenter.gauge(rows: rows)
    expectEqual(gauge?.ready, 1, "gauge ready=1")
    expectEqual(gauge?.blocked, 1, "gauge blocked=1")
    expectEqual(gauge?.waiting, 1, "gauge waiting=1 (draft excluded)")
    expectEqual(gauge?.segments.count, 2, "segments = ✓ready + ⚠blocked (waiting omitted when others present)")
    expectEqual(gauge?.segments.first?.state, .ready, "ready segment LEADS (good news first)")
    expectEqual(gauge?.segments.last?.state, .blocked, "blocked segment follows")
    expectEqual(PulsePresenter.gauge(rows: []), nil, "empty pulse → nil gauge (pill falls back to bare check)")
}

suite("PulsePresenter — liveness: stale partition + just-raised boost (the two-axis sort, iter 42)") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-23T12:00:00Z")!
    func at(daysAgo d: Double) -> String { iso.string(from: now.addingTimeInterval(-d * 86_400)) }
    func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
    func mk(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState, draft: Bool = false,
            created: String, updated: String) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: created, updatedAt: updated, ci: ci, review: r, merge: m)
    }

    // The screenshot's failure mode: a 4-month-old blocked PR (rotting) outranking live work.
    let oldBlocked   = mk(44, .failing, .approved, .conflicting, created: at(daysAgo: 117), updated: at(daysAgo: 111))
    let freshWait    = mk(99, .pending, ReviewState.none, .unknown, created: at(hoursAgo: 0.2), updated: at(hoursAgo: 0.2))
    let settledReady = mk(10, .passing, .approved, .mergeable, created: at(daysAgo: 3), updated: at(daysAgo: 1))
    let settledBlock = mk(15, .failing, .approved, .mergeable, created: at(daysAgo: 5), updated: at(daysAgo: 2))
    let draftWip     = mk(8, .passing, .approved, .mergeable, draft: true, created: at(daysAgo: 1), updated: at(daysAgo: 1))
    let s = PulsePresenter.sections(for: [oldBlocked, freshWait, settledReady, settledBlock, draftWip], now: now)

    // 1) Stale partition — the rotting PR leaves the live glance (THE screenshot fix).
    expectEqual(s.stale.map { $0.repo }, ["o/r #44"], "untouched-111d blocked PR → Stale group, OUT of Active")
    expect(!s.active.contains { $0.repo == "o/r #44" }, "the 4-month-old PR no longer sits at the top of the live lane")

    // 2) Active order — just-raised floats to the very top, THEN worst-first over settled work.
    expectEqual(s.active.map { $0.repo }, ["o/r #99", "o/r #15", "o/r #10"],
                "just-raised (#99) leads; then settled blocked (#15) > settled ready (#10)")
    expect(s.active.first?.isFresh == true, "the lead row carries the just-raised flag")

    // 3) Drafts stay their own group regardless of age.
    expectEqual(s.drafts.map { $0.repo }, ["o/r #8"], "draft → Drafts group")

    // 4) Stale never reaches the calm pill gauge (it counts live work only).
    let rows = PulsePresenter.rows(for: [oldBlocked, settledReady], now: now)
    let gauge = PulsePresenter.gauge(rows: rows.filter { !$0.isDraft && !$0.isStale })
    expectEqual(gauge?.blocked, 0, "the stale blocked PR is excluded from the gauge")
    expectEqual(gauge?.ready, 1, "only the live ready PR counts")

    // 5) Threshold honesty — boundaries parsed from real ISO timestamps.
    expect(!PulsePresenter.isStale(mk(1, .passing, .approved, .mergeable, created: at(daysAgo: 20), updated: at(daysAgo: 13.9)), now: now), "13.9d → still active")
    expect( PulsePresenter.isStale(mk(2, .passing, .approved, .mergeable, created: at(daysAgo: 20), updated: at(daysAgo: 14.1)), now: now), "14.1d → stale")
    expect( PulsePresenter.isFresh(mk(3, .pending, ReviewState.none, .unknown, created: at(hoursAgo: 3.9), updated: at(hoursAgo: 3.9)), now: now), "opened 3.9h ago → just-raised")
    expect(!PulsePresenter.isFresh(mk(4, .pending, ReviewState.none, .unknown, created: at(hoursAgo: 4.1), updated: at(hoursAgo: 4.1)), now: now), "opened 4.1h ago → not fresh")

    // 6) A draft is never stale — its own intentional group, not "forgotten work".
    expect(!PulsePresenter.isStale(mk(5, .passing, .approved, .mergeable, draft: true, created: at(daysAgo: 90), updated: at(daysAgo: 90)), now: now), "a 90d-old draft is NOT stale")
}

suite("PullRequestPulse — pulls.json fixture decodes to the full lattice + stays redactable (U7)") {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/GithudCoreTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures/pulls.json")
    let data = (try? Data(contentsOf: url)) ?? Data()
    let pulses = (try? PullRequestPulse.list(fromGraphQLData: data)) ?? []
    expectEqual(pulses.count, 11, "11 PRs decoded (lattice cells + 2 drafts)")

    var hist: [String: Int] = [:]
    for pulse in pulses { hist[pulse.state.rawValue, default: 0] += 1 }
    expectEqual(hist["ready"], 3, "3 ready (happy + no-checks + no-review)")
    expectEqual(hist["blocked"], 3, "3 blocked (CI / changes / conflicts)")
    expectEqual(hist["waiting"], 3, "3 waiting (review / CI pending / merge unknown)")
    expectEqual(hist["draft"], 2, "2 drafts")
    expectEqual(pulses.filter { $0.isDraft }.count, 2, "2 PRs carry isDraft (the grouping fact)")

    // Privacy: the probe's redacted evidence summarizes the pulse as this state
    // histogram — keys are state names only, never PR titles or repo names.
    expect(Set(hist.keys).isSubset(of: ["blocked", "ready", "waiting", "draft"]),
           "histogram keys are states only (no titles/repos can leak into evidence)")
    let serializedKeys = hist.keys.sorted().joined(separator: ",")
    expect(!serializedKeys.contains("retry") && !serializedKeys.contains("billing") && !serializedKeys.contains("acme"),
           "no PR title/repo substring in the redacted histogram")
}

suite("PulsePreferences + PulseRow.isDraft (iter 26 — draft grouping)") {
    expect(!PulsePreferences.default.showDrafts, "default hides drafts")
    expect(PulsePreferences.default.togglingShowDrafts().showDrafts, "toggling shows drafts")
    expect(!PulsePreferences.default.togglingShowDrafts().togglingShowDrafts().showDrafts, "double-toggle returns to hidden")
    // Stale subsection mirrors drafts: default hidden, independently togglable.
    expect(!PulsePreferences.default.showStale, "default hides stale")
    expect(PulsePreferences.default.togglingShowStale().showStale, "toggling shows stale")
    expect(!PulsePreferences.default.togglingShowStale().showDrafts, "toggling stale leaves drafts hidden (orthogonal)")
    expect(PulsePreferences.default.togglingShowDrafts().togglingShowStale().showDrafts, "the two toggles compose independently")
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let draft = PullRequestPulse(repo: "o/r", number: 9, title: "WIP", url: "u", isDraft: true,
        createdAt: "2026-06-16T09:00:00Z", updatedAt: "2026-06-16T09:00:00Z", ci: .passing, review: .approved, merge: .mergeable)
    let live = PullRequestPulse(repo: "o/r", number: 8, title: "Ship", url: "u", isDraft: false,
        createdAt: "2026-06-16T09:00:00Z", updatedAt: "2026-06-16T09:00:00Z", ci: .passing, review: .approved, merge: .mergeable)
    expect(PulsePresenter.row(for: draft, now: now).isDraft, "draft PR → row.isDraft true (grouping fact carried on the row)")
    expect(!PulsePresenter.row(for: live, now: now).isDraft, "non-draft PR → row.isDraft false")
    // The raw merge state rides onto the row so the view can pick GitHub's own conflict glyph.
    let conflicting = PullRequestPulse(repo: "o/r", number: 7, title: "x", url: "u", isDraft: false,
        createdAt: "2026-06-16T09:00:00Z", updatedAt: "2026-06-16T09:00:00Z", ci: .passing, review: .approved, merge: .conflicting)
    expectEqual(PulsePresenter.row(for: conflicting, now: now).merge, .conflicting, "row.merge carries .conflicting (drives the GitHub conflict badge)")
    expectEqual(PulsePresenter.row(for: live, now: now).merge, .mergeable, "row.merge carries .mergeable")
}

suite("PulsePresenter — pill gauge excludes drafts; the inversion is dissolved (iter 26)") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let liveRow = PulsePresenter.row(for: PullRequestPulse(repo: "o/r", number: 1, title: "a", url: "u",
        isDraft: false, createdAt: "2026-06-16T09:00:00Z", updatedAt: "2026-06-16T09:00:00Z", ci: .passing, review: .approved, merge: .mergeable), now: now)
    let draftFailing = PulsePresenter.row(for: PullRequestPulse(repo: "o/r", number: 2, title: "b", url: "u",
        isDraft: true, createdAt: "2026-06-16T08:00:00Z", updatedAt: "2026-06-16T08:00:00Z", ci: .failing, review: .approved, merge: .mergeable), now: now)
    // The dissolved inversion: a failing draft rolls up to .blocked (state) but is a draft (fact).
    expect(draftFailing.isDraft && draftFailing.state == .blocked, "a failing draft is state .blocked yet isDraft true")
    let mixed = [liveRow, draftFailing]
    // The pill gauge filters by the isDraft FACT — so the blocked draft never reaches the calm glance.
    let gauge = PulsePresenter.gauge(rows: mixed.filter { !$0.isDraft })
    expectEqual(gauge?.ready, 1, "gauge counts the 1 non-draft ready PR")
    expectEqual(gauge?.blocked, 0, "gauge ignores the blocked DRAFT (drafts excluded from the glance)")
    expectEqual(gauge?.segments.count, 1, "single ✓ready segment")
    expectEqual(PulsePresenter.gauge(rows: mixed)?.blocked, 1, "(control) over ALL rows the blocked draft counts")
}

suite("ThemeID — registry (iter 28/29 — theme system)") {
    expectEqual(ThemeID.allCases.count, 9, "9 themes (8 dark + 1 light)")
    expectEqual(ThemeID.default, .color, "Color is the default")
    expectEqual(Set(ThemeID.all), Set(ThemeID.allCases), "display order `all` covers every case (no theme dropped)")
    expectEqual(ThemeID.all.count, 9, "display order has all 9")
    expectEqual(ThemeID.all.last, .solarizedLight, "the lone light theme is last")
    expectEqual(ThemeID.solarizedLight.rawValue, "solarized-light", "solarizedLight raw")
    expectEqual(ThemeID.all.first, .color, "default leads the picker")
    // stable raw values (persisted in UserDefaults — must not drift)
    expectEqual(ThemeID.geistMono.rawValue, "geist-mono", "geistMono raw")
    expectEqual(ThemeID.github.rawValue, "github", "github raw")
    expectEqual(ThemeID.color.rawValue, "color", "color raw")
    expectEqual(ThemeID.dracula.rawValue, "dracula", "dracula raw")
    expectEqual(ThemeID.nord.rawValue, "nord", "nord raw")
    expectEqual(ThemeID.tokyoNight.rawValue, "tokyo-night", "tokyoNight raw")
    expectEqual(ThemeID.catppuccin.rawValue, "catppuccin", "catppuccin raw")
    expectEqual(ThemeID.solarizedDark.rawValue, "solarized-dark", "solarizedDark raw")
    expectEqual(ThemeID(rawValue: "color"), .color, "round-trips from raw")
    expect(ThemeID(rawValue: "bogus") == nil, "unknown raw → nil (store falls back to default)")
    for id in ThemeID.allCases { expect(!id.displayName.isEmpty, "\(id.rawValue) has a display name") }
}

// MARK: - PollReducer (WP-1a — the trust-critical poll state machine, every branch)

let reducerISO: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
func reducerAt(_ s: String) -> Date { reducerISO.date(from: s)! }
let reducerNow = reducerAt("2026-06-16T10:00:00Z")

/// A one-thread action-required radar (review_requested → always surfaces).
func makeRadar(id: String = "r1", updated: String = "2026-06-16T08:00:00Z", title: String = "Add retry") -> [RankedThread] {
    let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"\(updated)\",\"subject\":{\"title\":\"\(title)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
    return SignalClassifier.radar((try? NotificationThread.list(from: Data(json.utf8))) ?? [])
}

/// A successful notifications refresh (the reducer's narrow Core-side view).
func radarOK(_ radar: [RankedThread], notModified: Bool = false, next: Int = 60) -> Result<PollReducer.RadarRefresh, GitHubClientError> {
    .success(PollReducer.RadarRefresh(notModified: notModified, nextPollAfter: next, radar: radar))
}

func hasRenderRadar(_ effects: [PollReducer.Effect]) -> Bool { effects.contains { if case .renderRadar = $0 { return true }; return false } }
func hasRenderPulse(_ effects: [PollReducer.Effect]) -> Bool { effects.contains { if case .renderPulse = $0 { return true }; return false } }
func hasFreshness(_ effects: [PollReducer.Effect]) -> Bool { effects.contains { if case .emitFreshness = $0 { return true }; return false } }

let deadPulseFetch: Result<[PullRequestPulse], GitHubClientError> = .failure(.transport("pulse skipped"))

suite("PollReducer — 401 stops polling; applies NEITHER pulse NOR freshness (dead token, not late)") {
    let start = PollReducer.PollState()
    let (next, effects) = PollReducer.reduce(.polled(radar: .failure(.http(401, "Bad credentials")), pulse: .success([pulse()])), state: start, now: reducerNow)
    // WP-4e: the effect now carries WHY — 401 = invalid/expired token.
    expectEqual(effects, [.stopAndAuthFailure(.invalidToken)], "401 → exactly [stopAndAuthFailure(.invalidToken)]")
    expect(!hasRenderPulse(effects), "no pulse applied after the auth-stop (even though a fresh pulse arrived)")
    expect(!hasFreshness(effects), "no freshness cue after the auth-stop")
    expectEqual(next, start, "state untouched on auth-stop (no lastSuccess, no failure count, no pulse key)")
}

suite("PollReducer — a non-rate 403 (scope/SSO/forbidden) takes the SAME auth-stop path") {
    let (next, effects) = PollReducer.reduce(.polled(radar: .failure(.http(403, "SSO required")), pulse: .success([pulse()])), state: PollReducer.PollState(), now: reducerNow)
    // WP-4e: 403 carries a DISTINCT reason — org SSO / missing scope, not an invalid token.
    expectEqual(effects, [.stopAndAuthFailure(.ssoOrScope)], "403 non-rate → [stopAndAuthFailure(.ssoOrScope)]")
    expectEqual(next.lastPulseKey, nil, "pulse not applied on the 403 stop")
}

suite("PollReducer — the auth-failure REASON is carried through the effect (WP-4e; 401≠403)") {
    // The reason distinguishes the two auth statuses end-to-end so the shell routes each to
    // its OWN guidance. Assert the payload directly (not just "some auth stop") + that the two
    // are not conflated — a 401's reason must never read as a 403's.
    func reason(for error: GitHubClientError) -> AuthFailureReason? {
        let (_, effects) = PollReducer.reduce(.polled(radar: .failure(error), pulse: deadPulseFetch),
                                              state: PollReducer.PollState(), now: reducerNow)
        for e in effects { if case .stopAndAuthFailure(let r) = e { return r } }
        return nil
    }
    let e401: GitHubClientError = .http(401, "Bad credentials")
    let e403: GitHubClientError = .http(403, "SSO required")
    let r401: AuthFailureReason? = reason(for: e401)
    let r403: AuthFailureReason? = reason(for: e403)
    expect(r401 == .invalidToken, "401 → .invalidToken")
    expect(r403 == .ssoOrScope, "403 → .ssoOrScope")
    expect(r401 != r403, "401 and 403 reasons are NOT conflated")
    // The third reason, .wrongShape, is never API-derived — it is caught at intake/launch by
    // the classic-PAT WALL before any network call, so the reducer must never emit it.
    expect(r401 != .wrongShape && r403 != .wrongShape,
           ".wrongShape is intake-only — never emitted by the reducer from an API status")
}

suite("PollReducer — rate limit pauses max(60, retryAfter); NEVER a freshness failure (server reachable)") {
    // recent success so the reading stays .fresh — isolates the pause/floor behavior.
    let base = PollReducer.PollState(lastSuccessAt: reducerAt("2026-06-16T09:59:30Z"), consecutiveFailures: 0, lastFreshness: .fresh)
    func effectsFor(_ retryAfter: Int?) -> [PollReducer.Effect] {
        PollReducer.reduce(.polled(radar: .failure(.rateLimited(retryAfter: retryAfter)), pulse: deadPulseFetch), state: base, now: reducerNow).1
    }
    expect(effectsFor(nil).contains(.scheduleNext(afterSeconds: 60)), "retryAfter nil → pause 60 (default floor)")
    expect(effectsFor(30).contains(.scheduleNext(afterSeconds: 60)), "retryAfter 30 → floored up to 60")
    expect(effectsFor(120).contains(.scheduleNext(afterSeconds: 120)), "retryAfter 120 → honored above the floor")
    let (next, _) = PollReducer.reduce(.polled(radar: .failure(.rateLimited(retryAfter: 90)), pulse: deadPulseFetch), state: base, now: reducerNow)
    expectEqual(next.consecutiveFailures, 0, "a rate limit does NOT increment consecutiveFailures")
    expectEqual(next.lastSuccessAt, base.lastSuccessAt, "a rate limit does NOT touch lastSuccessAt (data merely ages to .stale)")
}

suite("PollReducer — a transient failure increments the streak and retries in 60s") {
    let base = PollReducer.PollState(lastSuccessAt: reducerAt("2026-06-16T09:59:30Z"), consecutiveFailures: 0, lastFreshness: .fresh)
    let (n1, e1) = PollReducer.reduce(.polled(radar: .failure(.transport("connection reset")), pulse: deadPulseFetch), state: base, now: reducerNow)
    expectEqual(n1.consecutiveFailures, 1, "consecutiveFailures 0 → 1 on a transport failure")
    expect(e1.contains(.scheduleNext(afterSeconds: 60)), "transient → retry in 60s")
    let (n2, _) = PollReducer.reduce(.polled(radar: .failure(.decode("bad json")), pulse: deadPulseFetch), state: n1, now: reducerNow)
    expectEqual(n2.consecutiveFailures, 2, "a decode failure is transient too → streak 1 → 2")
}

suite("PollReducer — a 304 confirms currency (resets the streak, no re-render) and schedules the interval") {
    let priorKey = RadarPresenter.changeKey(for: makeRadar())
    let base = PollReducer.PollState(lastKey: priorKey, consecutiveFailures: 3, lastFreshness: .failing(consecutive: 3, ageSeconds: 200))
    let (next, effects) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 90), pulse: deadPulseFetch), state: base, now: reducerNow)
    expectEqual(next.lastSuccessAt, reducerNow, "304 stamps lastSuccessAt (a 304 confirms the data is current)")
    expectEqual(next.consecutiveFailures, 0, "304 resets the failure streak")
    expect(!hasRenderRadar(effects), "304 → no radar re-render")
    expect(effects.contains(.scheduleNext(afterSeconds: 90)), "304 schedules the server interval")
    expect(effects.contains(.emitFreshness(.fresh)), "recovering from .failing to .fresh emits the freshness change")
    expectEqual(next.lastKey, priorKey, "304 leaves lastKey untouched")
}

suite("PollReducer — a CHANGED 200 renders rows, adopts the key, schedules — effect ORDER preserved") {
    let radar = makeRadar(id: "a", updated: "2026-06-16T08:00:00Z")
    let base = PollReducer.PollState(lastKey: ["stale-key"], lastSuccessAt: reducerAt("2026-06-16T09:59:30Z"), lastFreshness: .fresh)
    let (next, effects) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: false, next: 75), pulse: deadPulseFetch), state: base, now: reducerNow)
    expectEqual(next.lastKey, RadarPresenter.changeKey(for: radar), "lastKey adopts the new change key")
    expectEqual(effects, [.renderRadar(RadarPresenter.rows(for: radar, now: reducerNow)), .scheduleNext(afterSeconds: 75)],
                "radar render THEN schedule (freshness steady + pulse dead → neither appended)")
}

suite("PollReducer — an UNCHANGED 200 (key matches last render) does NOT re-render") {
    let radar = makeRadar(id: "a", updated: "2026-06-16T08:00:00Z")
    let base = PollReducer.PollState(lastKey: RadarPresenter.changeKey(for: radar), lastSuccessAt: reducerAt("2026-06-16T09:59:30Z"), lastFreshness: .fresh)
    let (_, effects) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: false, next: 60), pulse: deadPulseFetch), state: base, now: reducerNow)
    expect(!hasRenderRadar(effects), "unchanged 200 → no radar render")
    expect(effects.contains(.scheduleNext(afterSeconds: 60)), "but it still schedules the next poll")
}

suite("PollReducer — the FIRST successful poll renders even an EMPTY radar (lastKey starts nil)") {
    let base = PollReducer.PollState()   // lastKey nil
    let (next, effects) = PollReducer.reduce(.polled(radar: radarOK([], notModified: false, next: 60), pulse: deadPulseFetch), state: base, now: reducerNow)
    expect(effects.contains(.renderRadar([])), "empty radar STILL renders (leaves the 'loading' pill; U6 gauge can appear)")
    expectEqual(next.lastKey, [], "lastKey becomes [] (no longer nil)")
    let (_, effects2) = PollReducer.reduce(.polled(radar: radarOK([], notModified: false, next: 60), pulse: deadPulseFetch), state: next, now: reducerNow)
    expect(!effects2.contains(.renderRadar([])), "a second empty poll (lastKey now []) does not re-render")
}

suite("PollReducer — pulse: renders on change, silent when unchanged, keeps last-good on failure") {
    let radar = makeRadar()
    let steady = PollReducer.PollState(lastKey: RadarPresenter.changeKey(for: radar), lastSuccessAt: reducerAt("2026-06-16T09:59:30Z"), lastFreshness: .fresh)
    let pulses = [pulse()]
    let (n1, e1) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: .success(pulses)), state: steady, now: reducerNow)
    expect(e1.contains(.renderPulse(PulsePresenter.rows(for: pulses, now: reducerNow))), "first pulse (lastPulseKey nil) renders")
    expectEqual(n1.lastPulseKey, PulsePresenter.changeKey(for: pulses), "lastPulseKey adopted")
    let (_, e2) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: .success(pulses)), state: n1, now: reducerNow)
    expect(!hasRenderPulse(e2), "an identical pulse → no re-render")
    let (n3, e3) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: .failure(.transport("pulse down"))), state: n1, now: reducerNow)
    expect(!hasRenderPulse(e3), "a pulse failure → no render")
    expectEqual(n3.lastPulseKey, n1.lastPulseKey, "a pulse failure keeps the last good pulse key (no flicker-to-empty)")
}

suite("PollReducer — reading-freshness transitions fresh → stale → failing → fresh under an advancing clock") {
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    var state = PollReducer.PollState()
    // 1) success at t0 from a fresh start → stays fresh → NO emit (change-only)
    let (s1, e1) = PollReducer.reduce(.polled(radar: radarOK([], next: 60), pulse: deadPulseFetch), state: state, now: t0)
    state = s1
    expect(!hasFreshness(e1), "a success from a fresh start stays fresh → no freshness emit")
    // 2) rate-limit 300s later, no new success → data ages to .stale(300) → emit
    let t1 = t0.addingTimeInterval(300)
    let (s2, e2) = PollReducer.reduce(.polled(radar: .failure(.rateLimited(retryAfter: 300)), pulse: deadPulseFetch), state: state, now: t1)
    state = s2
    expect(e2.contains(.emitFreshness(.stale(ageSeconds: 300))), "aged 300s (server reachable) → stale, emitted on change")
    // 3) two transient failures → .failing (fires before staleAfter would, on the count)
    let t2 = t1.addingTimeInterval(30)
    let (s3, _) = PollReducer.reduce(.polled(radar: .failure(.transport("x")), pulse: deadPulseFetch), state: state, now: t2)
    let t3 = t2.addingTimeInterval(30)
    let (s4, e4) = PollReducer.reduce(.polled(radar: .failure(.transport("x")), pulse: deadPulseFetch), state: s3, now: t3)
    state = s4
    expectEqual(state.consecutiveFailures, 2, "two transient failures accumulated across ticks")
    expect(e4.contains(.emitFreshness(.failing(consecutive: 2, ageSeconds: 360))), "two failures → failing(2, age 360), emitted")
    // 4) a success recovers → fresh, emitted; streak reset
    let t4 = t3.addingTimeInterval(5)
    let (s5, e5) = PollReducer.reduce(.polled(radar: radarOK([], next: 60), pulse: deadPulseFetch), state: state, now: t4)
    expect(e5.contains(.emitFreshness(.fresh)), "a success after failures recovers to fresh, emitted on change")
    expectEqual(s5.consecutiveFailures, 0, "recovery resets the streak")
}

suite("PollReducer — freshness is emitted on CHANGE only (steady fresh adds no re-renders)") {
    let base = PollReducer.PollState(lastSuccessAt: reducerAt("2026-06-16T09:59:40Z"), lastFreshness: .fresh)
    let radar = makeRadar()
    let (n1, e1) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: deadPulseFetch), state: base, now: reducerNow)
    expect(!hasFreshness(e1), "fresh → fresh: no freshness emit")
    let (_, e2) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: deadPulseFetch), state: n1, now: reducerNow.addingTimeInterval(30))
    expect(!hasFreshness(e2), "still fresh a poll later: still no emit")
}

suite("PollReducer — a preferences change re-renders immediately + UNCONDITIONALLY, adopting the key") {
    let radar = makeRadar()
    // Even when lastKey already equals the recomputed key, it STILL renders (the user just
    // toggled the filter — they must see the effect immediately).
    let base = PollReducer.PollState(lastKey: RadarPresenter.changeKey(for: radar))
    let (next, effects) = PollReducer.reduce(.preferencesRecomputed(radar), state: base, now: reducerNow)
    expectEqual(effects, [.renderRadar(RadarPresenter.rows(for: radar, now: reducerNow))], "exactly one render, unconditional")
    expectEqual(next.lastKey, RadarPresenter.changeKey(for: radar), "lastKey adopts the recomputed key")
    // (WP-1c fix round) This suite used to assert "touches nothing else" over EFFECTS only,
    // which codified Blocker A: the STATE's retained rows were left pre-filter, so a later
    // age-flip re-emitted rows the user had just filtered out. The effect list is still
    // exactly one render — but the retained-render state MUST follow the filter too.
    expectEqual(effects.count, 1, "a pref change EMITS nothing else (no schedule/freshness/pulse)")
    expectEqual(next.lastRenderedRadar, RadarPresenter.rows(for: radar, now: reducerNow),
                "lastRenderedRadar adopts the FILTERED rows (age flips re-emit these — Blocker A)")
    expectEqual(next.lastRadarAgeSig, RadarPresenter.ageSignature(for: RadarPresenter.rows(for: radar, now: reducerNow), now: reducerNow),
                "the age baseline is re-stamped from the filtered rows at the pref-change moment")
}

suite("PollReducer — after a filter toggle, an age flip re-emits the FILTERED set, never the pre-filter set ⚠ [fix A repro]") {
    // The reviewer's repro, permanent. Two threads on the radar; the user filters one out;
    // a later 304 tick crosses an age-bucket boundary while expanded. The re-emitted rows
    // must be the filtered ONE-row set — re-emitting the retained TWO-row set would silently
    // resurface a notification the user explicitly filtered out (reverting a user action).
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    let json = "[{\"id\":\"ra\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"2026-06-16T09:59:30Z\",\"subject\":{\"title\":\"keep me\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}},"
        + "{\"id\":\"rb\",\"unread\":true,\"reason\":\"mention\",\"updated_at\":\"2026-06-16T09:59:30Z\",\"subject\":{\"title\":\"filter me out\",\"type\":\"Issue\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    let full = SignalClassifier.radar(threads)                                   // both surface under auto
    let filtered = SignalClassifier.radar(threads, preferences: SurfacePreferences.auto.toggling("mention"))
    expectEqual(full.count, 2, "pre-filter: both threads on the radar")
    expectEqual(filtered.count, 1, "post-filter: the mention is filtered out")

    // t0: a changed 200 renders the FULL set, expanded (both rows 30s old → bucket "now").
    let (s1, e1) = PollReducer.reduce(.polled(radar: radarOK(full, notModified: false, next: 60), pulse: deadPulseFetch),
                                      state: PollReducer.PollState(expanded: true), now: t0)
    expect(hasRenderRadar(e1), "initial 200 renders the full set")
    expectEqual(s1.lastRenderedRadar?.count, 2, "two rows retained pre-filter")

    // t0+10: the user toggles the filter → preferencesRecomputed with the FILTERED radar.
    let (s2, e2) = PollReducer.reduce(.preferencesRecomputed(filtered), state: s1, now: t0.addingTimeInterval(10))
    let filteredRows = RadarPresenter.rows(for: filtered, now: t0.addingTimeInterval(10))
    expectEqual(e2, [.renderRadar(filteredRows)], "the filter toggle renders the filtered set")
    expectEqual(s2.lastRenderedRadar, filteredRows, "the RETAINED rows follow the user's filter (was Blocker A: they stayed pre-filter)")

    // t0+40: a 304 tick; the rows' age bucket flips (now→1m). The re-emit must be the
    // FILTERED set — the exact structs retained at the pref change — not the two-row set.
    let (s3, e3) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: deadPulseFetch),
                                      state: s2, now: t0.addingTimeInterval(40))
    expect(e3.contains(.renderRadar(filteredRows)), "the age-flip re-emit is the FILTERED one-row set")
    var reEmitted: [RadarRow]? = nil
    for case .renderRadar(let rows) in e3 { reEmitted = rows }
    expectEqual(reEmitted?.count, 1, "exactly one row re-emitted — the filtered-out mention does NOT resurface")
    expect(reEmitted?.contains { $0.title == "filter me out" } == false, "the filtered-out thread is absent from the re-emit")
    expectEqual(s3.lastKey, s2.lastKey, "content key untouched — a pure age re-render, not a data change")
}

suite("PollReducer — a seeded stale baseline (snapshot launch-paint) CLEARS on the first healthy poll ⚠ [fix B]") {
    // Blocker B, permanent. AppDelegate paints the persisted snapshot with a .stale banner and
    // seeds the scheduler's reducer state with the SAME value + the persisted last-success
    // dates (seedFreshness). The first healthy poll computes .fresh ≠ the seed → the change
    // guard EMITS → the banner clears. (Unseeded, lastFreshness inits .fresh, .fresh == .fresh
    // suppresses the emit, and the launch banner would sit over live data all session — a
    // permanent false-stale on the doctrine-reserved caution cue.)
    let nineHoursAgo = reducerNow.addingTimeInterval(-9 * 3600)
    let seeded = PollReducer.PollState(lastSuccessAt: nineHoursAgo,          // what seedFreshness sets:
                                       lastFreshness: .stale(ageSeconds: 9 * 3600))  // banner + its basis
    let (next, effects) = PollReducer.reduce(.polled(radar: radarOK([], notModified: false, next: 60), pulse: deadPulseFetch),
                                             state: seeded, now: reducerNow)
    expect(effects.contains(.emitFreshness(.fresh)), "a healthy 200 after a stale seed EMITS .fresh (the launch banner clears)")
    expectEqual(next.lastFreshness, .fresh, "the baseline advances to .fresh")
    // A 304 clears it just the same (it equally confirms the reading is current).
    let (_, e304) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: deadPulseFetch),
                                       state: seeded, now: reducerNow)
    expect(e304.contains(.emitFreshness(.fresh)), "a healthy 304 after a stale seed also emits .fresh")
    // Control (why the last-success dates are part of the seed): a FAILING first poll must NOT
    // clear the banner — with the persisted lastSuccessAt seeded it computes .stale(sameAge) ==
    // the baseline → no emit, banner honestly stays. (Seeding ONLY lastFreshness would leave
    // lastSuccessAt nil → the "no poll yet → don't accuse" rule computes .fresh → the banner
    // would clear over 9h-old data on a FAILED poll — the opposite fabrication.)
    let (nFail, eFail) = PollReducer.reduce(.polled(radar: .failure(.transport("offline")), pulse: deadPulseFetch),
                                            state: seeded, now: reducerNow)
    expect(!eFail.contains(.emitFreshness(.fresh)), "a failed first poll does NOT emit .fresh (the stale banner honestly stays)")
    expectEqual(nFail.lastFreshness, .stale(ageSeconds: 9 * 3600), "the baseline stays stale at the persisted age")
}

// MARK: - WP-1b: worst-of-both freshness, poll-now, five-site rate-limit backoff

suite("FreshnessModel.worst — the more-degraded of two lanes (WP-1b worst-of-both)") {
    let fresh = Freshness.fresh
    let stale = Freshness.stale(ageSeconds: 200)
    let failing = Freshness.failing(consecutive: 2, ageSeconds: 360)
    expectEqual(FreshnessModel.worst(fresh, fresh), fresh, "fresh vs fresh → fresh (quiet)")
    expectEqual(FreshnessModel.worst(fresh, stale), stale, "fresh vs stale → stale (a degraded lane is never masked by a fresh one)")
    expectEqual(FreshnessModel.worst(stale, fresh), stale, "order-independent: stale wins over fresh")
    expectEqual(FreshnessModel.worst(stale, failing), failing, "stale vs failing → failing (failing outranks stale)")
    expectEqual(FreshnessModel.worst(failing, fresh), failing, "failing vs fresh → failing")
    // ties break toward the worse magnitude
    expectEqual(FreshnessModel.worst(.stale(ageSeconds: 200), .stale(ageSeconds: 500)), .stale(ageSeconds: 500), "two stale → the older age")
    expectEqual(FreshnessModel.worst(.failing(consecutive: 2, ageSeconds: 100), .failing(consecutive: 5, ageSeconds: 50)), .failing(consecutive: 5, ageSeconds: 50), "two failing → the longer streak")
}

suite("PollReducer — a persistently-failing pulse raises the caution cue even while notifications 304 happily (WP-1b) ⚠") {
    // The exact rule: worst-of-both, the pulse folded through the SAME thresholds as the
    // radar. A single blip does NOT degrade; the SECOND consecutive pulse failure crosses
    // failureThreshold(2) → the island-wide caution appears though the radar is 304-fresh.
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    let radar = makeRadar()
    let pulses = [pulse()]
    // A healthy steady state that has ALREADY rendered a good pulse (lastPulseSuccessAt set).
    let base = PollReducer.PollState(
        lastKey: RadarPresenter.changeKey(for: radar), lastPulseKey: PulsePresenter.changeKey(for: pulses),
        lastSuccessAt: t0, consecutiveFailures: 0, lastFreshness: .fresh,
        lastPulseSuccessAt: t0, pulseConsecutiveFailures: 0)
    // tick 1 (t0+60): notifications 304 (fresh), GraphQL dies → ONE pulse failure. A blip.
    let (s1, e1) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: .failure(.transport("graphql down"))), state: base, now: t0.addingTimeInterval(60))
    expect(!hasFreshness(e1), "a single pulse blip does NOT degrade the reading (symmetry with a radar blip)")
    expectEqual(s1.pulseConsecutiveFailures, 1, "one pulse failure counted")
    // tick 2 (t0+120): notifications still 304 (fresh), GraphQL still dead → SECOND failure.
    let (s2, e2) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: .failure(.transport("graphql down"))), state: s1, now: t0.addingTimeInterval(120))
    expectEqual(s2.pulseConsecutiveFailures, 2, "two consecutive pulse failures")
    expect(e2.contains(.emitFreshness(.failing(consecutive: 2, ageSeconds: 120))), "caution appears from the pulse lane alone (radar was 304-fresh the whole time)")
    // recovery (t0+180): GraphQL returns → back to fresh, emitted on change.
    let (s3, e3) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: .success(pulses)), state: s2, now: t0.addingTimeInterval(180))
    expect(e3.contains(.emitFreshness(.fresh)), "a pulse recovery clears the caution (worst-of-both back to fresh)")
    expectEqual(s3.pulseConsecutiveFailures, 0, "recovery resets the pulse streak")
}

suite("PollReducer — a pulse that has NEVER succeeded does not degrade the reading (nothing shown to distrust) ⚠") {
    // lastPulseSuccessAt nil → the pulse lane renders nothing → even repeated failures leave
    // the reading fresh (the radar is the only thing on screen). This is what preserves the
    // radar-only freshness tests that thread a dead pulse fetch.
    var state = PollReducer.PollState(lastSuccessAt: reducerNow, lastFreshness: .fresh)
    for i in 1...4 {
        let (n, e) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: .failure(.transport("never up"))), state: state, now: reducerNow.addingTimeInterval(Double(i) * 60))
        state = n
        expect(!hasFreshness(e), "pulse failure #\(i) with no prior pulse success → still fresh (no caution)")
    }
    expectEqual(state.pulseConsecutiveFailures, 4, "the raw failure count is still tracked truthfully")
}

suite("PollReducer — a pulse rate-limit does NOT bump the pulse streak (symmetry with the radar) ⚠") {
    let base = PollReducer.PollState(lastPulseKey: PulsePresenter.changeKey(for: [pulse()]),
                                     lastSuccessAt: reducerNow, lastFreshness: .fresh,
                                     lastPulseSuccessAt: reducerNow, pulseConsecutiveFailures: 0)
    let (n1, _) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true), pulse: .failure(.rateLimited(retryAfter: 120))), state: base, now: reducerNow.addingTimeInterval(60))
    expectEqual(n1.pulseConsecutiveFailures, 0, "a rate-limited pulse is NOT a failure (server reachable — ages toward .stale, never .failing on the count)")
}

suite("PollReducer — the full effect ORDER: radar-render → schedule → freshness → pulse-render (WP-1b optional) ⚠") {
    // A single tick that triggers ALL FOUR effects, asserted as an exact ordered list.
    let radar = makeRadar()
    let pulses = [pulse()]
    let base = PollReducer.PollState(lastKey: ["stale-key"], lastPulseKey: nil,
                                     lastSuccessAt: reducerAt("2026-06-16T09:55:00Z"),
                                     consecutiveFailures: 2, lastFreshness: .failing(consecutive: 2, ageSeconds: 300),
                                     lastPulseSuccessAt: nil, pulseConsecutiveFailures: 0)
    let (_, effects) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: false, next: 60), pulse: .success(pulses)), state: base, now: reducerNow)
    expectEqual(effects, [
        .renderRadar(RadarPresenter.rows(for: radar, now: reducerNow)),
        .scheduleNext(afterSeconds: 60),
        .emitFreshness(.fresh),
        .renderPulse(PulsePresenter.rows(for: pulses, now: reducerNow)),
    ], "exact ordered effect list: render → schedule → freshness → pulse")
}

suite("PollReducer — pollNow ACCEPTED when idle: returns exactly [.pollImmediately] (WP-1b) ⚠") {
    // never polled → accept
    let (_, e0) = PollReducer.reduce(.pollNowRequested, state: PollReducer.PollState(), now: reducerNow)
    expectEqual(e0, [.pollImmediately], "no prior poll → immediate")
    // last poll long ago, no pause → accept
    let idle = PollReducer.PollState(lastPollAt: reducerNow.addingTimeInterval(-60), pauseUntil: nil)
    let (_, e1) = PollReducer.reduce(.pollNowRequested, state: idle, now: reducerNow)
    expectEqual(e1, [.pollImmediately], "60s since the last poll, no pause → immediate (wake/path-change fires without waiting the tick)")
}

suite("PollReducer — pollNow DEBOUNCED: a poll within pollNowDebounce coalesces to nothing (WP-1b) ⚠") {
    let recent = PollReducer.PollState(lastPollAt: reducerNow.addingTimeInterval(-2), pauseUntil: nil)
    let (next, effects) = PollReducer.reduce(.pollNowRequested, state: recent, now: reducerNow)
    expectEqual(effects, [], "a poll 2s ago (< 5s debounce) → coalesced, no immediate poll")
    expectEqual(next, recent, "a debounced pollNow mutates nothing")
    // just past the debounce → accept
    let old = PollReducer.PollState(lastPollAt: reducerNow.addingTimeInterval(-Double(PollReducer.pollNowDebounce) - 0.1))
    let (_, e2) = PollReducer.reduce(.pollNowRequested, state: old, now: reducerNow)
    expectEqual(e2, [.pollImmediately], "just past the debounce window → immediate")
}

suite("PollReducer — pollNow REFUSED during an active rate-limit pause — reset outranks immediacy (WP-1b HARD) ⚠") {
    // pauseUntil in the future refuses EVEN when the debounce would otherwise allow it.
    let paused = PollReducer.PollState(lastPollAt: reducerNow.addingTimeInterval(-999), pauseUntil: reducerNow.addingTimeInterval(100))
    let (_, effects) = PollReducer.reduce(.pollNowRequested, state: paused, now: reducerNow)
    expectEqual(effects, [], "an active pause refuses pollNow (never bypass GitHub's reset)")
    // an EXPIRED pause no longer refuses
    let expired = PollReducer.PollState(lastPollAt: reducerNow.addingTimeInterval(-999), pauseUntil: reducerNow.addingTimeInterval(-1))
    let (_, e2) = PollReducer.reduce(.pollNowRequested, state: expired, now: reducerNow)
    expectEqual(e2, [.pollImmediately], "once the pause window has passed, pollNow is accepted again")
}

suite("PollReducer — a radar rate-limit SETS pauseUntil so a subsequent pollNow is refused; a success clears it ⚠") {
    let base = PollReducer.PollState(lastSuccessAt: reducerNow, lastFreshness: .fresh)
    let (afterRL, _) = PollReducer.reduce(.polled(radar: .failure(.rateLimited(retryAfter: 200)), pulse: deadPulseFetch), state: base, now: reducerNow)
    expectEqual(afterRL.pauseUntil, reducerNow.addingTimeInterval(200), "rate-limit records the pause window (now + max(60, 200))")
    let (_, refused) = PollReducer.reduce(.pollNowRequested, state: afterRL, now: reducerNow.addingTimeInterval(30))
    expectEqual(refused, [], "pollNow 30s into the 200s pause → refused")
    // a later successful poll clears the pause
    let (afterOK, _) = PollReducer.reduce(.polled(radar: radarOK([], next: 60), pulse: deadPulseFetch), state: afterRL, now: reducerNow.addingTimeInterval(210))
    expectEqual(afterOK.pauseUntil, nil, "a successful poll clears the pause window")
}

// MARK: - WP-1c: live-age bucket-flip re-render, expand visibility, snapshot persistence

suite("PollReducer — live ages: a 304 re-renders on an age-bucket flip, but ONLY while EXPANDED ⚠ [WP-1c]") {
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    let radar = makeRadar(id: "a", updated: "2026-06-16T09:59:30Z")   // 30s old at t0 → "now"
    // A changed 200 renders, RETAINS the rows, and stamps the age baseline.
    let (rendered, e0) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: false, next: 60), pulse: deadPulseFetch),
                                            state: PollReducer.PollState(expanded: true), now: t0)
    expect(hasRenderRadar(e0), "the initial 200 renders")
    expect(rendered.lastRenderedRadar != nil, "the rendered rows are retained for later age re-emission (a 304 carries no radar data)")
    expectEqual(rendered.lastRadarAgeSig, ["now"], "the age baseline is the displayed bucket at render time")

    // A 304 tick 40s on (now→1m boundary crossed) while EXPANDED → re-render the SAME rows.
    let (afterFlip, eFlip) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: deadPulseFetch),
                                                state: rendered, now: t0.addingTimeInterval(40))
    expect(hasRenderRadar(eFlip), "expanded + bucket flipped (now→1m) on a 304 → re-render (the view re-formats the age)")
    expectEqual(afterFlip.lastKey, rendered.lastKey, "the CONTENT key is unchanged — a pure age re-render, not a data change (no render loop)")
    expectEqual(afterFlip.lastRadarAgeSig, ["1m"], "the baseline advances to the new bucket (so it won't re-fire until the next flip)")

    // The SAME flip while COLLAPSED → no re-render (the pill shows no per-row age: invisible).
    var collapsed = rendered; collapsed.expanded = false
    let (_, eCollapsed) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: deadPulseFetch),
                                             state: collapsed, now: t0.addingTimeInterval(40))
    expect(!hasRenderRadar(eCollapsed), "collapsed → the same age flip does NOT re-render (no invisible churn)")

    // Expanded but WITHIN the bucket (still 'now' at +20s) → no re-render (no flip).
    let (_, eNoFlip) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true, next: 60), pulse: deadPulseFetch),
                                          state: rendered, now: t0.addingTimeInterval(20))
    expect(!hasRenderRadar(eNoFlip), "expanded but no bucket flip (still 'now') → NO re-render (attention-non-theft: a tick with no flip must not render)")
}

suite("PollReducer — live ages: the pulse lane flips independently, gated the same way ⚠ [WP-1c]") {
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    let radar = makeRadar()
    let pulses = [pulse(created: "2026-06-16T09:59:30Z", updated: "2026-06-16T09:59:30Z")]   // 30s → "now"
    // Render both lanes once, expanded.
    let base = PollReducer.PollState(lastKey: RadarPresenter.changeKey(for: radar), expanded: true)
    let (rendered, _) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: true), pulse: .success(pulses)), state: base, now: t0)
    expect(rendered.lastRenderedPulse != nil, "pulse rows retained")
    // 304 + pulse UNCHANGED (identical) 40s on → the pulse age bucket flipped (now→1m) → re-render.
    let (_, e) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true), pulse: .success(pulses)), state: rendered, now: t0.addingTimeInterval(40))
    expect(hasRenderPulse(e), "expanded + pulse age bucket flipped → renderPulse (same rows, re-aged)")
    // Collapsed: no pulse re-render on the same flip.
    var collapsed = rendered; collapsed.expanded = false
    let (_, e2) = PollReducer.reduce(.polled(radar: radarOK([], notModified: true), pulse: .success(pulses)), state: collapsed, now: t0.addingTimeInterval(40))
    expect(!hasRenderPulse(e2), "collapsed → no pulse age re-render")
}

suite("PollReducer — .expandChanged records visibility, emits nothing, re-baselines the age signature ⚠ [WP-1c]") {
    let t0 = reducerAt("2026-06-16T10:00:00Z")
    let radar = makeRadar(id: "a", updated: "2026-06-16T09:59:30Z")
    let (rendered, _) = PollReducer.reduce(.polled(radar: radarOK(radar, notModified: false, next: 60), pulse: deadPulseFetch),
                                           state: PollReducer.PollState(), now: t0)
    expect(!rendered.expanded, "starts collapsed")
    expectEqual(rendered.lastRadarAgeSig, ["now"], "baseline stamped at render (t0)")
    // expandChanged(true) 40s on → expanded set, NO effects, baseline re-stamped to the expand `now`.
    let (expanded, e) = PollReducer.reduce(.expandChanged(true), state: rendered, now: t0.addingTimeInterval(40))
    expect(e.isEmpty, "expandChanged emits no effects (the panel owns the expand render, WP-3e)")
    expect(expanded.expanded, "expanded flag set")
    expectEqual(expanded.lastRadarAgeSig, ["1m"], "the baseline is re-stamped to the expand moment (+40s → 1m), so the next tick measures flips from here — no redundant first-tick re-render")
    let (collapsed, e2) = PollReducer.reduce(.expandChanged(false), state: expanded, now: t0.addingTimeInterval(60))
    expect(e2.isEmpty && !collapsed.expanded, "collapse clears the flag, still no effects")
}

suite("PollReducer — D1 sweep-clock crossing: exactly ONE repaint per fresh↔stale flip, both directions ⚠ [F-1]") {
    // THE F-1 trap this suite pins: /notifications 304s forever (poll clock fresh), sweeps
    // fail with an unchanged key, the pill is collapsed (no age-flip renders) — with no
    // sweep-crossing emission a chronic "N waiting" sits under FRESH chrome indefinitely
    // (the exact F3 fabrication D1 closes). The crossing gates on the DEGRADED boolean:
    // steady-degraded ticks (ageing seconds) emit nothing; each direction emits once.
    func hasSweep(_ effects: [PollReducer.Effect]) -> Bool {
        effects.contains { if case .emitSweepFreshness = $0 { return true }; return false }
    }
    func sweepValue(_ effects: [PollReducer.Effect]) -> Freshness? {
        for e in effects { if case .emitSweepFreshness(let f) = e { return f } }
        return nil
    }
    let ok304 = radarOK([], notModified: true)   // steady 304s: the poll clock stays fresh forever
    let sweepItem = InboundItem(repo: "o/r", number: 1, title: "t", url: "u", authorLogin: "a",
                                authorType: "User", isPR: true, isDraft: false,
                                createdAt: "2026-06-01T00:00:00Z", updatedAt: "2026-06-01T00:00:00Z")

    // Never-swept (nil date) behaves per sweepStatus: the baseline INITS degraded, so a
    // session's first tick emits NO fabricated "crossing" — never-swept was the launch truth.
    let s0 = PollReducer.PollState()
    expect(s0.lastSweepFreshness.isDegraded, "PollState inits the sweep baseline DEGRADED (sweepStatus(nil) — never-swept)")
    let (s1, e1) = PollReducer.reduce(.polled(radar: ok304, pulse: deadPulseFetch), state: s0, now: reducerNow)
    expect(!hasSweep(e1), "never-swept first tick: no crossing emitted (degraded → degraded is steady state)")
    expect(s1.lastSweepFreshness.isDegraded, "…and the recorded baseline stays degraded")

    // Recovery: a COMPLETE sweep stamps the date; the NEXT tick crosses stale→fresh → ONE emit
    // (the direction that un-sticks a stuck prefix after a recovering sweep with an unchanged key).
    let (s2, _) = PollReducer.reduce(.sweptInbound(.success(InboundReading(items: [sweepItem], incomplete: false, totalCount: 1))),
                                     state: s1, now: reducerNow)
    expectEqual(s2.lastInboundSuccessAt, reducerNow, "the complete sweep stamped the clock")
    let (s3, e3) = PollReducer.reduce(.polled(radar: ok304, pulse: deadPulseFetch),
                                      state: s2, now: reducerNow.addingTimeInterval(60))
    expectEqual(sweepValue(e3)?.isDegraded, false, "stale→fresh crossing emits exactly once on the next tick (the un-stick direction)")
    let (s4, e4) = PollReducer.reduce(.polled(radar: ok304, pulse: deadPulseFetch),
                                      state: s3, now: reducerNow.addingTimeInterval(120))
    expect(!hasSweep(e4), "steady fresh: no re-emission")

    // Sweeps now silently fail (nothing stamps the clock) while 304s keep the poll clock
    // fresh: at +420s past the last complete sweep the sweep clock crosses into stale →
    // ONE emit — and the POLL clock emits nothing beside it (this crossing is its own signal).
    let (s5, e5) = PollReducer.reduce(.polled(radar: ok304, pulse: deadPulseFetch),
                                      state: s4, now: reducerNow.addingTimeInterval(420))
    expectEqual(sweepValue(e5)?.isDegraded, true, "fresh→stale crossing emits exactly once (the F3 fresh-chrome trap, closed)")
    expect(!hasFreshness(e5), "…while the 304-ing poll clock emits NO freshness of its own (isolating the sweep signal)")
    let (_, e6) = PollReducer.reduce(.polled(radar: ok304, pulse: deadPulseFetch),
                                     state: s5, now: reducerNow.addingTimeInterval(480))
    expect(!hasSweep(e6), "steady stale: the ageing seconds re-emit nothing (the gate is the boolean crossing, not the value)")
}

suite("SnapshotStore — round-trips the last-good radar+pulse; corrupt/missing → clean cold start ⚠ [WP-1c]") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let radar = RadarPresenter.rows(for: makeRadar(id: "r1", updated: "2026-06-16T08:00:00Z"), now: now)
    let pulseRows = PulsePresenter.rows(for: [pulse()], now: now)
    let radarSuccess = iso.date(from: "2026-06-16T01:00:00Z")!   // 9h before now
    let snap = Snapshot(radar: radar, pulse: pulseRows, lastRadarSuccessAt: radarSuccess, lastPulseSuccessAt: radarSuccess)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("githud-snap-\(UUID().uuidString).json")
    SnapshotStore.clear(at: tmp)
    expect(SnapshotStore.load(from: tmp) == nil, "a missing file loads as nil (clean cold start)")
    SnapshotStore.save(snap, to: tmp)
    let loaded = SnapshotStore.load(from: tmp)
    expectEqual(loaded?.radar, snap.radar, "radar rows round-trip exactly (incl. the raw timestamp for next-launch ageing)")
    expectEqual(loaded?.pulse, snap.pulse, "pulse rows round-trip exactly (state/merge enums Codable)")
    expect(abs((loaded?.lastRadarSuccessAt ?? .distantPast).timeIntervalSince(radarSuccess)) < 0.001, "lastRadarSuccessAt round-trips")
    expectEqual(loaded?.radar.first?.timestamp, "2026-06-16T08:00:00Z", "the row timestamp survives → the next launch ages it correctly")
    // Corrupt file → nil (never a crash, never a partial paint).
    try? Data("{ not json".utf8).write(to: tmp)
    expect(SnapshotStore.load(from: tmp) == nil, "a corrupt file loads as nil (clean cold start, no crash)")
    SnapshotStore.clear(at: tmp)
    expect(Snapshot(radar: [], pulse: [], lastRadarSuccessAt: nil, lastPulseSuccessAt: nil).isEmpty, "an all-empty snapshot isEmpty → cold start, no fabricated all-clear")
    expect(!snap.isEmpty, "a populated snapshot is not empty")

    // Reviews clock (WP 2026-07-17-002): round-trips when present, tolerant when absent —
    // a pre-WP snapshot on disk must still load (nil → the reviews gate stays closed).
    let withReviews = Snapshot(radar: radar, pulse: pulseRows,
                               lastRadarSuccessAt: radarSuccess, lastPulseSuccessAt: radarSuccess,
                               lastReviewsSuccessAt: radarSuccess)
    SnapshotStore.save(withReviews, to: tmp)
    expect(abs((SnapshotStore.load(from: tmp)?.lastReviewsSuccessAt ?? .distantPast).timeIntervalSince(radarSuccess)) < 0.001,
           "lastReviewsSuccessAt round-trips")
    if let oldJSON = try? JSONEncoder().encode(snap) {   // snap predates the field → key absent
        try? oldJSON.write(to: tmp)
        let old = SnapshotStore.load(from: tmp)
        expect(old != nil && old?.lastReviewsSuccessAt == nil,
               "a pre-WP snapshot decodes with a nil reviews clock (tolerant, fail-closed)")
        expect(old?.reviewsOwed == nil, "…and a nil owed baseline (tolerant decode, triage F2)")
    } else { expect(false, "encoding the legacy snapshot failed") }

    // Owed items round-trip (triage F2): the baseline itself persists, not just its clock.
    let owedItem = InboundItem(repo: "o/r", number: 9, title: "owed", url: "https://github.com/o/r/pull/9",
                               authorLogin: "colleague", authorType: "User", isPR: true, isDraft: false,
                               createdAt: "2026-07-10T00:00:00Z", updatedAt: "2026-07-15T00:00:00Z")
    let withOwed = Snapshot(radar: radar, pulse: pulseRows,
                            lastRadarSuccessAt: radarSuccess, lastPulseSuccessAt: radarSuccess,
                            lastReviewsSuccessAt: radarSuccess, reviewsOwed: [owedItem])
    SnapshotStore.save(withOwed, to: tmp)
    expectEqual(SnapshotStore.load(from: tmp)?.reviewsOwed, [owedItem],
                "the owed-review baseline round-trips through the snapshot")
    SnapshotStore.clear(at: tmp)
}

suite("SnapshotStore — launch-paint freshness is NEVER .fresh; it ages from the stalest lane (honest by construction) ⚠ [WP-1c]") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    let f9h = FreshnessModel.forSnapshot(radarSuccess: iso.date(from: "2026-06-16T01:00:00Z")!, pulseSuccess: iso.date(from: "2026-06-16T01:00:00Z")!, now: now)
    expectEqual(f9h, .stale(ageSeconds: 9 * 3600), "9h-old snapshot → stale(9h)")
    expectEqual(FreshnessModel.label(for: f9h), "Updated 9h ago", "the banner ages honestly (the '· as of last session' cue)")
    expect(f9h.isDegraded, "a snapshot paint ALWAYS shows the caution banner — never a bare, trusted-fresh reading")
    // Even a 10-second-old save is NOT .fresh — a snapshot is last-known-good, not confirmed live.
    let fRecent = FreshnessModel.forSnapshot(radarSuccess: now.addingTimeInterval(-10), pulseSuccess: now.addingTimeInterval(-10), now: now)
    if case .stale = fRecent { expect(true, "even a 10s-old snapshot is .stale, never .fresh (unconfirmed on launch)") }
    else { expect(false, "a recent snapshot must still be .stale, got \(fRecent)") }
    // Worst-of-both: the STALER lane governs the island-wide age (radar 1h, pulse 9h → 9h).
    let mixed = FreshnessModel.forSnapshot(radarSuccess: now.addingTimeInterval(-3600), pulseSuccess: now.addingTimeInterval(-9 * 3600), now: now)
    expectEqual(mixed, .stale(ageSeconds: 9 * 3600), "the stalest lane (pulse 9h) governs the one island-wide cue")
    // A lane that never succeeded (nil) is ignored; the present lane ages the banner (no crash).
    expectEqual(FreshnessModel.forSnapshot(radarSuccess: now.addingTimeInterval(-1800), pulseSuccess: nil, now: now), .stale(ageSeconds: 1800), "a nil lane is skipped; the present lane governs")
    expectEqual(FreshnessModel.forSnapshot(radarSuccess: nil, pulseSuccess: nil, now: now), .stale(ageSeconds: 0), "both nil → stale(0) (still degraded, never fresh)")
}

suite("SnapshotStore — comment excerpts NEVER reach disk (privacy; stripped at the write site) ⚠ [fix 2]") {
    // A radar row carrying a latest-comment excerpt, decoded from JSON (RadarRow's memberwise
    // init is module-internal; Codable is its public construction path). Carries the WP-3d′
    // identity fields (id + changeSignature) — the current schema.
    let inMemoryJSON = """
    {"radar":[{"id":"9001","repo":"o/r","title":"Fix login","subtitle":"@alice · commented","timestamp":"2026-06-16T08:00:00Z","urgency":70,"symbolName":"bubble.left","isCritical":false,"url":"https://github.com/o/r/issues/1","excerpt":"SECRET-COMMENT-BODY do not persist","changeSignature":"sig-9001"}],"pulse":[],"lastRadarSuccessAt":null,"lastPulseSuccessAt":null}
    """
    let snap = try? JSONDecoder().decode(Snapshot.self, from: Data(inMemoryJSON.utf8))
    expect(snap != nil, "fixture snapshot decodes")

    // Schema-upgrade honesty (WP-3d′ adds id/changeSignature to the persisted rows): a
    // pre-upgrade snapshot missing them fails decode and collapses to a CLEAN COLD START
    // (SnapshotStore.load → nil) — a one-time lost instant-paint, never a crash and never
    // a half-decoded row.
    let preUpgradeJSON = """
    {"radar":[{"repo":"o/r","title":"Fix login","subtitle":"@alice · commented","timestamp":"2026-06-16T08:00:00Z","urgency":70,"symbolName":"bubble.left","isCritical":false,"url":null,"excerpt":null}],"pulse":[],"lastRadarSuccessAt":null,"lastPulseSuccessAt":null}
    """
    expect((try? JSONDecoder().decode(Snapshot.self, from: Data(preUpgradeJSON.utf8))) == nil,
           "a pre-WP-3d′ snapshot (no id/changeSignature) → decode fails → clean cold start")
    if let snap {
        expectEqual(snap.radar.first?.excerpt, "SECRET-COMMENT-BODY do not persist", "the in-memory row carries the excerpt (control)")

        // The pure strip: excerpt nilled, every other field untouched.
        let stripped = snap.strippingExcerpts()
        expect(stripped.radar.first?.excerpt == nil, "strippingExcerpts nils the excerpt")
        expectEqual(stripped.radar.first?.title, "Fix login", "…and leaves the title")
        expectEqual(stripped.radar.first?.timestamp, "2026-06-16T08:00:00Z", "…and the timestamp (ages still work on relaunch)")
        expectEqual(stripped.radar.first?.url, "https://github.com/o/r/issues/1", "…and the URL (Open-on-GitHub still works)")

        // The write-site guarantee: save() strips unconditionally — the BYTES on disk carry no excerpt.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("githud-excerpt-\(UUID().uuidString).json")
        SnapshotStore.save(snap, to: tmp)
        let raw = String(decoding: (try? Data(contentsOf: tmp)) ?? Data(), as: UTF8.self)
        expect(!raw.isEmpty, "the snapshot was written")
        expect(!raw.contains("SECRET-COMMENT-BODY"), "the written JSON contains NO excerpt payload (comment bodies stay memory-only)")
        expect(raw.contains("Fix login"), "control: the rest of the row DID persist")
        expect(SnapshotStore.load(from: tmp)?.radar.first?.excerpt == nil, "the relaunch paint gets excerpt-free rows (honest degradation; live data restores them)")
        SnapshotStore.clear(at: tmp)
    }
}

// MARK: - WP-1b: GitHubClient five-site rate-limit backoff (URLProtocol-stubbed)

/// In-process URLProtocol stub — no real network. FIFO queue of canned responses; an empty
/// queue yields a default 200 so a leaked (un-fail-fasted) request is observable via the
/// request counter rather than hanging.
final class StubURLProtocol: URLProtocol {
    struct Stub { let status: Int; let headers: [String: String]; let body: Data }
    static var stubs: [Stub] = []
    static var requestCount = 0
    static func reset() { stubs = []; requestCount = 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubURLProtocol.requestCount += 1
        let stub = StubURLProtocol.stubs.isEmpty
            ? Stub(status: 200, headers: [:], body: Data("[]".utf8))
            : StubURLProtocol.stubs.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func stubClient() -> GitHubClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return GitHubClient(token: "ghp_test_token", session: URLSession(configuration: config))
}

/// A 429/403-with-`X-RateLimit-Reset` response (reset ~120s out → a positive pause).
func rateLimitStub(status: Int) -> StubURLProtocol.Stub {
    let reset = Int(Date().timeIntervalSince1970) + 120
    return StubURLProtocol.Stub(status: status,
        headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"],
        body: Data("{}".utf8))
}

func isRateLimited<T>(_ r: Result<T, GitHubClientError>) -> Bool {
    if case .failure(.rateLimited) = r { return true }
    return false
}

// Blocking wrappers (completions land on the URLSession queue; wait on the test thread —
// the session uses its own queues, so this never deadlocks).
func callNotifications(_ c: GitHubClient) -> Result<NotificationsResponse, GitHubClientError> {
    let sem = DispatchSemaphore(value: 0); var out: Result<NotificationsResponse, GitHubClientError>!
    c.fetchNotifications { out = $0; sem.signal() }; sem.wait(); return out
}
func callPulse(_ c: GitHubClient) -> Result<[PullRequestPulse], GitHubClientError> {
    let sem = DispatchSemaphore(value: 0); var out: Result<[PullRequestPulse], GitHubClientError>!
    c.fetchOpenPullRequests { out = $0; sem.signal() }; sem.wait(); return out
}
func callAuthor(_ c: GitHubClient) -> Result<(login: String, type: String, body: String?), GitHubClientError> {
    let sem = DispatchSemaphore(value: 0); var out: Result<(login: String, type: String, body: String?), GitHubClientError>!
    c.fetchLatestCommentAuthor(urlString: "https://api.github.com/repos/o/r/issues/comments/1") { out = $0; sem.signal() }; sem.wait(); return out
}
func callSubjectState(_ c: GitHubClient) -> Result<String, GitHubClientError> {
    let sem = DispatchSemaphore(value: 0); var out: Result<String, GitHubClientError>!
    c.fetchSubjectState(urlString: "https://api.github.com/repos/o/r/pulls/1") { out = $0; sem.signal() }; sem.wait(); return out
}
func callSelfLogin(_ c: GitHubClient) -> Result<String, GitHubClientError> {
    let sem = DispatchSemaphore(value: 0); var out: Result<String, GitHubClientError>!
    c.fetchAuthenticatedUserLogin { out = $0; sem.signal() }; sem.wait(); return out
}

suite("GitHubClient — the default session config stays cache-free (conditional-polling-no-cache) [WP-1b] ⚠") {
    let config = GitHubClient.ephemeralNoCacheConfiguration()
    expect(config.urlCache == nil, "urlCache is nil — no transparent revalidation swallowing our 304")
    expectEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData, "reloadIgnoringLocalCacheData preserves RUBRIC #8")
}

suite("GitHubClient — each of the FIVE call sites returns .rateLimited on a 429/403-with-reset AND sets the shared pause ⚠") {
    // For each endpoint: a fresh client, a single rate-limit response → the endpoint returns
    // .rateLimited (SET), then a SUBSEQUENT notifications poll fails fast without a network
    // request (the pause it set is SHARED across all sites).
    func proves(_ label: String, status: Int, _ call: @escaping (GitHubClient) -> Bool) {
        StubURLProtocol.reset()
        StubURLProtocol.stubs = [rateLimitStub(status: status)]
        let client = stubClient()
        expect(call(client), "\(label): a \(status) with X-RateLimit-Reset → .rateLimited")
        expectEqual(StubURLProtocol.requestCount, 1, "\(label): the call hit the network exactly once")
        expect(isRateLimited(callNotifications(client)), "\(label): the pause it SET is shared — a later notifications poll fails fast")
        expectEqual(StubURLProtocol.requestCount, 1, "\(label): the follow-up fired NO request (pause respected)")
    }
    proves("fetchNotifications", status: 403) { isRateLimited(callNotifications($0)) }
    proves("fetchLatestCommentAuthor", status: 429) { isRateLimited(callAuthor($0)) }
    proves("fetchSubjectState", status: 403) { isRateLimited(callSubjectState($0)) }
    proves("fetchAuthenticatedUserLogin", status: 429) { isRateLimited(callSelfLogin($0)) }
    proves("fetchOpenPullRequests (GraphQL)", status: 429) { isRateLimited(callPulse($0)) }
}

suite("GitHubClient — an active shared pause makes ALL FIVE sites fail fast, firing zero requests ⚠") {
    StubURLProtocol.reset()
    // One 403-with-reset via subject-state opens the shared pause.
    StubURLProtocol.stubs = [rateLimitStub(status: 403)]
    let client = stubClient()
    expect(isRateLimited(callSubjectState(client)), "the opening call rate-limits")
    expectEqual(StubURLProtocol.requestCount, 1, "one request opened the pause")
    // Now every site must fail fast — none of these fire a request.
    expect(isRateLimited(callNotifications(client)), "notifications respects the shared pause")
    expect(isRateLimited(callPulse(client)), "GraphQL pulse respects the shared pause")
    expect(isRateLimited(callAuthor(client)), "comment-author enrichment respects the shared pause")
    expect(isRateLimited(callSubjectState(client)), "subject-state respects the shared pause")
    expect(isRateLimited(callSelfLogin(client)), "self-login respects the shared pause")
    expectEqual(StubURLProtocol.requestCount, 1, "still exactly ONE request — five fail-fasts fired nothing (backoff honored at every site)")
}

suite("GitHubClient — a scope/SSO 403 (nonzero remaining, no Retry-After) is .http(403), opens NO pause, next call still fires ⚠ [WP-1c regression]") {
    // The dual of the rate-limit case: a 403 that is NOT a limit (the budget is intact —
    // X-RateLimit-Remaining is nonzero — and there's no Retry-After) is a forbidden/scope/SSO
    // error. It must NOT be mistaken for a rate limit, else a dead-scope token would silently
    // pause EVERY endpoint and never recover. It surfaces as .http(403) (→ the reducer's
    // auth-stop), opens no shared pause, and a follow-up call still fires a real request.
    StubURLProtocol.reset()
    let forbidden = StubURLProtocol.Stub(status: 403,
        headers: ["X-RateLimit-Remaining": "4999"],   // budget intact; no Retry-After, no reset
        body: Data("{\"message\":\"Resource not accessible by personal access token / SSO required\"}".utf8))
    StubURLProtocol.stubs = [forbidden]
    let client = stubClient()
    let r = callNotifications(client)
    if case .failure(.http(403, _)) = r { expect(true, "a nonzero-remaining 403 → .http(403), NOT .rateLimited") }
    else { expect(false, "expected .http(403), got \(r)") }
    expectEqual(StubURLProtocol.requestCount, 1, "the forbidden call fired exactly one request")
    // No shared pause opened → the follow-up FIRES a real request (an empty stub queue yields
    // the default 200, so requestCount incrementing proves the request actually went out).
    _ = callNotifications(client)
    expectEqual(StubURLProtocol.requestCount, 2, "the follow-up fired a real request — no shared pause was opened by the scope/SSO 403")
}

// MARK: - Reviews owed (WP 2026-07-17-002 — the standing source the inbox can't carry)

suite("Reviews search — decode the REAL response shape (committed fixture)") {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/reviews-search.json")
    guard let data = try? Data(contentsOf: url),
          let reading = try? InboundItem.reading(fromSearchData: data) else {
        expect(false, "reviews-search.json decodes"); return
    }
    expectEqual(reading.items.count, 2, "two owed reviews decode")
    expect(!reading.incomplete, "complete reading")
    expectEqual(reading.totalCount, 2, "totalCount rides through")
    expect(reading.items.allSatisfy { $0.isPR }, "is:pr query → every item a PR")
    expectEqual(reading.items.map { $0.number }, [513, 551], "oldest-first — the longest-owed review leads")
    expectEqual(reading.items[1].url, "https://github.com/acme/core/pull/551",
                "html url = the dedup match key")
}

suite("RadarReading × reviews — synthesis, dedup, adopt, and the merged radar") {
    func item(_ repo: String, _ n: Int, title: String = "t") -> InboundItem {
        InboundItem(repo: repo, number: n, title: title,
                    url: "https://github.com/\(repo)/pull/\(n)",
                    authorLogin: "alice", authorType: "User", isPR: true, isDraft: false,
                    createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-16T09:00:00Z")
    }
    func reading(_ items: [InboundItem], incomplete: Bool = false) -> InboundReading {
        InboundReading(items: items, incomplete: incomplete, totalCount: items.count)
    }

    // THE dogfood case (2026-07-17): notifications read, review still owed → the
    // synthetic surfaces at review_requested urgency with the prefixed id.
    var r = RadarReading()
    _ = r.adoptReviews(reading([item("acme/core", 551), item("acme/core", 513)]))
    let radar = r.radar()
    expectEqual(radar.count, 2, "both owed reviews surface with an empty inbox")
    expectEqual(Set(radar.map { $0.thread.id }),
                ["review-owed:acme/core#551", "review-owed:acme/core#513"],
                "prefixed ids — structurally disjoint from thread/inbound/pulse spaces")
    expectEqual(radar.first?.classification.urgency, 95, "review_requested urgency — it IS a review request")
    expect(r.consumeResolutions(), "first adoption arms the latch even with zero cached threads (reviews-only projection is real content)")
    expect(!r.consumeResolutions(), "…one-shot")

    // Dedup: the same PR as a REAL unread review_requested thread → the thread wins.
    let threadJSON = """
    [{"id":"real1","unread":true,"reason":"review_requested","updated_at":"t","latest_comment_author_login":"colleague",\
    "subject":{"title":"x","type":"PullRequest","url":"https://api.github.com/repos/acme/core/pulls/551"},\
    "repository":{"full_name":"acme/core","private":true,"owner":{"login":"acme","type":"Organization"}}}]
    """
    var deduped = RadarReading()
    deduped.adopt200(threads: (try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [], scopes: "repo")
    _ = deduped.adoptReviews(reading([item("acme/core", 551), item("acme/core", 513)]))
    let mergedIDs = deduped.radar().map { $0.thread.id }
    expectEqual(Set(mergedIDs), ["real1", "review-owed:acme/core#513"],
                "the real thread wins its PR (enrichment preserved); only the read-notification PR synthesizes")
    expectEqual(deduped.radar().first(where: { $0.thread.id == "real1" })?.thread.latestCommentAuthorLogin,
                "colleague", "…and the winning thread's enrichment survives")

    // AMBIENT thread on the same PR must NOT eat the synthetic (Codex P1): the read
    // review-request is gone, a later unread ci_activity thread shares the PR url, and
    // that ambient reason never surfaces — dropping the synthetic here re-opens the
    // structural miss. Distinct asks coexist.
    let ambientJSON = """
    [{"id":"amb1","unread":true,"reason":"ci_activity","updated_at":"t",\
    "subject":{"title":"x","type":"PullRequest","url":"https://api.github.com/repos/acme/core/pulls/551"},\
    "repository":{"full_name":"acme/core","private":true,"owner":{"login":"acme","type":"Organization"}}}]
    """
    var ambient = RadarReading()
    ambient.adopt200(threads: (try? NotificationThread.list(from: Data(ambientJSON.utf8))) ?? [], scopes: "repo")
    _ = ambient.adoptReviews(reading([item("acme/core", 551)]))
    expect(ambient.radar().map { $0.thread.id }.contains("review-owed:acme/core#551"),
           "an ambient ci_activity thread on the same PR never suppresses the owed review")

    // A TERMINALLY-RESOLVED review_requested thread can't claim the PR either (reopened
    // edge): its verdict suppresses the row, so only the synthetic can carry the ask.
    var reopened = RadarReading()
    reopened.adopt200(threads: (try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [], scopes: "repo")
    if let idx = reopened.threads.firstIndex(where: { $0.id == "real1" }) {
        reopened.applySubjectVerdict(at: idx, state: "merged")
    } else { expect(false, "real1 adopted") }
    _ = reopened.adoptReviews(reading([item("acme/core", 551)]))
    expectEqual(reopened.radar().map { $0.thread.id }, ["review-owed:acme/core#551"],
                "a dead review_requested thread yields the PR to the synthetic (never both hidden)")

    // Adopt: an incomplete search never removes standing truth.
    var flaky = RadarReading()
    _ = flaky.adoptReviews(reading([item("o/r", 1), item("o/r", 2)]))
    _ = flaky.consumeResolutions()
    _ = flaky.adoptReviews(reading([item("o/r", 1)], incomplete: true))
    expectEqual(flaky.radar().count, 2, "incomplete reading → baseline kept whole (fold-not-drop)")
    expect(!flaky.consumeResolutions(), "…and no change latch (nothing changed)")

    // Departure: a COMPLETE reading without the item removes it and arms the latch.
    _ = flaky.adoptReviews(reading([item("o/r", 1)]))
    expectEqual(flaky.radar().count, 1, "review landed / PR closed → the row departs on a complete reading")
    expect(flaky.consumeResolutions(), "departure arms the latch — a 304 tick still repaints")

    // DISCHARGE (Codex 5b P2): a real review_requested thread whose debt a complete
    // sweep proved repaid leaves "Needs you" — the CLI/API-review case, where the
    // notification stays unread forever and the read-state can never clear the row.
    var cliReviewed = RadarReading()
    cliReviewed.adopt200(threads: (try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [], scopes: "repo")
    _ = cliReviewed.adoptReviews(reading([item("acme/core", 551)]))   // owed: thread wins dedup
    expectEqual(cliReviewed.radar().map { $0.thread.id }, ["real1"], "owed + unread thread → the real row surfaces")
    _ = cliReviewed.adoptReviews(reading([]))   // review submitted via CLI — departure evidence
    expect(cliReviewed.radar().isEmpty, "the discharged review request leaves the radar (debt proven repaid)")
    expect(cliReviewed.suppressed().contains { $0.thread.id == "real1" },
           "…into the auditable suppressed set, never silently dropped")

    // Audit ORDER holds through the merge (land verdict P2): the discharged 95-urgency
    // row must LEAD the suppressed set — the probe audits prefix(25) under a
    // "most-likely-miss first" promise, and an append after hundreds of sorted rows
    // would bury the exact row the audit exists to catch.
    var audited = RadarReading()
    audited.adopt200(threads: ((try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [])
                            + ((try? NotificationThread.list(from: Data(ambientJSON.utf8))) ?? []),
                     scopes: "repo")
    _ = audited.adoptReviews(reading([item("acme/core", 551)]))
    _ = audited.adoptReviews(reading([]))
    expectEqual(audited.suppressed().first?.thread.id, "real1",
                "the discharged row leads the suppressed audit (urgency-sorted through the merge)")

    // RE-REQUEST generation (land verdict P1): the discharge binds to the notification
    // generation it repaid. Request B on the same PR re-notifies the SAME thread with a
    // bumped updated_at — it must surface even while the search index still lags B.
    func rrThread(_ updated: String) -> [NotificationThread] {
        let json = """
        [{"id":"real1","unread":true,"reason":"review_requested","updated_at":"\(updated)",\
        "subject":{"title":"x","type":"PullRequest","url":"https://api.github.com/repos/acme/core/pulls/551"},\
        "repository":{"full_name":"acme/core","private":true,"owner":{"login":"acme","type":"Organization"}}}]
        """
        return (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    }
    var rerequested = RadarReading()
    rerequested.adopt200(threads: rrThread("2026-07-17T01:00:00Z"), scopes: "repo")
    _ = rerequested.adoptReviews(reading([item("acme/core", 551)]))   // A owed
    _ = rerequested.adoptReviews(reading([]))                                        // A repaid → discharged
    expect(rerequested.radar().isEmpty, "generation A discharges (CLI review, thread unread)")
    rerequested.adopt200(threads: rrThread("2026-07-17T02:00:00Z"), scopes: "repo")  // B re-notifies; index lags
    _ = rerequested.adoptReviews(reading([]))                                        // search still empty
    expectEqual(rerequested.radar().map { $0.thread.id }, ["real1"],
                "request B is a NEW generation — never falsely re-discharged while the index lags")
    // …and when the index finally carries B, the binding dies with the candidacy.
    _ = rerequested.adoptReviews(reading([item("acme/core", 551)]))
    expectEqual(rerequested.radar().map { $0.thread.id }, ["real1"],
                "B indexed → owed again; the real thread wins the dedup as before")

    // Arrival-lag guard: a JUST-ARRIVED request whose notification beat the search
    // index was never owed-then-departed — absence alone must not discharge it.
    var justArrived = RadarReading()
    justArrived.adopt200(threads: (try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [], scopes: "repo")
    _ = justArrived.adoptReviews(reading([]))   // index hasn't caught up; url never owed
    expectEqual(justArrived.radar().map { $0.thread.id }, ["real1"],
                "a fresh request survives a lagging empty sweep (departure evidence required — never-miss)")

    // An INCOMPLETE baseline (seed / truncated union) never discharges: stale or
    // partial truth is not evidence the debt was repaid.
    var partial = RadarReading()
    partial.adopt200(threads: (try? NotificationThread.list(from: Data(threadJSON.utf8))) ?? [], scopes: "repo")
    _ = partial.adoptReviews(reading([item("acme/core", 551)]))
    let cappedPage = InboundReading(items: [item("o/r", 99)], incomplete: false, totalCount: 2)
    _ = partial.adoptReviews(cappedPage)   // truncated union: #551 kept, baseline incomplete
    expect(partial.radar().contains { $0.thread.id == "real1" },
           "a truncated baseline never discharges the real thread")

    // TRUNCATED page unions with the prior baseline (triage F1): a request landing on
    // an OLD PR sorts ahead (created asc) and pushes the youngest page item out — a
    // replace would fabricate its departure while the review is still owed.
    var capped = RadarReading()
    _ = capped.adoptReviews(reading([item("o/r", 1), item("o/r", 2)]))
    _ = capped.consumeResolutions()
    let page = InboundReading(items: [item("o/r", 0), item("o/r", 1)],   // #2 pushed past the cap
                              incomplete: false, totalCount: 3)
    _ = capped.adoptReviews(page)
    expectEqual(Set(capped.radar().map { $0.thread.id }),
                ["review-owed:o/r#0", "review-owed:o/r#1", "review-owed:o/r#2"],
                "a truncated page unions with prior truth — the pushed-out item never fabricates a departure")
    expect(capped.consumeResolutions(), "the union arrival repaints")
    // A COMPLETE page then rules: replace, departures render.
    _ = capped.adoptReviews(reading([item("o/r", 0)]))
    expectEqual(capped.radar().count, 1, "a complete page replaces the union (real departures render)")

    // Metadata motion on a STILL-owed PR (Codex P2 round 4): a retitle / new-commit
    // updated_at feeds the synthetic's title and ageing — the latch must arm even though
    // the url set is unchanged, or a 304-quiet inbox shows the stale row indefinitely.
    var retitled = RadarReading()
    _ = retitled.adoptReviews(reading([item("o/r", 5, title: "old title")]))
    _ = retitled.consumeResolutions()
    _ = retitled.adoptReviews(reading([item("o/r", 5, title: "new title")]))
    expect(retitled.consumeResolutions(), "a retitle on the same owed PR arms the repaint latch")
    _ = retitled.adoptReviews(reading([item("o/r", 5, title: "new title")]))
    expect(!retitled.consumeResolutions(), "an identical reading stays silent (no churn)")

    // Departure to EMPTY (found writing U3): the LAST owed review departing with zero
    // cached threads must still repaint — an empty COMPLETED sweep is live truth, not a
    // cold-start wipe. Without this the ghost row lingers while the inbox 304s (#416 class).
    var lastOne = RadarReading()
    _ = lastOne.adoptReviews(reading([item("o/r", 9)]))
    _ = lastOne.consumeResolutions()
    _ = lastOne.adoptReviews(reading([]))
    expect(lastOne.radar().isEmpty, "the last owed review departs")
    expect(lastOne.consumeResolutions(), "…and the empty projection still repaints (ghost row cleared on a 304 tick)")

    // changeKey: arrival/departure moves the radar change key (render on change only).
    let before = RadarPresenter.changeKey(for: flaky.radar())
    _ = flaky.adoptReviews(reading([item("o/r", 1), item("o/r", 3)]))
    expect(RadarPresenter.changeKey(for: flaky.radar()) != before, "an arriving owed review moves the change key")

    // SEED (triage F2): snapshot truth crosses the launch boundary — it renders, but it
    // never unlocks re-projection (a failed first tick must not wipe snapshot threads),
    // and the first COMPLETE sweep replaces it wholesale.
    var seeded = RadarReading()
    seeded.seedReviewsBaseline([item("o/r", 8)])
    expectEqual(seeded.radar().map { $0.thread.id }, ["review-owed:o/r#8"],
                "a seeded baseline renders its owed rows before the first sweep")
    seeded.resolvedSelf("me")   // arms the self latch, as a failed first tick would
    expect(!seeded.consumeResolutions(),
           "seed-only projection declines — a failed first tick never wipes the snapshot paint")
    _ = seeded.adoptReviews(reading([]))
    expect(seeded.radar().isEmpty, "the first COMPLETE sweep replaces the seed (review no longer owed)")
    expect(seeded.consumeResolutions(), "…and that real departure repaints")

    // The synthetic's html url round-trips (the Open-on-GitHub ceiling works).
    if let synthetic = flaky.radar().first(where: { $0.thread.id.hasPrefix("review-owed:") }) {
        expectEqual(RadarPresenter.htmlURL(for: synthetic.thread), "https://github.com/o/r/pull/1",
                    "api-form subject url converts back to the item's html url")
    } else { expect(false, "a synthetic row exists") }
}

// MARK: - RadarPipeline end-to-end (WP 2026-07-17-001 U3 — the LOOP under canned HTTP)
//
// The unit suites above pin the READING's policy; these pin the loop scaffolding the
// units can't see — pass ordering under the shared stub queue, the 304 re-verify path,
// verdict perishability across real refreshes, and the auth-stop leaving the reading
// untouched. The pipeline asserts off-main, so every drive hops a background queue
// (the ProbeCommand pattern).

func offMain<T>(_ body: @escaping () -> T) -> T {
    let sem = DispatchSemaphore(value: 0)
    var out: T!
    DispatchQueue.global().async { out = body(); sem.signal() }
    sem.wait()
    return out
}

func notifStub(_ threadsJSON: String, status: Int = 200) -> StubURLProtocol.Stub {
    StubURLProtocol.Stub(status: status,
        headers: ["X-OAuth-Scopes": "notifications, repo", "X-Poll-Interval": "60",
                  "X-RateLimit-Remaining": "4000"],
        body: Data(threadsJSON.utf8))
}
func jsonStub(_ json: String) -> StubURLProtocol.Stub {
    StubURLProtocol.Stub(status: 200, headers: [:], body: Data(json.utf8))
}
let loginJSON = #"{"login":"pro-vi"}"#
let openRRThread = """
[{"id":"n1","unread":true,"reason":"review_requested","updated_at":"2026-07-17T00:00:00Z",\
"subject":{"title":"needs my review","type":"PullRequest",\
"url":"https://api.github.com/repos/o/r/pulls/1","latest_comment_url":null},\
"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}]
"""
// The reviews-owed sweep (WP 2026-07-17-002) rides EVERY tick right after the
// notifications leg, so every e2e sequence stubs it: notif → reviews → enrichment.
let emptyReviews = #"{"total_count":0,"incomplete_results":false,"items":[]}"#

suite("RadarPipeline e2e — an open verdict is NEVER cached: every 200 re-verifies") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    // refresh #1: login + notifications + reviews sweep + subject-state(open) = 4 requests.
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(openRRThread),
                             jsonStub(emptyReviews), jsonStub(#"{"state":"open"}"#)]
    let r1 = offMain { pipeline.refresh() }
    if case .success(let res) = r1 {
        expectEqual(res.radar.map { $0.thread.id }, ["n1"], "open review request surfaces")
        expectEqual(res.subjectStateEnriched, 1, "subject verdict fetched")
        expect(res.reviewsComplete, "the reviews sweep completed on the same tick")
    } else { expect(false, "refresh#1 failed: \(r1)") }
    expectEqual(StubURLProtocol.requestCount, 4, "login + notifications + reviews + ONE subject GET")

    // refresh #2 (another 200): the open verdict was NOT cached → subject re-fetched.
    // Login is resolved (guarded) → notifications + reviews + subject = 3 more requests.
    StubURLProtocol.stubs = [notifStub(openRRThread), jsonStub(emptyReviews), jsonStub(#"{"state":"open"}"#)]
    _ = offMain { pipeline.refresh() }
    expectEqual(StubURLProtocol.requestCount, 7, "a second 200 re-verifies the perishable open verdict (and never re-resolves /user)")

    // refresh #3: the PR closed → terminal verdict stores → row leaves the radar.
    StubURLProtocol.stubs = [notifStub(openRRThread), jsonStub(emptyReviews), jsonStub(#"{"state":"closed"}"#)]
    let r3 = offMain { pipeline.refresh() }
    if case .success(let res) = r3 {
        expect(res.radar.isEmpty, "closed subject leaves the radar")
        expectEqual(res.suppressed.first?.thread.id, "n1", "…into the auditable suppressed set")
    } else { expect(false, "refresh#3 failed") }
}

suite("RadarPipeline e2e — 304 re-verify flips a resolved subject and arms the re-projection latch") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    // Seed: a 200 with the open thread.
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(openRRThread),
                             jsonStub(emptyReviews), jsonStub(#"{"state":"open"}"#)]
    _ = offMain { pipeline.refresh() }
    _ = pipeline.consumeResolutions()   // drain the self-resolution latch from the seed tick
    expectEqual(offMain { pipeline.recomputeRadar() }.count, 1, "seeded: one surfaced row")

    // 304 tick: first re-verify is due (distantPast baseline) → one subject GET → CLOSED.
    // The reviews sweep rides the 304 leg too (its own conditional economy comes from
    // search-side caching, not the notifications validator).
    StubURLProtocol.stubs = [notifStub("", status: 304), jsonStub(emptyReviews), jsonStub(#"{"state":"closed"}"#)]
    let counted = StubURLProtocol.requestCount
    let r304 = offMain { pipeline.refresh() }
    if case .success(let res) = r304 { expect(res.notModified, "304 leg taken") }
    else { expect(false, "304 refresh failed") }
    expectEqual(StubURLProtocol.requestCount, counted + 3, "the 304 tick fetched exactly one subject verdict (+ the reviews sweep)")
    expect(pipeline.consumeResolutions(), "the flip armed the consolidated latch")
    expect(offMain { pipeline.recomputeRadar() }.isEmpty, "re-projection drops the resolved row without a 200")

    // Another 304 inside the 600s window: throttled — NO subject GET.
    StubURLProtocol.stubs = [notifStub("", status: 304), jsonStub(emptyReviews)]
    let before = StubURLProtocol.requestCount
    _ = offMain { pipeline.refresh() }
    expectEqual(StubURLProtocol.requestCount, before + 2, "within the throttle window a 304 fires only itself + the reviews sweep")
    expect(!pipeline.consumeResolutions(), "…and nothing arms (an unchanged reviews set stays silent)")
}

suite("Just cleared — the departure buffer captures every knowable door (plan 2026-07-21-001)") {
    func mk(_ id: String, reason: String = "mention") -> NotificationThread {
        let json = "[{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"t\",\"subject\":{\"title\":\"T\(id)\",\"type\":\"PullRequest\",\"url\":\"https://api.github.com/repos/o/r/pulls/1\"},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!.first!
    }
    // Feed drop: surfaced thread absent from the next 200 → captured, reason-LESS.
    var r = RadarReading()
    r.adopt200(threads: [mk("a"), mk("b")], scopes: "repo")
    r.adopt200(threads: [mk("b")], scopes: "repo")
    expectEqual(r.clearedRows().map { $0.id }, ["a"], "a feed drop lands in the buffer")
    expect(r.clearedRows().first?.whyText == nil, "…reason-less — a plain departure never guesses")
    // Re-arrival: back on the radar means NOT cleared.
    r.adopt200(threads: [mk("a"), mk("b")], scopes: "repo")
    expect(r.clearedRows().isEmpty, "a re-arriving thread leaves the buffer")
    // Read door: the read-check's removal carries its reason.
    _ = r.applyThreadsRead(ids: ["a"])
    expectEqual(r.clearedRows().map { $0.whyText }, ["read ✓"], "the read door captures with its reason")
    // Verdict door: only asks that DIE with the subject depart on a verdict.
    var v = RadarReading()
    v.adopt200(threads: [mk("rr", reason: "review_requested"), mk("cm", reason: "comment")], scopes: "repo")
    v.applySubjectVerdict(at: 0, state: "merged")
    v.applySubjectVerdict(at: 1, state: "merged")
    expectEqual(v.clearedRows().map { $0.whyText }, ["merged"], "a merged review request captures; the read-me comment does NOT (it never departed)")
    // Suppressed departures never capture (not "cleared from Needs you").
    var sup = RadarReading()
    sup.adopt200(threads: [mk("ci", reason: "ci_activity")], scopes: "repo")   // default-off reason
    sup.adopt200(threads: [], scopes: "repo")
    expect(sup.clearedRows().isEmpty, "a suppressed thread's exit is not a departure receipt")
    // Cap 8, newest first.
    var cap = RadarReading()
    cap.adopt200(threads: (0..<10).map { mk("t\($0)") }, scopes: "repo")
    cap.adopt200(threads: [], scopes: "repo")
    expectEqual(cap.clearedRows().count, 8, "the buffer caps at 8")
    // Caption copy (B1, ratified) + spoken form.
    expectEqual(PlainWords.justClearedCaption(2), "2 just cleared (show)", "caption B1 verbatim")
    expectEqual(PlainWords.justClearedCaptionSpoken(2), "2 just cleared, show", "spoken form")
}

suite("Just cleared — the discharged receipt survives the feed (land-triage F1/F2)") {
    func rrThread(_ updated: String) -> [NotificationThread] {
        let json = "[{\"id\":\"d1\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"\(updated)\",\"subject\":{\"title\":\"x\",\"type\":\"PullRequest\",\"url\":\"https://api.github.com/repos/o/r/pulls/1\"},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}]"
        return (try? NotificationThread.list(from: Data(json.utf8)))!
    }
    func owed() -> InboundReading {
        let item = InboundItem(repo: "o/r", number: 1, title: "x", url: "https://github.com/o/r/pull/1",
                               authorLogin: "colleague", authorType: "User", isPR: true, isDraft: false,
                               createdAt: "2026-07-10T00:00:00Z", updatedAt: "2026-07-15T00:00:00Z")
        return InboundReading(items: [item], incomplete: false, totalCount: 1)
    }
    // The CLI-review case end to end: owed → discharged → the receipt is born…
    var r = RadarReading()
    r.adopt200(threads: rrThread("t1"), scopes: "repo")
    _ = r.adoptReviews(owed())
    _ = r.adoptReviews(InboundReading(items: [], incomplete: false, totalCount: 0))
    expectEqual(r.clearedRows().map { $0.whyText }, ["review submitted ✓"], "the discharge mints its receipt")
    // …and SURVIVES every 200 that keeps listing the still-unread thread (pre-F1 the
    // feed-membership re-arrival rule deleted it within one tick).
    r.adopt200(threads: rrThread("t1"), scopes: "repo")
    expectEqual(r.clearedRows().map { $0.whyText }, ["review submitted ✓"],
                "a 200 still listing the discharged thread never eats the receipt (it is not ON the radar)")
    // F1 RESIDUAL (round 3): the discharged thread is OFF the glass — the read-check
    // must not target it, and even a direct read event must not overwrite its receipt
    // with "read ✓" (the receipt records why it LEFT THE RADAR — it left by discharge;
    // the later read happened off-glass).
    expect(r.readCheckTargets().allSatisfy { r.threads[$0].id != "d1" },
           "a discharged thread is never a read-check target")
    var offGlassRead = r
    _ = offGlassRead.applyThreadsRead(ids: ["d1"])   // belt: a direct read event anyway
    expectEqual(offGlassRead.clearedRows().map { $0.whyText }, ["review submitted ✓"],
                "…and a read of the off-glass thread never overwrites the discharge receipt")
    // …and keeps its reason when the thread finally leaves the feed (nil never downgrades).
    r.adopt200(threads: [], scopes: "repo")
    expectEqual(r.clearedRows().map { $0.whyText }, ["review submitted ✓"],
                "the eventual feed departure never downgrades a known reason to nil")
    // A GENUINE radar re-arrival still un-clears: a re-request bumps the generation,
    // the thread surfaces again, and the receipt yields to the live row.
    r.adopt200(threads: rrThread("t2"), scopes: "repo")
    expect(r.radar().contains { $0.thread.id == "d1" }, "the re-request surfaces (new generation)")
    expect(r.clearedRows().isEmpty, "…and being back on the radar removes the receipt")
}

suite("RadarPipeline e2e — a read-emptied radar projects even when the reviews sweep never succeeded (land-triage F2)") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    // Seed: one surfaced row; the reviews sweep FAILS (garbage) → sweptThisRun stays false.
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(openRRThread),
                             jsonStub("not json"), jsonStub(#"{"state":"open"}"#)]
    _ = offMain { pipeline.refresh() }
    _ = pipeline.consumeResolutions()
    expectEqual(offMain { pipeline.recomputeRadar() }.count, 1, "seeded, sweep failing")
    // 304 tick: sweep fails again; the re-verify window runs (subject open, no flip)
    // and the read check REMOVES the last row — a positive per-thread verification.
    StubURLProtocol.stubs = [notifStub("", status: 304), jsonStub("not json"),
                             jsonStub(#"{"state":"open"}"#), jsonStub(#"{"unread":false}"#)]
    _ = offMain { pipeline.refresh() }
    expect(pipeline.consumeResolutions(),
           "the verified-empty projection renders — the receipt and its row can never coexist (pre-F2 this declined)")
    expect(offMain { pipeline.recomputeRadar() }.isEmpty, "…and the glass clears")
}

suite("RadarPipeline e2e — a READ thread clears on a 304 tick (the feed 304s across read transitions)") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    // THE dogfood shape (2026-07-18): a mention with a RELEASE subject — outside the
    // subject-state re-verify's PR/Issue world entirely, so only the read check can
    // ever clear it while the inbox is quiet.
    let releaseMention = """
    [{"id":"n7","unread":true,"reason":"mention","updated_at":"2026-07-18T00:00:00Z",\
    "subject":{"title":"v0.46.0","type":"Release",\
    "url":"https://api.github.com/repos/facebook/lexical/releases/123","latest_comment_url":null},\
    "repository":{"full_name":"facebook/lexical","private":false,"owner":{"login":"facebook","type":"Organization"}}}]
    """
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(releaseMention), jsonStub(emptyReviews)]
    _ = offMain { pipeline.refresh() }
    _ = pipeline.consumeResolutions()
    expectEqual(offMain { pipeline.recomputeRadar() }.map { $0.thread.id }, ["n7"], "the release mention surfaces")

    // User visits the release page → GitHub marks the thread read → the feed 304s
    // anyway (read transitions never bump its Last-Modified). The throttled read check
    // fetches the thread and sees unread:false → the row leaves NOW, not whenever an
    // unrelated notification happens to arrive.
    StubURLProtocol.stubs = [notifStub("", status: 304), jsonStub(emptyReviews),
                             jsonStub(#"{"unread":false}"#)]
    let counted = StubURLProtocol.requestCount
    _ = offMain { pipeline.refresh() }
    expectEqual(StubURLProtocol.requestCount, counted + 3,
                "304 + reviews sweep + ONE thread read-check (a Release never gets a subject GET)")
    expect(pipeline.consumeResolutions(), "the read transition arms the repaint latch")
    expect(offMain { pipeline.recomputeRadar() }.isEmpty, "the read row clears on the quiet inbox")

    // Negative direction: still-unread (or a failed check) NEVER removes — only a
    // positive unread:false from GitHub does (never-miss).
    let pipeline2 = RadarPipeline(client: stubClient())
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(releaseMention), jsonStub(emptyReviews)]
    _ = offMain { pipeline2.refresh() }
    _ = pipeline2.consumeResolutions()
    StubURLProtocol.stubs = [notifStub("", status: 304), jsonStub(emptyReviews),
                             jsonStub(#"{"unread":true}"#)]
    _ = offMain { pipeline2.refresh() }
    expectEqual(offMain { pipeline2.recomputeRadar() }.map { $0.thread.id }, ["n7"],
                "a still-unread thread survives its read check")
    expect(!pipeline2.consumeResolutions(), "…and nothing arms (no churn)")
}

suite("RadarPipeline e2e — enrichment pass ORDER: subject-state consumes the stub queue before comment-author") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    // One thread needing BOTH passes. The FIFO stub queue is the order oracle: if the
    // author pass ran first it would consume the subject JSON (and fail to decode a
    // LatestComment), leaving the author un-enriched — the assertions below would fail.
    let both = """
    [{"id":"n2","unread":true,"reason":"mention","updated_at":"2026-07-17T00:00:00Z",\
    "subject":{"title":"q","type":"Issue",\
    "url":"https://api.github.com/repos/o/r/issues/2",\
    "latest_comment_url":"https://api.github.com/repos/o/r/issues/comments/9"},\
    "repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}]
    """
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(both),
                             jsonStub(emptyReviews),
                             jsonStub(#"{"state":"open"}"#),
                             jsonStub(#"{"user":{"login":"colleague","type":"User"},"body":"ping"}"#)]
    let r = offMain { pipeline.refresh() }
    if case .success(let res) = r {
        expectEqual(res.subjectStateEnriched, 1, "subject pass ran (first)")
        expectEqual(res.enriched, 1, "author pass ran (second) — FIFO order proves the F6 discipline")
        expectEqual(res.radar.first?.thread.latestCommentAuthorLogin, "colleague", "author landed on the thread")
    } else { expect(false, "refresh failed") }
}

suite("RadarPipeline e2e — an auth-stop tick leaves the reading untouched") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub(openRRThread),
                             jsonStub(emptyReviews), jsonStub(#"{"state":"open"}"#)]
    _ = offMain { pipeline.refresh() }
    _ = pipeline.consumeResolutions()
    // A scope/SSO 403 (budget intact → .http(403), the reducer's auth-stop input).
    StubURLProtocol.stubs = [StubURLProtocol.Stub(status: 403,
        headers: ["X-RateLimit-Remaining": "4999"], body: Data("{}".utf8))]
    let r = offMain { pipeline.refresh() }
    if case .failure = r { expect(true, "the tick fails honestly") }
    else { expect(false, "expected failure") }
    expectEqual(offMain { pipeline.recomputeRadar() }.map { $0.thread.id }, ["n1"],
                "the cached reading survives the failed tick — last-good is never wiped")
    expect(!pipeline.consumeResolutions(), "no latch armed by a failure")
}

suite("RadarPipeline e2e — the reviews sweep surfaces the READ-notification review and fails closed") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    let oneOwed = """
    {"total_count":1,"incomplete_results":false,"items":[\
    {"number":7,"title":"needs my review (read notification)","html_url":"https://github.com/o/r/pull/7",\
    "repository_url":"https://api.github.com/repos/o/r","created_at":"2026-07-10T00:00:00Z",\
    "updated_at":"2026-07-15T00:00:00Z","draft":false,\
    "user":{"login":"colleague","type":"User"},"pull_request":{}}]}
    """
    // THE dogfood shape (acme/core #551/#513): empty inbox — the notification was read — but
    // the search still owes a review. The synthetic is the ONLY radar row.
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub("[]"), jsonStub(oneOwed)]
    let r1 = offMain { pipeline.refresh() }
    if case .success(let res) = r1 {
        expectEqual(res.radar.map { $0.thread.id }, ["review-owed:o/r#7"],
                    "the owed review surfaces with a clean inbox — the inbox can't carry it, the search does")
        expect(res.reviewsComplete, "a complete sweep confirms")
    } else { expect(false, "refresh failed: \(r1)") }
    expect(pipeline.consumeResolutions(), "arrival armed the re-projection latch")

    // A sweep that fails to decode: the tick still succeeds (never-block), the baseline
    // holds last-good (never-miss), but the CONFIRMATION is withheld (fail-closed).
    StubURLProtocol.stubs = [notifStub("[]"), jsonStub("not json")]
    let r2 = offMain { pipeline.refresh() }
    if case .success(let res) = r2 {
        expectEqual(res.radar.map { $0.thread.id }, ["review-owed:o/r#7"],
                    "a broken sweep never drops the standing row")
        expect(!res.reviewsComplete, "…but it cannot confirm (the affirmation gate stays closed)")
    } else { expect(false, "a broken reviews sweep must not fail the tick") }
    expect(!pipeline.consumeResolutions(), "no change, no latch")

    // The review lands: a complete EMPTY sweep clears the row and repaints.
    StubURLProtocol.stubs = [notifStub("[]"), jsonStub(emptyReviews)]
    let r3 = offMain { pipeline.refresh() }
    if case .success(let res) = r3 {
        expect(res.radar.isEmpty, "review submitted → the owed row departs")
        expect(res.reviewsComplete, "the empty sweep is a real, confirming reading")
    } else { expect(false, "refresh failed") }
    expect(pipeline.consumeResolutions(), "departure-to-empty repaints (no ghost row on a 304-quiet inbox)")

    // TRUNCATED page (no silent caps, Codex P2 round 5): totalCount beyond the page →
    // the items still adopt and render (partial beats blank) but the sweep must NOT
    // confirm — "complete" with an invisible tail would arm the caught-up gate over
    // owed reviews the page never carried.
    let truncated = """
    {"total_count":2,"incomplete_results":false,"items":[\
    {"number":7,"title":"one of two","html_url":"https://github.com/o/r/pull/7",\
    "repository_url":"https://api.github.com/repos/o/r","created_at":"2026-07-10T00:00:00Z",\
    "updated_at":"2026-07-15T00:00:00Z","draft":false,\
    "user":{"login":"colleague","type":"User"},"pull_request":{}}]}
    """
    StubURLProtocol.stubs = [notifStub("[]"), jsonStub(truncated)]
    let r4 = offMain { pipeline.refresh() }
    if case .success(let res) = r4 {
        expectEqual(res.radar.map { $0.thread.id }, ["review-owed:o/r#7"],
                    "the truncated page's items still surface (partial beats blank)")
        expect(!res.reviewsComplete, "…but a capped page never confirms (no silent caps)")
    } else { expect(false, "refresh failed") }
}

suite("RadarPipeline e2e — a SEEDED baseline survives a first tick whose reviews search fails (triage F2)") {
    StubURLProtocol.reset()
    let pipeline = RadarPipeline(client: stubClient())
    pipeline.seedReviewsBaseline([InboundItem(
        repo: "o/r", number: 9, title: "owed since last session",
        url: "https://github.com/o/r/pull/9", authorLogin: "colleague", authorType: "User",
        isPR: true, isDraft: false,
        createdAt: "2026-07-10T00:00:00Z", updatedAt: "2026-07-15T00:00:00Z")])
    // First tick: notifications 200 (empty inbox) + reviews search DECODE FAILURE.
    // Pre-seed this exact tick wiped the still-owed row (radar() had no lane to merge).
    StubURLProtocol.stubs = [jsonStub(loginJSON), notifStub("[]"), jsonStub("not json")]
    let r = offMain { pipeline.refresh() }
    if case .success(let res) = r {
        expectEqual(res.radar.map { $0.thread.id }, ["review-owed:o/r#9"],
                    "the seeded owed row survives the failed sweep — last-good crosses the launch boundary")
        expect(!res.reviewsComplete, "the failed sweep cannot confirm")
    } else { expect(false, "refresh failed: \(r)") }
    // A later COMPLETE sweep replaces the seed (the review landed).
    StubURLProtocol.stubs = [notifStub("[]"), jsonStub(emptyReviews)]
    if case .success(let res2) = offMain({ pipeline.refresh() }) {
        expect(res2.radar.isEmpty, "a complete sweep supersedes the seed")
        expect(res2.reviewsComplete, "…and confirms")
    } else { expect(false, "second refresh failed") }
}

// MARK: - PillAccessibilityPresenter (WP-5i — the collapsed pill's VoiceOver value)
//
// The pill is the product's thesis surface and was mute (`CollapsedPillView` set a
// static "githud — expand" label, never a value). This is the gray-swap a11y law's
// ultimate test: does the SPOKEN value carry the same meaning the shape/color/count
// visuals do? These are the runnable half of that proof — driving real VoiceOver is
// not possible headless (see WP-5i's report).

suite("PillAccessibilityPresenter — mirrors CollapsedPillView's own priority (loading → needs-you [+critical] → gauge → all-clear), degraded prefix composes with every case ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!

    // Build real RadarRows the sanctioned way (JSON → NotificationThread → classify →
    // RadarPresenter.row), same pipeline every other radar suite in this file uses —
    // RadarRow has no public memberwise init across the module boundary.
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-06-16T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    func pr(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState, draft: Bool = false,
            created: String = "2026-06-16T08:00:00Z", updated: String = "2026-06-16T08:00:00Z") -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: created, updatedAt: updated, ci: ci, review: r, merge: m)
    }
    func pulseRows(_ prs: [PullRequestPulse]) -> [PulseRow] { prs.map { PulsePresenter.row(for: $0, now: now) } }

    // 1) loading — never fakes a caught-up before the first radar lands (mirrors the
    // pill's dim dot glyph, shown instead of a check). D-copy plainspoken: the value
    // carries the wordmark ITSELF, and StatusGlyphPresenter.toolTip no longer re-prefixes
    // it — that pair was the "githud — githud, loading" double wordmark (see the tooltip suite).
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], loading: true),
                "githud — checking GitHub", "loading state (D-copy plainspoken)")

    // 2) N need you (no critical) — the plan's own literal examples.
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["review_requested"])),
                "1 needs you", "singular count")
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["review_requested", "review_requested", "review_requested"])),
                "3 need you", "plural count — the plan's literal '3 need you'")

    // 3) critical present — the ONE reserved color-doctrine emergency crosses to speech
    // too, same as it crosses to the collapsed pill's glyph color. D-copy NAMES it
    // ("a security alert", not the vaguer "critical alert").
    //
    // ⚠ TRIPWIRE: this copy HARD-COUPLES to SignalClassifier.criticalReasons having
    // exactly the one member "security_alert" — if that set ever grows (or renames), a
    // critical row might not BE a security alert and the spoken sentence becomes a lie.
    // The assert below trips the moment the set's cardinality changes, pointing here.
    expectEqual(SignalClassifier.criticalReasons, ["security_alert"],
                "TRIPWIRE — the ', including a security alert' copy is valid only while criticalReasons == {security_alert}")
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["review_requested", "security_alert"])),
                "2 need you, including a security alert", "critical present — names the one reserved emergency")
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["security_alert"])),
                "1 needs you, including a security alert", "critical present, singular count")

    // 4) caught up — no radar, no open PRs. D-copy plainspoken: the same affirmation the
    // expanded island prints (CaughtUpPresenter.caughtUpLine — one home, no drift).
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], clearConfirmed: true), "You're all caught up", "caught-up value")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], clearConfirmed: true), CaughtUpPresenter.caughtUpLine,
                "spoken clear value IS the island's affirmation line (shared constant)")

    // 5) the caught-up gauge — the plan's own literal '2 ready, 1 blocked' example —
    // plus the waiting-only fallback (neither ready nor blocked present).
    let mixedGauge = pulseRows([pr(1, .passing, .approved, .mergeable), pr(2, .passing, .approved, .mergeable),
                                pr(3, .failing, .approved, .mergeable)])
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: mixedGauge),
                "2 ready, 1 blocked", "gauge — the plan's literal example")
    let waitingOnly = pulseRows([pr(4, .pending, .approved, .mergeable)])
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: waitingOnly), "1 waiting", "waiting-only gauge")

    // 6) drafts/stale PRs never enter the glance — mirrors CollapsedPillView's own
    // `pulse.filter { !$0.isDraft && !$0.isStale }` before it computes the gauge.
    let draftRow = pulseRows([pr(9, .failing, .approved, .mergeable, draft: true)]).first!
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [draftRow], clearConfirmed: true), "You're all caught up", "draft-only PRs → caught up (excluded from the gauge)")
    let staleRow = pulseRows([pr(10, .passing, .approved, .mergeable, created: "2026-04-01T00:00:00Z", updated: "2026-04-01T00:00:00Z")]).first!
    expect(staleRow.isStale, "sanity: the constructed row is actually stale relative to `now`")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [staleRow], clearConfirmed: true), "You're all caught up", "stale-only PRs → caught up (excluded from the gauge)")

    // 7) degraded reading — the D-copy prefix "Reading may be stale — updated {age} ago. "
    // PREPENDS to every case above (composes, never replaces): `caution` marks a degraded
    // READING, not a data state, mirroring the pill's stale-clock glyph which renders
    // independent of the rest of the glyph stack. The age speaks the banner's own
    // vocabulary (FreshnessModel.ageText): 400s → 6m, 480s → 8m.
    let degraded = Freshness.stale(ageSeconds: 400)
    expect(degraded.isDegraded, "sanity: .stale is degraded")
    expect(!Freshness.fresh.isDegraded, "sanity: .fresh is never degraded")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], freshness: degraded, loading: true),
                "Reading may be stale — updated 6m ago. githud — checking GitHub", "degraded + loading")
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["review_requested"]), freshness: degraded),
                "Reading may be stale — updated 6m ago. 1 needs you", "degraded + needs-you")
    expectEqual(PillAccessibilityPresenter.value(rows: radarRows(["security_alert"]), freshness: degraded),
                "Reading may be stale — updated 6m ago. 1 needs you, including a security alert", "degraded + critical present")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: mixedGauge, freshness: degraded),
                "Reading may be stale — updated 6m ago. 2 ready, 1 blocked", "degraded + gauge")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], freshness: .failing(consecutive: 3, ageSeconds: 480),
                                                 clearConfirmed: true),
                "Reading may be stale — updated 8m ago. You're all caught up", "degraded (.failing) + caught-up")
    // ageSeconds == 0 on a degraded reading ⇔ NO success ever recorded (.failing can fire
    // before the first success) — the prefix must not fabricate an update that never
    // happened, so it stays age-free there (the honest fallback, pinned).
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], freshness: .failing(consecutive: 2, ageSeconds: 0), loading: true),
                "Reading may be stale. githud — checking GitHub",
                "degraded with NO recorded success (age 0) → age-free prefix, never a fabricated timestamp")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: [], clearConfirmed: true), "You're all caught up", "fresh (default) → no prefix, unchanged")
}

// MARK: - PulsePresenter.sections(for: [PulseRow]) — the ONE home of the live-work rule (WP-6a)

suite("PulsePresenter — sections(for: rows) regroups presented rows by their carried facts (WP-6a dedupe) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-23T12:00:00Z")!
    func at(daysAgo d: Double) -> String { iso.string(from: now.addingTimeInterval(-d * 86_400)) }
    func mk(_ n: Int, _ ci: CIState, draft: Bool = false, updatedDaysAgo: Double = 1) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: at(daysAgo: 30), updatedAt: at(daysAgo: updatedDaysAgo),
                         ci: ci, review: .approved, merge: .mergeable)
    }
    let live1  = mk(1, .passing)                              // active (ready)
    let live2  = mk(2, .failing)                              // active (blocked)
    let rotten = mk(3, .failing, updatedDaysAgo: 111)         // stale (untouched 14d+)
    let wip    = mk(4, .passing, draft: true)                 // draft

    // 1) A flat, presenter-ordered [PulseRow] (the transport the poll/snapshot spine uses)
    // round-trips through sections(for:) to the SAME three groups, order preserved —
    // active→stale→drafts in, active/stale/drafts out.
    let flat = PulsePresenter.rows(for: [live1, live2, rotten, wip], now: now)
    let regrouped = PulsePresenter.sections(for: flat)
    let pipeline = PulsePresenter.sections(for: [live1, live2, rotten, wip], now: now)
    expectEqual(regrouped, pipeline, "regrouping presented rows == the pipeline's own sections (no drift possible)")
    expectEqual(regrouped.active.map { $0.repo }, ["o/r #2", "o/r #1"], "active: blocked leads ready (input order preserved)")
    expectEqual(regrouped.stale.map { $0.repo }, ["o/r #3"], "the rotting PR lands in stale")
    expectEqual(regrouped.drafts.map { $0.repo }, ["o/r #4"], "the WIP draft lands in drafts")

    // 2) The live-work rule itself: active excludes BOTH facts; the excluded rows are
    // exactly the stale + drafts groups (nothing dropped, nothing duplicated).
    expect(regrouped.active.allSatisfy { !$0.isDraft && !$0.isStale }, "active == !isDraft && !isStale (the deduped rule)")
    expect(regrouped.stale.allSatisfy { !$0.isDraft && $0.isStale }, "stale == !isDraft && isStale")
    expect(regrouped.drafts.allSatisfy { $0.isDraft }, "drafts == isDraft (age-independent)")
    expectEqual(regrouped.active.count + regrouped.stale.count + regrouped.drafts.count, flat.count,
                "the three groups partition the input (no row lost or double-counted)")

    // 3) Gauge parity — the drawn pill and the spoken a11y value both compute the gauge
    // over sections(for:).active; assert that path equals the historical inline filter.
    let gaugeViaSections = PulsePresenter.gauge(rows: PulsePresenter.sections(for: flat).active)
    let gaugeViaFilter = PulsePresenter.gauge(rows: flat.filter { !$0.isDraft && !$0.isStale })
    expectEqual(gaugeViaSections?.ready, gaugeViaFilter?.ready, "gauge over .active == gauge over the old inline filter (ready)")
    expectEqual(gaugeViaSections?.blocked, gaugeViaFilter?.blocked, "gauge over .active == gauge over the old inline filter (blocked)")
    expectEqual(gaugeViaSections?.blocked, 1, "the stale blocked PR stays out; only the live blocked one counts")
    expectEqual(gaugeViaSections?.ready, 1, "only the live ready PR counts")

    // 4) VoiceOver parity with the visible pill: the a11y presenter (which now consumes the
    // same sections API) still excludes drafts+stale from the spoken gauge.
    let flatRows = flat
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: flatRows), "1 ready, 1 blocked",
                "spoken gauge == drawn gauge over the same sectioned data")
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: PulsePresenter.sections(for: flatRows).drafts + PulsePresenter.sections(for: flatRows).stale,
                                                 clearConfirmed: true),
                "You're all caught up", "stale+draft-only input → spoken caught-up (nothing live to gauge)")

    // 5) Empty input → empty sections (and a nil gauge downstream).
    let empty = PulsePresenter.sections(for: [PulseRow]())
    expect(empty.active.isEmpty && empty.stale.isEmpty && empty.drafts.isEmpty, "empty in → empty sections")
    expectEqual(PulsePresenter.gauge(rows: empty.active), nil, "empty active → nil gauge (pill falls back to bare check)")
}

// MARK: - StatusGlyphPresenter (WP-5g — D-glyph `constant-mark-count-text`, amended)
//
// The menu-bar glyph's trust logic: with the island hidden this is the ONLY ambient
// surface, so its priority/composition matrix must never claim a state the data can't
// back. Tested like PillAccessibilityPresenter (same inputs, same pipeline builders) —
// the AppKit half (StatusItemController) only translates descriptors to template ink.

suite("StatusGlyphPresenter — priority: loading → critical → action → clear (the classifier's own hierarchy) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-06T10:00:00Z")!

    // Real RadarRows the sanctioned way (JSON → NotificationThread → classify → row) —
    // same pipeline as the pill-presenter suite (RadarRow has no public memberwise init).
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-07-06T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    func pulseRows(_ prs: [PullRequestPulse]) -> [PulseRow] { prs.map { PulsePresenter.row(for: $0, now: now) } }
    func pr(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: "2026-07-06T08:00:00Z", updatedAt: "2026-07-06T08:00:00Z", ci: ci, review: r, merge: m)
    }
    let degraded = Freshness.stale(ageSeconds: 400)
    let criticalMix = radarRows(["review_requested", "security_alert"])   // 2 rows, one critical
    expect(criticalMix.contains { $0.isCritical }, "sanity: the security_alert row is critical")

    // 1) loading outranks EVERYTHING — even a critical radar under a degraded reading.
    // Pre-first-poll there is no reading to distrust, so no dashed arcs either.
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], loading: true), .loading, "loading, empty")
    expectEqual(StatusGlyphPresenter.descriptor(rows: criticalMix, freshness: degraded, loading: true),
                .loading, "loading outranks critical + degraded (total, never partial)")

    // 2) critical outranks action: ANY isCritical row → shield, count = the TOTAL row
    // count (same as the pill: shield glyph, whole-radar count).
    expectEqual(StatusGlyphPresenter.descriptor(rows: criticalMix),
                .critical(countText: "2", degraded: false), "critical mix → shield + total count")
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["security_alert"])),
                .critical(countText: "1", degraded: false), "critical alone")

    // 3) action: rows present, none critical → the locked-pupil g + count.
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["review_requested"])),
                .action(countText: "1", degraded: false), "action, singular")
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["review_requested", "mention", "assign"])),
                .action(countText: "3", degraded: false), "action, plural")

    // 4) clear: no rows → the g at ease (half-lid down), no count.
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], clearConfirmed: true), .clear(degraded: false), "clear")

    // 5) H1-only scope (ratified record-wide rule 3): open PRs never surface on the MARK —
    // an inbox-clear bar stays the at-ease g even with a live ready/blocked gauge.
    let gauge = pulseRows([pr(1, .passing, .approved, .mergeable), pr(2, .failing, .approved, .mergeable)])
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], pulse: gauge, clearConfirmed: true),
                .clear(degraded: false), "H1-only: a pulse gauge never crosses to the drawn mark")
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["mention"]), pulse: gauge),
                .action(countText: "1", degraded: false), "H1-only: pulse never inflates the count")
}

suite("StatusGlyphPresenter — degraded composes over every state EXCEPT loading (review amendment) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-06T10:00:00Z")!
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-07-06T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    let stale = Freshness.stale(ageSeconds: 400)
    let failing = Freshness.failing(consecutive: 3, ageSeconds: 480)

    // Both degraded kinds compose identically (the dash cares about isDegraded, not why).
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], freshness: stale, clearConfirmed: true),
                .clear(degraded: true), "clear + stale → dashed arcs")
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], freshness: failing, clearConfirmed: true),
                .clear(degraded: true), "clear + failing → dashed arcs")
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["mention"]), freshness: stale),
                .action(countText: "1", degraded: true), "action + degraded")
    // THE amendment: critical+degraded must show BOTH facts — the crisp shield may never
    // hide a reading that could be 20 minutes dead (dashed arcs flank a narrowed shield).
    expectEqual(StatusGlyphPresenter.descriptor(rows: radarRows(["security_alert"]), freshness: stale),
                .critical(countText: "1", degraded: true), "critical + degraded COMPOSES (never omitted)")
    // …and loading is the one exception (no reading yet to distrust).
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], freshness: stale, loading: true),
                .loading, "loading never carries a degraded flag")
    expect(!StatusGlyphDescriptor.loading.isDegraded, "loading.isDegraded is false by construction")

    // Accessors used by the renderer (the drawn ink reads THESE, so they must be exact).
    expectEqual(StatusGlyphDescriptor.critical(countText: "2", degraded: true).markClass, .critical, "markClass: critical")
    expectEqual(StatusGlyphDescriptor.clear(degraded: true).markClass, .clear, "markClass: clear")
    expect(StatusGlyphDescriptor.critical(countText: "2", degraded: true).isDegraded, "isDegraded carried through critical")
    expectEqual(StatusGlyphDescriptor.action(countText: "7", degraded: false).countText, "7", "countText carried through action")
    expectEqual(StatusGlyphDescriptor.clear(degraded: false).countText, nil, "no title when clear")
    expectEqual(StatusGlyphDescriptor.loading.countText, nil, "no title when loading")
    expectEqual(StatusGlyphPresenter.loadingAlpha, 0.55, "loading alpha is the spec's 0.55 — the g's waking register (WP 2026-07-22-001; one shared home)")
}

suite("StatusGlyphPresenter — count text: exact 1–99, '99+' beyond (bar-only cap) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-06T10:00:00Z")!
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-07-06T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    expectEqual(StatusGlyphPresenter.countText(1), "1", "1 exact")
    expectEqual(StatusGlyphPresenter.countText(9), "9", "9 exact")
    expectEqual(StatusGlyphPresenter.countText(42), "42", "42 exact")
    expectEqual(StatusGlyphPresenter.countText(99), "99", "99 exact (the boundary is inclusive)")
    expectEqual(StatusGlyphPresenter.countText(100), "99+", "100 → 99+")
    expectEqual(StatusGlyphPresenter.countText(500), "99+", "500 → 99+")
    // End-to-end through the descriptor: 100 real rows → "99+"; a critical among 100 keeps
    // the shield AND the capped total.
    let hundred = radarRows(Array(repeating: "review_requested", count: 100))
    expectEqual(hundred.count, 100, "sanity: 100 rows built")
    expectEqual(StatusGlyphPresenter.descriptor(rows: hundred),
                .action(countText: "99+", degraded: false), "100 rows → action '99+'")
    let hundredOneCritical = radarRows(["security_alert"] + Array(repeating: "review_requested", count: 99))
    expectEqual(StatusGlyphPresenter.descriptor(rows: hundredOneCritical),
                .critical(countText: "99+", degraded: false), "100 rows w/ critical → shield '99+'")
}

suite("StatusGlyphPresenter — crossfade matrix: 180ms is RESERVED for clear↔action↔critical; everything else is a 0ms hard swap ⚠") {
    typealias D = StatusGlyphDescriptor
    let clear = D.clear(degraded: false)
    let clearDegraded = D.clear(degraded: true)
    let action3 = D.action(countText: "3", degraded: false)
    let action4 = D.action(countText: "4", degraded: false)
    let action3Degraded = D.action(countText: "3", degraded: true)
    let critical3 = D.critical(countText: "3", degraded: false)
    let critical3Degraded = D.critical(countText: "3", degraded: true)

    // The six class-change pairs — the ONLY sanctioned motion (attention-non-theft:
    // motion maps 1:1 to a real action-class change).
    expect(StatusGlyphPresenter.crossfades(from: clear, to: action3), "clear → action crossfades")
    expect(StatusGlyphPresenter.crossfades(from: action3, to: clear), "action → clear crossfades")
    expect(StatusGlyphPresenter.crossfades(from: action3, to: critical3), "action → critical crossfades")
    expect(StatusGlyphPresenter.crossfades(from: critical3, to: action3), "critical → action crossfades")
    expect(StatusGlyphPresenter.crossfades(from: clear, to: critical3), "clear → critical crossfades")
    expect(StatusGlyphPresenter.crossfades(from: critical3, to: clear), "critical → clear crossfades")
    // A simultaneous degraded flip doesn't cancel a real class change.
    expect(StatusGlyphPresenter.crossfades(from: action3, to: critical3Degraded),
           "class change + degraded flip together → still crossfades (class wins)")

    // 0ms hard swaps: count-text changes and degraded-dash toggles (freshness degradation
    // must never be celebrated with motion), and no-ops.
    expect(!StatusGlyphPresenter.crossfades(from: action3, to: action4), "count change within action → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: clear, to: clearDegraded), "degraded toggle on clear → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: action3, to: action3Degraded), "degraded toggle on action → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: critical3, to: critical3Degraded), "degraded toggle on critical → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: critical3Degraded, to: critical3), "degraded recovery on critical → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: clear, to: clear), "no change → no motion")
    expect(!StatusGlyphPresenter.crossfades(from: .loading, to: .loading), "loading steady → no motion")

    // Loading in/out is NOT in the reserved set — first data landing is a hard swap
    // (the 180ms budget is spent only on the three named classes; review overall_note).
    expect(!StatusGlyphPresenter.crossfades(from: .loading, to: clear), "loading → clear → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: .loading, to: action3), "loading → action → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: .loading, to: critical3), "loading → critical → 0ms")
    expect(!StatusGlyphPresenter.crossfades(from: action3, to: .loading), "action → loading → 0ms")
}

suite("StatusGlyphPresenter — tooltip reuses the pill's spoken value verbatim (bar, pill, VoiceOver: one story) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-06T10:00:00Z")!
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-07-06T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    func pr(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: "2026-07-06T08:00:00Z", updatedAt: "2026-07-06T08:00:00Z", ci: ci, review: r, merge: m)
    }
    let gauge = [pr(1, .passing, .approved, .mergeable), pr(2, .passing, .approved, .mergeable),
                 pr(3, .failing, .approved, .mergeable)].map { PulsePresenter.row(for: $0, now: now) }

    expectEqual(StatusGlyphPresenter.toolTip(rows: radarRows(["review_requested", "mention", "assign"])),
                "githud — 3 need you. Click to expand, right-click for menu.", "action tooltip")
    expectEqual(StatusGlyphPresenter.toolTip(rows: radarRows(["security_alert"]), freshness: .stale(ageSeconds: 400)),
                "githud — Reading may be stale — updated 6m ago. 1 needs you, including a security alert. Click to expand, right-click for menu.",
                "degraded + critical tooltip (both facts spoken, D-copy strings)")
    // The H2 gauge is withheld from the drawn mark (H1-only) but NOT from the tooltip —
    // count context honored off-glass, exactly like the pill's spoken value.
    expectEqual(StatusGlyphPresenter.toolTip(rows: [], pulse: gauge),
                "githud — 2 ready, 1 blocked. Click to expand, right-click for menu.",
                "inbox-clear tooltip still speaks the pulse gauge")
    expectEqual(StatusGlyphPresenter.toolTip(rows: [], pulse: [], clearConfirmed: true),
                "githud — You're all caught up. Click to expand, right-click for menu.", "caught-up tooltip")
    // D-copy fix: the loading VALUE now carries the wordmark itself, and toolTip() no
    // longer re-prefixes a wordmark-led value — the old pair spoke the double wordmark
    // "githud — githud, loading" on the status item. ONE wordmark, pinned.
    expectEqual(StatusGlyphPresenter.toolTip(rows: [], loading: true),
                "githud — checking GitHub. Click to expand, right-click for menu.",
                "loading tooltip — the double wordmark is dead")
    expectEqual(StatusGlyphPresenter.toolTip(value: "3 need you"),
                "githud — 3 need you. Click to expand, right-click for menu.",
                "value-taking overload formats identically (controller's accessibility path)")
    // The witnessed composed edge (reachable: 2+ failed polls BEFORE any success →
    // degraded reading while still loading): the degraded prefix leads, so the wordmark
    // appears once mid-sentence. Both facts + identity spoken; pinned as a choice, not a bug.
    expectEqual(StatusGlyphPresenter.toolTip(rows: [], freshness: .failing(consecutive: 2, ageSeconds: 0), loading: true),
                "githud — Reading may be stale. githud — checking GitHub. Click to expand, right-click for menu.",
                "degraded-while-loading tooltip (the composed edge, witnessed)")
}

// MARK: - PillMorph (WP-3x — the slot-morph pill's fingerprint/diff brain)
//
// The ratified G-crossfade pick (`slot-morph-inkfocus`, pill half): one chassis, and the
// written invariant — **no motion where no fact changed**. These suites are the pure,
// headless proof of every transition rule the view executes; the two binding review
// clarifications (rule (a) covers ANY equal-digit tick including gauge segment counts;
// the width settle needs a drift proof) each get an explicit check below.

suite("PillMorph — fingerprint mirrors the pill's own decision tree (loading → needs-you → gauge → check; prefix composes) ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-06-16T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    func pr(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState, draft: Bool = false) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: "2026-06-16T08:00:00Z", updatedAt: "2026-06-16T08:00:00Z", ci: ci, review: r, merge: m)
    }
    func pulseRows(_ prs: [PullRequestPulse]) -> [PulseRow] { prs.map { PulsePresenter.row(for: $0, now: now) } }

    // 1) loading — wins over everything (the pill checks it first; never a fake all-clear).
    let loading = PillMorph.fingerprint(rows: radarRows(["mention"]), pulse: [], loading: true, freshness: .fresh)
    expectEqual(loading.glyph, PillMorph.Glyph.loading, "loading → loading glyph even with rows present")
    expectEqual(loading.value, PillMorph.Value.none, "loading → no value cell")
    expect(!loading.stalePrefix, "fresh → no prefix slot")

    // 2) needs-you — top row's symbol + count; critical flag mirrors rows.contains(isCritical).
    let calm = radarRows(["review_requested", "mention"])
    let calmFP = PillMorph.fingerprint(rows: calm, pulse: [], loading: false, freshness: .fresh)
    expectEqual(calmFP.glyph, PillMorph.Glyph.radar(symbol: calm.first!.symbolName, critical: false), "needs-you glyph = top row's symbol, ink")
    expectEqual(calmFP.value, PillMorph.Value.count("2"), "needs-you value = rows.count")
    let hot = radarRows(["review_requested", "security_alert"])
    let hotFP = PillMorph.fingerprint(rows: hot, pulse: [], loading: false, freshness: .fresh)
    expectEqual(hotFP.glyph, PillMorph.Glyph.radar(symbol: hot.first!.symbolName, critical: true), "a critical row sorts first AND flips the glyph fact to danger")

    // 3) gauge — inbox clear + live PRs; segments carry (state, count-as-drawn).
    let mixed = pulseRows([pr(1, .passing, .approved, .mergeable), pr(2, .failing, .approved, .mergeable)])
    let gaugeFP = PillMorph.fingerprint(rows: [], pulse: mixed, loading: false, freshness: .fresh)
    expectEqual(gaugeFP.glyph, PillMorph.Glyph.none, "gauge state has no standalone glyph cell (glyphs live in the segments)")
    expectEqual(gaugeFP.value, PillMorph.Value.gauge([.init(state: .ready, count: "1"), .init(state: .blocked, count: "1")]),
                "gauge segments = ✓ready then ⚠blocked, count-matched")

    // 4) drafts/stale never enter the glance — the fingerprint uses the SAME sections().active
    // the pill and its spoken value use, so all three surfaces stay in lockstep.
    let draftOnly = pulseRows([pr(9, .failing, .approved, .mergeable, draft: true)])
    let draftFP = PillMorph.fingerprint(rows: [], pulse: draftOnly, loading: false, freshness: .fresh,
                                        clearConfirmed: true)
    expectEqual(draftFP.glyph, PillMorph.Glyph.check, "draft-only PRs → bare check (excluded from the gauge)")
    expectEqual(draftFP.value, PillMorph.Value.none, "…and no value cell")

    // 5) degraded reading — the prefix slot composes with every case (caution = degraded READING).
    let degraded = PillMorph.fingerprint(rows: calm, pulse: [], loading: false, freshness: .stale(ageSeconds: 400))
    expect(degraded.stalePrefix, "degraded freshness → prefix slot present")
    expectEqual(degraded.glyph, calmFP.glyph, "…while the glyph fact is unchanged")
    expectEqual(degraded.value, calmFP.value, "…and the value fact is unchanged")
}

suite("PillMorph — plan: the invariant 'no motion where no fact changed' ⚠") {
    func fp(prefix: Bool = false, glyph: PillMorph.Glyph, value: PillMorph.Value) -> PillMorph.Fingerprint {
        PillMorph.Fingerprint(stalePrefix: prefix, glyph: glyph, value: value)
    }
    let count3 = fp(glyph: .radar(symbol: "at", critical: false), value: .count("3"))

    // Ground case: identical fingerprints → NOTHING repaints, NOTHING fades.
    let noop = PillMorph.plan(from: count3, to: count3)
    expect(noop.isNoop, "identical fingerprint → no-op (no motion where no fact changed)")
    expect(noop.isInstant && noop.fades.isEmpty, "…and trivially instant")

    // First render (nil previous) → a full instant paint, never a fade.
    let first = PillMorph.plan(from: nil, to: count3)
    expect(first.isInstant, "first render → instant (nothing on screen to morph from)")
    expectEqual(first.changed, Set(PillMorph.Cell.allCases), "first render repaints every cell")

    // Rule (a): equal-digit value tick → INSTANT, exactly today.
    let count4 = fp(glyph: .radar(symbol: "at", critical: false), value: .count("4"))
    let tick = PillMorph.plan(from: count3, to: count4)
    expectEqual(tick.changed, [PillMorph.Cell.value], "3→4 changes only the value cell")
    expect(tick.isInstant, "3→4 (equal digits) is INSTANT — zero pixels move (tabular digits)")

    // Rule (b): a digit-COUNT change is a cross-state change → the value cell fades.
    let count9 = fp(glyph: .radar(symbol: "at", critical: false), value: .count("9"))
    let count10 = fp(glyph: .radar(symbol: "at", critical: false), value: .count("10"))
    let growth = PillMorph.plan(from: count9, to: count10)
    expectEqual(growth.fades, [PillMorph.Cell.value], "9→10 (digit-count change) fades the value cell")
    expect(!growth.changed.contains(.glyph), "…and leaves the glyph cell untouched (same reason, ink)")

    // Review clarification (binding): rule (a) covers ANY equal-digit tick INCLUDING gauge
    // segment counts — ✓2·⚠1 → ✓1·⚠1 stays instant.
    let gauge21 = fp(glyph: .none, value: .gauge([.init(state: .ready, count: "2"), .init(state: .blocked, count: "1")]))
    let gauge11 = fp(glyph: .none, value: .gauge([.init(state: .ready, count: "1"), .init(state: .blocked, count: "1")]))
    let gaugeTick = PillMorph.plan(from: gauge21, to: gauge11)
    expectEqual(gaugeTick.changed, [PillMorph.Cell.value], "✓2·⚠1 → ✓1·⚠1 changes only the value cell")
    expect(gaugeTick.isInstant, "…and stays INSTANT (equal-digit gauge segment tick — the review's clarification)")

    // Gauge STRUCTURE changes are cross-state → fade.
    let gaugeReadyOnly = fp(glyph: .none, value: .gauge([.init(state: .ready, count: "1")]))
    expect(PillMorph.plan(from: gaugeReadyOnly, to: gauge11).fades.contains(.value),
           "a segment appearing (✓1 → ✓1·⚠1) fades the value cell")
    let gauge2digits = fp(glyph: .none, value: .gauge([.init(state: .ready, count: "10")]))
    expect(PillMorph.plan(from: gaugeReadyOnly, to: gauge2digits).fades.contains(.value),
           "a segment's digit-count change (✓1 → ✓10) fades the value cell")

    // Cross-state crossings: count↔gauge / count↔check / loading↔count — only changed cells fade.
    let check = fp(glyph: .check, value: .none)
    let toGauge = PillMorph.plan(from: count3, to: gauge11)
    expectEqual(toGauge.fades, [PillMorph.Cell.glyph, PillMorph.Cell.value], "count→gauge crossfades glyph + value cells")
    let toCheck = PillMorph.plan(from: count3, to: check)
    expectEqual(toCheck.fades, [PillMorph.Cell.glyph, PillMorph.Cell.value], "count→check crossfades glyph + value cells")
    let loadingFP = fp(glyph: .loading, value: .none)
    let firstData = PillMorph.plan(from: loadingFP, to: count3)
    expectEqual(firstData.fades, [PillMorph.Cell.glyph, PillMorph.Cell.value], "loading→count crossfades glyph + value cells")

    // Prefix appears/disappears: ONLY the prefix cell fades — the unchanged glyph/value
    // cells are untouched (they slide with the 150ms width settle, they never repaint).
    let stale3 = fp(prefix: true, glyph: .radar(symbol: "at", critical: false), value: .count("3"))
    let prefixIn = PillMorph.plan(from: count3, to: stale3)
    expectEqual(prefixIn.changed, [PillMorph.Cell.prefix], "prefix arrival changes only the prefix cell")
    expectEqual(prefixIn.fades, [PillMorph.Cell.prefix], "…which crossfades")
    let prefixOut = PillMorph.plan(from: stale3, to: count3)
    expectEqual(prefixOut.fades, [PillMorph.Cell.prefix], "prefix clearing fades only the prefix cell")

    // Rule (c): the ink↔danger critical transition is carried by the ordinary GLYPH-cell
    // crossfade — isCritical is part of the glyph fact, so a critical arrival/departure is a
    // glyph change that fades (the ONE animated color transition). No separate flag: a
    // computed-but-unconsumed `criticalFlip` was a false witness (radar→radar-only blind
    // spot) and was deleted; these checks assert the OBSERVABLE truth — the glyph fades.
    let calm2 = fp(glyph: .radar(symbol: "at", critical: false), value: .count("2"))
    let hot3 = fp(glyph: .radar(symbol: "exclamationmark.shield.fill", critical: true), value: .count("3"))
    let flip = PillMorph.plan(from: calm2, to: hot3)
    expect(flip.fades.contains(.glyph), "ink→danger crossfades the glyph cell (rule c — the sanctioned color motion)")
    expect(!flip.fades.contains(.value), "the equal-digit count tick beside it stays instant (no fade)")
    let flipBack = PillMorph.plan(from: hot3, to: calm2)
    expect(flipBack.fades.contains(.glyph), "danger→ink crossfades the glyph cell too (the one transition back)")
    // The old flag's BLIND SPOT, now covered: a security alert arriving from a CLEAR pill
    // (check→radar critical) and departing back — both are glyph-fact changes, so both fade.
    let clear = fp(glyph: .check, value: .none)
    expect(PillMorph.plan(from: clear, to: hot3).fades.contains(.glyph),
           "check→radar(critical) — a security alert from a clear pill — fades the glyph cell (no blind spot)")
    expect(PillMorph.plan(from: hot3, to: clear).fades.contains(.glyph), "radar(critical)→check fades the glyph cell")
    // A symbol change WITHOUT a criticality change is an ordinary glyph crossfade (still ink).
    let mention = fp(glyph: .radar(symbol: "at", critical: false), value: .count("3"))
    let review = fp(glyph: .radar(symbol: "arrow.triangle.pull", critical: false), value: .count("3"))
    let reshuffle = PillMorph.plan(from: mention, to: review)
    expect(reshuffle.fades.contains(.glyph), "top-reason reshuffle fades the glyph (ordinary crossfade — no color moves)")
}

// MARK: - D-pill config (WP 2026-07-10-001) — styles, D1 stale clock, F5 lockstep matrix
//
// The D-pill session ratified a CONFIG (three vocabularies, one default) with an honest
// visual preview, plus the F3 closure (D1 per-fact stale clock). These suites are the pure
// proof: the F5 style×state matrix pins fingerprint + width + spoken TOGETHER (the three
// functions cannot drift); D1 pins the poll/sweep/either-degraded/never-swept rules; and
// the plan suite extends rule (a) to the composed standing tier.

let dpillNow: Date = {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: "2026-06-16T10:00:00Z")!
}()

func dpillRadar(_ reasons: [String]) -> [RadarRow] {
    let items = reasons.enumerated().map { i, reason in
        "{\"id\":\"\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-06-16T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
    }.joined(separator: ",")
    let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
    return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: dpillNow)
}

/// Non-draft pulse rows that roll up to the requested live states (the pill's gauge input).
func dpillPulse(ready: Int = 0, blocked: Int = 0, waiting: Int = 0) -> [PulseRow] {
    func mk(_ n: Int, _ ci: CIState, _ r: ReviewState, _ m: MergeState) -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: "2026-06-16T08:00:00Z", updatedAt: "2026-06-16T08:00:00Z", ci: ci, review: r, merge: m)
    }
    var prs: [PullRequestPulse] = []; var n = 0
    for _ in 0..<ready   { n += 1; prs.append(mk(n, .passing, .approved, .mergeable)) }
    for _ in 0..<blocked { n += 1; prs.append(mk(n, .failing, .approved, .mergeable)) }
    for _ in 0..<waiting { n += 1; prs.append(mk(n, .pending, .approved, .mergeable)) }
    return prs.map { PulsePresenter.row(for: $0, now: dpillNow) }
}

/// Compute all THREE style-threaded functions for one (style × state) in ONE place — the
/// F5 lockstep helper: fingerprint, the pure width, and the spoken value, from identical
/// inputs, so a matrix assertion pins them together.
func dpill(_ style: PillStyle, rows: [RadarRow] = [], pulse: [PulseRow] = [], inbound: Int = 0,
           loading: Bool = false, poll: Freshness = .fresh, sweep: Freshness = .fresh,
           clearConfirmed: Bool = true)   // the F5 matrix pins the CONFIRMED grammar
    -> (fp: PillMorph.Fingerprint, width: CGFloat, spoken: String) {
    let fp = PillMorph.fingerprint(rows: rows, pulse: pulse, loading: loading, freshness: poll,
                                   sweepFreshness: sweep, inboundActive: inbound, style: style,
                                   clearConfirmed: clearConfirmed)
    let spoken = PillAccessibilityPresenter.value(rows: rows, pulse: pulse, freshness: poll,
                                                  sweepFreshness: sweep, loading: loading,
                                                  inboundActive: inbound, style: style,
                                                  clearConfirmed: clearConfirmed)
    return (fp, PillMorph.width(for: fp), spoken)
}

suite("Unconfirmed all-clear — the check is EARNED, never assumed (ratified A2, 2026-07-21) ⚠") {
    // Fail-closed default: a call site that doesn't know the confirmation fact draws the
    // unconfirmed check — the inbound/reviews-confirmation precedent, now on the pill.
    let unconfirmed = PillMorph.fingerprint(rows: [], pulse: [], loading: false, freshness: .fresh)
    expectEqual(unconfirmed.glyph, .checkUnconfirmed, "default (unknown facts) → the unconfirmed check, never the earned one")
    let confirmed = PillMorph.fingerprint(rows: [], pulse: [], loading: false, freshness: .fresh, clearConfirmed: true)
    expectEqual(confirmed.glyph, .check, "all three lanes confirmed → the earned check")
    expectEqual(PillMorph.width(for: unconfirmed), PillMorph.width(for: confirmed),
                "the two checks share one width — the confirm flip never moves the pill")

    // Spoken parity: the earned affirmation is never spoken over an unconfirmed reading.
    expectEqual(PillAccessibilityPresenter.value(rows: [], pulse: []),
                CaughtUpPresenter.unconfirmedClearLine, "spoken unconfirmed-clear line")
    expect(PillAccessibilityPresenter.value(rows: [], pulse: []) != CaughtUpPresenter.caughtUpLine,
           "…and it is NOT the affirmation")

    // The glyph: same gate, same fail-closed default; the confirm flip is a hard swap
    // (same markClass), and degraded composes over the unconfirmed clear too.
    expectEqual(StatusGlyphPresenter.descriptor(rows: []), .clearUnconfirmed(degraded: false),
                "glyph default → unconfirmed clear")
    expectEqual(StatusGlyphDescriptor.clearUnconfirmed(degraded: false).markClass, .clear,
                "confirm flip stays inside the clear class (0ms hard swap, no crossfade)")
    expect(!StatusGlyphPresenter.crossfades(from: .clearUnconfirmed(degraded: false), to: .clear(degraded: false)),
           "…pinned through the crossfade rule")
    expectEqual(StatusGlyphPresenter.descriptor(rows: [], freshness: .stale(ageSeconds: 400)),
                .clearUnconfirmed(degraded: true), "degraded composes over the unconfirmed clear")
    expect(StatusGlyphDescriptor.clearUnconfirmed(degraded: false).countText == nil, "no count on either clear")

    // The gate touches ONLY the clear claim — counts and the gauge are facts.
    let queue = PillMorph.fingerprint(rows: [], pulse: [], loading: false, freshness: .fresh, inboundActive: 2)
    expectEqual(queue.value, .count("2"), "the standing queue count is ungated (facts ride freshness, not confirmation)")
}

suite("D-pill F5 — the style × state matrix pins fingerprint + width + spoken in lockstep ⚠") {
    let gauge11 = dpillPulse(ready: 1, blocked: 1)
    let gSegs: [PillMorph.GaugeSegmentPrint] = [.init(state: .ready, count: "1"), .init(state: .blocked, count: "1")]
    let tray = PillMorph.standingTraySymbol

    // The states identical ACROSS all three styles — the acute region + the two poll-only
    // caught-up states + the shared queue-only tier. A drift in any of the three functions
    // for any style trips here.
    for style in PillStyle.allCases {
        let l = dpill(style, rows: dpillRadar(["mention"]), loading: true)
        expectEqual(l.fp.glyph, .loading, "\(style): loading glyph")
        expectEqual(l.fp.value, .none, "\(style): loading value")
        expect(!l.fp.stalePrefix, "\(style): loading fresh → no prefix")
        expectEqual(l.width, 52, "\(style): loading width")
        expectEqual(l.spoken, "githud — checking GitHub", "\(style): loading spoken")

        let r = dpill(style, rows: dpillRadar(["review_requested", "mention"]))
        expectEqual(r.fp.value, .count("2"), "\(style): radar value = count")
        if case .radar(_, let c) = r.fp.glyph { expect(!c, "\(style): radar non-critical") } else { expect(false, "\(style): radar glyph") }
        expectEqual(r.width, 60, "\(style): radar width")
        expectEqual(r.spoken, "2 need you", "\(style): radar spoken")

        let hot = dpill(style, rows: dpillRadar(["review_requested", "security_alert"]))
        if case .radar(_, let c) = hot.fp.glyph { expect(c, "\(style): critical flips the glyph fact") } else { expect(false, "\(style): critical glyph") }
        expectEqual(hot.spoken, "2 need you, including a security alert", "\(style): critical spoken names the emergency")

        let gg = dpill(style, pulse: gauge11)
        expectEqual(gg.fp.glyph, .none, "\(style): gauge-only glyph")
        expectEqual(gg.fp.value, .gauge(gSegs), "\(style): gauge-only value")
        expectEqual(gg.width, 88, "\(style): gauge-only width")
        expectEqual(gg.spoken, "1 ready, 1 blocked", "\(style): gauge-only spoken")

        let qo = dpill(style, inbound: 5)
        expectEqual(qo.fp.glyph, .radar(symbol: tray, critical: false), "\(style): queue-only draws the still tray (tray.fill)")
        expectEqual(qo.fp.value, .count("5"), "\(style): queue-only value = count")
        expectEqual(qo.width, 60, "\(style): queue-only width")
        expectEqual(qo.spoken, "5 waiting at your door", "\(style): queue-only spoken")

        // fix round M-1: the +19 stale pad crossed with a DEGRADED clock — the one width
        // class the matrix never pinned (a sweep-stale queue widens for the caution slot).
        let qoStale = dpill(style, inbound: 3, sweep: .stale(ageSeconds: 400))
        expect(qoStale.fp.stalePrefix, "\(style): queue-only sweep-stale → prefix slot present")
        expectEqual(qoStale.width, 79, "\(style): queue-only sweep-stale width = 60 + the 19pt stale pad")

        let clear = dpill(style)
        expectEqual(clear.fp.glyph, .check, "\(style): all-clear glyph")
        expectEqual(clear.fp.value, .none, "\(style): all-clear value")
        expectEqual(clear.width, 52, "\(style): all-clear width")
        expectEqual(clear.spoken, "You're all caught up", "\(style): all-clear spoken")
    }

    // gauge + queue — the ONE state where the styles DIVERGE (their reason to exist).
    // queueLeads: the standing queue is EXCLUSIVE (D2 reorder — it walls off the gauge).
    let ql = dpill(.queueLeads, pulse: gauge11, inbound: 5)
    expectEqual(ql.fp.glyph, .radar(symbol: tray, critical: false), "queueLeads gauge+queue → inbound tray (gauge walled off)")
    expectEqual(ql.fp.value, .count("5"), "queueLeads gauge+queue → queue count only")
    expectEqual(ql.width, 60, "queueLeads gauge+queue width = the count pill (gauge not drawn)")
    expectEqual(ql.spoken, "5 waiting at your door", "queueLeads gauge+queue spoken — the queue only")

    // standingMarked: composed gauge + a count-free mark; strict count-free spoken parity.
    let sm = dpill(.standingMarked, pulse: gauge11, inbound: 5)
    expectEqual(sm.fp.glyph, .none, "standingMarked composed → no standalone glyph")
    expectEqual(sm.fp.value, .standing(gauge: gSegs, queue: .mark), "standingMarked → gauge + count-free mark")
    expectEqual(sm.width, 108, "standingMarked width = gauge (88) + mark (+20)")
    expectEqual(sm.spoken, "1 ready, 1 blocked; people waiting at your door", "standingMarked spoken — count-free parity (no number)")

    // standingCounted: composed gauge + a glyph+count queue segment on the gauge's atoms.
    let sc = dpill(.standingCounted, pulse: gauge11, inbound: 5)
    expectEqual(sc.fp.value, .standing(gauge: gSegs, queue: .count("5")), "standingCounted → gauge + queue count segment")
    expectEqual(sc.width, 123, "standingCounted width = gauge 88 + gap 6 + segment 29 = 123 (the ✓_⚠_+_ chronic)")
    expectEqual(sc.spoken, "1 ready, 1 blocked. 5 waiting at your door", "standingCounted spoken — gauge clause + counted door")
}

suite("D-pill D1 — the per-fact stale clock (poll vs sweep, either-degraded, never-swept) ⚠") {
    let stale = Freshness.stale(ageSeconds: 400)   // 6m — past the 180s threshold
    let gauge11 = dpillPulse(ready: 1, blocked: 1)

    // Poll-clock facts read the POLL clock; the sweep clock is NOT consulted (no inbound fact).
    expect(dpill(.standingCounted, pulse: gauge11, poll: stale).fp.stalePrefix,
           "gauge-only + poll stale → prefix (poll clock)")
    expect(!dpill(.standingCounted, pulse: gauge11, sweep: stale).fp.stalePrefix,
           "gauge-only + SWEEP stale but no queue → NO prefix (sweep clock not consulted)")

    // Sweep-clock facts read the SWEEP clock; the poll clock is NOT consulted.
    let queueSweepStale = dpill(.queueLeads, inbound: 3, sweep: stale)
    expect(queueSweepStale.fp.stalePrefix, "queue-only + sweep stale → prefix (sweep clock)")
    expectEqual(queueSweepStale.spoken, "Reading may be stale — updated 6m ago. 3 waiting at your door",
                "…and the spoken prefix names the SWEEP age (6m)")
    expect(!dpill(.queueLeads, inbound: 3, poll: stale).fp.stalePrefix,
           "queue-only + POLL stale but fresh sweep → NO prefix (poll clock not consulted for a sweep fact)")

    // Composed standing state — degrades if EITHER member's clock is degraded (stalest wins).
    expect(dpill(.standingCounted, pulse: gauge11, inbound: 3, poll: stale).fp.stalePrefix,
           "composed + poll stale → prefix (the gauge member is stale)")
    expect(dpill(.standingCounted, pulse: gauge11, inbound: 3, sweep: stale).fp.stalePrefix,
           "composed + sweep stale → prefix (the queue member is stale)")
    expect(!dpill(.standingCounted, pulse: gauge11, inbound: 3).fp.stalePrefix,
           "composed + both fresh → no prefix")
    // standingMarked composes the same way — the mark is a sweep-clock claim, count-free or not.
    expect(dpill(.standingMarked, pulse: gauge11, inbound: 3, sweep: stale).fp.stalePrefix,
           "standingMarked composed + sweep stale → prefix (the mark is a sweep claim)")

    // Never-swept (nil sweep date) with a NON-ZERO count → degraded (the F3 case). The
    // nil→stale rule lives in FreshnessModel.sweepStatus, so a painted count whose clock
    // never ticked reads stale under otherwise-fresh chrome.
    let neverSwept = FreshnessModel.sweepStatus(lastSweepSuccess: nil, now: dpillNow)
    expect(neverSwept.isDegraded, "never-swept sweep clock is DEGRADED (nil date → stale, not fresh)")
    let queueNeverSwept = dpill(.queueLeads, inbound: 3, sweep: neverSwept)
    expect(queueNeverSwept.fp.stalePrefix, "never-swept + painted count → prefix (adopted-stale under fresh chrome)")
    expectEqual(queueNeverSwept.spoken, "Reading may be stale. 3 waiting at your door",
                "never-swept (age 0) spoken → age-free prefix, never a fabricated timestamp")

    // Never-swept with count 0 → MOOT: no count-bearing state renders, so the sweep clock is
    // never consulted (the all-clear reads the poll clock → fresh → no prefix).
    expect(!dpill(.queueLeads, inbound: 0, sweep: neverSwept).fp.stalePrefix,
           "never-swept + count 0 → moot (no sweep fact shown → no prefix)")

    // The sweep clock's happy path + threshold (same 180s as the poll clock).
    expect(!FreshnessModel.sweepStatus(lastSweepSuccess: dpillNow.addingTimeInterval(-30), now: dpillNow).isDegraded,
           "sweep 30s ago → fresh")
    expect(FreshnessModel.sweepStatus(lastSweepSuccess: dpillNow.addingTimeInterval(-400), now: dpillNow).isDegraded,
           "sweep 400s ago (> 180s) → stale")
}

suite("D-pill — plan: the standing tier ticks/fades by the extended rule (a) ⚠") {
    func fp(_ value: PillMorph.Value) -> PillMorph.Fingerprint {
        PillMorph.Fingerprint(stalePrefix: false, glyph: .none, value: value)
    }
    let segs2: [PillMorph.GaugeSegmentPrint] = [.init(state: .ready, count: "2"), .init(state: .blocked, count: "1")]
    let segs1: [PillMorph.GaugeSegmentPrint] = [.init(state: .ready, count: "1"), .init(state: .blocked, count: "1")]

    // Instant tick: same gauge structure + same queue-print case + equal digit counts.
    let a = fp(.standing(gauge: segs2, queue: .count("3")))
    let b = fp(.standing(gauge: segs1, queue: .count("4")))
    let tick = PillMorph.plan(from: a, to: b)
    expectEqual(tick.changed, [PillMorph.Cell.value], "standing equal-digit tick → only the value cell changes")
    expect(tick.isInstant, "…and stays INSTANT (gauge ✓2→✓1 + queue 3→4, all single digit)")

    // A digit-COUNT change on the queue → structure change → fade.
    let b2 = fp(.standing(gauge: segs2, queue: .count("10")))
    expect(PillMorph.plan(from: a, to: b2).fades.contains(.value), "queue 3→10 (digit-count change) fades the value cell")

    // A gauge segment appearing under a standing tier → fade.
    let readyOnlyQ = fp(.standing(gauge: [.init(state: .ready, count: "1")], queue: .count("3")))
    expect(PillMorph.plan(from: readyOnlyQ, to: a).fades.contains(.value), "a gauge segment appearing under a standing tier fades the value cell")

    // mark ↔ count is a STRUCTURE change → fade (never an equal-digit tick).
    let mark = fp(.standing(gauge: segs2, queue: .mark))
    expect(PillMorph.plan(from: mark, to: a).fades.contains(.value), "mark→count fades the value cell (structure change)")
    expect(PillMorph.plan(from: a, to: mark).fades.contains(.value), "count→mark fades the value cell too")
    // mark ↔ mark with the same gauge structure → instant (the mark carries no digits).
    let mark1 = fp(.standing(gauge: segs1, queue: .mark))
    let markTick = PillMorph.plan(from: mark, to: mark1)
    expectEqual(markTick.changed, [PillMorph.Cell.value], "mark→mark gauge tick changes only the value cell")
    expect(markTick.isInstant, "…and stays instant (the mark has no number; only the gauge ticked)")

    // Cross-shape crossings fade the whole value cell (today's gauge grammar, extended).
    expect(PillMorph.plan(from: fp(.gauge(segs2)), to: a).fades.contains(.value),
           "gauge→standing (a queue arrives beside the gauge) fades the value cell")
    let queueOnly = PillMorph.Fingerprint(stalePrefix: false,
                                          glyph: .radar(symbol: PillMorph.standingTraySymbol, critical: false),
                                          value: .count("3"))
    expect(PillMorph.plan(from: queueOnly, to: a).fades.contains(.value),
           "queue-only → composed standing fades the value cell")
}

suite("D-pill — QueuePrint equality + PillStyle raw decode/default + chooser content") {
    // QueuePrint equality (same case + payload equal; different case/payload not).
    expectEqual(PillMorph.QueuePrint.mark, .mark, "mark == mark")
    expectEqual(PillMorph.QueuePrint.count("3"), .count("3"), "count(3) == count(3)")
    expect(PillMorph.QueuePrint.mark != .count("3"), "mark != count(3)")
    expect(PillMorph.QueuePrint.count("3") != .count("4"), "count(3) != count(4)")
    // …and it rides into Value equality (auto-synthesized over the standing case).
    let segs: [PillMorph.GaugeSegmentPrint] = [.init(state: .ready, count: "1")]
    expectEqual(PillMorph.Value.standing(gauge: segs, queue: .mark), .standing(gauge: segs, queue: .mark), "standing==standing")
    expect(PillMorph.Value.standing(gauge: segs, queue: .mark) != .standing(gauge: segs, queue: .count("1")),
           "standing(mark) != standing(count) (a structure difference)")

    // PillStyle raw decode/default (the store's decode; the store itself is App-side).
    expectEqual(PillStyle.queueLeads.rawValue, "queueLeads", "default style's raw value")
    expectEqual(PillStyle(rawValue: "standingMarked"), .standingMarked, "decode standingMarked")
    expectEqual(PillStyle(rawValue: "standingCounted"), .standingCounted, "decode standingCounted")
    expectEqual(PillStyle(rawValue: "bogus"), nil, "unknown raw → nil (the store falls back to the default)")
    expectEqual(PillStyle.allCases.count, 3, "three styles")
    expectEqual(PillStyle.allCases.first, .queueLeads, "the default (first case) is queueLeads")

    // The chooser card content: copy + the option→style mapping, and — the focus-non-theft
    // proof the WP owes — a chooser can NEVER take a key moment (no field).
    let c = PillStyleChooser.standard
    expectEqual(c.title, "Pill style", "chooser title")
    expectEqual(c.options.count, 3, "one option per style")
    expectEqual(c.options.map { $0.style }, [.queueLeads, .standingMarked, .standingCounted], "option→style mapping, default first")
    expectEqual(c.options.map { $0.label }, ["Door first", "Side by side — quiet mark", "Side by side — with the count"], "D-copy option labels")
    expect(c.caption.contains("live data"), "the caption names that previews use real data")
    expect(!c.coincideNote.isEmpty, "the empty-door coincide note exists (never fabricate a queue)")
    expect(c.coincideNote.contains("empty"), "the CONFIRMED note may claim emptiness (a complete sweep read the door)")
    // fix round M-3: pre-first-sweep, count 0 is UNCONFIRMED — the fallback line claims only
    // the coincidence, never the emptiness (the island's inboundConfirmed gate, on this card).
    expect(!c.unconfirmedNote.isEmpty, "the unconfirmed empty-door fallback exists")
    expect(!c.unconfirmedNote.contains("empty"), "…and it never claims 'empty' before a sweep has confirmed it")
    expect(c.unconfirmedNote.contains("look the same"), "…while still explaining why the previews coincide")
    expect(!c.takesKeyMoment, "the chooser card takes NO key moment (canBecomeKey stays false — headless focus-non-theft proof)")
}

suite("PillMorph — drift proof, pure half: the 150ms width settle re-centers with ZERO midX drift ⚠") {
    // The review's binding build clarification: the per-frame recenter during the width
    // ease needs a drift proof. Pure half: (1) every pill width centers on the screen's
    // midX by construction; (2) two frames sharing a midX keep that midX under LINEAR
    // interpolation of origin+size at EVERY t — which is exactly what one animation group
    // animating the whole frame rect on one curve does. The runtime half is asserted in
    // HUDPanelController.animateSlotMorph's completion (midX before == after).
    for screen in [CGRect(x: 0, y: 0, width: 1728, height: 1080),
                   CGRect(x: 1728, y: 0, width: 1512, height: 982)] {   // offset second monitor too
        for width in [52.0, 60.0, 70.0, 79.0, 88.0, 107.0] {            // every pill width class (± the 19px prefix)
            let f = IslandGeometry.frame(size: CGSize(width: width, height: 36), in: screen)
            expectClose(f.midX, screen.midX, 0.01, "pill width \(Int(width)) centers on midX (screen at x=\(Int(screen.minX)))")
        }
    }
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    let from = IslandGeometry.frame(size: CGSize(width: 60, height: 36), in: screen)
    let to = IslandGeometry.frame(size: CGSize(width: 88, height: 36), in: screen)
    for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
        let x = from.origin.x + (to.origin.x - from.origin.x) * t
        let w = from.width + (to.width - from.width) * t
        expectClose(x + w / 2, screen.midX, 0.01, "interpolated frame keeps midX at t=\(t) (no drift at any step)")
    }
    // The container morph shares the lemma on BOTH axes: top edge pinned + center fixed.
    let pill = IslandGeometry.frame(size: CGSize(width: 60, height: 36), in: screen)
    let island = IslandGeometry.frame(size: CGSize(width: 520, height: 346), in: screen)
    for t in [0.0, 0.5, 1.0] {
        let y = pill.origin.y + (island.origin.y - pill.origin.y) * t
        let h = pill.height + (island.height - pill.height) * t
        expectClose(y + h, screen.maxY - IslandGeometry.menuBarGap, 0.01, "morph interpolation keeps the top edge pinned at t=\(t)")
        let x = pill.origin.x + (island.origin.x - pill.origin.x) * t
        let w = pill.width + (island.width - pill.width) * t
        expectClose(x + w / 2, screen.midX, 0.01, "morph interpolation keeps the center fixed at t=\(t)")
    }
}

// MARK: - TokenLedger (WP-4d — the handshake-ledger card's pure state machine)

// Row indices, for readability: 0 = Token, 1 = Keychain, 2 = GitHub.
func slotWord(_ s: TokenLedger.SlotState) -> String {
    switch s {
    case .pending: return "pending"
    case .done: return "done"
    case .failed: return "failed"
    }
}

suite("TokenLedger — welcome card: three pending receipts, nothing claimed") {
    let card = TokenLedger.card(for: TokenLedger.welcome())
    expectEqual(card.title, "Connect GitHub", "title")
    expectEqual(card.promise, "githud reads your GitHub notifications — it never writes.", "the one-line read-only promise")
    expectEqual(card.rows.count, 3, "exactly three ledger rows")
    expectEqual(card.rows.map(\.label), ["Token", "Keychain", "GitHub"], "row labels, in event order")
    expect(card.rows.allSatisfy { $0.slot == .pending }, "every slot pending — no receipt exists yet")
    expect(card.rows.allSatisfy { $0.remedy == nil }, "no remedy — nothing failed")
    expectEqual(card.rows[0].detail, "paste a classic token below", "row 1 pending detail invites the paste")
    expectEqual(card.rows[0].detailStyle, TokenLedger.DetailStyle.placeholder, "…in placeholder ink")
    expectEqual(card.rows[1].detail, "—", "row 2 claims nothing")
    expectEqual(card.rows[2].detail, "—", "row 3 claims nothing")
    expect(!card.isComplete, "not complete — the morph gate stays shut")
    expectEqual(card.settingsURL, "https://github.com/settings/tokens", "the one external URL (the action ceiling)")
    expectEqual(card.fieldPlaceholder, "ghp_…", "secure-field placeholder")
    expectEqual(card.footerCaption, "read-only · stays in your Keychain, nowhere else", "footer caption claims only what the code does")
    expectEqual(card.createLinkTitle, "Create token ↗", "create link visible in every state (never hover-gated)")
}

suite("TokenLedger — wrongShape fails row 1; rows 2–3 stay pending (progress never fabricated)") {
    let s = TokenLedger.reduce(TokenLedger.welcome(), .shapeRejected)
    let card = TokenLedger.card(for: s)
    expectEqual(card.rows[0].slot, TokenLedger.SlotState.failed(symbol: "exclamationmark.triangle.fill"),
                "row 1 fails with the triangle (per-reason SHAPE — gray-swap safe)")
    expectEqual(card.rows[1].slot, TokenLedger.SlotState.pending, "row 2 stays pending — no write happened")
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.pending, "row 3 stays pending — GitHub was never asked")
    expect(card.rows[0].remedy?.contains("classic token") == true, "remedy names the fix (plainspoken)")
    expect(card.rows[0].remedy?.contains("ghp_") == true, "remedy names the expected shape")
    expect(card.rows[1].remedy == nil && card.rows[2].remedy == nil, "the remedy lands ONLY under the failing row")
    expect(!card.isComplete, "not complete")
}

suite("TokenLedger — stored checks rows 1+2 with the REAL redacted receipt") {
    let s = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let card = TokenLedger.card(for: s)
    expectEqual(card.rows[0].slot, TokenLedger.SlotState.done, "row 1 done — the shape gate really passed")
    expectEqual(card.rows[0].detail, "ghp_•(40)", "row 1's done-detail is KeychainPAT.redacted — the only form of the secret that renders")
    expectEqual(card.rows[0].detailStyle, TokenLedger.DetailStyle.mono, "…in mono")
    expectEqual(card.rows[1].slot, TokenLedger.SlotState.done, "row 2 done — the Keychain write really returned success")
    expectEqual(card.rows[1].detail, "stored", "row 2 detail states exactly the store fact")
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.pending, "row 3 still pending — GitHub hasn't answered")
    expect(!card.isComplete, "store success is NOT completion — the morph gate needs GitHub's answer")
}

suite("TokenLedger — Keychain write failure fails row 2 (row 1 keeps its true receipt)") {
    let s = TokenLedger.reduce(TokenLedger.welcome(), .keychainWriteFailed(redacted: "ghp_•(40)"))
    let card = TokenLedger.card(for: s)
    expectEqual(card.rows[0].slot, TokenLedger.SlotState.done, "row 1 done — the shape gate did pass (a true fact)")
    expectEqual(card.rows[0].detail, "ghp_•(40)", "…with its real receipt")
    expectEqual(card.rows[1].slot, TokenLedger.SlotState.failed(symbol: "exclamationmark.triangle.fill"), "row 2 failed")
    expect(card.rows[1].remedy?.contains("nothing was stored") == true, "remedy claims exactly the outcome — nothing was stored")
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.pending, "row 3 pending — no session can start off a failed store")
}

suite("TokenLedger — sessionStarted → static 'verifying…' (and only after a real store)") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))
    let card = TokenLedger.card(for: verifying)
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.pending, "row 3's slot stays the pending circle — verifying is not progress")
    expectEqual(card.rows[2].detail, "verifying…", "row 3 detail is the static text (no spinner exists to render)")
    expectEqual(card.rows[2].detailStyle, TokenLedger.DetailStyle.plain, "…in plain ink (the reading isn't degraded)")
    expectEqual(verifying.sessionGeneration, 1, "the handshake binds to the session that started it")
    // Stray events fabricate nothing:
    expectEqual(TokenLedger.reduce(TokenLedger.welcome(), .sessionStarted(generation: 1)), TokenLedger.welcome(),
                "sessionStarted without a store is ignored (a session can only follow a real store)")
    expectEqual(TokenLedger.reduce(TokenLedger.welcome(), .pollSucceeded(generation: 0)), TokenLedger.welcome(),
                "a poll success with no handshake in flight checks nothing")
    expectEqual(TokenLedger.reduce(TokenLedger.welcome(), .pollFailed(generation: 0)), TokenLedger.welcome(),
                "a poll failure with no handshake in flight marks nothing")
}

suite("TokenLedger — first-poll outcomes: 'connected' only on GitHub's real answer") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))

    let connected = TokenLedger.reduce(verifying, .pollSucceeded(generation: 1))
    let done = TokenLedger.card(for: connected)
    expectEqual(done.rows[2].slot, TokenLedger.SlotState.done, "the first successful poll checks row 3")
    expectEqual(done.rows[2].detail, "connected", "…and says exactly that")
    expect(done.isComplete, "all three receipts → complete (the caller holds 700ms, then the morph IS the celebration)")
    expect(TokenLedger.isComplete(connected), "isComplete agrees with the card")

    // The bounded NETWORK-failure exit (binding review note): never unbounded 'verifying…'.
    let retrying = TokenLedger.reduce(verifying, .pollFailed(generation: 1))
    let caution = TokenLedger.card(for: retrying)
    expectEqual(caution.rows[2].slot, TokenLedger.SlotState.pending, "a transient failure is not a failed receipt — the slot stays pending")
    expectEqual(caution.rows[2].detail, "no answer yet — retrying", "the caution line claims only the real facts: no answer, and the loop retries")
    expectEqual(caution.rows[2].detailStyle, TokenLedger.DetailStyle.caution, "…in caution ink (the sanctioned degraded-reading treatment)")
    expect(!caution.isComplete, "not complete")
    expectEqual(TokenLedger.reduce(retrying, .pollFailed(generation: 1)), retrying,
                "repeat failures are the SAME state — the model's equality guard emits no render, no motion")
    expectEqual(TokenLedger.reduce(retrying, .pollSucceeded(generation: 1)).github, TokenLedger.GitHubPhase.connected,
                "a later success still connects (the outcome stream stays live)")
    expectEqual(TokenLedger.reduce(connected, .pollFailed(generation: 1)), connected,
                "a transient blip after connection never un-claims it (freshness is the banner's job)")
}

suite("TokenLedger — rate-limit is an ANSWER, never silence (fix round, honest copy)") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))
    let limited = TokenLedger.reduce(verifying, .pollRateLimited(pauseSeconds: 60, generation: 1))
    let card = TokenLedger.card(for: limited)
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.pending, "a rate-limit is not a failed receipt — the slot stays pending")
    expectEqual(card.rows[2].detail, "rate limited — retrying in ~1m", "the copy names BOTH facts: GitHub's verdict and the real pause")
    expectEqual(card.rows[2].detailStyle, TokenLedger.DetailStyle.caution, "…in caution ink (still the degraded-reading treatment)")
    expect(!card.rows[2].detail.contains("no answer"), "an answered request never reads as silence")
    // The minutes come from the reducer's own pause (one formula, one home):
    let long = TokenLedger.reduce(verifying, .pollRateLimited(pauseSeconds: 300, generation: 1))
    expectEqual(TokenLedger.card(for: long).rows[2].detail, "rate limited — retrying in ~5m", "pause 300s → ~5m")
    let odd = TokenLedger.reduce(verifying, .pollRateLimited(pauseSeconds: 61, generation: 1))
    expectEqual(TokenLedger.card(for: odd).rows[2].detail, "rate limited — retrying in ~2m", "pause rounds UP (never promises sooner than reality)")
    // A rate-limited handshake still resolves on the session's later real outcomes:
    expectEqual(TokenLedger.reduce(limited, .pollSucceeded(generation: 1)).github, TokenLedger.GitHubPhase.connected,
                "success after the pause connects")
    expectEqual(TokenLedger.reduce(limited, .pollFailed(generation: 1)).github, TokenLedger.GitHubPhase.retrying,
                "a genuine no-answer after the pause moves to the retrying line")
}

suite("TokenLedger — generation stamps: a stale session's answer never touches the handshake (fix round)") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 2))
    expectEqual(TokenLedger.reduce(verifying, .pollSucceeded(generation: 1)), verifying,
                "an OLD session's success cannot check a handshake it doesn't own")
    expectEqual(TokenLedger.reduce(verifying, .pollFailed(generation: 1)), verifying,
                "…nor caution it")
    expectEqual(TokenLedger.reduce(verifying, .pollRateLimited(pauseSeconds: 60, generation: 1)), verifying,
                "…nor rate-limit it")
    expectEqual(TokenLedger.reduce(verifying, .pollSucceeded(generation: 2)).github, TokenLedger.GitHubPhase.connected,
                "the owning session's success connects normally")
    // event(for:generation:) is the one mapping the shell forwards through:
    expectEqual(TokenLedger.event(for: .success, generation: 3), TokenLedger.Event.pollSucceeded(generation: 3),
                "seam mapping: success")
    expectEqual(TokenLedger.event(for: .transientFailure, generation: 3), TokenLedger.Event.pollFailed(generation: 3),
                "seam mapping: transient failure")
    expectEqual(TokenLedger.event(for: .rateLimited(pauseSeconds: 120), generation: 3),
                TokenLedger.Event.pollRateLimited(pauseSeconds: 120, generation: 3),
                "seam mapping: rate limit carries the pause")
}

suite("TokenLedger — a rejected paste never wipes a live handshake's receipts (fix round, finding 10)") {
    // Valid token verifying → user re-pastes a truncated token → row 1 fails, but rows
    // 2–3 keep describing the ACTIVE token — and the running session's outcomes still land.
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))
    let mootPaste = TokenLedger.reduce(verifying, .shapeRejected)
    expectEqual(mootPaste.token, TokenLedger.TokenPhase.failedShape, "the paste failure lands on row 1")
    expectEqual(mootPaste.keychain, TokenLedger.KeychainPhase.done, "row 2 keeps the active token's true store receipt")
    expectEqual(mootPaste.github, TokenLedger.GitHubPhase.verifying, "row 3 keeps the live verification")
    let resolved = TokenLedger.reduce(mootPaste, .pollSucceeded(generation: 1))
    expectEqual(resolved.github, TokenLedger.GitHubPhase.connected,
                "the active session's success still checks row 3 (no stranded card over a healthy session)")
    expect(!TokenLedger.isComplete(resolved), "…but a failed row 1 blocks completion — the error stays must-see until the user fixes the paste")
    // And a subsequent VALID paste restarts everything cleanly:
    let repaste = TokenLedger.reduce(resolved, .stored(redacted: "ghp_•(40)"))
    expectEqual(repaste.github, TokenLedger.GitHubPhase.pending, "a real store restarts the handshake")
}

suite("TokenLedger — auth failures land on the failing row with per-reason glyph shapes") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))

    let rejected = TokenLedger.card(for: TokenLedger.reduce(verifying, .authFailed(.invalidToken)))
    expectEqual(rejected.rows[2].slot, TokenLedger.SlotState.failed(symbol: "key.slash"), "401 → key-slash on row 3")
    expectEqual(rejected.rows[2].detail, "rejected (401)", "detail keeps the status code (debuggability)")
    expect(rejected.rows[2].remedy?.contains("invalid or expired") == true,
           "401 copy keeps 'invalid or expired' — a never-valid token also 401s (the binding record-wide rule)")
    expect(rejected.rows[0].slot == .done && rejected.rows[1].slot == .done,
           "rows 1–2 stay checked — true facts (the token exists; GitHub's rejection is row 3's news)")

    let refused = TokenLedger.card(for: TokenLedger.reduce(verifying, .authFailed(.ssoOrScope)))
    expectEqual(refused.rows[2].slot, TokenLedger.SlotState.failed(symbol: "lock.shield.fill"), "SSO-403 → lock-shield on row 3")
    expectEqual(refused.rows[2].detail, "refused (403)", "detail keeps the status code")
    expect(refused.rows[2].remedy?.contains("SSO") == true, "remedy names the SSO path")
    expect(refused.rows[2].remedy?.contains("notifications scope") == true, "…and the scope alternative")

    expectEqual(TokenLedger.reduce(verifying, .authFailed(.wrongShape)).token, TokenLedger.TokenPhase.failedShape,
                "a wrongShape auth event routes to row 1 defensively (same landing as the intake WALL)")
    // GitHub's newest answer outranks a stale celebration (the completion hold re-checks):
    let connected = TokenLedger.reduce(verifying, .pollSucceeded(generation: 1))
    expectEqual(TokenLedger.reduce(connected, .authFailed(.invalidToken)).github,
                TokenLedger.GitHubPhase.failed(.invalidToken),
                "a 401 landing after 'connected' fails row 3 — the card never defends a claim GitHub just withdrew")
}

suite("TokenLedger — reset returns every row to pending (a reset is not progress)") {
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let failed = TokenLedger.reduce(TokenLedger.reduce(stored, .sessionStarted(generation: 1)), .authFailed(.invalidToken))
    expectEqual(TokenLedger.reduce(failed, .reset), TokenLedger.welcome(), "reset from a failed handshake → all pending")
    expectEqual(TokenLedger.reduce(TokenLedger.reduce(TokenLedger.welcome(), .shapeRejected), .reset),
                TokenLedger.welcome(), "reset from a shape failure → all pending")
    let card = TokenLedger.card(for: TokenLedger.reduce(failed, .reset))
    expect(card.rows.allSatisfy { $0.remedy == nil }, "no remedy survives a reset")
}

suite("TokenLedger — runtime re-present: rows 1–2 pre-checked (true facts), row 3 failed") {
    let s = TokenLedger.runtimeFailure(reason: .invalidToken, redacted: "ghp_•(40)")
    let card = TokenLedger.card(for: s)
    expectEqual(card.rows[0].slot, TokenLedger.SlotState.done, "row 1 pre-checked — a stored token exists (that's why there was a 401)")
    expectEqual(card.rows[0].detail, "ghp_•(40)", "…showing the real stashed redacted form")
    expectEqual(card.rows[1].slot, TokenLedger.SlotState.done, "row 2 pre-checked — it IS in the Keychain")
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.failed(symbol: "key.slash"), "row 3 carries the failure")
    expect(card.rows[2].remedy != nil, "…with its remedy")

    let noRedacted = TokenLedger.card(for: TokenLedger.runtimeFailure(reason: .ssoOrScope, redacted: nil))
    expectEqual(noRedacted.rows[0].detail, "ghp_…", "missing redacted stash falls back to the SHAPE every live token provably passed — never a fabricated store word")
    expectEqual(noRedacted.rows[2].slot, TokenLedger.SlotState.failed(symbol: "lock.shield.fill"), "403 shape on row 3")

    let wrongShape = TokenLedger.card(for: TokenLedger.runtimeFailure(reason: .wrongShape, redacted: nil))
    expectEqual(wrongShape.rows[0].slot, TokenLedger.SlotState.failed(symbol: "exclamationmark.triangle.fill"),
                "launch-caught wrong shape fails row 1")
    expect(wrongShape.rows[1].slot == .pending && wrongShape.rows[2].slot == .pending,
           "…rows 2–3 pending (nothing stored, nothing asked — progress never fabricated)")

    // A re-submit on the runtime card walks the SAME machine as first-run (one species):
    let resubmitted = TokenLedger.reduce(TokenLedger.reduce(s, .reset), .stored(redacted: "ghp_•(40)"))
    expectEqual(resubmitted.github, TokenLedger.GitHubPhase.pending, "re-submit restarts the handshake honestly")
}

suite("TokenLedger — provenance: an env-sourced token never fabricates a store receipt (fix round)") {
    let s = TokenLedger.runtimeFailure(reason: .invalidToken, redacted: "ghp_•(40)", storedInKeychain: false)
    let card = TokenLedger.card(for: s)
    expectEqual(card.rows[0].slot, TokenLedger.SlotState.done, "row 1 done — a classic-shaped token was in use (true)")
    expectEqual(card.rows[1].slot, TokenLedger.SlotState.pending, "row 2's slot stays the pending circle — no store ever happened")
    expectEqual(card.rows[1].detail, "from environment", "…and the detail states the true provenance")
    expectEqual(card.rows[1].detailStyle, TokenLedger.DetailStyle.plain, "…as a plain fact, not a caution")
    expect(card.rows[1].remedy == nil, "provenance is a fact, not a failure — no remedy")
    expectEqual(card.rows[2].slot, TokenLedger.SlotState.failed(symbol: "key.slash"), "row 3 still carries the 401")
    // The default stays Keychain-true for the store path:
    expectEqual(TokenLedger.runtimeFailure(reason: .invalidToken, redacted: "ghp_•(40)").keychain,
                TokenLedger.KeychainPhase.done, "storedInKeychain defaults true (the submitToken path really stores)")
    // A real re-paste through the machine replaces provenance with a real store receipt:
    let repaste = TokenLedger.reduce(s, .stored(redacted: "ghp_•(41)"))
    expectEqual(repaste.keychain, TokenLedger.KeychainPhase.done, "a real store earns the real receipt")
}

suite("PollAttemptOutcome — the seam's vocabulary maps from the reducer's own taxonomy (fix round)") {
    typealias R = Result<PollReducer.RadarRefresh, GitHubClientError>
    let ok: R = .success(PollReducer.RadarRefresh(notModified: false, nextPollAfter: 60, radar: []))
    expectEqual(PollReducer.attemptOutcome(ok), PollAttemptOutcome.success, "200/304 → success")
    let auth401: R = .failure(.http(401, "unauthorized"))
    expectEqual(PollReducer.attemptOutcome(auth401), nil, "401 is an auth-stop, NOT an attempt outcome (rides onAuthFailure)")
    let auth403: R = .failure(.http(403, "forbidden"))
    expectEqual(PollReducer.attemptOutcome(auth403), nil, "non-rate 403 is an auth-stop too")
    let limited: R = .failure(.rateLimited(retryAfter: 120))
    expectEqual(PollReducer.attemptOutcome(limited), PollAttemptOutcome.rateLimited(pauseSeconds: 120),
                "rate limit carries the reducer's REAL pause (same formula, one home)")
    let limitedNoHeader: R = .failure(.rateLimited(retryAfter: nil))
    expectEqual(PollReducer.attemptOutcome(limitedNoHeader), PollAttemptOutcome.rateLimited(pauseSeconds: 60),
                "missing Retry-After → the reducer's 60s floor")
    let shortHeader: R = .failure(.rateLimited(retryAfter: 5))
    expectEqual(PollReducer.attemptOutcome(shortHeader), PollAttemptOutcome.rateLimited(pauseSeconds: 60),
                "a sub-minute header still reports the floored pause the reducer actually takes")
    let transport: R = .failure(.transport("timed out"))
    expectEqual(PollReducer.attemptOutcome(transport), PollAttemptOutcome.transientFailure, "transport failure → genuinely no answer")
    expectEqual(PollReducer.rateLimitPause(retryAfter: nil), 60, "pause floor")
    expectEqual(PollReducer.rateLimitPause(retryAfter: 300), 300, "server's Retry-After honored")
}

suite("TokenLedger — confirmation-claim rule: no string claims more than its event backs") {
    // 'connected' may not appear in ANY state whose GitHub row hasn't actually connected.
    let stored = TokenLedger.reduce(TokenLedger.welcome(), .stored(redacted: "ghp_•(40)"))
    let verifying = TokenLedger.reduce(stored, .sessionStarted(generation: 1))
    for (name, state) in [("welcome", TokenLedger.welcome()), ("stored", stored), ("verifying", verifying),
                          ("retrying", TokenLedger.reduce(verifying, .pollFailed(generation: 1))),
                          ("rate-limited", TokenLedger.reduce(verifying, .pollRateLimited(pauseSeconds: 60, generation: 1))),
                          ("failed-401", TokenLedger.reduce(verifying, .authFailed(.invalidToken)))] {
        let card = TokenLedger.card(for: state)
        expect(!card.rows.contains { $0.detail.contains("connected") }, "'connected' never renders in the \(name) state")
        expect(!card.isComplete, "\(name) never opens the morph gate")
    }
    // And a stored-but-unverified card never claims completion — the exact welcome-steps
    // fabrication the review struck (claim fired on store success).
    expectEqual(TokenLedger.card(for: stored).rows[2].detail, "—", "after store, row 3 still claims nothing")
}

// MARK: - WP-3d′ — CaughtUpPresenter (the affirmation: gating + the tense amendment)
//
// D-copy `voice-plainspoken` AS AMENDED (ratified 2026-07-06). The amendment exists
// because a cold-launch snapshot paint is ALWAYS `.stale` (FreshnessModel.forSnapshot):
// a present-tense "You're all caught up" over a possibly-minutes-dead reading is a
// fabricated state. These suites are the pure proof of every rule the view just inks.

suite("CaughtUpPresenter — the radar-confirmation gate: NEVER affirm an inbox that was never once read ⚠ [fix round 1a]") {
    // Pre-first-radar-read, everything empty and even .fresh (the pre-poll freshness): nothing.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none, "unconfirmed radar → no affirmation (an empty island is unconfirmed, not caught up)")
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false, freshness: .stale(ageSeconds: 400), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none, "unconfirmed radar + degraded → still nothing (never claim from silence)")
    // The same empty inputs WITH a confirmed radar read → the block. The gate is the whole story.
    if case .block = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true) {
        expect(true, "a confirmed radar read flips the SAME inputs to the block")
    } else {
        expect(false, "a confirmed radar read flips the SAME inputs to the block")
    }

    // THE FIX-ROUND SCENARIO (trust major 1a): a pulse-only snapshot — the inbox fetch
    // failed all last session while GraphQL succeeded, persisting radar:[] with
    // lastRadarSuccessAt:nil. The relaunch paint carries data (hasData in the model) but
    // the radar lane is UNCONFIRMED, and the snapshot freshness is anchored to the PULSE
    // lane's age. Pre-fix this rendered "All caught up as of 9h ago" for an inbox githud
    // never once read; the gate must return .none — block AND header phrase.
    let snapNow = ISO8601DateFormatter().date(from: "2026-07-08T10:00:00Z")!
    let pulseOnlyFreshness = FreshnessModel.forSnapshot(
        radarSuccess: nil, pulseSuccess: snapNow.addingTimeInterval(-9 * 3600), now: snapNow)
    expect(pulseOnlyFreshness.isDegraded, "sanity: the pulse-only snapshot paint is degraded")
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false, freshness: pulseOnlyFreshness, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none,
                "pulse-only snapshot (radar never read) → NO block, whatever the painted age says")
    let livePR = PullRequestPulse(repo: "o/r", number: 1, title: "PR1", url: "u1", isDraft: false,
                                  createdAt: "2026-07-07T08:00:00Z", updatedAt: "2026-07-08T08:00:00Z",
                                  ci: .passing, review: .approved, merge: .mergeable)
    let liveRows = [PulsePresenter.row(for: livePR, now: snapNow)]
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: liveRows, radarConfirmed: false, freshness: pulseOnlyFreshness, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none,
                "pulse-only snapshot WITH live PRs → no header phrase either (the header slot stays the wordmark)")
    // The other polarity: the SAME pulse-anchored freshness with a genuinely confirmed
    // radar read → the affirmation returns, past-anchored (the worst-of-both fold may
    // still name the staler lane's age — conservative, like the banner).
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: pulseOnlyFreshness, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of 9h ago", line2: nil),
                "confirmed radar + the same degraded reading → the as-of block renders again")
}

suite("CaughtUpPresenter × PollReducer — toggle-before-first-read: the recompute renders but must NOT confirm ⚠ [fix round 2, 1a residual]") {
    // THE RESIDUAL (round 2, verified reachable): cold launch, radar fetch failing, the
    // user toggles any H1 reason. AppDelegate.toggleReason → PollScheduler.setPreferences
    // → recomputeRadar() over a never-fetched cache ([]) → `.preferencesRecomputed`
    // renders UNCONDITIONALLY. Round 1's `setRadar(confirmed:)` DEFAULT of true let that
    // render fabricate radarConfirmed with zero radar reads → a present-tense "You're all
    // caught up" for an inbox never once read. The wiring rule now: a RENDER never
    // confirms (live renders pass confirmed: false; the default is gone); confirmation
    // rides the radar-success seam (attemptOutcome == .success in poll()) → confirmRadar().
    let (_, e1) = PollReducer.reduce(.preferencesRecomputed([]), state: PollReducer.PollState(), now: reducerNow)
    expectEqual(e1, [.renderRadar([])],
                "the residual's inlet is real: a recompute on a never-fetched cache renders [] unconditionally")
    // Per the wiring rule that render leaves radarConfirmed FALSE → .none in EVERY
    // freshness shape the scenario can wear. <2 failures + no snapshot computes .fresh —
    // the PRESENT-TENSE shape, the worst fabrication:
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none,
                "toggle-before-first-read, fresh shape → NO present-tense affirmation for an inbox never once read")
    // …the failing streak's age-0 shape (no success ever recorded):
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false,
                                          freshness: .failing(consecutive: 2, ageSeconds: 0), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none,
                "…failing(2,0) shape → no 'as of the last check' anchored to a check that never happened")
    // …and the stale shape (a pulse-only snapshot's painted age):
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: false, freshness: .stale(ageSeconds: 9 * 3600), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none, "…stale shape → no past-anchored block either")
    // HONESTY NOTE on reach: this zero-dep runner is Core-only. It pins the reducer facts
    // (the inlet renders; a recompute is an Event with no Result, so it can never produce
    // an attemptOutcome) and the presenter's gate. The wiring itself — setRadar(confirmed:
    // false) on the live render path, PollScheduler.onRadarConfirmed → AppModel
    // .confirmRadar(), and the removed default — lives in the App target, out of this
    // runner's reach; those lines are attested by inspection, and these pinned facts are
    // what make that wiring the only correct shape.
}

suite("PollReducer — the lastKey-adoption trap: an identical-key first-200 emits NO render, but the success seam still fires ⚠ [fix round 2, false-negative polarity]") {
    // The trap the round-2 fix must dodge: flipping confirmation on the RENDER effect
    // (or passing confirmed:false only on the recompute path while keeping the render
    // flip) would be a PERMANENT false negative — the recompute adopts s.lastKey, so a
    // later first-200 with an identical key emits no renderRadar and confirmation would
    // never flip. The seam is the fix: attemptOutcome speaks success on every genuine
    // read, regardless of render emission.
    let t1 = reducerNow.addingTimeInterval(30)
    let (s1, _) = PollReducer.reduce(.preferencesRecomputed([]), state: PollReducer.PollState(), now: reducerNow)
    expectEqual(s1.lastKey, RadarPresenter.changeKey(for: []), "the recompute ADOPTS the key (here: the empty radar's key)")
    let firstSuccess = radarOK([], notModified: false, next: 60)
    let (s2, e2) = PollReducer.reduce(.polled(radar: firstSuccess, pulse: deadPulseFetch), state: s1, now: t1)
    expect(!hasRenderRadar(e2),
           "the identical-key first-200 emits NO renderRadar (the change guard holds — why the flip cannot ride the render)")
    expectEqual(s2.lastSuccessAt, t1, "…yet it IS a genuine radar read (lastSuccessAt stamps)")
    expectEqual(PollReducer.attemptOutcome(firstSuccess), PollAttemptOutcome.success,
                "…and the success seam reports it regardless of render emission — the seam radarConfirmed flips on")
    // A 304 carries the same verdict (it requires a same-session 200 first; both confirm a read):
    expectEqual(PollReducer.attemptOutcome(radarOK([], notModified: true)), PollAttemptOutcome.success,
                "a 304 is a confirmed read too — the seam speaks success for it")
    // Negative polarities: the seam never calls a non-read a read.
    typealias R = Result<PollReducer.RadarRefresh, GitHubClientError>
    expectEqual(PollReducer.attemptOutcome(.failure(.transport("offline")) as R), PollAttemptOutcome.transientFailure,
                "a transient failure is not a read — never success")
    expectEqual(PollReducer.attemptOutcome(.failure(.rateLimited(retryAfter: 120)) as R),
                PollAttemptOutcome.rateLimited(pauseSeconds: 120),
                "a rate-limit is an answer but not a read of the inbox — never success")
    // And once the seam has flipped confirmed (the wiring rule), the SAME painted state
    // becomes an honest affirmation — the fix must not overcorrect into a permanent .none:
    if case .block = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true) {
        expect(true, "post-seam-flip, the identical-key caught-up state affirms (no permanent false negative)")
    } else {
        expect(false, "post-seam-flip, the identical-key caught-up state affirms (no permanent false negative)")
    }
}

suite("CaughtUpPresenter — the age-0 guard: a degraded reading with NO recorded time never fabricates a timestamp ⚠ [fix round 1b]") {
    // ageSeconds == 0 on a degraded reading ⇔ no success time was ever recorded
    // (.failing can fire with a nil lastSuccess). Pre-fix this rendered "All caught up
    // as of 1s ago" — a fabricated update. The line stays past-anchored but time-free,
    // mirroring the pill prefix's own guard + rationale.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                          freshness: .failing(consecutive: 2, ageSeconds: 0), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of the last check", line2: nil),
                "failing with no recorded success → time-free as-of line, never 'as of 1s ago'")
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                          freshness: .stale(ageSeconds: 0), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of the last check", line2: nil),
                "stale(0) (nil-dated snapshot edge) → the same time-free form")
    // Header-phrase polarity of the same guard.
    let now = ISO8601DateFormatter().date(from: "2026-07-08T10:00:00Z")!
    let livePR = PullRequestPulse(repo: "o/r", number: 2, title: "PR2", url: "u2", isDraft: false,
                                  createdAt: "2026-07-07T08:00:00Z", updatedAt: "2026-07-08T08:00:00Z",
                                  ci: .passing, review: .approved, merge: .mergeable)
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [PulsePresenter.row(for: livePR, now: now)],
                                          radarConfirmed: true, freshness: .failing(consecutive: 2, ageSeconds: 0), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.headerPhrase("Caught up as of the last check"),
                "header phrase under age-0 degraded → time-free too")
    // The digit tripwire: NO digit may appear in an age-0 degraded affirmation (that's
    // exactly what a fabricated "1s" would be).
    for degraded in [Freshness.failing(consecutive: 2, ageSeconds: 0), .stale(ageSeconds: 0)] {
        if case .block(let l1, _) = CaughtUpPresenter.display(rows: [], pulse: [],
                                                              radarConfirmed: true, freshness: degraded, inboundConfirmed: true, reviewsConfirmed: true) {
            expect(!l1.contains(where: { $0.isNumber }), "age-0 \(degraded) block names NO number")
        } else {
            expect(false, "age-0 \(degraded) still renders a block")
        }
    }
    // And the age>0 polarity keeps naming the real age (the guard must not over-fire).
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true,
                                          freshness: .failing(consecutive: 2, ageSeconds: 480), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of 8m ago", line2: nil),
                "a REAL recorded age (480s) still speaks: 8m")
}

suite("CaughtUpPresenter — fresh block vs degraded as-of block: the TENSE amendment, explicit ⚠") {
    // Fresh: two lines, present tense — 'right now' is permitted ONLY here.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "You're all caught up", line2: "Nothing needs you right now"),
                "fresh → the two-line present-tense affirmation")
    // Degraded (.stale): ONE as-of line, no line 2 — the block leaves the present tense.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: .stale(ageSeconds: 400), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of 6m ago", line2: nil),
                "stale → one past-anchored line (400s speaks the banner vocabulary: 6m)")
    // Degraded (.failing): same rule — ANY degraded freshness leaves the present tense.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: .failing(consecutive: 3, ageSeconds: 7200), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of 2h ago", line2: nil),
                "failing → the same as-of form (2h)")

    // THE AMENDMENT'S OWN SCENARIO: the cold-launch snapshot paint. forSnapshot is never
    // .fresh, so the launch-painted caught-up island must never speak the present.
    let snapNow = ISO8601DateFormatter().date(from: "2026-07-07T10:00:00Z")!
    let snapshotFreshness = FreshnessModel.forSnapshot(
        radarSuccess: snapNow.addingTimeInterval(-9 * 3600), pulseSuccess: nil, now: snapNow)
    expect(snapshotFreshness.isDegraded, "sanity: a snapshot paint is always degraded (never .fresh)")
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: snapshotFreshness, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.block(line1: "All caught up as of 9h ago", line2: nil),
                "cold-launch snapshot paint → as-of, never a present-tense all-clear")

    // String-level tense tripwire: sweep every degraded shape — INCLUDING the age-0
    // never-succeeded shapes (fix round 1b) — the present-tense words may not appear
    // ANYWHERE in a degraded display.
    for degraded in [Freshness.stale(ageSeconds: 200), .stale(ageSeconds: 90_000),
                     .failing(consecutive: 2, ageSeconds: 400), snapshotFreshness,
                     .failing(consecutive: 2, ageSeconds: 0), .stale(ageSeconds: 0)] {
        let display = CaughtUpPresenter.display(rows: [], pulse: [], radarConfirmed: true, freshness: degraded, inboundConfirmed: true, reviewsConfirmed: true)
        if case .block(let l1, let l2) = display {
            expect(!l1.contains("right now") && !(l2 ?? "").contains("right now"),
                   "degraded \(degraded) never says 'right now'")
            expect(!l1.contains("You're"), "degraded \(degraded) never speaks the present-tense 'You're' form")
            expectEqual(l2, nil, "degraded \(degraded) is the ONE-line form")
        } else {
            expect(false, "degraded \(degraded) still renders a block")
        }
    }
}

suite("CaughtUpPresenter — radar-empty-with-live-PRs: header phrase, same tense rule; live rule shared with the pill ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-07T10:00:00Z")!
    func pr(_ n: Int, draft: Bool = false, updated: String = "2026-07-07T08:00:00Z") -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: "2026-06-30T08:00:00Z", updatedAt: updated,
                         ci: .passing, review: .approved, merge: .mergeable)
    }
    func rows(_ prs: [PullRequestPulse]) -> [PulseRow] { prs.map { PulsePresenter.row(for: $0, now: now) } }

    // Live PRs present → the header slot carries the state; the lane renders as today.
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: rows([pr(1)]), radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.headerPhrase("All caught up"),
                "live PRs + fresh → header phrase 'All caught up'")
    expectEqual(CaughtUpPresenter.display(rows: [], pulse: rows([pr(1)]), radarConfirmed: true, freshness: .stale(ageSeconds: 480), inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.headerPhrase("Caught up as of 8m ago"),
                "live PRs + degraded → 'Caught up as of 8m ago' (the amendment binds the header slot too)")

    // The live-work rule is the pill's own: stale/draft-only pulses have NO live rows —
    // the pill speaks "You're all caught up" there, so the island renders the BLOCK, not
    // the with-PRs header phrase (the two surfaces may never disagree).
    let quiet = rows([pr(2, draft: true), pr(3, updated: "2026-03-01T00:00:00Z")])
    expect(PulsePresenter.sections(for: quiet).active.isEmpty, "sanity: draft+stale only → no live rows")
    if case .block(let l1, _) = CaughtUpPresenter.display(rows: [], pulse: quiet, radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true) {
        expectEqual(l1, CaughtUpPresenter.caughtUpLine, "stale/draft-only pulse → the full block (pill parity)")
    } else {
        expect(false, "stale/draft-only pulse → the full block (pill parity)")
    }

    // A non-empty radar silences every affirmation (there IS something needing you).
    let items = "{\"id\":\"1\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"2026-07-07T08:00:00Z\",\"subject\":{\"title\":\"t\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
    let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
    let radar = RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    expect(!radar.isEmpty, "sanity: the radar row surfaced")
    expectEqual(CaughtUpPresenter.display(rows: radar, pulse: rows([pr(1)]), radarConfirmed: true, freshness: .fresh, inboundConfirmed: true, reviewsConfirmed: true),
                CaughtUpPresenter.Display.none, "radar non-empty → no affirmation anywhere")
}

// MARK: - WP-3d′ — stable row identity + change signature (D-reveal blocking amendment 2)

suite("RadarRow — stable id is the THREAD id, never the collidable url; signature tracks display content ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-07T10:00:00Z")!
    // Two DIFFERENT threads in one repo, neither with a subject url → both fall back to
    // the SAME repo-page url (the exact collision the amendment names). A url-keyed stash
    // would peek both rows from one click; the thread id keeps them distinct.
    func thread(_ id: String, title: String, updated: String = "2026-07-07T08:00:00Z",
                excerpt: String? = nil) -> String {
        let excerptField = excerpt.map { ",\"latest_comment_excerpt\":\"\($0)\"" } ?? ""
        return "{\"id\":\"\(id)\",\"unread\":true,\"reason\":\"review_requested\",\"updated_at\":\"\(updated)\",\"subject\":{\"title\":\"\(title)\",\"type\":\"PullRequest\",\"url\":null,\"latest_comment_url\":null}\(excerptField),\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
    }
    func rows(_ json: [String]) -> [RadarRow] {
        let threads = (try? NotificationThread.list(from: Data("[\(json.joined(separator: ","))]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }

    let pair = rows([thread("7001", title: "first"), thread("7002", title: "second")])
    expectEqual(pair.count, 2, "both threads surfaced")
    expectEqual(pair.map { $0.url }, [pair.first?.url ?? "", pair.first?.url ?? ""],
                "the two rows COLLIDE on the repo-page fallback url (the amendment's scenario)")
    expect(pair[0].id != pair[1].id, "…but their stable ids stay distinct (thread ids)")
    expectEqual(Set(pair.map { $0.id }), ["7001", "7002"], "id IS the thread id, verbatim")

    // Signature: stable when nothing display-affecting changed…
    let a1 = rows([thread("7001", title: "first")])[0]
    let a2 = rows([thread("7001", title: "first")])[0]
    expectEqual(a1.changeSignature, a2.changeSignature, "identical content → identical signature")
    // …changed by a retitle, a fresh update stamp, or an excerpt landing (each alone).
    expect(rows([thread("7001", title: "renamed")])[0].changeSignature != a1.changeSignature,
           "title change flips the signature")
    expect(rows([thread("7001", title: "first", updated: "2026-07-07T09:30:00Z")])[0].changeSignature != a1.changeSignature,
           "updatedAt change flips the signature (a new event under the same texts)")
    expect(rows([thread("7001", title: "first", excerpt: "new comment body")])[0].changeSignature != a1.changeSignature,
           "an enrichment excerpt landing flips the signature")
    // The id survives every one of those changes — identity ≠ content.
    expectEqual(rows([thread("7001", title: "renamed", excerpt: "x")])[0].id, "7001",
                "the id is constant across content changes")
}

suite("PulseRow — stable id 'owner/repo#n'; signature tracks title/subtitle/state/updatedAt ⚠") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-07T10:00:00Z")!
    func pr(_ ci: CIState, review: ReviewState = .approved, merge: MergeState = .mergeable,
            title: String = "PR7", updated: String = "2026-07-07T08:00:00Z") -> PulseRow {
        PulsePresenter.row(for: PullRequestPulse(repo: "o/r", number: 7, title: title, url: "u7",
                                                 isDraft: false, createdAt: "2026-06-30T08:00:00Z",
                                                 updatedAt: updated, ci: ci, review: review, merge: merge),
                           now: now)
    }
    let base = pr(.passing)
    expectEqual(base.id, "o/r#7", "id = repo#number")
    expectEqual(pr(.failing).id, "o/r#7", "id survives a state flip (identity ≠ content)")
    expectEqual(pr(.passing).changeSignature, base.changeSignature, "identical content → identical signature")
    expect(pr(.failing).changeSignature != base.changeSignature, "a CI flip changes the signature")
    expect(pr(.passing, merge: .conflicting).changeSignature != base.changeSignature, "a merge problem changes the signature")
    expect(pr(.passing, title: "retitled").changeSignature != base.changeSignature, "a retitle changes the signature")
    expect(pr(.passing, updated: "2026-07-07T09:45:00Z").changeSignature != base.changeSignature,
           "a fresh update stamp changes the signature")
}

// MARK: - WP-3d′ — PeekStash (the ScrollOffsets-style carry, with the honesty drop)

suite("PeekStash — keyed on stable id, restored only on a matching signature, dropped when content changed ⚠") {
    var stash = PeekStash()
    expect(stash.isEmpty, "fresh stash is empty (a fresh expand opens clean)")

    // Open a peek: it restores across a rebuild while the signature holds.
    stash.setOpen(true, id: "7001", signature: "sigA")
    expect(stash.isOpen(id: "7001", signature: "sigA"), "open peek restores on an unchanged row")
    expect(!stash.isOpen(id: "7002", signature: "sigA"), "a different row is untouched")

    // The DROP rule: same id, new signature → the content is new; re-truncate honestly.
    expect(!stash.isOpen(id: "7001", signature: "sigB"),
           "changed signature → the peek DROPS (content is new — never restore a reveal over different text)")

    // Closing removes the entry entirely (a closed row carries no state).
    stash.setOpen(false, id: "7001", signature: "sigA")
    expect(!stash.isOpen(id: "7001", signature: "sigA"), "closed → no longer restored")
    expect(stash.isEmpty, "closing the only peek empties the stash")

    // Re-peek after a content change stores the NEW signature.
    stash.setOpen(true, id: "7001", signature: "sigB")
    expect(stash.isOpen(id: "7001", signature: "sigB"), "re-peek binds to the new signature")
    expect(!stash.isOpen(id: "7001", signature: "sigA"), "…and the old signature stays dead")

    // Reset-on-collapse is the caller's contract: a NEW stash (what a collapsed render
    // hands the next expand) restores nothing.
    let fresh = PeekStash()
    expect(!fresh.isOpen(id: "7001", signature: "sigB"), "a fresh expand's stash restores nothing")
}

// MARK: - WP-3d′ — PeekReveal (truncation predicate + the hitTest carve-out, pure halves)

suite("PeekReveal — truncation predicate: title OR subtitle OR excerpt (amendment 3 — the subtitle is in the OR) ⚠") {
    expect(!PeekReveal.needsChevron(titleFits: true, subtitleFits: true, excerptFits: true),
           "nothing hidden → no chevron (truncated-only rule: never fake chrome)")
    expect(PeekReveal.needsChevron(titleFits: false, subtitleFits: true, excerptFits: true),
           "title-only truncation → chevron")
    expect(PeekReveal.needsChevron(titleFits: true, subtitleFits: false, excerptFits: true),
           "SUBTITLE-only truncation → chevron (the shared defect the review fixed across all variants)")
    expect(PeekReveal.needsChevron(titleFits: true, subtitleFits: true, excerptFits: false),
           "excerpt-only truncation → chevron")
    expect(PeekReveal.needsChevron(titleFits: false, subtitleFits: false, excerptFits: false),
           "everything truncated → chevron")
    // Ratified caps ride along as the one shared home the views read.
    expectEqual(PeekReveal.titleLineCap, 3, "peeked title cap = 3 lines")
    expectEqual(PeekReveal.subtitleLineCap, 2, "peeked subtitle cap = 2 lines")
    expectEqual(PeekReveal.excerptLineCap, 4, "peeked excerpt cap = 4 lines")
}

suite("PeekReveal — the hitTest carve-out: a chevron click NEVER resolves to the row (amendment 1) ⚠") {
    // The row geometry the views actually build: a 484×~44 row with the 22×18 chevron
    // pinned to its top-trailing corner (RowMetrics: 484 − 22 = 462).
    let rowBounds = CGRect(x: 0, y: 0, width: 484, height: 44)
    let chevron = CGRect(x: 462, y: 26, width: 22, height: 18)   // top-trailing in flipped-ish terms

    // THE never-navigates proof, pure half: sweep the chevron's frame — every point
    // resolves to the chevron and never the row (the failure direction the review named:
    // a peek attempt that navigates is the worst possible violation).
    var chevronMisses = 0
    for dx in stride(from: CGFloat(0.5), to: chevron.width, by: 3.5) {
        for dy in stride(from: CGFloat(0.5), to: chevron.height, by: 3.5) {
            let p = CGPoint(x: chevron.minX + dx, y: chevron.minY + dy)
            if PeekReveal.hitTarget(point: p, rowBounds: rowBounds, chevronFrame: chevron) != .chevron {
                chevronMisses += 1
            }
        }
    }
    expectEqual(chevronMisses, 0, "EVERY point inside the chevron frame resolves to .chevron — a chevron click never navigates")

    // Every other point in the row stays the flattened one-target row (Open-on-GitHub
    // byte-for-byte — clicks on labels/gaps never leak to child views OR the chevron).
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: 10, y: 10), rowBounds: rowBounds, chevronFrame: chevron),
                PeekReveal.HitTarget.row, "a text click is the row")
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: 455, y: 30), rowBounds: rowBounds, chevronFrame: chevron),
                PeekReveal.HitTarget.row, "a click in the gap just left of the chevron is still the row")
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: 470, y: 5), rowBounds: rowBounds, chevronFrame: chevron),
                PeekReveal.HitTarget.row, "a click BELOW the chevron (inside the row) is the row, not the chevron")

    // Outside the row: nobody (the lane's other rows own their own bounds).
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: -1, y: 10), rowBounds: rowBounds, chevronFrame: chevron),
                PeekReveal.HitTarget.none, "outside the row → no target")
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: 100, y: 50), rowBounds: rowBounds, chevronFrame: chevron),
                PeekReveal.HitTarget.none, "above the row → no target")

    // No chevron on the row (nothing truncates) → the whole row is the one target, as today.
    expectEqual(PeekReveal.hitTarget(point: CGPoint(x: 470, y: 30), rowBounds: rowBounds, chevronFrame: nil),
                PeekReveal.HitTarget.row, "chevron-less row: the trailing corner is still just the row")
}

// MARK: - KeySession (WP-6k — the ⌃⌥G scoped key session's pure brain)

suite("KeySession — flattened actionable list: radar then pulse, structure skipped") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-06-16T10:00:00Z")!
    // Real RadarRows the sanctioned way (JSON → NotificationThread → classify → row) —
    // RadarRow has no public memberwise init across the module boundary.
    func radarRows(_ reasons: [String]) -> [RadarRow] {
        let items = reasons.enumerated().map { i, reason in
            "{\"id\":\"r\(i)\",\"unread\":true,\"reason\":\"\(reason)\",\"updated_at\":\"2026-06-16T08:00:00Z\",\"subject\":{\"title\":\"t\(i)\",\"type\":\"PullRequest\",\"latest_comment_url\":null},\"repository\":{\"full_name\":\"o/r\",\"private\":false,\"owner\":{\"login\":\"o\",\"type\":\"Organization\"}}}"
        }.joined(separator: ",")
        let threads = (try? NotificationThread.list(from: Data("[\(items)]".utf8))) ?? []
        return RadarPresenter.rows(for: SignalClassifier.radar(threads), now: now)
    }
    func pr(_ n: Int, ci: CIState = .passing, draft: Bool = false, updated: String = "2026-06-16T08:00:00Z") -> PullRequestPulse {
        PullRequestPulse(repo: "o/r", number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: "2026-05-01T08:00:00Z", updatedAt: updated,
                         ci: ci, review: .approved, merge: .mergeable)
    }
    let radar = radarRows(["review_requested", "mention"])
    expectEqual(radar.count, 2, "two radar rows built")
    // Pulse mix: 2 active, 1 stale (untouched 40d), 1 draft.
    let pulse = PulsePresenter.rows(for: [pr(1), pr(2, ci: .failing), pr(3, updated: "2026-05-01T08:00:00Z"), pr(4, draft: true)], now: now)
    let sections = PulsePresenter.sections(for: pulse)
    expectEqual(sections.active.count, 2, "pulse mix: 2 active")
    expectEqual(sections.stale.count, 1, "pulse mix: 1 stale")
    expectEqual(sections.drafts.count, 1, "pulse mix: 1 draft")

    // MIXED, default prefs (stale + drafts hidden): radar in order, then active pulse
    // only — the stale-count caption line contributes NOTHING (structure, not a row).
    let mixed = KeySession.actionableIDs(radar: radar, pulse: pulse, showDrafts: false, showStale: false)
    expectEqual(mixed, radar.map(\.id) + sections.active.map(\.id),
                "mixed: radar ids in order, then live pulse ids — hidden stale/drafts (and their caption) contribute nothing")
    expectEqual(mixed.count, 4, "mixed default = 2 radar + 2 active pulse")

    // Opted-in groups append in on-screen order: active → drafts → quiet (their
    // section HEADERS are skipped by construction — only rows contribute ids).
    let withStale = KeySession.actionableIDs(radar: radar, pulse: pulse, showDrafts: false, showStale: true)
    expectEqual(withStale, radar.map(\.id) + sections.active.map(\.id) + sections.stale.map(\.id),
                "showStale appends the quiet rows after the live group")
    // THE FLAT-SHAPE REORDER (WP 2026-07-29-001): drafts now precede quiet, matching the ratified
    // per-group tail order (rows → drafts → quiet). Before V3 quiet sat above drafts, inherited
    // from `PulseSections`' field order rather than chosen — so the flat lane and a grouped lane
    // disagreed about which tail came first. One mental model, deliberately visible.
    let withBoth = KeySession.actionableIDs(radar: radar, pulse: pulse, showDrafts: true, showStale: true)
    expectEqual(withBoth, radar.map(\.id) + sections.active.map(\.id) + sections.drafts.map(\.id) + sections.stale.map(\.id),
                "showStale+showDrafts: active → drafts → quiet (the exact render order)")
    let draftsOnly = KeySession.actionableIDs(radar: radar, pulse: pulse, showDrafts: true, showStale: false)
    expectEqual(draftsOnly, radar.map(\.id) + sections.active.map(\.id) + sections.drafts.map(\.id),
                "showDrafts alone appends drafts, stale stays out")

    // Single-lane and empty islands.
    expectEqual(KeySession.actionableIDs(radar: radar, pulse: [], showDrafts: false, showStale: false),
                radar.map(\.id), "radar-only island flattens to the radar ids")
    expectEqual(KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: false, showStale: false),
                sections.active.map(\.id), "pulse-only island flattens to the live pulse ids")
    expectEqual(KeySession.actionableIDs(radar: [], pulse: [], showDrafts: true, showStale: true),
                [], "empty lanes → empty list (a caught-up island has nothing to select)")
}

suite("KeySession — the key map (↑↓⏎ esc space consumed; everything else falls through)") {
    expectEqual(KeySession.intent(forKeyCode: 126), .moveUp, "126 → moveUp")
    expectEqual(KeySession.intent(forKeyCode: 125), .moveDown, "125 → moveDown")
    expectEqual(KeySession.intent(forKeyCode: 36), .open, "36 ⏎ → open")
    expectEqual(KeySession.intent(forKeyCode: 53), .dismiss, "53 esc → dismiss")
    expectEqual(KeySession.intent(forKeyCode: 49), .peek, "49 space → peek (D-reveal's ratified mapping)")
    expectEqual(KeySession.intent(forKeyCode: 76), .passthrough, "76 keypad-enter is NOT mapped (spec names 36 only)")
    expectEqual(KeySession.intent(forKeyCode: 48), .passthrough, "48 tab falls through")
    expectEqual(KeySession.intent(forKeyCode: 0), .passthrough, "0 'a' falls through (letters are not captured)")
    expectEqual(KeySession.intent(forKeyCode: 123), .passthrough, "123 ← falls through (only ↑/↓ move the bar)")
    expectEqual(KeySession.intent(forKeyCode: 124), .passthrough, "124 → falls through")
}

suite("KeySelection — initial selection, clamped movement, no wrap") {
    var sel = KeySelection(ids: ["a", "b", "c"])
    expectEqual(sel.selectedID, "a", "initial selection = first actionable row")
    expectEqual(sel.index, 0, "initial index 0")
    sel.moveUp()
    expectEqual(sel.selectedID, "a", "↑ at the top clamps (no wrap to the bottom)")
    sel.moveDown()
    expectEqual(sel.selectedID, "b", "↓ steps to the second row")
    sel.moveDown()
    expectEqual(sel.selectedID, "c", "↓ steps to the last row")
    sel.moveDown()
    expectEqual(sel.selectedID, "c", "↓ at the bottom clamps (no wrap to the top)")
    sel.moveUp()
    expectEqual(sel.selectedID, "b", "↑ steps back up")

    var single = KeySelection(ids: ["only"])
    single.moveDown(); single.moveUp(); single.moveDown()
    expectEqual(single.selectedID, "only", "single-row list: every move clamps in place")

    var empty = KeySelection(ids: [])
    expect(empty.isEmpty, "empty list reports isEmpty")
    expectEqual(empty.selectedID, nil, "empty list has no selection (nothing to put the bar on)")
    empty.moveDown(); empty.moveUp()
    expectEqual(empty.selectedID, nil, "moves on an empty list are safe no-ops")
}

suite("KeySelection — rebuild survives data rebuilds keyed on the STABLE row id") {
    // The id survives → the selection follows it to its new position.
    var sel = KeySelection(ids: ["a", "b", "c"])
    sel.moveDown()                                  // on "b"
    sel.rebuild(ids: ["x", "a", "b", "c"])          // a new row lands above
    expectEqual(sel.selectedID, "b", "selection follows the stable id, not the index")
    expectEqual(sel.index, 2, "…to its new position")
    sel.rebuild(ids: ["b"])                         // everything else dropped
    expectEqual(sel.selectedID, "b", "sole survivor keeps the selection")
    expectEqual(sel.index, 0, "…at its new index")

    // The selected row is dropped → clamp to the nearest index (never reset to top).
    var dropped = KeySelection(ids: ["a", "b", "c"])
    dropped.moveDown()                              // on "b" (index 1)
    dropped.rebuild(ids: ["a", "c"])                // "b" vanished
    expectEqual(dropped.selectedID, "c", "dropped row → same index position (the nearest neighbor)")
    var droppedEnd = KeySelection(ids: ["a", "b", "c"])
    droppedEnd.moveDown(); droppedEnd.moveDown()    // on "c" (index 2)
    droppedEnd.rebuild(ids: ["x"])                  // shrank past the old index
    expectEqual(droppedEnd.selectedID, "x", "old index past the new end clamps to the last row")
    expectEqual(droppedEnd.index, 0, "…index clamped into bounds")

    // Rebuild to/from empty.
    var toEmpty = KeySelection(ids: ["a"])
    toEmpty.rebuild(ids: [])
    expectEqual(toEmpty.selectedID, nil, "rebuild to empty → no selection (session may outlive its rows)")
    toEmpty.rebuild(ids: ["n1", "n2"])
    expectEqual(toEmpty.selectedID, "n1", "rows returning after empty → selection lands on the first row")
    toEmpty.moveDown()
    expectEqual(toEmpty.selectedID, "n2", "…and moves normally again")
}

// MARK: - PlainWords (WP 2026-07-12-001 — flavor C copy, count-interpolated)

suite("PlainWords — the ratified flavor-C strings, singular + plural") {
    // Stale ("gone quiet") caption — count interpolates; the parenthesized verb is baked in.
    expectEqual(PlainWords.staleCaption(1), "1 gone quiet (show)", "stale caption, singular")
    expectEqual(PlainWords.staleCaption(3), "3 gone quiet (show)", "stale caption, plural")
    expectEqual(PlainWords.staleCaptionSpoken(1), "1 gone quiet, show", "stale caption VO, singular")
    expectEqual(PlainWords.staleCaptionSpoken(3), "3 gone quiet, show", "stale caption VO, plural")
    expectEqual(PlainWords.staleHeader, "Gone quiet", "revealed stale header")

    // Held-back inbound ("bots & drafts") caption.
    expectEqual(PlainWords.heldBackCaption(1), "1 from bots & drafts (show)", "held-back caption, singular")
    expectEqual(PlainWords.heldBackCaption(2), "2 from bots & drafts (show)", "held-back caption, plural")
    expectEqual(PlainWords.heldBackCaptionSpoken(1), "1 from bots & drafts, show", "held-back caption VO, singular")
    expectEqual(PlainWords.heldBackCaptionSpoken(2), "2 from bots & drafts, show", "held-back caption VO, plural")
    expectEqual(PlainWords.heldBackHeader, "Bots & drafts", "revealed held-back header")

    // The affordance verbs.
    expectEqual(PlainWords.showVerb, "(show)", "show verb token")
    expectEqual(PlainWords.hideControl, "(hide)", "hide control")
    expectEqual(PlainWords.hideSpoken, "hide", "hide control VO")

    // Structural invariant: every caption ENDS with the underline-able verb token, so the
    // App's `range(of: showVerb)` always resolves (the underline never silently no-ops).
    expect(PlainWords.staleCaption(9).hasSuffix(PlainWords.showVerb), "stale caption carries the verb token")
    expect(PlainWords.heldBackCaption(9).hasSuffix(PlainWords.showVerb), "held-back caption carries the verb token")

    // Gear items — the threshold demoted from the title to the tooltip (off the glass).
    expectEqual(PlainWords.staleGearItem, "Show PRs gone quiet", "stale gear title")
    expectEqual(PlainWords.staleGearTooltip, "untouched for 14 days or more", "stale gear tooltip (the demoted threshold)")
    expectEqual(PlainWords.heldBackGearItem, "Show bots & drafts", "held-back gear title")
    expectEqual(PlainWords.heldBackGearTooltip, "Bot and draft arrivals held back from the queue", "held-back gear tooltip")

    // WP 2026-07-12-001 addendum — Drafts joins the revealed-header family. The header
    // replaces the old bare "Drafts"; the gear title is unchanged (just homed here) and
    // gains a tooltip like its two siblings. PRESERVED ASYMMETRY: there is deliberately no
    // `draftsCaption` — hidden drafts stay fully invisible (no count left behind).
    expectEqual(PlainWords.draftsHeader, "Draft PRs", "drafts revealed header (replaces bare \"Drafts\")")
    expectEqual(PlainWords.draftsGearItem, "Show draft PRs", "drafts gear title (unchanged, now homed)")
    expectEqual(PlainWords.draftsGearTooltip, "Your works-in-progress, kept out of the glance", "drafts gear tooltip")
}

// MARK: - RadarReading (WP 2026-07-17-001 — the reading's policy, pure + tested)

suite("RadarReading — terminal-only verdict caching (the 304 re-verify rule)") {
    let json = """
    [{"id":"t1","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"https://api.github.com/repos/o/r/pulls/1"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}]
    """
    var reading = RadarReading()
    reading.adopt200(threads: (try? NotificationThread.list(from: Data(json.utf8))) ?? [], scopes: "repo")
    expect(!reading.applySubjectVerdict(at: 0, state: "open"), "\"open\" is perishable — never stored")
    expectEqual(reading.threads[0].subjectState, nil, "…state stays nil so the next 200 re-checks")
    expect(reading.applySubjectVerdict(at: 0, state: "merged"), "terminal verdict stores")
    expectEqual(reading.threads[0].subjectState, "merged", "…and can't un-happen")
}

suite("RadarReading — latches: consolidated, per-call clear, decline-on-empty") {
    let json = """
    [{"id":"t1","unread":true,"reason":"mention","updated_at":"t","subject":{"title":"x","type":"Issue"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}}]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []

    // Decline-on-empty: an armed latch over an EMPTY cache drops harmlessly (a
    // snapshot-painted radar must not be wiped by an empty re-projection).
    var empty = RadarReading()
    empty.resolvedSelf("me")
    expect(!empty.consumeResolutions(), "armed latch + empty cache → declined")
    expect(!empty.consumeResolutions(), "…and the latch did NOT survive the call")

    var reading = RadarReading()
    reading.adopt200(threads: threads, scopes: nil)
    reading.resolvedSelf("me")
    expect(reading.consumeResolutions(), "self resolution arms → consumed true")
    expect(!reading.consumeResolutions(), "one-shot: second call false")
    reading.markSubjectResolution()
    expect(reading.consumeResolutions(), "subject flip arms the SAME consolidated latch")
    expect(!reading.consumeResolutions(), "…and clears per call")
}

suite("RadarReading — resolvedSelf encodes F9 (only an obtained login resolves)") {
    var reading = RadarReading()
    reading.resolvedSelf(nil)
    expect(!reading.selfResolved, "completed-but-failed GET /user must retry — nil never resolves")
    expectEqual(reading.selfLogin, nil, "…no login adopted")
    reading.resolvedSelf("pro-vi")
    expect(reading.selfResolved, "an obtained login resolves")
    expectEqual(reading.selfLogin, "pro-vi", "…and is adopted")
    reading.resolvedSelf("someone-else")
    expectEqual(reading.selfLogin, "pro-vi", "resolution is once per process — never re-adopts")
}

suite("RadarReading — 304 re-verify: throttle stamps on ATTEMPT; targets predicate") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-17T12:00:00Z")!
    var reading = RadarReading()
    expect(reading.reverifyDue(now: now), "distantPast baseline → first verify due")
    reading.stampReverify(now: now)
    expect(!reading.reverifyDue(now: now.addingTimeInterval(300)), "inside the 600s window → not due (stamp happened on attempt)")
    expect(reading.reverifyDue(now: now.addingTimeInterval(601)), "past the window → due again")

    let json = """
    [
      {"id":"ok","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u1"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"read","unread":false,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u2"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"done","unread":true,"reason":"review_requested","updated_at":"t","subject_state":"closed","subject":{"title":"x","type":"PullRequest","url":"u3"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"legacy","unread":true,"reason":"review_requested","updated_at":"t","subject_state":"open","subject":{"title":"x","type":"PullRequest","url":"u4"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"rel","unread":true,"reason":"mention","updated_at":"t","subject":{"title":"x","type":"Release","url":"u5"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"nourl","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"noise","unread":true,"reason":"ci_activity","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u6"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"priv","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u7"},"repository":{"full_name":"o/p","private":true,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    var scoped = RadarReading()
    scoped.adopt200(threads: (try? NotificationThread.list(from: Data(json.utf8))) ?? [], scopes: "notifications, repo")
    let ids = scoped.reverifyTargets().map { scoped.threads[$0].id }
    expectEqual(ids.sorted(), ["legacy", "ok", "priv"],
                "targets = unread ∧ (nil|legacy-open) ∧ PR/Issue ∧ url ∧ surfaced; read/resolved/Release/no-url/noise excluded; private INCLUDED under repo scope")

    var unscoped = RadarReading()
    unscoped.adopt200(threads: (try? NotificationThread.list(from: Data(json.utf8))) ?? [], scopes: "notifications")
    let unscopedIDs = unscoped.reverifyTargets().map { unscoped.threads[$0].id }
    expect(!unscopedIDs.contains("priv"), "no repo scope → private repos leave the target set (never burn the timeout)")
}

suite("RadarReading — enrichment targets: pass predicates + scope skip counted") {
    let json = """
    [
      {"id":"rr","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u1","latest_comment_url":null},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"mn","unread":true,"reason":"mention","updated_at":"t","subject":{"title":"x","type":"Issue","url":"u2","latest_comment_url":"c2"},"repository":{"full_name":"o/r","private":false,"owner":{"login":"o","type":"Organization"}}},
      {"id":"privrr","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"x","type":"PullRequest","url":"u3","latest_comment_url":null},"repository":{"full_name":"o/p","private":true,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    var reading = RadarReading()
    reading.adopt200(threads: (try? NotificationThread.list(from: Data(json.utf8))) ?? [], scopes: nil)
    expect(!reading.repoScope, "nil scopes → no repo scope")
    let subject = reading.subjectStateTargets()
    expectEqual(subject.hits.map { reading.threads[$0].id }, ["rr", "mn"], "subject pass targets the action set, in thread order")
    expectEqual(subject.skippedPrivate, 1, "the scope-blocked private target is COUNTED, never fetched")
    let author = reading.commentAuthorTargets()
    expectEqual(author.hits.map { reading.threads[$0].id }, ["mn"], "author pass needs a comment url")

    reading.cacheCommentAuthor(at: 1, login: "colleague", body: "hello world")
    expectEqual(reading.threads[1].latestCommentAuthorLogin, "colleague", "author cached")
    expect(reading.commentAuthorTargets().hits.isEmpty, "…and the target leaves the set (no re-fetch)")
}

suite("RadarReading — inbound adopt baseline rides the reading") {
    func item(_ n: Int) -> String {
        "{\"number\":\(n),\"title\":\"i\(n)\",\"html_url\":\"https://github.com/o/r/pull/\(n)\",\"created_at\":\"2026-07-01T00:00:00Z\",\"updated_at\":\"2026-07-01T00:00:00Z\",\"repository_url\":\"https://api.github.com/repos/o/r\",\"user\":{\"login\":\"a\",\"type\":\"User\"},\"draft\":false,\"pull_request\":{}}"
    }
    func reading(_ items: [Int], incomplete: Bool, total: Int) -> InboundReading? {
        let json = "{\"total_count\":\(total),\"incomplete_results\":\(incomplete),\"items\":[\(items.map(item).joined(separator: ","))]}"
        return try? InboundItem.reading(fromSearchData: Data(json.utf8))
    }
    guard let full = reading([1, 2], incomplete: false, total: 2),
          let partial = reading([1], incomplete: true, total: 2) else {
        expect(false, "fixtures decode"); return
    }
    var r = RadarReading()
    let adopted1 = r.adoptInbound(full)
    expectEqual(adopted1.items.count, 2, "complete reading adopts")
    let adopted2 = r.adoptInbound(partial)
    expectEqual(adopted2.items.count, 2, "incomplete never removes — baseline kept whole")
    expectEqual(r.inboundBaseline?.items.count, 2, "…and the baseline persists on the reading")
}

// MARK: - Deliberate routing vs bot demotion (dogfood 2026-07-17 — the fatal-miss class)

suite("SurfacePreferences — bot demotion never touches deliberate routing") {
    let json = """
    [
      {"id":"rrB","unread":true,"reason":"review_requested","updated_at":"t","latest_comment_author_login":"github-actions[bot]","subject":{"title":"[ENG-1] fix(web): report view","type":"PullRequest","latest_comment_url":"u","url":"https://api.github.com/repos/o/r/pulls/1"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"rrD","unread":true,"reason":"review_requested","updated_at":"t","subject":{"title":"Bump lodash from 4.17.20 to 4.17.21","type":"PullRequest","latest_comment_url":null,"url":"https://api.github.com/repos/o/r/pulls/2"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"rrC","unread":true,"reason":"review_requested","updated_at":"t","subject_state":"closed","subject":{"title":"done ask","type":"PullRequest","latest_comment_url":null,"url":"https://api.github.com/repos/o/r/pulls/3"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"asB","unread":true,"reason":"assign","updated_at":"t","latest_comment_author_login":"ci[bot]","subject":{"title":"x","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"tmB","unread":true,"reason":"team_mention","updated_at":"t","latest_comment_author_login":"github-actions[bot]","subject":{"title":"x","type":"Issue","latest_comment_url":"u"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    expectEqual(threads.count, 5, "decoded 5 threads")
    let prefs = SurfacePreferences.auto
    func surfaces(_ id: String) -> Bool {
        threads.first { $0.id == id }.map { prefs.surfaces($0, selfLogin: "me") } ?? false
    }

    // THE dogfood bug: an OPEN review request where CI spoke last must surface —
    // the latest commenter says nothing about whether the review is still owed.
    expect(surfaces("rrB"), "review_requested with a bot latest-commenter SURFACES (the 2026-07-17 miss)")
    // Never-miss over tidy: a dependabot PR that CODEOWNERS routes to you is still a
    // real review request (cost disclosed via the probe's policy-b line).
    expect(surfaces("rrD"), "dependabot-titled review request surfaces (deliberate routing wins)")
    // Resolution still outranks routing — a CLOSED ask is not owed.
    expect(!surfaces("rrC"), "closed review request stays suppressed (resolved wins)")
    expect(surfaces("asB"), "assignment with a bot latest-commenter surfaces")
    // Ambient reasons keep their bot demotion — matching classify()'s own handling.
    expect(!surfaces("tmB"), "team_mention by automation stays suppressed (ambient)")

    // The radar itself agrees end-to-end.
    let radar = SignalClassifier.radar(threads, selfLogin: "me", preferences: prefs)
    expectEqual(radar.map { $0.thread.id }.sorted(), ["asB", "rrB", "rrD"],
                "radar = exactly the live deliberate asks; closed + ambient-bot stay out")
}

suite("SurfacePreferences — an ANSWERED @mention is discharged (ball in others' court)") {
    let json = """
    [
      {"id":"mnA","unread":true,"reason":"mention","updated_at":"t","latest_comment_author_login":"pro-vi","subject":{"title":"q for you","type":"PullRequest","latest_comment_url":"u","url":"https://api.github.com/repos/o/r/pulls/9"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"mnO","unread":true,"reason":"mention","updated_at":"t","latest_comment_author_login":"colleague","subject":{"title":"q for you","type":"PullRequest","latest_comment_url":"u","url":"https://api.github.com/repos/o/r/pulls/10"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}},
      {"id":"rrA","unread":true,"reason":"review_requested","updated_at":"t","latest_comment_author_login":"pro-vi","subject":{"title":"needs review","type":"PullRequest","latest_comment_url":"u","url":"https://api.github.com/repos/o/r/pulls/11"},"repository":{"full_name":"o/r","private":true,"owner":{"login":"o","type":"Organization"}}}
    ]
    """
    let threads = (try? NotificationThread.list(from: Data(json.utf8))) ?? []
    let prefs = SurfacePreferences.auto
    func surfaces(_ id: String) -> Bool {
        threads.first { $0.id == id }.map { prefs.surfaces($0, selfLogin: "pro-vi") } ?? false
    }
    expect(!surfaces("mnA"), "mention you answered (your comment is latest) → suppressed; a reply re-notifies")
    expect(surfaces("mnO"), "mention with someone else's latest comment still surfaces")
    expect(surfaces("rrA"), "review_requested surfaces even when you commented last — a comment isn't a review")
    if let mnA = threads.first(where: { $0.id == "mnA" }) {
        expectEqual(SignalClassifier.classify(mnA, selfLogin: "pro-vi").actionClass, .fyi,
                    "classify agrees: answered mention drops to fyi (suppressed-set rationale stays honest)")
    }
    expect(surfaces("mnA") == false && SignalClassifier.isOwnLatestComment(threads[0], selfLogin: "PRO-VI"),
           "own-latest compare is case-insensitive")
}

func groups(_ layout: PulsePresenter.LensLayout)
    -> [(owner: String, rows: [String], drafts: [String], quiet: [String])] {
    layout.entries.compactMap { e in
        if case let .group(o, _, r, d, q) = e {
            return (o, r.map { $0.id }, d.map { $0.id }, q.map { $0.id })
        }
        return nil
    }
}

// MARK: - Owner-lens accounting helpers (shared by the owner-lens, draft-tails and quiet suites)
//
// Fold-not-filter: a row is accounted for if it is visible (a group's rows, either of its tails,
// or one of the flat shape's terminal regions) or counted on a ledger line — all three counts,
// both shapes.
//
// GRADES IDENTITIES, NOT A SUM. A cardinality total is invariant under re-homing, so it cannot
// see a row that moved to the wrong owner or landed in two groups at once. `assertFoldNotFilter`
// asserts: no id twice, the visible set == exactly the un-folded rows, and the ledger counts ==
// exactly what the folds hide.
//
// TAKES THE WHOLE `LensLayout`, not an entry array plus hand-passed terminal rows. Under the old
// shape a caller supplied `flatDrafts:` itself, so forgetting it in flat shape made the assertion
// PASS against a lane that had lost every draft. With a second terminal region that hazard
// doubles. Reading both sets off the layout is the same forget-proofing obligation O2 puts on the
// production consumers, applied to their test.

func visibleTailIDs(_ layout: PulsePresenter.LensLayout) -> [String] {
    layout.entries.flatMap { e -> [String] in
        switch e {
        case .rows(let r): return r.map { $0.id }
        case .group(_, _, let r, let d, let q):
            return r.map { $0.id } + d.map { $0.id } + q.map { $0.id }
        case .ledger: return []
        }
    } + layout.terminalDrafts.map { $0.id } + layout.terminalQuiet.map { $0.id }
}
func ledgerCounts(_ layout: PulsePresenter.LensLayout) -> Int {
    layout.entries.reduce(0) { acc, e in
        if case let .ledger(_, _, c, d, q, _) = e { return acc + c + d + q }
        return acc
    }
}
/// The whole invariant in one call: every input row lands exactly once, and the ledger
/// counts stand for precisely the rows the folds hide.
func assertFoldNotFilter(_ layout: PulsePresenter.LensLayout, all: [PulseRow],
                         prefs: LensPreferences, _ label: String) {
    let visible = visibleTailIDs(layout)
    let expectedVisible = all.filter { !prefs.isFolded(PulsePresenter.owner(of: $0)) }.map { $0.id }
    let hidden = all.filter { prefs.isFolded(PulsePresenter.owner(of: $0)) }
    expectEqual(Set(visible).count, visible.count, "\(label): no row is rendered twice")
    expectEqual(Set(visible), Set(expectedVisible), "\(label): visible set == exactly the un-folded rows")
    expectEqual(ledgerCounts(layout), hidden.count, "\(label): ledger counts == exactly what the fold hides")
    expectEqual(visible.count + ledgerCounts(layout), all.count, "\(label): every row lands exactly once")
    // A row can never have two homes — the LensLayout post-condition, asserted directly rather
    // than inferred from the id-uniqueness above (which would also pass if BOTH sets were empty).
    if layout.isGrouped {
        expectEqual(layout.terminalDrafts.count + layout.terminalQuiet.count, 0,
                    "\(label): grouped ⇒ both terminal sets empty")
    }
}

// MARK: - Owner lens (WP 2026-07-14-001 — LensPreferences + ledger-line copy)

suite("LensPreferences — fold set semantics, case-insensitive, denylist default") {
    let d = LensPreferences.default
    expect(!d.groupByOwner, "default shape is the flat list — the lens is opt-in")
    expect(d.foldedOwners.isEmpty, "default folds nothing")
    expect(d.leads("anyone"), "an owner the app has never seen leads by default (denylist)")
    expect(!d.foldsAnything, "default lens hides nothing — the eye has no slash to show")

    let folded = d.togglingFolded("Acme")
    expect(folded.isFolded("acme"), "fold stores lowercased; any casing folds")
    expect(folded.isFolded("ACME"), "…and any casing reads")
    expect(!folded.leads("acme"), "folded ⇒ not leading")
    expect(folded.leads("pro-vi"), "other owners untouched")
    expect(folded.foldsAnything, "a fold flips the eye's slash")

    let roundTrip = folded.togglingFolded("acme")
    expectEqual(roundTrip, d, "toggling twice is identity")

    let grouped = d.togglingGroupByOwner()
    expect(grouped.groupByOwner, "shape toggle flips")
    expectEqual(grouped.foldedOwners, d.foldedOwners, "shape toggle never touches who leads (orthogonal facts)")

    let seeded = LensPreferences(groupByOwner: true, foldedOwners: ["MiXeD"])
    expect(seeded.isFolded("mixed"), "init lowercases seeded owners")

    // Drag order (dogfood 2026-07-14): lowercased, deduped, carried by every toggle.
    let ordered = d.settingOwnerOrder(["Acme", "pro-vi", "acme"])
    expectEqual(ordered.ownerOrder, ["acme", "pro-vi"], "order lowercases + dedupes, first placement wins")
    expectEqual(ordered.togglingGroupByOwner().ownerOrder, ["acme", "pro-vi"], "shape toggle carries the order")
    expectEqual(ordered.togglingFolded("acme").ownerOrder, ["acme", "pro-vi"], "fold toggle carries the order")
}

suite("PulsePresenter — owner lens: grouping, folding, both shapes") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-14T12:00:00Z")!
    func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
    // All settled (created long ago) so active order is the plain worst-first glance —
    // the lens must preserve that order at group granularity, so pin it first.
    func mk(_ repo: String, _ n: Int, _ ci: CIState, updatedHoursAgo: Double) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: at(hoursAgo: 200), updatedAt: at(hoursAgo: updatedHoursAgo),
                         ci: ci, review: ReviewState.none, merge: .mergeable)
    }
    let pulses = [
        mk("acme/core", 631, .failing, updatedHoursAgo: 3),    // blocked → leads
        mk("pro-vi/githud", 214, .passing, updatedHoursAgo: 3),     // ready
        mk("acme/core", 620, .passing, updatedHoursAgo: 6),    // ready, older
        mk("helios-oss/hx-parse", 88, .passing, updatedHoursAgo: 48), // ready, oldest
        mk("pro-vi/githud", 217, .pending, updatedHoursAgo: 5),     // waiting → last
    ]
    let active = PulsePresenter.sections(for: pulses, now: now).active
    expectEqual(active.map { $0.id },
                ["acme/core#631", "pro-vi/githud#214", "acme/core#620",
                 "helios-oss/hx-parse#88", "pro-vi/githud#217"],
                "fixture active order pinned (worst-first, updated tiebreak)")

    expectEqual(PulsePresenter.lensTitle(owner: "Pro-Vi", selfLogin: "pro-vi"), "yours", "self owner → \"yours\", case-insensitive")
    expectEqual(PulsePresenter.lensTitle(owner: "acme", selfLogin: "pro-vi"), "acme", "other owner keeps its login")
    expectEqual(PulsePresenter.lensTitle(owner: "pro-vi", selfLogin: nil), "pro-vi", "auth in flight → raw login, never a wrong \"yours\"")

    // 3 — grouped, nothing folded: titled groups in lead-row rank order.
    let grouped = PulsePresenter.lensLayout(live: active, drafts: [],
                                            quiet: [],
                                            prefs: LensPreferences(groupByOwner: true),
                                            selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(grouped.entries.count, 3, "three owners → three groups")
    if case let .group(o1, t1, r1, _, _) = grouped.entries[0] {
        expectEqual(o1, "acme", "lead group = owner of the lead row")
        expectEqual(t1, "acme", "org title = login")
        expectEqual(r1.map { $0.id }, ["acme/core#631", "acme/core#620"], "in-group order preserved from active")
    } else { expect(false, "entry 0 should be a group") }
    if case let .group(_, t2, _, _, _) = grouped.entries[1] {
        expectEqual(t2, "yours", "second group ranks by ITS lead row (#214 beat #620? no — group rank is lead-row rank: pro-vi's #214 is rank 2)")
    } else { expect(false, "entry 1 should be a group") }

    // 4 — grouped + fold: the folded owner's ledger sinks below the titled groups.
    let foldX = LensPreferences(groupByOwner: true, foldedOwners: ["acme"])
    let gFold = PulsePresenter.lensLayout(live: active, drafts: [], quiet: [], prefs: foldX, selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(visibleTailIDs(gFold), ["pro-vi/githud#214", "pro-vi/githud#217", "helios-oss/hx-parse#88"],
                "leading groups keep rank order; folded rows gone from the visible run")
    expectEqual(gFold.entries.last, LensEntry.ledger(owner: "acme", title: "acme", count: 2, draftCount: 0, quietCount: 0, fresh: 0),
                "folded owner = one counted ledger line at the foot, zero fresh when never opened")

    // 5 — lone-header guard: grouping on, one leading owner → no titles (flat run), ledgers still print.
    let foldTwo = LensPreferences(groupByOwner: true, foldedOwners: ["acme", "helios-oss"])
    let lone = PulsePresenter.lensLayout(live: active, drafts: [], quiet: [], prefs: foldTwo, selfLogin: "pro-vi", lastOpened: [:])
    if case let .rows(r) = lone.entries[0] {
        expectEqual(r.map { $0.id }, ["pro-vi/githud#214", "pro-vi/githud#217"], "one leading owner → untitled flat run")
    } else { expect(false, "lone leading owner must not wear a title") }
    expectEqual(lone.entries.count, 3, "…followed by two ledger lines (≤2 folded → no merge)")

    // 6 — flat shape + fold: same lens, no titles.
    let flatFold = LensPreferences(groupByOwner: false, foldedOwners: ["acme"])
    let flat = PulsePresenter.lensLayout(live: active, drafts: [], quiet: [], prefs: flatFold, selfLogin: "pro-vi", lastOpened: [:])
    if case let .rows(r) = flat.entries[0] {
        expectEqual(r.map { $0.id }, ["pro-vi/githud#214", "helios-oss/hx-parse#88", "pro-vi/githud#217"],
                    "flat leading rows keep original active order")
    } else { expect(false, "flat shape leads with a rows run") }

    // 7 — THE RATIFIED AMENDMENT, executable: the shape toggle changes shape, never visibility.
    expectEqual(Set(visibleTailIDs(gFold)), Set(visibleTailIDs(flat)), "grouped vs flat: identical visible row set")
    expectEqual(gFold.entries.last, flat.entries.last, "…and the identical ledger line")

    // 8 — FOLD, NOT FILTER, executable: every row lands exactly once, both shapes. Uses the
    // SAME identity-grading assertion as the draft-tails suite — this loop used to add up
    // cardinalities, which a re-homing mutation walks straight through (see assertFoldNotFilter).
    for (name, entries, prefs) in [("grouped", gFold, foldX), ("flat", flat, flatFold),
                                   ("lone", lone, foldTwo), ("all-titled", grouped, LensPreferences(groupByOwner: true))] {
        assertFoldNotFilter(entries, all: active, prefs: prefs, name)
    }

    // 9 — the tail valve: >2 folded owners merge into one "elsewhere" line.
    let foldAll = LensPreferences(groupByOwner: true, foldedOwners: ["acme", "helios-oss", "pro-vi"])
    let merged = PulsePresenter.lensLayout(live: active, drafts: [], quiet: [], prefs: foldAll, selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(merged.entries.count, 1, "all folded → ledgers only")
    expectEqual(merged.entries[0], LensEntry.ledger(owner: nil, title: "elsewhere", count: 5, draftCount: 0, quietCount: 0, fresh: 0),
                "three folded owners merge: nil owner routes the click to the card")

    // 10 — fresh counts: activity since THIS machine last opened the group.
    let opened = ["acme": now.addingTimeInterval(-4 * 3_600)]   // opened 4h ago
    let freshed = PulsePresenter.lensLayout(live: active, drafts: [], quiet: [], prefs: foldX, selfLogin: "pro-vi", lastOpened: opened)
    expectEqual(freshed.entries.last, LensEntry.ledger(owner: "acme", title: "acme", count: 2, draftCount: 0, quietCount: 0, fresh: 1),
                "#631 (3h) is newer than last-opened (4h); #620 (6h) is not → fresh 1")

    // 11 — empty active → empty layout (the lane's emptiness rules stay upstream).
    expect(PulsePresenter.lensLayout(live: [], drafts: [], quiet: [], prefs: foldX,
                                     selfLogin: nil, lastOpened: [:]).entries.isEmpty,
           "no active rows → no entries")

    // 11b — drag order (dogfood 2026-07-14): placed owners lead in THEIR order; unplaced
    // fall back to lead-row rank after them; ledger lines follow the same rule.
    let dragged = PulsePresenter.lensLayout(
        live: active, drafts: [],
        quiet: [],
        prefs: LensPreferences(groupByOwner: true, ownerOrder: ["helios-oss"]),
        selfLogin: "pro-vi", lastOpened: [:])
    if case let .group(o, _, _, _, _) = dragged.entries[0] {
        expectEqual(o, "helios-oss", "placed owner leads regardless of lead-row rank")
    } else { expect(false, "entry 0 should be a group") }
    if case let .group(o, _, _, _, _) = dragged.entries[1] {
        expectEqual(o, "acme", "unplaced owners follow in lead-row order")
    } else { expect(false, "entry 1 should be a group") }
    let draggedFold = PulsePresenter.lensLayout(
        live: active, drafts: [],
        quiet: [],
        prefs: LensPreferences(groupByOwner: true,
                               foldedOwners: ["acme", "pro-vi"],
                               ownerOrder: ["pro-vi", "acme"]),
        selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(draggedFold.entries.suffix(2).compactMap { entry -> String? in
        if case let .ledger(o, _, _, _, _, _) = entry { return o } ; return nil
    }, ["pro-vi", "acme"], "ledger lines follow the drag order too")

    // 12 — elided subtitle for rows under a title.
    let base = PulsePresenter.displaySubtitle(for: active[0], now: now)
    let elided = PulsePresenter.displaySubtitle(for: active[0], now: now, elideOwner: true)
    expect(base.hasPrefix("acme/core #631 · "), "base subtitle leads with owner/repo")
    expect(elided.hasPrefix("core #631 · "), "elided subtitle drops the owner the title carries")
    expectEqual(PulsePresenter.displaySubtitle(for: active[0], now: now, elideOwner: false), base,
                "elideOwner: false is the base form")
}

// MARK: - Per-org draft tails (WP 2026-07-26-001 — the lens takes drafts)

suite("PulsePresenter — draft tails: per-owner WIP, positional, never in the group's sort") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-26T12:00:00Z")!
    func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
    func mk(_ repo: String, _ n: Int, _ ci: CIState, draft: Bool = false,
            merge: MergeState = .mergeable, updatedHoursAgo: Double = 3) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                         createdAt: at(hoursAgo: 500), updatedAt: at(hoursAgo: updatedHoursAgo),
                         ci: ci, review: ReviewState.none, merge: merge)
    }
    // The author's real lane shape on the day this was ratified: two owners with live work,
    // one owner (facebook) present ONLY in drafts.
    let pulses = [
        mk("acme/core", 736, .passing, merge: .conflicting, updatedHoursAgo: 1),  // blocked
        mk("acme/core", 414, .passing, updatedHoursAgo: 48),                      // ready
        mk("pro-vi/githud", 214, .passing, updatedHoursAgo: 6),                        // ready
        mk("acme/core", 720, .failing, draft: true, updatedHoursAgo: 72),         // draft, BLOCKED
        mk("acme/core", 721, .passing, draft: true, updatedHoursAgo: 73),         // draft
        mk("pro-vi/toolkit", 69, .passing, draft: true, merge: .conflicting, updatedHoursAgo: 144),
        mk("facebook/lexical", 8710, .passing, draft: true, merge: .conflicting, updatedHoursAgo: 900),
    ]
    let s = PulsePresenter.sections(for: pulses, now: now)
    let live = s.active, drafts = s.drafts
    expectEqual(live.map { $0.id }, ["acme/core#736", "pro-vi/githud#214", "acme/core#414"],
                "fixture live order pinned (blocked first, then ready by recency)")
    expectEqual(drafts.count, 4, "four drafts across three owners")

    let grouped = LensPreferences(groupByOwner: true)

    // 1 — happy path: every group ends with its OWN drafts, and only its own.
    let g = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: grouped,
                                      selfLogin: "pro-vi", lastOpened: [:])
    let gs = groups(g)
    expectEqual(gs.map { $0.owner }, ["acme", "pro-vi", "facebook"],
                "live owners in lead-row rank, then the draft-only owner")
    expectEqual(gs[0].rows, ["acme/core#736", "acme/core#414"], "acme's live rows, in order")
    expectEqual(gs[0].drafts, ["acme/core#720", "acme/core#721"], "…then only acme's drafts")
    expectEqual(gs[1].drafts, ["pro-vi/toolkit#69"], "pro-vi's tail holds only pro-vi's draft")
    // 1b — THE TAIL IS PARTITIONED, NEVER SORTED. Feed drafts in an order that DISAGREES with
    // a state sort — #721 (clean) before #720 (blocked, CI failing) — so a tail that re-sorted
    // would swap them. A fixture already in state order cannot tell the two apart.
    let unsortedDrafts = [
        PulsePresenter.row(for: mk("acme/core", 721, .passing, draft: true, updatedHoursAgo: 73), now: now),
        PulsePresenter.row(for: mk("acme/core", 720, .failing, draft: true, updatedHoursAgo: 72), now: now),
    ]
    let unsorted = PulsePresenter.lensLayout(live: live, drafts: unsortedDrafts, quiet: [], prefs: grouped,
                                             selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(groups(unsorted).first(where: { $0.owner == "acme" })?.drafts,
                ["acme/core#721", "acme/core#720"],
                "tail preserves INPUT order — the blocked draft does not float to the tail's head either")

    // 2 — THE INVERSION GUARD (2026-06-18 signal-taxonomy plan, restated at group scope).
    // #720 is a draft with FAILING CI: it rolls up `.blocked`, which outranks every live
    // row. If the tail ever joined the group's state sort it would lead acme's group.
    expectEqual(PulsePresenter.sections(for: pulses, now: now).drafts.first(where: { $0.id == "acme/core#720" })?.state,
                PulseState.blocked, "the fixture's premise: this draft really does roll up blocked")
    expect(gs[0].rows.allSatisfy { !gs[0].drafts.contains($0) }, "tail and rows are disjoint")
    expectEqual(Array(gs[0].rows.suffix(1) + gs[0].drafts.prefix(1)),
                ["acme/core#414", "acme/core#720"],
                "the blocked draft sits AFTER the ready live row — positional, never sorted")

    // 3 — draft-only owners are first-class, and sink below live work when unplaced.
    expectEqual(gs[2].rows, [], "facebook has no live rows…")
    expectEqual(gs[2].drafts, ["facebook/lexical#8710"], "…but still gets a group carrying its draft")
    let placed = PulsePresenter.lensLayout(live: live, drafts: drafts,
                                           quiet: [],
                                           prefs: LensPreferences(groupByOwner: true, ownerOrder: ["facebook"]),
                                           selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(groups(placed).map { $0.owner }, ["facebook", "acme", "pro-vi"],
                "a DRAGGED draft-only owner leads — the user's order outranks the sink rule")

    // 4 — THE GUARD COUNTS OWNERS WITH CONTENT, not owners with LIVE rows (dogfood 2026-07-29).
    // One live owner plus two owners seen only in drafts is THREE owners worth titling. The
    // narrow live-only guard dropped this lane to flat, which silently un-grouped the drafts —
    // the per-org feature switching itself off exactly when the user reached for the lens.
    let oneLiveOwner = live.filter { PulsePresenter.owner(of: $0) == "acme" }
    let shape = PulsePresenter.lensLayout(live: oneLiveOwner, drafts: drafts, quiet: [], prefs: grouped,
                                          selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(groups(shape).map { $0.owner }, ["acme", "pro-vi", "facebook"],
                "one live owner + two draft-only owners → GROUPED: every owner with content gets a title")
    expectEqual(groups(shape).first { $0.owner == "pro-vi" }?.rows, [],
                "…and an owner whose only content is drafts gets a group with no live rows")

    // 5 — drafts: [] reproduces the PRE-WP layout, asserted against an EXPLICIT expected
    // structure (comparing two calls of a pure function is a tautology, not a test).
    let noDrafts = PulsePresenter.lensLayout(live: live, drafts: [], quiet: [], prefs: grouped,
                                             selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(noDrafts.entries, [
        LensEntry.group(owner: "acme", title: "acme",
                        rows: live.filter { PulsePresenter.owner(of: $0) == "acme" },
                        drafts: [], quiet: []),
        LensEntry.group(owner: "pro-vi", title: "yours",
                        rows: live.filter { PulsePresenter.owner(of: $0) == "pro-vi" },
                        drafts: [], quiet: []),
    ], "drafts: [] → exactly the pre-WP entries: every live owner, in rank order, every tail empty")
    expect(!noDrafts.entries.contains { if case let .group(o, _, _, _, _) = $0 { return o == "facebook" }; return false },
           "…and the draft-only owner is absent entirely, not present-with-an-empty-group")

    // 6 — a fold hides the owner's DRAFTS too, and its ledger admits both counts.
    let foldX = LensPreferences(groupByOwner: true, foldedOwners: ["acme"])
    let folded = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: foldX,
                                           selfLogin: "pro-vi", lastOpened: [:])
    expect(!groups(folded).contains { $0.owner == "acme" }, "folded owner gets no group…")
    expectEqual(folded.entries.last, LensEntry.ledger(owner: "acme", title: "acme",
                                              count: 2, draftCount: 2, quietCount: 0, fresh: 0),
                "…its ledger line carries live AND draft counts (fold, not filter)")

    // 7 — a draft-only owner folded: zero live, its drafts still counted.
    let foldFB = LensPreferences(groupByOwner: true, foldedOwners: ["facebook"])
    let fbFolded = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: foldFB,
                                             selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(fbFolded.entries.last, LensEntry.ledger(owner: "facebook", title: "facebook",
                                                count: 0, draftCount: 1, quietCount: 0, fresh: 0),
                "zero-live owner still prints an honest ledger line")

    // 8 — FOLD, NOT FILTER, extended: every live+draft row lands exactly once, both shapes.
    let flatPrefs = LensPreferences(groupByOwner: false)
    let flat = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: flatPrefs,
                                         selfLogin: "pro-vi", lastOpened: [:])
    let flatFoldPrefs = LensPreferences(groupByOwner: false, foldedOwners: ["acme"])
    let flatFold = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: flatFoldPrefs,
                                             selfLogin: "pro-vi", lastOpened: [:])
    let all = live + drafts
    assertFoldNotFilter(g, all: all, prefs: grouped, "grouped")
    // Folding acme leaves pro-vi (live + drafts) and facebook (drafts) — two owners with
    // content, so the lane STAYS grouped and their drafts keep their org titles. Under the old
    // live-only guard this fell to flat and the drafts went back to one org-blind pile.
    expectEqual(groups(folded).map { $0.owner }, ["pro-vi", "facebook"],
                "folding an owner does not un-group the survivors")
    assertFoldNotFilter(folded, all: all, prefs: foldX, "grouped + fold")
    assertFoldNotFilter(fbFolded, all: all, prefs: foldFB, "grouped + draft-only fold")
    // Flat shape emits no tails — the terminal region carries them, filtered by the fold. The
    // assertion reads that region off the layout, so a flat case cannot pass by forgetting it.
    assertFoldNotFilter(flat, all: all, prefs: flatPrefs, "flat")
    assertFoldNotFilter(flatFold, all: all, prefs: flatFoldPrefs, "flat + fold")

    // 9 — the fold filter on the TERMINAL region, asserted at the boundary that owns it.
    // `leadingRows` is internal now (only `lensLayout` may call it) precisely because a public
    // fold predicate invites a consumer to rebuild the shape rule; the rule is observable here
    // instead, through the value the consumers actually read.
    expectEqual(flat.terminalDrafts.count, 4, "nothing folded → all drafts render terminally")
    expectEqual(flatFold.terminalDrafts.map { $0.id },
                ["pro-vi/toolkit#69", "facebook/lexical#8710"],
                "a folded owner's drafts leave the terminal region")
    let upperFold = PulsePresenter.lensLayout(
        live: live, drafts: drafts, quiet: [],
        prefs: LensPreferences(groupByOwner: false, foldedOwners: ["ACME"]),
        selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(upperFold.terminalDrafts.map { $0.id }, flatFold.terminalDrafts.map { $0.id },
                "…and the fold match is case-insensitive (GitHub's own rule)")

    // 10 — "N new" stays LIVE-only: a draft you opened yourself is not work that arrived.
    // DISCRIMINATING FIXTURE: the drafts are deliberately NEWER than `lastOpened`, so a rule
    // that counted them would report a different number. Drafts older than the clock cannot
    // distinguish the two rules at all.
    let freshDrafts = PulsePresenter.sections(for: pulses + [
        mk("acme/core", 999, .passing, draft: true, updatedHoursAgo: 0.25),   // pushed 15m ago
    ], now: now).drafts
    let opened = ["acme": now.addingTimeInterval(-2 * 3_600)]   // opened 2h ago
    let freshed = PulsePresenter.lensLayout(live: live, drafts: freshDrafts, quiet: [], prefs: foldX,
                                            selfLogin: "pro-vi", lastOpened: opened)
    expectEqual(freshed.entries.last, LensEntry.ledger(owner: "acme", title: "acme",
                                               count: 2, draftCount: 3, quietCount: 0, fresh: 1),
                "#736 (1h live) is the ONLY fresh row — the 15m-old DRAFT must not count, or \"N new\" shouts at your own WIP")

    // 10b — the tail valve carries drafts too: >2 folded owners merge into one "elsewhere"
    // line, and the merged counts must still account for every hidden row.
    let foldAll = LensPreferences(groupByOwner: true, foldedOwners: ["acme", "pro-vi", "facebook"])
    let mergedAll = PulsePresenter.lensLayout(live: live, drafts: drafts, quiet: [], prefs: foldAll,
                                              selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(mergedAll.entries.count, 1, "all folded → one merged ledger line")
    expectEqual(mergedAll.entries[0], LensEntry.ledger(owner: nil, title: "elsewhere",
                                                       count: 3, draftCount: 4, quietCount: 0,
                                                       fresh: 0),
                "the merged line sums every count across every folded owner")
    assertFoldNotFilter(mergedAll, all: all, prefs: foldAll, "elsewhere valve")

    // 10b2 — THE VALVE IS DRAFT-COUPLED, deliberately. `folded` is discovered from live +
    // drafts, so a folded DRAFT-ONLY owner counts toward the ">2 folded → merge" valve. That
    // makes the ledger region's shape depend on `showDrafts`: with drafts hidden the same
    // three folds can render as named lines, and with drafts shown they merge to "elsewhere".
    //
    // This is the valve working as specified — it merges when more than two ledger LINES would
    // render, and a folded draft-only owner really does render one — but it is a coupling
    // invariant 3 does not cover (that invariant is scoped to grouped↔flat, and still holds).
    // Pinned so the behaviour is a decision rather than an accident; see the WP plan's open
    // questions if it reads wrong in dogfood.
    // …and the same three folds with drafts HIDDEN render as two NAMED lines instead, because
    // facebook is then not in the lane at all. Reuses 10b's `foldAll`/`mergedAll` rather than
    // rebuilding an identical prefs value and re-running an identical layout call.
    let withoutDraftOwner = PulsePresenter.lensLayout(live: live, drafts: [], quiet: [], prefs: foldAll,
                                                      selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(withoutDraftOwner.entries.count, 2,
                "drafts hidden: facebook isn't in the lane at all, so two NAMED ledger lines render")

    // 10c — THE SHAPE RULE, carried in the layout rather than rebuilt by each consumer. The
    // island and the key walk both read it from here, so they cannot drift; two hand-written
    // copies would each stay green against their own tests while disagreeing with each other.
    expect(g.isGrouped, "the grouped fixture is grouped")
    expect(!flat.isGrouped, "…and the flat one is not")
    expectEqual(g.terminalDrafts, [],
                "grouped shape tails its groups → no terminal region (never two homes for one row)")
    expectEqual(flat.terminalDrafts.map { $0.id }, drafts.map { $0.id },
                "flat shape → every leading draft renders terminally")

    // 11 — empty in, empty out (the lane's emptiness rules stay upstream).
    expect(PulsePresenter.lensLayout(live: [], drafts: [], quiet: [], prefs: grouped,
                                     selfLogin: nil, lastOpened: [:]).entries.isEmpty,
           "no rows at all → no entries")
    // Drafts-only lane: every owner is draft-only, so all three get a title and a tail. The
    // old live-only guard emitted NOTHING here and pushed the whole lane into the terminal
    // region — a WIP-only morning read as one undifferentiated pile.
    let draftsOnly = PulsePresenter.lensLayout(live: [], drafts: drafts, quiet: [], prefs: grouped,
                                               selfLogin: nil, lastOpened: [:])
    expectEqual(groups(draftsOnly).map { $0.owner }, ["acme", "pro-vi", "facebook"],
                "drafts with no live work → still grouped by owner")
    expect(groups(draftsOnly).allSatisfy { $0.rows.isEmpty && !$0.drafts.isEmpty },
           "…every group is tail-only")
    assertFoldNotFilter(draftsOnly, all: drafts, prefs: grouped, "drafts-only lane")
}

// MARK: - Per-org quiet tails (WP 2026-07-29-001 — the lens takes the last org-blind region)

/// The shared three-region fixture: two owners with live work, one present ONLY in drafts,
/// one present ONLY in quiet. Reused by the layout suite and the key-walk suite so the two
/// cannot drift onto different lanes while both stay green.
struct QuietFixture {
    let now: Date
    let pulses: [PullRequestPulse]
    let live: [PulseRow], drafts: [PulseRow], quiet: [PulseRow]

    init() {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        let now = iso.date(from: "2026-07-29T12:00:00Z")!
        self.now = now
        func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
        func mk(_ repo: String, _ n: Int, _ ci: CIState, draft: Bool = false,
                merge: MergeState = .mergeable, updatedHoursAgo: Double) -> PullRequestPulse {
            PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: draft,
                             createdAt: at(hoursAgo: 4_000), updatedAt: at(hoursAgo: updatedHoursAgo),
                             ci: ci, review: ReviewState.none, merge: merge)
        }
        pulses = [
            // live
            mk("acme/core", 736, .passing, merge: .conflicting, updatedHoursAgo: 1),  // blocked
            mk("acme/core", 414, .passing, updatedHoursAgo: 48),                      // ready
            mk("pro-vi/githud", 214, .passing, updatedHoursAgo: 6),                        // ready
            // drafts
            mk("acme/core", 720, .failing, draft: true, updatedHoursAgo: 72),          // BLOCKED draft
            mk("pro-vi/toolkit", 69, .passing, draft: true, updatedHoursAgo: 144),
            mk("facebook/lexical", 8710, .passing, draft: true, updatedHoursAgo: 900),      // draft-only owner
            // quiet (non-draft, untouched > 14d)
            mk("acme/core", 100, .passing, merge: .conflicting, updatedHoursAgo: 2_688), // BLOCKED, 16 weeks
            mk("pro-vi/githud", 50, .passing, updatedHoursAgo: 720),                          // 30 days
            mk("helios-oss/hx-parse", 88, .passing, updatedHoursAgo: 3_360),                  // quiet-only owner
        ]
        let s = PulsePresenter.sections(for: pulses, now: now)
        live = s.active; drafts = s.drafts; quiet = s.stale
    }
}

suite("PulsePresenter — quiet tails: three regions, two tails, one layout value") {
    let f = QuietFixture()
    let grouped = LensPreferences(groupByOwner: true)

    // 0 — the fixture's premises, pinned. Every later assertion reads against these.
    expectEqual(f.live.map { $0.id }, ["acme/core#736", "pro-vi/githud#214", "acme/core#414"],
                "live order pinned (blocked first, then ready by recency)")
    expectEqual(f.drafts.count, 3, "three drafts across three owners")
    expectEqual(f.quiet.map { $0.id }, ["pro-vi/githud#50", "acme/core#100", "helios-oss/hx-parse#88"],
                "quiet order pinned (most-recently-touched first, the region's own sort)")

    // 1 — HAPPY PATH: every group ends with its own drafts, then its own quiet, and only its own.
    let g = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                      prefs: grouped, selfLogin: "pro-vi", lastOpened: [:])
    let gs = groups(g)
    expectEqual(gs.map { $0.owner }, ["acme", "pro-vi", "facebook", "helios-oss"],
                "live owners by lead-row rank, then the draft-only owner, then the quiet-only owner")
    expectEqual(gs[0].rows, ["acme/core#736", "acme/core#414"], "acme's live rows")
    expectEqual(gs[0].drafts, ["acme/core#720"], "…then only acme's draft")
    expectEqual(gs[0].quiet, ["acme/core#100"], "…then only acme's quiet row")
    expectEqual(gs[1].quiet, ["pro-vi/githud#50"], "pro-vi's quiet tail holds only pro-vi's quiet row")
    expectEqual(gs[2].quiet, [], "the draft-only owner has no quiet tail")

    // 2 — THE INVERSION GUARD, ×2 (2026-06-18 signal taxonomy, now restated for two tails).
    // #720 is a draft with FAILING CI and #100 is a 16-week-old CONFLICTING PR: BOTH roll up
    // `.blocked`, which outranks every live row. If either tail joined the group's state sort it
    // would lead acme's group instead of trailing it.
    expectEqual(f.drafts.first { $0.id == "acme/core#720" }?.state, PulseState.blocked,
                "fixture premise: the draft really does roll up blocked")
    expectEqual(f.quiet.first { $0.id == "acme/core#100" }?.state, PulseState.blocked,
                "fixture premise: the 16-week-old conflicted PR does too")
    expectEqual(gs[0].rows + gs[0].drafts + gs[0].quiet,
                ["acme/core#736", "acme/core#414", "acme/core#720", "acme/core#100"],
                "both blocked tail rows sit AFTER the ready live row — positional, drafts then quiet")

    // 3 — a QUIET-ONLY owner is first-class, and sinks below the draft-only owner when unplaced.
    expectEqual(gs[3].rows, [], "helios-oss has no live rows…")
    expectEqual(gs[3].drafts, [], "…and no drafts…")
    expectEqual(gs[3].quiet, ["helios-oss/hx-parse#88"], "…but still gets a group carrying its quiet row")
    let placedQuiet = PulsePresenter.lensLayout(
        live: f.live, drafts: f.drafts, quiet: f.quiet,
        prefs: LensPreferences(groupByOwner: true, ownerOrder: ["helios-oss"]),
        selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(groups(placedQuiet).map { $0.owner }, ["helios-oss", "acme", "pro-vi", "facebook"],
                "a DRAGGED quiet-only owner leads — the user's order outranks the sink rule")

    // 4 — quiet: [] reproduces the V2 layout exactly, asserted against an EXPLICIT structure
    // (comparing two calls of a pure function is a tautology, not a test).
    let noQuiet = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: [],
                                            prefs: grouped, selfLogin: "pro-vi", lastOpened: [:])
    func rows(_ owner: String, _ region: [PulseRow]) -> [PulseRow] {
        region.filter { PulsePresenter.owner(of: $0) == owner }
    }
    expectEqual(noQuiet.entries, [
        LensEntry.group(owner: "acme", title: "acme", rows: rows("acme", f.live),
                        drafts: rows("acme", f.drafts), quiet: []),
        LensEntry.group(owner: "pro-vi", title: "yours", rows: rows("pro-vi", f.live),
                        drafts: rows("pro-vi", f.drafts), quiet: []),
        LensEntry.group(owner: "facebook", title: "facebook", rows: [],
                        drafts: rows("facebook", f.drafts), quiet: []),
    ], "quiet: [] → exactly the V2 entries; every quiet tail empty and the quiet-only owner absent")

    // 5 — A ROW CAN NEVER HAVE TWO HOMES. The LensLayout post-condition, asserted directly:
    // inferring it from id-uniqueness would also pass if BOTH terminal sets were empty.
    expect(g.isGrouped, "the three-region fixture is grouped")
    expectEqual(g.terminalDrafts, [], "grouped ⇒ no terminal drafts")
    expectEqual(g.terminalQuiet, [], "grouped ⇒ no terminal quiet")
    let flatPrefs = LensPreferences(groupByOwner: false)
    let flat = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                         prefs: flatPrefs, selfLogin: "pro-vi", lastOpened: [:])
    expect(!flat.isGrouped, "…and the flat one is not")
    expectEqual(flat.terminalDrafts.map { $0.id }, f.drafts.map { $0.id },
                "flat ⇒ every leading draft renders terminally, in region order")
    expectEqual(flat.terminalQuiet.map { $0.id }, f.quiet.map { $0.id },
                "flat ⇒ every leading quiet row renders terminally, in region order")

    // 6 — a fold hides BOTH tails, and the ledger line admits all three counts.
    let foldX = LensPreferences(groupByOwner: true, foldedOwners: ["acme"])
    let folded = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                           prefs: foldX, selfLogin: "pro-vi", lastOpened: [:])
    expect(!groups(folded).contains { $0.owner == "acme" }, "folded owner gets no group…")
    expectEqual(folded.entries.last, LensEntry.ledger(owner: "acme", title: "acme",
                                                      count: 2, draftCount: 1, quietCount: 1,
                                                      fresh: 0),
                "…and its ledger line carries live, draft AND quiet counts (fold, not filter)")

    // 7 — a QUIET-ONLY owner folded: zero live, zero drafts, its quiet still counted. This is
    // the reported dogfood defect's core — before this WP its rows kept rendering below the fold.
    let foldHelios = LensPreferences(groupByOwner: true, foldedOwners: ["helios-oss"])
    let heliosFolded = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                                 prefs: foldHelios, selfLogin: "pro-vi",
                                                 lastOpened: [:])
    expectEqual(heliosFolded.entries.last, LensEntry.ledger(owner: "helios-oss", title: "helios-oss",
                                                            count: 0, draftCount: 0, quietCount: 1,
                                                            fresh: 0),
                "a quiet-only owner folds to an honest line — never · 0, never a stray row below")
    expect(!visibleTailIDs(heliosFolded).contains("helios-oss/hx-parse#88"),
           "THE REPORTED BUG: a folded owner's quiet row is nowhere on screen")

    // 8 — "N new" stays LIVE-only over three regions. DISCRIMINATING FIXTURE: last-opened is 20
    // weeks ago, so acme's 16-week-old quiet row IS newer than the clock — a rule that counted
    // quiet would report 3 instead of 2. A recent clock cannot tell the two rules apart at all.
    let longAgo = ["acme": f.now.addingTimeInterval(-20 * 7 * 86_400)]
    let freshed = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                            prefs: foldX, selfLogin: "pro-vi", lastOpened: longAgo)
    expectEqual(freshed.entries.last, LensEntry.ledger(owner: "acme", title: "acme",
                                                       count: 2, draftCount: 1, quietCount: 1,
                                                       fresh: 2),
                "both LIVE rows are newer than a 20-week-old clock; the 16-week QUIET row must not count")

    // 9 — the elsewhere valve sums all three regions across every folded owner.
    let foldAll = LensPreferences(groupByOwner: true,
                                  foldedOwners: ["acme", "pro-vi", "facebook", "helios-oss"])
    let mergedAll = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                              prefs: foldAll, selfLogin: "pro-vi", lastOpened: [:])
    expectEqual(mergedAll.entries, [LensEntry.ledger(owner: nil, title: "elsewhere", count: 3,
                                                     draftCount: 3, quietCount: 3, fresh: 0)],
                "four folded owners merge into one line summing all three regions")

    // 10 — FOLD, NOT FILTER over three regions × both shapes × folded and unfolded. The
    // assertion grades IDENTITIES and reads both terminal sets off the layout, so no case can
    // pass by losing a whole region.
    let all = f.live + f.drafts + f.quiet
    let flatFoldPrefs = LensPreferences(groupByOwner: false, foldedOwners: ["acme"])
    let flatFold = PulsePresenter.lensLayout(live: f.live, drafts: f.drafts, quiet: f.quiet,
                                             prefs: flatFoldPrefs, selfLogin: "pro-vi",
                                             lastOpened: [:])
    for (name, layout, prefs) in [("grouped", g, grouped), ("grouped + fold", folded, foldX),
                                  ("grouped + quiet-only fold", heliosFolded, foldHelios),
                                  ("flat", flat, flatPrefs), ("flat + fold", flatFold, flatFoldPrefs),
                                  ("elsewhere valve", mergedAll, foldAll)] {
        assertFoldNotFilter(layout, all: all, prefs: prefs, name)
    }

    // 11 — a quiet-only LANE: every owner is quiet-only, so all three get a title and a tail.
    let quietOnly = PulsePresenter.lensLayout(live: [], drafts: [], quiet: f.quiet,
                                              prefs: grouped, selfLogin: nil, lastOpened: [:])
    expectEqual(groups(quietOnly).map { $0.owner }, ["pro-vi", "acme", "helios-oss"],
                "quiet with no live work and no WIP → still grouped by owner, in region order")
    expect(groups(quietOnly).allSatisfy { $0.rows.isEmpty && $0.drafts.isEmpty && !$0.quiet.isEmpty },
           "…every group is quiet-tail-only")
    assertFoldNotFilter(quietOnly, all: f.quiet, prefs: grouped, "quiet-only lane")

    // 12 — all three regions empty → nothing, even though quiet is never pref-gated.
    expect(PulsePresenter.lensLayout(live: [], drafts: [], quiet: [], prefs: grouped,
                                     selfLogin: nil, lastOpened: [:]).entries.isEmpty,
           "no rows in any region → no entries")
}

suite("KeySession — the owner lens governs the actionable walk (folded rows leave it)") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-14T12:00:00Z")!
    func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
    func mk(_ repo: String, _ n: Int, _ ci: CIState) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: at(hoursAgo: 200), updatedAt: at(hoursAgo: 3),
                         ci: ci, review: ReviewState.none, merge: .mergeable)
    }
    let pulse = PulsePresenter.rows(for: [mk("acme/core", 631, .failing),
                                          mk("pro-vi/githud", 214, .passing)], now: now)

    let flat = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: false, showStale: false)
    expectEqual(flat, ["acme/core#631", "pro-vi/githud#214"],
                "default lens = identity: pre-lens walk unchanged")

    let folded = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: false, showStale: false,
                                          lens: LensPreferences(groupByOwner: false, foldedOwners: ["acme"]))
    expectEqual(folded, ["pro-vi/githud#214"],
                "a folded owner's rows leave the walk — its ledger line is structure, never a stop")

    let grouped = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: false, showStale: false,
                                           lens: LensPreferences(groupByOwner: true))
    expectEqual(grouped, ["acme/core#631", "pro-vi/githud#214"],
                "grouping alone reorders nothing here — titles are structure, rows all walk")

    // WP 2026-07-26-001 (U5) — draft tails walk with their group. The walk order IS the
    // render order; anything else lands the ink bar on a row that isn't where it looks.
    func mkDraft(_ repo: String, _ n: Int) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: true,
                         createdAt: at(hoursAgo: 200), updatedAt: at(hoursAgo: 3),
                         ci: .passing, review: ReviewState.none, merge: .mergeable)
    }
    let withDrafts = PulsePresenter.rows(for: [mk("acme/core", 631, .failing),
                                               mk("pro-vi/githud", 214, .passing),
                                               mkDraft("acme/core", 720),
                                               mkDraft("pro-vi/githud", 217),
                                               mkDraft("facebook/lexical", 8710)], now: now)

    let tails = KeySession.actionableIDs(radar: [], pulse: withDrafts, showDrafts: true, showStale: false,
                                         lens: LensPreferences(groupByOwner: true))
    expectEqual(tails, ["acme/core#631", "acme/core#720",
                        "pro-vi/githud#214", "pro-vi/githud#217",
                        "facebook/lexical#8710"],
                "each group's tail walks right after its live rows; the draft-only owner walks last")

    // No double-walk: grouped shape must not ALSO append the terminal region.
    expectEqual(Set(tails).count, tails.count, "every id appears exactly once in the walk")

    // A folded owner takes its tail off screen with it — the selection must never land there.
    let foldedTail = KeySession.actionableIDs(radar: [], pulse: withDrafts, showDrafts: true, showStale: false,
                                              lens: LensPreferences(groupByOwner: true, foldedOwners: ["acme"]))
    expect(!foldedTail.contains("acme/core#720"), "a folded owner's DRAFTS leave the walk too")
    expect(!foldedTail.contains("acme/core#631"), "…along with its live rows")
    expectEqual(Set(foldedTail).count, foldedTail.count, "still no duplicates after a fold")

    // showDrafts off → no draft is reachable, in either shape.
    for shape in [true, false] {
        let hidden = KeySession.actionableIDs(radar: [], pulse: withDrafts, showDrafts: false, showStale: false,
                                              lens: LensPreferences(groupByOwner: shape))
        expect(hidden.allSatisfy { !$0.contains("#720") && !$0.contains("#217") && !$0.contains("#8710") },
               "drafts hidden → unreachable (groupByOwner: \(shape))")
    }

    // Flat shape keeps drafts terminal — after live rows, fold-filtered.
    let flatDrafts = KeySession.actionableIDs(radar: [], pulse: withDrafts, showDrafts: true, showStale: false,
                                              lens: LensPreferences(groupByOwner: false))
    expectEqual(flatDrafts, ["acme/core#631", "pro-vi/githud#214",
                             "acme/core#720", "pro-vi/githud#217", "facebook/lexical#8710"],
                "flat shape: every live row, then the terminal draft region")
    let flatFolded = KeySession.actionableIDs(radar: [], pulse: withDrafts, showDrafts: true, showStale: false,
                                              lens: LensPreferences(groupByOwner: false, foldedOwners: ["acme"]))
    expect(!flatFolded.contains("acme/core#720"),
           "flat + fold: the folded owner's terminal drafts leave the walk (leadingRows)")
}

// MARK: - U4: the walk follows the quiet tail (WP 2026-07-29-001)

suite("KeySession — walk order == render order over three regions") {
    let f = QuietFixture()
    let grouped = LensPreferences(groupByOwner: true)
    // `actionableIDs` re-derives the sections from the raw rows, so hand it the fixture's pulses
    // as PRESENTED rows — the same path the island takes.
    let pulse = PulsePresenter.rows(for: f.pulses, now: f.now)

    // 1 — HAPPY PATH, grouped: each group walks rows → drafts → quiet, in that order, and the
    // tail-only owners walk last. This sequence IS the documented render order; the view unit
    // lands after this one deliberately so it matches a contract already pinned.
    let walk = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: true, showStale: true,
                                        lens: grouped)
    expectEqual(walk, ["acme/core#736", "acme/core#414",       // live
                       "acme/core#720",                             // drafts
                       "acme/core#100",                            // quiet
                       "pro-vi/githud#214",
                       "pro-vi/toolkit#69",
                       "pro-vi/githud#50",
                       "facebook/lexical#8710",                          // draft-only owner
                       "helios-oss/hx-parse#88"],                        // quiet-only owner
                "grouped: rows → drafts → quiet per owner, tail-only owners last")
    expectEqual(Set(walk).count, walk.count, "no id appears twice — grouped shape never also walks a terminal set")

    // 2 — A COLLAPSED quiet tail is UNREACHABLE. Its caption is structure, not a row: the same
    // rule that keeps a ledger line out of the walk. Applies in both shapes.
    for shape in [true, false] {
        let hidden = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: true,
                                              showStale: false,
                                              lens: LensPreferences(groupByOwner: shape))
        for quietID in f.quiet.map({ $0.id }) {
            expect(!hidden.contains(quietID),
                   "showStale off → \(quietID) unreachable (groupByOwner: \(shape))")
        }
        expect(hidden.contains("acme/core#720"), "…while drafts stay reachable (groupByOwner: \(shape))")
    }

    // 3 — a fold takes BOTH tails off screen with it, so neither enters the walk.
    let foldX = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: true, showStale: true,
                                         lens: LensPreferences(groupByOwner: true,
                                                               foldedOwners: ["acme"]))
    for gone in ["acme/core#736", "acme/core#720", "acme/core#100"] {
        expect(!foldX.contains(gone), "a folded owner contributes nothing: \(gone)")
    }
    expect(foldX.contains("pro-vi/githud#50"), "…while another owner's quiet tail still walks")

    // 4 — THE REPORTED DEFECT'S KEYBOARD HALF. Before V3 the walk appended `sections.stale`
    // WHOLE, so a folded owner's rotting rows stayed keyboard-reachable while off screen — the
    // selection landing on a row the lane does not draw, which is the one contract the whole key
    // session rests on. Now the quiet ids come from `LensLayout.terminalQuiet`, fold-filtered.
    let flatFold = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: true,
                                            showStale: true,
                                            lens: LensPreferences(groupByOwner: false,
                                                                  foldedOwners: ["helios-oss"]))
    expect(!flatFold.contains("helios-oss/hx-parse#88"),
           "flat + fold: the folded owner's terminal QUIET row leaves the walk too")
    expect(flatFold.contains("pro-vi/githud#50"), "…and the unfolded owners' quiet rows stay")

    // 5 — flat shape: live run, then terminal drafts, then terminal quiet. THE REORDER — drafts
    // before quiet, matching the ratified group order.
    let flat = KeySession.actionableIDs(radar: [], pulse: pulse, showDrafts: true, showStale: true,
                                        lens: LensPreferences(groupByOwner: false))
    expectEqual(flat, f.live.map { $0.id } + f.drafts.map { $0.id } + f.quiet.map { $0.id },
                "flat: live → terminal drafts → terminal quiet")
    expectEqual(Set(flat), Set(walk),
                "the shape toggle changes ORDER, never which rows are reachable")

    // 6 — no id appears twice under ANY pref × shape combination.
    for byOwner in [true, false] {
        for drafts in [true, false] {
            for stale in [true, false] {
                for folds: Set<String> in [[], ["acme"], ["helios-oss"],
                                           ["acme", "pro-vi", "facebook"]] {
                    let ids = KeySession.actionableIDs(
                        radar: [], pulse: pulse, showDrafts: drafts, showStale: stale,
                        lens: LensPreferences(groupByOwner: byOwner, foldedOwners: folds))
                    expectEqual(Set(ids).count, ids.count,
                                "unique ids (byOwner: \(byOwner), drafts: \(drafts), stale: \(stale), folds: \(folds.count))")
                }
            }
        }
    }
}

suite("LensChooser — discovered owners, releasable folds, honest counts") {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let now = iso.date(from: "2026-07-14T12:00:00Z")!
    func at(hoursAgo h: Double) -> String { iso.string(from: now.addingTimeInterval(-h * 3_600)) }
    func mk(_ repo: String, _ n: Int, _ ci: CIState) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: false,
                         createdAt: at(hoursAgo: 200), updatedAt: at(hoursAgo: 3),
                         ci: ci, review: ReviewState.none, merge: .mergeable)
    }
    let active = PulsePresenter.sections(for: [mk("acme/core", 631, .failing),
                                               mk("pro-vi/githud", 214, .passing),
                                               mk("acme/core", 620, .passing)], now: now).active

    let card = LensChooser.make(live: active, drafts: [],
                                quiet: [],
                                prefs: LensPreferences(groupByOwner: true, foldedOwners: ["ghost-org"]),
                                selfLogin: "pro-vi")
    expectEqual(card.owners.map { $0.title }, ["acme", "yours", "ghost-org"],
                "present owners in lead-row order; folded-but-absent owner still listed (releasable)")
    expectEqual(card.owners.map { $0.count }, [2, 1, 0], "counts honest — a folded remnant shows 0")
    expectEqual(card.owners.map { $0.leads }, [true, true, false], "checks mirror the fold set")
    expect(card.groupByOwner, "shape rides along")
    expect(!LensChooser.takesKeyMoment, "no field → never takes key (focus-non-theft)")

    let anonymous = LensChooser.make(live: active, drafts: [], quiet: [], prefs: .default, selfLogin: nil)
    expectEqual(anonymous.owners.map { $0.title }, ["acme", "pro-vi"],
                "auth in flight → raw logins, never a wrong \"yours\"")

    let dragged = LensChooser.make(live: active, drafts: [],
                                   quiet: [],
                                   prefs: LensPreferences(groupByOwner: false, ownerOrder: ["pro-vi"]),
                                   selfLogin: "pro-vi")
    expectEqual(dragged.owners.map { $0.title }, ["yours", "acme"],
                "card rows follow the same drag order as the lane (one rule, four surfaces)")
    expectEqual(dragged.ownersHeader, "Owners:", "card section header")

    // WP 2026-07-26-001 (U3) — "facebook should be there as an org": an owner present only
    // in drafts is a first-class lens owner, listed / foldable / draggable like any other.
    func draft(_ repo: String, _ n: Int) -> PullRequestPulse {
        PullRequestPulse(repo: repo, number: n, title: "PR\(n)", url: "u\(n)", isDraft: true,
                         createdAt: at(hoursAgo: 200), updatedAt: at(hoursAgo: 3),
                         ci: .passing, review: ReviewState.none, merge: .mergeable)
    }
    let drafts = PulsePresenter.sections(for: [draft("facebook/lexical", 8710),
                                               draft("acme/core", 720),
                                               draft("acme/core", 721)], now: now).drafts
    let withDrafts = LensChooser.make(live: active, drafts: drafts,
                                      quiet: [],
                                      prefs: LensPreferences(groupByOwner: true), selfLogin: "pro-vi")
    expectEqual(withDrafts.owners.map { $0.title }, ["acme", "yours", "facebook"],
                "live owners first in lead-row rank; the draft-only owner sinks below them")
    expectEqual(withDrafts.owners.map { $0.count }, [2, 1, 0], "live counts unchanged by drafts")
    expectEqual(withDrafts.owners.map { $0.draftCount }, [2, 0, 1], "draft counts land on the right owners")
    expect(withDrafts.owners.allSatisfy { $0.leads }, "a draft-only owner leads by default, like any other")

    // Dragged up, it genuinely leads — the user's order outranks the sink rule.
    let fbFirst = LensChooser.make(live: active, drafts: drafts,
                                   quiet: [],
                                   prefs: LensPreferences(groupByOwner: true, ownerOrder: ["facebook"]),
                                   selfLogin: "pro-vi")
    expectEqual(fbFirst.owners.map { $0.title }, ["facebook", "acme", "yours"],
                "a placed draft-only owner leads the card, exactly as it leads the lane")

    // Foldable like any other, and the fold survives the drafts being hidden lane-wide:
    // with `showDrafts` off the caller passes [], and the folded-remnant rule keeps the row
    // listed so the fold stays releasable (otherwise facebook would be folded forever with
    // no way to reach it).
    let fbFolded = LensChooser.make(live: active, drafts: drafts,
                                    quiet: [],
                                    prefs: LensPreferences(groupByOwner: true, foldedOwners: ["facebook"]),
                                    selfLogin: "pro-vi")
    expectEqual(fbFolded.owners.first(where: { $0.title == "facebook" })?.leads, false,
                "a draft-only owner folds like any other")
    let hiddenDrafts = LensChooser.make(live: active, drafts: [],
                                        quiet: [],
                                        prefs: LensPreferences(groupByOwner: true, foldedOwners: ["facebook"]),
                                        selfLogin: "pro-vi")
    expect(hiddenDrafts.owners.contains { $0.title == "facebook" },
           "drafts hidden + folded → still listed, so the fold stays releasable")
    expectEqual(hiddenDrafts.owners.first(where: { $0.title == "facebook" })?.draftCount, 0,
                "…with an honest zero (the pref, not the fold, is what hides them)")
    let hiddenUnfolded = LensChooser.make(live: active, drafts: [],
                                          quiet: [],
                                          prefs: LensPreferences(groupByOwner: true), selfLogin: "pro-vi")
    expect(!hiddenUnfolded.owners.contains { $0.title == "facebook" },
           "drafts hidden + not folded → the owner has nothing in the lane, so it isn't listed")

    // The card and the lane agree on owner set AND order — the "four surfaces, one truth"
    // rule, now spanning two regions.
    let laneOwners = PulsePresenter.lensLayout(live: active, drafts: drafts,
                                               quiet: [],
                                               prefs: LensPreferences(groupByOwner: true),
                                               selfLogin: "pro-vi", lastOpened: [:])
        .entries.compactMap { e -> String? in if case let .group(o, _, _, _, _) = e { return o }; return nil }
    expectEqual(laneOwners, withDrafts.owners.map { $0.owner },
                "card row order == lane group order, drafts included")

    // WP 2026-07-29-001 (U2) — the quiet region joins the card on the SAME precedent, and the
    // four-surfaces rule now spans three regions.
    let qf = QuietFixture()
    let threeRegion = LensChooser.make(live: qf.live, drafts: qf.drafts, quiet: qf.quiet,
                                       prefs: LensPreferences(groupByOwner: true), selfLogin: "pro-vi")
    expectEqual(threeRegion.owners.map { $0.title }, ["acme", "yours", "facebook", "helios-oss"],
                "live owners, then the draft-only owner, then the quiet-only owner")
    expectEqual(threeRegion.owners.map { $0.count }, [2, 1, 0, 0], "live counts")
    expectEqual(threeRegion.owners.map { $0.draftCount }, [1, 1, 1, 0], "draft counts")
    expectEqual(threeRegion.owners.map { $0.quietCount }, [1, 1, 0, 1], "quiet counts land on the right owners")
    let quietLane = PulsePresenter.lensLayout(live: qf.live, drafts: qf.drafts, quiet: qf.quiet,
                                              prefs: LensPreferences(groupByOwner: true),
                                              selfLogin: "pro-vi", lastOpened: [:])
        .entries.compactMap { e -> String? in if case let .group(o, _, _, _, _) = e { return o }; return nil }
    expectEqual(quietLane, threeRegion.owners.map { $0.owner },
                "card row order == lane group order across all three regions")

    // …and quiet is NOT pref-gated at the caller, unlike drafts. With `showStale` off the caller
    // still passes the rows (their count survives behind the caption), so a quiet-only owner is
    // listed and foldable either way — the asymmetry that makes fold-not-filter hold.
    let quietFolded = LensChooser.make(live: qf.live, drafts: qf.drafts, quiet: qf.quiet,
                                       prefs: LensPreferences(groupByOwner: true,
                                                              foldedOwners: ["helios-oss"]),
                                       selfLogin: "pro-vi")
    expectEqual(quietFolded.owners.first { $0.title == "helios-oss" }?.leads, false,
                "a quiet-only owner folds like any other")
    expectEqual(quietFolded.owners.first { $0.title == "helios-oss" }?.quietCount, 1,
                "…and its folded row still counts what it hides")
}

suite("PlainWords — owner-lens ledger lines (no verb; fresh clause only when non-zero)") {
    expectEqual(PlainWords.lensLedger("acme", count: 3, fresh: 1), "acme · 3, 1 new", "ledger with fresh")
    expectEqual(PlainWords.lensLedger("acme", count: 3), "acme · 3", "ledger without fresh")
    expectEqual(PlainWords.lensLedger("yours", count: 2, fresh: 0), "yours · 2", "zero fresh omits the clause — never \", 0 new\"")
    expectEqual(PlainWords.lensLedgerSpoken("acme", count: 3, fresh: 1), "acme, 3 folded, 1 new, open", "spoken form with fresh")
    expectEqual(PlainWords.lensLedgerSpoken("yours", count: 2), "yours, 2 folded, open", "spoken form without fresh")
    expectEqual(PlainWords.lensElsewhereLedger(count: 7, fresh: 2), "elsewhere · 7, 2 new", "merged line (>2 folded owners)")
    expectEqual(PlainWords.lensElsewhereLedgerSpoken(count: 7), "elsewhere, 7 folded, open lens", "merged spoken routes to the card")

    // Structural invariant: ratified round 5 REMOVED the verb — a ledger line must never
    // grow a "(show)" suffix (the eye and the card carry the vocabulary now).
    expect(!PlainWords.lensLedger("acme", count: 9, fresh: 3).contains(PlainWords.showVerb), "ledger carries no verb token")
    expect(!PlainWords.lensElsewhereLedger(count: 9).contains(PlainWords.showVerb), "merged line carries no verb token")

    // WP 2026-07-26-001 (U2) — a fold hides the owner's DRAFT tail too, so the line says so.
    expectEqual(PlainWords.lensLedger("acme", count: 4, draftCount: 5),
                "acme · 4, 5 drafts", "folded owner admits live AND draft counts")
    expectEqual(PlainWords.lensLedger("acme", count: 4, draftCount: 5, fresh: 1),
                "acme · 4, 5 drafts, 1 new", "clause order: live · drafts · new")
    expectEqual(PlainWords.lensLedger("pro-vi", count: 3, draftCount: 1),
                "pro-vi · 3, 1 draft", "one draft is singular")
    // The zero-live form: a DRAFT-ONLY owner (facebook, on the author's real lane) has no
    // live count to print — "· 0, 1 draft" would read as broken.
    expectEqual(PlainWords.lensLedger("facebook", count: 0, draftCount: 1),
                "facebook · 1 draft", "zero-live owner: the draft count IS the line's count")
    expectEqual(PlainWords.lensLedger("facebook", count: 0, draftCount: 3),
                "facebook · 3 drafts", "…plural too")
    expect(!PlainWords.lensLedger("facebook", count: 0, draftCount: 1).contains("· 0"),
           "a zero-live owner with drafts never prints \"· 0\"")
    // Honest about the domain: (0, 0) DOES render "x · 0". Unreachable from lensLayout — a
    // ledger is only emitted for an owner discovered from a row, so live+drafts ≥ 1.
    expectEqual(PlainWords.lensLedger("ghost", count: 0, draftCount: 0), "ghost · 0",
                "the (0,0) form is degenerate, not special-cased — callers never construct it")
    // Pre-WP lines stay byte-identical — the clause is empty when there are no drafts.
    expectEqual(PlainWords.lensLedger("acme", count: 3, draftCount: 0, fresh: 1), "acme · 3, 1 new",
                "zero drafts omits the clause — never \", 0 drafts\"")
    expectEqual(PlainWords.lensLedger("yours", count: 2, draftCount: 0), "yours · 2", "…and the bare form is unchanged")
    // Spoken forms mirror, including the zero-live shape.
    expectEqual(PlainWords.lensLedgerSpoken("acme", count: 4, draftCount: 5, fresh: 1),
                "acme, 4 folded and 5 drafts, 1 new, open", "spoken carries both counts")
    expectEqual(PlainWords.lensLedgerSpoken("facebook", count: 0, draftCount: 1),
                "facebook, 1 draft folded, open", "spoken zero-live form")
    expectEqual(PlainWords.lensLedgerSpoken("yours", count: 2, draftCount: 0), "yours, 2 folded, open",
                "spoken pre-WP form unchanged")
    // The merged "elsewhere" valve sums both.
    expectEqual(PlainWords.lensElsewhereLedger(count: 7, draftCount: 2, fresh: 2),
                "elsewhere · 7, 2 drafts, 2 new", "merged line carries the summed drafts")
    expectEqual(PlainWords.lensElsewhereLedgerSpoken(count: 7, draftCount: 2),
                "elsewhere, 7 folded and 2 drafts, open lens", "merged spoken form")
    expectEqual(PlainWords.lensElsewhereLedger(count: 0, draftCount: 4), "elsewhere · 4 drafts",
                "all-draft-only fold merges to the zero-live form")
    // Reachable: >2 folded owners, all draft-only, drafts shown. Its visible twin was pinned
    // above; the spoken form had no test.
    expectEqual(PlainWords.lensElsewhereLedgerSpoken(count: 0, draftCount: 4),
                "elsewhere, 4 drafts folded, open lens", "…and its spoken twin")
    // The Owners-card row: same numbers and plural rule as the ledger (one home), but NO
    // "folded … open" verb — the row is a checkbox whose value carries shown/hidden, and
    // announcing "open" would name an action it does not perform.
    expectEqual(PlainWords.lensCardRowSpoken("acme", count: 4, draftCount: 5),
                "acme, 4, 5 drafts", "card row speaks both counts")
    expectEqual(PlainWords.lensCardRowSpoken("facebook", count: 0, draftCount: 1),
                "facebook, 1 draft", "draft-only owner: no phantom zero, singular noun")
    expectEqual(PlainWords.lensCardRowSpoken("yours", count: 2), "yours, 2", "…and the plain form")
    for spoken in [PlainWords.lensCardRowSpoken("x", count: 1, draftCount: 1),
                   PlainWords.lensCardRowSpoken("x", count: 0, draftCount: 2)] {
        expect(!spoken.contains("folded") && !spoken.contains("open"),
               "a card row never speaks the ledger's verb — it toggles, it doesn't open")
    }
    expect(!PlainWords.lensLedger("x", count: 4, draftCount: 5).contains(PlainWords.showVerb),
           "the drafts clause introduces no verb token either")

    // U4 — the grouped-shape tail label. Quieter than the flat shape's revealed header:
    // the owner title above already named the org, so the tail only says what and how much.
    expectEqual(PlainWords.draftTailLabel(5), "5 drafts", "tail label is countful and lowercase")
    expectEqual(PlainWords.draftTailLabel(1), "1 draft", "…singular at one")
    expect(!PlainWords.draftTailLabel(3).contains(PlainWords.showVerb),
           "no verb — hidden drafts stay fully invisible (the family's no-caption asymmetry)")
    expect(!PlainWords.draftTailLabel(3).contains("(hide)"),
           "…and no hide control either; that affordance lives in the gear")
    expectEqual(PlainWords.draftsHeader, "Draft PRs",
                "the FLAT shape's revealed header is untouched — a flat list has no groups to tail")

    // ── WP 2026-07-29-001 (U2): the quiet clause ────────────────────────────────────────────
    // Clause order is live · drafts · quiet · new, each suppressed at zero.
    expectEqual(PlainWords.lensLedger("acme", count: 4, draftCount: 5,
                                      quietCount: 2, fresh: 1),
                "acme · 4, 5 drafts, 2 gone quiet, 1 new",
                "all four clauses, in ratified order")
    expectEqual(PlainWords.lensLedger("pro-vi", count: 3, quietCount: 1), "pro-vi · 3, 1 gone quiet",
                "quiet alone, no plural inflection at one — the phrase is adjectival")
    // Zero live: the FIRST tail noun carries the line, exactly as the drafts-only form does.
    expectEqual(PlainWords.lensLedger("helios-oss", count: 0, quietCount: 3),
                "helios-oss · 3 gone quiet", "a quiet-only owner reads with the noun as its count")
    expectEqual(PlainWords.lensLedger("x", count: 0, draftCount: 2, quietCount: 3),
                "x · 2 drafts, 3 gone quiet", "zero live with BOTH tails: drafts lead, quiet follows")
    for line in [PlainWords.lensLedger("helios-oss", count: 0, quietCount: 3),
                 PlainWords.lensLedger("x", count: 4, draftCount: 0, quietCount: 2),
                 PlainWords.lensLedger("x", count: 4, draftCount: 2, quietCount: 0)] {
        expect(!line.contains("· 0") && !line.contains(", 0 "),
               "no ledger line ever prints a zero count: \(line)")
    }
    // Every pre-V3 string byte-identical when quietCount is zero (the whole suite above runs
    // without the parameter; these pin the two shapes that gained a branch).
    expectEqual(PlainWords.lensLedger("facebook", count: 0, draftCount: 1, quietCount: 0),
                "facebook · 1 draft", "V2 zero-live form unchanged")
    expectEqual(PlainWords.lensLedger("yours", count: 2, quietCount: 0), "yours · 2",
                "V2 bare form unchanged")
    // Spoken mirrors, joining with "and" where the visible line uses commas — a screen reader
    // reading "3, 2 drafts, 2 gone quiet" hears a list of unrelated numbers.
    expectEqual(PlainWords.lensLedgerSpoken("acme", count: 3, draftCount: 2, quietCount: 2, fresh: 1),
                "acme, 3 folded and 2 drafts and 2 gone quiet, 1 new, open",
                "spoken carries all three counts")
    expectEqual(PlainWords.lensLedgerSpoken("helios-oss", count: 0, quietCount: 3),
                "helios-oss, 3 gone quiet folded, open", "spoken zero-live quiet form")
    expectEqual(PlainWords.lensElsewhereLedger(count: 7, draftCount: 2, quietCount: 4, fresh: 2),
                "elsewhere · 7, 2 drafts, 4 gone quiet, 2 new", "the valve sums all three regions")
    expectEqual(PlainWords.lensElsewhereLedgerSpoken(count: 0, draftCount: 4, quietCount: 1),
                "elsewhere, 4 drafts and 1 gone quiet folded, open lens", "…and its spoken twin")
    // The card row: same nouns, same order, no verb.
    expectEqual(PlainWords.lensCardRowSpoken("acme", count: 4, draftCount: 5, quietCount: 2),
                "acme, 4, 5 drafts, 2 gone quiet", "card row speaks all three counts")
    expectEqual(PlainWords.lensCardRowSpoken("helios-oss", count: 0, quietCount: 3),
                "helios-oss, 3 gone quiet", "quiet-only owner: no phantom zero")
    expect(!PlainWords.lensCardRowSpoken("x", count: 0, quietCount: 2).contains("folded"),
           "a card row still never speaks the ledger's verb")

    // A group's quiet tail: ONE OBJECT, TWO STATES (G1). Same noun, same shape, one token apart —
    // so the pair reads as a thing being toggled rather than two different controls.
    expectEqual(PlainWords.staleCaption(3), "3 gone quiet (show)",
                "the collapsed caption is the ratified string, unchanged")
    expectEqual(PlainWords.staleRevealedCaption(3), "3 gone quiet (hide)",
                "…and revealed, only the verb flips")
    expectEqual(PlainWords.staleCaption(1), "1 gone quiet (show)", "no plural inflection at one…")
    expectEqual(PlainWords.staleRevealedCaption(1), "1 gone quiet (hide)", "…in either state")
    // THE PAIR IS ONE EDIT APART. Asserted as a relation, not as two literals: two independent
    // string literals would drift on the next copy round while both tests stayed green.
    expectEqual(PlainWords.staleCaption(4).replacingOccurrences(of: PlainWords.showVerb,
                                                                with: PlainWords.hideControl),
                PlainWords.staleRevealedCaption(4),
                "the two states differ in the verb token and nothing else")
    expectEqual(PlainWords.staleCaptionSpoken(3), "3 gone quiet, show", "spoken twin, collapsed")
    expectEqual(PlainWords.staleRevealedCaptionSpoken(3), "3 gone quiet, hide", "spoken twin, revealed")
    for spoken in [PlainWords.staleCaptionSpoken(2), PlainWords.staleRevealedCaptionSpoken(2)] {
        expect(!spoken.contains("("), "a spoken caption speaks the verb as a word, never as glyph-parens")
    }
    // The noun phrase has ONE home — a group's tail, the lane's caption and the ledger's clause
    // cannot read differently from each other.
    expect(PlainWords.staleRevealedCaption(3).hasPrefix("3 gone quiet"),
           "revealed caption is built from the same noun phrase")
    expect(PlainWords.lensLedger("x", count: 0, quietCount: 3).contains("3 gone quiet"),
           "the ledger's quiet clause uses it too")

    expectEqual(PlainWords.yoursTitle, "yours", "self group title reads as a word, not a login")
    expectEqual(PlainWords.lensGearItem, "Lens…", "gear parent item")
    expectEqual(PlainWords.lensOwnersHeader, "Owners:", "card/submenu section header (dogfood: was \"Lead with:\")")
    expectEqual(PlainWords.lensBackControl, "(back)", "the card's way back to the island")
    expectEqual(PlainWords.lensBackSpoken, "back", "back control VO")
    expectEqual(PlainWords.groupByOwnerItem, "Group by owner", "shape toggle title")
    expectEqual(PlainWords.groupByOwnerTooltip, "off keeps the one list, as before", "shape toggle tooltip")
    expectEqual(PlainWords.lensEyeLabel(foldedCount: 0), "Lens", "eye label, nothing folded")
    expectEqual(PlainWords.lensEyeLabel(foldedCount: 2), "Lens — 2 folded", "eye label carries the folded count")
}

// MARK: - Settings card (mark-and-settings option B, dogfood-ratified 2026-07-14)

suite("SettingsCard — one descriptor holds what the dropdown held") {
    let card = SettingsCard.make(
        surface: .auto,
        pulse: PulsePreferences(showDrafts: true, showStale: false),
        inbound: InboundPreferences(showHeldBack: true),
        themeID: .github,
        launchAtLogin: true)

    expectEqual(card.title, "Settings", "card title")
    expectEqual(card.themes.count, ThemeID.all.count, "one chip per theme")
    expectEqual(card.themes.filter { $0.selected }.map { $0.id }, [ThemeID.github.rawValue],
                "exactly the current theme is selected")
    expectEqual(card.reasons.count, SurfacePreferences.allReasons.count + 1,
                "one row per H1 reason + the just-cleared receipts row (land-triage F5)")
    expectEqual(card.reasons.last?.id, "justCleared", "the receipts row rides the radar section, sentinel id")
    expect(card.reasons.last?.on == false, "…mirroring the (default-off) reveal pref")
    expect(card.reasons.dropLast().allSatisfy { $0.on == SurfacePreferences.auto.isEnabled($0.id) },
           "reason checks mirror the pref set")
    expectEqual(card.pulseItems.map { $0.id }, ["drafts", "stale"], "Your PRs rows")
    expectEqual(card.pulseItems.map { $0.on }, [true, false], "…with live check state")
    expectEqual(card.inboundItems.map { $0.on }, [true], "held-back row mirrors the pref")
    expect(card.launchAtLogin.on, "launch-at-login carries the live SMAppService read")
    expectEqual(card.pillStyleDoor, "Pill style…", "door into the pill-style card")
    expectEqual(card.lensDoor, "Lens…", "door into the lens card")
    expect(!SettingsCard.takesKeyMoment, "no field → never takes key")

    expectEqual(PlainWords.settingsMenuItem, "Settings…", "the verbs-only menu's one door")
    expectEqual(PlainWords.settingsGearTooltip, "Settings", "gear tooltip")
}

// MARK: - Report

print("")
if failures == 0 {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures)/\(checks) checks failed")
    exit(1)
}
