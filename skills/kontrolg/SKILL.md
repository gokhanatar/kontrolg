---
name: kontrolg
description: Runs an autonomous technical audit and remediation pass on a codebase. Detects the stack, scans for security, data-layer, architecture, performance and startup issues, produces a prioritized P0/P1/P2 plan with file-and-line evidence, and applies the fixes after approval. Use this skill when the user says "kontrolg", "/kontrolg", "audit this project", "run a control pass", "security review", "find and fix the gaps", "harden this codebase", or "is this production ready". Also use it when a user starting a new project asks what they should set up or watch out for.
---

# kontrolg — Autonomous Audit Pass

A full-codebase sweep that **decides for itself what is missing**, prioritizes it, and fixes it.

The goal is not to give generic advice. The goal is: **look at this repo, in this stack, at this scale, and find the 10–15 things that actually matter.** Filtering out the rest is as important as finding them.

## Core principles

1. **No finding without evidence.** Every finding carries a file path and line number, or a concrete absence ("this file does not exist"). Sentences like "security should be improved" do not belong in the report.
   - **Claiming something is absent is harder than claiming it is present.** A single grep returning nothing is not proof of absence; the project may implement that capability with its own module. Before writing an absence finding, run a second search with generic names and open the file where that capability would live.
   - Withdraw a false finding as soon as you notice it. Even when the user says "add X", verify it is genuinely missing first — stacking a second dependency on top of a working system is a net loss.
2. **Judge against scale.** Do not propose Kubernetes, CQRS, or distributed tracing for an app with 200 users. Over-engineering is as harmful as under-engineering, and the report must say so in its own section.
3. **Front-load the irreversible decisions.** Auth model, ID type, multi-tenancy approach, row-level security, migration discipline, money representation — changing these later rewrites the whole data layer. They are always P0.
4. **Make small, verifiable changes.** One fix per commit, build and tests after every commit.
5. **Respect the existing code.** Follow the patterns already in the repo; do not impose your own architectural taste.

---

## Flow

### Phase 0 — Preflight

Before any write phase:

```bash
git status --porcelain && git branch --show-current
```

- If the working tree is dirty, say so and ask the user to commit or stash. Never apply automatic changes on top of a dirty tree.
- Create a new branch named `kontrolg/<date>` for the remediation phase.
- No git? Produce the report only, change no code, and tell the user why.

### Phase 1 — Discovery

Learn everything the repo can tell you before asking anything:

```bash
ls -la; cat package.json 2>/dev/null; cat README.md 2>/dev/null | head -60
find . -maxdepth 3 -type d -not -path "*/node_modules/*" -not -path "*/.git/*" | head -60
```

Determine:
- **Stack**: framework, language, build tool, mobile layer (Capacitor/RN), backend (Node/Edge/serverless)
- **Data layer**: Postgres/Supabase/Firebase/Mongo/SQLite; ORM present (Prisma/Drizzle/raw)?
- **Auth**: hand-rolled, Supabase Auth, Clerk/Auth0, or none
- **Money flows**: Stripe, IAP, webhooks
- **Multi-tenancy**: is there a schema where users could see each other's data?
- **Deploy target**: Vercel/Netlify/VPS/app stores
- **Maturity**: prototype or live — infer from CI, tests, migrations folder, `.env.example`

Ask only what the code cannot tell you — at most three questions, in one batch:
- Is this live, and how many users do you expect?
- Is the user data sensitive (personal data, payments, health, minors)?
- What is the focus of this pass: security / performance / general hardening?

If no answer comes, assume the most conservative case (live + sensitive data) and state that in the report.

### Phase 2 — Scan

Read `references/audit-rules.md` — the stack-specific commands and detection patterns live there.

The detection commands are tuned to JavaScript/TypeScript (React, Vite, Node, Capacitor) plus Postgres/Supabase and Firebase. If the project is on another stack — Django, Rails, Go, .NET, Laravel, Spring — the *principles* in every category still apply, but the grep commands will not match. In that case, use each category as a checklist: read for the same shape of mistake in that ecosystem's idioms, and never mark a category "clean" just because a JS-shaped search found nothing. Say the automated check does not cover this stack and you inspected by hand.

Scan every category. For the category list and terminology pool see `references/concept-checklist.md`; its "symptom → concept" table is a shortcut from a complaint to the relevant concept.

Scan order (higher is more critical):
1. Secret and credential leakage
2. Authorization (BOLA/IDOR, RLS, tenant isolation)
3. Injection and input validation
4. Data layer (indexes, N+1, transactions, migrations, money and date types)
5. Idempotency and consistency, including **race conditions and read-modify-write** — the interleaving bugs where payment and inventory logic breaks
6. Time and money arithmetic — timezone/DST drift, duration from `Date.now()`, float money, rounding order, client-supplied time
7. Startup and runtime performance — **measure a baseline first** (`references/performance-audit.md`, section 0). No performance finding is written without a number; "feels slow" is not a finding. After each fix, measure the same metric again and put the before/after row in the report.
8. Error handling and observability
9. Async, cancellation, resource leaks
10. API surface (pagination, rate limits, error format)
11. Deploy and configuration hygiene
12. Dependencies and supply chain — lockfile, reachable advisories, install scripts, unpinned ranges (ranked, not a wall of upgrades)
13. Store and regulatory compliance (GDPR/CCPA, account deletion, permissions) — if mobile or handling user data

If a category does not apply, write one line — **"not applicable — why"** — and move on. This raises the credibility of the whole report.

**Business-logic invariants.** Pattern scanning cannot see intent — "no user can hold a premium feature without spending inventory" is not a syntax rule. If the repo has an `INVARIANTS.md` (or a `## Invariants` section in its README or CLAUDE.md), read it: each line is a rule the code must never violate, written by the person who knows the domain. Trace each invariant to the code paths that could break it and report any that can. If no such file exists and the app has payment, inventory, or access-tier logic, suggest the user write one — three or four plain sentences is enough — because it closes exactly the gap pattern scanning leaves open. Do not invent invariants the user did not state; an assumed business rule is worse than none.

### Phase 3 — Report

Create `KONTROLG-REPORT.md` at the project root:

```markdown
# Control Pass — [date]

## Summary
[3–5 sentences: state of the project, the three most critical findings]

Detected stack: ...
Assumptions: ...

## P0 — Now (irreversible or actively exploitable)
### [Finding title]
- **Where:** `path/file.ts:42`
- **Problem:** [what it is, concretely]
- **Why it matters:** [what happens when it fires]
- **Evidence:** [a one-line command the user can run to see it themselves — the grep/rg that surfaced it, or the file:line to open. This lets a skeptical user verify without trusting the report, and forces the finding to be real.]
- **Fix:** [what to do, how many files are affected]
- **Effort:** S / M / L

## P1 — Before the next release
## P2 — When scale arrives
## Unnecessary — do not do this now
[Common practices that are not warranted at this scale, with a short rationale]

## Irreversible decisions
[Things that become expensive if not decided now]

## Performance baseline
[Required whenever the performance category was scanned. Numbers, or "not measured — why".]

## Unverified live changes
[Anything already in production that no real client or device has exercised. Also anything deployed that the currently released client build cannot use. Write "none" if empty.]

## Remediation log
[Filled in during Phase 4]
```

If the performance category was scanned, the report **must** contain the baseline table from `performance-audit.md` section 0, whether or not findings emerged. It is a required section, not an optional one. Later passes need it to compare against.

A performance finding without a measured number is not a P1. Reasoning alone — "this recomputes on every keystroke", "this serializes on every setState" — is enough to *raise* the item, but not to rank it or to claim the fix worked. So: if you can measure it, measure it, and write the before/after row. If you genuinely cannot (no device, no profiler access, the user is unavailable), write **"not measured — why"** next to the finding and cap it at P2. Do not silently promote an estimate into a ranked finding; two passes in a row of confident-sounding unmeasured performance work is how a report stops being trustworthy.

After writing the report, give the user **a short summary in chat**: P0 count, the three most critical items, estimated effort. Do not paste the whole report into the conversation.

### Phase 4 — Remediation

Offer three choices: **everything / P0 only / pick individually**. Change no code before an answer arrives.

Once approved, work autonomously — do not ask per item. For each item:

1. Make the change
2. Run the project's build, plus tests and lint if present
3. On success, commit: `kontrolg: [category] short description`
4. On failure, fix it; if two attempts do not work, revert, mark it "needs manual intervention" in the report, and continue
5. Append a line to the remediation log

**Ask first, even inside an approved pass:**
- **Deploying to live infrastructure** — cloud functions, security rules (Firestore/Storage), server configuration, environment variables. Writing code and shipping it to production are two separate decisions; the second is always asked separately. Whatever is deployed must be revertible, and the user must be told how.
- **A server-side change the currently released client cannot survive.** Before deploying rules, a schema change, or an API contract change, work out what the shipped build does today. If tightening a rule closes a path the live app still uses — a paid feature, a login flow, a sync call — say so plainly and let the user choose: deploy now and accept that the feature is broken for every existing user until a new build clears review, or hold and ship both together. On mobile, review latency makes this irreversible for days. It is the decision itself, never a line to note afterwards in "remaining work".
- Migrations that alter the database schema (especially against a live database)
- Adding a new dependency
- Refactors touching five or more files
- Anything that changes the behavior of the auth flow
- Deletions

**Never:**
- Write secrets, tokens, or `.env` contents into the report or a commit. If you find a leak, show where it is, mask the value (`sk-...abcd`), and tell the user to rotate it — do not rotate it yourself.
- Write to or run migrations against a live database.
- Delete user data.
- Loosen or delete tests to make them pass.

### Phase 5 — Close out

- Complete the remediation log in `KONTROLG-REPORT.md`
- List what could not be done as remaining work
- Tell the user: how many items were applied, how many commits, which branch, what they must do manually
- **Never leave a deployed-but-unverified change unspoken.** If the server side went live while the client side was never tested, state that asymmetry and how to roll it back
- If a secret leak was found, repeat it separately and clearly so it does not get lost

---

## Re-running

If `KONTROLG-REPORT.md` already exists: read the old one and reconcile it against the current code before writing anything new. For each previous finding, use its **Evidence** command — re-run it. Three outcomes, and name each explicitly in the new report:

- **Resolved** — the evidence command now comes back clean. Mark it fixed; do not re-litigate it.
- **Still open** — the evidence still fires. Carry it forward at its original priority.
- **Regressed** — a finding that a prior report marked resolved is firing again. This is the highest-signal outcome a re-run produces: something a past pass fixed has broken again, usually from a deploy or a merge. Surface regressions at the top, above new findings, because a reintroduced P0 is more urgent than a fresh P2 — someone believed this was handled.

Then scan for new findings as normal. Do not regenerate the whole report from scratch; the value of a re-run is the delta.

If the user names a category (`kontrolg security`), scan only that category but still run Phase 0 and Phase 3.

## Reference files

- `references/audit-rules.md` — Stack-specific scan commands, detection patterns, false-positive warnings. Read in Phase 2.
- `references/performance-audit.md` — Measurement protocol, budget table, bottleneck classification, layer-by-layer performance checks. Read before entering the performance category; do not write a performance finding without it.
- `references/concept-checklist.md` — A pool of ~350 concepts across 13 categories, plus a symptom-to-concept table. Use it in Phase 2 to verify category coverage, and as a checklist when scaffolding a new project.
