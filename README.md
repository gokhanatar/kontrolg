# kontrolg

**Autonomous pre-ship checks for Claude Code.** Two skills that read your codebase and tell you what will actually bite you: `kontrolg` for a technical audit, `store-preflight` for App Store and Play rejection risk.

**`/kontrolg` — an autonomous audit pass.** Type `/kontrolg` in a project and it scans the codebase, decides for itself what actually matters, writes a prioritized report with file-and-line evidence, and — once you approve — fixes it. Its judgment is stack-independent; its automated detection is sharpest on JavaScript / TypeScript, Postgres/Supabase, and Firebase (where it was field-tested) and applied by hand elsewhere.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-8A63D2.svg)](https://docs.claude.com/en/docs/claude-code/skills)

---

## The problem

You ask an AI to "review my code for security issues" and get back a wall of generic advice: *add rate limiting, consider caching, implement proper error handling*. None of it points at a line in your repo. Half of it doesn't apply. The parts that do apply are buried next to suggestions to adopt Kubernetes for your 200-user side project.

`kontrolg` is a Claude Code skill built to fix that. It is opinionated about three things:

1. **Evidence or it doesn't ship.** Every finding carries `path/file.ts:42` or a concrete absence. "Security should be improved" is banned by the skill's own rules.
2. **Absence is harder to prove than presence.** A grep for `Sentry` returning nothing does *not* mean there's no error tracking — the project may have rolled its own. The skill is required to run a second, broader search and open the file before claiming anything is missing. This rule exists because an early version got it wrong.
3. **Over-engineering is a finding too.** The report has a mandatory "do not do this now" section. Suggesting sharding to a solo developer is a failure, not thoroughness.

---

## Install

```bash
git clone https://github.com/gokhanatar/kontrolg.git
cd kontrolg && ./install.sh
```

That copies both skills to `~/.claude/skills/` and both slash commands to `~/.claude/commands/` — global, so they work in every project. Open a new Claude Code session and you're done.

Prefer to do it by hand:

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
cp -r skills/* ~/.claude/skills/
cp commands/* ~/.claude/commands/
```

**Project-scoped instead of global?** Copy into `.claude/skills/` and `.claude/commands/` inside the repo and commit them, so your whole team gets it.

---

## Use

```
/kontrolg                 # full audit pass
/kontrolg security        # one category
/kontrolg performance

/store-preflight          # submission readiness check
/store-preflight ios      # one platform
```

Or just say it in plain language — *"audit this project"*, *"is this production ready?"*, *"find and fix the gaps"* — and the skill triggers on its own.

### What happens

```
Phase 0  Preflight    git clean? → branch kontrolg/<date>
Phase 1  Discovery    detect stack, data layer, auth, payments, maturity
Phase 2  Scan         13 categories, stack-specific patterns
Phase 3  Report       KONTROLG-REPORT.md, P0/P1/P2 + "don't do this"
         ── your approval: everything / P0 only / pick ──
Phase 4  Remediate    one fix per commit, build + tests after each
Phase 5  Close out    what shipped, what's unverified, what's left for you
```

It stops and asks before: deploying to live infrastructure, schema migrations, adding a dependency, refactors touching 5+ files, changing auth behavior, deletions. Everything else it just does.

---

## What it looks for

The **principles** below are stack-independent — an ownership check on an ID lookup, money that is never a float, a read-modify-write that loses data under concurrency, all hold in any language. The **detection commands** that find them are tuned to JavaScript / TypeScript (React, Vite, Node, Capacitor) plus Postgres/Supabase and Firebase, because that is where the skill was built and field-tested. On another stack, kontrolg applies the same checklist by reading for the same shape of mistake by hand, and says so in the report rather than pretending a JS-shaped search covered a Python repo. ([Detection rules for other stacks](CONTRIBUTING.md) are the single most useful contribution.)

<table>
<tr><td width="50%" valign="top">

**Security**
- Secret leakage (including git history, and `VITE_`/`NEXT_PUBLIC_` keys that ship to the client)
- BOLA/IDOR — the number-one real API flaw
- RLS policies, tenant isolation, `using (true)` mistakes
- Mass assignment, injection, file upload handling
- Auth: token storage, rotation, brute-force protection

**Data layer & consistency**
- Missing indexes, N+1, unbounded queries
- Migration discipline, transactions, isolation
- Race conditions and read-modify-write — the interleaving bugs where inventory and payment logic breaks
- Time/money arithmetic — timezone/DST drift, float money, rounding order, client-supplied time
- Money stored as float, dates without timezones
- Offset vs. cursor pagination

</td><td width="50%" valign="top">

**Performance**
- A measurement protocol and a budget table — no number, no finding
- Bottleneck classification: CPU-bound vs. I/O-bound vs. render-bound
- Cold start, bundle weight, request waterfalls
- Cache layer selection and invalidation
- Memory leaks from uncleaned listeners

**Everything else**
- Idempotency, webhook signature verification
- Dependencies & supply chain — lockfile, reachable advisories, install scripts (ranked, not a wall of upgrades)
- Business-logic invariants — checks your `INVARIANTS.md` rules against the code, closing the gap pattern-scanning can't
- Observability, correlation IDs, error boundaries
- Store compliance, GDPR, account deletion
- Firebase-specific: security rules, unbounded `onSnapshot`, read-cost blowouts

</td></tr>
</table>

Plus the pattern that turned out to be the highest-yield of all:

> **Comment–code mismatch.** When a comment claims a safeguard exists, verify the safeguard is in the code. `// limit added` survives the refactor that deleted the limit. In one real pass this found an unbounded realtime listener on a chat collection that everyone believed was capped — a live billing hazard nobody suspected, precisely *because* the comment said it was handled.

---

## Example output

<details>
<summary><b>What an excerpt looks like</b> (illustrative — a Capacitor + Firebase app)</summary>

```markdown
## P1 — Before the next release

### 2. Unbounded realtime listener on the chat collection (cost + memory)
- **Where:** `src/services/chat.ts:212-217`
- **Problem:** Subscribes to ALL of a user's threads with no `limit()`. A heavy
  user (100+ threads) re-reads the whole list on every message update.
- **Why it matters:** Firestore realtime cost is a function of documents read,
  so this grows the bill and client memory together. Chat is the riskiest
  collection type for this.
- **Evidence:** `rg -n 'onSnapshot' src/services/chat.ts` — no `limit()` on the query
- **Fix:** Add `limit(50)` on the existing `updatedAt desc` order, plus a
  "load more". Old threads are opened rarely.
- **Effort:** S-M

## Unnecessary — do not do this now
- Kubernetes/microservices/CQRS/Redis — solo developer on serverless Firebase.
- CI pipeline — useful, but below P2 at this scale; tests run locally.
- A dependency flagged as unused — verified actually unused. Harmless, not urgent.
```

Two things this illustrates: the listener finding carries an **Evidence** line the reader can run themselves, and the "unnecessary" section is doing as much work as the findings — a report that only ever adds is a report you learn to distrust. A real pass on a bundle-heavy app might also, for instance, cut an eagerly-imported multi-language i18n payload down by an order of magnitude for the startup bundle — but only with the before/after numbers measured, never estimated.

</details>

---

## store-preflight

A rejection costs one to three days, and almost all of them come from the same short list of causes — most of which are visible in the repo before you ever hit submit. `/store-preflight` answers one question: **would a reviewer reject this build, and why?**

It separates hard blockers from reviewer-dependent risk, because marking everything critical trains you to ignore the report. What it looks for:

- **Account deletion** — required by both stores for any app with accounts, and the single highest-frequency blocker. A string match isn't enough; the flow has to be reachable, delete server-side data, and not just open an email composer.
- **Declarations vs. code** — the most common silent failure is an App Privacy or Data Safety form that doesn't match what an analytics or ads SDK actually collects. The code is the source of truth; the form is what gets you rejected.
- **iOS privacy manifest** and required-reason APIs — validated at upload, so a gap here fails before a human ever looks at the build.
- **Permissions** — declared-but-unused (common when a plugin injects them), used-but-undeclared, and purpose strings too generic to pass 5.1.1.
- **Minimum functionality** — the real 4.2 risk for Capacitor and wrapper apps. If everything works identically in mobile Safari, the reviewer asks why it's an app.
- Payments and IAP rules, UGC requirements (report, block, contact, EULA), target API levels, listing gaps, families policy, encryption compliance.

It won't fill in a compliance form for you, and it won't help make a non-compliant app *look* compliant — if the app violates a policy, it says so plainly.

---

## Design notes

**Why the skill is allowed to be wrong out loud.** The verification protocol in [`audit-rules.md`](skills/kontrolg/references/audit-rules.md) exists because an early version claimed a project had no error tracking, based on a grep for `Sentry|captureException`. The project had a complete hand-rolled error reporter. The skill now treats *withdrawing a false finding as a success*, and refuses to install something the user asked for until it has verified it's actually missing.

**Why deploying is a separate decision.** Writing code and shipping it to production are two different acts. An earlier version deployed cloud functions during an audit pass because "deploy" wasn't on the ask-first list. It is now, along with a mandatory "unverified live changes" section in the report.

**Why performance works differently from security.** Security findings are binary — RLS is on or off. Performance findings are not, so the skill has to take a baseline, compare against a budget table, and write a before/after row for every fix. An unmeasured change gets filed under "code cleanup", not "performance fix". If the number got worse, it reverts.

---

## Repo layout

```
skills/
  kontrolg/
    SKILL.md                      the 5-phase flow and core principles
    references/
      audit-rules.md              13 categories of concrete grep patterns
      performance-audit.md        measurement protocol + budget table
      concept-checklist.md        ~350 concepts + symptom→concept map
  store-preflight/
    SKILL.md                      submission readiness flow
    references/
      store-rules.md              per-platform policy detection patterns
commands/                         the slash commands
install.sh
```

The references load only when the relevant phase needs them, so a session that never reaches the performance category never pays for that file's context.

---

## Contributing

The detection commands are tuned to JavaScript / TypeScript (React, Vite, Node, Capacitor) plus Postgres/Supabase and Firebase, because that is what they were built and field-tested on. The *principles* behind them are stack-independent, so the skill still audits other stacks by hand — but the automated matching is only reliable where it was tested. **Detection rules for other stacks are the most valuable thing you can contribute** — Django, Rails, Go, .NET, Next.js server actions, React Native, Flutter. That is also how the skill earns the right to claim it supports them: by someone actually running it there, not by shipping untested patterns.

Store policies move, and `store-preflight` deliberately points at official pages instead of hardcoding thresholds. If you spot a rule that has changed, that is a valuable issue.

False positives are the second most valuable. If a pattern fires on correct code, open an issue with the snippet; narrowing a rule improves the whole tool. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.
