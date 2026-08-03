import Foundation

/// How much to trust what the island is currently showing — the "is this reading even
/// CURRENT?" question, distinct from "is the data honest?" (the per-PR/per-thread
/// contract). A poll that silently fails or stalls leaves the last-good radar/pulse on
/// screen; showing that as if it were live is the same faked-liveness trap a missed
/// mention or a false-green PR is. This value drives the ONE sanctioned `caution` use
/// in the color doctrine (consult 008): degraded *reading* confidence.
///
/// `normal operation is quiet`: a fresh reading renders NO chrome — freshness only ever
/// appears when degraded.
public enum Freshness: Equatable, Sendable {
    case fresh                                              // a recent successful poll (200 or 304) — quiet
    case stale(ageSeconds: Int)                            // last success is old (e.g. resumed from sleep)
    case failing(consecutive: Int, ageSeconds: Int)        // repeated poll failures while showing last-good data

    /// True when the island should show a caution freshness cue.
    public var isDegraded: Bool {
        if case .fresh = self { return false }
        return true
    }
}

public enum FreshnessModel {
    /// Default: a reading is degraded after `staleAfter` seconds without a success, or after
    /// `failureThreshold` consecutive poll failures (whichever fires first). 180s tolerates
    /// ~2 missed ~60s polls before crying caution; the failure count catches an active
    /// outage sooner. A `nil` lastSuccess means "haven't polled yet" → `.fresh` (loading,
    /// NOT stale — we don't accuse the reading before the first poll).
    public static let defaultStaleAfter: TimeInterval = 180
    public static let defaultFailureThreshold = 2

    public static func status(lastSuccess: Date?, now: Date, consecutiveFailures: Int,
                              staleAfter: TimeInterval = defaultStaleAfter,
                              failureThreshold: Int = defaultFailureThreshold) -> Freshness {
        let age = lastSuccess.map { Int(max(0, now.timeIntervalSince($0))) }
        if consecutiveFailures >= failureThreshold {
            return .failing(consecutive: consecutiveFailures, ageSeconds: age ?? 0)
        }
        if let age, TimeInterval(age) > staleAfter {
            return .stale(ageSeconds: age)
        }
        return .fresh   // includes lastSuccess == nil (not polled yet → loading, not stale)
    }

    /// The INBOUND SWEEP's own freshness clock (D1, WP 2026-07-10-001) — the per-fact stale
    /// clock the pill's standing/queue tier reads, distinct from the poll clock the radar/gauge
    /// read. One rule diverges from `status`: a NEVER-swept lane (`nil` date) is DEGRADED, not
    /// fresh. A painted inbound COUNT whose sweep never once succeeded is exactly the F3
    /// "adopted-stale count under fresh chrome" case (an item can ride through failed sweeps
    /// via the adopt rule), so its clock must read stale. (When the count is 0 no count-bearing
    /// state renders, so this is only ever consulted over a real, painted count — "never-swept
    /// + count 0" is moot.) A real success date falls through to the same thresholds `status`
    /// uses; the sweep carries no failure streak of its own, so `consecutiveFailures` is 0.
    public static func sweepStatus(lastSweepSuccess: Date?, now: Date,
                                   staleAfter: TimeInterval = defaultStaleAfter) -> Freshness {
        guard let last = lastSweepSuccess else { return .stale(ageSeconds: 0) }   // never swept → stale
        return status(lastSuccess: last, now: now, consecutiveFailures: 0, staleAfter: staleAfter)
    }

    /// The freshness cue for a persisted last-session snapshot painted on launch (WP-1c). It is
    /// NEVER `.fresh`: a snapshot is last-known-good, not a confirmed-current reading, so the
    /// caution banner MUST show on every cold-launch paint — honest by construction (no fabricated
    /// freshness). It ages from the STALEST lane's last success (mirroring the live worst-of-both
    /// fold — the island is only as current as its most-degraded lane), and returns `.stale` (not
    /// `.failing`: the app isn't failing on launch, it simply hasn't re-confirmed the reading yet).
    /// The very next live poll supersedes it with the real freshness.
    public static func forSnapshot(radarSuccess: Date?, pulseSuccess: Date?, now: Date) -> Freshness {
        let oldest = [radarSuccess, pulseSuccess].compactMap { $0 }.min()
        let age = oldest.map { Int(max(0, now.timeIntervalSince($0))) } ?? 0
        return .stale(ageSeconds: age)
    }

    /// The more-degraded of two readings — the WORST-OF-BOTH fold (WP-1b) that lets the
    /// H1 notifications lane and the H2 pulse lane share the ONE island-wide caution cue.
    /// Severity order: `.fresh` < `.stale` < `.failing`; ties break toward the larger age
    /// (staler) and the longer failure streak (more broken). Total + deterministic, so
    /// folding two lanes into one cue is unit-testable — and neither lane can mask the
    /// other's degradation (a persistently-failing pulse raises caution even while the
    /// notifications path 304s happily, and vice-versa).
    public static func worst(_ a: Freshness, _ b: Freshness) -> Freshness {
        severity(a) >= severity(b) ? a : b
    }

    /// A total ordering key: (kind, then the within-kind "how bad" magnitude). `.stale`
    /// ranks on age; `.failing` ranks on the failure count then age.
    private static func severity(_ f: Freshness) -> (Int, Int, Int) {
        switch f {
        case .fresh:                        return (0, 0, 0)
        case .stale(let age):               return (1, age, 0)
        case .failing(let consec, let age): return (2, consec, age)
        }
    }

    /// The caution label for a degraded reading; `nil` when fresh (so the view renders
    /// nothing — quiet by default).
    public static func label(for freshness: Freshness) -> String? {
        switch freshness {
        case .fresh:
            return nil
        case .stale(let age):
            return "Updated \(ageText(age)) ago"
        case .failing(_, let age):
            return "Reconnecting — last update \(ageText(age)) ago"
        }
    }

    /// Compact age: "45s" · "8m" · "2h". (Seconds-based sibling of `RadarPresenter.age`.)
    public static func ageText(_ seconds: Int) -> String {
        switch seconds {
        case ..<60:    return "\(max(1, seconds))s"
        case ..<3600:  return "\(seconds / 60)m"
        default:       return "\(seconds / 3600)h"
        }
    }
}
