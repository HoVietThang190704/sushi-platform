# Realtime WebSocket Invalidation Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Triển khai hạ tầng cập nhật dữ liệu realtime qua WebSocket theo hướng event-driven (Service -> RabbitMQ -> API Gateway -> Socket.IO -> Admin Web TanStack Query Invalidation) cho Admin Web.

**Architecture:** Khi service (Inventory/Catalog) cập nhật dữ liệu, service đẩy domain event lên RabbitMQ exchange `sushi.events`. API Gateway lắng nghe event qua RabbitMQ consumer và phát tín hiệu nhẹ qua Socket.IO tới các phòng phù hợp (`branch:<branchId>`, `role:<role>`). Admin Web dùng `RealtimeProvider` để bắt event và tự động `queryClient.invalidateQueries` làm mới màn hình mà không cần reload trang.

**Tech Stack:** NestJS 11, `@nestjs/websockets`, `@nestjs/platform-socket.io`, `socket.io`, `socket.io-client`, `amqplib`, Next.js 16 (App Router), `@tanstack/react-query` v5, TypeScript.

**Spec:** `docs/superpowers/specs/2026-10-24-realtime-websocket-sync-design.md`

## Global Constraints
- **Không truyền full entity qua socket:** Chỉ gửi metadata tín hiệu (`resource`, `action`, `branchId`, `timestamp`, `id`).
- **REST giữ vai trò Single Source of Truth:** Giao diện chỉ tải lại dữ liệu mới nhất qua REST query khi nhận tín hiệu.
- **Bảo mật:** Socket handshake phải kiểm tra `access_token` từ Cookie hoặc Bearer Header qua `JWT_SECRET`.
- **Tương thích mạng LAN/Mobile:** Cho phép CORS WebSocket từ dải IP LAN giống HTTP Gateway.

## Review Focus
1. Handshake thiếu cookie/token hoặc token hết hạn -> Gateway từ chối kết nối (`401 Unauthorized`), client không loop spam.
2. Mất kết nối RabbitMQ tạm thời -> Service không làm treo request REST chính; Gateway tự reconnect.
3. Client rớt mạng rồi kết nối lại -> Tự động trigger revalidation dữ liệu hiện tại để tránh bỏ lỡ thay đổi trong lúc offline.
4. Sự kiện sai branch -> Admin ở chi nhánh A không bị nhảy dữ liệu của chi nhánh B.
5. Invalidation spam khi nhiều event dồn dập -> TanStack Query xử lý deduplicate/batch request hợp lý.

---

### Task 1: Contracts & Event Interfaces Shared Package / Shared Lib
**Files:**
- Create: `apps/api/libs/contracts/src/realtime-events.ts`
- Create: `apps/api/libs/contracts/src/index.ts`
- Modify: `apps/api/tsconfig.json`

**Interfaces:**
- Produces: `RealtimeDomainEvent`, `REALTIME_EXCHANGE = 'sushi.events'`

- [ ] **Step 1: Viết test định nghĩa interface & event serializer**
Tạo test kiểm tra cấu trúc chuẩn của RealtimeDomainEvent.

- [ ] **Step 2: Chạy test để xác nhận fail**
Run: `pnpm --filter sushi-api test contracts`

- [ ] **Step 3: Viết mã nguồn contracts cho realtime event**
Định nghĩa `RealtimeDomainEvent` với các trường `id`, `type`, `resource`, `action`, `branchId`, `timestamp`, `payload`.

- [ ] **Step 4: Chạy test để kiểm tra pass**
Run: `pnpm --filter sushi-api test`

- [ ] **Step 5: Commit**
```bash
git add apps/api/libs/contracts
git commit -m "feat(realtime): add shared realtime event contracts"
```

---

### Task 2: Service-side Event Publisher (RabbitMQ) trong Inventory & Catalog Service
**Files:**
- Create: `apps/api/libs/common/src/rabbitmq/rabbitmq.module.ts`
- Create: `apps/api/libs/common/src/rabbitmq/rabbitmq.service.ts`
- Modify: `apps/api/package.json` (thêm `amqplib`, `@types/amqplib`)
- Modify: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Modify: `apps/api/apps/catalog-service/src/catalog-service.service.ts`

**Interfaces:**
- Consumes: `RealtimeDomainEvent` từ Task 1
- Produces: `RabbitMQService.publishEvent(event: RealtimeDomainEvent): Promise<void>`

- [ ] **Step 1: Cài đặt dependency `amqplib`**
Run: `pnpm --filter sushi-api add amqplib && pnpm --filter sushi-api add -D @types/amqplib`

- [ ] **Step 2: Viết test cho RabbitMQService**
Tạo unit test mock channel/connection RabbitMQ, kiểm tra assertExchange và publish fanout/topic.

- [ ] **Step 3: Triển khai RabbitMQService & RabbitMQModule**
Kết nối an toàn đến `RABBITMQ_URL`, tự động phục hồi kết nối và log lỗi thay vì throw làm crash luồng DB.

- [ ] **Step 4: Kích hoạt publish event sau khi `createTransaction` và `createIngredient` thành công**
Gửi event `inventory.stock.updated` khi hoàn tất transaction.

- [ ] **Step 5: Kích hoạt publish event sau khi `createProduct` và `createCategory` thành công**
Gửi event `catalog.product.created`, `catalog.category.created`.

- [ ] **Step 6: Chạy test Inventory và Catalog service**
Run: `pnpm --filter sushi-api test inventory.service.spec.ts`

- [ ] **Step 7: Commit**
```bash
git add apps/api/libs/common/src/rabbitmq apps/api/apps/inventory-service apps/api/apps/catalog-service
git commit -m "feat(realtime): publish domain events to RabbitMQ from inventory and catalog"
```

---

### Task 3: API Gateway Socket.IO Gateway & RabbitMQ Consumer
**Files:**
- Create: `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`
- Create: `apps/api/apps/api-gateway/src/realtime/realtime-consumer.service.ts`
- Create: `apps/api/apps/api-gateway/src/realtime/realtime.module.ts`
- Modify: `apps/api/apps/api-gateway/src/app.module.ts`
- Modify: `apps/api/package.json` (thêm `@nestjs/websockets`, `@nestjs/platform-socket.io`, `socket.io`)

**Interfaces:**
- Consumes: RabbitMQ messages từ exchange `sushi.events`
- Produces: WebSocket server emit event `realtime:event` tới client

- [ ] **Step 1: Cài đặt dependency Socket.IO cho NestJS**
Run: `pnpm --filter sushi-api add @nestjs/websockets @nestjs/platform-socket.io socket.io`

- [ ] **Step 2: Viết unit test cho Handshake Authentication Guard**
Test kiểm tra xác thực cookie `access_token` hợp lệ -> giải mã ra `sub`, `role`, `branchId`; token sai -> reject connection.

- [ ] **Step 3: Triển khai RealtimeGateway với xác thực JWT Handshake**
Xử lý `handleConnection`: bóc tách cookie/header, verify JWT, gán user info vào socket, cho socket join room `branch:<branchId>` và `role:<role>`.

- [ ] **Step 4: Triển khai RealtimeConsumerService**
Lắng nghe queue `api_gateway_realtime` gắn với exchange `sushi.events`, nhận message và chuyển tiếp qua `RealtimeGateway.server.to(...).emit('realtime:event', event)`.

- [ ] **Step 5: Đăng ký RealtimeModule vào AppModule của Gateway**
Mở namespace `/realtime` với CORS tương thích dải LAN/localhost.

- [ ] **Step 6: Chạy test API Gateway**
Run: `pnpm --filter sushi-api test api-gateway`

- [ ] **Step 7: Commit**
```bash
git add apps/api/apps/api-gateway
git commit -m "feat(realtime): add Socket.IO gateway and RabbitMQ listener in api-gateway"
```

---

### Task 4: Admin Web Socket Client & TanStack Query Invalidation Provider
**Files:**
- Modify: `apps/admin-web/package.json` (thêm `socket.io-client`)
- Create: `apps/admin-web/src/providers/realtime-provider.tsx`
- Modify: `apps/admin-web/src/app/(dashboard)/layout.tsx`
- Modify: `apps/admin-web/src/features/inventory/hooks/use-inventory.ts`
- Modify: `apps/admin-web/src/features/catalog/hooks/use-products.ts`

**Interfaces:**
- Consumes: Socket.IO event `realtime:event` từ Gateway
- Produces: Auto-invalidation `queryClient.invalidateQueries`

- [ ] **Step 1: Cài đặt dependency `socket.io-client`**
Run: `pnpm --filter admin-web add socket.io-client`

- [ ] **Step 2: Tạo `RealtimeProvider` bao bọc Dashboard**
Kết nối tới `process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3000'` kèm `withCredentials: true`.
Xử lý các event kết nối: `connect`, `disconnect`, `connect_error`.

- [ ] **Step 3: Đăng ký handler lắng nghe `realtime:event` và ánh xạ Query Key Invalidation**
Khi nhận `resource: 'inventory'`: trigger `queryClient.invalidateQueries({ queryKey: inventoryKeys.all })`.
Khi nhận `resource: 'catalog'`: trigger `queryClient.invalidateQueries({ queryKey: catalogKeys.all })`.

- [ ] **Step 4: Xử lý Reconnection Revalidation**
Khi socket `reconnect`, tự động gọi `queryClient.invalidateQueries()` các query đang active để bù đắp sự kiện lúc rớt mạng.

- [ ] **Step 5: Tích hợp `RealtimeProvider` vào `DashboardLayout`**
Chỉ kích hoạt kết nối WebSocket khi người dùng đã đăng nhập thành công (`isAuthenticated = true`).

- [ ] **Step 6: Kiểm tra lint và typecheck admin-web**
Run: `pnpm --filter admin-web lint`

- [ ] **Step 7: Commit**
```bash
git add apps/admin-web
git commit -m "feat(realtime): integrate RealtimeProvider and query invalidation in admin-web"
```

---

### Task 5: End-to-End Verification & Edge Cases
**Files:**
- Verify: Luồng 2 cửa sổ/tab trình duyệt mở cùng lúc trên trang Quản lý kho (`/dashboard/inventory`) và Danh mục món (`/dashboard/catalog`).

- [ ] **Step 1: Khởi động hệ thống (PostgreSQL, RabbitMQ, Gateway, Inventory, Admin Web)**
Run: `docker compose -f infrastructure/docker/docker-compose.yml up -d`

- [ ] **Step 2: Thực hiện tạo giao dịch kho trên Tab 1**
Quan sát Tab 2 tự động cập nhật số tồn và danh sách phiếu nhập/xuất mà không cần F5/Reload.

- [ ] **Step 3: Kiểm tra hành vi rớt mạng và phục hồi**
Thử ngắt mạng hoặc restart Gateway, xác nhận client tự động reconnect và làm mới dữ liệu.

- [ ] **Step 4: Commit tài liệu hướng dẫn & hoàn tất**
```bash
git add docs/superpowers/plans/2026-10-24-realtime-websocket-sync.md
git commit -m "docs: finalize realtime websocket implementation plan"
```
