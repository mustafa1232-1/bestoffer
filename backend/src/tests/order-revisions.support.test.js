import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as revisions from "../modules/orders/order-revisions.service.js";

const userIds = [];
const merchantIds = [];
const productIds = [];
const orderIds = [];
const ticketIds = [];

function assertSafeTestDatabase() {
  const dbUrl = process.env.DATABASE_URL || "";
  const nodeEnv = process.env.NODE_ENV || "";
  const dbName = (() => {
    try {
      return new URL(dbUrl).pathname.replace(/^\//, "");
    } catch {
      return dbUrl;
    }
  })();
  const safeDbName = /(test|qa|local)/i.test(dbName);
  const unsafeRemote = /(railway|production|prod)/i.test(dbUrl);
  if ((!safeDbName && nodeEnv !== "test") || unsafeRemote) {
    throw new Error("Refusing to run order revision tests outside a test/QA database");
  }
}

function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

async function makeUser(role) {
  const user = await createUser({
    fullName: `REV ${role}`,
    username: `rev_${role}_${suffix()}`.slice(0, 32),
    phone: `07${String(Date.now() + Math.floor(Math.random() * 999999)).slice(-9)}`,
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "rev_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  userIds.push(Number(user.id));
  return Number(user.id);
}

async function makeFixture() {
  const customer = await makeUser("user");
  const owner = await makeUser("owner");
  const otherCustomer = await makeUser("user");
  const agent = await makeUser("admin");
  const zeroFeeSnapshot = {
    commissionType: "fixed",
    commissionValue: 0,
    commissionModel: "percentage",
    monthlySubscriptionAmount: 0,
    commissionAmount: 0,
    serviceFeeType: "fixed",
    serviceFeeValue: 0,
    serviceFeeAmount: 0,
    deliveryFeeMode: "app_defined",
    appDeliveryFeeValue: 0,
    storeDeliveryFeeValue: 0,
    appDeliveryFeeAmount: 0,
    storeDeliveryFeeAmount: 0,
    deliveryFee: 0,
    couponDiscountTotal: 0,
    customerTotalAmount: 2000,
  };

  const merchant = await q(
    `INSERT INTO merchant (name, type, owner_user_id, is_open)
     VALUES ($1, 'market', $2, TRUE)
     RETURNING id`,
    [`REV Merchant ${suffix()}`, owner]
  );
  const merchantId = Number(merchant.rows[0].id);
  merchantIds.push(merchantId);

  const otherMerchant = await q(
    `INSERT INTO merchant (name, type, owner_user_id, is_open)
     VALUES ($1, 'market', NULL, TRUE)
     RETURNING id`,
    [`REV Other ${suffix()}`]
  );
  const otherMerchantId = Number(otherMerchant.rows[0].id);
  merchantIds.push(otherMerchantId);

  await q(`INSERT INTO merchant_billing_profile (merchant_id) VALUES ($1) ON CONFLICT DO NOTHING`, [merchantId]);
  await q(`INSERT INTO inventory_settings (merchant_id, inventory_enabled) VALUES ($1, TRUE) ON CONFLICT DO NOTHING`, [merchantId]);
  await q(`INSERT INTO inventory_settings (merchant_id, inventory_enabled) VALUES ($1, TRUE) ON CONFLICT DO NOTHING`, [otherMerchantId]);

  const p1 = await q(
    `INSERT INTO product (merchant_id, name, price, discounted_price, is_available)
     VALUES ($1, 'Rice', 1000, NULL, TRUE)
     RETURNING id`,
    [merchantId]
  );
  const p2 = await q(
    `INSERT INTO product (merchant_id, name, price, discounted_price, is_available)
     VALUES ($1, 'Tea', 500, NULL, TRUE)
     RETURNING id`,
    [merchantId]
  );
  const otherProduct = await q(
    `INSERT INTO product (merchant_id, name, price, discounted_price, is_available)
     VALUES ($1, 'Other Store Item', 750, NULL, TRUE)
     RETURNING id`,
    [otherMerchantId]
  );
  const productA = Number(p1.rows[0].id);
  const productB = Number(p2.rows[0].id);
  const productOther = Number(otherProduct.rows[0].id);
  productIds.push(productA, productB, productOther);

  await q(
    `INSERT INTO store_inventory_item (merchant_id, product_id, quantity, stock_status)
     VALUES ($1,$2,3,'in_stock'), ($1,$3,5,'in_stock')`,
    [merchantId, productA, productB]
  );
  await q(
    `INSERT INTO store_inventory_item (merchant_id, product_id, quantity, stock_status)
     VALUES ($1,$2,5,'in_stock')`,
    [otherMerchantId, productOther]
  );

  const order = await q(
    `INSERT INTO customer_order
       (merchant_id, customer_user_id, status, customer_full_name, customer_phone,
        customer_block, customer_building_number, customer_apartment,
        subtotal, service_fee, delivery_fee, total_amount,
        gross_subtotal, product_discount_total, coupon_discount_total,
        pricing_breakdown_json, financial_config_snapshot_json)
     VALUES ($1,$2,'pending','Customer','07000000000','A','1','1',
             2000,0,0,2000,2000,0,0,'{}'::jsonb,$3::jsonb)
     RETURNING id`,
    [merchantId, customer, JSON.stringify(zeroFeeSnapshot)]
  );
  const orderId = Number(order.rows[0].id);
  orderIds.push(orderId);

  const orderItem = await q(
    `INSERT INTO order_item
       (order_id, product_id, product_name, base_unit_price, unit_price,
        quantity, line_total, pricing_breakdown_json)
     VALUES ($1,$2,'Rice',1000,1000,2,2000,'{}'::jsonb)
     RETURNING id`,
    [orderId, productA]
  );
  const orderItemId = Number(orderItem.rows[0].id);

  await q(
    `INSERT INTO inventory_reservation
       (order_id, order_item_id, merchant_id, product_id, quantity, status, expires_at)
     VALUES ($1,$2,$3,$4,2,'pending',NOW() + interval '30 minutes')`,
    [orderId, orderItemId, merchantId, productA]
  );

  const invoice = await q(
    `INSERT INTO merchant_receivable_invoice
       (merchant_id, order_id, invoice_number, order_status, subtotal,
        outstanding_amount, invoice_status)
     VALUES ($1,$2,$3,'pending',2000,2000,'unpaid')
     RETURNING id`,
    [merchantId, orderId, `INV-${suffix()}`]
  );
  const invoiceId = Number(invoice.rows[0].id);

  const ticket = await q(
    `INSERT INTO support_ticket
       (ticket_number, user_id, domain, type, priority, subject, status,
        entity_type, entity_id)
     VALUES ($1,$2,'SHOPPING','PROBLEM','normal','amend order','ASSIGNED','order',$3)
     RETURNING id`,
    [`TKT-${suffix()}`.slice(0, 24), customer, orderId]
  );
  const ticketId = Number(ticket.rows[0].id);
  ticketIds.push(ticketId);

  return {
    customer,
    owner,
    otherCustomer,
    agent,
    merchantId,
    orderId,
    orderItemId,
    productA,
    productB,
    productOther,
    ticketId,
    invoiceId,
  };
}

test.before(() => {
  assertSafeTestDatabase();
});

test.after(async () => {
  if (orderIds.length) {
    await q(`UPDATE customer_order SET last_order_revision_id = NULL WHERE id = ANY($1::bigint[])`, [orderIds]);
    await q(`DELETE FROM order_revision WHERE order_id = ANY($1::bigint[])`, [orderIds]);
  }
  if (ticketIds.length) await q(`DELETE FROM support_ticket WHERE id = ANY($1::bigint[])`, [ticketIds]);
  if (orderIds.length) await q(`DELETE FROM customer_order WHERE id = ANY($1::bigint[])`, [orderIds]);
  if (productIds.length) await q(`DELETE FROM product WHERE id = ANY($1::bigint[])`, [productIds]);
  if (merchantIds.length) await q(`DELETE FROM merchant WHERE id = ANY($1::bigint[])`, [merchantIds]);
  if (userIds.length) await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
});

test("support-created revision applies to the same order and invoice with inventory deltas", async () => {
  const fx = await makeFixture();
  const created = await revisions.createRevisionFromSupportTicket({
    ticketId: fx.ticketId,
    actorUserId: fx.agent,
    actorRole: "admin",
    orderId: fx.orderId,
    reason: "customer requested item correction",
    items: [
      {
        orderItemId: fx.orderItemId,
        productId: fx.productA,
        quantity: 3,
      },
      {
        productId: fx.productB,
        quantity: 1,
      },
    ],
  });
  assert.equal(created.revision.status, "DRAFT");
  assert.equal(Number(created.revision.order_id), fx.orderId);
  assert.equal(Number(created.revision.price_difference), 1500);
  assert.deepEqual(
    created.approvals.map((row) => row.approval_type).sort(),
    ["CUSTOMER", "MERCHANT"]
  );

  const submitted = await revisions.submitRevision({
    orderId: fx.orderId,
    revisionId: created.revision.id,
    actorUserId: fx.agent,
    actorRole: "admin",
  });
  assert.equal(submitted.revision.status, "AWAITING_BOTH");

  await assert.rejects(
    revisions.customerApprove({
      orderId: fx.orderId,
      revisionId: created.revision.id,
      userId: fx.otherCustomer,
      note: "not mine",
    })
  );

  const customerApproved = await revisions.customerApprove({
    orderId: fx.orderId,
    revisionId: created.revision.id,
    userId: fx.customer,
    note: "ok",
  });
  assert.equal(customerApproved.revision.status, "AWAITING_MERCHANT");

  const merchantApproved = await revisions.merchantApprove({
    orderId: fx.orderId,
    revisionId: created.revision.id,
    ownerUserId: fx.owner,
    note: "stock ok",
  });
  assert.equal(merchantApproved.revision.status, "APPROVED");

  const applied = await revisions.applyRevision({
    orderId: fx.orderId,
    revisionId: created.revision.id,
    actorUserId: fx.agent,
    actorRole: "admin",
  });
  assert.equal(applied.revision.status, "APPLIED");

  const order = await q(
    `SELECT id, total_amount, order_revision_version, last_order_revision_id
     FROM customer_order
     WHERE id=$1`,
    [fx.orderId]
  );
  assert.equal(Number(order.rows[0].id), fx.orderId);
  assert.equal(Number(order.rows[0].total_amount), 3500);
  assert.equal(Number(order.rows[0].order_revision_version), 2);
  assert.equal(Number(order.rows[0].last_order_revision_id), Number(created.revision.id));

  const invoice = await q(
    `SELECT id, subtotal, outstanding_amount
     FROM merchant_receivable_invoice
     WHERE order_id=$1`,
    [fx.orderId]
  );
  assert.equal(Number(invoice.rows[0].id), fx.invoiceId);
  assert.equal(Number(invoice.rows[0].subtotal), 3500);
  assert.equal(Number(invoice.rows[0].outstanding_amount), 3500);

  const stock = await q(
    `SELECT product_id, quantity
     FROM store_inventory_item
     WHERE product_id = ANY($1::bigint[])
     ORDER BY product_id ASC`,
    [[fx.productA, fx.productB]]
  );
  const stockMap = new Map(stock.rows.map((row) => [Number(row.product_id), Number(row.quantity)]));
  assert.equal(stockMap.get(fx.productA), 2);
  assert.equal(stockMap.get(fx.productB), 4);

  const orderCount = await q(`SELECT COUNT(*)::int AS total FROM customer_order WHERE id=$1`, [fx.orderId]);
  assert.equal(Number(orderCount.rows[0].total), 1);

  await revisions.applyRevision({
    orderId: fx.orderId,
    revisionId: created.revision.id,
    actorUserId: fx.agent,
    actorRole: "admin",
  });
  const stockAfterIdempotent = await q(
    `SELECT product_id, quantity
     FROM store_inventory_item
     WHERE product_id = ANY($1::bigint[])
     ORDER BY product_id ASC`,
    [[fx.productA, fx.productB]]
  );
  const stockAfterMap = new Map(
    stockAfterIdempotent.rows.map((row) => [Number(row.product_id), Number(row.quantity)])
  );
  assert.equal(stockAfterMap.get(fx.productA), 2);
  assert.equal(stockAfterMap.get(fx.productB), 4);
});

test("proposal rejects cross-merchant products and insufficient stock", async () => {
  const fx = await makeFixture();
  await assert.rejects(
    revisions.createRevisionFromSupportTicket({
      ticketId: fx.ticketId,
      actorUserId: fx.agent,
      actorRole: "admin",
      orderId: fx.orderId,
      reason: "bad merchant",
      items: [
        { orderItemId: fx.orderItemId, productId: fx.productA, quantity: 2 },
        { productId: fx.productOther, quantity: 1 },
      ],
    })
  );

  await assert.rejects(
    revisions.createRevisionFromSupportTicket({
      ticketId: fx.ticketId,
      actorUserId: fx.agent,
      actorRole: "admin",
      orderId: fx.orderId,
      reason: "too much stock",
      items: [{ orderItemId: fx.orderItemId, productId: fx.productA, quantity: 99 }],
    })
  );
});

test("revision requires a support ticket linked to the order and editable order status", async () => {
  const fx = await makeFixture();
  const otherOrder = await q(
    `INSERT INTO customer_order
       (merchant_id, customer_user_id, status, customer_full_name, customer_phone,
        customer_block, customer_building_number, customer_apartment,
        subtotal, delivery_fee, total_amount)
     VALUES ($1,$2,'pending','Other','07000000000','A','1','1',0,0,0)
     RETURNING id`,
    [fx.merchantId, fx.customer]
  );
  orderIds.push(Number(otherOrder.rows[0].id));

  await assert.rejects(
    revisions.createRevisionFromSupportTicket({
      ticketId: fx.ticketId,
      actorUserId: fx.agent,
      actorRole: "admin",
      orderId: Number(otherOrder.rows[0].id),
      reason: "wrong link",
      items: [{ productId: fx.productA, quantity: 1 }],
    })
  );

  await q(`UPDATE customer_order SET status='on_the_way' WHERE id=$1`, [fx.orderId]);
  await assert.rejects(
    revisions.createRevisionFromSupportTicket({
      ticketId: fx.ticketId,
      actorUserId: fx.agent,
      actorRole: "admin",
      orderId: fx.orderId,
      reason: "too late",
      items: [{ orderItemId: fx.orderItemId, productId: fx.productA, quantity: 1 }],
    })
  );
});
