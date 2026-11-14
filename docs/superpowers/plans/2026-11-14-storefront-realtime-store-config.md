# Storefront Realtime Store Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đồng bộ tức thời cấu hình cửa hàng (trạng thái nhận đơn và hotline) từ Admin Web sang tất cả các tab Storefront đang mở qua WebSocket mà không cần khách tải lại trang.

**Architecture:** Khi Admin lưu cấu hình tại `PATCH /api/orders/store-config`, `ordering-service` cập nhật DB và publish event `store-config.updated` vào RabbitMQ. `api-gateway` nhận event và broadcast tới room công khai `public:store-config`. Storefront duy trì kết nối WebSocket nhẹ tới `/realtime` để nghe sự kiện `store-config:updated`, lập tức cập nhật TanStack Query cache và UI.

**Tech Stack:** NestJS, Socket.IO, RabbitMQ, TanStack Query v5, Next.js 16 (App Router), React 19, TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-14-storefront-realtime-store-config-design.md`

## Global Constraints

- Không làm rò rỉ sự kiện đơn hàng, token hay thông tin nhạy cảm vào room public.
- Kết nối không có token chỉ được phép join room `public:store-config`, không được join `authenticated` hay `role:*`.
- Kết nối có token nhưng sai/hết hạn vẫn phải bị từ chối và ngắt kết nối (`disconnect`).
- Lỗi kết nối hoặc mất WebSocket không được làm sập giao diện Storefront; fallback query vẫn hoạt động.
- Không push lên remote git; chỉ commit local trên nhánh `main`.

## Review Focus

- Anonymous client cố gắng gửi hoặc nghe sự kiện riêng tư của đơn hàng khác -> Bị chặn, không nhận được sự kiện nội bộ.
- Admin cập nhật chỉ số điện thoại hotline -> Storefront tự đổi số điện thoại trên nút hotline và tel: link ngay lập tức.
- Admin gạt tắt đặt hàng -> Storefront tự đổi nút "Chọn món" thành nút "Gọi đặt" và ẩn giỏ hàng trên tất cả các tab đang mở.
- Storefront mất mạng tạm thời rồi kết nối lại (`reconnect`) -> Tự động refetch cấu hình mới nhất từ API.
- Request `PATCH /api/orders/store-config` thành công ngay cả khi RabbitMQ gặp sự cố tạm thời (không bị 500 unhandled).

---

### Task 1: Ordering Service - Publish Realtime Event `store-config.updated`

**Files:**
- Modify: `apps/api/apps/ordering-service/src/ordering.service.ts:1098-1135`
- Test: `apps/api/apps/ordering-service/src/ordering.service.spec.ts`

**Interfaces:**
- Consumes: `createRealtimeEvent` từ `@contracts`, `rabbitmqService.publishEvent` từ `RabbitmqService`.
- Produces: RabbitMQ message trên topic exchange `sushi.events` với type `store-config.updated`, resource `order`, action `UPDATED`, payload `{ customerOrderingEnabled, contactPhone }`.

- [ ] **Step 1: Write the failing test in `ordering.service.spec.ts`**

Thêm test case kiểm tra `updateStoreConfig` phát sự kiện `store-config.updated` qua `rabbitmqService.publishEvent`:

```typescript
it('should publish store-config.updated event to rabbitmq on successful update', async () => {
  const existingConfig = {
    id: 'cfg-1',
    key: 'DEFAULT',
    customerOrderingEnabled: true,
    contactPhone: '0988888888',
  };
  mockPrismaService.storeConfig.findUnique.mockResolvedValue(existingConfig);
  mockPrismaService.storeConfig.update.mockResolvedValue({
    ...existingConfig,
    customerOrderingEnabled: false,
    contactPhone: '0911222333',
  });

  const result = await service.updateStoreConfig(
    { customerOrderingEnabled: false, contactPhone: '0911222333' },
    'ADMIN',
  );

  expect(result.customerOrderingEnabled).toBe(false);
  expect(rabbitmqService.publishEvent).toHaveBeenCalledWith(
    expect.objectContaining({
      type: 'store-config.updated',
      resource: 'order',
      action: 'UPDATED',
      payload: {
        customerOrderingEnabled: false,
        contactPhone: '0911222333',
      },
    }),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter api test ordering.service.spec.ts`
Expected: FAIL vì `updateStoreConfig` hiện chưa gọi `rabbitmqService.publishEvent`.

- [ ] **Step 3: Implement event publishing in `ordering.service.ts`**

Trong `updateStoreConfig`, sau khi gọi `this.prisma.storeConfig.update(...)`:

```typescript
    const updated = await this.prisma.storeConfig.update({
      where: { id: existing.id },
      data: {
        ...(dto.customerOrderingEnabled !== undefined && {
          customerOrderingEnabled: dto.customerOrderingEnabled,
        }),
        ...(dto.contactPhone !== undefined && {
          contactPhone: dto.contactPhone.trim(),
        }),
      },
    });

    try {
      await this.rabbitmqService.publishEvent(
        createRealtimeEvent({
          type: 'store-config.updated',
          resource: 'order',
          action: 'UPDATED',
          payload: {
            customerOrderingEnabled: updated.customerOrderingEnabled,
            contactPhone: updated.contactPhone,
          },
        }),
      );
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.warn(`Failed to publish store-config.updated event: ${message}`);
    }

    return updated;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter api test ordering.service.spec.ts`
Expected: PASS toàn bộ các test cases của `OrderingService`.

- [ ] **Step 5: Commit**

```bash
git add apps/api/apps/ordering-service/src/ordering.service.ts apps/api/apps/ordering-service/src/ordering.service.spec.ts
git commit -m "feat(ordering): publish store-config.updated event to rabbitmq on config update"
```

---

### Task 2: API Gateway - Hỗ trợ anonymous client vào room public & broadcast `store-config:updated`

**Files:**
- Modify: `apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts`
- Test: `apps/api/apps/api-gateway/src/realtime/realtime.gateway.spec.ts`

**Interfaces:**
- Consumes: `RealtimeDomainEvent` từ `RealtimeConsumerService`.
- Produces: Socket.IO event `store-config:updated` phát tới room `public:store-config`.

- [ ] **Step 1: Write the failing tests in `realtime.gateway.spec.ts`**

Thêm các test cases kiểm thử:
1. Client không có token được chấp nhận kết nối và join room `public:store-config`.
2. Client có token lỗi/hết hạn bị từ chối (`client.disconnect()`).
3. `broadcastRealtimeEvent` khi nhận sự kiện `store-config.updated` sẽ emit sự kiện `store-config:updated` tới room `public:store-config`.

```typescript
it('should accept anonymous client without token and join public store config room', async () => {
  const client = {
    id: 'anon-client-1',
    handshake: { auth: {}, headers: {} },
    join: jest.fn().mockResolvedValue(undefined),
    disconnect: jest.fn(),
    data: {},
  } as unknown as Socket;

  await gateway.handleConnection(client);

  expect(client.disconnect).not.toHaveBeenCalled();
  expect(client.join).toHaveBeenCalledWith(REALTIME_ROOMS.PUBLIC_STORE_CONFIG);
  expect(client.join).not.toHaveBeenCalledWith(REALTIME_ROOMS.AUTHENTICATED);
});

it('should broadcast store-config:updated to public store config room', () => {
  const event: RealtimeDomainEvent = {
    id: 'evt-config-1',
    type: 'store-config.updated',
    resource: 'order',
    action: 'UPDATED',
    branchId: null,
    timestamp: '2026-11-14T10:00:00.000Z',
    payload: {
      customerOrderingEnabled: false,
      contactPhone: '0988888888',
    },
  };

  gateway.broadcastRealtimeEvent(event);

  expect(mockServer.to).toHaveBeenCalledWith(REALTIME_ROOMS.PUBLIC_STORE_CONFIG);
  expect(mockServer.emit).toHaveBeenCalledWith('store-config:updated', {
    customerOrderingEnabled: false,
    contactPhone: '0988888888',
    timestamp: '2026-11-14T10:00:00.000Z',
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter api test realtime.gateway.spec.ts`
Expected: FAIL vì `REALTIME_ROOMS.PUBLIC_STORE_CONFIG` chưa tồn tại và socket không có token hiện đang bị disconnect.

- [ ] **Step 3: Implement anonymous join and public broadcast in `realtime.gateway.ts`**

Cập nhật `realtime.gateway.ts`:
1. Bổ sung `PUBLIC_STORE_CONFIG: 'public:store-config'` vào `REALTIME_ROOMS`.
2. Trong `handleConnection(client: Socket)`:
   - Nếu không có token (`!token`):
     - `client.data = client.data || {};`
     - `client.data.isPublic = true;`
     - `await client.join(REALTIME_ROOMS.PUBLIC_STORE_CONFIG);`
     - `this.logger.log(`Public client connected: ${client.id}`);`
     - `return;`
   - Nếu có token: xác thực JWT như cũ. Khi xác thực thành công, client cũng join luôn `REALTIME_ROOMS.PUBLIC_STORE_CONFIG` để người dùng đã đăng nhập hoặc nhân viên cũng nhận được cập nhật cấu hình.
3. Trong `broadcastRealtimeEvent(event: RealtimeDomainEvent)`:
   - Nếu `event.type === 'store-config.updated'`:
     - Phát tới `REALTIME_ROOMS.PUBLIC_STORE_CONFIG`:
       ```typescript
       this.server
         .to(REALTIME_ROOMS.PUBLIC_STORE_CONFIG)
         .emit('store-config:updated', {
           customerOrderingEnabled: event.payload?.customerOrderingEnabled,
           contactPhone: event.payload?.contactPhone,
           timestamp: event.timestamp || new Date().toISOString(),
         });
       ```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter api test realtime.gateway.spec.ts`
Expected: PASS toàn bộ các test cases của `RealtimeGateway`.

- [ ] **Step 5: Commit**

```bash
git add apps/api/apps/api-gateway/src/realtime/realtime.gateway.ts apps/api/apps/api-gateway/src/realtime/realtime.gateway.spec.ts
git commit -m "feat(realtime): allow public clients for store-config room and broadcast store-config:updated"
```

---

### Task 3: Storefront - Tích hợp WebSocket realtime vào `useStoreConfig`

**Files:**
- Modify: `apps/storefront/src/hooks/use-store-config.ts`

**Interfaces:**
- Consumes: Endpoint REST `GET /api/orders/store-config` & WebSocket namespace `/realtime` phát sự kiện `store-config:updated`.
- Produces: Hook `useStoreConfig()` phản ứng tức thì với dữ liệu mới mà không cần F5.

- [ ] **Step 1: Inspect hook requirements and connection lifecycle**

Storefront cần:
1. `refetchOnWindowFocus: true` cho query `storeConfigKey`.
2. Tạo socket client kết nối tới `${socketUrl}/realtime` (với `withCredentials: false`, `transports: ["websocket", "polling"]`).
3. Khi nhận `store-config:updated`:
   - Cập nhật trực tiếp TanStack Query cache `queryClient.setQueryData(storeConfigKey, (prev) => ...)`
   - Đồng thời gọi `queryClient.invalidateQueries({ queryKey: storeConfigKey })` để đảm bảo đồng bộ triệt để.
4. Khi nhận event `reconnect`:
   - `queryClient.invalidateQueries({ queryKey: storeConfigKey })`.
5. Đảm bảo dùng listener an toàn, không tạo nhiều socket lặp lại mỗi lần component re-render.

- [ ] **Step 2: Implement realtime synchronization in `apps/storefront/src/hooks/use-store-config.ts`**

Cập nhật `apps/storefront/src/hooks/use-store-config.ts`:
```typescript
"use client";

import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { io, Socket } from "socket.io-client";
import { fetchStoreConfig, type StoreConfig } from "@/lib/api";
import { SITE_CONFIG } from "@/config/site.config";

export const storeConfigKey = ["store-config"] as const;

export function useStoreConfig() {
  const queryClient = useQueryClient();

  const query = useQuery<StoreConfig | null>({
    queryKey: storeConfigKey,
    queryFn: fetchStoreConfig,
    staleTime: 60 * 1000,
    refetchOnWindowFocus: true,
  });

  React.useEffect(() => {
    if (typeof window === "undefined") return;

    const socketUrl =
      process.env.NEXT_PUBLIC_SOCKET_URL ||
      `${window.location.protocol}//${window.location.hostname}:3000`;

    const socket: Socket = io(`${socketUrl}/realtime`, {
      withCredentials: false,
      transports: ["websocket", "polling"],
      reconnectionAttempts: 10,
      reconnectionDelay: 2000,
    });

    socket.on(
      "store-config:updated",
      (data?: { customerOrderingEnabled?: boolean; contactPhone?: string }) => {
        if (data) {
          queryClient.setQueryData<StoreConfig | null>(storeConfigKey, (old) => {
            if (!old) return data as StoreConfig;
            return {
              ...old,
              ...(data.customerOrderingEnabled !== undefined && {
                customerOrderingEnabled: data.customerOrderingEnabled,
              }),
              ...(data.contactPhone !== undefined && {
                contactPhone: data.contactPhone,
              }),
            };
          });
        }
        queryClient.invalidateQueries({ queryKey: storeConfigKey });
      }
    );

    socket.io.on("reconnect", () => {
      queryClient.invalidateQueries({ queryKey: storeConfigKey });
    });

    return () => {
      socket.disconnect();
    };
  }, [queryClient]);

  const customerOrderingEnabled = query.data?.customerOrderingEnabled ?? true;
  const contactPhone = query.data?.contactPhone || SITE_CONFIG.hotline;
  const contactPhoneTel = contactPhone.replace(/\s+/g, "");

  return {
    ...query,
    customerOrderingEnabled,
    contactPhone,
    contactPhoneTel,
  };
}
```

- [ ] **Step 3: Run storefront build & lint to verify type safety**

Run: `pnpm --filter storefront build`
Expected: Build thành công không có lỗi type hay lint.

- [ ] **Step 4: Commit**

```bash
git add apps/storefront/src/hooks/use-store-config.ts
git commit -m "feat(storefront): subscribe to realtime store-config:updated and auto invalidate query"
```

---

### Task 4: Kiểm thử tích hợp toàn bộ hệ thống (End-to-End Test & Verification)

**Files:**
- Toàn bộ các submodule liên quan (`apps/api`, `apps/storefront`, `apps/admin-web`).

- [ ] **Step 1: Chạy toàn bộ test suites backend**

Run: `pnpm --filter api test`
Expected: 17/17 test suites passed, 100% tests green.

- [ ] **Step 2: Build toàn bộ các ứng dụng**

Run: `pnpm --filter api build`
Run: `pnpm --filter admin-web build`
Run: `pnpm --filter storefront build`
Expected: Cả 3 ứng dụng build thành công không có lỗi biên dịch.

- [ ] **Step 3: Kiểm tra trạng thái Git**

Run: `git status --short`
Expected: Working tree clean trên nhánh `main`, sẵn sàng cho người dùng kiểm chứng.
