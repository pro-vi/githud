import Foundation
import GithudCore

/// The single observable app state (WP-6a). A plain, MAIN-CONFINED `final class` — no
/// Combine, no SwiftUI, no timers. **AppDelegate mutates it** (poll callbacks, menu
/// toggles, a11y observers, the setup/auth ledger card); **HUDPanelController reads it and
/// renders**; StatusItemController's menu closures read it for live checkmarks. Before
/// this, every toggle hand-threaded through 3–4 objects (AppDelegate field → store →
/// HUD setter → view initializer); now the value lives in exactly one place.
///
/// Change notification is a lightweight observer list of synchronous callbacks — each
/// mutator fires its `Change` kind INLINE, on main, exactly where the old direct
/// `HUDPanelController` setter call sat. The model therefore adds NO scheduling layer:
/// the panel's EXISTING render coalescer (`setNeedsRender`/`renderNow`) remains the one
/// and only render throttle, and every event produces the same number of renders as the
/// direct-call wiring did (idle-footprint / attention-non-theft — verified per event
/// type in the WP-6a render trace).
///
/// Change GUARDS that used to live in the panel's setters live in the matching mutators
/// here (freshness, reduceTransparency, increaseContrast) so a no-op mutation still
/// produces no notification — and therefore no render — exactly as before.
///
/// Deliberately NOT in the model: `isVisible`/`expanded`. Those are panel-lifecycle
/// state whose transitions carry side effects the controller owns (the click-away
/// monitor, `orderOut`, the `onExpandChange` seam firing once per real transition) and
/// they are written only by the controller itself. Reading them stays behind the
/// controller's existing accessors (`isVisible`, `toggleExpand`), so the summon-hotkey
/// and menu wiring are untouched.
final class AppModel {
    /// What changed — the controller maps each kind onto the SAME render path the old
    /// direct setter used (coalesced for data, immediate for user-visible must-see-now).
    enum Change {
        case radar               // rows replaced (flips hasData; never touches the ledger card)
        case pulse               // H2 lane rows replaced
        case inbound             // standing inbound lane rows replaced (WP 2026-07-09-001)
        case freshness           // reading-confidence cue changed (guarded: real change only)
        case pulsePreferences    // showDrafts/showStale toggled (re-render from cached pulse)
        case inboundPreferences  // showHeldBack toggled (re-render from cached inbound)
        case surfacePreferences  // H1 reason set toggled — NO render here; the scheduler's
                                 // recompute emits fresh radar rows, which render via .radar
        case theme               // themeID switched (surface rebuild + instant render)
        case reduceTransparency  // a11y flip (guarded) — surface rebuild + instant render
        case increaseContrast    // a11y flip (guarded) — surface rebuild + instant render
        case ledger              // setup/auth ledger card shown, updated, or cleared (instant render)
        case pillStyle           // collapsed-pill vocabulary switched (re-render the pill/chooser)
        case pillStyleChooser    // the pill-style chooser card shown or dismissed (instant render)
        case sweepFreshness      // D1 sweep clock crossed fresh↔stale (repaint the pill's prefix)
        case lensPreferences     // owner lens toggled (shape or fold — re-render from cached pulse)
        case selfLogin           // GET /user resolved — "yours" titles/elision become renderable
        case lensChooser         // the owner-lens card shown or dismissed (instant render)
        case settingsCard        // the settings card shown or dismissed (instant render)
    }

    // MARK: - state (read by the controllers; written only via the mutators below)

    private(set) var surfacePreferences: SurfacePreferences
    private(set) var pulsePreferences: PulsePreferences
    private(set) var inboundPreferences: InboundPreferences
    /// The collapsed-pill vocabulary (D-pill config, WP 2026-07-10-001). Persisted raw via
    /// `PillStyleStore`; threaded into the pill's fingerprint/size/spoken in lockstep.
    private(set) var pillStyle: PillStyle
    /// The pill-style chooser card descriptor while it is showing (nil = not showing) —
    /// rides render() presence like `ledger`, but it is dismissable (click-away/gear-again)
    /// and takes NO key moment (it has no field).
    private(set) var pillStyleChooser: PillStyleChooser?
    /// When a COMPLETE inbound sweep last succeeded — the SWEEP CLOCK's provenance (D1). Read
    /// at render to compute the pill's sweep freshness (`FreshnessModel.sweepStatus`); a nil
    /// date with a painted count reads stale (never-swept F3 case). Deliberately NOT a `Change`
    /// (it never feeds the spine's caution cue — recorded lane decision — and a per-sweep
    /// notify would re-render ~every 60s with no visible change: idle-footprint).
    private(set) var lastInboundSuccessAt: Date?
    /// The owner lens (WP 2026-07-14-001): the "Your PRs" lane's shape (grouped vs flat)
    /// and which owners lead on this machine. Persisted raw via `LensStore`.
    private(set) var lensPreferences: LensPreferences
    /// The signed-in login (GET /user), once the radar pipeline resolves it — drives the
    /// lens's "yours" titles and the viewer's owner-prefix elision. Nil until auth lands;
    /// the lane renders raw logins honestly in the meantime.
    private(set) var selfLogin: String?
    /// The owner-lens card's presence (WP 2026-07-14-001) — rides render() like
    /// `pillStyleChooser` (dismissable, no key moment). The render branch recomputes the
    /// descriptor FRESH each pass from prefs/rows/login, so this stored value is presence
    /// + initial content, never a second truth that could drift from the lane.
    private(set) var lensChooser: LensChooser?
    /// The settings card's presence (mark-and-settings option B, dogfood-ratified
    /// 2026-07-14) — same lifecycle as its two card siblings; the render branch
    /// recomputes the descriptor fresh each pass.
    private(set) var settingsCard: SettingsCard?
    /// Per-owner "last opened the group on this machine" clocks (lowercased keys) — the
    /// folded ledger line's "N new" provenance. Deliberately NOT a `Change` (mirrors
    /// `lastInboundSuccessAt`): read at render; the unfold that stamps it already
    /// re-renders via `.lensPreferences`. Persisted via `LensStore`, seeded at launch.
    private(set) var lensLastOpened: [String: Date] = [:]
    private(set) var themeID: ThemeID
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false
    private(set) var radarRows: [RadarRow] = []
    private(set) var pulseRows: [PulseRow] = []
    private(set) var inboundRows: [InboundRow] = []
    private(set) var inboundConfirmed = false
    private(set) var freshness: Freshness = .fresh
    /// False until the first radar lands (the pill shows a loading dot, never a fake "all clear").
    private(set) var hasData = false
    /// True only once the RADAR lane has a CONFIRMED read behind it — flipped by
    /// `confirmRadar()` off the RADAR-SUCCESS SEAM (`PollReducer.attemptOutcome == .success`
    /// in `PollScheduler.poll()`: every genuine 200/304), or by the cold-launch snapshot
    /// paint when the persisted radar lane genuinely succeeded last session
    /// (`lastRadarSuccessAt != nil`). NEVER by a render (fix 1a, round 2): a render is a
    /// paint, and a paint can arrive with zero reads behind it — toggleReason →
    /// setPreferences → recomputeRadar() on a never-fetched cache renders `[]`
    /// unconditionally, and round 1's `confirmed: true` default turned that off-network
    /// re-projection into a fabricated confirmation. The caught-up affirmation gates on
    /// THIS, never on `hasData`: a pulse-only snapshot or a recompute paint still shows
    /// data honestly (pill/lanes) but must never let the island affirm an inbox githud
    /// has never once read. Monotonic within a session: once a real read exists, later
    /// paints can't unconfirm it.
    private(set) var radarConfirmed = false
    /// The WP-4d handshake-ledger card descriptor (no-token / auth states). While set, the
    /// panel renders the card INSTEAD of the data surface — but data keeps flowing into the
    /// model underneath (the card's own "GitHub" row is what reports on it), so the morph at
    /// completion lands on whatever the pill then truly measures. Value type from GithudCore —
    /// the token never appears here (`redacted()` is the only display form).
    private(set) var ledger: TokenLedger.Card?

    init(surfacePreferences: SurfacePreferences, pulsePreferences: PulsePreferences,
         themeID: ThemeID, inboundPreferences: InboundPreferences = InboundPreferences(),
         pillStyle: PillStyle = .queueLeads, lensPreferences: LensPreferences = .default) {
        self.surfacePreferences = surfacePreferences
        self.pulsePreferences = pulsePreferences
        self.themeID = themeID
        self.inboundPreferences = inboundPreferences
        self.pillStyle = pillStyle
        self.lensPreferences = lensPreferences
    }

    // MARK: - observation (synchronous, main-confined — no scheduling of its own)

    private var observers: [(Change) -> Void] = []

    /// Register a change observer. Observers are never removed — the model and its
    /// observers (the HUD controller) live for the app's whole lifetime, mirroring the
    /// old permanently-wired direct calls.
    func addObserver(_ observer: @escaping (Change) -> Void) {
        observers.append(observer)
    }

    private func notify(_ change: Change) {
        dispatchPrecondition(condition: .onQueue(.main))   // main-confined, like every old setter call site
        for observer in observers { observer(change) }
    }

    // MARK: - mutators (AppDelegate-facing; persistence stays in AppDelegate)

    /// Update the radar and mark data as landed. Deliberately does NOT clear the ledger
    /// card (the old MessageView was silently dropped here): during verification the first
    /// poll's rows arrive WHILE the card is up — the card must stay until GitHub's answer
    /// checks row 3 and the completion hold clears it (WP-4d; never celebrate early).
    ///
    /// `confirmed` is EXPLICIT at every call site — no default (fix 1a, round 2: the old
    /// `= true` default silently confirmed the recompute render). A render is a paint,
    /// not a read: the live scheduler wiring always passes `false` (confirmation rides
    /// the radar-success seam → `confirmRadar()`); the snapshot paint passes the
    /// persisted lane's real provenance (`lastRadarSuccessAt != nil`); only the fixture
    /// path claims `true` directly (a deliberate simulated state for visual proof,
    /// never live).
    func setRadar(_ rows: [RadarRow], confirmed: Bool) {
        radarRows = rows
        hasData = true
        if confirmed { radarConfirmed = true }
        notify(.radar)
    }

    /// Flip the radar-lane confirmation off the RADAR-SUCCESS SEAM (fix 1a, round 2):
    /// `PollScheduler.poll()` fires this on every `attemptOutcome == .success` (a 200, or
    /// a 304 — which requires a same-session 200 first) — a REAL read, regardless of
    /// whether the tick emitted a render. It must NOT ride the render effect: the
    /// `.preferencesRecomputed` reducer path adopts `lastKey`, so a first success whose
    /// key matches a prior recompute emits NO `renderRadar` — gating confirmation on the
    /// render would leave it false forever (a permanent false negative: a genuinely-read
    /// empty inbox that could never affirm). Change-guarded + monotonic: only the
    /// false→true flip notifies (`.radar`, the coalesced render path — the affirmation
    /// may now appear even when no row changed); steady-state success ticks are no-ops.
    func confirmRadar() {
        guard !radarConfirmed else { return }
        radarConfirmed = true
        notify(.radar)
    }

    /// Update the H2 pulse lane (your open PRs). Independent of the radar.
    func setPulse(_ rows: [PulseRow]) {
        pulseRows = rows
        notify(.pulse)
    }

    /// Update the standing inbound lane (issues/PRs others opened on repos you own —
    /// WP 2026-07-09-001). Independent of both other lanes, same contract as `setPulse`.
    func setInbound(_ rows: [InboundRow]) {
        inboundRows = rows
        notify(.inbound)
    }

    /// Flip the reviews-owed confirmation off the COMPLETE-sweep seam (WP 2026-07-17-002)
    /// — the affirmation's third gate: zero radar rows over a reviews sweep that never
    /// completed is an unread state, never affirmed. Monotonic within a session; the
    /// false→true flip repaints via `.radar` (the affirmation may now appear).
    private(set) var reviewsConfirmed = false
    func confirmReviews() {
        guard !reviewsConfirmed else { return }
        reviewsConfirmed = true
        notify(.radar)
    }

    /// Flip the inbound-lane confirmation off the COMPLETE-sweep seam (fix round, the
    /// radar-confirmed symmetry): fired by the scheduler on a complete sweep success, by
    /// the snapshot paint when the persisted lane genuinely succeeded last session, and
    /// by the fixture path (a deliberate simulated read). Monotonic within a session.
    /// The affirmation and the pill's all-clear both gate on THIS — an empty-looking
    /// queue that was never fully read must never read as confirmed-empty.
    func confirmInbound() {
        guard !inboundConfirmed else { return }
        inboundConfirmed = true
        notify(.inbound)
    }

    /// Session boundary (triage F3): confirmations are READ provenance, and a read
    /// belongs to the account that performed it. A new live session (token re-entry,
    /// possibly a different account) must re-earn all three — without this reset the
    /// old account's provenance could affirm "caught up" over a new account whose
    /// first sweeps failed. "Monotonic" above means monotonic WITHIN a session.
    func resetConfirmations() {
        guard radarConfirmed || inboundConfirmed || reviewsConfirmed else { return }
        radarConfirmed = false
        inboundConfirmed = false
        reviewsConfirmed = false
        notify(.radar)
        notify(.inbound)
    }

    /// Update the reading-freshness cue. Change-guarded — a steady `.fresh` notifies
    /// nothing (normal operation is quiet), same as the old panel-setter guard.
    func setFreshness(_ value: Freshness) {
        guard freshness != value else { return }
        freshness = value
        notify(.freshness)
    }

    /// H2 subsection visibility (show drafts / show stale). Unguarded, like the old
    /// setter — the menu toggle always re-renders from the cached pulse (no refetch).
    func setPulsePreferences(_ value: PulsePreferences) {
        pulsePreferences = value
        notify(.pulsePreferences)
    }

    /// Inbound-lane choice (show held-back). Same contract as `setPulsePreferences`.
    /// "Just cleared" (plan 2026-07-21-001): display-only departure receipts + the
    /// reveal preference. Rows never touch radarRows/counts/affirmation.
    private(set) var clearedRows: [ClearedRow] = []
    func setCleared(_ rows: [ClearedRow]) {
        guard rows != clearedRows else { return }
        clearedRows = rows
        notify(.radar)
    }
    private(set) var showJustCleared = false
    func setShowJustCleared(_ value: Bool) {
        guard value != showJustCleared else { return }
        showJustCleared = value
        notify(.radar)
    }

    func setInboundPreferences(_ value: InboundPreferences) {
        inboundPreferences = value
        notify(.inboundPreferences)
    }

    /// H1 reason set. The panel does NOT render on this — fresh rows arrive via the
    /// scheduler's recompute → `setRadar` (same two-step flow as before).
    func setSurfacePreferences(_ value: SurfacePreferences) {
        surfacePreferences = value
        notify(.surfacePreferences)
    }

    /// Theme selection. Unguarded, like the old `setTheme` — re-selecting the current
    /// theme still rebuilds (a deliberate user action gets its instant response).
    func setThemeID(_ id: ThemeID) {
        themeID = id
        notify(.theme)
    }

    /// Reduce-Transparency (a11y). Guarded, like the old setter.
    func setReduceTransparency(_ value: Bool) {
        guard reduceTransparency != value else { return }
        reduceTransparency = value
        notify(.reduceTransparency)
    }

    /// Increase-Contrast (a11y). Guarded, like the old setter.
    func setIncreaseContrast(_ value: Bool) {
        guard increaseContrast != value else { return }
        increaseContrast = value
        notify(.increaseContrast)
    }

    /// Show / update the setup or auth-error ledger card (no token, 401/403, wrong shape,
    /// Keychain write failure — WP-4d, one card species for the whole family). The
    /// controller reacts by forcing the panel visible + rendering immediately (a state the
    /// user must see now). Equality-guarded: a repeated identical descriptor (e.g. another
    /// failed retry attempt with the same outcome) notifies nothing — no render churn, no
    /// motion where no fact changed.
    func showLedger(_ card: TokenLedger.Card) {
        guard ledger != card else { return }
        ledger = card
        notify(.ledger)
    }

    /// Drop the ledger card and return to the data surface (completion after the hold, or
    /// the WP-4e hot start's clear). Never touches visibility — clearing the card never
    /// hides the HUD; the render it triggers is where the card→pill morph runs.
    func clearLedger() {
        guard ledger != nil else { return }
        ledger = nil
        notify(.ledger)
    }

    /// Switch the collapsed-pill vocabulary (D-pill config). Change-guarded — re-selecting
    /// the current style notifies nothing. Persistence stays in AppDelegate (`PillStyleStore`).
    func setPillStyle(_ style: PillStyle) {
        guard pillStyle != style else { return }
        pillStyle = style
        notify(.pillStyle)
    }

    /// Show the pill-style chooser card (gear → "Pill style…"). Equality-guarded like the
    /// ledger — re-showing the same descriptor notifies nothing.
    func showPillStyleChooser(_ chooser: PillStyleChooser) {
        guard pillStyleChooser != chooser else { return }
        pillStyleChooser = chooser
        notify(.pillStyleChooser)
    }

    /// Dismiss the chooser card (click-away / collapse / gear-again). No-op when not showing.
    func clearPillStyleChooser() {
        guard pillStyleChooser != nil else { return }
        pillStyleChooser = nil
        notify(.pillStyleChooser)
    }

    /// Owner-lens choice (shape or fold set). Unguarded like `setPulsePreferences` — every
    /// handle (ledger line, card, gear) re-renders from the cached pulse, no refetch.
    func setLensPreferences(_ value: LensPreferences) {
        lensPreferences = value
        notify(.lensPreferences)
    }

    /// The signed-in login resolved (GET /user). Change-guarded — one repaint when it
    /// lands so "yours" titles/elision appear; steady re-resolutions of the same login
    /// are no-ops. Cleared only via `clearSelfLogin()` (a new live session).
    func setSelfLogin(_ login: String?) {
        guard let login, login != selfLogin else { return }
        selfLogin = login
        notify(.selfLogin)
    }

    /// A NEW live session (fresh token — possibly a different account) invalidates the
    /// previous login: the lens renders raw logins honestly until the new /user
    /// resolves, so an account switch can never label the OLD account "yours"
    /// (Codex P2, PR #1 round 3). Change-guarded like its setter.
    func clearSelfLogin() {
        guard selfLogin != nil else { return }
        selfLogin = nil
        notify(.selfLogin)
    }

    /// Show the owner-lens card (the eye / gear → "Lens…"). Equality-guarded like its
    /// chooser sibling.
    func showLensChooser(_ chooser: LensChooser) {
        guard lensChooser != chooser else { return }
        lensChooser = chooser
        notify(.lensChooser)
    }

    /// Dismiss the lens card (click-away / collapse / eye-again). No-op when not showing.
    func clearLensChooser() {
        guard lensChooser != nil else { return }
        lensChooser = nil
        notify(.lensChooser)
    }

    /// Show the settings card (the gear / menu → "Settings…"). Equality-guarded.
    func showSettingsCard(_ card: SettingsCard) {
        guard settingsCard != card else { return }
        settingsCard = card
        notify(.settingsCard)
    }

    /// Dismiss the settings card (click-away / collapse / gear-again). No-op when hidden.
    func clearSettingsCard() {
        guard settingsCard != nil else { return }
        settingsCard = nil
        notify(.settingsCard)
    }

    /// Seed the per-owner last-opened clocks from disk (launch). Not a `Change`.
    func seedLensLastOpened(_ map: [String: Date]) {
        lensLastOpened = map
    }

    /// Stamp an owner's "last seen" baseline — the ledger line's "N new" zero point.
    /// Fired on BOTH fold directions (fold = "I saw them as of now"; unfold = "I'm
    /// looking now" — Codex P2, round 7). Not a `Change`: the toggle that triggers it
    /// already re-renders via `.lensPreferences`; persistence stays in AppDelegate.
    func markLensOpened(owner: String, at date: Date = Date()) {
        lensLastOpened[owner.lowercased()] = date
    }

    /// Record the inbound sweep clock's provenance (D1). NOT a `Change` — see the field's
    /// doc: it is read at render, never a re-render trigger of its own (idle-footprint);
    /// the crossing that DOES warrant a repaint arrives via `sweepFreshnessCrossed()`.
    func setInboundSuccessAt(_ date: Date?) {
        lastInboundSuccessAt = date
    }

    /// The sweep clock crossed fresh↔stale (D1, F-1): the reducer detected the boolean
    /// crossing on its tick and the shell forwards it here — exactly one notification per
    /// crossing, both directions. Carries no value: the render recomputes the actual prefix
    /// from `lastInboundSuccessAt`, so this can never disagree with what gets drawn.
    func sweepFreshnessCrossed() {
        notify(.sweepFreshness)
    }
}
