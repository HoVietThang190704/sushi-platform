# Inventory Management Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Inventory Management (Nhập - Xuất - Tồn - Cảnh Báo) subsystem for Sushi Platform, allowing restaurant admins to track raw ingredients, post stock-in/stock-out transactions, manage initial stock, and receive 2-tier low-stock alerts.

**Architecture:** A dedicated NestJS microservice `inventory-service` running on port 3003, with PostgreSQL `inventory` schema managed via Prisma. API Gateway on port 3000 proxies `/api/inventory/*` to `inventory-service`. Next.js 16 Admin Web running on port 3004 provides interactive inventory dashboards, tables, and validation modals.

**Tech Stack:** NestJS 11, Prisma ORM, PostgreSQL (multi-schema), Next.js 16 (App Router), React 19, Ant Design, Tailwind CSS v4, TanStack Query v5, Zod.

**Spec:** `docs/superpowers/specs/2026-10-20-inventory-management-design.md`

## Global Constraints

- Services port allocation: API Gateway = 3000, Identity = 3001, Catalog = 3002, Inventory = 3003, Admin Web = 3004.
- Database uses PostgreSQL multi-schema: `inventory` schema is pre-created in `infrastructure/docker/init-db/01-init-schemas.sql`.
- Stock transactions must atomically adjust ingredient stock in a database transaction (`$transaction`).
- Negative stock is strictly disallowed on stock-out (`currentStock >= quantity`).
- Currency values use VND, formatted via `useFormatCurrency`.
- All user-facing text must have full Vietnamese and English entries in `locales/vi.json` and `locales/en.json`.

## Review Focus

1. **Negative Stock Attempt**: Submitting an outbound transaction with quantity greater than `currentStock` must be rejected with 400 Bad Request.
2. **Initial Stock Automation**: Creating an ingredient with `initialStock > 0` must create an atomic initial `IN` transaction with reason `INITIAL_STOCK`.
3. **Alert Threshold Exactness**: An ingredient with `currentStock == minStock` must trigger `LOW_STOCK` (yellow), and `currentStock <= 0` must trigger `OUT_OF_STOCK` (red).
4. **Code Generation Idempotence**: Stock in transaction code must format as `PNK-YYYYMMDD-XXXX` and stock out as `PXK-YYYYMMDD-XXXX`.
5. **CORS on Port 3004**: API Gateway must allow requests with credentials from `http://localhost:3004`.

---

### Task 1: Database Schema & Prisma Migration for Inventory

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Test: `apps/api/apps/catalog-service/test/app.e2e-spec.ts`

**Interfaces:**
- Consumes: PostgreSQL connection string from `DATABASE_URL`
- Produces: `prisma.ingredient` and `prisma.inventoryTransaction` client models

- [ ] **Step 1: Update Prisma schema with inventory models**

Add `"inventory"` to `schemas` array, and add `TransactionType`, `TransactionReason`, `Ingredient`, and `InventoryTransaction` models in `apps/api/prisma/schema.prisma`:

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
  schemas  = ["identity", "catalog", "inventory"]
}

enum TransactionType {
  IN
  OUT

  @@schema("inventory")
}

enum TransactionReason {
  INITIAL_STOCK
  PURCHASE
  KITCHEN_USAGE
  DISCARD_WASTE
  ADJUSTMENT

  @@schema("inventory")
}

model Ingredient {
  id           String   @id @default(uuid()) @db.Uuid
  code         String   @unique @db.VarChar(50)
  name         String   @db.VarChar(160)
  unit         String   @db.VarChar(30)
  currentStock Decimal  @default(0) @map("current_stock") @db.Decimal(18, 3)
  minStock     Decimal  @default(0) @map("min_stock") @db.Decimal(18, 3)
  costPrice    Decimal  @default(0) @map("cost_price") @db.Decimal(18, 2)
  isActive     Boolean  @default(true) @map("is_active")
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")

  transactions InventoryTransaction[]

  @@map("ingredients")
  @@schema("inventory")
}

model InventoryTransaction {
  id           String            @id @default(uuid()) @db.Uuid
  code         String            @unique @db.VarChar(50)
  type         TransactionType
  reason       TransactionReason @default(PURCHASE)
  ingredientId String            @map("ingredient_id") @db.Uuid
  ingredient   Ingredient        @relation(fields: [ingredientId], references: [id])
  quantity     Decimal           @db.Decimal(18, 3)
  unitPrice    Decimal           @default(0) @map("unit_price") @db.Decimal(18, 2)
  totalAmount  Decimal           @default(0) @map("total_amount") @db.Decimal(18, 2)
  note         String?           @db.Text
  createdBy    String?           @map("created_by")
  createdAt    DateTime          @default(now()) @map("created_at")

  @@map("inventory_transactions")
  @@schema("inventory")
}
```

- [ ] **Step 2: Generate Prisma Client & Push DB schema**

Run: `cd apps/api && pnpm prisma generate && pnpm prisma db push`
Expected: "Your database is now in sync with your Prisma schema. Done in ...ms"

- [ ] **Step 3: Verify Prisma Client output**

Run: `node -e "const { PrismaClient } = require('@prisma/client'); const p = new PrismaClient(); console.log(typeof p.ingredient.create === 'function');"`
Expected: `true`

- [ ] **Step 4: Commit schema changes**

```bash
git add apps/api/prisma/schema.prisma
git commit -m "feat(prisma): Add inventory schema with ingredient and transaction models"
```

---

### Task 2: Scaffold NestJS Inventory Microservice (Port 3003)

**Files:**
- Modify: `apps/api/nest-cli.json`
- Create: `apps/api/apps/inventory-service/tsconfig.app.json`
- Create: `apps/api/apps/inventory-service/src/prisma.service.ts`
- Create: `apps/api/apps/inventory-service/src/inventory-service.module.ts`
- Create: `apps/api/apps/inventory-service/src/main.ts`

**Interfaces:**
- Consumes: `@prisma/client`, `libs/common`
- Produces: NestJS service listening on HTTP port 3003

- [ ] **Step 1: Register inventory-service in nest-cli.json**

Add `inventory-service` entry under `projects` in `apps/api/nest-cli.json`:

```json
    "inventory-service": {
      "type": "application",
      "root": "apps/inventory-service",
      "entryFile": "main",
      "sourceRoot": "apps/inventory-service/src",
      "compilerOptions": {
        "tsConfigPath": "apps/inventory-service/tsconfig.app.json"
      }
    }
```

- [ ] **Step 2: Create inventory-service tsconfig.app.json**

Create `apps/api/apps/inventory-service/tsconfig.app.json`:

```json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "declaration": false,
    "outDir": "../../dist/apps/inventory-service"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "test", "**/*spec.ts"]
}
```

- [ ] **Step 3: Create PrismaService for inventory-service**

Create `apps/api/apps/inventory-service/src/prisma.service.ts`:

```typescript
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

- [ ] **Step 4: Create InventoryServiceModule and main.ts**

Create `apps/api/apps/inventory-service/src/inventory-service.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Module({
  imports: [],
  controllers: [],
  providers: [PrismaService],
  exports: [PrismaService],
})
export class InventoryServiceModule {}
```

Create `apps/api/apps/inventory-service/src/main.ts`:

```typescript
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { InventoryServiceModule } from './inventory-service.module';
import { TransformResponseInterceptor } from '@app/common/interceptors/transform-response.interceptor';
import { AllExceptionsFilter } from '@app/common/filters/all-exceptions.filter';

async function bootstrap() {
  const app = await NestFactory.create(InventoryServiceModule);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  app.useGlobalInterceptors(new TransformResponseInterceptor());
  app.useGlobalFilters(new AllExceptionsFilter());

  const port = process.env.INVENTORY_SERVICE_PORT || 3003;
  await app.listen(port);
  console.log(`Inventory Service is running on http://localhost:${port}`);
}
bootstrap();
```

- [ ] **Step 5: Verify service build**

Run: `cd apps/api && pnpm nest build inventory-service`
Expected: Compiled successfully with output in `dist/apps/inventory-service`.

- [ ] **Step 6: Commit scaffolding**

```bash
git add apps/api/nest-cli.json apps/api/apps/inventory-service
git commit -m "feat(inventory-service): Scaffold NestJS inventory microservice structure"
```

---

### Task 3: Implement Inventory Core DTOs, Service & Controller

**Files:**
- Create: `apps/api/apps/inventory-service/src/dto/create-ingredient.dto.ts`
- Create: `apps/api/apps/inventory-service/src/dto/create-transaction.dto.ts`
- Create: `apps/api/apps/inventory-service/src/dto/transaction-query.dto.ts`
- Create: `apps/api/apps/inventory-service/src/inventory.service.ts`
- Create: `apps/api/apps/inventory-service/src/inventory.controller.ts`
- Create: `apps/api/apps/inventory-service/src/inventory.service.spec.ts`

**Interfaces:**
- Consumes: `PrismaService`, `CreateIngredientDto`, `CreateTransactionDto`
- Produces: REST endpoints on `/inventory/ingredients`, `/inventory/transactions`, `/inventory/alerts`

- [ ] **Step 1: Create DTOs with class-validator**

Create `apps/api/apps/inventory-service/src/dto/create-ingredient.dto.ts`:

```typescript
import { IsString, IsNotEmpty, IsNumber, Min, IsOptional } from 'class-validator';

export class CreateIngredientDto {
  @IsString()
  @IsNotEmpty()
  code: string;

  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsNotEmpty()
  unit: string;

  @IsNumber()
  @Min(0)
  costPrice: number;

  @IsNumber()
  @Min(0)
  minStock: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  initialStock?: number;
}
```

Create `apps/api/apps/inventory-service/src/dto/create-transaction.dto.ts`:

```typescript
import { IsEnum, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import { TransactionType, TransactionReason } from '@prisma/client';

export class CreateTransactionDto {
  @IsEnum(TransactionType)
  @IsNotEmpty()
  type: TransactionType;

  @IsEnum(TransactionReason)
  @IsNotEmpty()
  reason: TransactionReason;

  @IsUUID()
  @IsNotEmpty()
  ingredientId: string;

  @IsNumber()
  @Min(0.001)
  quantity: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  unitPrice?: number;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsString()
  createdBy?: string;
}
```

Create `apps/api/apps/inventory-service/src/dto/transaction-query.dto.ts`:

```typescript
import { IsEnum, IsOptional, IsUUID } from 'class-validator';
import { TransactionType } from '@prisma/client';

export class TransactionQueryDto {
  @IsOptional()
  @IsEnum(TransactionType)
  type?: TransactionType;

  @IsOptional()
  @IsUUID()
  ingredientId?: string;
}
```

- [ ] **Step 2: Write failing unit test for inventory service logic**

Create `apps/api/apps/inventory-service/src/inventory.service.spec.ts`:

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { PrismaService } from './prisma.service';
import { TransactionType, TransactionReason } from '@prisma/client';

describe('InventoryService', () => {
  let service: InventoryService;
  let prisma: PrismaService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        InventoryService,
        {
          provide: PrismaService,
          useValue: {
            ingredient: {
              findMany: jest.fn(),
              findUnique: jest.fn(),
              create: jest.fn(),
              update: jest.fn(),
            },
            inventoryTransaction: {
              findMany: jest.fn(),
              create: jest.fn(),
              count: jest.fn(),
            },
            $transaction: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<InventoryService>(InventoryService);
    prisma = module.get<PrismaService>(PrismaService);
  });

  it('should throw BadRequestException when stock out quantity exceeds currentStock', async () => {
    jest.spyOn(prisma.ingredient, 'findUnique').mockResolvedValue({
      id: 'uuid-1',
      code: 'NL-01',
      name: 'Salmon',
      unit: 'kg',
      currentStock: 2 as any,
      minStock: 5 as any,
      costPrice: 100000 as any,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    await expect(
      service.createTransaction({
        type: TransactionType.OUT,
        reason: TransactionReason.KITCHEN_USAGE,
        ingredientId: 'uuid-1',
        quantity: 5,
      }),
    ).rejects.toThrow(BadRequestException);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/api && pnpm test apps/inventory-service/src/inventory.service.spec.ts`
Expected: FAIL with "Cannot find module './inventory.service'"

- [ ] **Step 4: Implement InventoryService with atomic stock management**

Create `apps/api/apps/inventory-service/src/inventory.service.ts`:

```typescript
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { CreateIngredientDto } from './dto/create-ingredient.dto';
import { CreateTransactionDto } from './dto/create-transaction.dto';
import { TransactionQueryDto } from './dto/transaction-query.dto';
import { TransactionType, TransactionReason, Prisma } from '@prisma/client';

@Injectable()
export class InventoryService {
  constructor(private readonly prisma: PrismaService) {}

  private generateCode(type: TransactionType): string {
    const prefix = type === TransactionType.IN ? 'PNK' : 'PXK';
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10).replace(/-/g, '');
    const rand = Math.floor(1000 + Math.random() * 9000);
    return `${prefix}-${dateStr}-${rand}`;
  }

  async getIngredients() {
    const items = await this.prisma.ingredient.findMany({
      where: { isActive: true },
      orderBy: { createdAt: 'desc' },
      include: {
        _count: {
          select: { transactions: true },
        },
      },
    });

    return items.map((item) => {
      const stock = Number(item.currentStock);
      const min = Number(item.minStock);

      let status: 'OUT_OF_STOCK' | 'LOW_STOCK' | 'SAFE' = 'SAFE';
      if (stock <= 0) {
        status = 'OUT_OF_STOCK';
      } else if (stock <= min) {
        status = 'LOW_STOCK';
      }

      return {
        ...item,
        currentStock: stock,
        minStock: min,
        costPrice: Number(item.costPrice),
        status,
        isAlert: status !== 'SAFE',
      };
    });
  }

  async createIngredient(dto: CreateIngredientDto) {
    const existing = await this.prisma.ingredient.findUnique({
      where: { code: dto.code },
    });
    if (existing) {
      throw new BadRequestException(`Mã nguyên liệu "${dto.code}" đã tồn tại!`);
    }

    const initialQty = dto.initialStock && dto.initialStock > 0 ? dto.initialStock : 0;

    return this.prisma.$transaction(async (tx) => {
      const ingredient = await tx.ingredient.create({
        data: {
          code: dto.code.trim().toUpperCase(),
          name: dto.name.trim(),
          unit: dto.unit.trim(),
          costPrice: dto.costPrice,
          minStock: dto.minStock,
          currentStock: initialQty,
        },
      });

      if (initialQty > 0) {
        await tx.inventoryTransaction.create({
          data: {
            code: this.generateCode(TransactionType.IN),
            type: TransactionType.IN,
            reason: TransactionReason.INITIAL_STOCK,
            ingredientId: ingredient.id,
            quantity: initialQty,
            unitPrice: dto.costPrice,
            totalAmount: Number(initialQty) * Number(dto.costPrice),
            note: 'Khởi tạo số lượng tồn ban đầu',
            createdBy: 'SYSTEM_INIT',
          },
        });
      }

      return ingredient;
    });
  }

  async createTransaction(dto: CreateTransactionDto) {
    const ingredient = await this.prisma.ingredient.findUnique({
      where: { id: dto.ingredientId },
    });
    if (!ingredient) {
      throw new NotFoundException(`Không tìm thấy nguyên liệu có ID "${dto.ingredientId}"`);
    }

    const currentStock = Number(ingredient.currentStock);
    const qty = Number(dto.quantity);

    if (dto.type === TransactionType.OUT && currentStock < qty) {
      throw new BadRequestException(
        `Số lượng tồn không đủ để xuất! Tồn hiện tại: ${currentStock} ${ingredient.unit}, yêu cầu xuất: ${qty} ${ingredient.unit}`,
      );
    }

    const unitPrice = dto.unitPrice !== undefined ? Number(dto.unitPrice) : Number(ingredient.costPrice);
    const totalAmount = qty * unitPrice;
    const code = this.generateCode(dto.type);

    return this.prisma.$transaction(async (tx) => {
      const transaction = await tx.inventoryTransaction.create({
        data: {
          code,
          type: dto.type,
          reason: dto.reason,
          ingredientId: dto.ingredientId,
          quantity: qty,
          unitPrice,
          totalAmount,
          note: dto.note,
          createdBy: dto.createdBy || 'ADMIN',
        },
        include: {
          ingredient: true,
        },
      });

      const updatedStock =
        dto.type === TransactionType.IN
          ? currentStock + qty
          : currentStock - qty;

      await tx.ingredient.update({
        where: { id: dto.ingredientId },
        data: { currentStock: updatedStock },
      });

      return transaction;
    });
  }

  async getTransactions(query: TransactionQueryDto) {
    const where: Prisma.InventoryTransactionWhereInput = {};
    if (query.type) where.type = query.type;
    if (query.ingredientId) where.ingredientId = query.ingredientId;

    return this.prisma.inventoryTransaction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      include: {
        ingredient: {
          select: {
            code: true,
            name: true,
            unit: true,
          },
        },
      },
    });
  }

  async getAlerts() {
    const ingredients = await this.getIngredients();
    return ingredients.filter((item) => item.isAlert);
  }
}
```

- [ ] **Step 5: Implement InventoryController**

Create `apps/api/apps/inventory-service/src/inventory.controller.ts`:

```typescript
import { Controller, Get, Post, Body, Query } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { CreateIngredientDto } from './dto/create-ingredient.dto';
import { CreateTransactionDto } from './dto/create-transaction.dto';
import { TransactionQueryDto } from './dto/transaction-query.dto';

@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Get('ingredients')
  getIngredients() {
    return this.inventoryService.getIngredients();
  }

  @Post('ingredients')
  createIngredient(@Body() dto: CreateIngredientDto) {
    return this.inventoryService.createIngredient(dto);
  }

  @Get('alerts')
  getAlerts() {
    return this.inventoryService.getAlerts();
  }

  @Post('transactions')
  createTransaction(@Body() dto: CreateTransactionDto) {
    return this.inventoryService.createTransaction(dto);
  }

  @Get('transactions')
  getTransactions(@Query() query: TransactionQueryDto) {
    return this.inventoryService.getTransactions(query);
  }
}
```

Update `apps/api/apps/inventory-service/src/inventory-service.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { InventoryService } from './inventory.service';
import { InventoryController } from './inventory.controller';

@Module({
  imports: [],
  controllers: [InventoryController],
  providers: [PrismaService, InventoryService],
  exports: [PrismaService, InventoryService],
})
export class InventoryServiceModule {}
```

- [ ] **Step 6: Run unit test to verify it passes**

Run: `cd apps/api && pnpm test apps/inventory-service/src/inventory.service.spec.ts`
Expected: PASS

- [ ] **Step 7: Commit backend core**

```bash
git add apps/api/apps/inventory-service
git commit -m "feat(inventory-service): Implement inventory service, controller and DTOs"
```

---

### Task 4: API Gateway Proxy & Port 3004 CORS Configuration

**Files:**
- Modify: `apps/api/apps/api-gateway/src/main.ts`

**Interfaces:**
- Consumes: Environment variable `INVENTORY_SERVICE_URL` (default `http://localhost:3003`)
- Produces: Proxy route `/api/inventory/*` -> `http://localhost:3003/inventory/*`, CORS access for port 3004

- [ ] **Step 1: Update API Gateway main.ts**

Update `apps/api/apps/api-gateway/src/main.ts`:
1. Add `'http://localhost:3004'` to CORS `origin` list.
2. Add `const inventoryServiceUrl = process.env.INVENTORY_SERVICE_URL || 'http://localhost:3003';`
3. Add reverse proxy route for `/api/inventory`:

```typescript
  // 5. Reverse Proxy: /api/inventory/* -> http://localhost:3003/inventory/*
  app.use(
    '/api/inventory',
    createProxyMiddleware({
      target: inventoryServiceUrl,
      changeOrigin: true,
      pathRewrite: (path) => `/inventory${path}`,
      on: {
        proxyReq: (proxyReq, req) => {
          const customReq = req as AuthenticatedRequest;
          fixRequestBody(proxyReq, req);

          let token = customReq.headers.authorization?.replace('Bearer ', '');
          if (!token && customReq.cookies) {
            token = customReq.cookies['access_token'];
          }

          if (token) {
            try {
              const payload = jwtService.verify(token, {
                secret: process.env.JWT_SECRET,
              });
              if (payload?.sub) proxyReq.setHeader('x-user-id', payload.sub);
              if (payload?.role) proxyReq.setHeader('x-user-role', payload.role);
              if (payload?.branchId)
                proxyReq.setHeader('x-user-branch-id', payload.branchId);
            } catch {}
          }
        },
      },
    }),
  );
```

- [ ] **Step 2: Build and verify api-gateway**

Run: `cd apps/api && pnpm nest build api-gateway`
Expected: Successfully compiled without TypeScript errors.

- [ ] **Step 3: Commit gateway proxy**

```bash
git add apps/api/apps/api-gateway/src/main.ts
git commit -m "feat(gateway): Add reverse proxy for inventory-service and allow port 3004 in CORS"
```

---

### Task 5: Admin Web Port 3004 Configuration & Inventory API Client

**Files:**
- Modify: `apps/admin-web/package.json`
- Create: `apps/admin-web/src/features/inventory/types.ts`
- Create: `apps/admin-web/src/features/inventory/schemas/inventory.schema.ts`
- Create: `apps/admin-web/src/features/inventory/api/inventory.api.ts`
- Create: `apps/admin-web/src/features/inventory/hooks/use-inventory.ts`
- Create: `apps/admin-web/src/features/inventory/index.ts`

**Interfaces:**
- Consumes: `/api/inventory` endpoints via `fetchApi`
- Produces: `useIngredients()`, `useInventoryTransactions()`, `useCreateIngredient()`, `useCreateTransaction()`

- [ ] **Step 1: Update package.json dev port to 3004**

In `apps/admin-web/package.json`:
Change `"dev": "next dev -p 3003"` to `"dev": "next dev -p 3004"`.

- [ ] **Step 2: Create Inventory Types and Zod Schemas**

Create `apps/admin-web/src/features/inventory/types.ts`:

```typescript
export type TransactionType = 'IN' | 'OUT';

export type TransactionReason =
  | 'INITIAL_STOCK'
  | 'PURCHASE'
  | 'KITCHEN_USAGE'
  | 'DISCARD_WASTE'
  | 'ADJUSTMENT';

export type StockAlertStatus = 'SAFE' | 'LOW_STOCK' | 'OUT_OF_STOCK';

export interface Ingredient {
  id: string;
  code: string;
  name: string;
  unit: string;
  currentStock: number;
  minStock: number;
  costPrice: number;
  status: StockAlertStatus;
  isAlert: boolean;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  _count?: {
    transactions: number;
  };
}

export interface InventoryTransaction {
  id: string;
  code: string;
  type: TransactionType;
  reason: TransactionReason;
  ingredientId: string;
  ingredient?: {
    code: string;
    name: string;
    unit: string;
  };
  quantity: number;
  unitPrice: number;
  totalAmount: number;
  note?: string | null;
  createdBy?: string | null;
  createdAt: string;
}

export interface CreateIngredientInput {
  code: string;
  name: string;
  unit: string;
  costPrice: number;
  minStock: number;
  initialStock?: number;
}

export interface CreateTransactionInput {
  type: TransactionType;
  reason: TransactionReason;
  ingredientId: string;
  quantity: number;
  unitPrice?: number;
  note?: string;
}
```

Create `apps/admin-web/src/features/inventory/schemas/inventory.schema.ts`:

```typescript
import { z } from 'zod';

export const createIngredientSchema = z.object({
  code: z
    .string()
    .min(2, 'Mã nguyên liệu tối thiểu 2 ký tự')
    .max(50, 'Mã nguyên liệu không vượt quá 50 ký tự')
    .toUpperCase(),
  name: z
    .string()
    .min(2, 'Tên nguyên liệu tối thiểu 2 ký tự')
    .max(160, 'Tên nguyên liệu không vượt quá 160 ký tự'),
  unit: z.string().min(1, 'Đơn vị tính không được để trống'),
  costPrice: z.number().min(0, 'Giá nhập tham chiếu phải lớn hơn hoặc bằng 0'),
  minStock: z.number().min(0, 'Định mức tồn tối thiểu phải lớn hơn hoặc bằng 0'),
  initialStock: z.number().min(0, 'Tồn đầu kỳ phải lớn hơn hoặc bằng 0').optional(),
});

export const createTransactionSchema = z.object({
  type: z.enum(['IN', 'OUT']),
  reason: z.enum(['INITIAL_STOCK', 'PURCHASE', 'KITCHEN_USAGE', 'DISCARD_WASTE', 'ADJUSTMENT']),
  ingredientId: z.string().uuid('Vui lòng chọn nguyên liệu hợp lệ'),
  quantity: z.number().positive('Số lượng xuất/nhập phải lớn hơn 0'),
  unitPrice: z.number().min(0, 'Đơn giá không được âm').optional(),
  note: z.string().max(500, 'Ghi chú tối đa 500 ký tự').optional(),
});
```

- [ ] **Step 3: Create API Service & TanStack Query Hooks**

Create `apps/admin-web/src/features/inventory/api/inventory.api.ts`:

```typescript
import { fetchApi } from '@/lib/api';
import {
  Ingredient,
  InventoryTransaction,
  CreateIngredientInput,
  CreateTransactionInput,
  TransactionType,
} from '../types';

export const inventoryApi = {
  getIngredients: () => fetchApi<Ingredient[]>('/api/inventory/ingredients'),
  getAlerts: () => fetchApi<Ingredient[]>('/api/inventory/alerts'),
  createIngredient: (dto: CreateIngredientInput) =>
    fetchApi<Ingredient>('/api/inventory/ingredients', {
      method: 'POST',
      body: JSON.stringify(dto),
    }),
  getTransactions: (type?: TransactionType, ingredientId?: string) => {
    const params = new URLSearchParams();
    if (type) params.set('type', type);
    if (ingredientId) params.set('ingredientId', ingredientId);
    const qs = params.toString();
    return fetchApi<InventoryTransaction[]>(`/api/inventory/transactions${qs ? `?${qs}` : ''}`);
  },
  createTransaction: (dto: CreateTransactionInput) =>
    fetchApi<InventoryTransaction>('/api/inventory/transactions', {
      method: 'POST',
      body: JSON.stringify(dto),
    }),
};
```

Create `apps/admin-web/src/features/inventory/hooks/use-inventory.ts`:

```typescript
'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { inventoryApi } from '../api/inventory.api';
import { CreateIngredientInput, CreateTransactionInput, TransactionType } from '../types';
import { message } from '@/components/ui';

export const inventoryKeys = {
  all: ['inventory'] as const,
  ingredients: () => [...inventoryKeys.all, 'ingredients'] as const,
  alerts: () => [...inventoryKeys.all, 'alerts'] as const,
  transactions: (type?: TransactionType) => [...inventoryKeys.all, 'transactions', type] as const,
};

export function useIngredients() {
  return useQuery({
    queryKey: inventoryKeys.ingredients(),
    queryFn: () => inventoryApi.getIngredients(),
  });
}

export function useInventoryAlerts() {
  return useQuery({
    queryKey: inventoryKeys.alerts(),
    queryFn: () => inventoryApi.getAlerts(),
  });
}

export function useInventoryTransactions(type?: TransactionType) {
  return useQuery({
    queryKey: inventoryKeys.transactions(type),
    queryFn: () => inventoryApi.getTransactions(type),
  });
}

export function useCreateIngredient() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (dto: CreateIngredientInput) => inventoryApi.createIngredient(dto),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: inventoryKeys.all });
      message.success(`Thêm nguyên liệu "${data.name}" thành công!`);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Không thể tạo nguyên liệu';
      message.error(msg);
    },
  });
}

export function useCreateTransaction() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (dto: CreateTransactionInput) => inventoryApi.createTransaction(dto),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: inventoryKeys.all });
      const actionLabel = data.type === 'IN' ? 'Nhập kho' : 'Xuất kho';
      message.success(`${actionLabel} thành công! Mã phiếu: ${data.code}`);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Giao dịch kho thất bại';
      message.error(msg);
    },
  });
}
```

Create `apps/admin-web/src/features/inventory/index.ts`:

```typescript
export * from './types';
export * from './schemas/inventory.schema';
export { inventoryApi } from './api/inventory.api';
export {
  useIngredients,
  useInventoryAlerts,
  useInventoryTransactions,
  useCreateIngredient,
  useCreateTransaction,
  inventoryKeys,
} from './hooks/use-inventory';
```

- [ ] **Step 4: Commit frontend client layer**

```bash
git add apps/admin-web/package.json apps/admin-web/src/features/inventory
git commit -m "feat(inventory-client): Add inventory types, zod schemas, API and TanStack Query hooks"
```

---

### Task 6: Admin Web Inventory UI Components & Dashboard Page

**Files:**
- Modify: `apps/admin-web/src/config/navigation.config.ts`
- Modify: `apps/admin-web/src/locales/vi.json`
- Modify: `apps/admin-web/src/locales/en.json`
- Create: `apps/admin-web/src/features/inventory/components/stock-balance-table.tsx`
- Create: `apps/admin-web/src/features/inventory/components/stock-transaction-table.tsx`
- Create: `apps/admin-web/src/features/inventory/components/create-ingredient-modal.tsx`
- Create: `apps/admin-web/src/features/inventory/components/create-transaction-modal.tsx`
- Create: `apps/admin-web/src/app/(dashboard)/dashboard/inventory/page.tsx`

**Interfaces:**
- Consumes: `useIngredients()`, `useInventoryTransactions()`, `useCreateIngredient()`, `useCreateTransaction()`
- Produces: `/dashboard/inventory` route and navigation link in Admin Sidebar

- [ ] **Step 1: Add i18n keys and Navigation Item**

In `apps/admin-web/src/config/navigation.config.ts`:
Add `CookingPot` icon import and add `inventory` item:

```typescript
  {
    key: 'inventory',
    path: '/dashboard/inventory',
    labelKey: 'dashboard.menuInventory',
    icon: CookingPot,
  },
```

In `apps/admin-web/src/locales/vi.json`:
Add keys for inventory:
- `"menuInventory": "Kho Nguyên Liệu"`
- `"inventoryTitle": "Quản Lý Kho Nguyên Liệu"`
- `"inventorySubtitle": "Theo dõi nhập - xuất - tồn và cảnh báo nguyên vật liệu chế biến"`
- `"stockIn": "Nhập Kho"`
- `"stockOut": "Xuất Kho"`
- `"addIngredient": "Thêm Nguyên Liệu"`
- `"tabStockBalance": "Tồn Kho & Cảnh Báo"`
- `"tabStockInHistory": "Lịch Sử Nhập Kho"`
- `"tabStockOutHistory": "Lịch Sử Xuất Kho"`
- `"alertSafe": "An Toàn"`
- `"alertLow": "Sắp Hết"`
- `"alertOut": "Đã Hết Hàng"`
- `"initialStock": "Tồn đầu kỳ"`
- `"minStock": "Định mức tối thiểu"`

In `apps/admin-web/src/locales/en.json`:
Add corresponding English translations.

- [ ] **Step 2: Create StockBalanceTable component**

Create `apps/admin-web/src/features/inventory/components/stock-balance-table.tsx`:
- Render columns: Mã nguyên liệu, Tên nguyên liệu, Đơn vị tính, Tồn thực tế (bold, font-mono), Định mức tối thiểu, Trạng thái cảnh báo 3 mức:
  - `OUT_OF_STOCK`: Red pulsing tag `Đã Hết Hàng`
  - `LOW_STOCK`: Amber tag `Sắp Hết`
  - `SAFE`: Emerald tag `An Toàn`
- Actions column with quick buttons: "Nhập thêm" / "Xuất kho".

- [ ] **Step 3: Create StockTransactionTable component**

Create `apps/admin-web/src/features/inventory/components/stock-transaction-table.tsx`:
- Render columns: Mã phiếu, Loại giao dịch (Tag `PNK` xanh/ `PXK` vàng), Tên nguyên liệu, Số lượng phát sinh (kèm đơn vị), Đơn giá, Thành tiền, Lý do, Ghi chú, Ngày lập.

- [ ] **Step 4: Create Modals with Zod Validation**

Create `apps/admin-web/src/features/inventory/components/create-ingredient-modal.tsx`:
- Form inputs: Mã (NL-...), Tên nguyên liệu, Đơn vị tính, Giá nhập tham chiếu, Định mức tồn tối thiểu (`minStock`), Số lượng tồn đầu kỳ (`initialStock`).

Create `apps/admin-web/src/features/inventory/components/create-transaction-modal.tsx`:
- Switchable mode: `IN` (Nhập kho) or `OUT` (Xuất kho).
- Dropdown select ingredient (showing current stock).
- Quantity input with maximum constraint check if mode is `OUT`.
- Reason select (Nhập mua, Xuất bếp, Xuất hủy).
- Unit price input (for stock in).
- Note input.

- [ ] **Step 5: Create `/dashboard/inventory/page.tsx`**

Create `apps/admin-web/src/app/(dashboard)/dashboard/inventory/page.tsx`:
- Render `SushiPageHeader` with title, subtitle, and top action buttons (`+ Nhập Kho`, `- Xuất Kho`, `+ Thêm Nguyên Liệu`).
- 4 Bento KPI Cards:
  1. Tổng số nguyên liệu
  2. Số mặt hàng đang cảnh báo (Đỏ/Vàng)
  3. Lượt phiếu Nhập kho
  4. Lượt phiếu Xuất kho
- Tabs container with Tab 1 (Tồn Kho & Cảnh Báo), Tab 2 (Lịch Sử Nhập Kho), Tab 3 (Lịch Sử Xuất Kho).
- Modals wired to mutations with automatic query cache invalidation.

- [ ] **Step 6: Build & Verify Admin Web**

Run: `cd apps/admin-web && pnpm build`
Expected: Build passes with 0 errors, route `/dashboard/inventory` generated.

- [ ] **Step 7: Commit Inventory UI**

```bash
git add apps/admin-web
git commit -m "feat(inventory-ui): Implement inventory management dashboard, tables, and modals"
```

---

### Task 7: End-to-End Integration & Verification

**Files:**
- Test: All microservices and frontend build

- [ ] **Step 1: Test NestJS build for all API projects**

Run: `cd apps/api && pnpm nest build inventory-service && pnpm nest build api-gateway`
Expected: All projects compile with 0 errors.

- [ ] **Step 2: Test Admin Web build**

Run: `cd apps/admin-web && pnpm build`
Expected: Turbopack and TypeScript build clean.

- [ ] **Step 3: Commit and Push**

Commit submodules and root repository with final integration commit and push to remote.
