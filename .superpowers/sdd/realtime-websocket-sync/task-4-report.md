# Task 4 Report: Admin Web Socket Client & TanStack Query Invalidation Provider

## Trạng thái
**DONE**

## Chi tiết công việc thực hiện

### 1. Cài đặt dependency `socket.io-client`
- Đã cài đặt `socket.io-client@^4.8.4` vào `apps/admin-web/package.json` và cập nhật `pnpm-lock.yaml`.

### 2. Các file đã tạo & chỉnh sửa

#### File tạo mới:
1. `apps/admin-web/src/providers/realtime-provider.tsx`
   - Client component (`'use client'`).
   - Import `io, Socket` từ `socket.io-client`.
   - Import `useQueryClient` từ `@tanstack/react-query`.
   - Import `useAuth` từ `@/features/auth`.
   - Import `inventoryKeys` từ `@/features/inventory/hooks/use-inventory`.
   - Import `catalogKeys` từ `@/features/catalog/hooks/use-categories`.
   - Interface `RealtimeContextType { isConnected: boolean; lastEvent: unknown | null }`.
   - Cung cấp Context `RealtimeContext` và hook `useRealtime()`.
   - Trong `RealtimeProvider`:
     - Kiểm tra `isAuthenticated` từ `useAuth()`. Nếu chưa đăng nhập, không khởi tạo kết nối socket.
     - Khi `isAuthenticated === true`:
       - Kết nối tới `${process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3000'}/realtime`.
       - Cấu hình options: `withCredentials: true` (tự động đính kèm cookie `access_token`), `transports: ['websocket', 'polling']`, `autoConnect: true`.
       - Lắng nghe sự kiện `connect`: Cập nhật `isConnected = true` và gọi `queryClient.invalidateQueries({ refetchType: 'active' })` để chủ động làm mới toàn bộ dữ liệu active trên màn hình khi kết nối/tái kết nối.
       - Lắng nghe sự kiện `disconnect`: Cập nhật `isConnected = false`.
       - Lắng nghe sự kiện `realtime:event`:
         - Nếu `event.resource === 'inventory'`: Tự động gọi `queryClient.invalidateQueries({ queryKey: inventoryKeys.all })`.
         - Nếu `event.resource === 'catalog'`: Tự động gọi `queryClient.invalidateQueries({ queryKey: catalogKeys.all })`.
         - Cập nhật `lastEvent = event`.
       - Cleanup function của `useEffect`: Gọi `socket.disconnect()` để tránh rò rỉ kết nối socket khi unmount hoặc logout.

#### File chỉnh sửa:
2. `apps/admin-web/src/app/(dashboard)/layout.tsx`
   - Import `RealtimeProvider` từ `@/providers/realtime-provider`.
   - Tích hợp `RealtimeProvider` bên trong `AuthProvider` và bọc quanh `DashboardLayoutContent`.

3. `apps/admin-web/package.json` & `apps/admin-web/pnpm-lock.yaml`
   - Bổ sung dependency `socket.io-client@^4.8.4`.

### 3. Kết quả kiểm tra
- **Lint Check:**
  - `npx eslint src/providers/realtime-provider.tsx "src/app/(dashboard)/layout.tsx"`: 0 errors, 0 warnings.
- **Type Check & Build:**
  - `npx tsc --noEmit`: Hoàn thành sạch sẽ, không có lỗi type nào.
  - `next build`: Biên dịch Turbopack thành công (`Compiled successfully in 2.8s`, `Finished TypeScript in 4.2s`, `Generating static pages (9/9)`).

### 4. Git Commit Hash
- **admin-web submodule:** `30cda22` (`feat(realtime): integrate RealtimeProvider and query invalidation in admin-web`)
- **root repository:** `26c8fcc` (`feat(realtime): integrate RealtimeProvider and query invalidation in admin-web`)
- **Strict Local Constraint:** TUYỆT ĐỐI KHÔNG CHẠY GIT PUSH.
