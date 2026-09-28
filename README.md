# Basic ERP (V1)

A practical multi-tenant ERP for small teams: **Customer → Quotation → Sales Order → Invoice → Payment → Inventory**.

| Layer | Tech |
|---|---|
| Frontend | Flutter (Riverpod, go_router, dio) |
| Backend | NestJS + TypeScript (modular monolith) |
| ORM | Prisma (pinned 6.19.3) |
| Database | PostgreSQL on Neon |
| Auth | JWT access + refresh tokens (server-side refresh tokens) |
| Docs | Swagger at `/api/v1` → `api/docs` |

## Repository layout

```text
backend/   NestJS API + Prisma schema/seed/e2e tests
frontend/  Flutter app (web / windows / android)
```

## Prerequisites

- Node.js 20+ and npm
- Flutter SDK (stable)
- A Neon PostgreSQL database (or any Postgres 14+)

## Backend — setup & run

```bash
cd backend
npm install
cp .env.example .env        # then fill in DATABASE_URL + JWT secrets
npx prisma generate
npx prisma migrate deploy    # or: npx prisma migrate dev --name init (dev)
npx prisma db seed           # creates the demo org
npm run start:dev            # http://localhost:3000/api/v1
```

Key `.env` values:

```env
DATABASE_URL=postgresql://user:pass@host/db
JWT_ACCESS_SECRET=<long random string>
JWT_REFRESH_SECRET=<long random string>
JWT_ACCESS_EXPIRES="15m"
JWT_REFRESH_EXPIRES="30d"
CORS_ORIGINS="http://localhost:3000,http://localhost:5173"
PORT=3000
```

### Seeded demo account

```text
email:    admin@acme.com
password: Admin@123
```
(plus sample categories, units, products, warehouse, stock, customer)

### Backend tests & checks

```bash
npm run lint        # oxlint
npm run test:e2e    # 12 end-to-end tests against the configured database (Neon)
npx tsc --noEmit -p tsconfig.build.json
npm run build
```

> The e2e suite registers temporary organizations and writes data to the
> database configured in `.env`. Run it against a development Neon branch,
> not production.

## Frontend — setup & run

```bash
cd frontend
flutter pub get
flutter run -d windows      # or -d chrome / an Android device
```

API base URL defaults to `http://localhost:3000/api/v1`. Override at build/run time:

```bash
flutter run --dart-define=API_BASE_URL=https://your-api.example.com/api/v1
```

### Frontend checks

```bash
flutter analyze
flutter test
flutter build web           # output in build/web (deployable to any static host)
flutter build apk --release # Android
```

## What V1 covers

- Auth (register, login, refresh, logout, me, change password)
- Organization profile + users (ADMIN / MANAGER / STAFF / ACCOUNTANT)
- Customers, Product categories/units, Products
- Quotations, Sales orders, Invoices (draft → posted → paid; direct + from order; post/pay/cancel with stock events)
- Payments (overpayment blocked, anti-duplicate), outstanding balances
- Expenses
- Inventory: warehouses, movements (sale/purchase/adjust/transfer/return), low-stock
- Stock actions: receive, adjust and transfer stock from the Inventory screen
- Dashboard KPIs, audit log
- Health check at `GET /api/v1/health` (public, verifies the database connection)

Every tenant-owned table carries `organization_id`; the backend derives the
org from the JWT (never from the client) and a global tenant extension scopes
all Prisma queries, so users only ever see their own organization's data.

## Security protections

HTTPS (terminated upstream), helmet, CORS allow-list, throttling, JWT auth,
bcrypt hashing, class-validator whitelist, RBAC roles, tenant isolation,
server-side audit logs, parameterized Prisma queries, secrets via environment.

## Deployment notes

**Backend (Render Web Service)**
- Root directory: `backend`
- Build: `npm ci && npx prisma generate && npx prisma migrate deploy && npm run build`
- Start: `npm run start:prod`
- Env vars: `DATABASE_URL`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
  `CORS_ORIGINS` (frontend origin(s)), `NODE_ENV=production`
- Health check path: `/api/v1/health`
- A `render.yaml` blueprint is included in the repo.

**Frontend**
- `flutter build web` → host `build/web` on any static host (Vercel/Netlify/Cloudflare Pages).
- Point `API_BASE_URL` at the deployed API.

## Deferred (out of V1)

Redis, queues/workers, object storage, microservices, offline sync, advanced
RBAC, payroll/HR, full double-entry accounting/GL, bank reconciliation.

Stock can be received without a purchase document: "Receive stock" records a
`PURCHASE` movement against a product and warehouse. Suppliers, purchase orders
and accounts payable are not modelled.

See `Basic_ERP_Implementation_Plan_Optimized.md` for the full plan.