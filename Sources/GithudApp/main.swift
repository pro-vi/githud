import AppKit
import GithudCore
import ServiceManagement

// `githud probe [--show-items]` — headless one-shot exercise of the live data
// spine (Keychain PAT → GET /notifications → classifier). Runs and exits; no GUI.
if CommandLine.arguments.contains("probe") {
    exit(ProbeCommand.run(
        showItems: CommandLine.arguments.contains("--show-items"),
        showSuppressed: CommandLine.arguments.contains("--show-suppressed"),
        showPulse: CommandLine.arguments.contains("--show-pulse")
    ))
}

// `githud login-status` (WP-5i proof) — a READ-ONLY, one-shot print of
// `SMAppService.mainApp.status`. Never registers/unregisters (no side effect on the user's
// actual login items) — this exists solely so the real `.status` read can be exercised and
// witnessed from the built `.app` bundle (SMAppService needs a real app bundle identity, not
// a bare `swift run` binary) without touching the toggle path the gear menu owns.
if CommandLine.arguments.contains("login-status") {
    let status: String
    switch SMAppService.mainApp.status {
    case .notRegistered:    status = "notRegistered"
    case .enabled:          status = "enabled"
    case .requiresApproval: status = "requiresApproval"
    case .notFound:         status = "notFound"
    @unknown default:       status = "unknown"
    }
    print("SMAppService.mainApp.status = \(status)")
    exit(0)
}

// `githud glyph-proof [dir]` (WP-5g proof) — one-shot render of the status-item glyph set
// (clear/action/critical ± degraded, loading) to PNGs at 1x AND 2x, via the SAME renderer
// the bar uses — so the template ink (geometry, dash pattern, '!' knockout, α .40 loading)
// is witnessable even when a hidden menu bar (full-screen Space) makes a live screenshot
// impossible. Runs and exits; no GUI.
if let index = CommandLine.arguments.firstIndex(of: "glyph-proof") {
    let dir = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1] : "build/glyph-proof"
    exit(GlyphProofCommand.run(directory: dir))
}

// Entry point. githud is a menu-bar agent (.accessory): no Dock icon, no app
// menu, just an NSStatusItem and a floating non-activating overlay panel.
let delegate = AppDelegate()

// `githud --fixture <path>` (H1 radar) and/or `--fixture-pulse <path>` (H2 lane)
// open the island populated from a committed fixture (no PAT, deterministic) — for
// seeing the real layout + visual proof. Either or both may be supplied.
let usingFixture = CommandLine.arguments.contains("--fixture")
    || CommandLine.arguments.contains("--fixture-pulse")
    || CommandLine.arguments.contains("--fixture-inbound")

/// Fail LOUDLY on an unreadable fixture path (review): otherwise `--fixture typo.json`
/// silently suppresses live mode and shows the misleading "no token" island.
func requireFixtureFile(_ path: String, flag: String) {
    guard FileManager.default.fileExists(atPath: path) else {
        FileHandle.standardError.write(Data("githud: \(flag) file not found: \(path)\n".utf8))
        exit(2)
    }
}
if let index = CommandLine.arguments.firstIndex(of: "--fixture"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    requireFixtureFile(path, flag: "--fixture")
    delegate.initialRows = FixtureLoader.rows(path: path, now: Date())
}
if let index = CommandLine.arguments.firstIndex(of: "--fixture-pulse"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    requireFixtureFile(path, flag: "--fixture-pulse")
    delegate.initialPulse = FixtureLoader.pulseRows(path: path, now: Date())
}
if let index = CommandLine.arguments.firstIndex(of: "--fixture-inbound"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    requireFixtureFile(path, flag: "--fixture-inbound")
    delegate.initialInbound = FixtureLoader.inboundRows(path: path)
}
if CommandLine.arguments.contains("--show-drafts") || CommandLine.arguments.contains("--show-stale") {
    delegate.initialPulsePreferences = PulsePreferences(                    // visual-proof affordances
        showDrafts: CommandLine.arguments.contains("--show-drafts"),
        showStale: CommandLine.arguments.contains("--show-stale"))
}
if CommandLine.arguments.contains("--collapsed") {
    delegate.initialCollapsed = true                                       // show the pill gauge, not the list
}
if CommandLine.arguments.contains("--stale") {
    delegate.initialFreshness = .failing(consecutive: 3, ageSeconds: 480)  // visual proof of the caution cue
}
if let index = CommandLine.arguments.firstIndex(of: "--theme"),
   index + 1 < CommandLine.arguments.count,
   let id = ThemeID(rawValue: CommandLine.arguments[index + 1]) {
    delegate.initialThemeID = id                                            // e.g. --theme geist-mono
}
// WP-4d cold-start proof aid (DEBUG-only, opt-in): pretend no token exists so the welcome
// ledger card can be witnessed live on a machine whose Keychain/env DOES hold one. Stripped
// from release builds (build-app.sh compiles -c release), mirroring GITHUD_DEV_SUBMIT_TOKEN.
var devPretendNoToken = false
#if DEBUG
devPretendNoToken = ProcessInfo.processInfo.environment["GITHUD_DEV_NO_TOKEN"] != nil
#endif

if !usingFixture, !devPretendNoToken, let resolved = resolvePAT() {
    // Default: LIVE mode. Read the classic PAT (GUI uses Keychain w/ a one-time
    // Always-Allow; GITHUD_PAT is the headless path) and poll /notifications + pulse.
    // Validate the SHAPE up front (review F8): a fine-grained / malformed token would
    // otherwise be accepted and 403 forever with no guidance. The Notifications API
    // needs a classic ghp_ token — catch the wrong shape now and show the setup card.
    if KeychainPAT.looksLikeClassicPAT(resolved.token) {
        delegate.liveClient = GitHubClient(token: resolved.token)
        // The redacted display form ("ghp_•(40)") rides along so a runtime auth card can
        // show row 1's true receipt without a second Keychain read (WP-4d) — and so does
        // PROVENANCE: an env-sourced token was never stored, and the card's row 2 must
        // say "from environment", never a fabricated "stored" receipt (fix round).
        delegate.tokenRedacted = KeychainPAT.redacted(resolved.token)
        delegate.tokenStoredInKeychain = resolved.fromKeychain
    } else {
        delegate.tokenShapeInvalid = true
    }
}

/// GITHUD_PAT env (headless/dev) → else the Keychain classic PAT (the GUI app's
/// path; prompts once for Always-Allow). Never logged. Carries WHERE the token came
/// from — the ledger card renders provenance, not assumption.
func resolvePAT() -> (token: String, fromKeychain: Bool)? {
    if let env = ProcessInfo.processInfo.environment["GITHUD_PAT"]?
        .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
        return (env, false)
    }
    if case .success(let token) = KeychainPAT.read() { return (token, true) }
    return nil
}

let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
