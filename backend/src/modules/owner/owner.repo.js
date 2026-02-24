import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

export async function findMerchantByOwnerUserId(ownerUserId) {
  const r = await q(
    `SELECT id, name, type, description, phone, image_url, is_open, is_approved, approved_by_user_id, approved_at, owner_user_id, created_at, updated_at
     FROM merchant
     WHERE owner_user_id=$1`,
    [ownerUserId]
  );
  return r.rows[0] || null;
}

export async function createOwnerWithMerchant(data) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const userResult = await client.query(
      `INSERT INTO app_user
        (full_name, phone, pin_hash, block, building_number, apartment, image_url, role)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING id, full_name, phone, role, block, building_number, apartment, image_url`,
      [
        data.fullName,
        data.phone,
        data.pinHash,
        data.block,
        data.buildingNumber,
        data.apartment,
        data.ownerImageUrl || null,
        "owner",
      ]
    );

    const user = userResult.rows[0];

    const merchantResult = await client.query(
      `INSERT INTO merchant
        (name, type, description, phone, image_url, owner_user_id, is_approved)
       VALUES ($1,$2,$3,$4,$5,$6,FALSE)
       RETURNING id, name, type, description, phone, image_url, is_open, is_approved, approved_by_user_id, approved_at, owner_user_id, created_at, updated_at`,
      [
        data.merchantName,
        data.merchantType,
        data.merchantDescription,
        data.merchantPhone,
        data.merchantImageUrl,
        user.id,
      ]
    );

    const merchant = merchantResult.rows[0];

    await client.query("COMMIT");

    const backofficeUsersResult = await q(
      `SELECT id
       FROM app_user
       WHERE role IN ('admin', 'deputy_admin')`
    );

    await createManyNotifications([
      ...backofficeUsersResult.rows.map((adminUser) => ({
        userId: adminUser.id,
        type: "admin_pending_merchant",
        title: "متجر بانتظار الموافقة",
        body: `متجر ${merchant.name} بانتظار المراجعة والموافقة`,
        merchantId: merchant.id,
        payload: {
          merchantId: merchant.id,
          ownerUserId: user.id,
        },
      })),
      {
        userId: user.id,
        type: "owner_pending_approval",
        title: "بانتظار موافقة الإدارة",
        body: `تم إنشاء متجرك ${merchant.name} وهو الآن بانتظار موافقة الإدارة`,
        merchantId: merchant.id,
        payload: {
          merchantId: merchant.id,
          isApproved: false,
        },
      },
    ]);

    return {
      user,
      merchant,
    };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function updateOwnerMerchant(ownerUserId, dto) {
  const map = {
    name: "name",
    type: "type",
    description: "description",
    phone: "phone",
    imageUrl: "image_url",
    isOpen: "is_open",
  };

  const values = [];
  const sets = [];
  let idx = 1;

  for (const [key, column] of Object.entries(map)) {
    if (dto[key] !== undefined) {
      values.push(dto[key]);
      sets.push(`${column}=$${idx++}`);
    }
  }

  if (sets.length === 0) {
    return findMerchantByOwnerUserId(ownerUserId);
  }

  values.push(ownerUserId);

  const r = await q(
    `UPDATE merchant
     SET ${sets.join(", ")}
     WHERE owner_user_id=$${idx}
     RETURNING id, name, type, description, phone, image_url, is_open, is_approved, approved_by_user_id, approved_at, owner_user_id, created_at, updated_at`,
    values
  );

  return r.rows[0] || null;
}

export async function listOwnerCategories(ownerUserId) {
  const r = await q(
    `SELECT c.*
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     WHERE m.owner_user_id = $1
     ORDER BY c.sort_order ASC, c.id ASC`,
    [ownerUserId]
  );
  return r.rows;
}

export async function createOwnerCategory(ownerUserId, dto) {
  const r = await q(
    `INSERT INTO merchant_category (merchant_id, name, sort_order)
     SELECT m.id, $2, $3
     FROM merchant m
     WHERE m.owner_user_id = $1
     RETURNING *`,
    [ownerUserId, dto.name, dto.sortOrder]
  );
  return r.rows[0] || null;
}

export async function findOwnerCategoryById(ownerUserId, categoryId) {
  const r = await q(
    `SELECT c.*
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     WHERE c.id = $1
       AND m.owner_user_id = $2`,
    [categoryId, ownerUserId]
  );
  return r.rows[0] || null;
}

export async function updateOwnerCategory(ownerUserId, categoryId, dto) {
  const map = {
    name: "name",
    sortOrder: "sort_order",
  };

  const values = [];
  const sets = [];
  let idx = 1;

  for (const [key, column] of Object.entries(map)) {
    if (dto[key] !== undefined) {
      values.push(dto[key]);
      sets.push(`${column}=$${idx++}`);
    }
  }

  if (sets.length === 0) {
    return findOwnerCategoryById(ownerUserId, categoryId);
  }

  values.push(categoryId, ownerUserId);

  const r = await q(
    `UPDATE merchant_category c
     SET ${sets.join(", ")}
     FROM merchant m
     WHERE c.id = $${idx}
       AND c.merchant_id = m.id
       AND m.owner_user_id = $${idx + 1}
     RETURNING c.*`,
    values
  );

  return r.rows[0] || null;
}

export async function deleteOwnerCategory(ownerUserId, categoryId) {
  const r = await q(
    `DELETE FROM merchant_category c
     USING merchant m
     WHERE c.id = $1
       AND c.merchant_id = m.id
       AND m.owner_user_id = $2
     RETURNING c.id`,
    [categoryId, ownerUserId]
  );

  return !!r.rows[0];
}

export async function listOwnerProducts(ownerUserId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE m.owner_user_id=$1
     ORDER BY COALESCE(c.sort_order, 999999), COALESCE(c.id, 0), p.sort_order ASC, p.id DESC`,
    [ownerUserId]
  );
  return r.rows;
}

export async function createOwnerProduct(ownerUserId, dto) {
  const merchant = await findMerchantByOwnerUserId(ownerUserId);
  if (!merchant) return null;

  const r = await q(
    `INSERT INTO product
      (
        merchant_id,
        category_id,
        name,
        description,
        price,
        discounted_price,
        image_url,
        free_delivery,
        offer_label,
        is_available,
        sort_order
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING *`,
    [
      merchant.id,
      dto.categoryId,
      dto.name,
      dto.description,
      dto.price,
      dto.discountedPrice,
      dto.imageUrl,
      dto.freeDelivery,
      dto.offerLabel,
      dto.isAvailable,
      dto.sortOrder,
    ]
  );

  return r.rows[0];
}

export async function findOwnerProductById(ownerUserId, productId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.id=$1
       AND m.owner_user_id=$2`,
    [productId, ownerUserId]
  );
  return r.rows[0] || null;
}

export async function updateOwnerProduct(ownerUserId, productId, dto) {
  const map = {
    name: "name",
    description: "description",
    price: "price",
    discountedPrice: "discounted_price",
    imageUrl: "image_url",
    categoryId: "category_id",
    freeDelivery: "free_delivery",
    offerLabel: "offer_label",
    isAvailable: "is_available",
    sortOrder: "sort_order",
  };

  const values = [];
  const sets = [];
  let idx = 1;

  for (const [key, column] of Object.entries(map)) {
    if (dto[key] !== undefined) {
      values.push(dto[key]);
      sets.push(`${column}=$${idx++}`);
    }
  }

  if (sets.length === 0) {
    return findOwnerProductById(ownerUserId, productId);
  }

  values.push(productId, ownerUserId);

  const r = await q(
    `UPDATE product p
     SET ${sets.join(", ")}
     FROM merchant m
     WHERE p.id=$${idx}
       AND p.merchant_id=m.id
       AND m.owner_user_id=$${idx + 1}
     RETURNING p.*`,
    values
  );

  return r.rows[0] || null;
}

export async function deleteOwnerProduct(ownerUserId, productId) {
  const r = await q(
    `DELETE FROM product p
     USING merchant m
     WHERE p.id=$1
       AND p.merchant_id=m.id
       AND m.owner_user_id=$2
     RETURNING p.id`,
    [productId, ownerUserId]
  );

  return !!r.rows[0];
}
