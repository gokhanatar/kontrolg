# Audit Rules — Concrete Detection Patterns

This file covers *how to look*. Commands assume `ripgrep` (`rg`); fall back to `grep -rn`. Always exclude `node_modules`, `dist`, `build`, `.git`.

## Two layers: principle vs. detection

Each category below has two parts, and they generalize differently.

- **The principle** — "a record fetched by ID needs an ownership check", "money is never a float", "a read-modify-write outside a transaction loses writes" — is **stack-independent**. It is as true in Django, Rails, Go, or .NET as in Node. When you audit a stack these commands do not target, apply the principle by hand: read the code for the same *shape* of mistake, even though the grep below won't match it.
- **The detection command** — the specific `rg` pattern, the file paths, the `--type ts --type js` filter, the `package.json` lookups — is **tuned to the JavaScript/TypeScript ecosystem** (React, Vite, Node, Capacitor) plus Postgres/Supabase and Firebase on the data side. That is where these rules were built and field-tested, so that is where the automated matching is reliable.

So: on a JS/TS + Postgres/Firebase project, the commands do the work. On any other stack, treat this file as a checklist of principles and translate each detection step into that ecosystem's equivalent (the ORM's raw-query escape hatch, that language's float type, its migration tool). Do not report a category as "clean" just because a JS-shaped grep returned nothing on a Python repo — that is the "absence mistaken for proof" error, one level up. Say instead that the automated check does not cover this stack and you inspected by hand.

Detection rules for other stacks are the single most valuable contribution to this skill; see CONTRIBUTING.md.

---

## Verification protocol (read before scanning)

The patterns below produce *suspicion*, not *findings*. Field data shows that close to half of first-pass grep hits evaporate once you open the file. The two most common ways they evaporate:

- **A narrow search mistaken for proof of absence.** "No Sentry → no error tracking." The project may do the same job with a module it wrote itself. Before claiming something is *missing*, search for the **generic** names of that capability too, then open the place it would live (entry file, global handler, root layout) and look.
- **Assuming the tool's output.** Believing `.env` is tracked, or that migrations do not exist, without reading what the command actually printed.

**Rule:** every suspicion gets at least one *confirming* step — a second, broader search, or opening the file and reading it. An unconfirmed suspicion does not go in the report. If it does, the credibility of the entire report drops, because a user who sees the first item proven wrong will disbelieve the correct ones too.

**Withdrawing a false finding is a success, not a defect.** If it turns out to be wrong after you wrote it, withdraw it explicitly and say why. In particular: even when the user says "install X", verify it is genuinely missing before installing. Stacking a second dependency on a system that already works is a net loss.

---

## 1. Secret and credential leakage

```bash
rg -n --hidden -g '!.git' -g '!node_modules' \
  -e 'sk-[a-zA-Z0-9]{20,}' -e 'AIza[0-9A-Za-z_-]{30,}' \
  -e 'SERVICE_ROLE' -e 'service_role' \
  -e 'BEGIN (RSA|PRIVATE) KEY' \
  -e 'password\s*[:=]\s*["'"'"']' -e 'secret\s*[:=]\s*["'"'"']'
git ls-files | rg -e '\.env$' -e '\.env\.(local|prod|production)'
cat .gitignore 2>/dev/null | rg -e 'env'
git log --oneline --all -- .env 2>/dev/null | head
```

**Confirming step:** `.env` appearing in `git ls-files` is not enough on its own — harmless files like `.env.example`, `.env.template`, `.env.d.ts` match too. Check the exact filename and open it to see whether it holds real values:

```bash
git ls-files | grep -E '(^|/)\.env($|\.)' | while read f; do echo "== $f"; head -3 "$f"; done
```

If the values are empty or placeholders like `<your-key>`, there is no finding.

Check:
- Is `.env` tracked now — and was it ever tracked historically?
- Does `.env.example` exist? If not, create it (with empty values).
- Variables that reach the client bundle: **anything** prefixed `VITE_`, `NEXT_PUBLIC_`, `EXPO_PUBLIC_` is public. A service-role key, admin key, or payment secret behind one of those prefixes is P0 on its own.
- Mobile: keys embedded in native code or the JS bundle. A Capacitor bundle inside `dist/` is plainly readable.

On a leak: report the location, mask the value, and **have the user rotate the key**. Suggest `git filter-repo` or BFG to purge history, but do not run it automatically.

---

## 2. Authorization — BOLA/IDOR, RLS, tenant isolation

The most common real vulnerability in APIs. Treat it seriously.

### Supabase / Postgres RLS
```bash
rg -n 'create table' -i supabase/migrations/ 2>/dev/null
rg -n 'enable row level security|create policy' -i supabase/migrations/ 2>/dev/null
```
For every table holding user data: is RLS enabled **and** is there at least one policy? RLS on with no policy means the table is fully closed (a broken feature). RLS off with an anon key means the whole table is public (critical).

Flag policies containing `using (true)` or `to public` separately — they are usually written by accident.

### Ownership checks in code
```bash
rg -n 'params\.id|req\.params|searchParams\.get\(.id' --type ts --type js
rg -n "\.eq\('id'," --type ts --type js
```
For every route that fetches a record by ID, ask: "what happens if I put someone else's ID here?" If the query has no `user_id`/`owner_id`/`tenant_id` filter and RLS does not guarantee it, that is a BOLA finding.

### Where authorization actually happens
```bash
rg -n 'isAdmin|role\s*===|hasPermission|requireAuth|getUser\(\)' --type ts --type js
```
Authorization performed only in the UI (hiding a button) is not authorization. Look for a server- or database-side counterpart.

### Mass assignment
```bash
rg -n '\.\.\.(req\.body|body|payload|data)\b' --type ts --type js
```
Spreading the whole request body into an insert or update lets a user send `role: "admin"`. Check for a whitelist or schema validation.

### Read the policy logic — presence is not correctness

This is the step that separates a real authorization audit from a checkbox. A policy existing tells you nothing; **what it permits** is the finding. Open every policy and every helper function it calls, and reason about who actually gets through.

```bash
rg -n 'create policy|using \(|with check \(' -i supabase/migrations/ 2>/dev/null -A3
# helper functions a policy trusts — their logic IS the policy
rg -n 'create (or replace )?function' -i supabase/migrations/ 2>/dev/null -A8
```

- **`using` vs `with check`.** `using` controls which rows are *visible*; `with check` controls what a write is *allowed to produce*. A policy with `using` but no `with check` lets a user update a row they can see into a state they should never be able to set (e.g. flipping `owner_id` to someone else, or `tier` to premium). Missing `with check` on an update/insert policy is a finding.
- **Operation asymmetry.** Read the `select` / `insert` / `update` / `delete` policies as a *set*. The classic breach is a policy that is strict on insert but loose on update — the same record reached by a different verb. If insert forces `user_id = auth.uid()` but update only checks `using (auth.uid() = user_id)` with no `with check`, a user can update their row and change its owner. Check every verb, not just the one that looks protected.
- **Helper-function trust.** A policy like `using (is_team_member(team_id))` is only as correct as `is_team_member`. Open it. Does it still return true after a member is removed, a team is deleted, or a subscription lapses? Does it read from a table that itself has weaker RLS? A `SECURITY DEFINER` function bypasses RLS entirely and runs as its owner — trace what it exposes.
- **Cross-table / cross-policy reach.** Ask: can a user reach protected data *indirectly*? A strict policy on `messages` is defeated if `message_reactions` joins to it with a laxer policy, or if a view or `SECURITY DEFINER` function returns joined rows without re-checking. Isolation is a property of the whole schema, not one table.
- **Column-level exposure.** RLS protects *rows*, not *columns*. A user may legitimately own a row but still read a column they shouldn't (another user's email on a shared record, an internal flag). Postgres column privileges or a view are the fix; note where a row-level check is doing a column-level job.
- **Self-escalation paths.** Can a user write to their own `role`, `tier`, `is_admin`, `credits`, or `verified` field? This is mass assignment and RLS meeting: even with `user_id = auth.uid()`, if the policy's `with check` doesn't pin the privileged columns, the user escalates themselves. Grep the writable columns against the sensitive ones.

If the repo has an `INVARIANTS.md` with tenancy or access rules ("a user never reads another user's messages", "only an owner edits billing"), check each policy set against those statements directly — that is the intent the raw SQL can't tell you.

### Defense in depth — RLS must not be the only lock

```bash
rg -n 'service_role|SERVICE_ROLE|supabaseAdmin|createClient.*service' --type ts --type js
```

- If a server path uses the **service-role key**, RLS is bypassed entirely on that path — every authorization check must then be in the application code. Verify it is. A service-role client behind an endpoint with a weak or missing check is a full-table exposure.
- The strongest posture is layered: a server-side authorization check **and** RLS **and** input validation, so one gap does not become a breach. Flag anywhere RLS is the *sole* line of defense for sensitive data, not as a bug but as a fragility — one policy edit away from exposure.

### Prove isolation with tests, don't just assert it

A read of the policies establishes intent. Only a test establishes behavior. Where the project has any test setup (or can get one cheaply), propose — and with approval, write — role-isolation tests that run real queries and assert the boundary holds:

- as **anon**: sensitive tables return nothing
- as **user A**: reads/writes only A's rows; attempts on B's specific IDs return empty or error
- as **user B**: the mirror, so a one-sided policy can't pass by accident
- as **a revoked/removed member**: access that should have ended actually ended
- attempting **self-escalation**: writing `role`/`tier`/`is_admin` on own row is rejected

This is the difference between "a policy exists" and "the boundary holds". Test generation is opt-in (it adds a dependency and files — an ask-first action), but it is the single highest-confidence thing an authorization pass can leave behind.

## 2b. Trust boundary — what must live on the server

The client is an untrusted input device. Anything the user's device can lie about, where the lie has a security, money, or data-integrity consequence, must be decided and enforced on the server. This is the architectural framing behind half the findings above; scan for it explicitly, because a value that flows from the client into a trusted write is the single most common real breach.

The principle is stack-independent. The detection: trace user-controllable input to any consequential decision and ask **"what stops the client from lying here?"** If the only enforcement lives in client code (a React handler, the mobile app) with no server / RLS / cloud-function counterpart, that is a finding — severity set by what the lie buys the user.

**Must be server-authoritative — flag if enforced only on the client:**
- **Access and authorization decisions.** A client role check hides a button; it does not protect the endpoint. There must be a server- or RLS-side counterpart. (Cross-references section 2.)
- **Prices, totals, discounts, tax.** Never trust an amount sent from the client. The server computes from a server-side source of truth. A checkout that charges `req.body.amount` or `body.price` is a P0.

```bash
rg -n 'body\.(amount|price|total|cost|quantity|discount)|req\.body\.(amount|price|total)' --type ts --type js
```
- **Consumption of inventory, credits, balance, quota.** The server decrements, atomically (see race conditions). "I have 3 credits left" from the client is a claim, not a fact.
- **Granting entitlement** — `premium`, `tier`, `role`, `is_admin`, `verified`, `credits`. Set by the server after it verifies the condition (payment, ownership), never accepted from the client. (Cross-references mass assignment and self-escalation.)
- **Payment and receipt verification.** Validated server-side against the provider. A client-sent "purchase succeeded" flag is forgeable.
- **Secrets** — third-party API keys for paid or privileged services, signing keys, DB credentials. If it is in the client bundle it is public (see secret leakage).
- **Security-consequential validation.** Client validation is fast feedback; the server must re-validate every input it then trusts.
- **Rate limiting and abuse controls** for anything costly or sensitive.
- **Tokens and expiries with security meaning** — reset tokens, session lifetimes, access windows. Server clock, server-generated (see time & money).
- **Webhook authenticity** — signature verified server-side (see idempotency).

**Can stay local — do not flag:**
- Pure presentation and UX state, formatting, optimistic UI.
- Client-side validation *in addition to* server validation — a fast-feedback layer, never the only one.
- Non-sensitive caching and non-security feature flags.

The tell is almost always the same shape: a client-controlled value reaching a trusted write or an access decision without the server recomputing or re-checking it. When you find one, the fix is not "validate harder on the client" — it is to move the decision server-side and treat the client value as a request, not a fact.

---

## 3. Injection and input validation

```bash
rg -n 'query\(`|execute\(`|raw\(`|\$\{.*\}.*(FROM|WHERE|INSERT|UPDATE|DELETE)' -i
rg -n 'dangerouslySetInnerHTML|innerHTML\s*=|eval\(|new Function\('
rg -n 'exec\(|execSync\(|spawn\(' --type ts --type js
```
- SQL built from a template literal containing user input → convert to a parameterized query.
- Is there a validation layer: `zod`, `joi`, `yup`, `valibot`, `class-validator`? If none exists and public endpoints do, that is P0/P1.
- File uploads: size limit, MIME/extension whitelist, and never placing the raw filename into a path.

---

## 4. Data layer

```bash
ls supabase/migrations prisma/migrations drizzle migrations 2>/dev/null
rg -n 'select\(.\*.\)|SELECT \*' -i
rg -n 'for\s*\(|\.map\(|forEach' -A3 | rg -n 'await'   # N+1 suspicion
rg -n 'float|double precision|REAL' -i --glob '*.sql'   # money type
rg -n 'new Date\(\)|Date\.now\(\)|toLocaleDateString' --type ts --type js
```

- **Migration discipline**: no migrations folder? Then where does the schema live? If it is edited by hand, that is P0 — environments will drift apart.
- **Indexes**: are foreign keys and columns used in `where`/`order by`/`join` indexed? Does the column order of a composite index match the query? Postgres does **not** index foreign keys automatically.
- **N+1**: an awaited query inside a loop → collapse into one query (`in`, join, or batch).
- **Unbounded queries**: list queries with no `limit`/`range`. This is the first thing to break as tables grow.
- **Pagination**: if offset pagination is used and the list will grow, propose cursor/keyset.
- **Money**: stored as a float → switch to integer minor units (cents) or `numeric`. Irreversible decision, so P0.
- **Dates**: stored in UTC, with zone information? Use `timestamptz` rather than `timestamp`.
- **Transactions**: are related writes wrapped in a single transaction (payment + record + balance)?
- **Soft delete / audit**: warn if user data is deleted irrecoverably while the business needs undo.
- **ID type**: sequential auto-increment IDs in a public API leak both predictability and business volume. Suggest UUIDv7/ULID (irreversible decision).

---

## 5. Idempotency and consistency

```bash
rg -n 'webhook|stripe|constructEvent|signature' -i
rg -n 'idempotenc' -i
rg -n 'retry|backoff' -i
```
- Does the webhook endpoint verify the signature? If not, anyone can forge a "payment succeeded" event → P0.
- What happens if a webhook, payment, or record-creation path receives the same request twice? Is there an idempotency key or a unique constraint?
- If retries exist, is the receiver idempotent (the mandatory partner of at-least-once delivery)?
- Is long-running work (reports, email, AI calls, video) running inside the HTTP request? It belongs in a queue or background job.

### Race conditions and read-modify-write

The most dangerous consistency bugs are not syntactic — the code is correct, the *interleaving* is wrong. This is where payment and inventory logic breaks, so scan it deliberately.

```bash
# read-then-write without a transaction (the classic non-atomic counter)
rg -n 'get\(\)|getDoc|\.data\(\)|findOne|SELECT' -A6 | rg -n 'update|set\(|save\(|UPDATE'
# manual counter mutation instead of an atomic operator
rg -n 'count\s*\+|balance\s*[-+]|inventory\s*[-+]' --type ts --type js | head -20
rg -n 'increment|FieldValue\.increment|atomic' -i
# multiple functions writing the same document/table
rg -n 'writeBatch|runTransaction|BEGIN|FOR UPDATE' -i
```

Check:
- **Read-modify-write outside a transaction.** `const doc = await get(); await set(doc.count + 1)` loses writes under concurrency — two clients read the same value, both write value+1, one increment vanishes. Use an atomic operator (`increment()`, `FieldValue.increment`, `UPDATE ... SET n = n + 1`) or a transaction.
- **Manual counters and balances.** Any `balance - amount`, `inventory - 1`, `count + 1` computed in application code and written back is a race unless it runs inside a transaction. This is exactly how a user spends the same credit twice.
- **Two writers, one document.** If more than one cloud function or endpoint writes the same record, ask what happens when they run at the same time. Last-write-wins silently discards the other's change.
- **Check-then-act.** `if (!exists) create()` and `if (balance >= price) charge()` are races unless check and act are atomic. Server-authoritative consumption plus a client guard is the pattern; a client-only guard is decorative.
- **In-flight guards.** For actions that spend inventory or money, is there a guard against a double-tap firing two parallel requests? The server must be the real defense, but the guard prevents the wasteful second transaction.

---

## 6. Time and money arithmetic

Silent, expensive, and invisible to a type checker. A wrong number that still type-checks ships to production and corrupts data or revenue.

```bash
rg -n 'new Date\(|Date\.now\(\)|getTime\(\)|setHours|getTimezoneOffset' --type ts --type js | head -30
rg -n 'expiresAt|expiry|duration|ttl|validUntil|renewal|activeUntil' --type ts --type js | head
rg -n 'price.*[*/]|amount.*[*/]|Math\.round|toFixed|parseFloat' --type ts --type js | head -20
```

Check:
- **Duration from `Date.now()` and local time.** `Date.now() + days*86400000` is fine in UTC but breaks the moment local time, DST, or the device clock enters the calculation. Expiries, boosts, trials, and subscription periods are computed and stored in UTC; the display layer localizes.
- **Timezone drift.** `new Date('2026-01-01')` parses as UTC, `new Date(2026,0,1)` as local — mixing them shifts dates by hours. Any date crossing the client/server boundary should be ISO 8601 with an explicit zone.
- **DST edges.** "Every day at 9am" and "24 hours from now" are not the same thing twice a year. Recurring schedules built by adding milliseconds drift across a DST change.
- **Float money.** `0.1 + 0.2 !== 0.3`. Price arithmetic in floating point accumulates error. Store and compute in integer minor units; format to a decimal only for display. (Storage is flagged in the data layer; here the concern is *computation*.)
- **Rounding order.** Rounding before summing vs. after gives different totals; per-line-item vs. per-invoice rounding is a reconciliation bug. Tax and discount multiplication order matters — decide it once, be consistent.
- **Client-supplied time.** Never trust a timestamp, expiry, or duration from the client for anything with money or access implications. The server sets the clock.

---

## 6b. Startup and performance

Read `performance-audit.md` in full before scanning this category. Never write a performance finding without a measured number.

---

## 7. Error handling and observability

```bash
rg -n 'catch\s*\(\s*\w*\s*\)\s*\{\s*\}' -U          # swallowed errors
rg -n 'console\.(log|error)' src/ | wc -l
rg -n 'Sentry|Crashlytics|Bugsnag|captureException' -i
# IMPORTANT: the search above only finds off-the-shelf SDKs. A hand-rolled error
# system is invisible to it. Run this BEFORE claiming "no error tracking":
rg -n 'errorReporter|reportError|logError|trackError|onerror|unhandledrejection|window\.addEventListener\(.error' -i
rg -n 'ErrorBoundary'
rg -n 'fetch\(' --type ts --type js | head -30       # any timeouts?
```
- Silently swallowed `catch` blocks → at minimum, log them.
- No error tracking in production means the user experiences the bug and you never learn about it. Even on a small project this is P1.
- Without an ErrorBoundary in React, a single component error is a white screen.
- `fetch` calls with no timeout/AbortSignal can hang forever.
- Are emails, phone numbers, or tokens being written to logs? That is a privacy problem too.
- Is there a correlation/request ID (if there is a backend)?

---

## 8. Async, cancellation, resource leaks

```bash
rg -n 'useEffect' -A8 | rg -n 'fetch|subscribe|setInterval|addEventListener'
rg -n 'AbortController|AbortSignal|cancel'
rg -n 'setInterval|setTimeout' -A5 | rg -n 'clear'
```
- Are fetches, subscriptions, and intervals started inside `useEffect` cancelled on cleanup?
- Are realtime/WebSocket subscriptions closed on unmount (a frequent leak with Supabase Realtime and Firestore)?
- Are rapidly repeated searches debounced, and can a late response from an old request overwrite a newer one (race condition)?
- Is there a cap on concurrent requests, especially for paid APIs?

---

## 9. API surface

- Rate limits, especially on `login`, `register`, `forgot-password`, OTP, and expensive AI endpoints. Without them you get brute force and runaway bills.
- Is the error format consistent? Are stack traces or SQL errors reaching the client (information disclosure)?
- Is CORS set to `*`, and is it combined with credentialed requests?
- Security headers (CSP, HSTS, X-Content-Type-Options) on the web.
- Is the pagination limit capped (is `?limit=100000` rejected)?

---

## 10. Configuration and deploy hygiene

```bash
ls .github/workflows .gitlab-ci.yml 2>/dev/null
rg -n 'localhost|127\.0\.0\.1|http://' src/ --type ts --type js
cat .nvmrc .node-version 2>/dev/null; rg -n '"engines"' package.json
```
- Are environments separated (distinct dev/prod databases and keys)? Sharing one database is P0.
- Have hardcoded URLs or `localhost` leaked into production code?
- Is the build in production mode, and are source maps being published?
- No CI? Propose a minimal pipeline that at least runs build and lint.
- Is the lockfile committed?

---

## 11. Store and regulatory compliance (mobile / user data)

- Is there an account deletion flow? **Mandatory** for App Store and Play for any app that creates accounts. Its absence is a rejection reason.
- Are the privacy policy and terms reachable from inside the app?
- Does the Play Data Safety / App Privacy form match what the code actually collects? An analytics SDK may be collecting quietly.
- Are permission prompts justified and requested at the right moment (not all at launch)?
- Is iOS ATT required (any advertising or tracking)?
- GDPR/CCPA: retention period, deletion request flow, data minimization, possibility of minors (COPPA / age gate).
- With an ad SDK: correct configuration for child-directed content.

---

## 12. Comment–code mismatch

The single highest-yield pattern in the scan. When a comment claims a safeguard *exists*, verify the safeguard is actually in the code. Comments like "limit added", "authorization checked", "sanitized", "cached", or "rate limited" survive the refactors that delete the code itself — and mislead every future reader, including you.

```bash
rg -n -i 'limit|sanitiz|validat|auth|secure|cache|check|fix|TODO|FIXME|HACK|temporary' \
  -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' | rg '//|/\*|#'
```

For each matching comment, read the 5–10 lines beneath it: is the thing the comment describes actually there? If not, that is a finding and usually a P0, because nobody suspects that spot. Surface `TODO`/`FIXME`/`temporary` tags on security or limit comments separately.

The same logic applies to: a security setting defined in config but never used, a validation function written but never called, a rate-limit constant defined but never enforced.

**The reverse case counts too.** A comment may *overstate* severity — a `CRITICAL` tag on something that turns out to be a revenue leak rather than a vulnerability. Reprioritize based on what the code does, not what the comment claims.

---

## 13. Firebase / Firestore

The Postgres/Supabase sections do not apply here. Firebase's critical points are different:

```bash
cat firestore.rules storage.rules 2>/dev/null
cat firestore.indexes.json 2>/dev/null
rg -n 'onSnapshot|collection\(|query\(' --type ts --type js
rg -n 'limit\(|orderBy\(|startAfter\(' --type ts --type js
```

- **Security rules are the only line of defense.** The client talks to the database directly; `allow read, write: if true` or `if request.auth != null` (everything to any signed-in user) is a common and critical mistake. Rules must check the record's owner or tenant.
- **Rules vs. code alignment:** do the rules validate the fields the code writes (`request.resource.data` checks)? Without them a user writes whatever field they like — Firestore's version of mass assignment.
- **Unbounded `onSnapshot`**: a realtime listener without `limit()` inflates both the read bill and client memory as the collection grows. In Firestore, cost is a function of **documents read**, which makes an unbounded query far more expensive here than in Postgres. Chat, notification, log, and activity-feed collections are the riskiest.
- **Listener cleanup**: is the value returned by `onSnapshot` (the unsubscribe function) called in the `useEffect` cleanup? If not, you get both a leak and a recurring bill.
- **Composite indexes**: are the `where` + `orderBy` combinations declared in `firestore.indexes.json`? If not, the query fails in production.
- **Denormalization cost**: counters and totals computed on every read should live in a field maintained with `increment()`.
- **Storage rules**: are file size and content-type constrained? Without them anyone uploads anything, without limit.
- **Quota blowout**: is there a budget alarm (App Check + budget alert)?

---

## 14. Dependencies and supply chain

The code you did not write is still code you ship. A compromised or abandoned dependency is a live attack surface, and a lockfile problem is how the same repo builds differently on two machines.

```bash
ls package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null
npm audit --production 2>/dev/null | tail -20 || echo "run npm audit manually"
rg -n '"(preinstall|postinstall|prepare)"' package.json
rg -n '"[^"]+":\s*"(\*|latest|>=?0)' package.json    # unpinned ranges
```

Check:
- **Lockfile committed and honored.** No lockfile means every install is a different build. A lockfile that drifts from `package.json` is nearly as bad. Installs in CI should use the frozen lockfile (`npm ci`, not `npm install`).
- **`npm audit` triage — not blind upgrading.** Read the output, but do not propose upgrading everything. A critical advisory in a transitive dev dependency that never runs in production is not the same as one in a runtime path. Rank by whether the vulnerable code is actually reachable in the shipped app.
- **Install scripts.** `postinstall`/`preinstall` scripts run arbitrary code at install time — the primary supply-chain attack vector. Flag any dependency that adds one, especially recently added or low-download packages.
- **Unpinned ranges.** `"*"`, `"latest"`, or a wide `">=0"` range means an install can silently pull a new major. For anything security-relevant, pin.
- **Abandoned and duplicated packages.** A dependency with no releases in years, or two packages doing the same job (two date libraries, two HTTP clients), is both a bundle-size and a maintenance finding.
- **Phantom dependencies.** Code that imports a package not listed in `package.json` (it resolves only because a transitive dep happens to provide it) breaks the moment that transitive tree changes.

Do not turn this into a wall of "upgrade X to Y". The output is a *ranked* short list: what is actually reachable, what runs at install time, what is unpinned in a security-relevant spot.

---

## Over-engineering filter

Do **not** propose the following without evidence of need:
- Kubernetes, service mesh, microservices (solo developer or <10k users)
- CQRS, event sourcing, sagas (no distributed transactions)
- Sharding, read replicas (no measured single-database bottleneck)
- Distributed tracing (single service)
- A hand-rolled auth system (when a provider is available)
- GraphQL (single client, simple data model)
- Redis (no measured caching need)

If one of these is already present and unnecessary, note it in the report as a "simplification opportunity" — but never remove it automatically.
