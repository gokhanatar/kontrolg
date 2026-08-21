---
name: store-preflight
description: Checks a mobile app for App Store and Google Play rejection risks before submission. Detects the stack, scans for the concrete policy violations that actually cause rejections (missing account deletion, privacy manifest gaps, permission declarations that do not match the code, Data Safety mismatches, minimum functionality risk for webview wrappers), and produces a prioritized report with file-and-line evidence. Use this skill when the user says "store-preflight", "/store-preflight", "am I ready to submit", "will this get rejected", "app store review check", "play store compliance", "prepare for submission", or is about to ship a mobile release. Also use it when a user has already been rejected and wants to find out why.
---

# store-preflight — Submission Readiness Check

A rejection costs one to three days. Almost all of them come from the same short list of causes, and almost all of those are detectable in the repo before you ever hit submit.

This skill finds them. It is not a general code audit — for that, use `kontrolg`. This one asks a single question: **would a reviewer reject this build, and why?**

## Core principles

1. **No finding without evidence.** File path and line number, or a concrete absence ("this file does not exist"). "Review the privacy policy" is not a finding.
   - **Claiming something is absent is harder than claiming it is present.** One grep returning nothing does not prove a feature is missing — the project may implement account deletion inside a settings screen with a name you did not search for. Run a second, broader search and open the file before writing an absence finding.
2. **Separate hard blockers from risk.** A missing account deletion flow is a guaranteed rejection. Weak screenshots are a maybe. Marking everything critical trains the user to ignore the report.
3. **The form must match the code.** The most common silent failure is a privacy declaration that does not match what the app actually collects — usually because an analytics or ads SDK collects something the developer forgot about. The code is the source of truth; the form is what gets you rejected.
4. **Never guess at policy.** Store rules change. When you are unsure whether a rule still applies or what the current threshold is, say so and point the user at the official page rather than inventing a requirement. A confidently wrong policy claim is worse than an admitted gap.

---

## Flow

### Phase 0 — Preflight

```bash
git status --porcelain && git branch --show-current
```

If the tree is dirty, ask the user to commit or stash before any fix phase. Create `store-preflight/<date>` for remediation. No git means report only.

### Phase 1 — Discovery

```bash
ls -la; cat package.json 2>/dev/null
cat capacitor.config.* 2>/dev/null
ls ios/App/App 2>/dev/null; ls android/app/src/main 2>/dev/null
cat android/app/build.gradle 2>/dev/null | head -40
```

Determine:
- **Platform**: iOS, Android, or both. Native, Capacitor, React Native, Flutter?
- **Store presence**: is this a first submission or an update? (An update to a live app is judged against a different risk profile — new permissions and new SDKs are what break it.)
- **Account model**: does the app create accounts? This single answer drives the highest-frequency blocker on both stores.
- **Monetization**: IAP, subscriptions, ads, external payments?
- **Content model**: user-generated content, chat, user profiles?
- **Audience**: could children plausibly use it? Is it declared as child-directed?
- **Sensitive data**: location, health, financial, contacts, photos?

Ask only what the code cannot answer — at most three questions in one batch. Absent answers, assume the stricter case and say so in the report.

### Phase 2 — Scan

Read `references/store-rules.md`. Scan in this order — the top entries cause the most rejections:

1. Account deletion (both stores; a hard blocker for any app with accounts)
2. Privacy declarations vs. actual code (App Privacy labels, Play Data Safety)
3. iOS privacy manifest and required-reason APIs
4. Permissions: declared but unused, used but undeclared, missing or generic purpose strings
5. Minimum functionality — the real risk for webview wrappers
5b. Completeness and originality — launch crash, "coming soon"/placeholder screens, a feature the reviewer cannot find (2.1); template/reskin similarity across a portfolio (4.3)
6. Payments: IAP where required, external payment links, subscription disclosure
7. User-generated content: moderation, reporting, blocking, EULA
8. Target API level, SDK minimums, build configuration
9. Store listing: privacy policy URL, support URL, demo account, screenshots
10. Children and families policy, if plausibly applicable
11. Encryption export compliance

For anything that does not apply, write one line — **"not applicable — why"** — and move on.

### Phase 3 — Report

Create `STORE-PREFLIGHT.md` at the project root:

```markdown
# Store Preflight — [date]

## Verdict
[One paragraph: submit, submit with risk, or do not submit yet. Then the count of blockers.]

Platforms: ...
Submission type: first / update
Assumptions: ...

## Blockers — will be rejected
### [Finding]
- **Where:** `path/file:42` (or: file absent)
- **Rule:** [store, guideline number where known]
- **Why it fires:** [what the reviewer sees]
- **Fix:** [concrete]
- **Effort:** S / M / L

## Risks — may be rejected, depends on the reviewer
## Listing gaps — fix before you submit the metadata
## Not applicable
## Needs your confirmation
[Things the code cannot prove: is the privacy policy live, does the Data Safety form say X, is the demo account working. List them as questions.]
```

Then give the user a short chat summary: blocker count, the three worst items, and a plain submit / do-not-submit verdict. Do not paste the report into chat.

### Phase 4 — Remediation

Offer: **everything / blockers only / pick individually.** Wait for the answer.

Then work autonomously: change, build, commit as `store-preflight: [area] description`, log it.

**Ask first, even in an approved pass:**
- Anything that changes the store listing itself (descriptions, screenshots, categories, age rating) — that is publishing, not code
- Submitting or uploading a build
- Changing the Data Safety or App Privacy declarations — these are legal attestations; you can tell the user exactly what to select, but the user selects it
- Adding a dependency
- Removing a permission that a feature may still depend on
- Changes to the payment flow

**Never:**
- Write a privacy policy that claims something you have not verified in the code
- Fill in a compliance form on the user's behalf
- Advise on how to make a rejected build "look" compliant to a reviewer while remaining non-compliant. If the app genuinely violates a policy, say so plainly — the fix is the behavior, not the presentation.

### Phase 5 — Close out

- Complete the log, list what remains
- Repeat the "needs your confirmation" list — those are the items no scan can close
- If anything was deployed or submitted, say what and how to roll back

---

## Re-running

If `STORE-PREFLIGHT.md` exists, read it, mark previous findings resolved or open, and surface only new items and regressions.

`store-preflight ios` or `store-preflight android` narrows the scan to one platform; Phase 0 and Phase 3 still run.

## Reference files

- `references/store-rules.md` — Concrete detection commands and the policy areas behind them, per platform. Read in Phase 2.
