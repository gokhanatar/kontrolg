# Store Rules — Detection Patterns

Commands assume `ripgrep` (`rg`). Exclude `node_modules`, `build`, `Pods`.

**Policy changes. These notes reflect the rules as of the skill's writing.** When a threshold matters (target API level, SDK minimums, deadline dates), verify against the official page rather than trusting the number here:
- App Store Review Guidelines — `https://developer.apple.com/app-store/review/guidelines/`
- Play Developer Policy Center — `https://play.google.com/about/developer-content-policy/`

An admitted gap is fine. A confidently wrong policy claim is not.

---

## 1. Account deletion — the single highest-frequency blocker

Both stores require it for any app that lets users create an account. Apple under Guideline 5.1.1(v); Play under its account deletion policy, which also wants a **web-accessible** deletion URL, not only an in-app path.

```bash
rg -n -i 'delete.?account|account.?deletion|deleteUser|closeAccount|remove.?account|hesab.*sil' --type ts --type js --type tsx 2>/dev/null
rg -n -i 'deleteUser|admin\.auth\(\)\.deleteUser|auth\.currentUser' functions/ src/ 2>/dev/null
```

**Confirming step:** a match on a string is not a working flow. Open it and check that the path is reachable from the UI, that it deletes server-side data and not just the local session, and that it does not merely open an email composer. "Contact support to delete your account" does not satisfy either store.

Check:
- Reachable in-app without contacting support
- Deletes the auth record **and** associated user data
- A public web URL for Play, listed in the Play Console
- If deletion is partial (legal retention of transaction records), that is allowed but must be disclosed to the user at the moment of deletion
- Subscriptions: the flow should tell the user that deleting the account does not cancel a store subscription

---

## 2. Privacy declarations vs. what the code actually does

The most common silent failure. The developer fills the form honestly about their own code and forgets that an SDK collects more.

```bash
rg -n '"(firebase|@react-native-firebase|@capacitor-firebase|amplitude|mixpanel|posthog|segment|sentry|@sentry|appsflyer|adjust|facebook|react-native-fbsdk|google-mobile-ads|@capacitor-community/admob|onesignal|branch|smartlook|clarity)' package.json
rg -n -i 'analytics|logEvent|track\(|identify\(|setUserId|setUserProperty' src/ | head -30
rg -n -i 'getCurrentPosition|watchPosition|Geolocation|Contacts|Camera|PhotoLibrary|HealthKit' src/ | head -20
```

Build the actual list: for each SDK and each call site, what data category leaves the device? Compare that list against what the user says the store forms declare. Every mismatch is a finding — an undeclared collection is a rejection, and an over-declaration is a needless privacy label that hurts conversion.

Watch specifically for:
- Ads or attribution SDKs collecting device identifiers the developer never declared
- Crash reporting attaching user IDs, emails, or breadcrumbs containing personal data
- Analytics `identify()` calls carrying email addresses
- A "linked to identity" distinction: the same data category is declared differently depending on whether it is tied to a user account

The forms themselves cannot be inspected from the repo. Put them in the report's **"needs your confirmation"** section as explicit questions.

---

## 3. iOS privacy manifest and required-reason APIs

Apple requires a privacy manifest for apps and for many third-party SDKs, declaring collected data types, tracking domains, and a reason code for certain APIs.

```bash
find ios -name 'PrivacyInfo.xcprivacy' 2>/dev/null
rg -n 'UserDefaults|NSUserDefaults|Preferences' src/ ios/ 2>/dev/null | head
rg -n 'creationDate|modificationDate|fileModificationDate|systemUptime|mach_absolute|freeDiskSpace|volumeAvailableCapacity|activeInputModes' ios/ src/ 2>/dev/null | head
```

Check:
- Does `PrivacyInfo.xcprivacy` exist in the app target?
- Do the required-reason API categories used by the app appear with a reason code — file timestamp, system boot time, disk space, active keyboard, and user defaults are the categories that catch people
- Capacitor and its plugins touch `UserDefaults` through `Preferences`; that counts
- Third-party SDKs must ship their own manifests and signatures — an outdated SDK version without one blocks the upload
- If the app tracks: `NSPrivacyTracking` true plus the tracking domains listed, and ATT actually requested before any tracking begins

The manifest is validated at upload, so a gap here fails before a human ever reviews it.

---

## 4. Permissions and purpose strings

```bash
cat android/app/src/main/AndroidManifest.xml 2>/dev/null | rg -n 'uses-permission|uses-feature'
rg -n 'NS.*UsageDescription' ios/App/App/Info.plist 2>/dev/null
```

Three separate failure modes, and all three are common:

**Declared but unused.** A permission in the manifest that no code path uses. Frequent with Capacitor, where installing a plugin injects permissions you never call. Reviewers ask why you want it; the honest answer is that you do not. Remove it.

**Used but undeclared.** Runtime crash or silently broken feature.

**Generic purpose strings.** `NSCameraUsageDescription` set to "This app uses the camera" is a rejection under 5.1.1. It must say what for, in user terms: "Photos you take are attached to your report and visible to your building's management."

Also check:
- Android media permissions on modern API levels: the granular `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / photo picker path rather than blanket storage access
- `QUERY_ALL_PACKAGES` — restricted; needs a qualifying use case or it blocks the release
- Foreground services need a declared type and a policy justification
- Advertising ID: on Android it needs a permission declaration and a Play Console answer; if the app is child-directed it must not be used at all
- SMS and call log permissions are restricted and require a declaration form; if a plugin dragged one in, remove it
- Background location triggers a separate, slow review — is it genuinely needed?

---

## 5. Minimum functionality — the webview wrapper trap

Apple Guideline 4.2. **The highest-risk area for a Capacitor or wrapper app**, and the hardest to fix late, because the fix is product work rather than configuration.

```bash
cat capacitor.config.* 2>/dev/null
rg -n 'server:|url:|allowNavigation' capacitor.config.* 2>/dev/null
rg -n '@capacitor/' package.json
```

Signals that raise the risk:
- `server.url` pointing at a remote site — the app is loading a website rather than bundling an app. This is the classic 4.2 / 4.2.2 rejection.
- No native plugins at all beyond the defaults: no push, no camera, no biometrics, no share, no haptics, no offline behavior. If everything works identically in mobile Safari, the reviewer asks why it is an app.
- Content that is only a feed of a website, or a repackaged blog

What to check and recommend: does the app do at least a few things a website cannot — push notifications, offline use, native share, camera or biometrics, home-screen widgets, background sync? At least one substantive native capability, working and discoverable, is what moves a build out of 4.2 risk.

**Do not suggest disguising a wrapper.** If the app is genuinely a website in a shell, say so directly; the fix is to add real native value, not to hide the shell.

---

## 6. Payments

```bash
rg -n -i 'stripe|paypal|iyzico|paddle|lemonsqueezy|checkout|payment' src/ | head -20
rg -n '@capgo/native-purchases|react-native-iap|@revenuecat|purchases' package.json
rg -n -i 'subscription|premium|upgrade|pro plan' src/ | head -20
```

- Digital goods and in-app features consumed inside the app must use the platform's in-app purchase, both stores. Physical goods and real-world services use external payment — and must **not** use IAP.
- Any external purchase link is a hard rejection outside the narrow, region-specific exceptions and their entitlements. If the app links out to a web checkout for a digital subscription, that is a blocker.
- Subscription screens must show, before purchase: title, length, price per period, what is included, and links to the terms and privacy policy. Missing these is a routine rejection.
- Restore purchases must exist and work on iOS.
- Receipt validation should happen server-side. Client-only validation is a fraud finding rather than a store one, but it belongs in the report.
- Free trials must state exactly when billing begins.

---

## 7. User-generated content

If users can post, message, or upload anything visible to another user, Apple 1.2 and Play's UGC policy both apply. This is a hard requirement set, not a suggestion.

```bash
rg -n -i 'report|block.?user|moderat|flag.?content|abuse' src/ | head -20
rg -n -i 'terms|eula|agree' src/ | head -10
```

Required, all four:
- A way to report objectionable content
- A way to block an abusive user
- A published means of contacting the developer about reports
- A stated commitment to act on reports, with an EULA the user accepts

Plus: filtering of objectionable content (automated, manual, or both), and removal of the reporting user's exposure quickly. Apps with chat or profiles that lack a block function get rejected reliably.

---

## 8. Build configuration

```bash
rg -n 'compileSdk|targetSdk|minSdk|versionCode|versionName' android/app/build.gradle 2>/dev/null
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|IPHONEOS_DEPLOYMENT_TARGET' ios/App/App.xcodeproj/project.pbxproj 2>/dev/null | head
rg -n 'billing|com.android.billingclient' android/app/build.gradle 2>/dev/null
```

- Play enforces a rolling **target API level** minimum for new releases and updates; existing apps that fall behind stop being discoverable. Verify the current requirement and deadline on the policy page rather than assuming.
- Android needs 64-bit support and the App Bundle format.
- The Play Billing Library also has a rolling minimum version — check it if the app sells anything.
- iOS builds must be made with a recent SDK; Apple enforces a minimum.
- Version code must exceed the last uploaded build. A duplicate version is a rejected upload, not a rejected review — cheap to catch here.
- Debug flags, test endpoints, and staging URLs must not be in the release configuration.

---

## 9. Store listing

Not in the repo, so most of this belongs in "needs your confirmation" — but ask about all of it, because listing problems delay a submission just as effectively as code problems:

- Privacy policy URL, live and reachable (both stores require it; Play requires it in the listing, Apple in App Store Connect)
- Support URL that resolves to something real
- A **working demo account** if any content sits behind a login — the most common avoidable delay, because the reviewer simply cannot get in. Include any second factor workaround and a note for region-locked content.
- Review notes explaining anything non-obvious, especially permissions and any hardware the app expects
- Screenshots for every required device size, showing the actual app rather than marketing art
- Description free of competitor names, unsupported claims, and keyword stuffing
- Age rating answers consistent with the content, including UGC and in-app purchases
- If the app requires external hardware or a specific region, say so in the notes or expect a rejection for "unable to review"

---

## 10. Children and families

If children could plausibly use the app, or it is declared child-directed, an extra and stricter set applies: Play's Families policy, Apple's Kids Category rules, plus COPPA and GDPR-K.

Check for: no behavioral advertising, no advertising identifier collection, certified ad SDKs only, no external links or purchases outside a parental gate, age screening where appropriate, and a privacy policy addressing children's data.

Misdeclaring a child-directed app is one of the few store issues that carries regulatory consequences beyond a rejection. If the audience is ambiguous, say so and recommend the user resolve it deliberately rather than defaulting.

---

## 11. Encryption export compliance

```bash
rg -n 'ITSAppUsesNonExemptEncryption' ios/App/App/Info.plist 2>/dev/null
```

Missing the key means every upload stops to ask. Nearly all apps qualify for the standard exemption (HTTPS and platform crypto only), but the declaration still has to be present and correct. If the app ships custom or non-standard cryptography, the exemption does not apply and further documentation is required — flag it rather than guessing.

---

## 12. OTA updates and live updates

If the project uses Capacitor Live Update, CodePush, or similar:

```bash
rg -n 'live-update|codepush|@capgo/capacitor-updater' package.json
```

Pushing JavaScript over the air is permitted within limits: the update must not change the app's primary purpose or add features the reviewed build did not have. A wrapper that swaps its entire content remotely violates that, and it is also how apps get removed rather than merely rejected. Check what the update channel is actually allowed to replace, and note it.

---

## What not to flag

Keep the report credible by leaving these alone unless there is a real signal:
- Cosmetic UI issues that are not accessibility or policy problems
- Performance, unless it is bad enough to read as "app is broken" to a reviewer (that is 2.1)
- Architectural opinions — that is `kontrolg`'s job, not this skill's
- Speculative "the reviewer might not like" items with no rule behind them. Every risk entry should be traceable to a policy area; if it is only a hunch, leave it out.
