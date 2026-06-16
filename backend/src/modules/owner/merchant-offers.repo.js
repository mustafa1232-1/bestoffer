import { pool, q } from '../../config/db.js';

function runner(client) {
  if (client?.query) {
    return (sql, params = []) => client.query(sql, params);
  }
  return (sql, params = []) => q(sql, params);
}

export async function listOwnerProductsByIds(ownerUserId, productIds) {
  if (!Array.isArray(productIds) || productIds.length === 0) return [];
  const r = await q(
    `SELECT p.id, p.merchant_id, p.name, p.price, p.discounted_price, p.offer_label, p.free_delivery, p.is_available
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE m.owner_user_id = $1
       AND p.id = ANY($2::bigint[])
     ORDER BY p.id ASC`,
    [Number(ownerUserId), productIds.map((id) => Number(id))]
  );
  return r.rows;
}

export async function listOwnerOffers(ownerUserId) {
  const r = await q(
    `SELECT
       mo.*,
       COALESCE(
         json_agg(
           json_build_object(
             'id', p.id,
             'name', p.name,
             'price', p.price,
             'discountedPrice', p.discounted_price,
             'offerLabel', p.offer_label,
             'isAvailable', p.is_available
           )
           ORDER BY p.name ASC, p.id ASC
         ) FILTER (WHERE p.id IS NOT NULL),
         '[]'::json
       ) AS products
     FROM merchant_offer mo
     JOIN merchant m ON m.id = mo.merchant_id
     LEFT JOIN merchant_offer_product mop ON mop.offer_id = mo.id
     LEFT JOIN product p ON p.id = mop.product_id
     WHERE m.owner_user_id = $1
     GROUP BY mo.id
     ORDER BY mo.created_at DESC, mo.id DESC`,
    [Number(ownerUserId)]
  );
  return r.rows;
}

export async function findOwnerOfferById(ownerUserId, offerId) {
  const r = await q(
    `SELECT mo.*
     FROM merchant_offer mo
     JOIN merchant m ON m.id = mo.merchant_id
     WHERE m.owner_user_id = $1 AND mo.id = $2
     LIMIT 1`,
    [Number(ownerUserId), Number(offerId)]
  );
  return r.rows[0] || null;
}

export async function createOwnerOffer(ownerUserId, dto) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const merchantResult = await client.query(
      `SELECT id FROM merchant WHERE owner_user_id = $1 LIMIT 1`,
      [Number(ownerUserId)]
    );
    const merchant = merchantResult.rows[0] || null;
    if (!merchant) return null;

    const insert = await client.query(
      `INSERT INTO merchant_offer (
         merchant_id,
         title,
         description,
         offer_type,
         discount_value,
         buy_quantity,
         get_quantity,
         starts_at,
         ends_at,
         status,
         max_usage,
         created_by_user_id,
         updated_by_user_id
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       RETURNING *`,
      [
        Number(merchant.id),
        dto.title,
        dto.description || null,
        dto.offerType,
        dto.discountValue == null ? null : Number(dto.discountValue),
        dto.buyQuantity == null ? null : Number(dto.buyQuantity),
        dto.getQuantity == null ? null : Number(dto.getQuantity),
        dto.startsAt || null,
        dto.endsAt || null,
        dto.status,
        dto.maxUsage == null ? null : Number(dto.maxUsage),
        Number(ownerUserId),
        Number(ownerUserId),
      ]
    );
    const offer = insert.rows[0];
    await syncOfferProductsTx(client, Number(offer.id), dto.productIds || []);
    await client.query('COMMIT');
    return offer;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateOwnerOffer(ownerUserId, offerId, dto) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT mo.*
       FROM merchant_offer mo
       JOIN merchant m ON m.id = mo.merchant_id
       WHERE m.owner_user_id = $1 AND mo.id = $2
       FOR UPDATE`,
      [Number(ownerUserId), Number(offerId)]
    );
    if (!current.rows[0]) {
      await client.query('ROLLBACK');
      return null;
    }

    const map = {
      title: 'title',
      description: 'description',
      offerType: 'offer_type',
      discountValue: 'discount_value',
      buyQuantity: 'buy_quantity',
      getQuantity: 'get_quantity',
      startsAt: 'starts_at',
      endsAt: 'ends_at',
      status: 'status',
      maxUsage: 'max_usage',
    };
    const values = [];
    const sets = [];
    let idx = 1;
    for (const [key, column] of Object.entries(map)) {
      if (!Object.prototype.hasOwnProperty.call(dto, key)) continue;
      values.push(dto[key]);
      sets.push(`${column} = $${idx++}`);
    }
    values.push(Number(ownerUserId));
    sets.push(`updated_by_user_id = $${idx++}`);
    values.push(Number(ownerUserId));
    values.push(Number(offerId));

    const updated = await client.query(
      `UPDATE merchant_offer mo
       SET ${sets.join(', ')}
       FROM merchant m
       WHERE m.id = mo.merchant_id
         AND m.owner_user_id = $${idx}
         AND mo.id = $${idx + 1}
       RETURNING mo.*`,
      values
    );

    if (Object.prototype.hasOwnProperty.call(dto, 'productIds')) {
      await syncOfferProductsTx(client, Number(offerId), dto.productIds || []);
    }

    await client.query('COMMIT');
    return updated.rows[0] || null;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteOwnerOffer(ownerUserId, offerId) {
  const r = await q(
    `DELETE FROM merchant_offer mo
     USING merchant m
     WHERE m.id = mo.merchant_id
       AND m.owner_user_id = $1
       AND mo.id = $2
     RETURNING mo.id`,
    [Number(ownerUserId), Number(offerId)]
  );
  return Boolean(r.rows[0]);
}

export async function listLatestEligibleOffersByProductIds({
  client = null,
  merchantId,
  productIds,
  at = new Date().toISOString(),
}) {
  const ids = Array.isArray(productIds)
    ? productIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0)
    : [];
  if (!ids.length) return [];
  const run = runner(client);
  const out = await run(
    `WITH usage_counts AS (
       SELECT offer_id, COUNT(*)::INT AS used_count
       FROM merchant_offer_usage
       WHERE COALESCE(is_void, FALSE) = FALSE
       GROUP BY offer_id
     )
     SELECT DISTINCT ON (mop.product_id)
       mop.product_id,
       mo.id,
       mo.title,
       mo.description,
       mo.offer_type,
       mo.discount_value,
       mo.buy_quantity,
       mo.get_quantity,
       mo.starts_at,
       mo.ends_at,
       mo.status,
       mo.max_usage,
       COALESCE(uc.used_count, 0) AS used_count,
       mo.created_at
     FROM merchant_offer_product mop
     JOIN merchant_offer mo ON mo.id = mop.offer_id
     LEFT JOIN usage_counts uc ON uc.offer_id = mo.id
     WHERE mo.merchant_id = $1
       AND mop.product_id = ANY($2::bigint[])
       AND mo.status NOT IN ('draft', 'disabled', 'expired')
       AND (mo.starts_at IS NULL OR mo.starts_at <= $3::timestamptz)
       AND (mo.ends_at IS NULL OR mo.ends_at >= $3::timestamptz)
       AND (mo.max_usage IS NULL OR COALESCE(uc.used_count, 0) < mo.max_usage)
     ORDER BY mop.product_id, mo.created_at DESC, mo.id DESC`,
    [Number(merchantId), ids, at]
  );
  return out.rows;
}

export async function markOfferUsageByOrderTx(client, usages = []) {
  const rows = Array.isArray(usages) ? usages : [];
  for (const item of rows) {
    await client.query(
      `INSERT INTO merchant_offer_usage (
         offer_id,
         order_id,
         merchant_id,
         customer_user_id,
         discount_total
       ) VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (offer_id, order_id)
       DO UPDATE SET
         discount_total = EXCLUDED.discount_total,
         is_void = FALSE,
         void_reason = NULL`,
      [
        Number(item.offerId),
        Number(item.orderId),
        Number(item.merchantId),
        item.customerUserId == null ? null : Number(item.customerUserId),
        Number(item.discountTotal || 0),
      ]
    );
  }
}

async function syncOfferProductsTx(client, offerId, productIds) {
  await client.query(`DELETE FROM merchant_offer_product WHERE offer_id = $1`, [Number(offerId)]);
  const ids = Array.isArray(productIds)
    ? [...new Set(productIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0))]
    : [];
  for (const productId of ids) {
    await client.query(
      `INSERT INTO merchant_offer_product (offer_id, product_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [Number(offerId), Number(productId)]
    );
  }
}
