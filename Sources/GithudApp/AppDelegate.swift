import AppKit
import GithudCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hudController: HUDPanelController?
    /// Global summon hotkey (WP-6h, ⌃⌥G) — independent of the key-session gate; owns its
    /// own Carbon registration lifecycle (unregisters in `deinit`).
    private var summonHotkey: SummonHotkey?

    /// When non-empty (e.g. `--fixture` mode), the island opens populated + expanded.
    var initialRows: [RadarRow] = []
    /// H2 pulse fixture (`--fixture-pulse`) — renders the "Your PRs" lane.
    var initialPulse: [PulseRow] = []
    var initialInbound: [InboundRow] = []
    /// Overrides the stored pulse preferences (e.g. `--show-drafts` for visual proof).
    var initialPulsePreferences: PulsePreferences?
    /// Overrides the stored theme (e.g. `--theme geist-mono` for visual proof).
    var initialThemeID: ThemeID?
    /// Render the fixture COLLAPSED (e.g. `--collapsed` to see the pill gauge), not expanded.
    var initialCollapsed = false
    /// Force a degraded reading-freshness for visual proof (e.g. `--stale`).
    var initialFreshness: Freshness = .fresh
    /// When set (a PAT was resolved), the app polls live and refreshes the island.
    var liveClient: GitHubClient?
    /// A token was found but isn't a classic PAT (e.g. a fine-grained `github_pat_…`) —
    /// show a shape-specific setup card instead of silently 403-looping (review F8).
    var tokenShapeInvalid = false
    /// The NON-SENSITIVE redacted display form of the active token ("ghp_•(40)") — the only
    /// form of the secret that ever renders (WP-4d ledger row 1's done-detail). Stashed
    /// wherever a live client is created (main.swift's launch resolve + `submitToken`), so a
    /// runtime auth card never needs a second Keychain read (`keychain-headless-prompt`).
    var tokenRedacted: String?
    /// Token PROVENANCE (fix round, finding 7): true only when the active token really
    /// lives in the Keychain (a launch Keychain read, or a `submitToken` store). An
    /// env-sourced `GITHUD_PAT` token sets this false — its runtime auth card must never
    /// fabricate a "Keychain · stored" receipt for a store that never happened.
    var tokenStoredInKeychain = true
    /// WP-4d — the handshake-ledger card's state (pure machine in `GithudCore.TokenLedger`).
    /// This delegate OWNS the state and applies events at the exact real callback sites
    /// (`submitToken`'s gates, `startLiveSession`, the first-poll seam, `onAuthFailure`);
    /// the model carries only the derived `Card` descriptor; the AppKit view just renders it.
    private var ledgerState: TokenLedger.State?
    /// Monotonic live-session counter (fix round, finding 10): every `startLiveSession`
    /// bumps it, `.sessionStarted` binds the ledger's handshake to it, and every outcome
    /// event carries it — so an outcome from a superseded session can never touch a
    /// handshake it doesn't own (the pure reduce drops mismatches).
    private var sessionGeneration = 0
    private var scheduler: PollScheduler?
    /// THE single observable app state (WP-6a): surface/pulse preferences, theme id, a11y
    /// flags, radar/pulse rows, freshness, ledger card. This delegate MUTATES it (poll callbacks,
    /// menu toggles, a11y observers, the auth/setup ledger); `HUDPanelController` observes + renders;
    /// the gear-menu closures read it for live checkmarks. Persistence (UserDefaults stores)
    /// stays here, beside each mutation — the model itself never touches disk.
    private let model = AppModel(surfacePreferences: SurfaceStore.load(),   // user's surface choices (default auto)
                                 pulsePreferences: PulseStore.load(),       // H2 pulse choices (default: drafts hidden)
                                 themeID: ThemeStore.load(),                // selected theme (default: Color)
                                 inboundPreferences: InboundStore.load(),   // inbound lane (default: held-back hidden)
                                 pillStyle: PillStyleStore.load(),          // D-pill vocabulary (default: queueLeads)
                                 lensPreferences: LensStore.load())         // owner lens (default: flat, all leading)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Owner lens: seed the per-owner "last opened" clocks (the ledger lines' "N new"
        // baseline) before anything renders.
        model.seedLensLastOpened(LensStore.loadLastOpened())
        let hud = HUDPanelController(model: model)
        hudController = hud

        // Status item + in-island gear FIRST, so onGearTap is set before any render.
        // Passing the model wires the WP-5g live glyph to the SAME observer seam the panel
        // renders from (mutation-driven only — no timer in the status item).
        statusItemController = StatusItemController(
            model: model,
            onToggle: { [weak hud] in hud?.toggleExpand() },   // menu-bar click = summon
            onQuit: { NSApp.terminate(nil) },
            // VERBS-ONLY menu (mark-and-settings option B, dogfood-ratified 2026-07-14):
            // all config lives in the in-island Settings card.
            onOpenSettings: { [weak self] in self?.toggleSettingsCard() },
            currentVisibility: { [weak hud] in hud?.isVisible ?? false },
            onToggleVisibility: { [weak hud] in
                guard let hud else { return }
                hud.isVisible ? hud.hide() : hud.show()   // WP-5i: the unified menu's Hide/Show affordance
            }
        )
        // The in-island gear opens the SETTINGS CARD, not a system dropdown (option B).
        hud.onGearTap = { [weak self] _ in self?.toggleSettingsCard() }
        // Settings-card actions — the SAME funcs the old menu items called (one truth).
        hud.onSettingsToggleReason = { [weak self] reason in self?.toggleReason(reason) }
        hud.onSettingsSelectTheme = { [weak self] id in self?.selectTheme(id) }
        hud.onSettingsToggleLaunch = { [weak self] in self?.toggleLaunchAtLogin() }
        hud.onSettingsOpenPillStyle = { [weak self] in self?.openPillFromSettings() }
        hud.onSettingsOpenLens = { [weak self] in self?.openLensFromSettings() }
        hud.onDismissSettingsCard = { [weak self] in self?.model.clearSettingsCard() }
        hud.currentLaunchAtLogin = { SMAppService.mainApp.status == .enabled }
        // Back returns WHERE YOU CAME FROM (dogfood 2026-07-14): a door from Settings
        // goes back to Settings; the eye's lens goes back to the island. Settings is
        // the root pane — its back is always the island.
        hud.onSettingsBack = { [weak hud] in hud?.returnSettingsCardToIsland() }
        hud.onLensBack = { [weak self, weak hud] in
            guard let self else { return }
            if self.lensOpenedFromSettings {
                self.lensOpenedFromSettings = false
                self.model.showSettingsCard(self.makeSettingsCard())   // show first —
                self.model.clearLensChooser()                          // navigation, not exit
            } else {
                hud?.returnLensCardToIsland()
            }
        }
        hud.onPillBack = { [weak self, weak hud] in
            guard let self else { return }
            if self.pillOpenedFromSettings {
                self.pillOpenedFromSettings = false
                self.model.showSettingsCard(self.makeSettingsCard())
                self.model.clearPillStyleChooser()
            } else {
                hud?.returnPillCardToIsland()
            }
        }
        // WP 2026-07-12-001: the island's plain-words caption/hide controls share ONE truth
        // with the gear — they call the exact same toggle funcs, so the gear checkmark stays
        // honest and the reveal eases on the existing preference-change re-render.
        hud.onToggleStale = { [weak self] in self?.toggleShowStale() }
        hud.onToggleHeldBackInbound = { [weak self] in self?.toggleShowHeldBackInbound() }
        hud.onToggleJustCleared = { [weak self] in self?.toggleShowJustCleared() }
        model.setShowJustCleared(ClearedStore.load())     // the reveal pref survives launches

        hud.onToggleDrafts = { [weak self] in self?.toggleShowDrafts() }
        // Owner lens (WP 2026-07-14-001): the folded ledger line's click unfolds through the
        // SAME toggle the lens card + gear use — the unfold stamps the "N new" clock.
        hud.onToggleFoldedOwner = { [weak self] owner in self?.toggleFoldedOwner(owner) }
        // WP-4d: the ledger card's secure field submits into the SAME runtime intake wire
        // the DEBUG driver exercises (WP-4e) — one path, no card-only fork.
        hud.onTokenSubmit = { [weak self] raw in self?.submitToken(raw) }
        // WP 2026-07-10-001: the chooser card's selection persists + applies instantly; its
        // dismissal (click-away / chevron) clears the model presence, morphing back to the pill.
        hud.onPillStyleSelect = { [weak self] style in self?.selectPillStyle(style) }
        hud.onDismissPillStyleChooser = { [weak self] in self?.model.clearPillStyleChooser() }
        // Owner lens (WP 2026-07-14-001): the eye + merged "elsewhere" line open the lens
        // card; its two toggles route to the SAME funcs the ledger lines + gear use (one
        // truth); dismissal mirrors the pill chooser's.
        hud.onOpenLensCard = { [weak self] in self?.toggleLensChooser() }
        hud.onLensToggleOwner = { [weak self] owner in self?.toggleFoldedOwner(owner) }
        hud.onLensToggleGroup = { [weak self] in self?.toggleGroupByOwner() }
        hud.onLensReorder = { [weak self] order in self?.reorderLensOwners(order) }
        hud.onDismissLensChooser = { [weak self] in self?.model.clearLensChooser() }
        // Correct screen anchoring (WP-5i): the status item's OWN screen first (so the island
        // lands on the monitor the menu-bar item actually lives on, not whichever one AppKit
        // calls "main") — falling back to the screen under the mouse, then `NSScreen.main`.
        // Externally owned, like `onGearTap` (HUDPanelController never reaches into
        // StatusItemController itself).
        hud.screenProvider = { [weak statusItemController] in
            statusItemController?.screen
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
        }
        // Global summon hotkey (WP-6h, ⌃⌥G) — independent of the key-session gate: routes
        // through the EXISTING show()/setExpanded()/toggleExpand() paths only, so it
        // inherits the click-away monitor lifecycle + the onExpandChange poll-now seam for
        // free. Hidden → show() then expand; otherwise → toggle. A ledger-card state (no
        // token / auth error) is left alone — it's already showing (isVisible is true), so
        // this just falls into the toggle branch and raises/toggles whatever is true.
        summonHotkey = SummonHotkey(onSummon: { [weak hud] in
            guard let hud else { return }
            if !hud.isVisible {
                hud.show()
                hud.setExpanded(true)
            } else {
                hud.toggleExpand()
            }
            // WP-6k: the ⌃⌥G path — and ONLY it — begins the scoped key session, after
            // the expanded render above completed. Its internal guards keep every other
            // outcome honest: a toggle that COLLAPSED already ended the session inside
            // setExpanded(false); a ledger card keeps today's WP-4d behavior (force-
            // shown card, no list session). Mouse summons (pill click, status-item
            // click, "Show island") never call this — the F8 never-key boundary is
            // structural, not conditional.
            hud.beginKeySummonSession()
        })
        // Apply the theme up front (surface/material/grain), honoring Reduce Transparency +
        // Increase Contrast, and keep tracking both a11y settings live (same observer, one
        // notification — accessibilityDisplayOptionsDidChangeNotification covers both).
        model.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        model.setIncreaseContrast(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        model.setThemeID(initialThemeID ?? model.themeID)   // forced by --theme when present
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        // Apply the drafts-hidden default before any pulse lands (forced by --show-drafts /
        // --show-stale for visual proof when present).
        model.setPulsePreferences(initialPulsePreferences ?? model.pulsePreferences)

        if !initialRows.isEmpty || !initialPulse.isEmpty || !initialInbound.isEmpty {
            model.setRadar(initialRows, confirmed: true)  // sets hasData (even if empty) so the
                                                          // collapsed pill gauge can show; a
                                                          // fixture is a deliberate SIMULATED
                                                          // read (visual proof) — the one
                                                          // non-live site that claims confirmed
            if !initialPulse.isEmpty { model.setPulse(initialPulse) } // …the H2 lane
            if !initialInbound.isEmpty { model.setInbound(initialInbound) }   // …the Inbound lane
            // A fixture is a deliberate simulated read of ALL lanes (mirrors the
            // unconditional radar `confirmed: true` above) — without this, a pulse-only
            // fixture could never render the affirmation (fail-closed inbound gate).
            model.confirmInbound()
            model.confirmReviews()   // same simulated-read rule for the reviews sweep
            // D1 sweep clock (a fixture is a simulated read of ALL lanes): match the
            // fixture's freshness intent so `--stale` shows the caution prefix on the
            // standing/inbound tier too, and a fresh fixture never fabricates a stale queue.
            model.setInboundSuccessAt(initialFreshness.isDegraded ? Date().addingTimeInterval(-600) : Date())
            model.setFreshness(initialFreshness)          // --stale → caution freshness cue (visual proof)
            if !initialCollapsed { hud.setExpanded(true) }          // expanded list, unless --collapsed
            hud.show()
        } else if let client = liveClient {
            startLiveSession(client: client)              // extracted (WP-4e) — same wiring at launch AND runtime
        } else if tokenShapeInvalid {
            showAuthFailure(.wrongShape)                  // launch-caught non-classic shape (WALL) → row 1 failed
        } else {
            setLedger(TokenLedger.welcome())              // first run: three pending receipts, nothing claimed (WP-4d)
        }

        #if DEBUG
        // NON-SHIPPING dev aid (WP-4e hot-start proof) — DEBUG-only AND env-gated, so it is
        // stripped from the release .app (build-app.sh builds `-c release`) and does nothing
        // unless opted in. When GITHUD_DEV_SUBMIT_TOKEN holds a classic PAT, drive the runtime
        // intake ~1.5s after launch so a GUI run witnesses the "no token" card flip to a live
        // session with NO relaunch — exactly the path the design-gated entry UI (WP-4d) will
        // drive. Writes the REAL Keychain (what a real user does), so it is opt-in, never
        // automated, and never touched by the test runner.
        if let devToken = ProcessInfo.processInfo.environment["GITHUD_DEV_SUBMIT_TOKEN"],
           !devToken.isEmpty, liveClient == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                _ = self?.submitToken(devToken)
            }
        }
        #endif
    }

    /// Build + start the LIVE poll session from an already-resolved client (WP-4e). Same
    /// wiring at launch AND runtime (`submitToken`), so a stored token goes live with no
    /// relaunch: the scheduler's callbacks now mutate the MODEL (radar/pulse/freshness —
    /// the panel observes + renders, same one-render-per-burst coalescing), auth failures
    /// route through the reason-specific copy, the expand seam drives the scheduler, and the
    /// cold-launch snapshot paints + seeds freshness. Idempotent: any prior scheduler is torn
    /// down first, so a second call can't leave two poll loops running.
    func startLiveSession(client: GitHubClient) {
        guard let hud = hudController else { return }
        let firstSession = sessionGeneration == 0         // captured BEFORE the increment below
        scheduler?.stop()                                 // idempotent: never two live loops
        model.clearSelfLogin()                            // a fresh token may be a different account —
                                                          // the lens must never call the OLD login "yours"
        model.setCleared([])                              // receipts are session facts —
                                                          // a replacement session starts
                                                          // with none (land-triage F4)
        model.resetConfirmations()                        // …and never inherit its READ provenance
                                                          // (triage F3): all three confirmations are
                                                          // re-earned per session — a no-op at launch
        let scheduler = PollScheduler(client: client, preferences: model.surfacePreferences) { [weak self] rows in
            // Refresh on change (collapsed pill or list). NEVER confirms (fix 1a, round 2):
            // a render is a paint, not a read — the toggleReason → setPreferences recompute
            // rides this SAME callback with possibly zero reads behind it. Confirmation
            // arrives via onRadarConfirmed below, off the radar-success seam.
            self?.model.setRadar(rows, confirmed: false)
        }
        scheduler.onRadarConfirmed = { [weak self] in
            self?.model.confirmRadar()                    // a genuine 200/304 radar read — the ONE
                                                          // live fact that may unlock the affirmation
        }
        scheduler.onPulse = { [weak self] rows in
            self?.model.setPulse(rows)                    // H2 lane — your open PRs' state
        }
        scheduler.onInbound = { [weak self] rows in
            self?.model.setInbound(rows)                  // standing inbound queue (at your door)
        }
        scheduler.onInboundConfirmed = { [weak self] in
            self?.model.confirmInbound()                  // a COMPLETE sweep actually read the queue
            self?.model.setInboundSuccessAt(Date())       // D1 sweep clock: a complete sweep just ticked
        }
        scheduler.onFreshness = { [weak self] freshness in
            self?.model.setFreshness(freshness)           // caution cue when the reading goes stale
        }
        scheduler.onSelfLogin = { [weak self] login in
            self?.model.setSelfLogin(login)               // owner lens: "yours" becomes renderable
        }
        scheduler.onReviewsConfirmed = { [weak self] in
            self?.model.confirmReviews()                  // reviews owed: a COMPLETE sweep read the debt
        }
        scheduler.onCleared = { [weak self] rows in
            self?.model.setCleared(rows)                  // "Just cleared" receipts (change-guarded)
        }
        scheduler.onSweepFreshness = { [weak self] _ in
            self?.model.sweepFreshnessCrossed()           // D1 (F-1): one repaint per fresh↔stale
                                                          // sweep crossing — the render recomputes
                                                          // the prefix from the model's own date
        }
        scheduler.onAuthFailure = { [weak self] reason in
            self?.showAuthFailure(reason)                 // 401 vs 403 → distinct, specific guidance (WP-4e)
        }
        // WP-4d: each session gets a GENERATION so the ledger can ignore outcomes from a
        // session its handshake doesn't own (fix round, finding 10 — a stale answer must
        // never check, fail, or caution a fresh handshake).
        sessionGeneration += 1
        let generation = sessionGeneration
        scheduler.onPollOutcome = { [weak self] outcome in
            // WP-4d first-poll seam: the ledger's "GitHub" row consumes real attempt
            // outcomes — success checks it ("connected", the morph gate); a genuine
            // no-answer is the bounded caution exit off "verifying…"; a rate-limit renders
            // its own honest line ("rate limited — retrying in ~Xm" — GitHub DID answer).
            // No card up → applyLedger is a no-op (cheap per tick).
            self?.applyLedger(TokenLedger.event(for: outcome, generation: generation))
        }
        // Panel expand/collapse → scheduler (WP-1c): tracks visibility so poll ticks re-render
        // on a coarse-age-bucket flip ONLY while the ages are visible, AND fires a debounced
        // poll-now on expand — absorbed follow-up (a): completes the panel-expand poll-now
        // trigger through the onExpandChange seam WP-3e left unwired.
        hud.onExpandChange = { [weak scheduler] expanded in scheduler?.setExpanded(expanded) }

        // Cold-launch instant paint (WP-1c): last session's radar + pulse, painted BEFORE the
        // first poll and marked STALE via the freshness banner (never .fresh — it's
        // last-known-good, not a confirmed-current reading). Kills the blank pill during the
        // slow sequential first fetch (self-login → notifications → enrich → pulse). The first
        // live render supersedes it (it arrives after start()). Live path only — fixture runs
        // never touch the snapshot.
        // FIRST session only (triage F3): the disk snapshot is the LAST session's truth,
        // and a runtime re-entry may be a different account — re-seeding its rows and
        // confirmations would resurrect another account's provenance right after the
        // reset above. A token re-entry starts from the live fetches instead.
        if firstSession, let snap = SnapshotStore.load(), !snap.isEmpty {
            let snapshotFreshness = FreshnessModel.forSnapshot(
                radarSuccess: snap.lastRadarSuccessAt, pulseSuccess: snap.lastPulseSuccessAt, now: Date())
            // `confirmed:` carries the RADAR lane's real provenance (fix round, trust
            // major 1a): a pulse-only snapshot (radar failed all last session →
            // lastRadarSuccessAt nil) still paints — hasData flips, the pill leaves the
            // loading dot honestly — but does NOT confirm the radar, so the caught-up
            // affirmation cannot claim an inbox that was never once read.
            model.setRadar(snap.radar, confirmed: snap.lastRadarSuccessAt != nil)
            model.setPulse(snap.pulse)
            model.setInbound(snap.inbound ?? [])
            // D1 sweep clock: seed the persisted last-complete-sweep date so a chronic count
            // painted on launch reads correctly (nil ⇒ never swept ⇒ the pill's stale prefix).
            model.setInboundSuccessAt(snap.lastInboundSuccessAt)
            // Same provenance rule as the radar line above: the persisted lane confirms
            // only if a COMPLETE sweep genuinely succeeded last session.
            if snap.lastInboundSuccessAt != nil { model.confirmInbound() }
            // Reviews provenance, same rule: confirm only over a real prior complete sweep.
            scheduler.seedReviewsSuccess(snap.lastReviewsSuccessAt)
            if snap.lastReviewsSuccessAt != nil { model.confirmReviews() }
            // Standing review truth crosses the launch boundary (triage F2): without this
            // seed a first tick whose notifications succeed while the reviews search
            // fails renders the radar WITHOUT the lane and wipes still-owed rows.
            scheduler.seedReviewsBaseline(snap.reviewsOwed ?? [])
            model.setFreshness(snapshotFreshness)
            // Seed the reducer's freshness baseline to the SAME value the glass now shows
            // (Blocker B): the first healthy poll computes .fresh ≠ this seed, so the change
            // guard EMITS and the "Updated Xh ago" banner CLEARS. Unseeded, the reducer's
            // .fresh default would suppress that emit and the stale cue would sit over live
            // data all session (a permanent false-stale on the reserved caution cue). The
            // persisted last-success dates ride along so a FAILED first poll keeps the
            // banner honestly aged instead of clearing it (see seedFreshness).
            scheduler.seedFreshness(snapshotFreshness,
                                    radarSuccess: snap.lastRadarSuccessAt,
                                    pulseSuccess: snap.lastPulseSuccessAt,
                                    inboundSuccess: snap.lastInboundSuccessAt)   // F-1: the sweep
                                                          // crossing detector needs the real clock,
                                                          // or a seeded-fresh queue ageing into
                                                          // stale would never repaint
        }

        applyLedger(.sessionStarted(generation: generation))   // row 3 → "verifying…" (static — no spinner, ever)
        scheduler.start()
        self.scheduler = scheduler
        hud.show()                                        // collapsed by default
    }

    // MARK: - WP-4d — the handshake ledger (event application + completion)

    /// Apply one REAL event to the ledger card. No card showing → no-op (poll outcomes keep
    /// flowing after completion; they must not resurrect a dismissed card). Unchanged state →
    /// no notify (the model's equality guard makes repeat outcomes render-free).
    private func applyLedger(_ event: TokenLedger.Event) {
        guard let state = ledgerState else { return }
        let next = TokenLedger.reduce(state, event)
        guard next != state else { return }
        setLedger(next)
    }

    /// Install a ledger state and render its card (force-visible via `handle(.ledger)` — a
    /// must-see-now state, same contract the old MessageView had). On the TRANSITION into
    /// complete (all three receipts checked — GitHub really answered), hold ~700ms so the
    /// third check is witnessed, then clear: the panel morphs the card into whatever the
    /// collapsed pill then measures (the WP-3d machinery; Reduce Motion → instant swap; the
    /// hold remains — it is stillness, not motion). The morph is the celebration; no
    /// interstitial claim beyond the ledger's facts.
    private func setLedger(_ state: TokenLedger.State) {
        let wasComplete = ledgerState.map(TokenLedger.isComplete) ?? false
        ledgerState = state
        model.showLedger(TokenLedger.card(for: state))
        if !wasComplete, TokenLedger.isComplete(state) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                // Re-check: a re-submit (reset) or a late auth verdict during the hold
                // outranks the stale celebration — then the card simply stays, honest.
                guard let self, let s = self.ledgerState, TokenLedger.isComplete(s) else { return }
                self.ledgerState = nil
                self.model.clearLedger()
            }
        }
    }

    /// Runtime token intake (WP-4e HOT START), now driven by the WP-4d ledger card's field
    /// (and still by the DEBUG driver). Steps, in strict order — each gate applying its
    /// ledger event AT the real outcome, never before:
    ///   1. trim paste artifacts (whitespace/newlines);
    ///   2. WALL (`notifications-classic-pat`): `looksLikeClassicPAT` is the SINGLE gate — a
    ///      non-classic shape fails ledger row 1 and returns BEFORE any Keychain write
    ///      (fine-grained/App tokens never get stored, never reach the API); rows 2–3 are
    ///      untouched — they keep describing the ACTIVE token (pending on first run);
    ///   3. store to the Keychain (add-or-update) — a write failure fails row 2;
    ///   4. rows 1+2 check (both events truly happened, in that order — the view staggers
    ///      0/150ms) and the handshake RESTARTS instantly (`.stored` — no animation; a
    ///      restart is not progress) + a fresh live session, NO relaunch; row 3 belongs to
    ///      that session's own generation-stamped outcomes from here.
    /// Never logs the token and never places it in an error (`redacted()` is the only display
    /// form; the token flows only into `KeychainPAT.store` and `GitHubClient`). Returns the
    /// specific outcome so a caller/UI can react. `@discardableResult` for the dev aid.
    @discardableResult
    func submitToken(_ raw: String) -> Result<Void, TokenIntakeError> {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ledgerState == nil { ledgerState = TokenLedger.welcome() }   // defensive: intake always has its card
        guard KeychainPAT.looksLikeClassicPAT(token) else {
            // WALL: reject before any write. Fails row 1 ONLY — rows 2–3 keep describing
            // the ACTIVE token truthfully (fix round, finding 10: a moot paste while a
            // live handshake verifies must not wipe its real receipts, and the running
            // session's outcomes still belong to it).
            applyLedger(.shapeRejected)
            return .failure(.wrongShape)
        }
        let redacted = KeychainPAT.redacted(token)        // shape-only, never the value
        if case .failure(let error) = KeychainPAT.store(token) {
            // The token never appears here — WriteError carries only an OSStatus.
            applyLedger(.keychainWriteFailed(redacted: redacted))
            return .failure(.keychainWrite(error))
        }
        let client = GitHubClient(token: token)
        liveClient = client
        tokenRedacted = redacted
        tokenStoredInKeychain = true                      // provenance: a real store just happened
        tokenShapeInvalid = false
        applyLedger(.stored(redacted: redacted))          // rows 1+2: real receipts (restarts the handshake)
        startLiveSession(client: client)                  // go live with no relaunch (fires .sessionStarted)
        return .success(())
    }

    /// The runtime-intake outcomes (WP-4e). Carries no token — never the secret in a value.
    enum TokenIntakeError: Error, Equatable {
        case wrongShape                                   // failed the classic-PAT WALL at intake
        case keychainWrite(KeychainPAT.WriteError)        // Keychain add/update failed (OSStatus only)
    }

    /// Route each auth-failure REASON onto the ledger card (WP-4d): with a card up, the
    /// failure lands on the exact row that failed (401 → row 3 key-slash, SSO-403 → row 3
    /// lock-shield, wrong shape → row 1 triangle) with its plainspoken remedy. With NO card
    /// up (a runtime failure mid-session, or the launch-caught wrong shape), the SAME card
    /// re-presents — rows 1–2 pre-checked where a stored token makes them true facts — so
    /// the whole error family stays one species. Force-visible is preserved via
    /// `handle(.ledger)` (must-see-now, hide-fx cancelled).
    func showAuthFailure(_ reason: AuthFailureReason) {
        if ledgerState != nil {
            applyLedger(.authFailed(reason))
        } else {
            // Provenance rides along (fix round, finding 7): an env-sourced GITHUD_PAT
            // token was never stored — its card must not fabricate a Keychain receipt.
            setLedger(TokenLedger.runtimeFailure(reason: reason, redacted: tokenRedacted,
                                                 storedInKeychain: tokenStoredInKeychain))
        }
    }

    private func toggleReason(_ reason: String) {
        // The settings card's receipts row rides the radar section with a sentinel id
        // (land-triage F5) — it flips the ClearedStore preference, never a reason key.
        if reason == "justCleared" { toggleShowJustCleared(); return }
        let next = model.surfacePreferences.toggling(reason)
        SurfaceStore.save(next)
        model.setSurfacePreferences(next)                 // no render on this change — fresh rows arrive via…
        scheduler?.setPreferences(next)                   // …the recompute (re-render immediately, no re-fetch)
    }

    private func toggleShowDrafts() {
        let next = model.pulsePreferences.togglingShowDrafts()
        PulseStore.save(next)
        model.setPulsePreferences(next)                   // re-render from cached pulse, no re-fetch
    }

    private func toggleShowStale() {
        let next = model.pulsePreferences.togglingShowStale()
        PulseStore.save(next)
        model.setPulsePreferences(next)                   // re-render from cached pulse, no re-fetch
    }

    private func toggleShowJustCleared() {
        let next = !model.showJustCleared
        ClearedStore.save(next)
        model.setShowJustCleared(next)                    // re-render from the cached buffer
    }

    private func toggleShowHeldBackInbound() {
        let next = model.inboundPreferences.togglingShowHeldBack()
        InboundStore.save(next)
        model.setInboundPreferences(next)                 // re-render from cached inbound, no re-fetch
    }

    private func selectTheme(_ id: ThemeID) {
        ThemeStore.save(id)
        model.setThemeID(id)                              // re-render, no re-fetch
    }

    /// Owner lens: flip the lane's shape (grouped ⇄ flat). Never touches who leads —
    /// the two prefs are orthogonal by ratified amendment.
    private func toggleGroupByOwner() {
        let next = model.lensPreferences.togglingGroupByOwner()
        LensStore.save(next)
        model.setLensPreferences(next)                    // re-render from cached pulse, no re-fetch
    }

    /// Owner lens: adopt the card's drag order as the group/ledger display order
    /// (dogfood 2026-07-14). Persist + re-render, like every lens transition.
    private func reorderLensOwners(_ order: [String]) {
        let next = model.lensPreferences.settingOwnerOrder(order)
        LensStore.save(next)
        model.setLensPreferences(next)                    // re-render from cached pulse, no re-fetch
    }

    /// Owner lens: fold ⇄ unfold one owner — the ONE transition behind all three handles
    /// (ledger line, lens card, gear). BOTH directions stamp this machine's baseline
    /// clock (Codex P2, round 7): unfolding means "I'm looking now", folding means
    /// "I saw them as of now" — either way the ledger's "N new" counts from this
    /// moment. (The hide-first path previously never established a baseline, so a
    /// freshly folded owner could sit silent through later activity until unfolded once.)
    private func toggleFoldedOwner(_ owner: String) {
        let next = model.lensPreferences.togglingFolded(owner)
        LensStore.save(next)
        model.markLensOpened(owner: owner)
        LensStore.saveLastOpened(model.lensLastOpened)
        model.setLensPreferences(next)                    // re-render from cached pulse, no re-fetch
    }

    /// Toggle the pill-style chooser card (gear → "Pill style…"). Open when hidden; a second
    /// invocation with the card up dismisses it (gear-again — the ordinary card lifecycle).
    /// A must-see ledger card (no token / auth error) outranks it — deal with the token
    /// first; the chooser would otherwise stage invisibly behind the ledger's surface.
    /// Card provenance (dogfood 2026-07-14): which pane a card was opened FROM — its
    /// "(back)" returns there. Settings' doors set these; direct entries clear them.
    private var lensOpenedFromSettings = false
    private var pillOpenedFromSettings = false

    private func togglePillStyleChooser() {
        guard model.ledger == nil else { return }
        if model.pillStyleChooser != nil {
            model.clearPillStyleChooser()
        } else {
            pillOpenedFromSettings = false
            model.showPillStyleChooser(.standard)   // show FIRST — a sibling's dismissal
            model.clearLensChooser()                // then reads "navigation", never collapse
            model.clearSettingsCard()
        }
    }

    /// Settings → Pill style door: same show-first order; back returns to Settings.
    private func openPillFromSettings() {
        guard model.ledger == nil else { return }
        pillOpenedFromSettings = true
        model.showPillStyleChooser(.standard)
        model.clearLensChooser()
        model.clearSettingsCard()
    }

    /// Settings → Lens door: same show-first order; back returns to Settings.
    private func openLensFromSettings() {
        guard model.ledger == nil else { return }
        lensOpenedFromSettings = true
        model.showLensChooser(makeLensChooser())
        model.clearPillStyleChooser()
        model.clearSettingsCard()
    }

    /// The settings card (mark-and-settings option B, dogfood-ratified 2026-07-14): the
    /// gear's and the menu's "Settings…" destination. Same lifecycle as its siblings.
    private func toggleSettingsCard() {
        guard model.ledger == nil else { return }
        if model.settingsCard != nil {
            model.clearSettingsCard()
        } else {
            model.showSettingsCard(makeSettingsCard())   // show FIRST (navigation order)
            model.clearPillStyleChooser()
            model.clearLensChooser()
        }
    }

    /// The lens card's descriptor, built from ALL THREE regions the lens governs (WP
    /// 2026-07-26-001, 2026-07-29-001). `showDrafts` gates the draft side at this one edge — with
    /// drafts hidden the lens holds exactly its pre-WP domain, so no folded line and no card row
    /// can claim work the pref is hiding lane-wide. `showStale` does NOT gate here: quiet rows
    /// stay counted behind their caption, so a quiet-only owner belongs in the card either way.
    /// Three doors (gear, eye, Settings) reach the card and all three come through here, so they
    /// can never disagree.
    private func makeLensChooser() -> LensChooser {
        let sections = PulsePresenter.sections(for: model.pulseRows)
        let regions = sections.lensRegions(showDrafts: model.pulsePreferences.showDrafts)
        return LensChooser.make(live: regions.live, drafts: regions.drafts, quiet: sections.stale,
                                prefs: model.lensPreferences, selfLogin: model.selfLogin)
    }

    private func makeSettingsCard() -> SettingsCard {
        SettingsCard.make(surface: model.surfacePreferences, pulse: model.pulsePreferences,
                          inbound: model.inboundPreferences, themeID: model.themeID,
                          launchAtLogin: SMAppService.mainApp.status == .enabled,
                          showJustCleared: model.showJustCleared)
    }

    /// Launch at Login (WP-5i, moved from the menu to the settings card). Never fakes
    /// success: `.requiresApproval` routes to System Settings' Login Items; the card's
    /// check ALWAYS reflects the next real `.status` read, so a failed registration on
    /// an ad-hoc-signed bundle shows unchecked, never a lie.
    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            try? service.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .notRegistered, .notFound:
            try? service.register()
        @unknown default:
            try? service.register()
        }
        // Re-present the card so the check re-reads the real status (equality-guarded).
        if model.settingsCard != nil { model.showSettingsCard(makeSettingsCard()) }
    }

    /// Toggle the owner-lens card (the island eye, the merged "elsewhere" line, or
    /// gear → "Lens…"). Same lifecycle as its pill-style sibling: open when hidden,
    /// second invocation dismisses, a must-see ledger card outranks it, and the two
    /// chooser cards never co-present.
    private func toggleLensChooser() {
        guard model.ledger == nil else { return }
        if model.lensChooser != nil {
            model.clearLensChooser()
        } else {
            lensOpenedFromSettings = false
            model.showLensChooser(makeLensChooser())                         // show FIRST
            model.clearPillStyleChooser()
            model.clearSettingsCard()
        }
    }

    /// Apply + persist a pill-style selection (D-pill config). The card stays up (its radios
    /// refresh via the re-render); the collapsed pill morphs to the new vocabulary on dismiss.
    private func selectPillStyle(_ style: PillStyle) {
        PillStyleStore.save(style)
        model.setPillStyle(style)
    }

    @objc private func accessibilityDisplayChanged() {
        // Reduce Transparency → solid surfaces (applied in the HUD's surface rebuild); the
        // stored theme id is unchanged, so toggling the setting back restores vibrancy.
        model.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        // Increase Contrast (WP-5i) — same notification, same live-tracking shape.
        model.setIncreaseContrast(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }
}
