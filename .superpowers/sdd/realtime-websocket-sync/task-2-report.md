# Task 2 Report: Service-side Event Publisher (RabbitMQ) trong Inventory & Catalog Service

## 1. Trạng thái
- **Trạng thái:** DONE
- **Tiêu chuẩn chất lượng:** 100% tests pass (7 test suites, 29 tests), không có lỗi build/compilation, try/catch bảo vệ fault-tolerant tránh crash DB transaction khi broker RabbitMQ gián đoạn.

---

## 2. Các file đã tạo và chỉnh sửa
### Files tạo mới:
1. `apps/api/libs/common/src/rabbitmq/rabbitmq.service.ts`:
   - Kết nối tới `RABBITMQ_URL` (default: `amqp://sushi_app:change_me_local@localhost:5672`).
   - Khởi tạo và assert Topic Exchange `sushi.events` (`durable: true`).
   - Hàm `publishEvent(event: RealtimeDomainEvent, routingKey?: string): Promise<boolean>`:
     - Serialize event sang Buffer JSON.
     - Routing key mặc định lấy từ `event.type`.
     - Try/catch toàn diện, log warning và trả về `false` khi RabbitMQ disconnect hoặc publish lỗi (không throw exception làm gián đoạn transaction DB).
   - Lifecycle hook: `onModuleInit` để kết nối, `onModuleDestroy` để đóng connection và channel an toàn.
2. `apps/api/libs/common/src/rabbitmq/rabbitmq.module.ts`:
   - Module `@Global()` export `RabbitMQService`.
3. `apps/api/libs/common/src/rabbitmq/index.ts`:
   - Export `RabbitMQModule`, `RabbitMQService`.
4. `apps/api/libs/common/src/rabbitmq/rabbitmq.service.spec.ts`:
   - Unit test kiểm tra khởi tạo, assert exchange, publish thành công, override routing key, fault-tolerance khi mất kết nối hoặc channel lỗi, và đóng kết nối graceful shutdown (8 tests passed).
5. `apps/api/apps/catalog-service/src/catalog-service.service.spec.ts`:
   - Unit test cho `CatalogServiceService` xác nhận `createCategory` phát event `catalog.category.created` và `createProduct` phát event `catalog.product.created` (4 tests passed).

### Files chỉnh sửa:
1. `apps/api/package.json` & `apps/api/pnpm-lock.yaml`:
   - Thêm dependency `amqplib` (^2.2.0) và devDependency `@types/amqplib` (^0.10.8).
2. `apps/api/libs/common/src/index.ts`:
   - Export `* from './rabbitmq'`.
3. `apps/api/apps/inventory-service/src/inventory.service.ts`:
   - Inject `RabbitMQService`.
   - Trong `createTransaction`: Sau khi commit transaction DB thành công, gọi `publishEvent(createRealtimeEvent({ type: 'inventory.stock.updated', resource: 'inventory', action: 'UPDATED', payload: { code: transaction.code, ingredientId: dto.ingredientId, type: dto.type, quantity: qty } }))`.
   - Trong `createIngredient`: Sau khi tạo ingredient thành công, phát `inventory.ingredient.created`.
4. `apps/api/apps/inventory-service/src/inventory-service.module.ts`:
   - Import `RabbitMQModule`.
5. `apps/api/apps/inventory-service/src/inventory.service.spec.ts`:
   - Cung cấp mock `RabbitMQService`, bổ sung test case xác thực phát `inventory.stock.updated` và `inventory.ingredient.created` (3 tests passed).
6. `apps/api/apps/catalog-service/src/catalog-service.service.ts`:
   - Inject `RabbitMQService`.
   - Trong `createProduct`: Sau khi tạo product thành công, phát `catalog.product.created`.
   - Trong `createCategory`: Sau khi tạo category thành công, phát `catalog.category.created`.
7. `apps/api/apps/catalog-service/src/catalog-service.module.ts`:
   - Import `RabbitMQModule`.
8. `apps/api/apps/catalog-service/src/catalog-service.controller.spec.ts`:
   - Mock `RolesGuard`, `RabbitMQService`, `PrismaService`, `CloudinaryService` cho controller test (5 tests passed).
9. `apps/api/eslint.config.mjs`:
   - Thêm quy tắc nới lỏng cho Jest test files (`**/*.spec.ts`) để tránh cảnh báo unbound method / unsafe assignment trong test assertion.

---

## 3. Kết quả kiểm thử
- **Lệnh thực thi:** `pnpm --prefix apps/api test`
- **Kết quả:**
  ```text
  Test Suites: 7 passed, 7 total
  Tests:       29 passed, 29 total
  Snapshots:   0 total
  Time:        1.872 s
  Ran all test suites.
  ```
- **Build verification:**
  ```text
  pnpm --prefix apps/api build
  - api-gateway: compiled successfully
  - identity-service: compiled successfully
  - catalog-service: compiled successfully
  - inventory-service: compiled successfully
  ```

---

## 4. Git Commit Hash
- **apps/api repo:** `d6a53ff` (`feat(realtime): publish domain events to RabbitMQ from inventory and catalog`)
- **root repo:** `00b7e9b` (`feat(realtime): publish domain events to RabbitMQ from inventory and catalog`)
- **Push status:** Strict Local (không thực hiện `git push` theo yêu cầu).
