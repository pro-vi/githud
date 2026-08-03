# githud — topology

**What this is.** The rules that make githud's surfaces composable: the operators the
interface is built from, and the laws they must obey. It describes *structure*, not features.

**What this is not.** Not a feature list — that's the [README](../README.md). Not a history of
decisions — that's `docs/plans/`, which is append-only and correct only about the day it was
written. Not a component library; githud has ~5 primitives, not a catalogue.

**Why it exists.** Features are the *output* of the system and change on every ship, so any
document enumerating them is stale on landing. The rules underneath don't. This is also the
document an outside contributor needs most: not *what githud does*, but **what they may not
break**.

**The one rule that keeps it alive:** a change that alters a law must alter that law's line
here, in the same pull request. Nothing else in this document is load-bearing against drift.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **row** | One actionable thing — a notification, an inbound item, one of your PRs. The atom. Every row opens on GitHub — where no subject maps cleanly the link falls back to the repository page, which is a valid destination rather than a dead one. githud never acts on your behalf. |
| **lane** | A question the island answers. Three today: **Needs you**, **Inbound**, **Your PRs**. |
| **region** | A classification of a lane's rows by fact, not by preference. Disjoint and total: every row is in exactly one. |
| **surface** | Somewhere rows or counts are rendered: the lane, a ledger line, a card, the menu-bar glyph, the collapsed pill. |
| **count** | The residue an operator leaves behind when it hides rows. Counts are the honesty mechanism; see **L1**. |

---

## Laws

Numbering is stable. Reordering preserves numbers in place; a retired law leaves a gap. Same
rule as `U-ID`s in `docs/plans/`.

**L1 — conservation.** Every row **admitted to a lane** lands exactly once: as a visible row,
inside a subordinate run, in a terminal region, or inside a count. Hiding is never dropping.

> *Fold, not filter.* This is the oldest rule in the project and the one every other law
> serves. A surface that hides work without counting it is a **miss**, and a miss is the only
> thing that kills a tool like this.

**L1's domain is rows, and two boundaries sit above it.** Stating them is not a weakening — a
law whose edges are unwritten gets read as either false or unbounded, and both are worse.

- **Admission.** Signal and trust filtering decides what becomes a row at all. This is
  githud's central act — roughly fifty notifications become a handful — and suppressed threads
  leave **no count on the glass**. Their audit path is deliberately external: the footer link
  to the full GitHub inbox, and `probe --show-suppressed`. Conservation cannot govern this
  boundary, because the whole point is that the firehose is not conserved. What governs it
  instead is the miss doctrine: suppression must always be *auditable*, never silent.
- **Input gating.** One preference removes a region from a lane's input rather than from its
  rendering (see **E1**). Rows gated out that way are not in the lane, so they are not in
  L1's domain either.

**L2 — agreement.** Surfaces showing the same underlying set agree on that set — except where
**E2** applies — and on its order **within each partition**. If the lane, a ledger line, a card
and a menu disagree about which owners exist, at least one of them is lying.

> The partition qualifier is load-bearing, not a hedge. The lane sinks folded owners below
> every leading one, so a folded owner the user dragged to the top renders near the bottom of
> the lane while the card still lists it first. Both are right: the card shows *configuration*,
> the lane shows *what is on screen now*. They agree on the set, and on the order within
> leading and within folded — never on a single global order.

**L3 — linearization.** For every row the key session governs, keyboard traversal order equals
render order, exactly, and a selection can never land on a row the lane does not draw.

> A row that is hidden — input-gated, collapsed, or folded away — is not "unreachable"; it is
> not drawn at all, and **L1** guarantees its caption or ledger count stands in its place. The
> only rows *drawn but not walked* are departure receipts, which is **G3**.

**L4 — no zero.** A surviving count never renders as zero. An operator that would leave `0`
behind renders nothing instead — a zero count is noise wearing the costume of honesty.

**L5 — fail closed.** A claim githud cannot back is not made. Absent CI checks are not
"passing"; an unconfirmed all-clear is not a check-mark. Where truth is unavailable, the
degraded vocabulary is used rather than the confident one.

---

## Operators

Each operator transforms rows into a smaller rendering while satisfying **L1**. `scope` names
where it applies today — several have not generalized across lanes yet, and saying so is more
useful than implying a symmetry that isn't built.

### `collapse(set) → caption`
*scope: all lanes.* A default-off set renders as one line carrying its count and a verb:
`3 gone quiet (show)`, `2 from bots & drafts (show)`, `2 just cleared (show)`. The caption is
both the honesty and the affordance.

The domain is a **set**, not a region: quiet, drafts and bots-and-drafts are regions of their
lane's rows, but *just cleared* is a set of departed ghosts that have already left the lane, so
"region" would not cover it.

**Revealed, the form depends on shape, and the verb is always present.** A terminal set gains a
section header with `(hide)` on its right edge. A **grouped tail** keeps its caption and flips
the verb in place — `2 gone quiet (show)` becomes `2 gone quiet (hide)` — so a tail's two states
are one object rather than two different controls. Both flip the same lane-wide preference: any
group's verb toggles every group's quiet, exactly as the gear does. There is no per-group reveal
state, and that is a named non-goal.

> `(hide)` therefore takes exactly two forms: a section header's right-edge control, or a
> caption's trailing verb token. It never appears as a third kind of thing. Drafts have neither —
> their tail is an uncontrolled label, per **E1**.

**A count is not always the same promise.** Collapsible sets come in three kinds, and knowing
which you are designing decides whether a count belongs:

| Kind | Example | What its count means |
|---|---|---|
| outstanding work | gone quiet, bots & drafts | a **debt** — someone is waiting, and the count is what stops it being a miss |
| audit receipt | just cleared | a **trail** — nothing is owed; the count proves githud did not lose something silently |
| your own WIP | drafts | **nothing** — only you can act on it, and only when you choose to |

> **⚠ EXEMPTION — drafts (E1).** Hidden drafts leave **no** caption; they are fully invisible.
> The mechanism is the real distinction: drafts gate at the lane's **input**, every other
> collapsible set gates at its **rendering**. The rationale is the table above — a draft is the
> only kind whose count would promise nothing, so it is the only set that may vanish outright.

### `fold(owner) → ledger line`
*scope: Your PRs.* An owner the user has folded renders as one counted line instead of its
rows — `acme · 4, 5 drafts, 2 gone quiet, 1 new`. Clause order is fixed; each clause is
suppressed at zero (**L4**). The whole line is the click target and unfolds the owner.

### `tail(region) → subordinate run`
*scope: Your PRs.* A region rendered *under* its owner group rather than as a peer lane, after
the group's live rows. **A tail never joins its parent's sort** — it is positional. This
matters because a draft with failing CI and a long-abandoned conflicted PR both roll up to
`blocked`; sorting either into the live rows would float the least urgent work to the top.

### `sink(owner)`
*scope: Your PRs.* An owner with no live rows ranks below every owner that has some — but an
explicit user ordering outranks the sink, so an owner dragged to the top genuinely leads.

### `merge(folds) → one line`
*scope: Your PRs.* More than two folded owners merge into a single `elsewhere · N` line, whose
counts sum every region across every owner it stands for. Its click opens the lens rather than
unfolding, since one owner cannot be inferred from a merged line.

---

## Lane: Your PRs

The only lane specified at this layer today. The other two are named below, honestly unfinished.

```
axes         region = live | draft | quiet      classification by fact; disjoint, total
             owner  = partition by login        identity; discovery-ordered

composition  owner × { live, draft, quiet }     every owner holds every region

order        GROUPED — fold partitions first: every leading group renders above
             every folded ledger line, whatever the user's ordering says (see L2).
             Within each partition: placed owners first in their order, then
             unplaced owners by lead live row, tail-only owners last.
             Within a group: rows → draft tail → quiet tail.

             FLAT — live rows, then folded ledger lines, then terminal drafts,
             then terminal quiet. The VISIBLE ROWS ignore owner order entirely
             and keep their state order: the drag order is a GROUP order, and a
             flat lane has no groups to order. The LEDGER LINES still follow it,
             because a ledger line is not a row — it stands for an owner, and
             owners are what the order ranks.

shape        grouped when the user opts in AND ≥2 LEADING owners have content
             (leading = not folded — folding down to one leading owner drops the
             lane to flat, and its ledger lines still print)
             flat shape has no groups to tail, so the tails render as terminal sets —
             same order: drafts, then quiet
```

**Preferences gate at different layers, and the asymmetry is the design.**

| Preference | Gates | Because |
|---|---|---|
| show-drafts | the lens's **input** | no caption ⇒ hidden means *absent*; a folded line must not claim drafts the preference is hiding lane-wide |
| show-quiet | the group's **rendering** | a caption ⇒ hidden means *counted*; gating the input would take a quiet-only owner's count off screen along with its rows, breaking **L1** |

---

## Lanes: Needs you, Inbound

**Needs you** answers *"what needs my action right now?"* — threads that survive signal and
trust filtering, urgency-ranked, with a `just cleared` receipt band for departures.
**Inbound** answers *"what's at my door?"* — open issues and PRs others opened on repos you
own, waiting-longest first, with bot and draft arrivals held back to a count.

Both use `collapse`. Neither uses `fold`, `tail`, `sink` or `merge` — the owner lens has not
generalized past Your PRs. Whether these lanes should share those operators or merely rhyme
with them is **an open question, not a settled one.** They are not specified here because
they have not been designed at this layer; an empty section is more honest than an invented one.

---

## Exemption register

Every carve-out from a law or an operator's normal behaviour, with its reason. **This list
staying short is the health metric for this document.** A growing register means the operators
are wrong and should be re-cut — it does not mean the register should grow.

| # | Operator | Exemption | Reason |
|---|---|---|---|
| E1 | `collapse` | drafts gate at **input**, not rendering — hidden means absent, no caption | A count is a debt; a draft is your own WIP, and only you can act on it |
| E2 | `fold` / **L2** | a folded owner with nothing left in the lane stays listed on the card, so the card's owner set can legitimately exceed the lane's | A fold must stay **releasable**. An owner folded and then emptied — by hiding drafts, or by its work landing — would otherwise be folded forever with no way to reach it. The card shows configuration; the lane shows what is on screen |

### Known gaps

Not exemptions — these are unresolved, and listing them keeps them from being mistaken for
intent. Each needs a decision, not a rationalisation.

| # | Gap | Status |
|---|---|---|
| **G3** | A revealed departure receipt is clickable and VoiceOver-pressable, but the ⌃⌥G key session does not traverse it — reachable by pointer, not by keyboard. | **Open.** Found by this document's audit. Either the walk includes them or L3's narrowing becomes deliberate; today it is neither. |

> **Closed: G1** (*"grouped quiet has a way in but no way out"*). The tail's caption now flips its
> verb instead of becoming an uncontrolled label. The fix that was *not* taken is worth recording:
> a right-edge `(hide)` on the tail, which would have been the app's first such control unbound
> from a section header. The caption family was already the ratified grammar at group scope, so
> flipping the verb added no new pattern. Found by this document's audit; two code reviews of the
> change that introduced it had passed clean.

> **Retired: G2** (*"a receipt with no URL cannot be opened"*). Withdrawn — the field is
> optional in the type, but the single production construction always assigns a URL, falling
> back to the repository page when no subject maps cleanly. The nil is unreachable. Recorded
> because the mistake is instructive: **an optional type is not evidence of a reachable state.**

---

## Demonstrations

The primitives are **verbs**. A still image can show folded and unfolded but cannot show that
the count *survives*, which is the actual law. These slots are named and stable; the prose here
never changes when the visuals change, only when a law does.

| Slot | Demonstrates | Status |
|---|---|---|
| `fold-conserves` | fold an owner; its rows leave, its counts appear | not built |
| `collapse-counts` | the three captions, and E1 beside them | not built |
| `tail-never-sorts` | a blocked draft staying below a ready live row | not built |
| `walk-equals-render` | keyboard traversal overlaid on render order | not built |
| `merge-valve` | a third fold collapsing three lines into `elsewhere` | not built |
| `sink-order` | a tail-only owner's rank, and a dragged one outranking it | not built |

---

## Changing this document

1. **A pull request that changes a law changes its line here.** That is the forcing function;
   without it this becomes another stale document within a month.
2. **No file/line citations, no "current state" section.** Both rot on contact. `docs/design/specs/`
   is the cautionary example — its snapshots describe a product that no longer exists.
3. **Laws are testable, and are tested.** All five are graded by the Core suite — including L5,
   whose fail-closed gate is pinned by a state matrix. When a law changes, its assertions change
   in the same commit.
4. **Add an exemption only with its reason, and only in the register.** An undocumented carve-out
   is indistinguishable from a bug. If it has no reason yet, it is a **gap**, not an exemption —
   put it in *Known gaps* and leave it uncomfortable.
5. **Keep the narrative short.** Comprehensiveness is what kills documents like this one.
