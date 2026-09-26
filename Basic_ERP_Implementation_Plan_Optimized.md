# Basic ERP — Optimized Implementation Plan

## 1. Goal

Build a practical V1 ERP that is:

- Simple enough for a small team to develop and maintain.
- Ready for multiple organizations/tenants without introducing unnecessary infrastructure.
- Frontend/backend separated into two top-level applications.
- Backed by remote Neon PostgreSQL.
- Deployable from GitHub to Render for the backend.
- Focused on one complete business flow first: Customer → Quote → Order → Invoice → Payment → Inventory update.

The original plan included enterprise infrastructure such as Redis, background workers, S3 storage, subscriptions, and multiple clients. For a basic ERP V1, these are deferred until there is a real need.

---

# 2. Recommended Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter |
| State Management | Riverpod |
| Routing | go_router |
| Backend | NestJS + TypeScript |
| API | REST |
| ORM | Prisma |
| Database | PostgreSQL on Neon |
| Authentication | JWT + refresh token |
| Deployment | Render |
| Source Control | GitHub |
| API Documentation | Swagger / OpenAPI |
| Validation | class-validator |
| Password Hashing | Argon2 or bcrypt |
| Logging | NestJS/server logs |

### V1 infrastructure

```text
Flutter App
     |
 HTTPS / REST
     |
     v
NestJS API on Render
     |
     v
Neon PostgreSQL
```

Do not add Redis, BullMQ, S3, microservices, or a separate worker service in V1.

---

# 3. Repository Structure

Use two clear application folders rather than the larger monorepo structure.

```text
basic-erp/
│
├── frontend/
│   ├── lib/
│   │   ├── app/
│   │   │   ├── app.dart
│   │   │   ├── router/
│   │   │   └── theme/
│   │   │
│   │   ├── core/
│   │   │   ├── network/
│   │   │   ├── auth/
│   │   │   ├── storage/
│   │   │   ├── errors/
│   │   │   └── utils/
│   │   │
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── dashboard/
│   │   │   ├── organization/
│   │   │   ├── users/
│   │   │   ├── customers/
│   │   │   ├── products/
│   │   │   ├── inventory/
│   │   │   ├── sales/
│   │   │   ├── payments/
│   │   │   └── settings/
│   │   │
│   │   └── shared/
│   │       ├── widgets/
│   │       ├── models/
│   │       ├── enums/
│   │       └── formatters/
│   │
│   ├── assets/
│   ├── test/
│   └── pubspec.yaml
│
├── backend/
│   ├── src/
│   │   ├── main.ts
│   │   │
│   │   ├── config/
│   │   │   ├── env.config.ts
│   │   │   └── database.config.ts
│   │   │
│   │   ├── common/
│   │   │   ├── guards/
│   │   │   ├── decorators/
│   │   │   ├── filters/
│   │   │   ├── interceptors/
│   │   │   └── utils/
│   │   │
│   │   ├── auth/
│   │   ├── organization/
│   │   ├── users/
│   │   ├── customers/
│   │   ├── products/
│   │   ├── inventory/
│   │   ├── sales/
│   │   ├── payments/
│   │   ├── dashboard/
│   │   └── audit/
│   │
│   ├── prisma/
│   │   ├── schema.prisma
│   │   ├── migrations/
│   │   └── seed.ts
│   │
│   ├── test/
│   ├── .env.example
│   ├── package.json
│   └── tsconfig.json
│
├── .gitignore
├── README.md
└── .github/
    └── workflows/
        └── backend-ci.yml
```

This keeps the project easy to navigate:

```text
frontend = Flutter application
backend  = NestJS API + Prisma + database schema
```

---

# 4. Frontend Architecture

Use feature-first organization.

Each feature should look approximately like:

```text
customers/
├── data/
│   ├── customer_api.dart
│   ├── customer_model.dart
│   └── customer_repository.dart
│
├── presentation/
│   ├── pages/
│   ├── widgets/
│   └── providers/
│
└── domain/
    └── entities/
```

For a basic ERP, do not force every feature into a large Clean Architecture structure. Keep the separation where it provides value.

### Main frontend sections

```text
Auth
Dashboard
Organization
Users
Customers
Products
Inventory
Sales
Payments
Settings
```

### Basic UI pattern

Desktop/Web:

```text
Sidebar
   |
   +-- Dashboard
   +-- Customers
   +-- Products
   +-- Inventory
   +-- Sales
   +-- Payments
   +-- Users
   +-- Settings
```

Mobile:

```text
Dashboard
Quick Actions
Pending Items
Recent Transactions
```

Use the same API and business rules across clients.

---

# 5. Backend Architecture

Use a modular NestJS monolith.

```text
backend/src/
├── auth/
├── organization/
├── users/
├── customers/
├── products/
├── inventory/
├── sales/
├── payments/
├── dashboard/
└── audit/
```

Each module should generally contain:

```text
module.ts
controller.ts
service.ts
dto/
```

Example:

```text
sales/
├── sales.module.ts
├── sales.controller.ts
├── sales.service.ts
└── dto/
    ├── create-quotation.dto.ts
    ├── create-order.dto.ts
    └── create-invoice.dto.ts
```

Use Prisma directly from the service layer initially. Add repository abstractions only when a module actually needs them.

---

# 6. Multi-Tenancy — Simplified

Keep the shared Neon database model from the original architecture, but simplify the implementation.

Conceptually:

```text
Neon PostgreSQL
│
├── Organization A
│   ├── users
│   ├── customers
│   ├── products
│   └── invoices
│
├── Organization B
│   ├── users
│   ├── customers
│   ├── products
│   └── invoices
│
└── Organization C
```

Every tenant-owned table should contain:

```text
organization_id UUID
```

Use `organization_id` instead of introducing a separate `tenant_id` and `company_id` concept in V1.

### Core tables

```text
organizations
users
```

For basic RBAC, start with a role on the user/organization membership:

```text
ADMIN
MANAGER
STAFF
ACCOUNTANT
```

Do not build a full dynamic permission matrix in V1.

Later, this can become:

```text
roles
permissions
role_permissions
user_roles
```

### Critical rule

The backend determines the organization from the authenticated session. Never trust an arbitrary organization ID supplied by the Flutter client.

---

# 7. Authentication

V1 flow:

```text
Login
  ↓
Validate email/password
  ↓
Create access token
  ↓
Create refresh token
  ↓
Flutter stores tokens securely
  ↓
API requests use Bearer token
```

Required endpoints:

```text
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
GET  /api/v1/auth/me
```

Use secure token storage on Flutter.

---

# 8. Core Database

Keep the first schema small.

## Organization

```text
organizations
--------------
id
name
slug
email
phone
address
currency
timezone
created_at
updated_at
```

## Users

```text
users
-----
id
organization_id
name
email
password_hash
role
status
created_at
updated_at
```

## Customers

```text
customers
---------
id
organization_id
name
email
phone
address
tax_number
status
created_at
updated_at
```

## Products

```text
products
--------
id
organization_id
name
sku
category_id
unit
sale_price
cost_price
tax_rate
status
created_at
updated_at
```

## Inventory

```text
warehouses
----------
id
organization_id
name
location

stock_movements
---------------
id
organization_id
product_id
warehouse_id
movement_type
quantity
reference_type
reference_id
created_at
```

Do not make inventory a manually edited `stock` number only. Record movements.

## Sales

```text
quotations
quotation_items

sales_orders
sales_order_items

invoices
invoice_items

payments
```

Every business table that belongs to an organization should carry `organization_id`.

---

# 9. Basic V1 Modules

## Module 1 — Authentication

- Register
- Login
- Logout
- Refresh token
- Current user
- Password change

## Module 2 — Organization

- Organization profile
- Basic settings
- Users
- Roles

## Module 3 — Customers

- Create
- List
- Search
- Edit
- View details
- Disable

## Module 4 — Products

- Create
- List
- Search
- Categories
- SKU
- Price
- Tax
- Disable

## Module 5 — Inventory

- Warehouses
- Stock movements
- Stock balance calculation
- Stock adjustment
- Low-stock indicator

## Module 6 — Sales

```text
Customer
   ↓
Quotation
   ↓
Sales Order
   ↓
Invoice
   ↓
Payment
```

For V1, keep delivery/dispatch optional unless the business actually requires it.

## Module 7 — Dashboard

Show only useful KPIs:

```text
Total Customers
Total Products
Sales This Month
Outstanding Invoices
Payments This Month
Low Stock Products
```

---

# 10. API Structure

Prefix all endpoints with:

```text
/api/v1
```

Examples:

```text
GET    /api/v1/customers
GET    /api/v1/customers/:id
POST   /api/v1/customers
PATCH  /api/v1/customers/:id

GET    /api/v1/products
POST   /api/v1/products

GET    /api/v1/invoices
POST   /api/v1/invoices
GET    /api/v1/invoices/:id

POST   /api/v1/invoices/:id/submit
POST   /api/v1/invoices/:id/cancel

POST   /api/v1/payments
```

Business actions should have explicit endpoints rather than allowing arbitrary status updates.

---

# 11. Document States

Keep the lifecycle small:

```text
DRAFT
  ↓
CONFIRMED
  ↓
COMPLETED
  ↓
CANCELLED
```

For invoices:

```text
DRAFT
  ↓
POSTED
  ↓
PAID
```

The backend validates every state transition.

---

# 12. Document Numbers

Use human-readable document numbers.

Examples:

```text
QUO-2026-00001
SO-2026-00001
INV-2026-00001
PAY-2026-00001
```

Store the database UUID separately.

For V1, a simple sequence mechanism is sufficient. Avoid building an elaborate numbering engine until the business requirements are known.

---

# 13. Inventory Rules

Inventory should be event/movement based.

Example:

```text
PURCHASE       +100
SALE            -10
RETURN           +2
ADJUSTMENT       -1
TRANSFER OUT     -5
TRANSFER IN      +5
```

Available stock can be calculated from movements.

Every movement should contain a reference to the business event that caused it.

---

# 14. Finance Scope for Basic ERP

Do not build a full accounting platform in the first release.

V1 finance should cover:

```text
Payments received
Expenses
Outstanding invoices
Basic income summary
Basic expense summary
```

Defer:

```text
Full chart of accounts
Double-entry general ledger
Bank reconciliation
Fiscal periods
Advanced tax reports
Accounts payable
Accounts receivable engine
```

These can be Phase 2/3 features after the sales and inventory workflow is stable.

---

# 15. Audit Logging

Keep a lightweight audit table:

```text
audit_logs
----------
id
organization_id
user_id
action
entity_type
entity_id
created_at
```

Log important operations:

```text
LOGIN
CREATE
UPDATE
DELETE
INVOICE_POST
PAYMENT_CREATE
STOCK_ADJUST
USER_ROLE_CHANGE
```

Do not overbuild audit infrastructure in V1.

---

# 16. Validation and Security

Required backend protections:

```text
HTTPS
JWT authentication
Password hashing
Input validation
CORS
Rate limiting
RBAC
Organization isolation
Environment-based secrets
Prisma/parameterized queries
Audit logging
```

Most important test:

```text
User from Organization A
        ↓
Requests Organization B data
        ↓
403/404
        ↓
No data returned
```

Never rely on Flutter UI restrictions as security.

---

# 17. Pagination and Search

All large lists must be server-side paginated.

Example:

```text
GET /api/v1/invoices?page=1&limit=20&search=acme
```

Backend handles:

```text
pagination
search
filtering
sorting
```

Do not load thousands of rows into Flutter at once.

---

# 18. Neon PostgreSQL Setup

Use Neon as the remote PostgreSQL database.

Backend environment:

```env
DATABASE_URL=your_neon_connection_string
JWT_SECRET=your_secret
CORS_ORIGINS=https://your-frontend-domain
PORT=3000
```

Prisma:

```text
backend/prisma/schema.prisma
backend/prisma/migrations/
```

Typical workflow:

```bash
npx prisma generate
npx prisma migrate dev
npx prisma db seed
```

Production:

```bash
npx prisma migrate deploy
```

Use separate database environments/branches for development and production when practical.

Do not expose `DATABASE_URL` to Flutter.

---

# 19. Render Backend Deployment

Deploy only the backend API as a Render Web Service.

Repository:

```text
basic-erp/
├── frontend/
└── backend/
```

Render service root directory:

```text
backend
```

Build command:

```bash
npm ci && npx prisma generate && npx prisma migrate deploy && npm run build
```

Start command:

```bash
npm run start:prod
```

NestJS should listen on:

```ts
process.env.PORT || 3000
```

Set these Render environment variables:

```text
DATABASE_URL
JWT_SECRET
CORS_ORIGINS
NODE_ENV=production
```

The Flutter app calls:

```text
https://your-render-service.onrender.com/api/v1
```

---

# 20. Frontend Deployment

The frontend remains independent from the backend.

For Flutter:

### Mobile

```bash
flutter build apk
```

or release builds for the required mobile platform.

### Web

```bash
flutter build web
```

Deploy the generated `build/web` directory to a static hosting provider.

The frontend only needs the public API base URL.

Example:

```text
API_BASE_URL=https://your-render-service.onrender.com/api/v1
```

---

# 21. Development Workflow

Run the two applications separately.

### Backend

```bash
cd backend
npm install
npx prisma generate
npm run start:dev
```

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

Development architecture:

```text
Flutter
   |
   | HTTP
   v
NestJS localhost
   |
   | PostgreSQL
   v
Neon
```

This avoids maintaining a local database when you specifically want Neon as the database platform.

---

# 22. Implementation Phases

## Phase 0 — Project Setup

```text
✓ GitHub repository
✓ frontend/
✓ backend/
✓ NestJS setup
✓ Flutter setup
✓ Prisma setup
✓ Neon connection
✓ Environment variables
✓ Basic API structure
```

## Phase 1 — Authentication + Organization

```text
✓ Registration
✓ Login
✓ JWT
✓ Refresh token
✓ Organization
✓ Users
✓ Basic roles
```

Definition of done:

A user can log in and access only their organization.

## Phase 2 — Master Data

```text
✓ Customers
✓ Products
✓ Categories
✓ Units
```

Definition of done:

Customers and products can be created and reused by sales.

## Phase 3 — Sales

```text
✓ Quotations
✓ Sales orders
✓ Invoices
✓ Payments
```

Complete flow:

```text
Customer
→ Quote
→ Order
→ Invoice
→ Payment
```

## Phase 4 — Inventory

```text
✓ Warehouse
✓ Stock movements
✓ Stock balance
✓ Adjustments
✓ Low-stock indicator
```

Integrate:

```text
Sales → Inventory
```

## Phase 5 — Dashboard + Basic Finance

```text
✓ Sales summary
✓ Payment summary
✓ Expenses
✓ Outstanding invoices
✓ Low-stock dashboard
```

## Phase 6 — Security + Production

```text
✓ Validation
✓ Authorization tests
✓ Organization isolation tests
✓ API tests
✓ Migration verification
✓ Render deployment
✓ Production environment
✓ Monitoring/logging
```

---

# 23. What to Defer

Do not build these in the first release unless the business requires them immediately:

```text
Redis
BullMQ
Background workers
S3/object storage
Microservices
Offline-first synchronization
Subscription billing
SaaS usage metering
Advanced RBAC
Payroll
Advanced HR
Full accounting/GL
Bank reconciliation
Complex approval engine
Advanced notifications
Desktop-specific features
```

This is the biggest optimization of the original plan.

---

# 24. V1 Scope

The first production version should be:

```text
BASIC ERP
│
├── Authentication
├── Organization
├── Users / Roles
│
├── Customers
├── Products
├── Categories
│
├── Inventory
│   ├── Warehouse
│   ├── Stock
│   └── Movements
│
├── Sales
│   ├── Quotations
│   ├── Sales Orders
│   ├── Invoices
│   └── Payments
│
├── Basic Finance
│   ├── Expenses
│   └── Income Summary
│
├── Dashboard
└── Audit Logs
```

This gives you a real working ERP without prematurely implementing an entire enterprise platform.

---

# 25. Immediate Build Order

```text
STEP 01
Create repository
       ↓
STEP 02
Create frontend/ and backend/
       ↓
STEP 03
Setup NestJS
       ↓
STEP 04
Setup Flutter
       ↓
STEP 05
Create Neon PostgreSQL database
       ↓
STEP 06
Connect Prisma to Neon
       ↓
STEP 07
Create organization + users
       ↓
STEP 08
Implement authentication
       ↓
STEP 09
Implement customers
       ↓
STEP 10
Implement products
       ↓
STEP 11
Implement quotations
       ↓
STEP 12
Implement sales orders
       ↓
STEP 13
Implement invoices
       ↓
STEP 14
Implement payments
       ↓
STEP 15
Implement inventory movements
       ↓
STEP 16
Implement dashboard
       ↓
STEP 17
Add audit logging
       ↓
STEP 18
Security/E2E testing
       ↓
STEP 19
Deploy backend to Render
       ↓
STEP 20
Deploy Flutter web / build mobile app
```

---

# 26. Final Architecture

```text
                    ┌─────────────────────┐
                    │   Flutter Frontend  │
                    │      frontend/      │
                    └──────────┬──────────┘
                               │
                            HTTPS
                               │
                               ▼
                    ┌─────────────────────┐
                    │    NestJS Backend   │
                    │      backend/       │
                    │      Render         │
                    └──────────┬──────────┘
                               │
                            Prisma
                               │
                               ▼
                    ┌─────────────────────┐
                    │   Neon PostgreSQL   │
                    │    Remote Database  │
                    └─────────────────────┘
```

## Core design principle

Keep V1 as:

```text
Flutter
+
NestJS Modular Monolith
+
Prisma
+
Neon PostgreSQL
+
Render
```

Build the complete business workflow first. Add infrastructure only when a real requirement justifies it. 
