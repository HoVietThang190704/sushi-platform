# Chuyển Đổi Mô Hình Đặt Món: Giao Hàng Tận Nơi TP.HCM & Bảng Cấu Hình Phí Ship

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển đổi toàn diện nền tảng từ mô hình nhận tại quầy (Take Away) sang mô hình giao hàng tận nơi (Delivery) tại TP.HCM: khách chọn Xã/Phường qua dropdown, nhập địa chỉ chi tiết, hệ thống tự động gán chi nhánh phục vụ và tính phí ship theo cấu hình của Admin, hỗ trợ thanh toán VietQR & COD, đồng bộ luồng trạng thái đơn hàng (Đã xác nhận -> Đang chế biến -> Chờ giao -> Đang giao -> Đã giao).

**Architecture:** 
1. Database (Prisma): Thêm model `Branch` (danh sách chi nhánh), model `ShippingRule` (cấu hình phí ship theo branchId x ward/district, cờ isDefault), bổ sung trường `shippingFee` vào `Order` và cập nhật enum `OrderStatus` với các trạng thái giao hàng (`DELIVERING`, `DELIVERED`).
2. Backend (Ordering Service & Gateway): API quản lý cấu hình phí ship cho Admin; API public lấy danh sách xã/phường & tính phí ship cho Storefront; bảo đảm tính toàn vẹn giá (backend tính lại phí ship và tổng tiền từ database, không tin client).
3. Admin Web: Thêm trang cấu hình phí giao hàng (Quản lý chi nhánh, danh sách xã/phường, mức phí, chi nhánh mặc định); cập nhật màn hình quản lý đơn hàng theo luồng giao hàng và hiển thị địa chỉ chi tiết + phí ship.
4. Storefront: Cập nhật giao diện Checkout Bước 1 (Dropdown Phường/Xã TP.HCM + Ô nhập số nhà/đường + Chọn chi nhánh nếu có nhiều chi nhánh hỗ trợ), Bước 2 (Phí ship minh bạch, Tổng tiền = Món + Phí ship, COD / VietQR); trang Tracking & Success hiển thị địa chỉ giao và trạng thái giao hàng.

**Tech Stack:** NestJS, Prisma ORM, PostgreSQL, Next.js 16 (App Router), Tailwind CSS, Socket.IO, Lucide Icons, Sonner.

**Spec:** In-chat consensus approved on 2026-11-07.

## Global Constraints
- Tất cả địa chỉ giao hàng giới hạn trong phạm vi TP.HCM.
- Xã/phường chưa có chi nhánh cấu hình giao hàng vẫn hiển thị trên dropdown nhưng gắn nhãn "Chưa hỗ trợ giao hàng" và chặn không cho đặt đơn.
- Khách không thể tự nhập mức phí ship; Backend bắt buộc tính lại `shippingFee` và `totalAmount` từ database.
- Giữ vững 2 phương thức thanh toán: Chuyển khoản VietQR và Tiền mặt khi nhận hàng (COD).
- Mọi thay đổi code frontend mobile phải đáp ứng chuẩn ngón tay bấm, không tạo thanh cuộn ngang ngoài ý muốn (`overflow-x-clip`).

## Review Focus
1. Đơn hàng gửi lên phường/xã chưa được cấu hình phí ship -> Backend ném lỗi BadRequestException rõ ràng, không tạo đơn rác.
2. Đơn hàng có client gửi `shippingFee` giả mạo -> Backend ghi đè hoàn toàn bằng phí tra cứu từ `ShippingRule`.
3. Khách đổi phường/xã trên Storefront -> Tự động cập nhật lại chi nhánh mặc định, phí ship và tổng tiền tức thì.
4. Cấu hình phí ship của Admin thay đổi sau khi đơn đã đặt -> Không làm thay đổi `shippingFee` và `totalAmount` của các đơn đã tạo trong quá khứ (đã snapshot vào Order).
5. Màn hình Tracking đơn hàng -> Hiển thị chuẩn xác địa chỉ giao hàng và huy hiệu trạng thái giao hàng mới.

---

### Task 1: Thiết Kế Schema Cơ Sở Dữ Liệu & Migration

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Modify: `apps/api/prisma/seed.ts` (nếu có) hoặc tạo script seed dữ liệu mẫu TP.HCM

**Interfaces:**
- Consumes: Prisma schema hiện tại (model `Order`, enum `OrderStatus`)
- Produces: 
  - `model Branch`: `id`, `name`, `code`, `address`, `phone`, `isActive`
  - `model ShippingRule`: `id`, `branchId`, `province`, `district`, `ward`, `fee`, `isDefault`, `isActive`
  - `Order.shippingFee Decimal @default(0)`
  - `enum OrderStatus`: `PENDING`, `CONFIRMED`, `PREPARING`, `READY_FOR_PICKUP`, `DELIVERING`, `COMPLETED`, `CANCELLED`

- [ ] **Step 1: Viết cập nhật Prisma schema**
Bổ sung model `Branch`, `ShippingRule`, trường `shippingFee` và cập nhật enum `OrderStatus`.

- [ ] **Step 2: Chạy migration hoặc prisma db push / generate**
Run: `pnpm --filter @sushi/api prisma generate`
Expected: Prisma Client generate thành công với các model và type mới.

- [ ] **Step 3: Tạo seed data danh sách Quận/Huyện, Phường/Xã TP.HCM và chi nhánh mặc định**
Thêm chi nhánh trung tâm Hanbi Sushi Quận 1, Quận 3, Bình Thạnh kèm mức phí ship mẫu (ví dụ: Q1: 15.000đ, Q3: 20.000đ, Bình Thạnh: 25.000đ, Thủ Đức: 35.000đ).

- [ ] **Step 4: Chạy seed và kiểm tra dữ liệu**
Run: `pnpm --filter @sushi/api ts-node prisma/seed.ts` (hoặc script tương ứng).
Expected: Dữ liệu chi nhánh và bảng phí giao hàng được nạp vào DB.

- [ ] **Step 5: Commit**
```bash
git add apps/api/prisma/
git commit -m "feat(api): add Branch, ShippingRule and update Order status for delivery"
```

---

### Task 2: Backend APIs - Quản Lý Phí Ship & Tính Phí Đơn Hàng

**Files:**
- Create: `apps/api/apps/ordering-service/src/shipping/shipping.service.ts`
- Create: `apps/api/apps/ordering-service/src/shipping/shipping.controller.ts`
- Create: `apps/api/apps/ordering-service/src/shipping/dto/shipping-rule.dto.ts`
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts`
- Modify: `apps/api/apps/ordering-service/src/dto/create-order.dto.ts`
- Modify: `apps/api/apps/api-gateway/src/controllers/ordering.controller.ts`

**Interfaces:**
- Consumes: `ShippingRule`, `Branch`, `Order`
- Produces:
  - `GET /api/v1/shipping/locations`: Danh sách phường/xã TP.HCM kèm tình trạng hỗ trợ và chi nhánh phục vụ
  - `GET /api/v1/shipping/calculate?ward=...&district=...&branchId=...`: Tính phí ship cho địa chỉ đã chọn
  - `POST /api/v1/shipping/rules`: CRUD bảng phí ship cho Admin
  - `POST /api/v1/orders`: Tự động tra cứu `ShippingRule`, cộng `shippingFee` vào `totalAmount`

- [ ] **Step 1: Viết test cho tính phí ship và tạo đơn giao hàng**
Viết unit test cho `ShippingService` và `OrderingService.createOrder` với trường hợp có phí ship, địa chỉ không hỗ trợ, địa chỉ hợp lệ.

- [ ] **Step 2: Chạy test để xác nhận fail**
Run: `pnpm --filter @sushi/api test apps/ordering-service`
Expected: Fail do chưa có code triển khai.

- [ ] **Step 3: Cài đặt ShippingService và ShippingController**
Triển khai logic truy vấn danh sách phường/xã, lấy chi nhánh mặc định và tính toán mức phí ship chuẩn xác.

- [ ] **Step 4: Cập nhật OrderingService.createOrder**
Xác thực địa chỉ giao hàng (`address`, `district`, `ward`), lấy `ShippingRule` hợp lệ, gán `order.shippingFee` và `totalAmount = calculatedTotal + shippingFee`.

- [ ] **Step 5: Chạy test kiểm tra pass**
Run: `pnpm --filter @sushi/api test apps/ordering-service`
Expected: All tests pass.

- [ ] **Step 6: Commit**
```bash
git add apps/api/apps/ordering-service/ apps/api/apps/api-gateway/
git commit -m "feat(api): implement shipping calculation and delivery order logic"
```

---

### Task 3: Storefront UI - Tích Hợp Địa Chỉ Giao Hàng & Phí Ship Vào Checkout

**Files:**
- Create: `apps/storefront/src/config/hcm-locations.config.ts` (hoặc hook fetch từ API)
- Modify: `apps/storefront/src/components/checkout/checkout-view.tsx`
- Modify: `apps/storefront/src/lib/api.ts`

**Interfaces:**
- Consumes: `GET /api/v1/shipping/locations`, `GET /api/v1/shipping/calculate`
- Produces: Form chọn Phường/Xã (Dropdown) + Số nhà/Đường + Hiển thị Phí Ship & Tổng tiền + Đặt đơn gửi thông tin giao hàng

- [ ] **Step 1: Cập nhật hàm gọi API `createOrder` và API tra cứu phí ship trong `api.ts`**
Thêm kiểu dữ liệu `district`, `ward`, `address`, `shippingFee` vào interface `CreateOrderInput`.

- [ ] **Step 2: Nâng cấp Bước 1 Checkout (Nhập thông tin người nhận & Địa chỉ)**
  - Thay thế khái niệm "Nhận tại quầy" thành "Giao hàng tận nơi (TP.HCM)".
  - Thêm Dropdown chọn Quận/Huyện và Xã/Phường TP.HCM.
  - Thêm ô nhập "Số nhà, tên đường, số phòng/tòa nhà".
  - Tự động hiển thị chi nhánh giao hàng được chọn và thông báo nếu xã/phường đó chưa được hỗ trợ.

- [ ] **Step 3: Nâng cấp Bước 2 Checkout (Xác nhận & Thanh toán)**
  - Hiển thị chi tiết tiền món, phí giao hàng, và tổng thanh toán.
  - Đổi lựa chọn thanh toán: "Chuyển khoản VietQR" và "Thanh toán khi nhận hàng (COD)".
  - Nút bấm xác nhận hiển thị tổng tiền đã gồm phí ship.

- [ ] **Step 4: Kiểm tra build Storefront**
Run: `pnpm --filter @sushi/storefront build`
Expected: Build thành công không có lỗi type.

- [ ] **Step 5: Commit**
```bash
git add apps/storefront/src/components/checkout/ apps/storefront/src/lib/api.ts
git commit -m "feat(storefront): integrate delivery address and shipping fee calculation into checkout"
```

---

### Task 4: Storefront UI - Đồng Bộ Trang Order Success, Tracking & Dọn Dẹp Từ Khóa "Take Away"

**Files:**
- Modify: `apps/storefront/src/components/order-success/order-success-view.tsx`
- Modify: `apps/storefront/src/components/track-order/track-order-view.tsx`
- Modify: `apps/storefront/src/components/cart/cart-view.tsx`
- Modify: `apps/storefront/src/components/menu/menu-view.tsx`
- Modify: `apps/storefront/src/config/site.config.ts`

**Interfaces:**
- Consumes: Dữ liệu đơn hàng có `address`, `district`, `ward`, `shippingFee`, status mới (`DELIVERING`, `DELIVERED`/`COMPLETED`)
- Produces: Giao diện hiển thị địa chỉ giao hàng, tiến trình 5 bước giao hàng trực quan, nhãn thanh toán COD.

- [ ] **Step 1: Cập nhật OrderSuccessView**
Thay thế "Hướng dẫn nhận tại quầy" thành "Thông tin giao hàng tận nơi": Đơn hàng sẽ được chuyển đến địa chỉ của bạn ngay sau khi chế biến.

- [ ] **Step 2: Cập nhật TrackOrderView**
  - Cập nhật tiến trình: Đã nhận -> Chế biến -> Đóng gói -> Đang giao -> Đã giao.
  - Cột thông tin: Hiển thị đầy đủ Người nhận, Số điện thoại, Địa chỉ giao hàng chi tiết, Phí ship và Tiền món.

- [ ] **Step 3: Dọn dẹp từ khóa "Take Away" trên Storefront**
Chuyển đổi các thông điệp sang "Giao hàng tận nơi / Đặt món Online" trên Giỏ hàng, Menu và Site Config.

- [ ] **Step 4: Kiểm tra build Storefront**
Run: `pnpm --filter @sushi/storefront build`
Expected: Build pass 100%.

- [ ] **Step 5: Commit**
```bash
git add apps/storefront/
git commit -m "feat(storefront): update tracking and success pages for delivery fulfillment"
```

---

### Task 5: Admin Web - Quản Lý Bảng Cấu Hình Phí Ship & Xử Lý Đơn Giao Hàng

**Files:**
- Create: `apps/admin-web/src/app/(dashboard)/dashboard/shipping/page.tsx`
- Create: `apps/admin-web/src/features/shipping/` (components, api, types)
- Modify: `apps/admin-web/src/config/navigation.config.ts`
- Modify: `apps/admin-web/src/features/orders/components/order-detail-modal.tsx` (hoặc view chi tiết đơn)
- Modify: `apps/admin-web/src/features/orders/types.ts`
- Modify: `apps/admin-web/src/features/orders/components/order-status-badge.tsx`

**Interfaces:**
- Consumes: API Shipping Rules (`/api/v1/shipping/*`), Orders API
- Produces: 
  - Màn hình cấu hình phí ship: Thêm/Sửa mức phí theo từng Xã/Phường, chọn Chi nhánh mặc định.
  - Màn hình đơn hàng: Hiển thị địa chỉ giao hàng, phí ship, đổi trạng thái đơn sang "Đang giao hàng" và "Đã giao hàng".

- [ ] **Step 1: Tạo Feature Module Shipping trên Admin Web**
Xây dựng giao diện bảng quản lý phí ship: bộ lọc theo Quận/Huyện, bảng danh sách Phường/Xã, mức phí (VND), chi nhánh phục vụ và trạng thái hoạt động.

- [ ] **Step 2: Thêm mục "Cấu hình giao hàng" vào Sidebar Admin**
Cập nhật `navigation.config.ts` với icon và route `/dashboard/shipping`.

- [ ] **Step 3: Cập nhật luồng xử lý đơn hàng phía Admin**
Thêm trạng thái `DELIVERING` (Đang giao hàng) vào `order-status-badge.tsx` và popup đổi trạng thái đơn hàng. Hiển thị địa chỉ khách hàng nhận món rõ ràng trên chi tiết đơn.

- [ ] **Step 4: Kiểm tra build Admin Web**
Run: `pnpm --filter @sushi/admin-web build`
Expected: Build pass 100%.

- [ ] **Step 5: Commit**
```bash
git add apps/admin-web/
git commit -m "feat(admin): add shipping rules configuration and update delivery order status management"
```

---

### Task 6: Kiểm Thử Toàn Diện & Xác Minh Trực Tiếp

**Files:** Toàn bộ hệ thống (`apps/api`, `apps/storefront`, `apps/admin-web`)

- [ ] **Step 1: Chạy toàn bộ Unit Tests**
Run: `pnpm --filter @sushi/api test`
Expected: Tất cả các bài test API vượt qua.

- [ ] **Step 2: Chạy Build Production toàn bộ workspace**
Run: `pnpm build`
Expected: API, Storefront và Admin-web đều compile thành công.

- [ ] **Step 3: Xác minh luồng end-to-end**
  1. Admin cấu hình phí ship cho Phường Bến Nghé, Quận 1: 20.000đ.
  2. Khách vào Storefront đặt món, chọn Phường Bến Nghé, nhập số nhà -> Phí ship 20.000đ được cộng vào tổng tiền.
  3. Khách chọn COD và ấn "Xác nhận Đặt hàng".
  4. Đơn hàng hiển thị trên Admin với đầy đủ địa chỉ giao hàng, tiền món và phí ship.
  5. Admin cập nhật trạng thái sang "Đang giao hàng" -> Storefront realtime cập nhật đúng bước "Đang giao".

- [ ] **Step 4: Commit hoàn tất**
```bash
git commit -m "chore: complete delivery transition with dynamic shipping fee by ward"
```
