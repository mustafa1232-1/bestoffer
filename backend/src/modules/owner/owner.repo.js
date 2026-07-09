import { pool, q } from "../../config/db.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { hasPermission } from "../../shared/workspaces/employee-permissions.js";
import {
  loadProductRichCatalogByIds,
  syncProductRichCatalogTx,
} from "../products/products.repo.js";

function normalizeDiscoveryCodes(values) {
  if (!Array.isArray(values)) return [];
  const out = [];
  const seen = new Set();
  for (const value of values) {
    if (value == null) continue;
    const normalized = String(value).trim().toLowerCase();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

export async function findMerchantByOwnerUserId(ownerUserId) {
  const r = await q(
    `SELECT id, name, type, activity_type, store_department, discovery_subcategory, discovery_select_all, service_flags_json, supports_chat, supports_attachments, supports_pharmacy_workflow, badges_json, description, phone, image_url, is_open, is_approved, approval_status, approved_by_user_id, approved_at, owner_user_id, tagline, working_hours, service_area_note, created_at, updated_at, financial_terms_sent_at, financial_terms_accepted_at, financial_terms_rejected_at, financial_terms_snapshot_json, financial_terms_rejection_note,
            COALESCE(
              (
                SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
                FROM merchant_discovery_subcategory mds
                WHERE mds.merchant_id = merchant.id
              ),
              ARRAY[]::text[]
            ) AS discovery_subcategories
     FROM merchant
     WHERE owner_user_id=$1`,
    [ownerUserId]
  );
  return r.rows[0] || null;
}

export async function listOwnerDeliveryAgents(ownerUserId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.image_url,
       mda.created_at
     FROM merchant_delivery_agent mda
     JOIN merchant m
       ON m.id = mda.merchant_id
     JOIN app_user u
       ON u.id = mda.delivery_user_id
     WHERE m.owner_user_id = $1
       AND mda.is_active = TRUE
       AND u.role = 'delivery'
       AND u.is_account_disabled = FALSE
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     ORDER BY u.full_name ASC, u.id DESC`,
    [Number(ownerUserId)]
  );
  return r.rows;
}

export async function listOwnerAccountants(ownerUserId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.image_url,
       ma.created_at
     FROM merchant_accountant ma
     JOIN merchant m
       ON m.id = ma.merchant_id
     JOIN app_user u
       ON u.id = ma.accountant_user_id
     WHERE m.owner_user_id = $1
       AND ma.is_active = TRUE
       AND u.role = 'accountant'
       AND u.is_account_disabled = FALSE
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     ORDER BY u.full_name ASC, u.id DESC`,
    [Number(ownerUserId)]
  );
  return r.rows;
}

export async function listOwnerHrStaff(ownerUserId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.image_url,
       hs.created_at
     FROM merchant_hr_staff hs
     JOIN merchant m
       ON m.id = hs.merchant_id
     JOIN app_user u
       ON u.id = hs.hr_user_id
     WHERE m.owner_user_id = $1
       AND hs.is_active = TRUE
       AND u.role = 'hr'
       AND u.is_account_disabled = FALSE
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       )
     ORDER BY u.full_name ASC, u.id DESC`,
    [Number(ownerUserId)]
  );
  return r.rows;
}

export async function linkDeliveryAgentToMerchant({
  merchantId,
  deliveryUserId,
  createdByUserId,
  source = "owner",
}) {
  const r = await q(
    `INSERT INTO merchant_delivery_agent
      (
        merchant_id,
        delivery_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, delivery_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_delivery_agent.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, delivery_user_id`,
    [
      Number(merchantId),
      Number(deliveryUserId),
      Number(createdByUserId) || null,
      String(source || "owner").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function linkAccountantToMerchant({
  merchantId,
  accountantUserId,
  createdByUserId,
  source = "owner",
}) {
  const r = await q(
    `INSERT INTO merchant_accountant
      (
        merchant_id,
        accountant_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, accountant_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_accountant.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, accountant_user_id`,
    [
      Number(merchantId),
      Number(accountantUserId),
      Number(createdByUserId) || null,
      String(source || "owner").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function linkHrToMerchant({
  merchantId,
  hrUserId,
  createdByUserId,
  source = "owner",
}) {
  const r = await q(
    `INSERT INTO merchant_hr_staff
      (
        merchant_id,
        hr_user_id,
        created_by_user_id,
        source,
        is_active,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,TRUE,NOW(),NOW())
     ON CONFLICT (merchant_id, hr_user_id)
     DO UPDATE SET
       is_active = TRUE,
       source = EXCLUDED.source,
       created_by_user_id = COALESCE(EXCLUDED.created_by_user_id, merchant_hr_staff.created_by_user_id),
       updated_at = NOW()
     RETURNING merchant_id, hr_user_id`,
    [
      Number(merchantId),
      Number(hrUserId),
      Number(createdByUserId) || null,
      String(source || "owner").slice(0, 20),
    ]
  );
  return r.rows[0] || null;
}

export async function searchUsersForStaff(ownerUserId, { search = "", limit = 100 }) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 100));
  const normalizedSearch = String(search || "").trim();

  const whereSearch =
    normalizedSearch.length > 0
      ? `AND (
          u.full_name ILIKE $2
          OR regexp_replace(
            translate(
              u.phone,
              '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
              '01234567890123456789'
            ),
            '[^0-9]',
            '',
            'g'
          ) ILIKE $2
        )`
      : "";

  const params = [Number(ownerUserId)];
  if (normalizedSearch.length > 0) {
    params.push(`%${normalizedSearch}%`);
  }
  params.push(safeLimit);

  const limitIndex = params.length;

  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.is_account_disabled,
       EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       ) AS is_taxi_captain
     FROM app_user u
     WHERE u.is_account_disabled = FALSE
       AND u.id <> $1
       AND u.role IN ('user', 'delivery', 'accountant', 'hr')
       AND u.id NOT IN (
         SELECT m.owner_user_id
         FROM merchant m
         WHERE m.owner_user_id IS NOT NULL
       )
       ${whereSearch}
     ORDER BY u.full_name ASC, u.id DESC
     LIMIT $${limitIndex}`,
    params
  );

  return r.rows;
}

export async function findUserForStaffById(userId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       u.is_account_disabled,
       u.delivery_account_approved,
       u.block,
       u.building_number,
       u.apartment,
       EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       ) AS is_taxi_captain
     FROM app_user u
     WHERE u.id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function setUserRole(userId, role) {
  const r = await q(
    `UPDATE app_user
     SET role = $2
     WHERE id = $1
     RETURNING id, full_name, phone, role, image_url`,
    [Number(userId), String(role || "user")]
  );
  return r.rows[0] || null;
}

export async function createOwnerWithMerchant(data) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const userResult = await client.query(
      `INSERT INTO app_user
        (
          full_name,
          username,
          phone,
          pin_hash,
          block,
          building_number,
          apartment,
          image_url,
          role,
          analytics_consent_granted,
          analytics_consent_version,
          analytics_consent_granted_at,
          chat_quality_review_consent
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       RETURNING id, username, full_name, phone, role, is_super_admin, block, building_number, apartment, image_url`,
      [
        data.fullName,
        data.username,
        data.phone,
        data.pinHash,
        data.block,
        data.buildingNumber,
        data.apartment,
        data.ownerImageUrl || null,
        "owner",
        data.analyticsConsentGranted === true,
        data.analyticsConsentVersion || null,
        data.analyticsConsentGrantedAt || null,
        data.chatQualityReviewConsent === true,
      ]
    );

    const user = userResult.rows[0];
    const discoverySelectAll = data.merchantDiscoverySelectAll === true;
    const discoveryCodes = normalizeDiscoveryCodes(
      data.merchantDiscoverySubcategories
    );

    const merchantResult = await client.query(
      `INSERT INTO merchant
        (
          name,
          type,
          activity_type,
          store_department,
          discovery_subcategory,
          discovery_select_all,
          description,
          phone,
          image_url,
          owner_user_id,
          is_approved,
          tagline,
          working_hours,
          service_area_note,
          service_flags_json,
          supports_chat,
          supports_attachments,
          supports_pharmacy_workflow,
          badges_json
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,FALSE,$11,$12,$13,$14::jsonb,$15,$16,$17,$18::jsonb)
       RETURNING id`,
      [
        data.merchantName,
        data.merchantType,
        data.merchantActivityType || null,
        data.merchantDepartment || null,
        data.merchantDiscoverySubcategory || null,
        discoverySelectAll,
        data.merchantDescription,
        data.merchantPhone,
        data.merchantImageUrl,
        user.id,
        data.merchantTagline || null,
        data.merchantWorkingHours || null,
        data.merchantServiceAreaNote || null,
        JSON.stringify(data.merchantServiceFlags || {}),
        data.merchantSupportsChat === true,
        data.merchantSupportsAttachments === true,
        data.merchantSupportsPharmacyWorkflow === true,
        JSON.stringify(Array.isArray(data.merchantBadges) ? data.merchantBadges : []),
      ]
    );

    const merchantId = Number(merchantResult.rows[0]?.id);

    if (Number.isInteger(merchantId) && merchantId > 0 && discoveryCodes.length) {
      await client.query(
        `INSERT INTO merchant_discovery_subcategory (merchant_id, discovery_code)
         SELECT $1::bigint, code
         FROM UNNEST($2::text[]) AS t(code)
         ON CONFLICT (merchant_id, discovery_code) DO NOTHING`,
        [merchantId, discoveryCodes]
      );
    }

    const merchantQuery = await client.query(
      `SELECT id, name, type, activity_type, store_department, discovery_subcategory, discovery_select_all, service_flags_json, supports_chat, supports_attachments, supports_pharmacy_workflow, badges_json, description, phone, image_url, is_open, is_approved, approval_status, approved_by_user_id, approved_at, owner_user_id, tagline, working_hours, service_area_note, created_at, updated_at, financial_terms_sent_at, financial_terms_accepted_at, financial_terms_rejected_at, financial_terms_snapshot_json, financial_terms_rejection_note,
              COALESCE(
                (
                  SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
                  FROM merchant_discovery_subcategory mds
                  WHERE mds.merchant_id = merchant.id
                ),
                ARRAY[]::text[]
              ) AS discovery_subcategories
       FROM merchant
       WHERE id = $1
       LIMIT 1`,
      [merchantId]
    );
    const merchant = merchantQuery.rows[0];

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
    activityType: "activity_type",
    storeDepartment: "store_department",
    discoverySubcategory: "discovery_subcategory",
    discoverySelectAll: "discovery_select_all",
    description: "description",
    phone: "phone",
    imageUrl: "image_url",
    isOpen: "is_open",
    tagline: "tagline",
    workingHours: "working_hours",
    serviceAreaNote: "service_area_note",
    serviceFlags: "service_flags_json",
    supportsChat: "supports_chat",
    supportsAttachments: "supports_attachments",
    supportsPharmacyWorkflow: "supports_pharmacy_workflow",
    badges: "badges_json",
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
     RETURNING id, name, type, activity_type, store_department, discovery_subcategory, discovery_select_all, service_flags_json, supports_chat, supports_attachments, supports_pharmacy_workflow, badges_json, description, phone, image_url, is_open, is_approved, approval_status, approved_by_user_id, approved_at, owner_user_id, tagline, working_hours, service_area_note, created_at, updated_at, financial_terms_sent_at, financial_terms_accepted_at, financial_terms_rejected_at, financial_terms_snapshot_json, financial_terms_rejection_note`,
    values
  );

  const row = r.rows[0] || null;
  if (!row) return null;
  const hydrated = await q(
    `SELECT id, name, type, activity_type, store_department, discovery_subcategory, discovery_select_all, service_flags_json, supports_chat, supports_attachments, supports_pharmacy_workflow, badges_json, description, phone, image_url, is_open, is_approved, approval_status, approved_by_user_id, approved_at, owner_user_id, tagline, working_hours, service_area_note, created_at, updated_at, financial_terms_sent_at, financial_terms_accepted_at, financial_terms_rejected_at, financial_terms_snapshot_json, financial_terms_rejection_note,
            COALESCE(
              (
                SELECT ARRAY_AGG(mds.discovery_code ORDER BY mds.discovery_code)
                FROM merchant_discovery_subcategory mds
                WHERE mds.merchant_id = merchant.id
              ),
              ARRAY[]::text[]
            ) AS discovery_subcategories
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(row.id)]
  );
  return hydrated.rows[0] || row;
}

export async function replaceMerchantDiscoverySubcategories(
  merchantId,
  discoveryCodes
) {
  const normalizedCodes = normalizeDiscoveryCodes(discoveryCodes);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `DELETE FROM merchant_discovery_subcategory WHERE merchant_id = $1`,
      [Number(merchantId)]
    );
    if (normalizedCodes.length) {
      await client.query(
        `INSERT INTO merchant_discovery_subcategory (merchant_id, discovery_code)
         SELECT $1::bigint, code
         FROM UNNEST($2::text[]) AS t(code)
         ON CONFLICT (merchant_id, discovery_code) DO NOTHING`,
        [Number(merchantId), normalizedCodes]
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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
    `INSERT INTO merchant_category (merchant_id, name, sort_order, catalog_type)
     SELECT m.id, $2, $3, $4
     FROM merchant m
     WHERE m.owner_user_id = $1
     RETURNING *`,
    [ownerUserId, dto.name, dto.sortOrder, dto.catalogType]
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

export async function findMerchantCategoryById(merchantId, categoryId) {
  const r = await q(
    `SELECT c.*
     FROM merchant_category c
     WHERE c.id = $1
       AND c.merchant_id = $2`,
    [categoryId, merchantId]
  );
  return r.rows[0] || null;
}

export async function countOwnerProductsByCategory(ownerUserId, categoryId) {
  const r = await q(
    `SELECT COUNT(*)::int AS count
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE m.owner_user_id = $1
       AND p.category_id = $2`,
    [ownerUserId, categoryId]
  );
  return Number(r.rows[0]?.count || 0);
}

export async function updateOwnerCategory(ownerUserId, categoryId, dto) {
  const map = {
    name: "name",
    sortOrder: "sort_order",
    catalogType: "catalog_type",
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
       si.quantity AS stock_quantity,
       c.name AS category_name,
       c.catalog_type AS category_catalog_type,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     LEFT JOIN store_inventory_item si ON si.merchant_id = p.merchant_id AND si.product_id = p.id
     WHERE m.owner_user_id=$1
     ORDER BY COALESCE(c.sort_order, 999999), COALESCE(c.id, 0), p.sort_order ASC, p.id DESC`,
    [ownerUserId]
  );
  return r.rows;
}

async function upsertSimpleProductStockTx(client, {
  merchantId,
  productId,
  quantity,
  actorUserId,
}) {
  if (quantity === undefined || quantity === null) return;
  const normalized = Math.max(0, Math.trunc(Number(quantity) || 0));
  await client.query(
    `INSERT INTO inventory_settings (merchant_id, inventory_enabled, daily_update_mode, updated_by_user_id)
     VALUES ($1, TRUE, 'manual_override', $2)
     ON CONFLICT (merchant_id) DO UPDATE
       SET inventory_enabled = TRUE, updated_by_user_id = EXCLUDED.updated_by_user_id, updated_at = NOW()`,
    [Number(merchantId), Number(actorUserId)]
  );
  await client.query(
    `INSERT INTO store_inventory_item
       (merchant_id, product_id, quantity, stock_status, last_quantity_update_at, updated_by_user_id)
     VALUES ($1,$2,$3,$4,NOW(),$5)
     ON CONFLICT (merchant_id, product_id) DO UPDATE
       SET quantity = EXCLUDED.quantity,
           stock_status = EXCLUDED.stock_status,
           manual_disabled = FALSE,
           auto_disabled = FALSE,
           last_quantity_update_at = NOW(),
           updated_by_user_id = EXCLUDED.updated_by_user_id,
           updated_at = NOW()`,
    [
      Number(merchantId),
      Number(productId),
      normalized,
      normalized <= 0 ? "out_of_stock" : "in_stock",
      Number(actorUserId),
    ]
  );
}

export async function hydrateOwnerProducts(rows) {
  const rich = await loadProductRichCatalogByIds((rows || []).map((row) => row.id));
  return (rows || []).map((row) => ({
    ...(rich.get(Number(row.id)) || row),
    stockQuantity: row.stock_quantity == null ? null : Number(row.stock_quantity),
    categoryCatalogType: row.category_catalog_type || null,
  }));
}

export async function createOwnerProduct(ownerUserId, dto) {
  const merchant = await findMerchantByOwnerUserId(ownerUserId);
  if (!merchant) return null;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const r = await client.query(
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
        unavailable_reason,
        unavailable_until,
        requires_prescription,
        requires_review,
        sort_order
      )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
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
        dto.unavailableReason,
        dto.unavailableUntil,
        dto.requiresPrescription === true,
        dto.requiresReview === true,
        dto.sortOrder,
      ]
    );

    const product = r.rows[0];
    if (product && dto.richCatalog) {
      await syncProductRichCatalogTx(client, product.id, {
        ...dto.richCatalog,
        imageUrl: dto.imageUrl,
      });
    }
    if (product) {
      await upsertSimpleProductStockTx(client, {
        merchantId: merchant.id,
        productId: product.id,
        quantity: dto.stockQuantity,
        actorUserId: ownerUserId,
      });
    }
    await client.query("COMMIT");
    return product;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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

export async function findMerchantProductById(merchantId, productId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.id=$1
       AND m.id=$2`,
    [productId, merchantId]
  );
  return r.rows[0] || null;
}

export async function updateOwnerProduct(actorUserId, merchantId, productId, dto) {
  const richCatalog = dto.richCatalog || null;
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
    unavailableReason: "unavailable_reason",
    unavailableUntil: "unavailable_until",
    requiresPrescription: "requires_prescription",
    requiresReview: "requires_review",
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
    const current = await findMerchantProductById(merchantId, productId);
    if (!current) return null;
    if (richCatalog || dto.stockQuantity !== undefined) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        if (richCatalog) {
          await syncProductRichCatalogTx(client, productId, {
            ...richCatalog,
            imageUrl: current.image_url || dto.imageUrl || null,
          });
        }
        await upsertSimpleProductStockTx(client, {
          merchantId: current.merchant_id,
          productId,
          quantity: dto.stockQuantity,
          actorUserId,
        });
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    }
    return current;
  }

  values.push(productId, merchantId);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const r = await client.query(
      `UPDATE product p
       SET ${sets.join(", ")}
       FROM merchant m
       WHERE p.id=$${idx}
         AND p.merchant_id=m.id
         AND m.id=$${idx + 1}
       RETURNING p.*`,
      values
    );

    const updated = r.rows[0] || null;
    if (updated && richCatalog) {
      await syncProductRichCatalogTx(client, productId, {
        ...richCatalog,
        imageUrl: updated.image_url || dto.imageUrl || null,
      });
    }
    if (updated) {
        await upsertSimpleProductStockTx(client, {
          merchantId: updated.merchant_id,
          productId,
          quantity: dto.stockQuantity,
          actorUserId,
        });
    }
    await client.query("COMMIT");
    return updated;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
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

export async function updateOwnerProductVariantAvailability(ownerUserId, productId, variantId, dto) {
  const map = {
    isAvailable: "is_available",
    unavailableReason: "unavailable_reason",
    unavailableUntil: "unavailable_until",
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

  const current = await q(
    `SELECT v.*
     FROM product_variant v
     JOIN product p ON p.id = v.product_id
     JOIN merchant m ON m.id = p.merchant_id
     WHERE v.id = $1
       AND p.id = $2
       AND m.owner_user_id = $3
     LIMIT 1`,
    [Number(variantId), Number(productId), Number(ownerUserId)]
  );
  if (!current.rows[0]) return null;
  if (sets.length === 0) return current.rows[0];

  values.push(variantId, productId, ownerUserId);
  const r = await q(
    `UPDATE product_variant v
     SET ${sets.join(", ")},
         updated_at = NOW()
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     WHERE v.id = $${idx}
       AND v.product_id = p.id
       AND p.id = $${idx + 1}
       AND m.owner_user_id = $${idx + 2}
     RETURNING v.*`,
    values
  );
  return r.rows[0] || null;
}

export async function findMerchantByEmployeeUserId(employeeUserId) {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.activity_type,
       m.discovery_subcategory,
       m.discovery_select_all,
       m.service_flags_json,
       m.supports_chat,
       m.supports_attachments,
       m.supports_pharmacy_workflow,
       m.badges_json,
       m.description,
       m.phone,
       m.image_url,
       m.is_open,
       m.is_approved,
       m.approval_status,
       m.approved_by_user_id,
       m.approved_at,
       m.owner_user_id,
       m.tagline,
       m.working_hours,
       m.service_area_note,
       m.created_at,
       m.updated_at,
       m.financial_terms_sent_at,
       m.financial_terms_accepted_at,
       m.financial_terms_rejected_at,
       m.financial_terms_snapshot_json,
       m.financial_terms_rejection_note,
       ep.id AS employee_profile_id,
       ep.role_tag,
       ep.display_name,
       ep.contact_email,
       ep.permissions_json,
       ep.is_active,
       ep.archived_at
     FROM merchant_employee_profile ep
     JOIN merchant m ON m.id = ep.merchant_id
     WHERE ep.employee_user_id = $1
       AND ep.is_active = TRUE
       AND ep.archived_at IS NULL
       AND m.is_disabled = FALSE
     ORDER BY ep.updated_at DESC, ep.id DESC
     LIMIT 1`,
    [Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function findEmployeeProfileForMerchant({
  merchantId,
  employeeUserId,
}) {
  const r = await q(
    `SELECT *
     FROM merchant_employee_profile
     WHERE merchant_id = $1
       AND employee_user_id = $2
       AND is_active = TRUE
       AND archived_at IS NULL
     LIMIT 1`,
    [Number(merchantId), Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function findAnyEmployeeProfileForMerchant({
  merchantId,
  employeeUserId,
}) {
  const r = await q(
    `SELECT *
     FROM merchant_employee_profile
     WHERE merchant_id = $1
       AND employee_user_id = $2
     LIMIT 1`,
    [Number(merchantId), Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function listActiveMerchantNotificationRecipients({
  merchantId,
  requiredPermissions = [],
} = {}) {
  const permissions = Array.isArray(requiredPermissions)
    ? requiredPermissions
        .map((value) => String(value || "").trim().toLowerCase())
        .filter(Boolean)
    : [];

  const r = await q(
    `SELECT
       u.id AS user_id,
       ep.permissions_json,
       ep.merchant_id,
       ep.is_active,
       ep.archived_at,
       u.is_account_disabled,
       m.owner_user_id
     FROM merchant_employee_profile ep
     JOIN app_user u ON u.id = ep.employee_user_id
     JOIN merchant m ON m.id = ep.merchant_id
     WHERE ep.merchant_id = $1
       AND ep.is_active = TRUE
       AND ep.archived_at IS NULL
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND m.is_disabled = FALSE
       AND u.id <> m.owner_user_id
     ORDER BY ep.updated_at DESC, ep.id DESC`,
    [Number(merchantId)]
  );

  return r.rows
    .map((row) => ({
      userId: Number(row.user_id),
      merchantId: Number(row.merchant_id),
      permissions: Array.isArray(row.permissions_json)
        ? row.permissions_json
        : [],
    }))
    .filter((row) => {
      if (!Number.isInteger(row.userId) || row.userId <= 0) return false;
      if (!permissions.length) return true;
      return permissions.some((permission) =>
        hasPermission(row.permissions, permission)
      );
    });
}

export async function markOrderedProductUnavailable(
  ownerUserId,
  orderId,
  productId,
  dto = {}
) {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const targetResult = await client.query(
      `SELECT
         o.id AS order_id,
         o.customer_user_id,
         o.merchant_id,
         m.name AS merchant_name,
         oi.product_id,
         oi.product_name,
         p.is_available AS previous_is_available,
         p.unavailable_reason AS previous_unavailable_reason,
         p.unavailable_until AS previous_unavailable_until
       FROM customer_order o
       JOIN merchant m
         ON m.id = o.merchant_id
       JOIN order_item oi
         ON oi.order_id = o.id
       JOIN product p
         ON p.id = oi.product_id
        AND p.merchant_id = m.id
       WHERE o.id = $1
         AND m.owner_user_id = $2
         AND oi.product_id = $3
       LIMIT 1`,
      [Number(orderId), Number(ownerUserId), Number(productId)]
    );

    const target = targetResult.rows[0];
    if (!target) {
      await client.query("ROLLBACK");
      return null;
    }

    await client.query(
      `UPDATE product
       SET is_available = FALSE,
           unavailable_reason = COALESCE($2, 'ORDER_PREPARATION_UNAVAILABLE'),
           unavailable_until = $3,
           updated_at = NOW()
       WHERE id = $1`,
      [
        Number(productId),
        dto.unavailableReason == null || String(dto.unavailableReason).trim() === ""
          ? null
          : String(dto.unavailableReason).trim(),
        dto.unavailableUntil == null || String(dto.unavailableUntil).trim() === ""
          ? null
          : String(dto.unavailableUntil).trim(),
      ]
    );

    await client.query("COMMIT");
    return target;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
