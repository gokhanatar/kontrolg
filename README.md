# kontrolg

**An autonomous audit pass for Claude Code.** Type `/kontrolg` in any project and it scans the codebase, decides for itself what actually matters, writes a prioritized report with file-and-line evidence, and — once you approve — fixes it.

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

That copies the skill to `~/.claude/skills/kontrolg/` and the slash command to `~/.claude/commands/kontrolg.md` — both global, so they work in every project. Open a new Claude Code session and you're done.

Prefer to do it by hand:

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
cp -r skills/kontrolg ~/.claude/skills/
cp commands/kontrolg.md ~/.claude/commands/
```

**Project-scoped instead of global?** Copy into `.claude/skills/` and `.claude/commands/` inside the repo and commit them, so your whole team gets it.

---

## Use

```
/kontrolg                 # full pass
/kontrolg security        # one category
/kontrolg performance
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

<table>
<tr><td width="50%" valign="top">

**Security**
- Secret leakage (including git history, and `VITE_`/`NEXT_PUBLIC_` keys that ship to the client)
- BOLA/IDOR — the number-one real API flaw
- RLS policies, tenant isolation, `using (true)` mistakes
- Mass assignment, injection, file upload handling
- Auth: token storage, rotation, brute-force protection

**Data layer**
- Missing indexes, N+1, unbounded queries
- Migration discipline, transactions, isolation
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
<summary><b>Excerpt from a real report</b> (Capacitor + React + Firebase, live app)</summary>

```markdown
## P1 — Before the next release

### 2. Unbounded `listenUserChats` realtime listener (cost + memory)
- **Where:** `src/services/firebase/chats.ts:264-268`
- **Problem:** Listens to ALL of a user's chats with no `limit()`. A heavy user
  (100+ chats) re-reads the whole list on every message update.
- **Why it matters:** Affects all users, not just admins. Firestore realtime
  cost plus client memory. Chat is the riskiest collection type.
- **Fix:** Add `limit(50)` (already ordered `lastMessageAt desc`) plus a
  "load more" pagination. Old chats are opened rarely.
- **Effort:** S-M

## Unnecessary — do not do this now
- Kubernetes/microservices/CQRS/Redis — solo developer on serverless Firebase.
- CI pipeline — useful, but below P2 at this scale; tests run locally.
- Dead `@supabase/supabase-js` dependency — verified unused. Harmless, not urgent.
```

The same pass shrank an eagerly-bundled 17-language i18n import from **489 KB to 3.8 KB** of startup bundle, and correctly *downgraded* a finding whose code comment was labelled `CRITICAL` — the code showed it was a revenue leak, not a vulnerability.

</details>

---

## Design notes

**Why the skill is allowed to be wrong out loud.** The verification protocol in [`audit-rules.md`](skills/kontrolg/references/audit-rules.md) exists because an early version claimed a project had no error tracking, based on a grep for `Sentry|captureException`. The project had a complete hand-rolled error reporter. The skill now treats *withdrawing a false finding as a success*, and refuses to install something the user asked for until it has verified it's actually missing.

**Why deploying is a separate decision.** Writing code and shipping it to production are two different acts. An earlier version deployed cloud functions during an audit pass because "deploy" wasn't on the ask-first list. It is now, along with a mandatory "unverified live changes" section in the report.

**Why performance works differently from security.** Security findings are binary — RLS is on or off. Performance findings are not, so the skill has to take a baseline, compare against a budget table, and write a before/after row for every fix. An unmeasured change gets filed under "code cleanup", not "performance fix". If the number got worse, it reverts.

---

## Repo layout

```
skills/kontrolg/
  SKILL.md                        the 5-phase flow and core principles
  references/
    audit-rules.md                13 categories of concrete grep patterns
    performance-audit.md          measurement protocol + budget table
    concept-checklist.md          ~350 concepts + symptom→concept map
commands/kontrolg.md              the /kontrolg slash command
install.sh
```

The references load only when the relevant phase needs them, so a session that never reaches the performance category never pays for that file's context.

---

## Contributing

The detection rules are tuned against React / Vite / Capacitor / Supabase / Firebase, because that's what they were built and field-tested on. **Rules for other stacks are the most valuable thing you can contribute** — Django, Rails, Go, .NET, Next.js server actions, React Native, Flutter.

False positives are the second most valuable. If a pattern fires on correct code, open an issue with the snippet; narrowing a rule improves the whole tool. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.
