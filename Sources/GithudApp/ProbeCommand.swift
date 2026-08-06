import Foundation
import GithudCore

/// `githud probe` — a one-shot, headless exercise of the live data spine via the
/// shared `RadarPipeline` (Keychain/GITHUD_PAT → fetch → enrich → self-demote →
/// radar + suppressed). Prints REDACTED aggregates by default (safe for transcripts
/// + committed evidence). `--show-items` / `--show-suppressed` additionally print the
/// real radar / hidden set for the operator's own eyes (never run automatically).
enum ProbeCommand {
    /// Entry point. The probe body runs on a background queue so RadarPipeline's
    /// off-main precondition (unconditional since WP-1a's stitch) holds for BOTH its
    /// callers. Blocking the startup main thread on the semaphore is safe: there is no
    /// main run loop yet, and every completion fires on URLSession's own queue (see the
    /// deadlock-safety note in RadarPipeline) — never on main.
    static func run(showItems: Bool, showSuppressed: Bool = false, showPulse: Bool = false) -> Int32 {
        var exitCode: Int32 = 1
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            exitCode = runOffMain(showItems: showItems, showSuppressed: showSuppressed, showPulse: showPulse)
            semaphore.signal()
        }
        semaphore.wait()
        return exitCode
    }

    private static func runOffMain(showItems: Bool, showSuppressed: Bool, showPulse: Bool) -> Int32 {
        // Token: GITHUD_PAT (headless) else Keychain. An ad-hoc binary blocks on the
        // Keychain GUI prompt headless, so the loop's probe uses GITHUD_PAT.
        let token: String
        if let envToken = ProcessInfo.processInfo.environment["GITHUD_PAT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            print("▸ token from GITHUD_PAT (headless path — via the authorized `security` CLI)")
            token = envToken
        } else {
            switch KeychainPAT.read() {
            case .success(let value): token = value
            case .failure(let error):
                err("keychain read failed: \(error) (service \(KeychainPAT.service)/\(KeychainPAT.account)). Headless? pass GITHUD_PAT.")
                return 2
            }
        }
        guard KeychainPAT.looksLikeClassicPAT(token) else {
            err("not a classic PAT: \(KeychainPAT.redacted(token)) — the Notifications API needs ghp_…")
            return 2
        }
        print("▸ token \(KeychainPAT.redacted(token)) — classic PAT ✓")

        let pipeline = RadarPipeline(client: GitHubClient(token: token))
        let first = pipeline.refresh()
        guard case .success(let r) = first else {
            if case .failure(let error) = first { err("GET /notifications failed: \(error)") }
            return 1
        }

        print("▸ self: \(pipeline.currentSelfLogin.map { "@\($0)" } ?? "unknown (GET /user failed)")")
        print("▸ GET /notifications → 200  threads=\(r.threadCount)  action_required(pre-enrich)=\(r.radarPreEnrich.count)")
        print("  scopes=\(r.scopes ?? "?")  poll_interval=\(r.nextPollAfter)s  rate_remaining=\(r.rateRemaining.map(String.init) ?? "?")")
        print("  reason histogram: \(formatHistogram(r.reasonHistogram))")
        print("▸ enrichment: enriched=\(r.enriched) skipped_private_no_repo_scope=\(r.skippedPrivate); action_required \(r.radarPreEnrich.count) → \(r.radar.count) (demoted \(r.demotedByEnrichment) bot/self)")
        let stateHist = Dictionary(grouping: r.resolvedThreads, by: { $0.subjectState?.rawValue ?? "?" }).mapValues { $0.count }
        print("▸ subject-state: enriched \(r.subjectStateEnriched) (PR/Issue merged/closed/open) — \(formatHistogram(stateHist)); resolved (merged/closed) drop off the radar")
        if r.skippedPrivate > 0 && !r.hasRepoScope {
            print("  ⓘ \(r.skippedPrivate) private-repo threads not enriched — PAT lacks the `repo` scope.")
        }
        // policy-b cost meter (redacted): radar items that are AUTOMATION — i.e. a bot's
        // direct @you mention, surfaced because policy-b never bot-demotes a direct mention.
        let botOnRadar = r.radar.filter { SignalClassifier.isLikelyAutomated($0.thread) }.count
        print("  ⓘ policy-b cost: \(botOnRadar) of \(r.radar.count) radar items are automation (bot direct-@you mentions). Allow-list would re-demote these.")
        if showItems {
            print("  — radar (action-required, urgency-ranked) —")
            // Both dumps print the EFFECTIVE reason (review round 1): the audit
            // instrument must speak the taxonomy the HUD renders — an inbound row
            // prints `inbound`, never the raw `subscribed` it derived from. (The
            // histogram above stays raw deliberately: it describes the API response.)
            for item in r.radar {
                let t = item.thread
                let bot = SignalClassifier.isLikelyAutomated(t) ? "   ⚠ BOT (policy-b)" : ""
                print("   [\(item.classification.urgency)] \(t.repository.fullName) · \(t.subject.type) · \(item.effectiveReason) · \(t.subject.title)\(bot)")
            }
        }
        // Reviews-owed standing sweep (WP 2026-07-17-002): the search truth the unread-only
        // inbox structurally can't carry (read notification + review still owed). The owed
        // list must match github.com/pulls/review-requested — the WP's kill condition.
        let owed = pipeline.currentReviewsOwed
        let syntheticOnRadar = r.radar.filter { $0.thread.id.hasPrefix("review-owed:") }.count
        print("▸ reviews owed (standing search): \(owed.count) — sweep \(r.reviewsComplete ? "complete ✓ (feeds the affirmation gate)" : "INCOMPLETE ✗ (affirmation stays closed)"); \(syntheticOnRadar) synthetic on radar (rest carried by real threads)")
        if showItems {
            for item in owed {
                print("   [owed] \(item.repo)#\(item.number) · by @\(item.authorLogin) · \(item.title)")
            }
        }
        print("▸ suppressed: \(r.suppressed.count) hidden — `--show-suppressed` to AUDIT for misses (false negatives kill trust)")
        if showSuppressed {
            print("  — suppressed (most-likely-miss first; is any of these something you actually need?) —")
            for item in r.suppressed.prefix(25) {
                let t = item.thread
                print("   [\(item.classification.actionClass.rawValue)] \(t.repository.fullName) · \(item.effectiveReason) · \(t.subject.title)")
            }
        }

        // H2 pulse — open-PR CI/review/merge state via GraphQL. Redacted by default
        // (state histogram only; no titles/repos). The live-verification gate for H2.
        var pulseHistogram: [String: Int] = [:]
        var pulseCount = -1
        var pulseDrafts = 0
        var pulseLensShape = "unknown"
        var pulseOwnerSplit: [(owner: String, live: Int, drafts: Int, quiet: Int)] = []
        switch pipeline.fetchPulse() {
        case .success(let pulses):
            let now = Date()
            let sections = PulsePresenter.sections(for: pulses, now: now)
            pulseCount = pulses.count
            pulseDrafts = pulses.filter { $0.isDraft }.count
            for p in pulses { pulseHistogram[p.state.rawValue, default: 0] += 1 }
            let staleCount = sections.stale.count
            let freshCount = sections.active.filter { $0.isFresh }.count
            print("▸ pulse (H2): \(pulses.count) open PRs — \(formatHistogram(pulseHistogram))")
            print("  split: \(sections.active.count) active (\(freshCount) just-raised) · \(staleCount) stale (untouched 14d+) · \(pulseDrafts) draft — stale+draft hidden by default")
            // Per-owner lens split (WP 2026-07-26-001, three-way since 2026-07-29-001) — the
            // diffable form of what the lane draws, so a dogfood run can be checked against `gh`
            // truth without opening the panel and squinting at a tail.
            //
            // The prefs are the MACHINE'S OWN (LensStore/PulseStore), not a hardcoded shape:
            // this line claims to report what the island draws, and hardcoding
            // `groupByOwner: true` would make that claim false on a flat-shape desk. For the same
            // reason `quiet` is `sections.stale` and NOT `[]`: a quiet-only owner counts toward
            // the lone-header guard, so passing an empty third region would report "flat" on a
            // desk the island actually draws grouped.
            let probeLens = LensStore.load()
            let regions = sections.lensRegions(showDrafts: PulseStore.load().showDrafts)
            let lensLayout = PulsePresenter.lensLayout(
                live: regions.live, drafts: regions.drafts, quiet: sections.stale,
                prefs: probeLens, selfLogin: pipeline.currentSelfLogin, lastOpened: [:])
            // Partition from the SOURCE ROWS, not from the entries: flat shape emits `.rows`
            // rather than `.group`, so reading groups alone reports an empty split on exactly
            // the desks that have no owner titles — a silent "no owners" that looks like data
            // rather than like a shape. Pref-independent on purpose: this is the ground truth
            // to diff against `gh`, while `lens_shape` above says how it gets drawn.
            pulseLensShape = lensLayout.isGrouped ? "grouped" : "flat"
            pulseOwnerSplit = PulsePresenter.ownerBuckets(live: sections.active,
                                                          drafts: sections.drafts,
                                                          quiet: sections.stale)
                .map { (owner: $0.key, live: $0.live.count, drafts: $0.drafts.count,
                        quiet: $0.quiet.count) }
            // Owner LOGINS are an identity, and this probe is redacted by default (the same
            // reason titles/repos sit behind --show-items): an org name can be a private
            // employer. Default prints the SHAPE — how many owners, split how — and names
            // appear only under the flag the operator opted into.
            let ownerList = pulseOwnerSplit.isEmpty ? "(none)" : pulseOwnerSplit
                .map { showItems ? "\($0.owner) \($0.live)+\($0.drafts)d+\($0.quiet)q"
                                 : "\($0.live)+\($0.drafts)d+\($0.quiet)q" }
                .joined(separator: " · ")
            print("  lens: \(pulseLensShape) shape · \(pulseOwnerSplit.count) owner(s) — \(ownerList) [live+drafts+quiet per owner\(showItems ? "" : "; --show-items for names")]")
            if showPulse {
                func dump(_ label: String, _ rows: [PulseRow]) {
                    guard !rows.isEmpty else { return }
                    print("  — \(label) —")
                    for row in rows {
                        print("   \(row.isFresh ? "✦" : " ")[\(row.state.rawValue)] \(row.title) — \(PulsePresenter.displaySubtitle(for: row, now: now))")
                    }
                }
                // Dumps THE REGIONS, never the lens layout: this output's contract is
                // completeness ("did a row go missing"), and the lens is a view whose job is
                // hiding — it folds owners into ledger lines and its drafts are pref-gated, so
                // an audit derived from it inherits every bit of that. Regions are complete in
                // every shape and under every pref. Owner attribution survives the flat dump:
                // `displaySubtitle` prints `owner/repo #N` per row, and `lens:` carries the split.
                dump("Your PRs (active — ✦ = just-raised)", sections.active)
                dump("Drafts (per-owner tails in the lane; flat here — this is the audit)",
                     sections.drafts)
                dump("Gone quiet (untouched 14d+; per-owner tails in the lane, flat here)",
                     sections.stale)
            }
        case .failure(let error):
            print("▸ pulse (H2): fetch failed (\(error)) — non-fatal (the lane keeps its last good state)")
        }

        // Conditional re-poll to demonstrate 304 discipline (RUBRIC #8).
        var secondStatus = -1
        var secondNotModified = false
        if case .success(let r2) = pipeline.refresh() {
            secondNotModified = r2.notModified
            secondStatus = r2.notModified ? 304 : 200
            print("▸ conditional re-GET (If-None-Match/If-Modified-Since) → \(secondStatus)\(secondNotModified ? " Not Modified ✓ (no primary-rate cost)" : "")")
        }

        let evidence = redactedEvidence(result: r, secondStatus: secondStatus,
                                        secondNotModified: secondNotModified,
                                        pulseCount: pulseCount, pulseDrafts: pulseDrafts,
                                        pulseHistogram: pulseHistogram,
                                        pulseLensShape: pulseLensShape, pulseOwnerSplit: pulseOwnerSplit,
                                        radarAutomation: botOnRadar, reviewsOwed: owed.count,
                                        reviewsSynthetic: syntheticOnRadar)
        print("EVIDENCE_JSON: \(evidence)")
        return 0
    }

    // MARK: - helpers

    private static func err(_ message: String) {
        FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    }

    private static func formatHistogram(_ histogram: [String: Int]) -> String {
        histogram.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// Redacted evidence — counts + reasons + headers only. No titles/repos/logins/ids.
    /// The H2 pulse is summarized as a state histogram (blocked/ready/waiting/draft
    /// counts) — never PR titles or repo names. The token's raw `oauth_scopes` string is
    /// NOT emitted (review): a committed artifact shouldn't disclose the token's granted
    /// capabilities — the `has_repo_scope` boolean carries all the radar logic needs.
    private static func redactedEvidence(result r: RadarPipeline.Result, secondStatus: Int, secondNotModified: Bool,
                                         pulseCount: Int, pulseDrafts: Int, pulseHistogram: [String: Int],
                                         pulseLensShape: String,
                                         pulseOwnerSplit: [(owner: String, live: Int, drafts: Int, quiet: Int)],
                                         radarAutomation: Int, reviewsOwed: Int, reviewsSynthetic: Int) -> String {
        let histJSON = "{" + r.reasonHistogram.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        let pulseJSON = "{" + pulseHistogram.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        // Per-owner live/draft/quiet split (WP 2026-07-26-001, 2026-07-29-001): the diffable form
        // of what the lane draws. ANONYMOUS BY POSITION — this function's contract is "no titles/repos/logins/
        // ids" and these payloads get committed as evidence, so an owner login (which can be a
        // private employer's org) must never reach it. The lane-ordered index carries every
        // property the evidence needs — how many owners, how the live/draft counts split, and
        // whether that changed between runs — without naming anyone. The operator reads names
        // from the human line under --show-items.
        let ownerSplitJSON = "[" + pulseOwnerSplit.enumerated().map {
            "{\"index\":\($0.offset),\"live\":\($0.element.live),\"drafts\":\($0.element.drafts),\"quiet\":\($0.element.quiet)}"
        }.joined(separator: ",") + "]"
        let rate = r.rateRemaining.map(String.init) ?? "null"
        return "{\"probe\":\"notifications\",\"first\":{\"status\":200,\"thread_count\":\(r.threadCount),\"action_required_post_enrich\":\(r.radar.count),\"action_required_pre_enrich\":\(r.radarPreEnrich.count),\"radar_automation_policy_b\":\(radarAutomation),\"suppressed\":\(r.suppressed.count),\"enriched\":\(r.enriched),\"demoted_by_enrichment\":\(r.demotedByEnrichment),\"skipped_private_no_repo_scope\":\(r.skippedPrivate),\"has_repo_scope\":\(r.hasRepoScope),\"reason_histogram\":\(histJSON),\"poll_interval\":\(r.nextPollAfter),\"rate_remaining\":\(rate)},\"second\":{\"status\":\(secondStatus),\"not_modified\":\(secondNotModified)},\"conditional_polling_proven\":\(secondNotModified),\"pulse\":{\"open_prs\":\(pulseCount),\"drafts\":\(pulseDrafts),\"state_histogram\":\(pulseJSON),\"lens_shape\":\"\(pulseLensShape)\",\"owner_split\":\(ownerSplitJSON)},\"reviews\":{\"owed\":\(reviewsOwed),\"complete\":\(r.reviewsComplete),\"synthetic_on_radar\":\(reviewsSynthetic)}}"
    }
}
