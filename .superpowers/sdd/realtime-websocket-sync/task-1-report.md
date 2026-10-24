# Task 1 Report: Contracts & Event Interfaces Shared Package / Shared Lib

- **Trạng thái (Status):** DONE
- **Ngày hoàn thành:** 2026-10-24

## 1. Các file đã tạo và chỉnh sửa (Files Created & Modified)

### Files Created:
1. `apps/api/libs/contracts/src/realtime-events.ts`:
   - Định nghĩa hằng số `REALTIME_EXCHANGE = 'sushi.events'`.
   - Định nghĩa type `RealtimeResource = 'inventory' | 'catalog' | 'order' | 'identity'`.
   - Định nghĩa type `RealtimeAction = 'CREATED' | 'UPDATED' | 'DELETED'`.
   - Định nghĩa interface `RealtimeDomainEvent<T = Record<string, unknown>>` chuẩn:
     - `id: string` (UUID v4)
     - `type: string`
     - `resource: RealtimeResource`
     - `action: RealtimeAction`
     - `branchId?: string | null`
     - `timestamp: string` (ISO 8601 string)
     - `payload: T`
   - Helper function `createRealtimeEvent<T>(params: CreateRealtimeEventParams<T>): RealtimeDomainEvent<T>` tự động sinh UUID v4 và timestamp ISO nếu không truyền vào.
2. `apps/api/libs/contracts/src/index.ts`:
   - Re-export toàn bộ types, interfaces, constants và helper functions từ `realtime-events.ts`.
3. `apps/api/libs/contracts/src/realtime-events.spec.ts`:
   - Unit tests kiểm tra `REALTIME_EXCHANGE`, cấu trúc `RealtimeDomainEvent`, định dạng UUID v4, định dạng ISO timestamp, hỗ trợ custom id/timestamp, xử lý `branchId` optional/null, các types `RealtimeResource`, `RealtimeAction`, và kiểm tra alias import qua `@contracts`.

### Files Modified:
1. `apps/api/tsconfig.json`:
   - Thêm alias paths:
     - `"@contracts": ["libs/contracts/src"]`
     - `"@contracts/*": ["libs/contracts/src/*"]`
     - `"@libs/contracts": ["libs/contracts/src"]`
     - `"@libs/contracts/*": ["libs/contracts/src/*"]`
2. `apps/api/nest-cli.json`:
   - Thêm cấu hình library `contracts` vào danh sách `projects`.
3. `apps/api/package.json`:
   - Thêm `<rootDir>/libs/` vào jest `roots`.
   - Thêm `moduleNameMapper` để jest resolve `@contracts`, `@libs/contracts`, `@common`.

---

## 2. Kết quả kiểm thử (Test Results)

Chạy lệnh: `cd apps/api && pnpm jest libs/contracts`

```
PASS libs/contracts/src/realtime-events.spec.ts
  Realtime Events Contracts
    Constants
      √ should have REALTIME_EXCHANGE set to "sushi.events" (2 ms)
    createRealtimeEvent
      √ should generate a valid event with auto-generated UUID and ISO timestamp (2 ms)
      √ should preserve custom id and timestamp when explicitly provided (1 ms)
      √ should handle optional branchId when omitted (1 ms)
      √ should correctly support all RealtimeResource types (1 ms)
      √ should correctly support all RealtimeAction types (1 ms)
      √ should be exportable and importable via @contracts alias (1 ms)

Test Suites: 1 passed, 1 total
Tests:       7 passed, 7 total
Snapshots:   0 total
Time:        0.388 s, estimated 1 s
Ran all test suites matching libs/contracts.
```

Đồng thời kiểm tra build: `nest build api-gateway` biên dịch thành công 100%.

---

## 3. Git Commit Hash

- **Submodule `apps/api` commit:** `9cca4e402b3111f3d23a32314755531178c16643`
  - Message: `feat(realtime): add shared realtime event contracts`
- **Root repo commit:** `45c59211116495a04d6cefb48e6012613dc9adbf`
  - Message: `feat(realtime): add shared realtime event contracts`
- **Constraint check:** Tuân thủ 100% yêu cầu KHÔNG thực hiện `git push`.
