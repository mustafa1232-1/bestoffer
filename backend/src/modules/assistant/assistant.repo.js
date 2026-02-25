import { q } from "../../config/db.js";

function mapMessage(row) {
  return {
    id: Number(row.id),
    role: row.role,
    text: row.text,
    metadata: row.metadata || null,
    createdAt: row.created_at,
  };
}

function mapDraft(row) {
  if (!row) return null;

  const rawItems = Array.isArray(row.items_json)
    ? row.items_json
    : row.items_json && typeof row.items_json === "object"
    ? row.items_json.items
    : [];

  const items = Array.isArray(rawItems)
    ? rawItems.map((item) => ({
        productId: Number(item.productId),
        productName: item.productName,
        quantity: Number(item.quantity || 1),
        unitPrice: Number(item.unitPrice || 0),
        lineTotal: Number(
          item.lineTotal ?? Number(item.unitPrice || 0) * Number(item.quantity || 1)
        ),
      }))
    : [];

  return {
    id: Number(row.id),
    token: row.token,
    customerUserId: Number(row.customer_user_id),
    sessionId: row.session_id == null ? null : Number(row.session_id),
    merchantId: Number(row.merchant_id),
    merchantName: row.merchant_name,
    merchantType: row.merchant_type,
    addressId: row.address_id == null ? null : Number(row.address_id),
    addressLabel: row.address_label || null,
    addressCity: row.address_city || null,
    addressBlock: row.address_block || null,
    addressBuildingNumber: row.address_building_number || null,
    addressApartment: row.address_apartment || null,
    note: row.note || null,
    items,
    subtotal: Number(row.subtotal || 0),
    serviceFee: Number(row.service_fee || 0),
    deliveryFee: Number(row.delivery_fee || 0),
    totalAmount: Number(row.total_amount || 0),
    rationale: row.rationale || null,
    status: row.status,
    linkedOrderId: row.linked_order_id == null ? null : Number(row.linked_order_id),
    expiresAt: row.expires_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function expireOldDrafts(customerUserId) {
  await q(
    `UPDATE ai_order_draft
     SET status = 'expired'
     WHERE customer_user_id = $1
       AND status = 'pending'
       AND expires_at < NOW()`,
    [Number(customerUserId)]
  );
}

export async function getSessionById(customerUserId, sessionId) {
  const result = await q(
    `SELECT id, customer_user_id, title, last_message_at, created_at, updated_at
     FROM ai_chat_session
     WHERE id = $1
       AND customer_user_id = $2
     LIMIT 1`,
    [Number(sessionId), Number(customerUserId)]
  );
  return result.rows[0] || null;
}

export async function getLatestSession(customerUserId) {
  const result = await q(
    `SELECT id, customer_user_id, title, last_message_at, created_at, updated_at
     FROM ai_chat_session
     WHERE customer_user_id = $1
     ORDER BY last_message_at DESC, id DESC
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return result.rows[0] || null;
}

export async function createSession(customerUserId, title = null) {
  const result = await q(
    `INSERT INTO ai_chat_session (customer_user_id, title)
     VALUES ($1, $2)
     RETURNING id, customer_user_id, title, last_message_at, created_at, updated_at`,
    [Number(customerUserId), title]
  );
  return result.rows[0] || null;
}

export async function touchSession(sessionId) {
  await q(
    `UPDATE ai_chat_session
     SET last_message_at = NOW()
     WHERE id = $1`,
    [Number(sessionId)]
  );
}

export async function insertMessage(sessionId, role, text, metadata = null) {
  const result = await q(
    `INSERT INTO ai_chat_message (session_id, role, text, metadata)
     VALUES ($1, $2::ai_chat_role, $3, $4)
     RETURNING id, role, text, metadata, created_at`,
    [
      Number(sessionId),
      role,
      text,
      metadata == null ? null : JSON.stringify(metadata),
    ]
  );
  await touchSession(sessionId);
  return mapMessage(result.rows[0]);
}

export async function listMessages(sessionId, limit = 40) {
  const clampedLimit = Math.min(Math.max(Number(limit) || 40, 1), 120);
  const result = await q(
    `SELECT id, role, text, metadata, created_at
     FROM (
       SELECT id, role, text, metadata, created_at
       FROM ai_chat_message
       WHERE session_id = $1
       ORDER BY id DESC
       LIMIT $2
     ) x
     ORDER BY id ASC`,
    [Number(sessionId), clampedLimit]
  );
  return result.rows.map(mapMessage);
}

export async function getProfile(customerUserId) {
  const result = await q(
    `SELECT customer_user_id, preference_json, last_summary, created_at, updated_at
     FROM ai_customer_profile
     WHERE customer_user_id = $1
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return result.rows[0] || null;
}

export async function upsertProfile(customerUserId, preferenceJson, lastSummary = null) {
  const result = await q(
    `INSERT INTO ai_customer_profile (customer_user_id, preference_json, last_summary)
     VALUES ($1, $2, $3)
     ON CONFLICT (customer_user_id)
     DO UPDATE
       SET preference_json = EXCLUDED.preference_json,
           last_summary = EXCLUDED.last_summary
     RETURNING customer_user_id, preference_json, last_summary, created_at, updated_at`,
    [Number(customerUserId), JSON.stringify(preferenceJson || {}), lastSummary]
  );
  return result.rows[0] || null;
}

export async function getHistorySignals(customerUserId) {
  const merchantResult = await q(
    `SELECT
       o.merchant_id,
       m.name AS merchant_name,
       COUNT(*)::int AS orders_count
     FROM customer_order o
     JOIN merchant m ON m.id = o.merchant_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY o.merchant_id, m.name
     ORDER BY orders_count DESC
     LIMIT 12`,
    [Number(customerUserId)]
  );

  const categoryResult = await q(
    `SELECT
       COALESCE(c.name, 'general') AS category_name,
       SUM(oi.quantity)::int AS items_count
     FROM customer_order o
     JOIN order_item oi ON oi.order_id = o.id
     LEFT JOIN product p ON p.id = oi.product_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE o.customer_user_id = $1
       AND o.status <> 'cancelled'
     GROUP BY COALESCE(c.name, 'general')
     ORDER BY items_count DESC
     LIMIT 16`,
    [Number(customerUserId)]
  );

  const favoritesResult = await q(
    `SELECT
       p.id AS product_id,
       p.merchant_id,
       p.name AS product_name,
       COALESCE(p.discounted_price, p.price) AS effective_price
     FROM customer_favorite_product f
     JOIN product p ON p.id = f.product_id
     JOIN merchant m ON m.id = p.merchant_id
     WHERE f.customer_user_id = $1
       AND p.is_available = TRUE
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
     ORDER BY f.created_at DESC
     LIMIT 30`,
    [Number(customerUserId)]
  );

  return {
    merchants: merchantResult.rows.map((row) => ({
      merchantId: Number(row.merchant_id),
      merchantName: row.merchant_name,
      ordersCount: Number(row.orders_count || 0),
    })),
    categories: categoryResult.rows.map((row) => ({
      categoryName: row.category_name,
      itemsCount: Number(row.items_count || 0),
    })),
    favoriteProducts: favoritesResult.rows.map((row) => ({
      productId: Number(row.product_id),
      merchantId: Number(row.merchant_id),
      productName: row.product_name,
      effectivePrice: Number(row.effective_price || 0),
    })),
  };
}


export async function getGlobalSignals() {
  const [merchantResult, categoryResult, productResult] = await Promise.all([
    q(
      `SELECT
         o.merchant_id,
         COUNT(*)::int AS delivered_orders
       FROM customer_order o
       WHERE o.status = 'delivered'
       GROUP BY o.merchant_id
       ORDER BY delivered_orders DESC
       LIMIT 40`
    ),
    q(
      `SELECT
         COALESCE(c.name, 'general') AS category_name,
         SUM(oi.quantity)::int AS items_count
       FROM customer_order o
       JOIN order_item oi ON oi.order_id = o.id
       LEFT JOIN product p ON p.id = oi.product_id
       LEFT JOIN merchant_category c ON c.id = p.category_id
       WHERE o.status = 'delivered'
       GROUP BY COALESCE(c.name, 'general')
       ORDER BY items_count DESC
       LIMIT 40`
    ),
    q(
      `SELECT
         oi.product_id,
         SUM(oi.quantity)::int AS sold_units
       FROM customer_order o
       JOIN order_item oi ON oi.order_id = o.id
       WHERE o.status = 'delivered'
       GROUP BY oi.product_id
       ORDER BY sold_units DESC
       LIMIT 120`
    ),
  ]);

  return {
    merchants: merchantResult.rows.map((row) => ({
      merchantId: Number(row.merchant_id),
      deliveredOrders: Number(row.delivered_orders || 0),
    })),
    categories: categoryResult.rows.map((row) => ({
      categoryName: row.category_name || 'general',
      itemsCount: Number(row.items_count || 0),
    })),
    products: productResult.rows.map((row) => ({
      productId: Number(row.product_id),
      soldUnits: Number(row.sold_units || 0),
    })),
  };
}
export async function listRecommendationPool(customerUserId, limit = 500) {
  const clampedLimit = Math.min(Math.max(Number(limit) || 500, 20), 1500);

  const result = await q(
    `SELECT
       p.id AS product_id,
       p.merchant_id,
       p.name AS product_name,
       p.description AS product_description,
       COALESCE(p.discounted_price, p.price) AS effective_price,
       p.price AS base_price,
       p.discounted_price,
       p.free_delivery,
       p.offer_label,
       p.image_url AS product_image_url,
       c.name AS category_name,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.image_url AS merchant_image_url,
       m.is_open,
       COALESCE(
         AVG(o.merchant_rating)
           FILTER (WHERE o.status = 'delivered' AND o.merchant_rating IS NOT NULL),
         0
       )::double precision AS merchant_avg_rating,
       AVG(o.estimated_delivery_minutes)
         FILTER (WHERE o.estimated_delivery_minutes IS NOT NULL)::double precision
         AS merchant_avg_delivery_minutes,
       COUNT(o.id)
         FILTER (WHERE o.status = 'delivered')::int AS merchant_completed_orders,
       EXISTS (
         SELECT 1
         FROM customer_favorite_product f
         WHERE f.customer_user_id = $1
           AND f.product_id = p.id
       ) AS is_favorite
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     LEFT JOIN customer_order o ON o.merchant_id = m.id
     WHERE p.is_available = TRUE
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
       AND m.is_open = TRUE
     GROUP BY p.id, m.id, c.name
     ORDER BY p.id DESC
     LIMIT $2`,
    [Number(customerUserId), clampedLimit]
  );

  return result.rows.map((row) => ({
    productId: Number(row.product_id),
    merchantId: Number(row.merchant_id),
    productName: row.product_name,
    productDescription: row.product_description || "",
    effectivePrice: Number(row.effective_price || 0),
    basePrice: Number(row.base_price || 0),
    discountedPrice:
      row.discounted_price == null ? null : Number(row.discounted_price),
    freeDelivery: row.free_delivery === true,
    offerLabel: row.offer_label || null,
    productImageUrl: row.product_image_url || null,
    categoryName: row.category_name || null,
    merchantName: row.merchant_name,
    merchantType: row.merchant_type,
    merchantImageUrl: row.merchant_image_url || null,
    merchantIsOpen: row.is_open === true,
    merchantAvgRating: Number(row.merchant_avg_rating || 0),
    merchantAvgDeliveryMinutes:
      row.merchant_avg_delivery_minutes == null
        ? null
        : Number(row.merchant_avg_delivery_minutes),
    merchantCompletedOrders: Number(row.merchant_completed_orders || 0),
    isFavorite: row.is_favorite === true,
  }));
}

export async function listCustomerAddresses(customerUserId) {
  const result = await q(
    `SELECT
       id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default
     FROM customer_address
     WHERE customer_user_id = $1
       AND is_active = TRUE
     ORDER BY is_default DESC, id DESC`,
    [Number(customerUserId)]
  );
  return result.rows;
}

export async function getDefaultAddress(customerUserId) {
  const result = await q(
    `SELECT
       id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default
     FROM customer_address
     WHERE customer_user_id = $1
       AND is_active = TRUE
     ORDER BY is_default DESC, id DESC
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return result.rows[0] || null;
}

export async function getAddressById(customerUserId, addressId) {
  const result = await q(
    `SELECT
       id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default
     FROM customer_address
     WHERE customer_user_id = $1
       AND id = $2
       AND is_active = TRUE
     LIMIT 1`,
    [Number(customerUserId), Number(addressId)]
  );
  return result.rows[0] || null;
}

export async function createDraft({
  token,
  customerUserId,
  sessionId,
  merchantId,
  addressId,
  note,
  items,
  subtotal,
  serviceFee,
  deliveryFee,
  totalAmount,
  rationale,
}) {
  const result = await q(
    `INSERT INTO ai_order_draft
      (
        token,
        customer_user_id,
        session_id,
        merchant_id,
        address_id,
        note,
        items_json,
        subtotal,
        service_fee,
        delivery_fee,
        total_amount,
        rationale
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     RETURNING id`,
    [
      token,
      Number(customerUserId),
      sessionId == null ? null : Number(sessionId),
      Number(merchantId),
      addressId == null ? null : Number(addressId),
      note || null,
      JSON.stringify(items || []),
      Number(subtotal || 0),
      Number(serviceFee || 0),
      Number(deliveryFee || 0),
      Number(totalAmount || 0),
      rationale || null,
    ]
  );

  return getDraftById(result.rows[0]?.id);
}

export async function getDraftById(draftId) {
  if (!draftId) return null;
  const result = await q(
    `SELECT
       d.*,
       m.name AS merchant_name,
       m.type AS merchant_type,
       a.label AS address_label,
       a.city AS address_city,
       a.block AS address_block,
       a.building_number AS address_building_number,
       a.apartment AS address_apartment
     FROM ai_order_draft d
     JOIN merchant m ON m.id = d.merchant_id
     LEFT JOIN customer_address a ON a.id = d.address_id
     WHERE d.id = $1
     LIMIT 1`,
    [Number(draftId)]
  );
  return mapDraft(result.rows[0]);
}

export async function getDraftByToken(customerUserId, token) {
  const result = await q(
    `SELECT
       d.*,
       m.name AS merchant_name,
       m.type AS merchant_type,
       a.label AS address_label,
       a.city AS address_city,
       a.block AS address_block,
       a.building_number AS address_building_number,
       a.apartment AS address_apartment
     FROM ai_order_draft d
     JOIN merchant m ON m.id = d.merchant_id
     LEFT JOIN customer_address a ON a.id = d.address_id
     WHERE d.customer_user_id = $1
       AND d.token = $2
     LIMIT 1`,
    [Number(customerUserId), token]
  );
  return mapDraft(result.rows[0]);
}

export async function getLatestPendingDraft(customerUserId, sessionId = null) {
  const params = [Number(customerUserId)];
  let sessionClause = "";

  if (sessionId != null) {
    params.push(Number(sessionId));
    sessionClause = "AND d.session_id = $2";
  }

  const result = await q(
    `SELECT
       d.*,
       m.name AS merchant_name,
       m.type AS merchant_type,
       a.label AS address_label,
       a.city AS address_city,
       a.block AS address_block,
       a.building_number AS address_building_number,
       a.apartment AS address_apartment
     FROM ai_order_draft d
     JOIN merchant m ON m.id = d.merchant_id
     LEFT JOIN customer_address a ON a.id = d.address_id
     WHERE d.customer_user_id = $1
       ${sessionClause}
       AND d.status = 'pending'
     ORDER BY d.created_at DESC
     LIMIT 1`,
    params
  );
  return mapDraft(result.rows[0]);
}

export async function markDraftConfirmed(draftId, orderId) {
  await q(
    `UPDATE ai_order_draft
     SET status = 'confirmed',
         linked_order_id = $2
     WHERE id = $1`,
    [Number(draftId), Number(orderId)]
  );
}

export async function markDraftCancelled(draftId) {
  await q(
    `UPDATE ai_order_draft
     SET status = 'cancelled'
     WHERE id = $1`,
    [Number(draftId)]
  );
}

