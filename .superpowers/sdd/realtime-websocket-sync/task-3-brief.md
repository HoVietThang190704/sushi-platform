### Task 3: API Gateway Socket.IO Gateway & RabbitMQ Consumer
**Files:**
- Create: `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`
- Create: `apps/api/apps/api-gateway/src/realtime/realtime-consumer.service.ts`
- Create: `apps/api/apps/api-gateway/src/realtime/realtime.module.ts`
- Modify: `apps/api/apps/api-gateway/src/app.module.ts`
- Modify: `apps/api/package.json` (thêm `@nestjs/websockets`, `@nestjs/platform-socket.io`, `socket.io`)
- Test: `apps/api/apps/api-gateway/src/realtime/realtime.gateway.spec.ts`

**Interfaces:**
- Consumes: RabbitMQ messages từ exchange `sushi.events` qua RabbitMQ topic queue `api_gateway_realtime`
- Produces: WebSocket server emit event `realtime:event` tới các clients phù hợp qua Socket.IO

**Constraints:**
- Handshake Authentication: Đọc cookie `access_token` hoặc `Authorization: Bearer <token>`, giải mã bằng `JwtService` (`JWT_SECRET`). Nếu không hợp lệ hoặc thiếu token -> disconnect/reject connection.
- Room Scoping: Tự động join client vào room `branch:<branchId>` (nếu có branchId) và `role:<role>`.
- Tenancy Isolation: Nếu event có `branchId`, emit tới room `branch:<branchId>`. Nếu event không có `branchId`, broadcast tới toàn bộ client authenticated.
- Strict Local: Không chạy git push.
