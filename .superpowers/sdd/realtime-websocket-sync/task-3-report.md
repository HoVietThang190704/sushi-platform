# Task 3 Report: API Gateway Socket.IO Gateway & RabbitMQ Consumer

## Trạng thái
**DONE**

## Chi tiết công việc thực hiện

### 1. Cài đặt dependency Socket.IO cho API Gateway
- Đã cài đặt các dependencies tương thích với NestJS v11:
  - `@nestjs/websockets@^11.0.1`
  - `@nestjs/platform-socket.io@^11.0.1`
  - `socket.io@^4.8.4`
  - `@nestjs/jwt@^11.0.0`

### 2. Các file đã tạo & chỉnh sửa

#### Files tạo mới:
1. `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`
   - Khởi tạo `@WebSocketGateway({ cors: { origin: true, credentials: true }, namespace: '/realtime' })`.
   - Implement `OnGatewayConnection` và `OnGatewayDisconnect`.
   - Trích xuất JWT token linh hoạt từ:
     - Cookie `access_token` qua header `cookie`
     - Handshake `auth.token`
     - Header `authorization` (Bearer token)
   - Nếu thiếu token hoặc verify thất bại -> gọi `client.disconnect()`.
   - Khi token hợp lệ -> gán payload vào `client.data.user`, tự động cho socket join room `branch:<branchId>`, `role:<role>`, và room chung `authenticated`.
   - Method `broadcastRealtimeEvent(event: RealtimeDomainEvent)`:
     - Phân phối event tới room `branch:<branchId>` nếu có `branchId`.
     - Phân phối event tới room `authenticated` nếu không có `branchId`.

2. `apps/api/apps/api-gateway/src/realtime/realtime-consumer.service.ts`
   - Kết nối tới RabbitMQ (`REALTIME_EXCHANGE = 'sushi.events'`).
   - Khởi tạo và assert queue `api_gateway_realtime` (`exclusive: false`, `durable: true`).
   - Bind queue `api_gateway_realtime` vào exchange `sushi.events` với routing pattern `#`.
   - Lắng nghe message, parse JSON sang `RealtimeDomainEvent`, gọi `RealtimeGateway.broadcastRealtimeEvent(event)` và ack message.
   - Bọc toàn bộ xử lý trong try/catch an toàn tránh poison messages làm crash process hoặc tắc nghẽn queue.
   - Quản lý lifecycle `onModuleInit` và `onModuleDestroy` đóng kết nối an toàn.

3. `apps/api/apps/api-gateway/src/realtime/realtime.module.ts`
   - Đăng ký `JwtModule.register({})`.
   - Đăng ký providers: `RealtimeGateway`, `RealtimeConsumerService`.
   - Export `RealtimeGateway`.

4. `apps/api/apps/api-gateway/src/realtime/realtime.gateway.spec.ts`
   - Unit test xác thực handshake qua cookie `access_token`, `auth.token`, `Authorization: Bearer`.
   - Unit test kiểm tra join room `branch:<branchId>`, `role:<role>`, `authenticated`.
   - Unit test từ chối kết nối khi thiếu token hoặc token hết hạn/không hợp lệ.
   - Unit test `broadcastRealtimeEvent` theo tenancy isolation (branch room vs authenticated room).

5. `apps/api/apps/api-gateway/src/realtime/realtime-consumer.service.spec.ts`
   - Unit test thiết lập exchange, queue và binding `#`.
   - Unit test nhận message, broadcast realtime event và ack.
   - Unit test xử lý payload lỗi/invalid JSON an toàn.
   - Unit test dọn dẹp kết nối khi module destroy.

#### Files chỉnh sửa:
1. `apps/api/apps/api-gateway/src/app.module.ts`: Import `RealtimeModule`.
2. `apps/api/package.json` & `apps/api/pnpm-lock.yaml`: Cập nhật các dependencies Socket.IO và NestJS.

---

## Kết quả kiểm thử & Build

### Test Suite:
```
$ jest
Test Suites: 9 passed, 9 total
Tests:       40 passed, 40 total
Snapshots:   0 total
Time:        2.156 s
```
- `realtime.gateway.spec.ts`: 7/7 passed.
- `realtime-consumer.service.spec.ts`: 4/4 passed.
- Toàn bộ 9 test suites của toàn bộ `apps/api`: PASSED.

### Build Verification:
```
$ nest build api-gateway
webpack 5.106.2 compiled successfully in 3024 ms
```
- Toàn bộ 4 backend services (`api-gateway`, `identity-service`, `catalog-service`, `inventory-service`) build thành công không lỗi.

---

## Git Commit
- **Commit Hash:** `07d2d0b8dbe0cd541a1c03fcf25a265d48549a00`
- **Commit Message:** `feat(realtime): add Socket.IO gateway and RabbitMQ listener in api-gateway`
- **Remote Push:** TUYỆT ĐỐI KHÔNG CHẠY `git push` (Strict Local Policy tuân thủ).
