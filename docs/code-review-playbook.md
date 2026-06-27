# Code-review playbook

How to run a **deep, comprehensive, resumable** review of this repository — and re-run
it from zero later (e.g. every 6–12 months, after major change, or to re-review with a
newer AI model). The playbook is model-agnostic; a future reviewer follows it without
needing the conversation that produced it.

## Why this exists

Asking one agent to "review everything" (quality, duplication, a11y, tests, docs, …) in
one pass produces *a little bit of everything*: it grabs the most visible issue under
each heading and never walks any concern to the bottom. This playbook fixes that by
giving **one narrow lens to one agent at a time** — depth over breadth — and by keeping
all progress on disk so a multi-day review survives token-limit interruptions.

## Principles

- **One lens per agent.** No agent juggles concerns; the only way to produce volume is
  to go deep on its single lens.
- **Read-only against one frozen commit.** All lenses review the same baseline SHA.
  Implementation happens only after triage — never interleaved (or findings reference
  line numbers that have moved).
- **Durable on disk; compute is disposable.** A manifest + per-unit findings files are
  the source of truth. Any agent or driver session can be killed and resumed.
- **You decide.** Reviewers never suppress a finding for effort; they record effort +
  risk so you can triage. Accept/reject/defer is a human step.
- **Repo-agnostic by design (anti-staleness).** This playbook names things by *role/topic*,
  never by drift-prone specifics. Concrete bindings — file paths, ARCHITECTURE §-numbers,
  current project-state deferrals, the filled dispatch template — live in `current.md`,
  regenerated and **verified against the live repo at round start**. Resolve section numbers
  via AGENTS.md's reference index, never from memory of this doc.
- **Scope is a per-round parameter.** A round covers the whole repository, or a diff (changes
  since a ref/tag/version, or specific commits) — recorded in `current.md`. A diff scope still
  greps the whole repo for cross-references (duplication/architecture need it).

## The 10 lenses

Run order is **structural → surface** (a structural fix can delete code that a spelling
finding was written against). Concerns map to the full original review list; nothing is
dropped.

| # | Lens | Concerns covered |
|---|------|------------------|
| 1 | Architecture, best-practices & convention conformance | overall quality, best practices, clean architecture, audit vs the conventions list, + greenfield-rethink bucket |
| 2 | Simplification | duplication, dead/stale code, complexity, readability, maintainability |
| 3 | Correctness, edge-cases & robustness | logic bugs (scoring, seat derivation, doubling, migrations), untrusted import-path (ZIP/JSON) security |
| 4 | Performance | rebuild/startup/jank only, scoped to the app's data scale |
| 5 | Flutter/Dart idioms + Material 3 | effective-Dart, Flutter guidelines, M3 against the pinned version |
| 6 | Accessibility | beyond the guidelines gated by the a11y test; WCAG 2.2 AA |
| 7 | Tests | coverage (lcov) + test design quality |
| 8 | Docs, comments & language | drift / gaps / quality in the project docs, comment drift, bilingual spelling & grammar |
| 9 | Project & build health | dependency health (outdated/unmaintained), CI workflows, tooling, analyzer config. **Any version / release-date / runner- or SDK-availability claim — "does version X exist", "is it the latest / outdated", "what runner/Ruby/Gradle/Xcode is current" — MUST be grounded in a fetched changelog / release-notes / registry source and cite it, NOT model memory** (same discipline as #10): training lags the real ecosystem, so a missed release can turn a perfectly valid pin into a phantom "blocker". |
| 10 | Modernization (Dart/Flutter/deps) | adopt newer language/framework/package features not yet used. **Grounded in changelogs/release notes, NOT model memory** (training lags the pinned toolchain — each finding cites the source proving the feature's version). Per-round look-back floor; upper bound = pinned toolchain. Dedup: #5 = follow current idioms · #9 = outdated/unmaintained · #10 = adopt new features. |

*File paths, §-numbers and lens specifics above are illustrative — verify against the live
repo at round start. This round's resolved bindings, scope, and project-state deferrals (e.g.
intentional non-localization, untracked scratch out of scope) live in `current.md`.*

## Pipeline — artifacts & timing

1. **Per-unit findings** — `findings/<UNIT>.md`, schema below. Raw, atomic, resumable output.
   **Each unit numbers in its own distinct key namespace** — prefix every id with a unit tag
   (e.g. `CORR-import-001`, `CORR-state-001`), never bare `CORR-001`. Two units reviewing
   different files otherwise both emit `CORR-001` for unrelated things, so a later cross-reference
   to "CORR-001" is ambiguous about which unit/source it means. The bare `<LENS>-<NNN>` namespace
   is **reserved for the consolidated file** (step 2), assigned there exactly once.
2. **Per-lens consolidation** — when a lens finishes, merge its unit files into one
   `findings-<LENS>.md`: assign the **canonical, globally unique `<LENS>-<NNN>` IDs here** (the
   only place bare numbers live — no more per-unit collisions), a leading **sortable summary
   table** (ID · severity · effort · category ·
   location · title · status), then the full finding blocks, each keeping a `Source:` backref
   to its unit. Derived/regenerable — the unit files stay the source of truth.
   The merge — and the other mechanical passes below (the reconciliation location-join, the
   triage mirror) — run via small **per-round helper scripts**: kept with the round's ephemeral
   working state, regenerable from the descriptions here, never committed. The implementation
   language is incidental (Python is merely convenient; reimplement in whatever the round has on
   hand). The playbook describes what each helper *does*, not how it's written.
3. **Cross-lens back-reconciliation — after consolidation, before triage.** A lens stays in
   its own scope *while reviewing*, but the same defect can still surface under several lenses
   from different angles, and an **already-triaged** decision from an earlier lens can change —
   or retire — a new finding. So before you triage a lens, cross-check every new finding
   against **all prior lenses** by reading their consolidated **`findings-<LENS>.md`** files —
   the summary table is the complete per-finding record (**ID · Location · Title · Status**),
   because the consolidation helper mirrors each triage decision back into it. Match on **both**
   `file:line` *and* meaning: a shared location is a near-certain tie, a shared concept a likely
   one. (Do **not** reconcile against `triage-<LENS>.md` alone — it carries the decision but no
   locations, so same-site duplicates slip through silently; `triage-<LENS>.md` stays
   authoritative for the *decision*, the consolidated file is the *matching surface*.) Also scan
   open `carry-forward.md` rows. For each new finding, classify and annotate:
   - **duplicate** — the same issue a prior lens already decided (possibly from another angle):
     dedup-by-reference to that ID; inherit its decision instead of re-deciding from scratch.
   - **superseded / subsumed** — a prior *accepted* change already fixes or deletes this (the
     planned refactor removes the code, or makes the recommendation moot): mark "superseded by
     `<ID>`"; fold into that plan-chunk, don't double-count the effort.
   - **redirected** — a prior decision changes what the *right* recommendation is here (e.g. an
     earlier lens chose to **keep** a seam this finding wanted to remove, or vice-versa):
     rewrite the recommendation to fit the decided direction before the human sees it.
   - **conflict** — this finding contradicts a prior decision: surface the tension *explicitly*
     so triage resolves it, rather than silently shipping two opposite plans.
   - **reopen** — this finding is new evidence that a prior *already-decided* finding should be
     revisited: flag it back to that lens's triage. Rare, but it is the only channel by which a
     later lens can correct an earlier call — don't suppress it for tidiness.
   - **confirm** — this finding *verifies* a prior decision is correctness-safe (no action, but
     it de-risks that prior item's plan). Worth annotating so the plan inherits the assurance.
   Record the result **per finding** in a durable `reconcile-<LENS>.md` map — one line per tied
   finding, and **the first field is a single finding ID** (the join key the consolidation helper
   matches on exactly): `<ID> | <relationship> | <ref-ids> | <note> | <post-reconciliation recommendation>`.
   Never group several IDs into one row's first field (no `A, B, C | …` / `A/B | …`); a tie that
   spans several findings is one row *each*.
   The consolidation helper reads it and **injects the annotation into `findings-<LENS>.md`
   itself** — a `Prior-lens` column in the summary table, plus two bullets placed **directly
   below each finding's own `Recommendation`** (just before `Status`): a
   `- **Prior-lens reconciliation:**` line (the relationship + refs + note) and a
   `- **Post-reconciliation recommendation:**` line (the **updated recommendation given the
   reconciliation** — what to actually do now that the prior decision is accounted for, e.g.
   "fold into chunk X, no standalone change" / "merge into ID Y" / "accept, orthogonal to Z").
   Below-Recommendation (not at the top) is deliberate: the reader sees the reviewer's original
   recommendation first, then how the cross-lens context revises it. The map is the durable
   source; the consolidated file is regenerable, so re-running consolidation re-injects the
   annotations (they never go stale). **No silent drops:** because the helper keys on the exact
   first field, a row it can't parse as a single ID would vanish *without warning* — so the helper
   must **report** every entry-shaped line (≥4 `|`-fields beginning with a `<PREFIX>-<n>` token)
   whose first field isn't a recognized single ID, never skip it quietly. Confirm the helper's
   consumed-row count matches the number of entries you wrote.

   **Mechanical backstop — additional to the scan-by-eye pass, never a replacement.** After the
   judgment pass, run a **location-overlap join** (another per-round helper): parse every
   finding's `Location` across all consolidated `findings-*.md`, then report every cross-lens
   pair whose `file:line` ranges overlap but which no `reconcile-`/`triage-`/`carry-forward`
   ledger already references — deterministically surfacing same-site ties the eye can miss. It is
   high-recall / low-precision: most hits are benign co-locations (a broad structural finding
   overlapping a narrow one; a correctness finding that's already `closed` co-located with a
   dedup), so the human still classifies each. It catches false negatives; it does not decide.
   Triage its candidates alongside the judgment-pass ties.

   This is the **backward** counterpart to carry-forward (which seeds *forward*); together they
   keep the lenses coherent in both directions. Reconciliation reads only durable on-disk files
   (the consolidated `findings-*.md` plus the `triage-`/`reconcile-`/`carry-forward` maps), so it
   survives a session kill like everything else. `findings-*.md` is a regenerable *view*: keep it
   current — always re-run consolidation after a triage edit before reconciling against it.
   Locations are frozen-baseline so they never drift; only the mirrored `Status` could lag a
   missed re-consolidation.
4. **Triage — per lens, right after reconciliation.** You mark each finding
   `accepted`/`rejected`/`deferred` with a note in the durable **`triage-<LENS>.md`** table
   (`| ID | Status | Note |`), now informed by the reconciliation. Per-lens keeps the set
   manageable and lets later lenses reference earlier decisions.
   `triage-<LENS>.md` stays **authoritative**, but the consolidation helper **mirrors each
   decision back into `findings-<LENS>.md`** so that file is one complete overview (finding +
   reconciliation + decision): the summary-table `Status` column shows the decision, the
   finding's `- **Status:**` field is updated from `open` to the decision, and a
   `- **Triage:** **<status>** — <note>` bullet is injected **after the Post-reconciliation
   recommendation** (just before `Status`) — so a finding reads reviewer's recommendation →
   cross-lens revision → final decision + rationale. Re-running consolidation re-mirrors the
   latest decisions (never stale); undecided findings stay `open` with no `Triage:` bullet.
5. **Plan + implementation — deferred and global.** Only after *all* lenses are reviewed and
   triaged: derive the plan from accepted findings (grouped by locality, structural-first,
   split into session-sized chunks), then implement. Never implement mid-review — line numbers
   would move under the lenses not yet run.
   - **Coverage gate — before finalizing the plan.** Every `accepted` (and `deferred`) finding
     across *all* `triage-<LENS>.md` must map to a plan chunk **as a fix**, not merely as an
     xlens/coordinate/redirect mention. Cross-check each finding's `Plan-chunk:` field: any
     accepted finding whose only plan reference is another finding's coordinate/redirect note is
     an **orphan** (it has no chunk that actually lands it). Reconcile every orphan explicitly —
     fold it into the most natural chunk, schedule it standalone, or consciously skip/defer with
     a one-line rationale — so none is silently dropped. A redirect tie (test written against a
     fix's POST-state) only holds if that fix is itself scheduled; if it isn't, the fix is the
     orphan. Re-run this gate after any triage edit, since a late accept can add an orphan.

### Finding schema

```
### <ID> — <one-line title>      ID = <LENS>-<nnn>, LENS ∈ {ARCH,SIMP,CORR,PERF,FLTR,A11Y,TEST,DOCS,BLDH,MODN}
- **Lens / Category:** <lens> / <maps to a concern, e.g. "duplication" | "import-security">
- **Location:** path/file.dart:LL   (+ second location for duplication)
- **Severity:** blocker | major | minor | nit
- **Effort:** S (<1h) | M (hours) | L (day+) | XL (structural)
- **Risk of fixing:** low | med | high   (regression / blast-radius)
- **Greenfield?:** yes/no — would a from-scratch build avoid this?
- **Evidence:** verbatim quote; for dead-code/dup, the grep proving the claim
- **Finding:** what's wrong and why it matters
- **Pros of fixing:** …
- **Cons / risk:** …
- **Recommendation:** …
- **Status:** open        <!-- → accepted | rejected | deferred -->
- **Plan-chunk:** —       <!-- filled when grouped into the plan -->
```

## Cross-lens carry-forward (forward direction)

A finding raised under one lens sometimes belongs to **another** lens's decision (e.g. a
Simplification finding that's really a correctness call). Do NOT rely on the target lens
re-discovering it — that's how items get silently dropped. Register it, and **seed** it.
(The **backward** direction — checking a new lens's findings against *already-triaged* prior
decisions — is pipeline step 3, "Cross-lens back-reconciliation". Carry-forward pushes an item
to a future lens; back-reconciliation pulls prior decisions onto the current lens. Run both.)

- **Register:** `carry-forward.md` — every carried item with source ID, target lens, type,
  and the question.
- **seed (guaranteed inclusion):** when the target lens runs, its `seed` items are injected
  directly into `findings-<LENS>.md` (origin noted) so they appear in that lens's consolidated
  list and get triaged like any other finding — independent of whether a reviewer re-finds
  them. The relevant unit's reviewer is also briefed so it adds depth without duplicating.
- **dep (planning-time condition):** "if lens X doesn't flag Y, do Z" — checked when building
  the implementation plan, not seeded as a finding.
- **Discipline:** every cross-lens reference made during triage (a "carry to #N" / "belongs to
  lens #N" / "loop in lens #N" note) MUST be entered in the register in the *same step* you
  write the triage note — a triage-file note alone is not durable. Audit periodically: every
  cross-lens mention in a triage ledger should have a matching register row.

## Resumable execution model

A review can span days and be killed by token limits at any point. Resumability comes
from disk, not from any session staying alive.

- **`progress.md` is the source of truth.** Resume by reading it and dispatching the next
  `[ ]` unit. Legend: `[ ]` pending · `[~]` dispatched · `[x]` done.
- **Unit = work + checkpoint.** Each unit is reviewed by one agent that writes ALL its
  findings to `findings/<UNIT>.md` and ends the file with the trailer
  `<!-- UNIT COMPLETE -->` as its final action, then the unit flips to `[x]`.
- **Atomic per unit.** A unit interrupted before the trailer stays `[ ]`/`[~]` and is
  **fully re-run (overwrite)** — never a partial or duplicated finding.
- **Serial dispatch, disposable driver.** One unit in flight keeps atomicity trivial. If
  the driver session dies, the next one reads `progress.md` and continues.
- **Survives main-session auto-compaction.** All review state is on disk (manifest, per-unit
  findings, this playbook, the dispatch template in `current.md`) — a session-limit pause keeps the
  conversation, a compaction summarizes it, but neither loses progress. A compacted or fresh
  driver re-reads the files and continues identically, no conversation history needed.
- **Reconcile from the disk trailer, NOT the agent's return status.** An agent can finish
  writing its findings file (trailer included) and *still* report an error or "session limit /
  0 tokens" on the way back — the failure is in the return trip, not the work. Observed in
  practice. So on resume, decide done/not-done purely by whether `findings/<UNIT>.md` ends
  with `<!-- UNIT COMPLETE -->`; never re-run (or discard) a unit based on the agent's reply.

## Unit sizing & throughput (the key tuning decision)

The binding constraint is **wall-clock throughput**, not token cost. Plans typically cap
usage with a rolling session window (you do ~one window of work, then wait for it to
reset) plus a longer-period cap on top. The exact window length, the longer cap, the
per-subagent output-token cap, and any per-agent runtime limit all **depend on the plan
and tooling in force — determine them at initiation (runbook step 1); none are assumed
here**, because the person or model running a future round may have different ones.

```
wall-clock ≈ total_tokens / (resumes_per_day × tokens_per_window)
total_tokens ≈ fixed_review_work + (num_units × per_spawn_rampup)
```

Each spawned agent starts **cold** and re-pays a fixed **ramp-up** (oracle docs + lens
instructions + reading its files) before producing anything. Review work is fixed; the
only lever on total tokens — and therefore on wall-clock — is the **unit count**. So:

- **Prefer larger units** to amortize ramp-up → fewer tokens → fewer windows → faster.
- **Capped by two ceilings — verify both at initiation:** (1) *depth/context* — beyond
  some number of dense files, one agent can't hold enough to stay exhaustive and starts
  skimming (a stronger model raises this number; treat any file count here as a starting
  heuristic and calibrate it at the pilot); (2) *output cap* — the runtime usually
  truncates a subagent's output at a fixed token limit, so a unit's full findings must fit
  under whatever that limit currently is (also depth-protecting: too big a unit forces
  truncation = skim). Check too whether the tooling imposes any per-agent wall-clock
  runtime limit. Hitting the account token cap *mid-unit* only pauses you until reset; the
  atomic per-unit re-run handles it on resume.
- **Cut ramp-up further:** give each agent only the ARCHITECTURE.md *sections* its lens
  needs (use the reference index in AGENTS.md), not the whole file.
- **Chunk by size (lines/tokens), not file count.** In practice a unit's token cost is
  dominated by a fixed *ramp-up* (oracle reading + grep sweeps + reasoning) that stays
  roughly flat across a wide size range — cost barely tracks lines and does NOT track file
  count (ten 30-line files ≈ one 1,400-line file). So the only real lever on total tokens
  and wall-clock is **unit count**: make units as large as the *depth ceiling* allows, to
  amortize the ramp-up. Budget by lines; give any file above the budget its own unit; let
  low-density data/boilerplate run larger (fewer findings per line). Find the depth ceiling
  at the pilot — push the largest *dense* file through one unit and check its coverage
  table for skim; the atomic per-unit redo makes probing a bigger size safe.
- **Recalibrate the budget per lens — altitude differs.** Line-by-line lenses
  (Simplification, Correctness) read every line, so they cap lower. Higher-altitude lenses
  review relationships, not lines: Architecture can take whole subsystems/directories per
  unit (multiples of a line-by-line budget); Docs go by document; build-health is 1–2 units
  total. Each lens gets its own 1-unit pilot before fanning out.

**Calibrate with a pilot, don't guess.** The pilot measures per-unit token cost and
whether depth holds, so you can set unit count to hit your wall-clock target *and* verify
total spend fits under the weekly cap before fanning out.

## Rules for every reviewer (anti-skim)

- Own exactly one lens. Ignore issues outside it — another lens owns them.
- Be **exhaustive, not illustrative**: when you *do* raise an issue, enumerate every instance
  of it, never "e.g. …". (Exhaustive about *issues* — this is not licence to file a finding per
  clean check; see the next rule.)
- **Findings are issues, not receipts.** A numbered finding must be a real defect, risk, or
  actionable improvement. Do **NOT** number "checked — verified correct / no defect / no action
  needed" observations: each one still costs a human read at triage, so they are pure noise.
  This bites hardest on the *is-it-correct?* lenses (Correctness, Performance, Accessibility),
  where most checks come back clean — those clean results go in the coverage table / Notes, not
  the numbered list. Never instruct a reviewer to "record that you scrutinised X"; ask for a
  verdict in the *reply*, not a finding. A unit that legitimately finds few/no issues should
  emit few/no findings — that is a good outcome, not a gap to pad.
- End the unit file with a **coverage table** (every in-scope file marked reviewed + finding
  count, so skimming is auditable) and, optionally, a short **unnumbered `## Notes`** section
  summarising notable things checked-and-found-clean — so exhaustiveness is auditable *without*
  inflating the numbered findings.
- Anchor every finding to `file:line` with a verbatim quote. Dead-code/duplication
  require grep evidence (zero references / both locations).
- Read the oracles first: AGENTS.md + the relevant ARCHITECTURE.md sections (resolve numbers
  via AGENTS.md's reference index). Do NOT re-raise a documented invariant or accepted deferral
  (the invariants / deferred-upgrades sections) — reference its ID instead.
- Record effort + risk; never omit a finding for effort.
- Dedup by reference: if a finding already exists, cite its ID rather than re-raising.

## Per-unit dispatch prompt

What every dispatch must contain is already specified above in **Rules for every reviewer**
(one lens · read-only · exhaustive · file:line + grep evidence · finding schema · coverage
table · the `<!-- UNIT COMPLETE -->` trailer). To keep this playbook repo-agnostic, the
**filled, ready-to-send template — with this round's resolved §-numbers, paths and deferrals —
lives in `current.md`** and is regenerated at round start (so it can't go stale). Build it
there by binding the placeholders to the live repo: `{LENS}`, `{LENS-SCOPE}`, `{SHA-or-range}`,
`{UNIT}`, `{FILES}`, oracle `{SECTIONS}` (resolved via AGENTS.md's index), `{EXTRA-DEFERRALS}`,
`{PREFIX}`, and the findings path.

**The template must INLINE the full finding schema verbatim** — the **Finding schema** block
above, copied into the dispatch with its bullets kept SEPARATE (`Finding` · `Pros of fixing` ·
`Cons / risk` · `Recommendation` are four distinct bullets, never collapsed into one
`Finding / Pros / Cons / Recommendation` line). Do NOT merely *reference* "the finding schema":
reviewers reproduce exactly what the prompt shows them, so a merged or abbreviated schema in the
template yields merged findings that are painful to triage. Inlining it makes `current.md`
self-contained and a fresh regeneration correct by construction.

## Runbook — start a round from zero

1. **Baseline, scope & constraints.** Pick the baseline (a commit for whole-repo, or a range
   `BASE..HEAD` for a diff scope) and the **scope** (whole repo / since ref-tag-version /
   specific commits). For lens #10, set the **modernization look-back floor** (a version or
   date; for a diff scope, the base ref). Record baseline + scope + date + model in
   `current.md`. Then determine the limits in force — session-window length + longer cap,
   per-subagent output-token cap, any per-agent runtime limit — and record them too (don't
   assume a previous round's numbers; plan and model change between rounds).
2. **Verify cross-references & bindings.** Confirm every path/section this round will use
   against the live repo; resolve ARCHITECTURE §-numbers via AGENTS.md's reference index.
   Record the resolved bindings, this round's project-state deferrals, and the **filled
   dispatch template** in `current.md`.
3. **Manifests.** Generate per-lens units in `progress.md` by the line/size budget (for a
   diff scope, units are built from the changed files). Test lenses shard over the test dirs;
   docs over the doc files; build-health over CI/tooling/analyzer config; #10 over the
   changelog range + affected code.
4. **Pilot.** Run one lens, 1–2 units. Verify depth (exhaustive, not skimmed), the schema,
   and the resume mechanism (clean file + trailer). Read per-unit cost → extrapolate →
   check wall-clock vs the step-1 budget and that output stays under the cap. **Resize
   units** if it would overrun or risk truncation, then proceed.
5. **Fan out, lens by lens, structural→surface.** When a lens **starts**, seed its
   carry-forward items (`carry-forward.md`) into its findings and brief the relevant reviewers.
   Serial dispatch; flip each unit `[x]` on a **verified trailer** (not the agent's reply);
   resume across sessions via `progress.md`. **When a lens completes: consolidate its units →
   back-reconcile its findings against all prior lenses' triaged decisions (pipeline step 3) →
   you triage that lens → next lens.**
6. **Plan (after all lenses triaged).** Derive from accepted findings, grouped by locality,
   ordered structural-first, split into session-sized chunks. Promote to a tracked doc.
7. **Implement** chunk by chunk (resumable the same way). Implementing a finding means
   **code + tests + green CI** — update and extend every test the change touches (migrate
   renamed call sites, re-confirm goldens, cover new/changed branches); tests are
   first-class, CI-gated code, never sidelined. The review phase's read-only "tests out of
   this unit's scope" notes constrain *reviewing*, not implementing. Changes made while
   implementing do **not** re-trigger the review — that would never terminate.

   **Per-finding re-validation gate — deep-dive each finding as you implement it; do NOT batch
   the judgement to the end.** Triage accepts a finding on its *described* merit, but triage
   sees a limited slice — a finding can still turn out redundant, not worth its cost, or a
   false positive that slipped through. So before/while applying each accepted finding,
   re-validate it against the *actual* code, and **stop, step back, and check in with the human
   on that specific finding** the moment a red flag appears — never silently drop it and never
   silently push it through:
   - **Still real?** Re-confirm the finding holds against current code. A false positive that
     survived triage is caught and handed back here (record why).
   - **Net-complexity — Simplification especially, but EVERY lens.** Measure the change: a
     "simplification" that lands the **same amount of code, or more** (or more indirection),
     has defeated its own purpose. Simplification must come out **net-negative on code +
     complexity**; if the implementation doesn't, stop and check in.
   - **Worth-it tradeoff.** Weigh the *realized* cost (new abstraction, indirection, coupling)
     against the benefit. **Superficial** architectural changes that add indirection for little
     gain may not be worth it; **deep** architectural changes are *expected* to trade some
     added complexity for better overall quality — that tradeoff is acceptable. The test is
     whether the change is genuinely net-positive, not whether it adds any complexity at all.
   - **Why per-finding, not at the end:** implementation produces a large diff; once everything
     is applied it is impossible to judge each finding's individual worth. The only place to
     catch a not-worth-it or false-positive finding is *as you implement it* — pause and check
     in *then*, per finding.
   This is the implementation-phase complement to the review rule "never suppress a finding for
   effort": review records everything; implementation **re-validates and may hand a finding
   back**. Stay vigilant across all lenses, not just Simplification.

   **Deviations log — record every deliberate divergence as you land it.** The gate above decides
   *whether* to diverge from a finding/plan; a running **`DEVIATIONS.md`** records *that you did and
   why*. Whenever the implemented code intentionally differs from a finding or the plan — you route
   more (or fewer) sites than enumerated, deliberately *exclude* a look-alike, reshape a finding's
   suggested API, split or defer a sub-finding, or leave a known code-vs-docs gap that a later chunk
   will close — write an entry **at the moment it lands**. It is the durable backstop against the
   traps the per-finding gate can't see across chunks: a later step "fixing" a deliberate choice,
   re-applying something that was deliberately *not* applied, or tripping over a scheduled gap as if
   it were a bug. One entry per divergence, each with the same shape: **what the finding/plan implied
   → what actually landed → a `Do not:` line naming the trap to avoid** (link related entries by ID).
   Finding IDs (`CORR-…`, `SIMP-…`, …) **are** allowed here — `DEVIATIONS.md` is ephemeral per-round
   working state, the one place outside the committed tree where they belong (committed code, tests,
   and docs must never carry them). **Read it before implementing or reviewing any chunk**, the same
   way reviewers read `carry-forward.md` — it is to implementation what carry-forward is to review.

## Re-running with a newer model

Just start a new round at step 1 with a fresh baseline. The playbook is model-agnostic.
A stronger model may hold more context — re-calibrate the unit ceiling at the pilot
rather than reusing an old unit count.
