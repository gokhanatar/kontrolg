# Concept Checklist

A pool of concepts to scan a project against. The point is not to memorize it — it is to sweep for **"does this exist in my project, and does it need to?"**

Priority logic:
- **P0 (expensive if not decided up front):** auth model, data model, indexing strategy, idempotency, migration discipline, logging/error tracking, secret management, multi-tenancy decision
- **P1 (right after the first release):** caching, rate limiting, queues, pagination strategy, test infrastructure
- **P2 (when scale arrives):** sharding, Kubernetes, tracing, CQRS, event sourcing

---

## 1. Architecture & code structure

- Layered architecture (controller → service → repository)
- Modular monolith vs. microservices vs. monolith
- Clean / hexagonal architecture, ports and adapters
- Domain-Driven Design, bounded context, aggregate root
- Folder-by-feature structure
- Dependency injection, inversion of control
- SOLID, DRY, KISS, YAGNI, separation of concerns
- Patterns: Repository, Factory, Strategy, Observer, Adapter, Decorator, Singleton
- Event-driven architecture
- CQRS (command/query separation), event sourcing
- Saga pattern, compensating transactions
- Outbox pattern (DB + queue consistency)
- API gateway, backend for frontend (BFF)
- Monorepo vs. polyrepo
- 12-Factor App principles
- Configuration management (env vars, config service, secret manager)
- Feature flags / toggles
- Semantic versioning, changelog
- **Idempotency** and idempotency keys
- Retry + exponential backoff + jitter
- Circuit breaker, bulkhead, fallback
- Timeout and deadline propagation
- Graceful shutdown, graceful degradation
- Middleware / interceptor / pipeline (auth, logging, validation, error handling)
- Dead code elimination, tech-debt register

## 2. Database & data layer

- Normalization / deliberate denormalization
- **Index** types: B-tree, hash, composite, partial, covering, unique
- Index cardinality and selectivity, the write cost of an index
- Column order in composite indexes (leftmost-prefix rule)
- Query planner, `EXPLAIN ANALYZE`, seq scan vs. index scan
- **N+1 queries**, eager vs. lazy loading
- Connection pooling, max connections, pgBouncer
- **Transactions**, ACID
- Isolation levels: read uncommitted / read committed / repeatable read / serializable
- Dirty read, non-repeatable read, phantom read
- Optimistic locking (version column) vs. pessimistic locking (`SELECT FOR UPDATE`)
- Deadlock, lock contention, the cost of long transactions
- Migrations / schema versioning, reversible migrations, expand-contract
- Soft delete vs. hard delete, `deleted_at`
- Foreign keys, cascade behavior, referential integrity
- Constraints: unique, check, not null (do not trust the application layer)
- **SQL vs. NoSQL**: document, key-value, wide-column, graph, time-series
- CAP theorem, eventual consistency, BASE
- Sharding, partitioning (range / hash / list), partition pruning
- Read replicas, replication lag, read-after-write consistency
- Materialized views, views
- Full-text search, GIN index, trigram, fuzzy search
- Vector index / pgvector (for AI features)
- **Row-Level Security (RLS)** — critical in Supabase/Postgres
- Stored procedures, triggers, database functions
- **Multi-tenancy** models: row-per-tenant, schema-per-tenant, db-per-tenant
- UUID vs. auto-increment; UUIDv7 / ULID (index-friendly sortable IDs)
- Audit log / changelog tables, temporal tables
- Backup strategy, point-in-time recovery, restore drills
- **ORM** vs. query builder vs. raw SQL; the hidden costs of an ORM
- Seed data, fixtures, factories
- Bulk insert / upsert (`ON CONFLICT`), batch writes
- Cursor-based iteration for large table scans

## 3. API design

- REST resource design, correct HTTP methods and status codes
- GraphQL: over/under-fetching, N+1, DataLoader, query depth limits
- gRPC, protobuf, schema evolution
- WebSocket, SSE, long polling — when to use which
- Webhooks: signature verification, replay protection, retries, idempotent receivers
- **Offset vs. cursor (keyset) pagination** — how offset collapses on large data
- Filtering, sorting, sparse fieldsets, page size limits
- API versioning (URL / header / content type)
- RFC 7807 problem+json — a standard error format
- An error code dictionary (a machine-readable `code` field for clients)
- **Rate limiting**: token bucket, leaky bucket, sliding window; per user/IP/endpoint
- Throttling, quotas, backpressure
- ETag / If-None-Match, conditional requests, 304
- CORS, preflight, credentialed requests
- Compression (gzip / brotli), payload size limits
- Batch / bulk endpoints
- OpenAPI (Swagger), contract-first development, generated clients
- Request validation schemas (zod, joi, class-validator)
- Consistent response envelopes

## 4. Security

### Identity & authorization
- **Authentication vs. authorization**
- Session-based vs. token-based auth
- JWT: access + refresh tokens, short lifetimes, rotation, revocation/blacklists, `jti`
- Where to store tokens (HttpOnly cookie vs. the risk of localStorage)
- OAuth 2.0, OpenID Connect, PKCE (mandatory on mobile)
- Social login, account linking
- MFA / 2FA, TOTP, recovery codes
- Password hashing: bcrypt / argon2id, salt, pepper; never plain MD5/SHA1
- Password reset flow: single-use, short-lived, non-leaking tokens
- **RBAC** (role-based), **ABAC** (attribute-based), ReBAC (relationship-based)
- Least privilege, separate service accounts

### Vulnerabilities
- **BOLA / IDOR** — accessing someone else's record by changing an ID (the number-one API flaw)
- BFLA — reaching an unauthorized function (an admin endpoint open to normal users)
- Mass assignment / over-posting (sending `is_admin: true`)
- **SQL injection** → parameterized queries / prepared statements (never string concatenation)
- NoSQL injection, operator injection (`$ne`, `$gt`)
- XSS: stored / reflected / DOM-based; output encoding, CSP
- CSRF, SameSite cookies, anti-CSRF tokens
- SSRF (server-side requests to a user-supplied URL)
- Path traversal, command injection, template injection
- Open redirect, clickjacking (X-Frame-Options / frame-ancestors)
- Brute force, credential stuffing → rate limits and lockout on auth endpoints
- Account enumeration (not leaking whether an email is registered)
- Timing attacks, constant-time comparison
- Insecure direct file access → signed URLs with short-lived signatures
- File uploads: MIME/magic-byte validation, size limits, a separate domain/bucket, virus scanning
- OWASP Top 10 and OWASP API Security Top 10 sweeps

### Infrastructure & data
- Mandatory HTTPS/TLS, HSTS, TLS version policy
- Security header set (CSP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- Secret management: env vars, vaults, key rotation; never a key in the repo
- Encryption at rest and in transit, field-level encryption
- PII masking, tokenization, never leaking sensitive data into logs
- Dependency scanning, SBOM, supply-chain attacks, lockfile discipline
- Audit trail (who changed what, when)
- **Mobile-specific:** certificate pinning, root/jailbreak detection, code obfuscation, Keychain/Keystore, no API keys in the client, tamper detection
- **GDPR / CCPA:** data minimization, explicit consent, right to erasure, retention periods, privacy notices, breach notification

## 5. Performance, caching & startup

- **Cache layers:** browser → CDN → reverse proxy → application → database
- Strategies: cache-aside, read-through, write-through, write-behind
- **Cache invalidation** (the hard part), TTL, stale-while-revalidate
- Cache stampede / thundering herd → mutex locks, jittered TTLs
- Redis / in-memory caches, eviction policies (LRU, LFU)
- Cache key design, namespacing, versioning
- HTTP cache headers: Cache-Control, ETag, Last-Modified
- CDN, edge caching, edge functions
- **Cold start** — serverless cold starts and app launch time
- Startup optimization: lazy init, deferring non-critical work past the first frame
- Splash and skeleton screens, perceived performance
- Code splitting, lazy loading, dynamic import, tree shaking, bundle analysis
- Preload / prefetch / preconnect, critical CSS
- Image optimization: WebP/AVIF, responsive srcset, lazy loading, placeholders
- Font loading strategy (`font-display: swap`)
- Virtualized / windowed long lists
- Optimistic UI, debounce, throttle
- Memoization, avoiding unnecessary re-renders
- Pagination and infinite scroll performance
- Query optimization, slow query logs
- Profiling, flame graphs, memory-leak hunting
- Load / stress / soak / spike testing (k6, Artillery)
- **p50 / p95 / p99 latency**, throughput, Apdex
- HTTP/2, HTTP/3, keep-alive, multiplexing
- Database connection warm-up

## 6. Async programming & concurrency

- **Process vs. thread vs. coroutine**; context-switch cost
- **CPU-bound vs. I/O-bound** work — which solution fits which
- Concurrency vs. parallelism
- Event loop, call stack, microtask/macrotask queues
- Blocking vs. non-blocking I/O
- Callback hell → Promises → async/await
- `Promise.all / allSettled / race / any` — when to use which
- **Cancellation:** AbortController/AbortSignal, cancellation tokens, context cancellation, cooperative cancellation
- Cancellation by timeout, deadlines via `Promise.race`
- Cleanup on unmount (the error caused by a fetch nobody cancelled)
- Race conditions, mutexes, semaphores, atomic operations
- Deadlock, livelock, starvation
- Thread and worker pools, queue saturation
- Web Workers, Service Workers, background sync
- Streams (readable / writable / transform), backpressure
- Parallel programming: map-reduce, fork-join, data vs. task parallelism
- Amdahl's law (the ceiling on parallelization)
- Debounce and throttle in async contexts
- Concurrency limits (how many requests at once — the `p-limit` idea)

## 7. Queues & messaging

- Message queues (RabbitMQ, SQS, BullMQ, Redis Streams)
- Pub/sub vs. point-to-point vs. fan-out
- Kafka: topics, partitions, consumer groups, offsets, log compaction
- Delivery guarantees: at-most-once, at-least-once, exactly-once (and why it is genuinely hard)
- **Idempotent consumers** (the mandatory complement to at-least-once)
- Dead letter queues, poison messages
- Retry policies, backoff, max attempts
- Message ordering, FIFO queues, partition keys
- Visibility timeout, ack/nack, requeue
- Delayed jobs, scheduled jobs, cron
- Job priority, rate-limited workers
- Outbox pattern (making the DB transaction and the message atomic)
- Worker scaling, queue-depth alarms
- Moving long work out of the HTTP request (reports, email, video, PDF, AI calls)

## 8. Infrastructure, deployment & DevOps

- Docker, layer caching, multi-stage builds, image size, distroless
- **Kubernetes:** pods, deployments, replicasets, services, ingress, configmaps, secrets, namespaces
- K8s: liveness/readiness/startup probes, HPA, resource requests and limits, node affinity, PDB
- Helm, Kustomize
- Serverless: Lambda, Cloud Run, edge functions; cold starts and duration limits
- CI/CD pipelines, build caches, artifacts
- Deployment strategies: rolling, blue-green, canary, shadow
- Zero-downtime deploys plus backward-compatible migrations
- Infrastructure as code (Terraform, Pulumi)
- Load balancers, sticky sessions, health checks
- Autoscaling: horizontal vs. vertical
- Reverse proxies (nginx, Caddy), TLS termination
- Environment separation (dev/staging/prod), never testing against production data
- Disaster recovery, RTO / RPO, restore drills
- Cost optimization / FinOps, budget alarms against runaway cloud bills
- CDN plus object storage (S3/R2) for static assets

## 9. Observability

- Structured logging (JSON), log levels, **correlation/request IDs**
- Log retention, a logging policy that does not leak PII
- Metrics: RED (rate, errors, duration), USE, the four golden signals
- Distributed tracing, OpenTelemetry, traces and spans
- Error tracking (Sentry, Crashlytics), source map uploads
- APM, real user monitoring
- Health check / readiness endpoints
- Alerting, on-call, alert fatigue
- SLI / SLO / SLA, error budgets
- Product analytics: event tracking, funnels, retention, cohorts
- A/B testing paired with feature flags
- Session replay, heatmaps
- Dashboards and an at-a-glance health signal

## 10. Frontend & mobile specifics

- Rendering strategies: CSR, SSR, SSG, ISR; hydration and hydration mismatch
- Core Web Vitals: LCP, INP, CLS
- Offline-first / local-first architecture
- Sync and conflict resolution: last-write-wins, vector clocks, CRDTs
- Optimistic updates and rollback
- State management, normalized state, server state vs. client state
- react-query / SWR: stale time, refetching, cache invalidation
- Accessibility (a11y), semantic HTML, ARIA, keyboard navigation, contrast
- i18n / l10n, plural rules, RTL support, date and currency formats
- Deep links, universal links, app links
- Push notifications (FCM / APNs), token lifecycle, when to ask for permission
- App size reduction, R8/ProGuard, Android App Bundle, asset optimization
- OTA updates (Capacitor Live Update / CodePush) and store policy
- Permission handling (camera, location, notifications) and rationale screens
- Network awareness: offline detection, retries, low-bandwidth mode
- WebView performance, Capacitor bridge call cost, minimizing native hops
- Storage choice: localStorage / IndexedDB / SQLite / MMKV / SecureStorage
- Crash-free rate, ANR tracking
- Store compliance: App Store Review Guidelines, Play Data Safety, ATT, mandatory account deletion

## 11. Testing & code quality

- The test pyramid: unit → integration → E2E
- Mocks, stubs, fakes, spies; choosing a test double
- Coverage (and how it misleads), mutation testing
- Snapshot testing, visual regression
- Contract testing between API consumer and producer
- Smoke tests, regression suites
- TDD / BDD
- Test data management, isolated test databases, transaction rollback for cleanup
- Linters, formatters, type safety, `strict` mode
- Static analysis, code review checklists, pre-commit hooks
- Error boundaries and meaningful user-facing failure messages
- Chaos engineering (advanced)

## 12. Language & runtime level

- **Compiler vs. interpreter**, JIT, AOT, transpilers (Babel, tsc)
- Bytecode, virtual machines, Hermes/V8
- Garbage collection, memory leaks, reference counting, weak references
- Stack vs. heap, the memory impact of closures
- Immutability, pure functions, side effects
- Type systems: static/dynamic, structural/nominal, generics, narrowing
- Big-O complexity, data structure choice (hash map vs. array vs. set)
- Serialization cost (`JSON.parse` on a large payload)
- Encoding: UTF-8, base64, unicode normalization
- Dates and times: store UTC, timezones, DST, ISO 8601
- Money: never floats — integer minor units or a decimal type

## 13. Payments, subscriptions & business logic

- Idempotency keys in payments (preventing double charges)
- Webhook signature verification, event replay, out-of-order events
- Reconciliation against the provider's records
- Subscription lifecycle: trial, active, past due, cancelled, grace period
- Dunning (failed-payment retry flows), proration
- In-app purchase receipt validation (App Store / Play), server-side
- Refunds, chargebacks, account closure
- Tax / VAT, invoicing, country-based pricing
- Fraud and abuse detection, abuse limits
- Quotas and usage metering (mandatory for costly AI/API features)

---

## Quick map: "if you see this, look at that"

| Problem | Concepts to check |
|---|---|
| App stutters on first launch | Cold start, code splitting, lazy init, bundle size, skeleton screens, deferring non-critical work, image optimization |
| List page slows as data grows | Indexes, cursor pagination, N+1, covering indexes, virtualization |
| The same operation happened twice | Idempotency keys, unique constraints, at-least-once + idempotent consumers, optimistic locking |
| A user can see someone else's data | BOLA/IDOR, RLS, RBAC, tenant scoping, an owner filter on every query |
| Server intermittently crashes or times out | Connection pool limits, long transactions, rate limits, circuit breakers, moving work to a queue |
| Third-party/AI API costs exploded | Caching, quotas, rate limits, batching, debounce, usage metering |
| A report/email/PDF request blocks the user | Message queues, background jobs, DLQs, a job-status endpoint |
| Things break after deploy | Migration strategy (expand-contract), canary, feature flags, rollback plan, health checks |
| I cannot find the cause of an error | Correlation IDs, structured logs, error tracking, distributed tracing |
| The app breaks offline | Offline-first, local cache, sync queue, conflict resolution, optimistic updates |

---

## Prompt template for a new project

```
Below is a broad list of technical concepts. About my project:

- Application: [what it does, target audience]
- Platform: [web / iOS / Android / all]
- Stack: [e.g. React + Vite + Capacitor + Supabase/Postgres + Node]
- Expected users: [first 3 months / 1 year]
- Critical features: [payments? realtime? AI calls? file uploads? multi-tenant?]
- Team: [solo / N people], budget and infra constraints: [...]

Your task:
1) Pick what this project GENUINELY needs from the list. Briefly dismiss the rest with "not needed now, because...".
2) Sort your picks into P0 (must be decided before writing code) / P1 (first release) / P2 (when scale arrives).
3) For every P0 item: how it is concretely implemented in this stack, which file/layer it lives in, and a code skeleton.
4) Collect the decisions that are expensive to reverse under a separate "irreversible decisions" heading.
5) Warn me about over-engineering: what is unnecessary at this scale but commonly added by reflex.

List:
[paste the list here]
```
