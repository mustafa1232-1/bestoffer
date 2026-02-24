import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

function appError(message, status) {
  const err = new Error(message);
  err.status = status;
  return err;
}

export async function createMerchantWithOwnerLink({
  merchant,
  approvedByUserId,
  ownerUserId,
  ownerToCreate,
  ownerPinHash,
}) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    let owner = null;

    if (ownerUserId) {
      const ownerResult = await client.query(
        `SELECT id, full_name, phone, role, image_url
         FROM app_user
         WHERE id=$1
           AND role='owner'`,
        [ownerUserId]
      );

      owner = ownerResult.rows[0] || null;

      if (!owner) {
        throw appError("OWNER_NOT_FOUND", 404);
      }
    } else {
      const phoneExistsResult = await client.query(
        `SELECT id
         FROM app_user
         WHERE phone=$1
         LIMIT 1`,
        [ownerToCreate.phone]
      );

      if (phoneExistsResult.rows[0]) {
        throw appError("PHONE_EXISTS", 409);
      }

      const ownerInsertResult = await client.query(
        `INSERT INTO app_user
          (full_name, phone, pin_hash, block, building_number, apartment, image_url, role)
         VALUES ($1,$2,$3,$4,$5,$6,$7,'owner')
         RETURNING id, full_name, phone, role, image_url`,
        [
          ownerToCreate.fullName,
          ownerToCreate.phone,
          ownerPinHash,
          ownerToCreate.block,
          ownerToCreate.buildingNumber,
          ownerToCreate.apartment,
          ownerToCreate.imageUrl || null,
        ]
      );

      owner = ownerInsertResult.rows[0];
    }

    const merchantByOwnerResult = await client.query(
      `SELECT id
       FROM merchant
       WHERE owner_user_id=$1
       LIMIT 1`,
      [owner.id]
    );

    if (merchantByOwnerResult.rows[0]) {
      throw appError("OWNER_ALREADY_HAS_MERCHANT", 409);
    }

    const merchantResult = await client.query(
      `INSERT INTO merchant
        (name, type, description, phone, image_url, owner_user_id, is_approved, approved_by_user_id, approved_at)
       VALUES ($1,$2,$3,$4,$5,$6,TRUE,$7,NOW())
       RETURNING *`,
      [
        merchant.name,
        merchant.type,
        merchant.description,
        merchant.phone || owner.phone,
        merchant.imageUrl,
        owner.id,
        approvedByUserId || null,
      ]
    );
    const createdMerchant = merchantResult.rows[0];

    await client.query("COMMIT");

    await createManyNotifications([
      {
        userId: owner.id,
        type: "owner_merchant_linked",
        title: "تم ربط المتجر بحسابك",
        body: `تم إنشاء متجر ${createdMerchant.name} وربطه بحسابك`,
        merchantId: createdMerchant.id,
        payload: {
          merchantId: createdMerchant.id,
        },
      },
    ]);

    return createdMerchant;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function getAllMerchants(type) {
  if (type) {
    const r = await q(
      `SELECT
         m.*,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND p.discounted_price IS NOT NULL
             AND p.discounted_price < p.price
         ) AS has_discount_offer,
         EXISTS (
           SELECT 1
           FROM product p
           WHERE p.merchant_id = m.id
             AND p.is_available = TRUE
             AND p.free_delivery = TRUE
         ) AS has_free_delivery_offer
       FROM merchant m
       WHERE m.type=$1
         AND m.is_approved=TRUE
         AND m.is_disabled=FALSE`,
      [type]
    );
    return r.rows;
  }

  const r = await q(
    `SELECT
       m.*,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.discounted_price IS NOT NULL
           AND p.discounted_price < p.price
       ) AS has_discount_offer,
       EXISTS (
         SELECT 1
         FROM product p
         WHERE p.merchant_id = m.id
           AND p.is_available = TRUE
           AND p.free_delivery = TRUE
       ) AS has_free_delivery_offer
     FROM merchant m
     WHERE m.is_approved=TRUE
       AND m.is_disabled=FALSE`
  );
  return r.rows;
}

export async function getPublicMerchantProducts(merchantId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.merchant_id=$1
       AND p.is_available=true
       AND m.is_approved=TRUE
       AND m.is_disabled=FALSE
     ORDER BY COALESCE(c.sort_order, 999999), COALESCE(c.id, 0), p.sort_order ASC, p.id DESC`,
    [merchantId]
  );
  return r.rows;
}

export async function getPublicMerchantCategories(merchantId) {
  const r = await q(
    `SELECT
       c.id,
       c.merchant_id,
       c.name,
       c.sort_order,
       c.created_at,
       c.updated_at,
       COUNT(p.id)::int AS available_products_count
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     LEFT JOIN product p
       ON p.category_id = c.id
      AND p.is_available = TRUE
     WHERE c.merchant_id = $1
       AND m.is_approved = TRUE
       AND m.is_disabled = FALSE
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC`,
    [merchantId]
  );
  return r.rows;
}
