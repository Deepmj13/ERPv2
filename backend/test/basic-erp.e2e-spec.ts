import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module.js';

let suffix = Date.now().toString(36);
let orgA = { name: `TestOrgA-${suffix}`, slug: `testorga-${suffix}` };
let orgB = { name: `TestOrgB-${suffix}`, slug: `testorgb-${suffix}` };
let emailA = `a-${suffix}@test.local`;
let emailB = `b-${suffix}@test.local`;

describe('Basic ERP (e2e)', () => {
  let app: INestApplication<App>;
  let tokenA: string;
  let tokenB: string;

  let customerAId: string;
  let customerBId: string;
  let productAId: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api/v1');
    app.useLogger(false);
    await app.init();
  });

const api = (token?: string) => {
  const base = request(app.getHttpServer());
  const wrap =
    (verb: 'get' | 'post' | 'patch' | 'delete') =>
    (path: string) => {
      const req = base[verb](path);
      if (token) req.set('Authorization', `Bearer ${token}`);
      return req;
    };
  return {
    get: wrap('get'),
    post: wrap('post'),
    patch: wrap('patch'),
    delete: wrap('delete'),
  };
};

  describe('health', () => {
    it('is public and reports the database connection', async () => {
      const res = await api().get('/api/v1/health').expect(200);
      expect(res.body.status).toBe('ok');
      expect(res.body.database).toBe('up');
      expect(typeof res.body.uptime).toBe('number');
    });
  });

  describe('auth', () => {
    it('registers two organizations and returns tokens', async () => {
      const ra = await api().post('/api/v1/auth/register').send({
        organizationName: orgA.name,
        organizationSlug: orgA.slug,
        name: 'Admin A',
        email: emailA,
        password: 'password1',
      });
      expect(ra.status).toBe(201);
      expect(ra.body.accessToken).toBeTruthy();
      tokenA = ra.body.accessToken;

      const rb = await api().post('/api/v1/auth/register').send({
        organizationName: orgB.name,
        organizationSlug: orgB.slug,
        name: 'Admin B',
        email: emailB,
        password: 'password1',
      });
      expect(rb.status).toBe(201);
      tokenB = rb.body.accessToken;
    });

    it('rejects duplicate email and duplicate slug', async () => {
      const dupEmail = await api().post('/api/v1/auth/register').send({
        organizationName: 'X',
        organizationSlug: `x-${suffix}`,
        name: 'X',
        email: emailA,
        password: 'password1',
      });
      expect(dupEmail.status).toBe(409);

      const dupSlug = await api().post('/api/v1/auth/register').send({
        organizationName: 'X',
        organizationSlug: orgA.slug,
        name: 'X',
        email: `x-${suffix}@test.local`,
        password: 'password1',
      });
      expect(dupSlug.status).toBe(409);
    });

    it('rejects bad login', async () => {
      const res = await api().post('/api/v1/auth/login').send({
        email: emailA,
        password: 'wrong-password',
      });
      expect(res.status).toBe(401);
    });

    it('returns /me', async () => {
      const res = await api(tokenA).get('/api/v1/auth/me');
      expect(res.status).toBe(200);
      expect(res.body.user.organizationId).toBeTruthy();
      expect(res.body.organization.slug).toBe(orgA.slug);
    });
  });

  describe('tenant isolation', () => {
    it('org A cannot read org B customers', async () => {
      const bCust = await api(tokenB).post('/api/v1/customers').send({
        name: 'B-only customer',
        email: `b-only-${suffix}@test.local`,
      });
      expect(bCust.status).toBe(201);
      customerBId = bCust.body.id;

      const aReadB = await api(tokenA).get(`/api/v1/customers/${customerBId}`);
      expect([403, 404]).toContain(aReadB.status);
    });

    it('org A cannot update org B customers', async () => {
      const res = await api(tokenA)
        .patch(`/api/v1/customers/${customerBId}`)
        .send({ name: 'Hacked' });
      expect([403, 404]).toContain(res.status);
    });

    it('org lists only contain their own data', async () => {
      const aList = await api(tokenA).get('/api/v1/customers');
      const bList = await api(tokenB).get('/api/v1/customers');
      const aIds = aList.body.items.map((c: any) => c.id);
      const bIds = bList.body.items.map((c: any) => c.id);
      const overlap = aIds.filter((x: string) => bIds.includes(x));
      expect(overlap.length).toBe(0);
    });
  });

  describe('master data + sales flow', () => {
    it('creates customer, category, product, warehouse in org A', async () => {
      const cust = await api(tokenA).post('/api/v1/customers').send({ name: 'Acme Buyer', email: 'buyer@acme.test' });
      expect(cust.status).toBe(201);
      customerAId = cust.body.id;

      const cat = await api(tokenA).post('/api/v1/categories').send({ name: 'Gadgets' });
      expect(cat.status).toBe(201);

      const prod = await api(tokenA).post('/api/v1/products').send({
        name: 'Product A',
        sku: `SKU-A-${suffix}`,
        categoryId: cat.body.id,
        salePrice: 100,
        costPrice: 60,
        taxRate: 10,
      });
      expect(prod.status).toBe(201);
      productAId = prod.body.id;

      await api(tokenA).post('/api/v1/warehouses').send({ name: 'Main A' }).expect(201);

      await api(tokenA)
        .post('/api/v1/inventory/adjustments')
        .send({ productId: productAId, quantity: 100, note: 'opening' })
        .expect(201);
    });

    it(
      'runs quote -> order -> invoice -> payment and moves stock',
      async () => {
        const quote = await api(tokenA).post('/api/v1/quotations').send({
          customerId: customerAId,
          items: [{ productId: productAId, quantity: 5, unitPrice: 100, taxRate: 10 }],
        });
        expect(quote.status).toBe(201);
        expect(quote.body.number).toMatch(/^QUO-\d{4}-/);
        expect(quote.body.status).toBe('DRAFT');
        const quoteId = quote.body.id;

        await api(tokenA).post(`/api/v1/quotations/${quoteId}/submit`).expect(201);
        const order = await api(tokenA)
          .post(`/api/v1/quotations/${quoteId}/convert`)
          .expect(201);
        expect(order.body.number).toMatch(/^SO-/);
        expect(order.body.status).toBe('CONFIRMED');
        const orderId = order.body.id;

        const invoice = await api(tokenA)
          .post(`/api/v1/sales-orders/${orderId}/create-invoice`)
          .expect(201);
        expect(invoice.body.number).toMatch(/^INV-/);
        expect(Number(invoice.body.totalAmount)).toBe(550);
        const invoiceId = invoice.body.id;

        // stock is 100; none moved yet (invoice still DRAFT)
        let stock = await api(tokenA)
          .get(`/api/v1/inventory/products/${productAId}/stock`)
          .expect(200);
        expect(Number(stock.body.balance)).toBe(100);

        await api(tokenA).post(`/api/v1/invoices/${invoiceId}/post`).expect(201);
        stock = await api(tokenA)
          .get(`/api/v1/inventory/products/${productAId}/stock`)
          .expect(200);
        expect(Number(stock.body.balance)).toBe(95);

        const out = await api(tokenA)
          .get(`/api/v1/invoices/${invoiceId}/outstanding`)
          .expect(200);
        expect(Number(out.body.outstanding)).toBe(550);

        const payment = await api(tokenA)
          .post('/api/v1/payments')
          .send({ invoiceId, amount: 550, method: 'BANK_TRANSFER' })
          .expect(201);
        expect(payment.body.number).toMatch(/^PAY-/);

        const paid = await api(tokenA)
          .get(`/api/v1/invoices/${invoiceId}`)
          .expect(200);
        expect(paid.body.status).toBe('PAID');
      },
      120000,
    );

    it('blocks overpayment and cancel of posted invoice with a payment', async () => {
      const cust2 = await api(tokenA)
        .post('/api/v1/customers')
        .send({ name: 'Acme Buyer 2', email: `buyer2-${suffix}@acme.test` })
        .expect(201);

      const invoice = await api(tokenA)
        .post('/api/v1/invoices')
        .send({
          customerId: cust2.body.id,
          items: [{ productId: productAId, quantity: 1, unitPrice: 200, taxRate: 0 }],
        })
        .expect(201);
      const invoiceId = invoice.body.id;
      await api(tokenA).post(`/api/v1/invoices/${invoiceId}/post`).expect(201);

      const over = await api(tokenA)
        .post('/api/v1/payments')
        .send({ invoiceId, amount: 9999, method: 'CASH' });
      expect(over.status).toBe(400);

      await api(tokenA)
        .post('/api/v1/payments')
        .send({ invoiceId, amount: 50, method: 'CASH' })
        .expect(201);

      const cancel = await api(tokenA).post(`/api/v1/invoices/${invoiceId}/cancel`);
      expect(cancel.status).toBe(400);
    });

    it('returns dashboard summary', async () => {
      const res = await api(tokenA).get('/api/v1/dashboard/summary').expect(200);
      expect(res.body.totalCustomers).toBeGreaterThanOrEqual(2);
      expect(res.body.salesThisMonth).toBeTruthy();
    });
  });

  afterAll(async () => {
    await app.close();
  });
});