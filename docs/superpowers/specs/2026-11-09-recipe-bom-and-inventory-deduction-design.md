# Thiết Kế Phân Hệ Công Thức Món (BOM) & Khấu Trừ Tồn Kho Theo Chi Nhánh

- **Ngày tạo:** 2026-11-09
- **Trạng thái:** Đã thống nhất (Approved)
- **Hệ thống:** Sushi Platform (Chuỗi nhà hàng Sushi & Bếp chế biến)

---

## 1. Bối Cảnh & Các Quyết Định Nghiệp Vụ Cốt Lõi

1. **Gán Chi nhánh - Kho:** Mỗi chi nhánh (`Branch`) gắn với đúng **1 Kho (`Warehouse`)**. Một kho có thể được dùng chung bởi nhiều chi nhánh.
2. **Quản lý Tồn kho đa điểm:** Tồn kho nguyên liệu được quản lý theo cặp `(warehouseId, ingredientId)` trong bảng `warehouse_stocks`. `Ingredient` lưu thông tin danh mục, đơn vị chuẩn (`unit`) và giá vốn chuẩn.
3. **Định mức công thức (BOM):**
   - Chỉ cấu hình công thức cho sản phẩm đơn (`SINGLE`).
   - Sản phẩm `COMBO` được tự động phân rã thành các sản phẩm đơn thành phần dựa theo cấu trúc `combo_items` trong Catalog, sau đó nhân số lượng và cộng dồn định mức nguyên liệu.
   - Đơn vị tính định mức trong công thức khớp trực tiếp với `unit` của `Ingredient` (g, ml, quả, miếng...).
4. **Quy tắc chuyển trạng thái & Điểm trừ kho:**
   - Luồng trạng thái đơn hàng bắt buộc: `PENDING` $\rightarrow$ `CONFIRMED` $\rightarrow$ `PREPARING`.
   - **Chỉ khi chuyển từ `CONFIRMED` sang `PREPARING`**, hệ thống mới thực hiện khấu trừ kho. Không cho phép chuyển thẳng từ `PENDING` sang `PREPARING`.
5. **Chính sách chặn nghiêm ngặt (Strict Block):**
   - Nếu bất kỳ món ăn nào trong đơn thiếu công thức, hoặc bất kỳ nguyên liệu nào trong kho của chi nhánh không đủ số lượng tồn, hệ thống **CHẶN** chuyển trạng thái sang `PREPARING`.
   - Trả về danh sách chi tiết các nguyên liệu bị thiếu kèm số lượng cần, số lượng hiện có, đơn vị và tên kho. Đơn hàng giữ nguyên trạng thái `CONFIRMED`.
6. **Đảm bảo tính Nguyên tử (Atomic Transaction) & Chống trừ trùng (Idempotency):**
   - Kiểm tra tồn kho, trừ tồn, tạo phiếu xuất `KITCHEN_USAGE`, ghi dấu đơn đã khấu trừ vào `order_recipe_deductions`, cập nhật trạng thái đơn sang `PREPARING` và tạo bản ghi lịch sử trạng thái trong **1 Database Transaction duy nhất**.
   - Bảng `order_recipe_deductions` với khóa duy nhất `orderId` ngăn chặn việc khấu trừ 2 lần nếu yêu cầu bị gửi lặp lại.
7. **Chính sách khi Hủy đơn sau chế biến:**
   - Nếu đơn hàng bị hủy sau khi đã chuyển sang `PREPARING` (hoặc các trạng thái tiếp theo), hệ thống **KHÔNG tự động hoàn kho**, vì nguyên liệu có thể đã được cắt gọt/chế biến. Nhân viên quản lý kho sẽ kiểm kê thực tế và lập phiếu nhập/điều chỉnh thủ công nếu cần.

---

## 2. Thiết Kế Cơ Sở Dữ Liệu (Prisma Schema)

### 2.1. Cập nhật Schema `ordering`
Mỗi chi nhánh gắn 1 kho:
```prisma
model Branch {
  // ... existing fields ...
  warehouseId String?    @map("warehouse_id") @db.Uuid
  warehouse   Warehouse? @relation(fields: [warehouseId], references: [id])
}
```

### 2.2. Mở rộng Schema `inventory`
```prisma
model Warehouse {
  id        String   @id @default(uuid()) @db.Uuid
  code      String   @unique @db.VarChar(50)
  name      String   @db.VarChar(160)
  address   String?  @db.Text
  isActive  Boolean  @default(true) @map("is_active")
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  branches     Branch[]
  stocks       WarehouseStock[]
  transactions InventoryTransaction[]

  @@map("warehouses")
  @@schema("inventory")
}

model WarehouseStock {
  id           String     @id @default(uuid()) @db.Uuid
  warehouseId  String     @map("warehouse_id") @db.Uuid
  warehouse    Warehouse  @relation(fields: [warehouseId], references: [id], onDelete: Cascade)
  ingredientId String     @map("ingredient_id") @db.Uuid
  ingredient   Ingredient @relation(fields: [ingredientId], references: [id], onDelete: Cascade)
  currentStock Decimal    @default(0) @map("current_stock") @db.Decimal(18, 3)
  minStock     Decimal    @default(0) @map("min_stock") @db.Decimal(18, 3)
  createdAt    DateTime   @default(now()) @map("created_at")
  updatedAt    DateTime   @updatedAt @map("updated_at")

  @@unique([warehouseId, ingredientId])
  @@index([warehouseId])
  @@index([ingredientId])
  @@map("warehouse_stocks")
  @@schema("inventory")
}

model Recipe {
  id        String       @id @default(uuid()) @db.Uuid
  productId String       @unique @map("product_id") @db.Uuid
  notes     String?      @db.Text
  isActive  Boolean      @default(true) @map("is_active")
  createdAt DateTime     @default(now()) @map("created_at")
  updatedAt DateTime     @updatedAt @map("updated_at")

  items     RecipeItem[]

  @@map("recipes")
  @@schema("inventory")
}

model RecipeItem {
  id           String     @id @default(uuid()) @db.Uuid
  recipeId     String     @map("recipe_id") @db.Uuid
  recipe       Recipe     @relation(fields: [recipeId], references: [id], onDelete: Cascade)
  ingredientId String     @map("ingredient_id") @db.Uuid
  ingredient   Ingredient @relation(fields: [ingredientId], references: [id])
  quantity     Decimal    @db.Decimal(18, 3) // Định mức cho 1 phần món

  @@unique([recipeId, ingredientId])
  @@map("recipe_items")
  @@schema("inventory")
}

model OrderRecipeDeduction {
  id          String   @id @default(uuid()) @db.Uuid
  orderId     String   @unique @map("order_id") @db.Uuid
  orderCode   String   @map("order_code") @db.VarChar(50)
  warehouseId String   @map("warehouse_id") @db.Uuid
  createdAt   DateTime @default(now()) @map("created_at")

  @@map("order_recipe_deductions")
  @@schema("inventory")
}
```

Và cập nhật `InventoryTransaction`:
- Thêm `warehouseId String? @map("warehouse_id") @db.Uuid`
- Thêm `orderId String? @map("order_id") @db.Uuid`
- Thêm quan hệ tới `Warehouse`

---

## 3. Kiến Trúc Khấu Trừ Trong Transaction Duy Nhất

Khi gọi `PATCH /orders/:id/status` với `status: PREPARING`:
1. Kiểm tra trạng thái hiện tại của Order:
   - Nếu `status !== 'CONFIRMED'`: throw `BadRequestException('Đơn hàng cần được Xác nhận (CONFIRMED) trước khi bắt đầu chế biến.')`.
2. Lấy thông tin `Branch` của đơn hàng và `branch.warehouseId`:
   - Nếu chi nhánh chưa được gán kho: throw `BadRequestException('Chi nhánh phục vụ đơn hàng chưa được cấu hình Kho nguyên vật liệu.')`.
3. Phân rã giỏ hàng (`order_items`):
   - Món `SINGLE`: số lượng món $\times$ định mức từng nguyên liệu trong `Recipe`.
   - Món `COMBO`: duyệt các món con trong `combo_items`, nhân số lượng combo $\times$ số lượng con $\times$ định mức món con.
   - Cộng dồn thành danh sách tổng nguyên liệu cần dùng: `Map<ingredientId, Decimal>`.
4. Bắt đầu PostgreSQL Transaction:
   - Khóa các dòng `WarehouseStock` tương ứng bằng `FOR UPDATE` (sắp xếp theo `ingredientId` tăng dần để tránh deadlock).
   - Kiểm tra tồn kho của từng nguyên liệu: nếu có nguyên liệu thiếu, rollback và throw `BadRequestException` kèm chi tiết `insufficientIngredients`.
   - Trừ `currentStock` tại `WarehouseStock`.
   - Tạo các bản ghi `InventoryTransaction` (loại `OUT`, lý do `KITCHEN_USAGE`, gắn `warehouseId`, `orderId`).
   - Ghi bản ghi `OrderRecipeDeduction`.
   - Cập nhật Order sang `PREPARING` và tạo `OrderStatusHistory`.
   - Tạo `OutboxEvent` cho realtime event.
5. Sau commit: Publish sự kiện RabbitMQ.
