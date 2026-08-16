# Performance Audit

Security findings are binary (RLS is on or off). Performance findings are not. So this file works differently from the others: **measure first, then find, then measure again.**

---

## 0. Do not optimize without measuring

No exceptions. "Optimization" without measurement harms in three ways: it speeds up the wrong place, it makes the code unreadable, and it hides the real bottleneck.

**Every performance pass starts here:** take the baseline and write it into `KONTROLG-REPORT.md`. No number, no finding.

```bash
# Bundle size (after build)
du -sh dist build .next 2>/dev/null
find dist build .next -name '*.js' -size +100k 2>/dev/null | xargs -r ls -lhS | head -10

# Dependency weight
du -sh node_modules 2>/dev/null
npx source-map-explorer 'dist/assets/*.js' --no-border-checks 2>/dev/null || echo "source-map-explorer not installed"

# Build time
time npm run build
```

Ask the user for the browser-side numbers you cannot produce: Lighthouse score, request count and total transfer on first load from the Network tab, and the three most expensive components in the React DevTools Profiler.

**Budget table** — this, not "it feels slow", decides whether a finding is P0 or P2:

| Metric | Good | Acceptable | Finding |
|---|---|---|---|
| Initial JS bundle (gzip) | <200 KB | <500 KB | >500 KB |
| Single chunk | <150 KB | <300 KB | >300 KB |
| LCP | <2.5 s | <4 s | >4 s |
| INP | <200 ms | <500 ms | >500 ms |
| Requests on first screen | <10 | <20 | >20 |
| API p95 | <300 ms | <1 s | >1 s |
| Mobile cold start | <2 s | <4 s | >4 s |

---

## 1. Classify the bottleneck first

Misclassification is the most expensive mistake — trying to parallelize an I/O-bound problem, or trying to cache a CPU-bound one. From symptom to class:

| Symptom | Class | Solution family | Wrong solution |
|---|---|---|---|
| UI freezes, taps lag | CPU-bound (main thread) | Web Worker, chunking, algorithm | Caching, parallel requests |
| Long blank screen, then fast | Network / bundle | Code splitting, prefetch, CDN | Memoization |
| Data arrives late, single request | I/O-bound (server/DB) | Index, query, cache | Worker, memo |
| Many small requests | Network waterfall | Batch, join, parallelize, prefetch | Scaling the server |
| Stutters while scrolling a list | Render-bound | Virtualization, memo, key | Server-side work |
| Degrades over time | Memory leak | Cleanup, remove listeners | More RAM |
| Slow only for some users | Data volume | Pagination, limits, indexes | General optimization |

**The practical test for CPU-bound vs. I/O-bound:** during the work, is the main thread busy (UI frozen) or waiting (UI smooth but no data)? Frozen means CPU, waiting means I/O. Confusing the two means moving a `Promise.all` problem into a Worker, or the reverse.

---

## 2. Startup (the most common complaint)

```bash
# What is in the entry file — everything here delays the first frame
cat src/main.tsx src/main.ts src/index.tsx 2>/dev/null
rg -n "^import .* from" src/App.tsx src/App.jsx 2>/dev/null | head -30

# Dynamic import usage (few means no code splitting)
rg -c 'import\(' src/ 2>/dev/null
rg -n 'lazy\(|Suspense' src/ 2>/dev/null | head

# Work performed at startup
rg -n 'useEffect\(\s*\(\)\s*=>' src/App.* src/main.* 2>/dev/null -A5
```

Check:
- **Every import in the entry file delays the first frame.** Analytics, charting, maps, AI SDKs, PDF generators, rich-text editors — if it is not on the first screen, `lazy()` + `Suspense`.
- **Is there route-based splitting?** Without it the user downloads the code for eight pages they will never open.
- **How many network requests fire at startup?** Anything not needed for the first screen should be deferred. More than three parallel startup requests deserves justification.
- **Does the auth check block?** If the screen stays white until the session is validated, can it render optimistically with a skeleton?
- **Synchronous storage reads.** A large JSON parse from `localStorage`/`Preferences` at startup blocks the main thread.
- **When does the splash screen close?** Closing before data arrives shows a blank screen and makes perceived speed worse; close into a skeleton.
- **Fonts and images.** Without `font-display: swap`, text waits invisibly.

---

## 3. Bundle and dependency weight

```bash
rg -n '"(moment|lodash|chart\.js|three|@ffmpeg|pdfjs|jquery|axios)"' package.json
rg -n "from 'lodash'" src/          # whole library, not a single import
rg -n "from 'date-fns'|from 'moment'" src/
```

| Heavy dependency | Alternative | Saving |
|---|---|---|
| `moment` | `date-fns` (single imports) or `Intl` | ~230 KB |
| `import _ from 'lodash'` | `lodash-es` + single imports | ~70 KB |
| `axios` | native `fetch` | ~15 KB |
| `three`, `chart.js`, editors | defer with `lazy()` | varies |

Also: are there two libraries doing the same job (two date libraries, two HTTP clients)? Is a package that belongs in `devDependencies` sitting in `dependencies`? Is `import *` breaking tree-shaking?

---

## 4. Network layer

```bash
rg -n 'await fetch|await supabase|await axios' src/ -B3 | rg -n 'for |\.map\(|forEach'
rg -n 'Promise\.all' src/
rg -n 'select\(.\*.\)|select\("\*"\)' src/
```

- **Request waterfall:** requests that do not depend on each other running sequentially → `Promise.all`. One of the highest-yield one-line fixes there is.
- **Requests inside a loop:** the network flavour of N+1. Collapse into one batched call.
- **Over-fetching:** pulling 30 columns with `select('*')` and using three. On mobile that is bandwidth and battery directly.
- **No pagination:** a list query without `limit` is both a performance *and* a cost finding.
- **Compression:** is the server serving gzip/brotli?
- **Client cache:** is `react-query`/`swr` present? If not, is the same data refetched on every mount? An unset `staleTime` produces needless refetches by default.
- **Debounce:** does a search or filter input fire a request on every keystroke?

---

## 5. Render layer (React)

```bash
rg -n 'useMemo|useCallback|React\.memo' src/ | wc -l
rg -n 'key=\{.*index.*\}' src/          # index used as key
rg -n '\.map\(' src/ -A2 | rg -n 'onClick=\{\(\)' # new function per render
rg -n 'createContext' src/
```

- **Long lists:** 100+ items rendered means virtualization (`react-window`, `@tanstack/react-virtual`). The number-one cause of scroll stutter.
- **`key={index}`:** unnecessary re-renders and state mix-ups when the list changes.
- **Overly broad context:** a frequently changing value in a single context re-renders every consumer. Split frequent from infrequent.
- **Expensive computation in render:** filtering, sorting, or `JSON.parse` in the render body → `useMemo`.
- **Sprinkling `memo` without measuring:** an anti-pattern. `React.memo` adds comparison cost on every render; without Profiler evidence, do not add it.

---

## 6. Caching — which layer

Caching at the wrong layer is worse than no caching (stale data plus complexity). Decide:

| Data | Layer | TTL |
|---|---|---|
| Static assets (js, css, images) | CDN + immutable header | 1 year (hashed filenames) |
| Rarely changing reference data (cities, categories) | Client memory + localStorage | hours |
| User-specific lists | react-query / SWR | seconds–minutes |
| Expensive computed results | Server (Redis / DB table) | per business rule |
| Session/identity | Do not cache | — |

Every time a cache is added, **answer two questions in the report:** (1) what happens if stale data is shown? (2) which event invalidates it? A cache with no answer does not get added.

Also, `stale-while-revalidate` is the right default for most lists: show the old data immediately, refresh behind it.

---

## 7. CPU-bound work

```bash
rg -n 'JSON\.parse|JSON\.stringify' src/ | head
rg -n '\.sort\(|\.filter\(.*\.filter\(|for\s*\(.*for\s*\(' src/ | head
rg -n 'Worker\(|new Worker' src/
```

- Large array processing, cryptography, image manipulation, PDF generation, big `JSON.parse` → Web Worker or chunking (`requestIdleCallback` / splitting into batches).
- Nested loops (O(n²)) — harmless on small data, the first thing to collapse as data grows. Can a `Map`/`Set` bring it to O(n)?
- Is the same computation repeated on every render (memoization)?

---

## 8. Memory

```bash
rg -n 'addEventListener' src/ -A5 | rg -n 'removeEventListener' | wc -l
rg -n 'setInterval|setTimeout' src/ -A5 | rg -n 'clearInterval|clearTimeout' | wc -l
rg -n 'onSnapshot|subscribe\(|\.on\(' src/ -A8 | rg -n 'unsubscribe|off\(|return \(\)'
```

The gap between registrations and cleanups is a direct leak candidate. Especially: realtime subscriptions, event listeners, timers, and unboundedly growing arrays/Maps (log buffers, message lists).

Symptom: the app slows the longer it stays open, and crashes after a while on mobile.

---

## 9. Images and assets

```bash
find . -path ./node_modules -prune -o \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) -size +200k -print 2>/dev/null
rg -n '<img' src/ | rg -v 'loading=' | head
```

- Images over 200 KB: convert to WebP/AVIF, resize to actual display dimensions.
- Are `loading="lazy"` and `width`/`height` (for CLS) present?
- Are unused assets shipping in the bundle?

---

## 10. Mobile / Capacitor specifics

- **Bridge call cost:** every native plugin call is a JS↔native serialization. Calls like `Preferences.get` inside a loop should become one batched read.
- **WebView first paint:** in Capacitor the bundle is read from local disk, so there is no network latency — which means the mobile startup bottleneck is usually *parse + execute*, not download. Shrinking the bundle still helps, but the bigger win is deferring work.
- **Lists plus images:** long list plus large images on a mobile GPU is the most frequent stutter combination.
- **Battery and network:** background intervals, permanently open realtime connections.

---

## 11. Server / database

Details live in `audit-rules.md` sections 4 and 13. The summary to check from here: missing indexes, N+1, unbounded queries, connection-pool limits, long transactions, synchronous third-party calls on the hot path.

---

## Verification — mandatory for every performance change

Before a performance fix is committed, this row must exist in the report:

```
| Change | Metric | Before | After | Gain |
|---|---|---|---|---|
| Lazy-load charting library | Initial bundle (gzip) | 612 KB | 388 KB | 37% |
```

An unmeasured change is not reported as a performance fix — it goes under "code cleanup". If the number got worse, the change is reverted.

---

## Optimization traps

These go into the report as "do not do":

- **Premature optimization:** scaling a feature that has no users yet.
- **Sprinkling `memo`/`useCallback` without measuring:** hurts readability, usually delivers no measurable gain.
- **Micro-optimization:** swapping loop constructs, `for` vs `forEach` — invisible next to network and render cost.
- **Caching everything:** stale-data bugs cost more than the cache saves.
- **Infinite `staleTime`:** the user cannot see fresh data and concludes the app is broken.
- **Unneeded infrastructure:** adding Redis, a CDN layer, or a queue without a measured bottleneck.
- **Ignoring perceived performance:** a skeleton screen and optimistic updates usually register more than 200 ms of real gain.
