# Recipe BOM and Branch Inventory Deduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Bill of Materials (Recipe/BOM) and atomic inventory deduction per branch warehouse when orders transition from CONFIRMED to PREPARING, with strict block on insufficient stock.

**Architecture:** Prisma multi-schema extension with Warehouses and WarehouseStocks in `inventory` schema linked to `Branch` in `ordering` schema. Recipes for single products, combo product decomposition, atomic single-transaction stock verification and deduction, idempotency guarantee via `order_recipe_deductions`, and Admin Web UI for recipe & warehouse configuration.

**Tech Stack:** NestJS, Prisma ORM 6.4 (multiSchema PostgreSQL), RabbitMQ, Next.js 16 (React 19 App Router), Tailwind CSS.

**Spec:** `docs/superpowers/specs/2026-11-09-recipe-bom-and-inventory-deduction-design.md`

## Global Constraints

- Every unit test must be written and observed failing before implementation code (TDD).
- Transition to `PREPARING` is strictly prohibited unless current status is `CONFIRMED`.
- Stock deduction and status update must occur in a single atomic database transaction.
- If any required ingredient is missing a recipe or insufficient in the branch warehouse, the entire transaction rolls back and returns a detailed 400 error.
- Deducting the same order twice must be prevented by unique `order_id` in `order_recipe_deductions`.
- Cancelling an order after it has entered `PREPARING` must NOT auto-replenish stock.

## Review Focus

- Combo product with nested single products sharing the same ingredient correctly sums total required quantities.
- Missing recipe for any single product in the order causes strict block with clear error message.
- Concurrent orders competing for the same warehouse stock cannot drive stock negative.
- Idempotent re-execution does not deduct inventory a second time.
- Orders not in `CONFIRMED` status cannot be moved to `PREPARING`.

---

### Task 1: Prisma Schema Migration for Warehouses, WarehouseStocks, Recipes, and Deductions

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Database: Apply migration via Prisma db push / migrate
- Seed: `apps/api/prisma/seed.ts` (if needed)

**Interfaces:**
- Produces: `Warehouse`, `WarehouseStock`, `Recipe`, `RecipeItem`, `OrderRecipeDeduction` models in Prisma Client, and `warehouseId` on `Branch`.

- [ ] **Step 1: Update schema.prisma with new models and relationships**
- [ ] **Step 2: Generate Prisma Client and push/migrate to PostgreSQL database**
- [ ] **Step 3: Run existing API test suite to verify no regressions**

---

### Task 2: Warehouse and WarehouseStock Management in Inventory Service

**Files:**
- Create: `apps/api/apps/inventory-service/src/dto/create-warehouse.dto.ts`
- Create: `apps/api/apps/inventory-service/src/dto/update-stock.dto.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory.controller.ts`
- Test: `apps/api/apps/inventory-service/src/inventory.service.spec.ts`

**Interfaces:**
- Produces:
  - `getWarehouses()`
  - `createWarehouse(dto: CreateWarehouseDto)`
  - `getWarehouseStocks(warehouseId: string)`
  - `adjustWarehouseStock(warehouseId: string, dto: AdjustStockDto)`

- [ ] **Step 1: Write failing unit test for warehouse creation and stock listing**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement warehouse and warehouse stock methods in inventory service**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 3: Recipe (BOM) Management API in Inventory Service

**Files:**
- Create: `apps/api/apps/inventory-service/src/dto/create-recipe.dto.ts`
- Create: `apps/api/apps/inventory-service/src/dto/update-recipe.dto.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory.controller.ts`
- Test: `apps/api/apps/inventory-service/src/inventory.service.spec.ts`

**Interfaces:**
- Produces:
  - `getRecipes()`
  - `getRecipeByProduct(productId: string)`
  - `upsertRecipe(dto: UpsertRecipeDto)`
  - `deleteRecipe(id: string)`

- [ ] **Step 1: Write failing unit test for upserting recipe and validating ingredient items**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement recipe methods in inventory service and controller**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 4: Atomic Inventory Deduction on Order Status Transition to PREPARING

**Files:**
- Create: `apps/api/apps/ordering-service/src/inventory-deduction.helper.ts` (or integrate in ordering service)
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Consumes: `Recipe`, `RecipeItem`, `ComboItem`, `WarehouseStock`, `Branch.warehouseId`
- Produces: Atomic deduction logic during `updateOrderStatus(orderId, 'PREPARING')`

- [ ] **Step 1: Write failing unit test for strict status transition: PENDING to PREPARING must fail**
- [ ] **Step 2: Write failing unit test for insufficient ingredient stock throwing 400 Bad Request with details**
- [ ] **Step 3: Write failing unit test for combo item decomposition and aggregated stock deduction**
- [ ] **Step 4: Write failing unit test for duplicate status transition prevention (idempotency)**
- [ ] **Step 5: Run tests to verify they fail**
- [ ] **Step 6: Implement atomic deduction logic in ordering service**
- [ ] **Step 7: Run tests to verify they pass**
- [ ] **Step 8: Run entire API test suite**
- [ ] **Step 9: Commit changes**

---

### Task 5: Admin Web UI for Recipe Management and Stock Deduction Alerts

**Files:**
- Create/Modify: `apps/admin-web/src/features/inventory/components/recipe-management-view.tsx`
- Modify: `apps/admin-web/src/features/orders/components/order-detail-modal.tsx`
- Modify: `apps/admin-web/src/features/inventory/components/warehouse-stock-view.tsx`

- [ ] **Step 1: Add Recipe configuration table and modal for products**
- [ ] **Step 2: Add Warehouse Stock table and branch warehouse selector**
- [ ] **Step 3: Update Order Detail status transition buttons: only allow PREPARING when CONFIRMED**
- [ ] **Step 4: Display detailed error toast when stock deduction fails with missing ingredient list**
- [ ] **Step 5: Verify build with `pnpm lint` and `pnpm build`**
- [ ] **Step 6: Commit changes**
