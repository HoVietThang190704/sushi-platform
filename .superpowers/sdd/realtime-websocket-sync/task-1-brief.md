### Task 1: Contracts & Event Interfaces Shared Package / Shared Lib
**Files:**
- Create: `apps/api/libs/contracts/src/realtime-events.ts`
- Create: `apps/api/libs/contracts/src/index.ts`
- Modify: `apps/api/tsconfig.json`
- Test: `apps/api/libs/contracts/src/realtime-events.spec.ts`

**Interfaces:**
- Produces: `RealtimeDomainEvent`, `REALTIME_EXCHANGE = 'sushi.events'`
- Action: Định nghĩa type-safe domain event cho toàn bộ luồng realtime microservices.
- Constraint: Không git push lên remote. Tuân thủ Clean Code, không any, có đầy đủ type definition.
