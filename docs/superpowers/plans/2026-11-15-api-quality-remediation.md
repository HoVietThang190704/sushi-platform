# API Quality Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the verified delivery-fee, refresh-token race, event-delivery, unbounded-list, and test-typecheck gaps without invalidating legitimate zero-fee shipping.

**Architecture:** Make delivery location a validated input and calculate fee from an active district/ward/branch rule. Rotate refresh tokens atomically; publish durable outbox records through an independently running dispatcher and confirmed RabbitMQ publishes. Move the admin order list to server-side pagination before enforcing a default on the API.

**Tech Stack:** NestJS 11, Prisma 6/PostgreSQL, RabbitMQ, Jest, TypeScript, Next.js admin-web.

**Spec:** `docs/superpowers/specs/2026-11-15-api-quality-remediation-design.md`

## Global Constraints

- Public checkout remains delivery-only; a configured shipping fee of `0` is valid.
- Preserve existing uncommitted work in the nested `apps/api` git repository; inspect diffs before every edit.
- Do not run `prisma db push` against an existing database without deployment review.
- Do not expose customer order data through an idempotency retry response.
- Avoid changing the public order-list response contract until the admin-web client is updated.
- Refresh JWTs must contain a new random `jti` on every issuance; signing an identical payload twice within one second must not recreate the same token.
- Next.js changes in `apps/admin-web` must follow `apps/admin-web/AGENTS.md` and the relevant installed `node_modules/next/dist/docs/` guide before editing.
- Outbox is at-least-once delivery, not exactly-once; consumers must tolerate repeated event IDs.

## Review Focus

- Blank-but-present `ward`, `district`, or `address` must fail before order persistence (Task 1).
- A district with a same-named ward in a different area must not inherit that area's shipping rule (Task 1).
- Two concurrent refresh calls with the same token must yield at most one live replacement (Task 2).
- Broker disconnection between DB commit and publication must leave a retryable event, and a broker-confirmed event must not be marked published merely because `publish()` returned `true` (Task 3).
- A non-admin querying a later order page must not see another branch's orders (Task 4).

---

### Task 1: Delivery address and fee correctness

**Files:**
- Modify: `apps/api/apps/ordering-service/src/dto/create-order.dto.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/shipping/shipping.service.ts`
- Modify: `apps/api/apps/ordering-service/src/shipping/dto/shipping-rule.dto.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`
- Test: `apps/api/apps/ordering-service/src/shipping/shipping.service.spec.ts`

**Interfaces:** Keep `ShippingService.calculateShipping(dto: CalculateShippingDto)` returning `{ district, ward, fee, branch }`. Reject a specified branch when it has no active rule for the district/ward; do not silently change branches for staff orders.

- [ ] **Step 1: Write failing cases** for missing and whitespace-only address/district/ward, no matching rule, same-named ward in another district, explicitly selected unsupported branch, and a rule with fee `0`. Use `validate(plainToInstance(CreateOrderDto, input))` for DTO cases; assert service-level rejection before `prisma.order.create` or `$transaction` when input omits location (never call shipping with an invalid ward). Example assertions:
  ```ts
  expect(validate(plainToInstance(CreateOrderDto, { ...validOrder, ward: '   ' })))
    .resolves.not.toHaveLength(0);
  await expect(service.createOrder({ ...validOrder, ward: '' }))
    .rejects.toBeInstanceOf(BadRequestException);
  expect(prisma.shippingRule.findFirst).toHaveBeenCalledWith(
    expect.objectContaining({ where: expect.objectContaining({ district: expect.anything() }) }),
  );
  ```
- [ ] **Step 2: Run focused tests:** `pnpm exec jest apps/ordering-service/src/ordering.service.spec.ts apps/ordering-service/src/shipping/shipping.service.spec.ts --runInBand --no-cache` from `apps/api`; expect new cases to fail.
- [ ] **Step 3: Implement validation** with `@IsString()`, `@IsNotEmpty()`, and `@Matches(/\S/)` on public `address`, `district`, `ward`; reject blank strings in `createOrder()` before product or DB access (service callers may bypass Nest validation). Replace `if (dto.ward)` with unconditional `calculateShipping({ district: dto.district, ward: dto.ward, branchId: dto.branchId })`; use the returned `fee` including `0` and branch ID. In shipping lookup, include district in every `where` clause; if omitted for the public calculation endpoint, query distinct matching districts and reject ambiguity. When `branchId` is provided and its rule is absent, return a client error rather than falling back. Preserve the existing canonical-ward mapping but match aliases within the requested district; do not map an ambiguous legacy ward name across districts.
  ```ts
  for (const field of ['address', 'district', 'ward'] as const) {
    if (typeof dto[field] !== 'string' || !dto[field].trim()) {
      throw new BadRequestException(`${field} is required for delivery`);
    }
  }
  const shipping = await this.shippingService.calculateShipping({
    district: dto.district, ward: dto.ward, branchId: dto.branchId,
  });
  const shippingFee = shipping.fee; // 0 is an explicitly configured rule
  ```
- [ ] **Step 4: Re-run focused tests and type-check** using the command in Step 2 and `pnpm exec tsc --noEmit --incremental false --project apps/ordering-service/tsconfig.app.json`. Update existing fixture payloads to supply valid delivery data rather than weakening validations.

### Task 2: Atomic refresh-token rotation

**Files:**
- Modify: `apps/api/apps/identity-service/src/auth.service.ts`
- Create: `apps/api/apps/identity-service/src/auth.service.spec.ts`

**Interfaces:** Preserve `AuthService.refreshToken(rawRefreshToken: string)` response `{ user, tokens }` and `AuthService.generateTokens(userId, email, role, branchId)`. Make the latter accept an optional Prisma transaction client for refresh rotation (or extract a private signing/persistence pair) so replacement creation shares the claim transaction.

- [ ] **Step 1: Write failing cases** for two concurrent refreshes of one token (one succeeds, one throws `UnauthorizedException`), revoked/expired token, and failed replacement insertion leaving the old token usable. Add a real JWT-signing test (not a mocked signer) that calls token generation twice in the same second, verifies distinct refresh JWTs and `jti` values, and confirms the new token is not byte-identical to the spent one. In the transaction mock, return `{ count: 1 }` only on the first `refreshToken.updateMany({ where: { id, revokedAt: null, expiresAt: { gt: ... } } })` claim; emulate rollback when `create` throws.
  ```ts
  const [first, second] = await Promise.allSettled([
    service.refreshToken(rawToken), service.refreshToken(rawToken),
  ]);
  expect([first.status, second.status].sort()).toEqual(['fulfilled', 'rejected']);
  expect(createdRefreshRecords).toHaveLength(1);
  ```
- [ ] **Step 2: Run:** `pnpm exec jest apps/identity-service/src/auth.service.spec.ts --runInBand --no-cache`; expect new concurrency/rollback cases to fail.
- [ ] **Step 3: In `refreshToken`,** after verifying JWT and matching a persisted hash, load active user and perform claim plus replacement insertion in a single `prisma.$transaction(async tx => ...)`. Require `claim.count === 1`; otherwise throw `UnauthorizedException`. Ensure `generateTokens` signs the refresh payload with `jti: randomUUID()` (or `randomBytes(16).toString('hex')`) on *every* call, including login, and persists the replacement through the transaction client. Hash the newly signed refresh JWT, not the old one; retain login's existing `this.prisma` behavior. Avoid unconditional user-wide revocation for an ordinary replay that lost the claim race.
  ```ts
  const tokens = await this.prisma.$transaction(async (tx) => {
    const claim = await tx.refreshToken.updateMany({
      where: { id: matchedTokenRecord.id, revokedAt: null, expiresAt: { gt: new Date() } },
      data: { revokedAt: new Date() },
    });
    if (claim.count !== 1) throw new UnauthorizedException('Refresh token already used');
    return this.generateTokens(user.id, user.email, user.role, user.branchId, tx);
  });
  ```
  Keep the legacy revoked-record family policy only if it can distinguish a compromised replay from a normal concurrent retry; otherwise document the deliberate policy change and test that a loser cannot revoke the winner.
- [ ] **Step 4: Re-run tests** and `pnpm exec tsc --noEmit --incremental false --project apps/identity-service/tsconfig.app.json`.

### Task 3: Reliable outbox publishing in both producer services

**Files:**
- Modify: `apps/api/libs/common/src/rabbitmq/rabbitmq.service.ts`
- Create: `apps/api/libs/common/src/outbox/outbox-dispatcher.service.ts`
- Create: `apps/api/libs/common/src/outbox/outbox-dispatcher.service.spec.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering-service.module.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory-service.module.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts` (remove competing direct publish for durable status event)
- Modify: `apps/api/prisma/schema.prisma` (lease metadata on the existing `inventory.outbox_events` table)
- Create: `apps/api/prisma/migrations/<timestamp>_outbox_claim_lease/migration.sql` (use project's checked-in migration convention; if none exists, create an explicit SQL migration and record how to apply it)

**Interfaces:** `OutboxDispatcherService` depends on Prisma's `outboxEvent` delegate and `RabbitMQService.publishEvent(event): Promise<boolean>`. Explicitly provide it with the service-local Prisma and RabbitMQ instances in both service modules; do not assume importing a common module supplies the service-local Prisma instance. Keep `PENDING`, `FAILED`, and `PUBLISHED`; add nullable `claimedBy String?`, `claimedUntil DateTime?`, `nextAttemptAt DateTime?` to `OutboxEvent`, and index `(status, nextAttemptAt, createdAt)` for scanning.

- [ ] **Step 1: Write failing tests** showing pending events are retried after a publish failure, two dispatcher instances cannot publish the same row simultaneously, and a crashed worker's stale claim becomes eligible again. Add a test where `publishEvent` returns `false` and the row remains pending, plus one where a broker confirm arrives but DB status update fails (the event must remain retryable). Test status-event creation without optional `tx.outboxEvent` guards in a real Prisma-backed transaction.
  ```ts
  expect(await Promise.all([dispatcherA.dispatchBatch(), dispatcherB.dispatchBatch()]))
    .toEqual(expect.arrayContaining([0, 1]));
  expect(publishEvent).toHaveBeenCalledTimes(1);
  ```
- [ ] **Step 2: Run:** `pnpm exec jest libs/common/src/outbox/outbox-dispatcher.service.spec.ts --runInBand --no-cache`; expect failure before the dispatcher exists.
- [ ] **Step 3: Implement durable claiming** using `findMany` only for candidate IDs, then `updateMany` with `id`, eligible status, and `(claimedUntil IS NULL OR claimedUntil < now)` to atomically take a lease; skip candidates whose claim count is not `1`. Give each dispatcher a random worker ID and a bounded batch (`20`), interval (`5s`), and lease (`60s`); wrap the `setInterval` tick so it cannot overlap itself. Set `nextAttemptAt` with capped exponential backoff on failure; check `retryCount` and backlog age in structured logs. On success update `status=PUBLISHED` only with matching `claimedBy`; on failure clear the claim, increment retry, and retain a retryable status. A timed-out publish may still reach RabbitMQ: require consumers to de-duplicate by the event's stable `id` or tolerate replay. Add the schema migration with rollout order: migration → deploy dispatcher + publisher → monitor backlog. Replace inventory's unused method or delegate to the shared dispatcher. Wire to both service modules and remove the ordering-service's competing post-transaction immediate publish for durable status events (or make immediate publish claim the row first).
  ```ts
  const claimed = await prisma.outboxEvent.updateMany({
    where: { id: row.id, status: OutboxStatus.PENDING,
      OR: [{ claimedUntil: null }, { claimedUntil: { lt: now } }] },
    data: { claimedBy: workerId, claimedUntil: new Date(now.getTime() + 60_000) },
  });
  if (claimed.count !== 1) continue;
  ```
  Include `nextAttemptAt` eligibility and `FAILED` handling consistently in the actual query; test lease expiry with a frozen clock.
- [ ] **Step 4: Make RabbitMQ success meaningful:** use `connection.createConfirmChannel()` and await confirmation for each message (callback or `waitForConfirms()` with bounded timeout). Ignore the synchronous `publish()` boolean for success; it signals stream backpressure only. On timeout or channel close return `false`, invalidate the channel, and let the outbox retry; test ack, nack, timeout and reconnect with a mocked confirm channel. Preserve the existing durable exchange and persistent messages.
- [ ] **Step 5: Run focused tests and both service type-checks** from `apps/api`:
  `pnpm exec jest libs/common/src/outbox apps/inventory-service/src/inventory.service.spec.ts apps/ordering-service/src/ordering.service.spec.ts --runInBand --no-cache`;
  `pnpm exec tsc --noEmit --incremental false --project apps/ordering-service/tsconfig.app.json`;
  `pnpm exec tsc --noEmit --incremental false --project apps/inventory-service/tsconfig.app.json`.
  In an isolated database/broker, disconnect RabbitMQ, commit a status/inventory event, reconnect it, and verify eventual consumer delivery and restart recovery. Record duplicate-delivery semantics explicitly; do not promise exactly once.

### Task 4: Admin-compatible orders pagination

**Files:**
- Modify: `apps/admin-web/src/features/orders/api/orders.api.ts`
- Modify: `apps/admin-web/src/features/orders/hooks/use-orders.ts`
- Modify: `apps/admin-web/src/app/(dashboard)/dashboard/orders/page.tsx` or its owning list component
- Modify: `apps/api/apps/ordering-service/src/ordering.controller.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:** Paged result `{ items: Order[], page: number, limit: number, total: number }` with default `page=1`, `limit=50`, max `limit=200`; use one explicit deployment cutover (or versioned compatibility) so old admin-web does not receive an unexpected object. Existing `GetOrdersDto` accepts `page` and `limit`.

- [ ] **Step 1: Write failing API tests** for default/max limit, stable ordering with equal `createdAt`, total count under the same filters and branch scope, out-of-range pages, and metadata. Check admin-web's `Order` type and all `ordersApi.getOrders` consumers before changing the response. Test that branch scope is applied identically to `count` and `findMany`.
  ```ts
  expect(prisma.order.count).toHaveBeenCalledWith({
    where: expect.objectContaining({ branchId: staff.branchId }),
  });
  expect(prisma.order.findMany).toHaveBeenCalledWith(
    expect.objectContaining({ take: 50, skip: 50,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }] }),
  );
  ```
- [ ] **Step 2: Run:** `pnpm exec jest apps/ordering-service/src/ordering.service.spec.ts --runInBand --no-cache`; expect pagination cases to fail.
- [ ] **Step 3: Read `apps/admin-web/AGENTS.md` and relevant installed Next.js docs**, then switch admin-web to page queries (`page`, `limit`, filters in the query key), display next/previous controls and total, and reset to page 1 on filter change; ensure realtime invalidation updates the displayed page. The existing page assumes `const { data: orders = [] } = useOrders(...)`; adapt it to `data?.items ?? []` only as part of the coordinated cutover. Do not deploy a client expecting `{ items }` against an array response. Inspect `apps/admin-web/src/lib/api.ts` for the response interceptor's unwrap behavior before typing the result.
  ```ts
  export type PagedOrders = { items: Order[]; page: number; limit: number; total: number };
  // ordersApi.getOrders: fetchApi<PagedOrders>(`/api/orders?${params}`)
  // useOrders queryKey: [...orderKeys.lists(), { ...filters, page, limit }]
  ```
- [ ] **Step 4: Apply the API default** `page=1`, `limit=50`, max `200` and return paged metadata; use the same filtered `where` for `findMany` and `count`; sort by `createdAt desc, id desc` so pages do not drift on timestamp ties. The page currently reads status history: do not remove it until the UI is verified not to need it. Do not rely on `limit` being present to apply `skip`.
  ```ts
  const page = params?.page ?? 1;
  const limit = Math.min(params?.limit ?? 50, 200);
  const where: Prisma.OrderWhereInput = { /* current status/date/authorized branch filters */ };
  const [orders, total] = await Promise.all([
    this.prisma.order.findMany({ where, skip: (page - 1) * limit, take: limit,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: { items: true, statusHistories: { orderBy: { createdAt: 'asc' } } } }),
    this.prisma.order.count({ where }),
  ]);
  return { items: orders.map((order) => this.sanitizeOrder(order)), page, limit, total };
  ```
- [ ] **Step 5: Re-run API tests and admin-web checks:** `pnpm exec jest apps/ordering-service/src/ordering.service.spec.ts --runInBand --no-cache` from `apps/api`, then `pnpm exec tsc --noEmit` from `apps/admin-web`. Manually verify filters, next/previous, branch isolation, and realtime invalidation; document the coordinated rollout or versioned compatibility window.

### Task 5: Restore test type-safety and verify release gates

**Files:**
- Modify: `apps/api/apps/inventory-service/src/inventory.service.spec.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`
- Modify: `apps/api/apps/catalog-service/test/app.e2e-spec.ts`
- Modify: `apps/api/apps/identity-service/test/app.e2e-spec.ts`
- Modify: additional failing test files only when the compiler names them.

**Interfaces:** Keep Jest test behavior unchanged while making tests compile against the actual Prisma enum/client and Supertest import shapes.

- [ ] **Step 1: Reproduce baseline:** from `apps/api`, run `pnpm exec tsc --noEmit --incremental false --project tsconfig.json`. Confirm the existing errors include `TransactionReason.PURCHASE_IMPORT`, `trackingToken` possibly null, incorrect Prisma `findUnique` mock signatures, spread from unknown, and namespace-imported Supertest.
- [ ] **Step 2: Update tests** to use `TransactionReason.PURCHASE`; narrow `trackingToken` before `.length`; use a typed mock Prisma adapter instead of a bare async `findUnique` implementation; narrow the spread source to a concrete object; import callable Supertest with the project's TypeScript interop setting. Replace stale placeholder E2E assertions with actual route behavior or explicitly mark them as environment-dependent integration tests.
  ```ts
  expect(result.trackingToken).not.toBeNull();
  if (result.trackingToken === null) throw new Error('Expected new tracking token');
  expect(result.trackingToken.length).toBeGreaterThanOrEqual(32);
  // In E2E files, use: import request from 'supertest';
  ```
- [ ] **Step 3: Run:** `pnpm exec tsc --noEmit --incremental false --project tsconfig.json` and `pnpm exec jest --runInBand --no-cache`; expect zero type errors and all suites passing.
- [ ] **Step 4: Run per-service builds** (`pnpm build` from `apps/api`) and DB-backed E2E tests only in an isolated test database that is safe to recreate. Record environment blockers and schema rollout ordering; inspect `git diff --check` and `git status --short` in both repositories before claiming completion. Never include pre-existing uncommitted files in a commit.

## Execution order

Tasks 1, 2, and 3 can be reviewed independently; Task 4 must update admin-web before activating the API default. Task 5 is the final cross-cutting gate. Do not commit existing user changes as part of these tasks; request explicit permission before staging or committing.
