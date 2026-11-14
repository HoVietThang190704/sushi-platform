# Chế độ đặt hàng trên Storefront và Đơn giao hàng qua điện thoại tại Admin

## Mục tiêu và Quyết định đã duyệt

Một storefront duy nhất phục vụ toàn bộ chuỗi nhà hàng, với một cấu hình vận hành chung. Admin có thể bật/tắt khả năng **khách tự đặt hàng qua website** và cập nhật số điện thoại liên hệ của cửa hàng.
- Khi **bật**: Khách đặt món và thanh toán/chuyển khoản bình thường trên Storefront.
- Khi **tắt**: Khách vẫn xem thực đơn, danh mục, chi tiết món nhưng không thể thêm giỏ hay gửi đơn; các nút đặt hàng chuyển thành nút gọi trực tiếp (`tel:`).
- **Admin**: Dù công tắc đặt hàng trên website đang bật hay tắt, nhân viên/admin vẫn có thể **tạo đơn hàng giao tận nơi** cho khách khi nhận cuộc gọi điện thoại, chọn món, chọn chi nhánh phục vụ hợp lệ, hệ thống tự động tính tiền món và phí giao hàng.
- **Tồn kho & Trừ kho**: Giữ nguyên quy tắc bất biến. Chỉ trừ kho khi đơn chuyển sang `CONFIRMED → PREPARING`; món `SINGLE` dùng BOM, món `COMBO` phân rã qua `combo_items`. Số dư seed không phải số tồn đã kiểm kê.

## Phạm vi

- **Trong phạm vi**:
  1. Cấu hình vận hành cửa hàng chung (`StoreConfig` / `StoreSettings`): `customerOrderingEnabled` (boolean, default `true`), `contactPhone` (string).
  2. API quản lý cấu hình: `GET /orders/store-config` (public), `PATCH /orders/store-config` (yêu cầu quyền quản trị).
  3. Phía Admin Web:
     - Thêm trang "Cấu hình cửa hàng" trong nhóm Cấu hình của Sidebar.
     - Dọn dẹp các mục placeholder tĩnh trong Dropdown User (loại bỏ nút "Cài đặt hệ thống" gây nhầm lẫn).
     - Thêm giao diện "Tạo đơn giao hàng" tại trang Quản lý đơn hàng (chọn món, số lượng, nhập thông tin người nhận, địa chỉ/phường-xã, chọn chi nhánh phục vụ, tính phí ship và tổng tiền tự động, tạo đơn nguồn `STAFF`).
  4. Phía Storefront:
     - Nhận diện trạng thái `customerOrderingEnabled`. Khi `false`, ẩn các nút thêm giỏ, ẩn giỏ hàng trên header/bottom nav, chuyển thành nút gọi điện thoại trực tiếp (`tel:`). Chặn truy cập `/cart` và `/checkout` (chuyển hướng hoặc báo trạng thái kèm nút gọi).
  5. Phía Backend API:
     - Chặn tạo đơn mới từ khách hàng (`POST /orders`) khi `customerOrderingEnabled = false`.
     - Thêm endpoint tạo đơn nhân viên (`POST /orders/staff` hoặc phân biệt role có xác thực) để admin tạo đơn mọi lúc.
     - Ghi nhận trường `source` (`STOREFRONT` hoặc `STAFF`) và người tạo đơn trong lịch sử.

- **Ngoài phạm vi**:
  - Không cấu hình theo từng chi nhánh riêng biệt (chỉ dùng 1 cấu hình chung cho storefront).
  - Không xây form để khách để lại số điện thoại (khách bấm gọi trực tiếp).
  - Không tích hợp Zalo hay thanh toán trực tuyến.
  - Không thay đổi nghiệp vụ trừ kho BOM.

## Kiến trúc & Luồng dữ liệu

```
[Admin Web]
   │
   ├──> PATCH /api/orders/store-config (Bật/tắt đặt hàng, cập nhật SĐT)
   │
   └──> POST /api/orders/staff (Tạo đơn giao hàng qua điện thoại, nguồn STAFF)
           │
           ▼
[Ordering Service] ───> Lưu DB (StoreConfig, Order source=STAFF, Status=PENDING)
           ▲
           │
[Storefront] ───> GET /api/orders/store-config
   │                 ├──> true: Hiện giỏ hàng, cho đặt món
   │                 └──> false: Ẩn giỏ, hiện nút "Gọi cửa hàng (tel:...)"
   │
   └───> POST /api/orders (Nguồn STOREFRONT -> Nếu customerOrderingEnabled=false: 400 Bad Request)
```
