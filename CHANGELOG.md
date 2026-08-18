# Changelog

## [1.0.0] — 2026-08-15

First public release.

### Included
- 5-phase flow: preflight → discovery → scan → report → remediation → close out
- 13 audit categories with stack-specific detection patterns
- Separate performance audit with a measurement protocol and budget table
- ~350-concept checklist plus a symptom→concept map
- `/kontrolg` slash command with category argument

### Notes from field testing
Rules were tuned across passes on live React / Capacitor / Supabase / Firebase projects. Three changes came directly from things that went wrong:

- **Verification protocol** — an early version claimed a project had no error tracking based on a narrow grep. It had a hand-rolled one. Absence claims now require a second broader search plus opening the file.
- **Deploy is ask-first** — an early version deployed cloud functions mid-pass. Shipping to production is now a separate decision from writing the code, and the report has a mandatory "unverified live changes" section.
- **Comment–code mismatch category** — added after a pass found an unbounded realtime listener sitting under a comment claiming a limit was in place.

## [1.1.0] — 2026-08-16

### Added
- **`store-preflight` skill** — checks a mobile app for App Store and Google Play rejection risks before submission. Separates hard blockers from reviewer-dependent risk, and puts anything a repo scan cannot prove (live privacy policy URL, form contents, working demo account) into an explicit "needs your confirmation" section.
- `/store-preflight` slash command, with an optional platform argument.

### Notes
Rules cover account deletion, privacy declarations vs. actual SDK behavior, the iOS privacy manifest and required-reason APIs, permission and purpose-string problems, minimum functionality risk for webview wrappers, payments, UGC requirements, build configuration, listing gaps, families policy, and encryption compliance.

Store policy thresholds are deliberately not hardcoded — the skill points at the official pages and is instructed to admit uncertainty rather than invent a requirement.

## [1.1.1] — 2026-08-18

Two changes, both from a second field pass on a live Capacitor + Firebase app.

### Changed
- **Backward compatibility is now an ask-first gate.** A server-side change (security rules, schema, API contract) that the currently released client cannot survive must be raised as a decision *before* deploying, not noted afterwards. In the pass that prompted this, closing a genuine revenue-bypass hole in Firestore rules also broke a paid feature for every user on the shipped build — correct to fix, but the timing should have been the user's call, because mobile review latency makes it irreversible for days.
- **Unmeasured performance findings are capped at P2.** The baseline table is now a required report section rather than an instruction that can be skipped, and a finding with no number must say "not measured — why". Reasoning is enough to raise an item, not to rank it or to claim the fix worked. Two passes in a row had produced confident performance findings with no measurement at all.

## [1.2.0] — 2026-08-18

Broadened what a pass looks for, and made re-runs sharper — all aimed at the class of bug pattern-scanning was missing.

### Added
- **Race conditions and read-modify-write** (in the consistency category) — non-atomic counters, two writers on one document, check-then-act, missing in-flight guards. This is where payment and inventory logic actually breaks; the code type-checks, the interleaving is wrong.
- **Time and money arithmetic** as its own category — timezone/DST drift, durations built from `Date.now()`, float money, rounding order, and trusting client-supplied timestamps. Silent, expensive, invisible to a type checker.
- **Dependencies and supply chain** — lockfile discipline, `npm audit` triaged by *reachability* rather than blindly upgrading, install-script scanning, unpinned ranges, phantom dependencies.
- **Business-logic invariants** — if the repo has an `INVARIANTS.md`, the pass traces each stated rule ("no user holds a premium feature without spending inventory") against the code and reports violations. This closes the gap pattern-scanning structurally cannot: it needs the intent, which only the domain owner can supply. The skill won't invent invariants the user didn't state.

### Changed
- **Every finding now carries an Evidence line** — a one-line command to reproduce it. A skeptical user can verify without trusting the report, and writing the command forces the finding to be real.
- **Re-runs now detect regressions explicitly.** Each prior finding's evidence command is re-run and classified resolved / still-open / regressed. A finding a past pass fixed that is firing again is surfaced at the very top — a reintroduced P0 outranks a fresh P2, because someone believed it was handled.

## [1.2.1] — 2026-08-18

### Changed
- **Principle vs. detection, made explicit.** Every category now separates the stack-independent *principle* (which holds in any language) from the *detection command* (tuned to JavaScript/TypeScript, Postgres/Supabase, and Firebase, where the skill was field-tested). On other stacks the skill applies each category as a checklist by hand and says so, rather than reporting a category "clean" because a JS-shaped search matched nothing on, say, a Python repo. This keeps the tool honest about where its automated matching is reliable instead of claiming a generality it hasn't been tested for.

## [1.3.0] — 2026-08-18

Deepened authorization from a presence check into a logic review, and made the report structurally honest about what it cannot certify.

### Added
- **Policy logic review.** The authorization category no longer stops at "does a policy exist". It reads what each policy *permits*: `using` vs `with check` (a visible row updated into a forbidden state), verb asymmetry (strict insert, loose update — the same record reached by a different path), helper-function trust (`is_team_member` that still returns true after removal; `SECURITY DEFINER` that bypasses RLS), cross-table and cross-policy reach, column-level exposure (RLS guards rows, not columns), and self-escalation paths (writing your own `role`/`tier`/`is_admin`).
- **Defense in depth.** Flags where RLS is the sole line of defense, and where a service-role key bypasses it entirely so the check must live in application code.
- **Role-isolation test generation.** With approval, the pass writes tests that run real queries as anon / user A / user B / a revoked member / a self-escalation attempt, and assert the boundary holds. A read of the policies establishes intent; only a test establishes behavior.

### Changed
- **New mandatory report section: "What this pass did NOT verify."** A pass finds patterns; it does not certify safety. The report must now state plainly what remains unchecked — authorization correctness under real conditions, cross-policy interaction, runtime isolation unless tests were run — so no one reads it as a guarantee. A new core principle ("an audit is a filter, not a guarantee") and a close-out step enforce the same honesty in the chat summary: if the user frames the result as "now we're safe", the skill corrects it plainly rather than letting false confidence ship to production.

### Added (trust boundary)
- **Explicit trust-boundary lens** in the authorization pass. Previously the "client can't be trusted" concern was scattered across UI-only auth, client-supplied time, mass assignment, and client-bundle secrets. It is now a consolidated check: trace any client-controllable value to a consequential decision (price, entitlement, credit/inventory consumption, access) and flag anything enforced only on the client with no server/RLS counterpart. Severity is set by what the lie buys the user — a checkout charging `req.body.amount` is a P0; cosmetic client state is not a finding. The section also names what legitimately stays local, so the check doesn't generate noise.
