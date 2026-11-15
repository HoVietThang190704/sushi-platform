# API quality remediation design

## Goal and scope

Fix the verified ordering, shipping, authentication, outbox, pagination, and test-typecheck issues without changing the existing delivery-only public ordering flow. An administrator-configured delivery fee of `0` remains valid; an omitted delivery location must not silently become free shipping. Preserve unrelated, uncommitted changes in the nested `apps/api` repository.

The work does not introduce pickup orders, payment-provider integration, or a general microservice redesign.

## Delivery order and shipping

The public order endpoint continues to create delivery orders only. Require a nonblank delivery address, district, and ward; the existing storefront checkout already supplies these fields. The ordering service must calculate shipping for every public order before persistence, rejecting unsupported locations instead of defaulting to zero. A matching active shipping rule with a fee of zero must be accepted unchanged. Staff orders retain their assigned-branch authorization and must not silently use a different branch's rule if the specified branch does not serve the location.

Shipping lookup must use both district and ward for order creation. Canonicalize administrative aliases using the existing address service where possible; do not allow a same-named ward in a different district to satisfy the lookup. On the public shipping-calculation endpoint, if a legacy client omits district, only accept an unambiguous ward match or reject with a client error.

## Refresh token rotation

Verify the refresh JWT, locate its persisted token record, and atomically claim the unrevoked, unexpired record with a conditional update. Only the request that updates exactly one record may create replacement tokens; concurrent replays must fail. Keep the claim and creation of the replacement refresh-token record inside one database transaction so a failed issuance does not consume the old token. Preserve the existing revoked-token-family response policy where practical, but ensure it cannot revoke a newly rotated token due solely to an ordinary concurrent retry.

## Outbox delivery

Use an application-owned periodic dispatcher for `PENDING` outbox records; do not rely on a method called only from tests. Protect concurrent dispatchers from publishing the same record at the same time (claim/lease or equivalent). Make retries observable, avoid an unbounded tight retry loop, and define how stale claims are recovered. Continue marking an event `PUBLISHED` only after a confirmed publish; retain failures for retry. Run the dispatcher wherever outbox records are produced, including ordering-service order status events, rather than covering inventory alone.

## Orders pagination

Keep the current unpaginated `GET /api/orders` contract until admin-web consumes pages. First update admin-web to request and navigate pages while retaining filters and stable ordering; then impose an API default and maximum page size. Return pagination metadata using a client-compatible response shape. Preserve branch authorization for every page and avoid loading status histories unless the client needs them.

## Test and rollout gates

Add focused tests for missing/unsupported delivery locations and zero-fee rules; duplicate ward names; concurrent refresh requests and rollback on issuance failure; outbox failure/recovery and competing dispatchers; and paginated, branch-scoped order lists. Fix the existing TypeScript errors in unit/E2E tests without weakening types. Run Jest, full-repository `tsc --noEmit`, per-service builds, and database-backed integration/E2E tests when the required services are available. Do not use schema synchronization against an existing database without an explicit deployment review; document any schema changes and the safe rollout order.
