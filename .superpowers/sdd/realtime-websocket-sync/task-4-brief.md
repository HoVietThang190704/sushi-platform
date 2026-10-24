### Task 4: Admin Web Socket Client & TanStack Query Invalidation Provider
**Files:**
- Modify: `apps/admin-web/package.json` (thêm `socket.io-client`)
- Create: `apps/admin-web/src/providers/realtime-provider.tsx`
- Modify: `apps/admin-web/src/app/(dashboard)/layout.tsx`
- Test: `apps/admin-web/src/providers/realtime-provider.spec.tsx` hoặc lint/typecheck verify

**Interfaces:**
- Consumes: Socket.IO event `realtime:event` từ Gateway namespace `/realtime`
- Produces: Auto query invalidation:
  - `resource === 'inventory'` -> `queryClient.invalidateQueries({ queryKey: inventoryKeys.all })`
  - `resource === 'catalog'` -> `queryClient.invalidateQueries({ queryKey: catalogKeys.all })`

**Constraints:**
- Socket Connection URL: Sử dụng `process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3000'`, namespace `/realtime`.
- Credentials: `withCredentials: true` (để gửi cookie `access_token` tự động).
- Connection Lifecycle: Chỉ khởi tạo kết nối khi `isAuthenticated === true`. Khi user logout hoặc unmount -> `socket.disconnect()`.
- Reconnect Resilience: Khi bắt sự kiện `connect` (sau khi reconnect), tự động gọi `queryClient.invalidateQueries()` các query đang active để bù đắp các event bị bỏ lỡ lúc mất mạng.
- Strict Local: Không git push.
