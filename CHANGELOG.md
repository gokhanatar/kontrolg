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
