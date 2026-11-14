# Cập nhật cấu hình cửa hàng thời gian thực (Realtime Store Config) giữa Admin và Storefront

## Mục tiêu

Khi Admin bật/tắt chế độ tự đặt hàng hoặc cập nhật số điện thoại Hotline trong Admin Web, tất cả các tab Storefront của khách hàng đang mở sẽ tự động cập nhật trạng thái hiển thị ngay lập tức (realtime) mà **không cần khách phải tải lại trang (reload)**.

## Bối cảnh và vấn đề hiện tại

1. **Hiện trạng Storefront:**
   - Hook `useStoreConfig` dùng TanStack Query với `staleTime: 60 * 1000` (1 phút) và `refetchOnWindowFocus: false`.
   - TanStack Query khi hết `staleTime` **không tự động gọi lại API** trừ khi có thao tác re-render / mount lại observer hoặc có trigger refetch chủ động.
   - Khi Admin thay đổi công tắc hoặc hotline tại `/orders/settings`, chỉ có `queryClient` trong trình duyệt Admin được invalidate, tab Storefront của khách hàng hoàn toàn không nhận được tín hiệu. Khách đang mở tab phải nhấn F5 / reload trang mới thấy thay đổi.
2. **Kênh WebSocket hiện tại:**
   - Kênh WebSocket `/realtime` tại API Gateway yêu cầu JWT token hợp lệ trong handshake (`handleConnection`). Nếu không có token, kết nối bị từ chối và ngắt ngay (`client.disconnect()`).
   - Khách vãng lai xem thực đơn Storefront chưa đăng nhập nên không có JWT token để kết nối vào `/realtime`.

## Nguyên tắc thiết kế & An toàn

1. **Bảo mật phân quyền trên WebSocket (Least Privilege):**
   - Khách chưa đăng nhập (anonymous) được phép kết nối vào `/realtime` nhưng **chỉ được join duy nhất vào phòng công khai `public:store-config`**.
   - Socket anonymous **tuyệt đối không được join** `authenticated`, `role:ADMIN`, `role:SUPER_ADMIN`, `branch:*`, hoặc `order:*`.
   - Tuyệt đối không phát tán bất kỳ sự kiện đơn hàng, trạng thái thanh toán hay dữ liệu nhạy cảm nào vào phòng `public:store-config`.
2. **Tín hiệu nhẹ (Lightweight Notification / Cache Invalidation Trigger):**
   - Sự kiện realtime bắn sang Storefront là sự kiện thông báo: `store-config:updated` mang theo phiên bản hoặc timestamp.
   - Khi nhận được sự kiện, Storefront thực hiện `queryClient.invalidateQueries({ queryKey: storeConfigKey })` (hoặc cập nhật trực tiếp cache query an toàn) để đồng bộ dữ liệu chuẩn qua REST API `GET /api/orders/store-config`.
   - Khi socket kết nối lại (`reconnect`), Storefront tự động kích hoạt refetch để bù các sự kiện có thể bị gián đoạn khi mạng chập chờn.
3. **Tính dự phòng (Fallback & Resilience):**
   - Phía Storefront bổ sung thêm cấu hình `refetchOnWindowFocus: true` riêng cho query `storeConfigKey` (hoặc `refetchInterval: 60000`) để làm lớp phòng vệ dự phòng nếu kết nối WebSocket gặp sự cố mạng hoặc bị chặn bởi firewall/proxy.
   - Backend API vẫn là chốt chặn cuối cùng (Single Source of Truth): nếu khách cố tình gửi request đặt món khi `customerOrderingEnabled = false`, API trả về `400 Bad Request`.

## Luồng dữ liệu (Data Flow)

```
[Admin Web]
   │
   ├──> PATCH /api/orders/store-config
           │
           ▼
   [Ordering Service]
           │
           ├──> Lưu DB (StoreConfig)
           │
           └──> RabbitMQ: Publish RealtimeDomainEvent
                   type: 'store-config.updated'
                   resource: 'order'
                   action: 'UPDATED'
                   branchId: null
                   payload: { customerOrderingEnabled, contactPhone }
                           │
                           ▼
                   [API Gateway - RealtimeConsumerService]
                           │
                           ▼
                   [API Gateway - RealtimeGateway]
                           │
                           ├──> broadcastRealtimeEvent()
                           │       Phát sự kiện `store-config:updated`
                           │       tới room `public:store-config`
                           │
                           ▼ (WebSocket)
                   [Storefront (Các tab đang mở)]
                           │
                           ├──> Nhận sự kiện `store-config:updated`
                           ├──> Invalidate cache `['store-config']`
                           └──> UI tự động cập nhật nút "Chọn món" <-> "Gọi đặt",
                                giỏ hàng, thông báo hotline
```

## Chi tiết các thành phần thay đổi

### 1. Phía Backend API

#### A. `apps/api/apps/ordering-service/src/ordering.service.ts`
- Sau khi `prisma.storeConfig.update` thành công trong hàm `updateStoreConfig`:
  - Gọi `this.rabbitmqService.publishEvent(createRealtimeEvent({ ... }))` với:
    - `type: 'store-config.updated'`
    - `resource: 'order'`
    - `action: 'UPDATED'`
    - `payload: { customerOrderingEnabled: updated.customerOrderingEnabled, contactPhone: updated.contactPhone }`
  - Đảm bảo bọc try/catch log warning nếu publish RabbitMQ thất bại để không làm đứt quãng request HTTP của Admin.

#### B. `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`
- Thêm room hằng số: `PUBLIC_STORE_CONFIG: 'public:store-config'`.
- Điều chỉnh `handleConnection(client: Socket)`:
  - Kiểm tra token:
    - Nếu có token: xác thực JWT bình thường như hiện tại.
    - Nếu **không có token** hoặc token là anonymous client (ví dụ `client.handshake.auth?.isPublic` hoặc không truyền token):
      - Gán `client.data.isPublic = true`.
      - Cho socket join vào `REALTIME_ROOMS.PUBLIC_STORE_CONFIG`.
      - **Không** ngắt kết nối (không gọi `client.disconnect()`).
      - Ghi log client công khai kết nối.
    - Nếu có token nhưng token bị lỗi (hết hạn / sai secret): log warning và ngắt kết nối (`client.disconnect()`).
- Điều chỉnh `broadcastRealtimeEvent(event: RealtimeDomainEvent)`:
  - Nếu `event.type === 'store-config.updated'`:
    - Gửi tới room `REALTIME_ROOMS.PUBLIC_STORE_CONFIG`:
      ```ts
      this.server.to(REALTIME_ROOMS.PUBLIC_STORE_CONFIG).emit('store-config:updated', {
        customerOrderingEnabled: event.payload?.customerOrderingEnabled,
        contactPhone: event.payload?.contactPhone,
        timestamp: event.timestamp || new Date().toISOString(),
      });
      ```
    - Đồng thời vẫn gửi tới các room quản trị (`ADMIN`, `SUPER_ADMIN`) như bình thường.

### 2. Phía Storefront

#### A. `apps/storefront/src/hooks/use-store-config.ts`
- Bổ sung cấu hình query:
  - `refetchOnWindowFocus: true` riêng cho query cấu hình cửa hàng.
- Kết nối tới WebSocket `/realtime` (không cần truyền token, hoặc truyền cờ public):
  - Lắng nghe sự kiện `store-config:updated`.
  - Khi nhận sự kiện: gọi `queryClient.setQueryData(storeConfigKey, ...)` và `queryClient.invalidateQueries({ queryKey: storeConfigKey })`.
  - Lắng nghe sự kiện `reconnect`: tự động `invalidateQueries` để bù trừ mọi cập nhật khi mất kết nối.
  - Quản lý lifecycle kết nối sạch sẽ (dùng singleton socket hoặc effect cleanup đúng chuẩn React 19).

## Tiêu chí nghiệm thu (Verification Criteria)

1. **Khách chưa đăng nhập (Anonymous Socket):**
   - Kết nối tới `/realtime` thành công không bị reject.
   - Chỉ nhận được sự kiện `store-config:updated`, không nhận được sự kiện `order:updated` của đơn khác hay sự kiện nội bộ `realtime:event`.
2. **Khách đang mở tab Storefront:**
   - Mở 2 cửa sổ/tab song song: 1 tab Admin Web (`/orders/settings`), 1 tab Storefront (`/`).
   - Admin gạt tắt công tắc "Cho phép khách tự đặt món trên website" và nhấn "Lưu Cấu Hình Cửa Hàng".
   - Ngay lập tức tab Storefront chuyển nút "Chọn món" thành nút "Gọi đặt" kèm số hotline, giỏ hàng biến mất, không cần nhấn F5.
   - Admin bật lại công tắc và đổi số Hotline -> tab Storefront lập tức hiện lại nút "Chọn món" và icon giỏ hàng.
3. **Chặn đơn backend khi tắt:**
   - Kiểm tra `POST /orders` từ storefront vẫn bị chặn `400 Bad Request` khi `customerOrderingEnabled = false`.
4. **Kiểm thử tự động:**
   - Chạy toàn bộ test suites hiện có của `ordering-service`, `api-gateway` và `contracts` đảm bảo 100% passed.
   - Bổ sung unit test cho sự kiện `store-config.updated` tại `ordering.service.spec.ts` và `realtime.gateway.spec.ts`.
