# Ordering Service MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Xây dựng Ordering Service độc lập cho nền tảng Sushi Platform hỗ trợ đặt món Take Away không cần đăng nhập, thanh toán tiền mặt khi nhận món, theo dõi trạng thái bảo mật qua token bí mật, và chống tạo đơn trùng lặp.

**Architecture:** Tạo NestJS microservice `apps/api/apps/ordering-service` sở hữu schema `ordering` trong PostgreSQL (Neon). Giá sản phẩm và tên món được snapshot từ Catalog Service tại thời điểm đặt để ngăn chặn giả mạo giá từ client. Khách hàng theo dõi đơn qua liên kết chứa access token ngẫu nhiên (lưu bản băm SHA-256 trong database). Quản trị viên cập nhật trạng thái đơn qua Gateway và phát sự kiện realtime qua RabbitMQ.

**Tech Stack:** NestJS 11, Prisma 6 (Multi-Schema PostgreSQL), TypeScript, class-validator, crypto (SHA-256), RabbitMQ.

**Spec:** `docs/superpowers/specs/2026-10-25-ordering-service-mvp-design.md`

## Global Constraints

- **Single Source of Truth:** Không bao giờ tin tưởng giá bán, tổng tiền hoặc trạng thái do client gửi lên. Backend luôn đọc giá hiện tại từ database/Catalog.
- **Idempotency:** Mỗi request tạo đơn hỗ trợ `X-Idempotency-Key` (hoặc trường `idempotencyKey`), nếu key đã tồn tại thì trả về đơn đã tạo trước đó thay vì tạo mới.
- **Privacy by Design:** Khách không cần đăng nhập, nhưng theo dõi đơn qua token bí mật ngẫu nhiên (32 bytes hex). Chỉ lưu `accessTokenHash = SHA-256(token)` trong database.
- **Cancellation Rule:** Khách chỉ được tự hủy trước khi đơn sang trạng thái `PREPARING`.
- **Payment Method:** MVP chỉ hỗ trợ thanh toán tiền mặt khi nhận hàng (`CASH_ON_PICKUP`), trạng thái ban đầu luôn là `UNPAID`.
- **Inventory Decoupling:** Không tự động trừ kho trong MVP cho tới khi hoàn thiện BOM/Recipe service.

## Review Focus

1. Client sửa giá bán trong payload -> Backend bỏ qua giá client, tính đúng theo giá Catalog.
2. Hai request tạo đơn gửi cùng `idempotencyKey` -> Chỉ tạo 1 đơn duy nhất, request thứ hai trả về đơn đã tạo.
3. Người lạ dùng `orderCode` công khai để tra cứu mà không có `token` bí mật -> Từ chối truy cập (401/403).
4. Khách yêu cầu hủy đơn khi trạng thái đã là `PREPARING` hoặc `READY_FOR_PICKUP` -> Ném lỗi `BadRequestException` ("Đơn hàng đã bắt đầu chế biến, không thể hủy").
5. Đơn hàng không có món nào hoặc số lượng <= 0 -> Ném lỗi `BadRequestException`.

---

### Task 1: Prisma Schema & Database Migration cho Ordering

**Files:**
- Modify: `apps/api/prisma/schema.prisma`

**Interfaces:**
- Produces: `Order`, `OrderItem`, `OrderStatusHistory`, `OrderStatus`, `PaymentStatus` trong `@prisma/client`.

- [ ] **Step 1: Cập nhật `schema.prisma` thêm schema `ordering`**
Thêm `"ordering"` vào `schemas = ["identity", "catalog", "inventory", "ordering"]`. Định nghĩa `OrderStatus`, `PaymentStatus`, `Order`, `OrderItem`, `OrderStatusHistory`.

- [ ] **Step 2: Đẩy schema lên database**
Run: `pnpm --filter sushi-api prisma db push --skip-generate`
Expected: Database Neon cập nhật bảng mới trong schema `ordering`.

- [ ] **Step 3: Cập nhật Prisma Client**
Run: `pnpm --filter sushi-api prisma generate`
Expected: Tạo thành công Prisma Client có kiểu dữ liệu `Order`, `OrderItem`, `OrderStatusHistory`.

- [ ] **Step 4: Commit**
```bash
git add apps/api/prisma/schema.prisma
git commit -m "feat(ordering): add ordering schema models to prisma"
```

---

### Task 2: Shared Contracts cho Ordering Events

**Files:**
- Modify: `apps/api/libs/contracts/src/realtime-events.ts`
- Modify: `apps/api/libs/contracts/src/index.ts`
- Test: `apps/api/libs/contracts/src/realtime-events.spec.ts`

**Interfaces:**
- Produces: `OrderEventPayload`, `createOrderRealtimeEvent`, event types: `order.created`, `order.status.updated`, `order.payment.updated`.

- [ ] **Step 1: Viết test cho Order event contracts**
Tạo test kiểm tra cấu trúc event `order.status.updated` tuân thủ `RealtimeDomainEvent`.

- [ ] **Step 2: Chạy test xác nhận fail**
Run: `pnpm --filter sushi-api test contracts`

- [ ] **Step 3: Viết mã nguồn contracts cho Order events**
Export các type và helper `createOrderRealtimeEvent`.

- [ ] **Step 4: Chạy test xác nhận pass**
Run: `pnpm --filter sushi-api test contracts`

- [ ] **Step 5: Commit**
```bash
git add apps/api/libs/contracts
git commit -m "feat(ordering): add order realtime event contracts"
```

---

### Task 3: Scaffold Ordering Microservice Structure

**Files:**
- Create: `apps/api/apps/ordering-service/src/main.ts`
- Create: `apps/api/apps/ordering-service/src/ordering-service.module.ts`
- Create: `apps/api/apps/ordering-service/src/prisma.service.ts`
- Modify: `apps/api/nest-cli.json`
- Modify: `apps/api/package.json`

**Interfaces:**
- Produces: `start:ordering:dev` script, `build:ordering` script, port `3004`.

- [ ] **Step 1: Đăng ký app `ordering-service` trong `nest-cli.json`**
Thêm cấu hình compiler và root dir cho `ordering-service`.

- [ ] **Step 2: Thêm npm scripts vào `package.json`**
Thêm `build:ordering`: `nest build ordering-service` và `start:ordering:dev`: `nest start ordering-service --watch`.

- [ ] **Step 3: Tạo `prisma.service.ts` và `ordering-service.module.ts`**
Khởi tạo Nest module kết nối Prisma và RabbitMQ.

- [ ] **Step 4: Kiểm tra build**
Run: `pnpm --filter sushi-api build:ordering`
Expected: Webpack compile thành công.

- [ ] **Step 5: Commit**
```bash
git add apps/api/apps/ordering-service apps/api/nest-cli.json apps/api/package.json
git commit -m "feat(ordering): scaffold ordering microservice"
```

---

### Task 4: Core Domain Logic: Tạo đơn hàng với TDD

**Files:**
- Create: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Create: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`
- Create: `apps/api/apps/ordering-service/src/dto/create-order.dto.ts`

**Interfaces:**
- Produces: `OrderingService.createOrder(dto: CreateOrderDto): Promise<{ order: Order, trackingToken: string }>`

- [ ] **Step 1: Viết failing test cho `createOrder`**
  - Test 1: Kiểm tra tính toán giá phía server (lấy giá từ bảng `catalog.products`, bỏ qua giá client).
  - Test 2: Kiểm tra sinh `orderCode` chuẩn (`ORD-YYYYMMDD-XXXX`).
  - Test 3: Kiểm tra sinh `trackingToken` (raw) và lưu `accessTokenHash = SHA-256(token)`.
  - Test 4: Kiểm tra chống trùng lặp với `idempotencyKey`.
  - Test 5: Bắt lỗi nếu giỏ hàng rỗng hoặc sản phẩm không tồn tại / đã ngừng bán (`isActive = false`).

- [ ] **Step 2: Chạy test xác nhận fail**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 3: Viết mã nguồn `createOrder`**
Triển khai logic tính tiền, băm token SHA-256, transaction tạo đơn + order_items + history ban đầu `PENDING`.

- [ ] **Step 4: Chạy test xác nhận pass**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 5: Commit**
```bash
git add apps/api/apps/ordering-service
git commit -m "feat(ordering): implement order creation with price snapshot and idempotency"
```

---

### Task 5: Core Domain Logic: Theo dõi đơn hàng bí mật (Tracking) với TDD

**Files:**
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Produces: `OrderingService.trackOrder(code: string, token: string): Promise<OrderTrackResult>`

- [ ] **Step 1: Viết failing test cho `trackOrder`**
  - Test 1: Truy vấn đúng mã đơn và token hợp lệ -> Trả về thông tin đơn, danh sách món và lịch sử trạng thái.
  - Test 2: Mã đơn không tồn tại -> Ném `NotFoundException`.
  - Test 3: Mã đơn đúng nhưng token sai -> Ném `UnauthorizedException` hoặc `ForbiddenException`.

- [ ] **Step 2: Chạy test xác nhận fail**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 3: Triển khai `trackOrder`**
Băm `token` gửi lên qua SHA-256 và so khớp với `order.accessTokenHash`.

- [ ] **Step 4: Chạy test xác nhận pass**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 5: Commit**
```bash
git add apps/api/apps/ordering-service
git commit -m "feat(ordering): implement secure order tracking via secret token"
```

---

### Task 6: Core Domain Logic: Chuyển trạng thái, Hủy đơn & Audit Log với TDD

**Files:**
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Produces:
  - `updateOrderStatus(orderId: string, toStatus: OrderStatus, reason?: string, changedBy?: string)`
  - `cancelOrderByCustomer(code: string, token: string, reason?: string)`
  - `updatePaymentStatus(orderId: string, status: PaymentStatus)`

- [ ] **Step 1: Viết failing test cho chuyển trạng thái và hủy đơn**
  - Test 1: Khách hủy đơn khi `PENDING` -> Đơn chuyển `CANCELLED`, ghi history `Khách tự hủy`.
  - Test 2: Khách hủy đơn khi trạng thái đã là `PREPARING` -> Ném `BadRequestException`.
  - Test 3: Quản trị viên cập nhật trạng thái đơn -> Cập nhật `Order`, ghi `OrderStatusHistory`, phát event RabbitMQ `order.status.updated`.
  - Test 4: Thu ngân đánh dấu `PAID` -> Cập nhật `paymentStatus = PAID`.

- [ ] **Step 2: Chạy test xác nhận fail**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 3: Triển khai logic trạng thái và hủy đơn**
Triển khai chuyển trạng thái và ràng buộc hủy đơn.

- [ ] **Step 4: Chạy test xác nhận pass**
Run: `pnpm --filter sushi-api test ordering.service.spec.ts`

- [ ] **Step 5: Commit**
```bash
git add apps/api/apps/ordering-service
git commit -m "feat(ordering): implement status transitions, customer cancel rules and audit trail"
```

---

### Task 7: Controllers & Gateway Proxy

**Files:**
- Create: `apps/api/apps/ordering-service/src/ordering.controller.ts`
- Modify: `apps/api/apps/api-gateway/src/main.ts`
- Modify: `apps/api/apps/api-gateway/src/app.module.ts`
- Test: `apps/api/apps/ordering-service/src/ordering.controller.spec.ts`

**Interfaces:**
- Produces: REST endpoints `/orders`, `/orders/track`, `/orders/:id/status`, `/orders/:id/payment`, `/orders/:code/cancel`. Gateway chuyển tiếp request `/orders` sang port `3004`.

- [ ] **Step 1: Viết unit test cho `OrderingController`**
Kiểm tra ủy quyền gọi service từ controller.

- [ ] **Step 2: Triển khai `OrderingController` với DTO Validation**
Sử dụng `ValidationPipe`, bảo vệ endpoint quản trị bằng `RolesGuard` / JWT.

- [ ] **Step 3: Cấu hình Gateway Reverse Proxy cho Ordering Service**
Thêm reverse proxy trong `apps/api/apps/api-gateway/src/main.ts` định tuyến `/orders` tới `INVENTORY_SERVICE_PORT / ORDERING_SERVICE_PORT = 3005`.

- [ ] **Step 4: Chạy toàn bộ test suite và build**
Run: `pnpm --filter sushi-api test && pnpm --filter sushi-api build`
Expected: 100% test passing, build không có lỗi.

- [ ] **Step 5: Commit**
```bash
git add apps/api/apps/ordering-service apps/api/apps/api-gateway
git commit -m "feat(ordering): add REST controller and gateway reverse proxy"
```
