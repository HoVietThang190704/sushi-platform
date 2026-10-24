### Task 2: Service-side Event Publisher (RabbitMQ) trong Inventory & Catalog Service
**Files:**
- Create: `apps/api/libs/common/src/rabbitmq/rabbitmq.service.ts`
- Create: `apps/api/libs/common/src/rabbitmq/rabbitmq.module.ts`
- Create: `apps/api/libs/common/src/rabbitmq/index.ts`
- Modify: `apps/api/package.json` (thêm `amqplib`, `@types/amqplib`)
- Modify: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Modify: `apps/api/apps/inventory-service/src/inventory-service.module.ts`
- Modify: `apps/api/apps/catalog-service/src/catalog-service.service.ts`
- Modify: `apps/api/apps/catalog-service/src/catalog-service.module.ts`

**Interfaces:**
- Consumes: `createRealtimeEvent`, `REALTIME_EXCHANGE`, `RealtimeDomainEvent` từ `@contracts`
- Produces: `RabbitMQService.publishEvent(event: RealtimeDomainEvent, routingKey?: string): Promise<boolean>`

**Constraints:**
- Resilience: Nếu RabbitMQ broker chưa bật hoặc lỗi kết nối, `publishEvent` chỉ log cảnh báo, không được throw exception làm hỏng transaction DB chính của nghiệp vụ (`createTransaction`, `createProduct`).
- Clean Code: Không dùng `any`, có đầy đủ unit tests, graceful shutdown khi module destroy (`onModuleDestroy`).
- Strict Local: Không git push lên remote.
