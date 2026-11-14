# Storefront Ordering Mode & Admin Phone Orders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow administrators to toggle customer online ordering on the Storefront and manage the store's contact phone number, switching Storefront to a "Call to Order" direct dialing experience when disabled, while allowing staff to create delivery orders directly from the Admin Web dashboard at any time.

**Architecture:** A centralized `StoreConfig` entity in Ordering Service manages online ordering status and phone number. Storefront reads this configuration to toggle cart/ordering CTAs vs. direct `tel:` dialing buttons. Public `POST /orders` enforces this restriction at the API boundary (after idempotency check), while an authenticated `POST /orders/staff` endpoint allows staff to create delivery orders with automated server-side pricing and shipping calculations. API Gateway strips spoofed identity headers, and backend endpoints enforce role-based access control.

**Tech Stack:** NestJS, Prisma, PostgreSQL, Next.js 16 (App Router), TanStack Query, Tailwind CSS, Ant Design (Admin Web), Lucide Icons.

**Spec:** `docs/superpowers/specs/2026-11-14-storefront-ordering-mode-and-admin-phone-orders-design.md`

## Global Constraints

- Inventory deduction rules remain immutable: only deducted when order transitions from `CONFIRMED → PREPARING`.
- Server never trusts client-supplied prices or total amounts; all item prices and shipping fees are calculated server-side.
- Seed data balances are not verified inventory; strict stock deduction occurs only on verified BOM recipes.
- Staff phone orders must support delivery address, ward/district selection, and valid branch selection.
- Commits are made locally on branch `main` in each respective submodule first, then the root repository, without pushing to remote.

## Review Focus

1. **Mid-checkout disablement**: Customer is on checkout screen when admin disables online ordering; server rejects submission with a clear localized message without corrupting cart state.
2. **Idempotency retry while disabled**: Retrying an already created order while ordering is disabled must return the existing order without creating a duplicate or failing.
3. **Staff order bypass & security**: Staff order creation via admin must succeed regardless of `customerOrderingEnabled` state, but must reject requests missing proper staff/admin credentials or spoofed headers.
4. **Storefront direct URL navigation**: Direct navigation to `/cart` or `/checkout` when ordering is disabled displays a clean "Call to order" screen rather than a broken form or blank page.
5. **Real phone validation**: Contact phone number saved by admin is validated (Vietnamese phone regex) and cannot be a dummy placeholder when disabling online ordering.

---

### Task 1: Prisma Schema & StoreConfig Model + Migration

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Create migration: `apps/api/prisma/migrations/YYYYMMDD_add_store_config_and_order_source/migration.sql`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Produces: `StoreConfig` model with fields `id`, `key` ("DEFAULT"), `customerOrderingEnabled` (Boolean, default true), `contactPhone` (VarChar(30), default "0988888888"), `updatedAt`.
- Produces: `Order.source` field with default `"STOREFRONT"` (`STOREFRONT` | `STAFF`).

- [ ] **Step 1: Update Prisma schema**

Add `StoreConfig` model and `source` field to `Order` in `apps/api/prisma/schema.prisma`:
```prisma
model Order {
  // ... existing fields
  source           String        @default("STOREFRONT") @db.VarChar(20) // STOREFRONT | STAFF
  // ... rest of fields
}

model StoreConfig {
  id                      String   @id @default(uuid()) @db.Uuid
  key                     String   @unique @default("DEFAULT") @db.VarChar(50)
  customerOrderingEnabled Boolean  @default(true) @map("customer_ordering_enabled")
  contactPhone            String   @default("0988888888") @map("contact_phone") @db.VarChar(30)
  createdAt               DateTime @default(now()) @map("created_at")
  updatedAt               DateTime @updatedAt @map("updated_at")

  @@map("store_configs")
  @@schema("ordering")
}
```

- [ ] **Step 2: Generate Prisma Client & Run Migration**

Run in `apps/api`:
`pnpm prisma generate`
`pnpm prisma db push` or `pnpm prisma migrate deploy`

- [ ] **Step 3: Commit in apps/api**

```bash
git -C apps/api add prisma/schema.prisma prisma/migrations
git -C apps/api commit -m "feat(ordering): Add StoreConfig model and Order source field"
```

---

### Task 2: Gateway Security & Backend Ordering Service - StoreConfig API & Public Order Blocking

**Files:**
- Modify: `apps/api/apps/api-gateway/src/main.ts`
- Create: `apps/api/apps/ordering-service/src/dto/update-store-config.dto.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.controller.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Security: Gateway strips untrusted `x-user-id`, `x-user-role`, `x-user-branch-id` headers on incoming requests before proxying.
- Produces: `GET /orders/store-config` -> `{ customerOrderingEnabled: boolean, contactPhone: string }`
- Produces: `PATCH /orders/store-config` -> requires `x-user-role` in `['ADMIN', 'SUPER_ADMIN']`. Validates `contactPhone` matches phone regex. Rejects disabling if phone is invalid/empty.
- Modifies: `createOrder` ->
  1. Checks idempotency key first. If existing order found, returns existing order.
  2. If new order and `storeConfig.customerOrderingEnabled === false`, throws `BadRequestException('Cửa hàng hiện đang tạm ngưng nhận đặt món trực tuyến. Quý khách vui lòng liên hệ hotline để được phục vụ.')`.

- [ ] **Step 1: Write failing unit tests for StoreConfig, Order blocking, and Idempotency bypass**

In `apps/api/apps/ordering-service/src/ordering.service.spec.ts`:
- Test that existing order idempotency retry succeeds even when `customerOrderingEnabled = false`.
- Test that new order creation throws `BadRequestException` when `customerOrderingEnabled = false`.
- Test that `updateStoreConfig` rejects non-admin roles and invalid phone numbers.

- [ ] **Step 2: Update API Gateway to strip spoofable headers**

In `apps/api/apps/api-gateway/src/main.ts`, in proxyReq hook for `/api/orders`:
Remove incoming `x-user-id`, `x-user-role`, `x-user-branch-id` headers first, then set them only if JWT is verified.

- [ ] **Step 3: Implement StoreConfig DTO & Service methods**

In `apps/api/apps/ordering-service/src/dto/update-store-config.dto.ts`:
Validate `contactPhone` matches `^(0|\+84)[35789]\d{8}$` or valid hotline format.

In `ordering.service.ts`:
Implement `getStoreConfig()` and `updateStoreConfig()`.
In `createOrder()`, ensure idempotency check happens BEFORE checking `customerOrderingEnabled`.

- [ ] **Step 4: Expose endpoints in ordering.controller.ts with Role checks**

Verify `x-user-role` for `PATCH /orders/store-config`.

- [ ] **Step 5: Run unit tests to verify they pass**

Run: `pnpm --filter ordering-service test`
Expected: PASS

- [ ] **Step 6: Commit in apps/api**

```bash
git -C apps/api add apps/ordering-service apps/api-gateway
git -C apps/api commit -m "feat(ordering-service): Add secure store-config API and guard public order creation"
```

---

### Task 3: Backend Staff Order Creation Endpoint

**Files:**
- Create: `apps/api/apps/ordering-service/src/dto/create-staff-order.dto.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.controller.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Produces: `POST /orders/staff` -> requires role `ADMIN`, `SUPER_ADMIN`, `BRANCH_MANAGER`, or `STAFF`.
- Requires `branchId`, validates branch is active and supports destination ward/district.
- Calculates dish prices server-side from catalog and shipping fee from `ShippingService`.
- Sets `order.source = 'STAFF'`, status = `PENDING`, paymentStatus = `UNPAID`.
- Records status history with `changedBy = staffId`, `reason = 'Nhân viên tạo đơn giao tận nơi qua điện thoại'`.
- Bypasses `customerOrderingEnabled`.

- [ ] **Step 1: Write failing unit tests for createStaffOrder**

In `ordering.service.spec.ts`:
- Test that staff order succeeds with `source = 'STAFF'` when online ordering is disabled.
- Test that staff order calculates correct item totals and shipping fee.
- Test that invalid branch or unsupported ward throws BadRequestException.
- Test that unauthorized role throws UnauthorizedException.

- [ ] **Step 2: Implement createStaffOrder in ordering.service.ts**

- [ ] **Step 3: Expose POST /orders/staff in ordering.controller.ts**

- [ ] **Step 4: Run unit tests to verify PASS**

Run: `pnpm --filter ordering-service test`
Expected: PASS

- [ ] **Step 5: Commit in apps/api**

```bash
git -C apps/api add apps/ordering-service
git -C apps/api commit -m "feat(ordering-service): Add authenticated POST /orders/staff endpoint for phone delivery orders"
```

---

### Task 4: Admin Web - Store Settings Page

**Files:**
- Modify: `apps/admin-web/src/config/navigation.config.ts`
- Modify: `apps/admin-web/src/features/orders/api/orders.api.ts`
- Modify: `apps/admin-web/src/features/orders/types/index.ts`
- Create: `apps/admin-web/src/features/orders/components/store-settings-view.tsx`
- Create: `apps/admin-web/src/app/(dashboard)/dashboard/store-settings/page.tsx`
- Modify: `apps/admin-web/src/locales/vi.json` and `en.json`

- [ ] **Step 1: Add Store Settings to navigation config**

In `apps/admin-web/src/config/navigation.config.ts`, add under `settings` children:
`key: 'store-settings'`, `path: '/dashboard/store-settings'`.

- [ ] **Step 2: Implement Store Settings View Component**

Build `store-settings-view.tsx`:
- Toggle Switch: "Cho phép khách đặt hàng trực tuyến trên Storefront" (Active / Inactive).
- Input: "Số điện thoại hotline nhận đơn (Hotline)" with Vietnam phone validation regex.
- Live preview banner explaining Storefront behavior in both ON and OFF states.
- Save button with toast notification.

- [ ] **Step 3: Create Next.js page**

In `apps/admin-web/src/app/(dashboard)/dashboard/store-settings/page.tsx`:
Render `StoreSettingsView`.

- [ ] **Step 4: Test build and lint**

Run: `pnpm --filter admin-web build && pnpm --filter admin-web lint`
Expected: 0 errors

- [ ] **Step 5: Commit in apps/admin-web**

```bash
git -C apps/admin-web add src
git -C apps/admin-web commit -m "feat(admin-web): Add Store Settings page for storefront ordering toggle"
```

---

### Task 5: Admin Web - Staff Phone Order Creation Modal & Source Badge

**Files:**
- Modify: `apps/admin-web/src/features/orders/api/orders.api.ts`
- Create: `apps/admin-web/src/features/orders/components/create-staff-order-modal.tsx`
- Modify: `apps/admin-web/src/features/orders/components/order-table.tsx`
- Modify: `apps/admin-web/src/features/orders/components/order-detail-modal.tsx`
- Modify: `apps/admin-web/src/app/(dashboard)/dashboard/orders/page.tsx`

- [ ] **Step 1: Add staff order API method in orders.api.ts**

- [ ] **Step 2: Create CreateStaffOrderModal component**

Build `create-staff-order-modal.tsx`:
- Dish Selector: select active products from catalog + quantity spinner.
- Receiver form: Full name, phone number (validated with regex), address, ward & district selection.
- Serving branch: dynamically filtered to branches supporting the selected ward.
- Summary block: items subtotal + shipping fee + final total.
- Payment method: CASH or VIETQR.
- "Xác nhận tạo đơn" button calling `createStaffOrder`.

- [ ] **Step 3: Add Trigger button in Orders Page**

Add "+ Tạo đơn qua điện thoại" button in header of `apps/admin-web/src/app/(dashboard)/dashboard/orders/page.tsx`.

- [ ] **Step 4: Add Source badge in Order Table & Order Detail Modal**

Render `STOREFRONT` (Khách đặt) vs `STAFF` (Nhân viên tạo) badge in `order-table.tsx` and `order-detail-modal.tsx`.

- [ ] **Step 5: Test build and lint**

Run: `pnpm --filter admin-web build && pnpm --filter admin-web lint`
Expected: 0 errors

- [ ] **Step 6: Commit in apps/admin-web**

```bash
git -C apps/admin-web add src
git -C apps/admin-web commit -m "feat(admin-web): Add staff phone order creation modal and order source badges"
```

---

### Task 6: Storefront - Store Config Hook & Call-to-Order Experience

**Files:**
- Modify: `apps/storefront/src/lib/api.ts`
- Create: `apps/storefront/src/hooks/use-store-config.ts`
- Modify: `apps/storefront/src/components/layout/header.tsx`
- Modify: `apps/storefront/src/components/layout/bottom-nav.tsx`
- Modify: `apps/storefront/src/components/menu/menu-view.tsx`
- Modify: `apps/storefront/src/components/menu/product-detail-view.tsx`
- Modify: `apps/storefront/src/components/cart/cart-view.tsx`
- Modify: `apps/storefront/src/components/checkout/checkout-view.tsx`

- [ ] **Step 1: Add fetchStoreConfig API and TanStack Query Hook**

In `apps/storefront/src/lib/api.ts` and `apps/storefront/src/hooks/use-store-config.ts`:
Create `useStoreConfig` with 60s staleTime.

- [ ] **Step 2: Update Header and BottomNav when ordering is disabled**

- In `header.tsx`: If `customerOrderingEnabled === false`, hide cart bag icon, render "Gọi đặt món: [phone]" button with `tel:` link.
- In `bottom-nav.tsx`: If `customerOrderingEnabled === false`, replace "Giỏ hàng" tab with "Hotline" tab linking to `tel:[phone]`.

- [ ] **Step 3: Update Menu & Product Detail Views**

- In `menu-view.tsx`: When disabled, replace "Thêm vào giỏ" button on dish cards with "Gọi đặt món" linking to `tel:[phone]`.
- In `product-detail-view.tsx`: Replace Add to Cart CTA with direct Call button.

- [ ] **Step 4: Protect /cart and /checkout pages**

- In `cart-view.tsx` & `checkout-view.tsx`: If `customerOrderingEnabled === false`, display friendly banner "Cửa hàng hiện tạm ngưng đặt món qua website. Quý khách vui lòng gọi [phone] để đặt món giao tận nơi." with a large direct Call button.
- If order submission fails with `CUSTOMER_ORDERING_DISABLED` or ordering disabled message, do not wipe user cart, show localized error and direct call button.

- [ ] **Step 5: Test build and lint**

Run: `pnpm --filter storefront build && pnpm --filter storefront lint`
Expected: 0 errors

- [ ] **Step 6: Commit in apps/storefront**

```bash
git -C apps/storefront add src
git -C apps/storefront commit -m "feat(storefront): Add call-to-order mode when customer ordering is disabled"
```

---

### Task 7: Full System Verification & Monorepo Validation

**Files:**
- Root & Submodules

- [ ] **Step 1: Run linter across all projects**

Run in root: `pnpm lint`
Expected: 0 errors

- [ ] **Step 2: Run unit and integration tests**

Run: `pnpm test`
Expected: All tests pass.

- [ ] **Step 3: Run builds across all projects**

Run:
- `pnpm --filter ordering-service build`
- `pnpm --filter admin-web build`
- `pnpm --filter storefront build`
Expected: All build cleanly.

- [ ] **Step 4: Commit root repository**

Stage updated submodule references and docs in root on local `main`:
```bash
git add apps/api apps/admin-web apps/storefront docs/superpowers
git commit -m "chore(root): Complete storefront ordering mode and staff phone orders feature"
```
