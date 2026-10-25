# Ordering Service MVP Design (Take Away & Cash on Pickup)

**Date:** 2026-10-25  
**Status:** Approved  
**Scope:** `apps/api/apps/ordering-service`, shared contracts, Gateway routing, Admin Web & Storefront preparation.

---

## 1. Intent & Business Requirements

- **Take Away Model:** Khách hàng đặt món mang về, nhận tại quán sớm nhất có thể (không chọn khung giờ trong MVP).
- **Guest Checkout:** Khách không bắt buộc đăng nhập để đặt món.
  - Bắt buộc: Họ và tên (`customerName`), Số điện thoại (`customerPhone`).
  - Tùy chọn: `email`, `address`, `province`, `district`, `ward`. Địa chỉ lưu phục vụ liên hệ/mở rộng sau, không kích hoạt giao hàng trong MVP.
- **Single Branch Baseline:** Gắn mặc định một `branchId` chuẩn trên đơn hàng để sẵn sàng mở rộng đa chi nhánh về sau.
- **Payment Method:** Tiền mặt khi nhận món (`CASH_ON_PICKUP`). Đơn tạo ra ở trạng thái `UNPAID`. Nhân viên thu tiền khi giao và đánh dấu `PAID`.
- **Order Lifecycle & Cancellation:**
  - Trạng thái: `PENDING` -> `CONFIRMED` -> `PREPARING` -> `READY_FOR_PICKUP` -> `COMPLETED`.
  - Khách chỉ được tự hủy khi đơn chưa sang `PREPARING`.
  - Khi đã sang `PREPARING`, chỉ nhân viên/quản lý có thẩm quyền mới được xử lý hủy (`CANCELLED`).
- **Data Integrity & Privacy:**
  - Giá và tên sản phẩm do backend lấy từ Catalog và lưu snapshot vào `order_items`. Không nhận giá/tổng tiền từ client.
  - Sử dụng Idempotency Key (`idempotencyKey`) để chống tạo đơn trùng lặp do bấm nhiều lần hoặc retry mạng.
  - Khách tra cứu trạng thái qua link bí mật chứa token truy cập ngẫu nhiên (`accessTokenHash` được lưu dưới dạng băm SHA-256 trong database). Không lộ thông tin cá nhân khách hàng qua mã đơn công khai.
- **Inventory Boundary:** Tạm thời **chưa bật tự động trừ kho theo công thức món** cho đến khi dữ liệu Recipe/BOM được hoàn thiện và cơ chế outbox/locking của kho được rà soát đồng bộ.

---

## 2. Architecture & Data Model

### Database Schema (`ordering` schema trong PostgreSQL / Prisma)

```prisma
enum OrderStatus {
  PENDING
  CONFIRMED
  PREPARING
  READY_FOR_PICKUP
  COMPLETED
  CANCELLED

  @@schema("ordering")
}

enum PaymentStatus {
  UNPAID
  PAID
  REFUNDED

  @@schema("ordering")
}

model Order {
  id               String        @id @default(uuid()) @db.Uuid
  code             String        @unique @db.VarChar(50) // ORD-YYYYMMDD-XXXX
  branchId         String        @map("branch_id") @db.Uuid
  customerName     String        @map("customer_name") @db.VarChar(120)
  customerPhone    String        @map("customer_phone") @db.VarChar(30)
  customerEmail    String?       @map("customer_email") @db.VarChar(255)
  address          String?       @db.Text
  province         String?       @db.VarChar(100)
  district         String?       @db.VarChar(100)
  ward             String?       @db.VarChar(100)
  note             String?       @db.Text
  status           OrderStatus   @default(PENDING)
  paymentStatus    PaymentStatus @default(UNPAID) @map("payment_status")
  paymentMethod    String        @default("CASH") @map("payment_method") @db.VarChar(30)
  totalAmount      Decimal       @map("total_amount") @db.Decimal(18, 2)
  idempotencyKey   String?       @unique @map("idempotency_key") @db.VarChar(100)
  accessTokenHash  String        @map("access_token_hash") @db.VarChar(64)
  createdAt        DateTime      @default(now()) @map("created_at")
  updatedAt        DateTime      @updatedAt @map("updated_at")

  items            OrderItem[]
  statusHistories  OrderStatusHistory[]

  @@index([customerPhone])
  @@index([status, createdAt])
  @@map("orders")
  @@schema("ordering")
}

model OrderItem {
  id          String   @id @default(uuid()) @db.Uuid
  orderId     String   @map("order_id") @db.Uuid
  order       Order    @relation(fields: [orderId], references: [id], onDelete: Cascade)
  productId   String   @map("product_id") @db.Uuid
  productName String   @map("product_name") @db.VarChar(160)
  unitPrice   Decimal  @map("unit_price") @db.Decimal(18, 2)
  quantity    Int
  subtotal    Decimal  @db.Decimal(18, 2)

  @@map("order_items")
  @@schema("ordering")
}

model OrderStatusHistory {
  id         String      @id @default(uuid()) @db.Uuid
  orderId    String      @map("order_id") @db.Uuid
  order      Order       @relation(fields: [orderId], references: [id], onDelete: Cascade)
  fromStatus OrderStatus? @map("from_status")
  toStatus   OrderStatus @map("to_status")
  reason     String?     @db.Text
  changedBy  String      @default("SYSTEM") @map("changed_by")
  createdAt  DateTime    @default(now()) @map("created_at")

  @@map("order_status_histories")
  @@schema("ordering")
}
```

---

## 3. Endpoints & API Contract

1. `POST /orders` (Public / Storefront)
   - Header: `X-Idempotency-Key` (tùy chọn nhưng khuyến nghị)
   - Body:
     ```json
     {
       "customerName": "Nguyen Van A",
       "customerPhone": "0901234567",
       "customerEmail": "a@example.com",
       "address": "123 Le Loi",
       "province": "TP.HCM",
       "district": "Quan 1",
       "ward": "Ben Nghe",
       "note": "Khong lay wasabi",
       "items": [
         { "productId": "uuid-product", "quantity": 2 }
       ]
     }
     ```
   - Response:
     - `orderCode`: `ORD-20261025-1024`
     - `trackingToken`: Chuỗi ngẫu nhiên bí mật (raw token) chỉ trả về một lần duy nhất lúc tạo đơn.
     - `trackingUrl`: `/orders/track?code=ORD-...&token=...`

2. `GET /orders/track` (Public / Storefront)
   - Query: `code`, `token`
   - Logic: Backend băm SHA-256 `token` gửi lên so sánh với `accessTokenHash` trong DB.
   - Response: Thông tin đơn hàng (trạng thái, items, tổng tiền, thời gian; che bớt số điện thoại nếu cần).

3. `GET /orders` (Admin / Internal)
   - Quyền: Nhân viên, Quản lý (JWT Guard)
   - Query lọc: `status`, `paymentStatus`, `dateFrom`, `dateTo`.

4. `PATCH /orders/:id/status` (Admin / Internal)
   - Quyền: Nhân viên, Quản lý
   - Body: `{ "status": "CONFIRMED" | "PREPARING" | "READY_FOR_PICKUP" | "COMPLETED" | "CANCELLED", "reason": "..." }`
   - Audit: Ghi vào `OrderStatusHistory`. Phát realtime event `order.status.updated` qua RabbitMQ.

5. `PATCH /orders/:id/payment` (Admin / Internal)
   - Quyền: Thu ngân, Quản lý
   - Body: `{ "paymentStatus": "PAID" }`

6. `POST /orders/:code/cancel` (Khách tự hủy)
   - Query/Body: `token`
   - Điều kiện: Đơn đang ở `PENDING` hoặc `CONFIRMED`. Nếu đã `PREPARING`, từ chối với lỗi `400 Bad Request`.
