import Foundation

/// The last rendered radar + pulse, with each lane's last-success time — persisted so a cold
/// launch can paint last-known-good INSTANTLY instead of a blank pill (worst case ~77s of
/// sequential self-login → fetch → enrich → pulse before the first live paint). Honest by
/// construction: the timestamps let the launch-paint show the caution banner ageing correctly
/// ("Updated 9h ago"), and it is NEVER shown as `.fresh` (see `FreshnessModel.forSnapshot`).
/// The snapshot is only the PRE-first-poll paint — live data arriving later always wins.
public struct Snapshot: Codable, Equatable, Sendable {
    public var radar: [RadarRow]
    public var pulse: [PulseRow]
    /// The standing inbound lane (WP 2026-07-09-001). OPTIONAL so a pre-inbound snapshot
    /// file (no key) still decodes — an old snapshot simply paints without the lane.
    public var inbound: [InboundRow]?
    /// When the notifications lane last succeeded (200 or 304). Drives the honest stale age.
    public var lastRadarSuccessAt: Date?
    /// When the pulse lane last succeeded. `nil` if the pulse never produced last-good data.
    public var lastPulseSuccessAt: Date?
    /// When a COMPLETE inbound sweep last succeeded — the lane's confirmation provenance
    /// (the launch paint confirms the queue only when this is non-nil, mirroring the
    /// radar's `lastRadarSuccessAt` rule). Optional: absent in pre-sweep snapshots.
    public var lastInboundSuccessAt: Date?
    /// When a COMPLETE reviews-owed sweep last succeeded (WP 2026-07-17-002) — same
    /// provenance rule; the synthetic rows themselves ride `radar`. Optional: absent in
    /// pre-reviews snapshots (tolerant decode).
    public var lastReviewsSuccessAt: Date?
    /// The owed-review baseline ITEMS (triage F2): display rows alone can't rebuild the
    /// pipeline's standing truth, and without it a first tick whose reviews search fails
    /// wipes still-owed rows. Optional: absent in older snapshots (tolerant decode).
    public var reviewsOwed: [InboundItem]?

    public init(radar: [RadarRow], pulse: [PulseRow], inbound: [InboundRow]? = nil,
                lastRadarSuccessAt: Date?, lastPulseSuccessAt: Date?,
                lastInboundSuccessAt: Date? = nil, lastReviewsSuccessAt: Date? = nil,
                reviewsOwed: [InboundItem]? = nil) {
        self.radar = radar
        self.pulse = pulse
        self.inbound = inbound
        self.lastRadarSuccessAt = lastRadarSuccessAt
        self.lastPulseSuccessAt = lastPulseSuccessAt
        self.lastInboundSuccessAt = lastInboundSuccessAt
        self.lastReviewsSuccessAt = lastReviewsSuccessAt
        self.reviewsOwed = reviewsOwed
    }

    /// True when there is anything worth painting. An empty snapshot yields a clean cold start
    /// (the loading pill), never a fabricated "all clear".
    public var isEmpty: Bool { radar.isEmpty && pulse.isEmpty && (inbound ?? []).isEmpty }

    /// A copy with every radar comment-excerpt removed — the PERSISTED form (WP-1c review,
    /// Minor 2). Comment bodies were memory-only before the snapshot existed; writing them to
    /// `Application Support` would silently widen the privacy surface (plaintext comment
    /// content on disk). `SnapshotStore.save` applies this unconditionally, so no caller can
    /// persist an excerpt. The launch paint renders rows without the preview line — honest
    /// degradation; the first live poll restores excerpts in memory. (Inbound rows carry no
    /// comment bodies — titles + opener logins only, the same class the other lanes persist.)
    public func strippingExcerpts() -> Snapshot {
        Snapshot(radar: radar.map { $0.droppingExcerpt }, pulse: pulse, inbound: inbound,
                 lastRadarSuccessAt: lastRadarSuccessAt, lastPulseSuccessAt: lastPulseSuccessAt,
                 lastInboundSuccessAt: lastInboundSuccessAt,
                 lastReviewsSuccessAt: lastReviewsSuccessAt,
                 reviewsOwed: reviewsOwed)
    }
}

extension RadarRow {
    /// The same row without the latest-comment excerpt (privacy: comment bodies never persist).
    /// The change signature is RECOMPUTED excerpt-free so it always describes the row's actual
    /// displayed content (a signature claiming text the row no longer carries would be a lie);
    /// the first live poll's rows carry fresh full signatures, so any snapshot-era peek drops
    /// honestly when real content lands (WP-3d′ drop-on-changed-signature).
    var droppingExcerpt: RadarRow {
        RadarRow(id: id, repo: repo, title: title, subtitle: subtitle, timestamp: timestamp,
                 urgency: urgency, symbolName: symbolName, isCritical: isCritical,
                 url: url, excerpt: nil,
                 changeSignature: RadarPresenter.changeSignature(
                     title: title, subtitle: subtitle, timestamp: timestamp, excerpt: nil))
    }
}

/// Reads/writes the last-session `Snapshot` as JSON under Application Support. Best-effort:
/// a failed save is never fatal, and a missing/corrupt/old-schema file loads as `nil` → a
/// clean cold start. No timers, no per-render writes — the scheduler saves only on a real
/// data change (see `PollScheduler`).
public enum SnapshotStore {
    public static let directoryName = "githud"
    public static let fileName = "last-session.json"

    /// `~/Library/Application Support/githud/last-session.json`. `nil` only if the OS can't
    /// resolve Application Support (then persistence silently no-ops — never a crash).
    public static var defaultURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        return base.appendingPathComponent(directoryName, isDirectory: true)
                   .appendingPathComponent(fileName)
    }

    /// Persist `snapshot` (atomic write). Best-effort — a failure (e.g. read-only disk) is
    /// swallowed: losing a snapshot only costs the next launch its instant paint, never data.
    /// Comment excerpts are ALWAYS stripped before the bytes hit disk (privacy — Minor 2):
    /// enforced here, at the one write site, so no caller can persist comment content.
    public static func save(_ snapshot: Snapshot, to url: URL? = defaultURL) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot.strippingExcerpts())
            try data.write(to: url, options: .atomic)
        } catch {
            // best-effort; a failed snapshot save is never fatal
        }
    }

    /// Load the last-session snapshot, or `nil` if absent/unreadable/corrupt/old-schema — every
    /// non-happy path collapses to `nil` so a bad file can only ever cause a clean cold start.
    public static func load(from url: URL? = defaultURL) -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        // Defense-in-depth: strip on load too, so a legacy pre-strip file on disk
        // (written before excerpts were excluded from persistence) never paints one.
        return (try? JSONDecoder().decode(Snapshot.self, from: data))?.strippingExcerpts()
    }

    /// Remove the persisted snapshot (used by tests; also a clean-slate hook).
    public static func clear(at url: URL? = defaultURL) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
