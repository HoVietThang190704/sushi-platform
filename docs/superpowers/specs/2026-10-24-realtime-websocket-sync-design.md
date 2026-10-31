# Realtime WebSocket Synchronization Design (Architecture Path)

**Date:** 2026-10-24  
**Status:** Approved by User  
**Target Clients:** `apps/admin-web` (Phase 1), extensible to storefront & mobile (Phase 2+)

---

## 1. Context & Business Intent
Admin users currently need to reload pages or perform self-mutations to observe fresh state. When inventory or catalog records are altered by background tasks, other admins, or upcoming services, data becomes stale.
The goal is **zero-reload automatic updates** for current active screens without loading entire database record sets via sockets.

---

## 2. Selected Architectural Pattern (Approach 1)
Event-driven invalidation pipeline:
```
[Microservices (Inventory/Catalog)]
      │
      ▼ (Prisma Transaction Outbox)
   [Outbox Table]
      │
      ▼ (Reliable Publisher / RabbitMQ Exchange: sushi.events)
   [RabbitMQ Topic Exchange]
      │
      ▼ (Queue: api_gateway_realtime)
   [API Gateway WebSocket Gateway (Socket.IO)]
      │
      ▼ (Cookie Auth Handshake + Branch/Role Room Join)
   [Socket.IO Client in Admin-Web]
      │
      ▼ (TanStack Query queryClient.invalidateQueries)
   [REST API GET (Fresh Data Loaded Transparently)]
```

### Key Architectural Boundaries:
1. **Source of Truth:** PostgreSQL remains single source of truth; REST API handles read/write queries.
2. **Signal-Only Payloads:** WebSockets transmit domain signals (`resource`, `action`, `branchId`, `timestamp`), NOT full mutable entity rows.
3. **Decoupled Gateway:** Gateway manages client connections and authentication. Backend microservices emit domain events into RabbitMQ without coupling to Socket connection IDs.
4. **Resilient Reconnection:** TanStack Query revalidates active queries on socket reconnect.

---

## 3. Security & Authentication Model
- **Handshake Authentication:** Gateway inspects `access_token` cookie or `Authorization: Bearer <token>` in handshake headers.
- **JWT Verification:** Validated using `process.env.JWT_SECRET`.
- **Tenancy Isolation:** Client automatically joins `branch:<branchId>` and `role:<role>` rooms. Events scoped to a branch are dispatched only to the matching room.
- **Unauthorized Handling:** If JWT is missing/expired, gateway rejects connection with error code `401`.

---

## 4. Contract Specification

### Event Schema (`sushi.events`):
```typescript
export interface RealtimeDomainEvent<T = Record<string, unknown>> {
  id: string;             // UUID
  type: string;           // e.g. "inventory.stock.updated", "catalog.product.created"
  resource: 'inventory' | 'catalog' | 'order';
  action: 'CREATED' | 'UPDATED' | 'DELETED';
  branchId?: string | null;
  timestamp: string;
  payload: T;
}
```

### Client Invalidation Map:
- `inventory.*` -> `queryClient.invalidateQueries({ queryKey: inventoryKeys.all })`
- `catalog.product.*` -> `queryClient.invalidateQueries({ queryKey: catalogKeys.all })`
- `catalog.category.*` -> `queryClient.invalidateQueries({ queryKey: catalogKeys.categories() })`

---

## 5. Technology Choices
- **Backend Realtime Gateway:** NestJS `@nestjs/websockets` + `@nestjs/platform-socket.io` + `socket.io`.
- **Inter-service Broker:** `amqplib` / RabbitMQ topic exchange.
- **Client Realtime:** `socket.io-client` wrapped in custom `RealtimeProvider`.
- **State Synchronization:** `@tanstack/react-query` v5 invalidation hooks.
