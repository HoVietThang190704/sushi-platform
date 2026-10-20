# Thiết Kế Phân Hệ Quản Lý Kho Nguyên Liệu (Inventory Management Subsystem)

- **Ngày tạo:** 2026-10-20
- **Trạng thái:** Chờ phê duyệt (Pending Approval)
- **Tác giả:** AI Assistant & Engineering Team
- **Hệ thống:** Sushi Platform (Chuỗi nhà hàng Sushi & Bếp trung tâm)

---

## 1. Bối Cảnh & Mục Tiêu Nghiệp Vụ

### 1.1. Bối cảnh
Khách hàng cần triển khai gấp phân hệ Quản lý Kho nguyên vật liệu F&B với tiêu chí **đơn giản trước, đúng trọng tâm nghiệp vụ, dễ bảo trì và sẵn sàng mở rộng**.

### 1.2. Mục tiêu cốt lõi
1. **Nhập tồn đầu kỳ (Initial Stock)**: Cho phép nhập số lượng tồn ban đầu khi khởi tạo mặt hàng/nguyên liệu mới.
2. **Nhập kho (Stock In - PNK)**: Lập phiếu nhập nguyên liệu từ nhà cung cấp, tự động cộng dồn số lượng tồn và lưu vết thành tiền.
3. **Xuất kho (Stock Out - PXK)**: Lập phiếu xuất nguyên liệu (xuất cho bếp chế biến hoặc xuất hủy hỏng), kiểm tra chặn xuất âm kho, tự động trừ tồn.
4. **Tồn kho thực tế (Stock Balance)**: Giám sát số lượng tồn theo thời gian thực của từng loại nguyên liệu theo đơn vị tính chuẩn (kg, gam, lít, gói, hộp...).
5. **Cảnh báo tồn 2 cấp độ**:
   - **Gần hết (Low Stock - Cảnh báo Vàng)**: Khi số lượng tồn $\le$ ngưỡng tối thiểu và $> 0$.
   - **Đã hết hàng (Out of Stock - Cảnh báo Đỏ)**: Khi số lượng tồn chạm $0$ hoặc âm.

---

## 2. Kiến Trúc Hạ Tầng & Phân Bổ Cổng Dịch Vụ

Hệ thống tuân thủ mô hình Microservices hiện hữu trong NestJS monorepo:
- **API Gateway**: Cổng `3000` (Reverse proxy toàn bộ API tới các service)
- **Identity Service**: Cổng `3001` (Xác thực, JWT, phân quyền)
- **Catalog Service**: Cổng `3002` (Danh mục thực đơn, món ăn, combo)
- **Inventory Service**: Cổng `3003` (Quản lý kho nguyên liệu, nhập - xuất - tồn - cảnh báo)
- **Admin Web**: Cổng `3004` (Next.js 16 App Router, chạy script `next dev -p 3004`)

API Gateway cấu hình chuyển tiếp:
- Route: `/api/inventory/*` $\rightarrow$ `http://localhost:3003/inventory/*`
- Thêm CORS cho nguồn `http://localhost:3004`.

---

## 3. Thiết Kế Cơ Sở Dữ Liệu (Prisma Schema - `inventory`)

Kích hoạt schema `inventory` trong file `apps/api/prisma/schema.prisma`:

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
  schemas  = ["identity", "catalog", "inventory"]
}

enum TransactionType {
  IN   // Nhập kho
  OUT  // Xuất kho
  @@schema("inventory")
}

enum TransactionReason {
  INITIAL_STOCK   // Nhập tồn đầu kỳ
  PURCHASE        // Nhập hàng nhà cung cấp
  KITCHEN_USAGE   // Xuất cho bếp chế biến
  DISCARD_WASTE   // Xuất hủy hỏng / hết hạn
  ADJUSTMENT      // Điều chỉnh kiểm kê
  @@schema("inventory")
}

model Ingredient {
  id           String   @id @default(uuid()) @db.Uuid
  code         String   @unique @db.VarChar(50) // Mã NL: NL-CA-HOI, NL-GAO...
  name         String   @db.VarChar(160)        // Tên: Cá hồi Na Uy, Gạo sushi...
  unit         String   @db.VarChar(30)         // Đơn vị tính: kg, g, lít, gói...
  currentStock Decimal  @default(0) @map("current_stock") @db.Decimal(18, 3)
  minStock     Decimal  @default(0) @map("min_stock") @db.Decimal(18, 3) // Ngưỡng an toàn
  costPrice    Decimal  @default(0) @map("cost_price") @db.Decimal(18, 2) // Giá nhập tham chiếu
  isActive     Boolean  @default(true) @map("is_active")
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")

  transactions InventoryTransaction[]

  @@map("ingredients")
  @@schema("inventory")
}

model InventoryTransaction {
  id           String            @id @default(uuid()) @db.Uuid
  code         String            @unique @db.VarChar(50) // Mã phiếu: PNK-..., PXK-...
  type         TransactionType
  reason       TransactionReason @default(PURCHASE)
  ingredientId String            @map("ingredient_id") @db.Uuid
  ingredient   Ingredient        @relation(fields: [ingredientId], references: [id])
  quantity     Decimal           @db.Decimal(18, 3)     // Số lượng phát sinh
  unitPrice    Decimal           @default(0) @map("unit_price") @db.Decimal(18, 2)
  totalAmount  Decimal           @default(0) @map("total_amount") @db.Decimal(18, 2)
  note         String?           @db.Text
  createdBy    String?           @map("created_by")
  createdAt    DateTime          @default(now()) @map("created_at")

  @@map("inventory_transactions")
  @@schema("inventory")
}
```

---

## 4. Hợp Đồng API Backend (`inventory-service` Cổng 3003)

### 4.1. Nhóm API Nguyên Liệu & Tồn Kho
- `GET /inventory/ingredients`:
  - Trả về danh sách nguyên liệu, tồn hiện tại, kèm cờ trạng thái tính toán tự động:
    - `OUT_OF_STOCK`: Khi `currentStock <= 0`
    - `LOW_STOCK`: Khi `0 < currentStock <= minStock`
    - `SAFE`: Khi `currentStock > minStock`
- `POST /inventory/ingredients`:
  - Payload: `{ code, name, unit, costPrice, minStock, initialStock? }`
  - Nếu có `initialStock > 0`: Thiết lập `currentStock = initialStock` và tự động tạo 1 phiếu giao dịch `IN` với lý do `INITIAL_STOCK` trong cùng `$transaction`.
- `GET /inventory/alerts`:
  - Trả về danh sách các nguyên liệu đang cần nhập khẩn cấp (`OUT_OF_STOCK` hoặc `LOW_STOCK`).

### 4.2. Nhóm API Giao Dịch Xuất / Nhập
- `POST /inventory/transactions`:
  - Payload: `{ type: 'IN' | 'OUT', ingredientId, quantity, unitPrice?, reason, note? }`
  - **Quy tắc nghiệp vụ**:
    - Chạy trong Prisma interactive transaction (`$transaction`).
    - Nếu `type === 'IN'`: Tự động sinh mã `PNK-YYYYMMDD-XXXX`, tăng `currentStock += quantity`, tính `totalAmount = quantity * unitPrice`.
    - Nếu `type === 'OUT'`: Kiểm tra nếu `currentStock < quantity` $\rightarrow$ Ném lỗi `BadRequestException("Số lượng tồn kho không đủ để xuất")`. Nếu đủ, tự động sinh mã `PXK-YYYYMMDD-XXXX`, giảm `currentStock -= quantity`.
- `GET /inventory/transactions`:
  - Query params: `type?: 'IN' | 'OUT'`, `ingredientId?: string`.
  - Trả về lịch sử giao dịch sắp xếp theo thời gian mới nhất.

---

## 5. Thiết Kế Giao Diện Frontend Admin Web (`apps/admin-web`, Cổng 3004)

### 5.1. Tích Hợp Điều Hướng
- Bổ sung NavItem vào `src/config/navigation.config.ts`:
  - Key: `inventory`, Path: `/dashboard/inventory`, Icon: `CookingPot`, Label: `"dashboard.menuInventory"`.
- Bổ sung Lối tắt trên Trang Tổng quan `/dashboard`.

### 5.2. Cấu Trúc Trang `/dashboard/inventory`
1. **Header Trang**:
   - Tiêu đề: *"Quản Lý Kho Nguyên Liệu"* kèm dòng phụ *"Theo dõi nhập - xuất - tồn và cảnh báo nguyên vật liệu"*.
   - Cụm nút hành động:
     - `+ Nhập Kho` (Nút đỏ son gradient mở Modal Nhập).
     - `- Xuất Kho` (Nút mở Modal Xuất dùng cho bếp/hủy).
     - `+ Thêm Nguyên Liệu` (Nút mở Modal tạo mặt hàng mới).
2. **4 Thẻ Chỉ Số Vận Hành (KPI Bento)**:
   - *Tổng nguyên liệu trong kho*: Đếm tổng mặt hàng.
   - *Cảnh báo Hết Hàng / Gần Hết*: Số lượng mặt hàng đang chạm ngưỡng nguy hiểm (tag đỏ/vàng).
   - *Tổng lượt nhập kho* (`PNK`).
   - *Tổng lượt xuất kho* (`PXK`).
3. **Giao Diện Phân Tab (Tabs)**:
   - **Tab 1: Bảng Tồn Kho & Cảnh Báo (Mặc định)**:
     - Toolbar: Ô tìm kiếm nguyên liệu + Bộ lọc nhanh *"Tất cả"*, *"Gần hết"*, *"Đã hết hàng"*.
     - Bảng dữ liệu: Mã, Tên nguyên liệu, Đơn vị tính, Tồn kho thực tế (in to rõ), Ngưỡng an toàn, Badge Cảnh báo 3 mức:
       - 🟢 `An Toàn` (Tồn $> minStock$)
       - 🟡 `Gần Hết` ($0 < Tồn \le minStock$)
       - 🔴 `Đã Hết Hàng` ($Tồn \le 0$)
     - Nút thao tác nhanh trực tiếp trên từng dòng: "Nhập nhanh" / "Xuất nhanh".
   - **Tab 2: Lịch Sử Nhập Kho (`PNK`)**:
     - Bảng phiếu nhập: Mã phiếu, Tên nguyên liệu, Số lượng nhập, Đơn giá nhập, Tổng tiền, Ghi chú, Ngày tạo.
   - **Tab 3: Lịch Sử Xuất Kho (`PXK`)**:
     - Bảng phiếu xuất: Mã phiếu, Tên nguyên liệu, Số lượng xuất, Lý do xuất (Xuất bếp, Xuất hủy), Ghi chú, Ngày tạo.

### 5.3. Các Modal Nhập Liệu (Tích Hợp Zod Schema)
- `CreateIngredientModal`: Tạo nguyên liệu mới (Mã, Tên, Đơn vị tính, Ngưỡng cảnh báo, Tồn đầu kỳ).
- `StockInModal`: Lập phiếu nhập kho (Chọn nguyên liệu, Số lượng, Đơn giá nhập, Ghi chú).
- `StockOutModal`: Lập phiếu xuất kho (Chọn nguyên liệu, hiển thị sẵn số tồn hiện có, Số lượng xuất, Lý do xuất, Ghi chú).

---

## 6. Tiêu Chí Nghiệp Vụ Hoàn Thành (Acceptance Criteria)
- [ ] Schema `inventory` được sinh trong Prisma và migrate thành công vào PostgreSQL.
- [ ] Service `inventory-service` chạy độc lập trên cổng `3003`.
- [ ] API Gateway proxy thông suốt `/api/inventory/*` $\rightarrow$ `3003`.
- [ ] Admin Web chạy trên cổng `3004` giao tiếp CORS thành công với API Gateway.
- [ ] Tạo được nguyên liệu mới có sẵn số lượng tồn đầu kỳ.
- [ ] Nhập kho cộng đúng số lượng; Xuất kho trừ đúng số lượng và chặn xuất âm.
- [ ] Bảng tồn kho hiển thị chính xác 3 trạng thái cảnh báo: *An Toàn*, *Gần Hết*, *Đã Hết Hàng*.
