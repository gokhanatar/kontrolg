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

Scan every category. For the category list and terminology pool see `references/concept-checklist.md`; its "symptom → concept" table is a shortcut from a complaint to the relevant concept.

Scan order (higher is more critical):
1. Secret and credential leakage
2. Authorization (BOLA/IDOR, RLS, tenant isolation)
3. Injection and input validation
4. Data layer (indexes, N+1, transactions, migrations, money and date types)
5. Idempotency and consistency (payments, webhooks, retries)
6. Startup and runtime performance — **measure a baseline first** (`references/performance-audit.md`, section 0). No performance finding is written without a number; "feels slow" is not a finding. After each fix, measure the same metric again and put the before/after row in the report.
7. Error handling and observability
8. Async, cancellation, resource leaks
9. API surface (pagination, rate limits, error format)
10. Deploy and configuration hygiene
11. Store and regulatory compliance (GDPR/CCPA, account deletion, permissions) — if mobile or handling user data

If a category does not apply, write one line — **"not applicable — why"** — and move on. This raises the credibility of the whole report.

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

If `KONTROLG-REPORT.md` already exists: read the old one, mark previous findings resolved or unresolved, and surface only new findings and regressions. Do not regenerate the same report from scratch.

If the user names a category (`kontrolg security`), scan only that category but still run Phase 0 and Phase 3.

## Reference files

- `references/audit-rules.md` — Stack-specific scan commands, detection patterns, false-positive warnings. Read in Phase 2.
- `references/performance-audit.md` — Measurement protocol, budget table, bottleneck classification, layer-by-layer performance checks. Read before entering the performance category; do not write a performance finding without it.
- `references/concept-checklist.md` — A pool of ~350 concepts across 13 categories, plus a symptom-to-concept table. Use it in Phase 2 to verify category coverage, and as a checklist when scaffolding a new project.
