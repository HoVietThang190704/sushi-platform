# Storefront Realtime Store Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sau khi admin lưu công tắc hoặc hotline, các tab Storefront đang mở tự cập nhật mà không tải lại trang.

**Architecture:** Ordering-service cập nhật DB rồi phát sự kiện `store-config.updated` qua RabbitMQ; gateway chỉ gửi tín hiệu `store-config:updated` vào room công khai chuyên dụng. Một listener duy nhất trong Storefront làm mới TanStack Query từ REST; kết nối lại, quay lại tab và đồng bộ định kỳ là các đường bù sự kiện thất lạc. REST/API tạo đơn vẫn là nguồn dữ liệu và chốt kiểm soát cuối cùng.

**Tech Stack:** NestJS 11, Socket.IO 4, RabbitMQ, React 19, Next.js 16, TanStack Query 5, Jest (API). Storefront hiện chưa có test runner.

**Spec:** `docs/superpowers/specs/2026-11-14-storefront-realtime-store-config-design.md`

## Global Constraints

- Chỉ socket công khai **không mang bất kỳ token nào** mới được vào `public:store-config`; token không hợp lệ/hết hạn phải bị từ chối, kể cả khi client tự khai là public.
- Socket anonymous không được vào `authenticated`, `role:*`, `branch:*` hay `order:*`; giữ nguyên phạm vi token guest theo dõi đơn.
- Tín hiệu công khai chỉ gồm timestamp/phiên bản, không chứa payload cấu hình hay sự kiện đơn hàng.
- Không thay đổi nghiệp vụ tạo đơn, thanh toán, trừ kho; API vẫn chặn khách đặt khi tắt và vẫn cho nhân viên tạo đơn.
- Đọc hướng dẫn Next.js liên quan tại `apps/storefront/node_modules/next/dist/docs/` trước khi sửa mã Storefront, theo `apps/storefront/AGENTS.md`.
- Không push. `apps/api`, `apps/storefront` và `apps/admin-web` là Git submodule: chạy lệnh trong từng repo, nếu commit thì commit trong submodule trước rồi mới commit gitlink ở root trên `main` local. Không stage thay đổi không thuộc nhiệm vụ.

## File Map

- `apps/api/apps/ordering-service/src/ordering.service.ts` và `.spec.ts`: phát tín hiệu sau cập nhật DB và test tình huống broker hỏng.
- `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts` và `.spec.ts`: phân quyền room công khai và giới hạn kiểu sự kiện được phát vào room.
- `apps/storefront/src/components/providers/store-config-realtime.tsx`: đúng một kết nối/socket listener mỗi tab, cleanup khi unmount.
- `apps/storefront/src/components/providers/query-provider.tsx`: đặt listener bên trong QueryClientProvider (không đặt trong hook dùng ở nhiều component).
- `apps/storefront/src/hooks/use-store-config.ts`: query dùng chung, refetch theo focus và interval.
- `apps/storefront/src/lib/api.ts`: không biến lỗi tải cấu hình thành `null` ghi đè cấu hình đã biết.
- `apps/storefront/package.json` và lockfile tương ứng: chỉ thêm test runner nếu chọn viết automated client test; không tự thêm khi chưa cần.

## Review Focus

1. Một tab render Header + BottomNav + Menu: vẫn chỉ một socket cấu hình (Task 3, kiểm tra browser/network).
2. Client không token nhận tín hiệu cấu hình nhưng không nhận `realtime:event`/`order:updated`; token sai không được hạ cấp thành anonymous (Task 2).
3. Token guest `order_track` vẫn chỉ nhận sự kiện của mã đơn của mình; token admin vẫn nhận sự kiện quản trị (Task 2).
4. Broker `publishEvent()` trả `false`, socket rớt hoặc sự kiện bị lỡ: request lưu vẫn thành công, Storefront hội tụ về trạng thái REST qua reconnect/focus/interval (Tasks 1, 3, 4).
5. REST lỗi tạm thời: Storefront giữ cấu hình cuối cùng đã biết thay vì ghi `null` và bật lại UI đặt món (Task 3); API tiếp tục chặn đơn khi tắt (Task 4).

---

### Task 1: Phát sự kiện sau khi lưu DB

**Files:** `apps/api/apps/ordering-service/src/ordering.service.ts`, `apps/api/apps/ordering-service/src/ordering.service.spec.ts`.

**Interfaces:** Dùng `createRealtimeEvent({ type: 'store-config.updated', resource: 'order', action: 'UPDATED', payload: {} })`; gateway chỉ dựa vào `type` và `timestamp`. `RabbitMQService.publishEvent(event): Promise<boolean>` có thể trả `false` mà không throw.

- [ ] **Step 1: Thêm test đỏ.** Trong `describe` cấu hình cửa hàng hiện có (`ordering.service.spec.ts`), dùng `jest.spyOn(prisma.storeConfig, 'findUnique'/'update')` như test `should update store config when admin provides valid data`. Kiểm tra thứ tự lưu rồi phát, tín hiệu không mang số điện thoại; thêm case `publishEvent.mockResolvedValue(false)` vẫn trả cấu hình đã lưu và `Logger.warn` được gọi; case DB update reject thì `publishEvent` không được gọi.

```typescript
expect(rabbitmqService.publishEvent).toHaveBeenCalledWith(
  expect.objectContaining({
    type: 'store-config.updated', resource: 'order', action: 'UPDATED',
    branchId: null, payload: {},
  }),
);
expect(result.customerOrderingEnabled).toBe(false);
```

- [ ] **Step 2: Chạy test đỏ:** trong `apps/api`, `pnpm exec jest --runInBand ordering.service.spec.ts`. Xác nhận test mới fail do chưa publish.
- [ ] **Step 3: Sửa tối thiểu:** giữ nguyên data object của lệnh `storeConfig.update` hiện có, chỉ thay `return this.prisma.storeConfig.update(...)` bằng `const updated = await this.prisma.storeConfig.update(...)` và đặt đoạn sau trước `return updated`:

```typescript
try {
  const published = await this.rabbitmqService.publishEvent(
    createRealtimeEvent({
      type: 'store-config.updated', resource: 'order', action: 'UPDATED', payload: {},
    }),
  );
  if (!published) this.logger.warn('Failed to publish store-config.updated event');
} catch (error) {
  this.logger.warn(`Failed to publish store-config.updated event: ${String(error)}`);
}
return updated;
```

- [ ] **Step 4: Chạy lại:** trong `apps/api`, `pnpm exec jest --runInBand ordering.service.spec.ts`; các test cũ và mới đều pass.

### Task 2: Cô lập kênh công khai tại gateway

**Files:** `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`, `apps/api/apps/api-gateway/src/realtime/realtime.gateway.spec.ts`.

**Interfaces:** `REALTIME_ROOMS.PUBLIC_STORE_CONFIG = 'public:store-config'`; event Socket.IO `store-config:updated` có `{ timestamp: string }` (tín hiệu, không dữ liệu cấu hình).

- [ ] **Step 1: Thêm test đỏ vào suite có sẵn.** Thay test `should disconnect client when token is missing` bằng test `join` duy nhất room public; giữ test bad-token; thêm test trường hợp `auth.isPublic` kèm bad token vẫn disconnect; giữ test guest tracking `order:CODE` không bị thêm room khác; test broadcast sự kiện đúng room chỉ mang timestamp, và order event không bao giờ phát tới room public.

```typescript
expect(client.join).toHaveBeenCalledWith(REALTIME_ROOMS.PUBLIC_STORE_CONFIG);
expect(client.join).not.toHaveBeenCalledWith(REALTIME_ROOMS.AUTHENTICATED);
expect(client.join).not.toHaveBeenCalledWith(expect.stringMatching(/^(role:|branch:|order:)/));
expect(mockServer.emit).toHaveBeenCalledWith('store-config:updated', {
  timestamp: '2026-11-14T10:00:00.000Z',
});
```

- [ ] **Step 2: Chạy test đỏ:** trong `apps/api`, `pnpm exec jest --runInBand realtime.gateway.spec.ts`.
- [ ] **Step 3: Sửa tối thiểu:** giữ `extractToken()` và nhánh JWT hiện có; chỉ khi `!token` join `PUBLIC_STORE_CONFIG` rồi `return` **trước** nhánh authenticated. Không tin cờ `isPublic` để bỏ qua JWT. Nhánh guest track giữ nguyên `return` chỉ sau khi join order room. Với event `type === 'store-config.updated'`, `server.to(PUBLIC_STORE_CONFIG).emit('store-config:updated', { timestamp: event.timestamp })`; các event còn lại chỉ vào room vốn có. Duy trì `realtime:event` cho admin như hiện tại, không emit nó vào public room.
- [ ] **Step 4: Chạy lại:** trong `apps/api`, `pnpm exec jest --runInBand realtime.gateway.spec.ts`; kiểm tra test về branch/admin/guest vẫn xanh.

### Task 3: Một listener cho toàn Storefront, REST là nguồn dữ liệu

**Files:** tạo `apps/storefront/src/components/providers/store-config-realtime.tsx`; sửa `apps/storefront/src/components/providers/query-provider.tsx`, `apps/storefront/src/hooks/use-store-config.ts`, `apps/storefront/src/lib/api.ts`.

**Interfaces:** `StoreConfigRealtime` dùng `useQueryClient()` và `storeConfigKey`; không tự đọc query, chỉ invalidate/refetch; toàn bộ UI tiếp tục dùng `useStoreConfig()` hiện có.

- [ ] **Step 1: Xác minh hướng dẫn Next.js:** đọc guide `node_modules/next/dist/docs/` liên quan client components/provider từ thư mục `apps/storefront` trước khi đổi mã; không đổi layout server nếu không cần.
- [ ] **Step 2: Viết tiêu chí kiểm chứng trước khi sửa:** tạo ca browser hai tab có Header + BottomNav + Menu; Network chỉ thấy 1 socket `/realtime` cho cấu hình trên mỗi tab; một event gây một lần invalidate/fetch (deduped), UI đổi cả số `tel:`. Đánh dấu đây là kiểm chứng thủ công vì `apps/storefront` hiện không có test runner; nếu cần tự động hóa, bổ sung runner + ca test riêng trong phạm vi Task 3.
- [ ] **Step 3: Sửa truy vấn:** tại `fetchStoreConfig`, nếu HTTP không OK, JSON không hợp lệ hoặc network lỗi thì throw để TanStack Query giữ dữ liệu thành công trước đó (không trả `null` và ghi đè); giữ `cache: 'no-store'`. Trong `useStoreConfig`, đặt `refetchOnWindowFocus: 'always'` và `refetchInterval: 60_000` (chỉ query này, mặc định không poll khi tab nền). Sau khi có lỗi lần đầu mà chưa có dữ liệu, giữ fallback hiện có; API vẫn bảo vệ submit.
- [ ] **Step 4: Sửa listener duy nhất:** render `<StoreConfigRealtime />` đúng một lần bên trong `QueryClientProvider` của `QueryProvider`. Effect tạo `io(`${socketUrl}/realtime`, { withCredentials: false, transports: ['websocket', 'polling'] })`; đăng ký `socket.on('store-config:updated', invalidate)`, `socket.on('connect', invalidate)` (bao gồm lần đầu và reconnect); cleanup bằng `socket.off(...)` và `socket.disconnect()`. Không đặt socket trong `useStoreConfig`, không dùng `setQueryData` từ event. Dùng cấu hình `NEXT_PUBLIC_SOCKET_URL`/fallback như `order-success-view.tsx`; không gửi auth/token.

```typescript
const invalidate = () => {
  void queryClient.invalidateQueries({ queryKey: storeConfigKey });
};
socket.on('store-config:updated', invalidate);
socket.on('connect', invalidate);
return () => {
  socket.off('store-config:updated', invalidate);
  socket.off('connect', invalidate);
  socket.disconnect();
};
```

- [ ] **Step 5: Kiểm tra tĩnh:** trong `apps/storefront`, chạy `pnpm lint` và `pnpm build`; sửa các lỗi do thay đổi mới gây ra. Không sửa các warning tồn tại trước không liên quan.

### Task 4: Kiểm chứng tích hợp và bàn giao

**Files:** không cần thêm mã nếu các ca đã pass.

- [ ] **Step 1: Test/backend build:** trong `apps/api`, chạy `pnpm exec jest --runInBand`, `pnpm build`; kiểm tra cả ordering, gateway, contracts, không mặc định số lượng suite cố định.
- [ ] **Step 2: Browser/runtime:** chạy dịch vụ API + RabbitMQ + admin/storefront theo hướng dẫn repo; mở Storefront chưa đăng nhập và Admin song song. Đổi `true → false → true`, đổi hotline riêng, xác nhận UI và `tel:` đổi không F5; thử tab khác, reload, mất/kết nối lại socket, tab nền quay lại. Kiểm tra anonymous không nhận event order/admin bằng Socket.IO client hoặc DevTools. Nếu môi trường không chạy được, báo rõ ca nào chưa xác minh; không gọi build là E2E.
- [ ] **Step 3: Git:** nếu được yêu cầu commit, commit các file thay đổi trong `apps/api` và `apps/storefront` trên `main` local, rồi cập nhật gitlink ở repo root cùng tài liệu; kiểm tra `git status --short` tại từng repo và root; không push.

## Self-review khi thực hiện

- Task 1 test riêng nhánh `publishEvent() === false`, vì RabbitMQService trả `false` thay vì throw.
- Task 2 test quyền socket anonymous, token sai và guest tracking; không thêm anonymous vào phòng admin/order.
- Task 3 socket một lần mỗi tab; REST không làm mất dữ liệu cũ khi lỗi; fallback interval 60 giây không thay thế realtime.
- Task 4 phân biệt test tự động, build và kiểm chứng browser thật; không cam kết 17 suites khi số test thay đổi.
