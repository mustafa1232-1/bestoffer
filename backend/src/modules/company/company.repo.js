import { pool, q } from "../../config/db.js";
import { couponLifecycleStatusSql } from "../coupons/coupons.repo.js";

function toPositiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function toNonEmpty(value, max = 255) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  if (!out) return null;
  return out.slice(0, max);
}

function toJson(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

export async function listActiveMembershipsByUserId(userId) {
  const r = await q(
    `SELECT cu.*, c.name AS company_name, c.code AS company_code, c.status AS company_status
     FROM company_user cu
     JOIN company c ON c.id = cu.company_id
     WHERE cu.user_id = $1
       AND cu.is_active = TRUE
       AND c.status = 'active'
     ORDER BY cu.company_id ASC, cu.id ASC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function findCompanyById(companyId) {
  const r = await q(
    `SELECT c.*,
            (SELECT COUNT(*)::INT FROM merchant m WHERE m.company_id = c.id) AS branches_count,
            (SELECT COUNT(*)::INT FROM company_user cu WHERE cu.company_id = c.id AND cu.is_active = TRUE) AS users_count
     FROM company c
     WHERE c.id = $1
     LIMIT 1`,
    [Number(companyId)]
  );
  return r.rows[0] || null;
}

export async function findCompanyByCode(code) {
  const normalized = toNonEmpty(code, 40);
  if (!normalized) return null;
  const r = await q(
    `SELECT *
     FROM company
     WHERE LOWER(code) = LOWER($1)
     LIMIT 1`,
    [normalized]
  );
  return r.rows[0] || null;
}

export async function listCompaniesAdmin({ search = null, status = null, limit = 50, offset = 0 } = {}) {
  const params = [];
  const where = [];
  if (toNonEmpty(search, 180)) {
    params.push(`%${toNonEmpty(search, 180)}%`);
    where.push(`(
      c.name ILIKE $${params.length}
      OR COALESCE(c.legal_name, '') ILIKE $${params.length}
      OR COALESCE(c.brand_name, '') ILIKE $${params.length}
      OR COALESCE(c.code, '') ILIKE $${params.length}
      OR COALESCE(c.contact_phone, '') ILIKE $${params.length}
    )`);
  }
  if (toNonEmpty(status, 24)) {
    params.push(toNonEmpty(status, 24));
    where.push(`c.status = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(200, Number(limit) || 50)));
  const limitIndex = params.length;
  params.push(Math.max(0, Number(offset) || 0));
  const offsetIndex = params.length;
  const whereSql = where.length ? `WHERE ${where.join(" AND ")}` : "";
  const r = await q(
    `SELECT c.*,
            COUNT(DISTINCT m.id)::INT AS branches_count,
            COUNT(DISTINCT cu.id) FILTER (WHERE cu.is_active = TRUE)::INT AS active_users_count
     FROM company c
     LEFT JOIN merchant m ON m.company_id = c.id
     LEFT JOIN company_user cu ON cu.company_id = c.id
     ${whereSql}
     GROUP BY c.id
     ORDER BY c.created_at DESC, c.id DESC
     LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
    params
  );
  return r.rows;
}

export async function createCompany({
  name,
  legalName = null,
  brandName = null,
  code,
  contactPhone = null,
  contactEmail = null,
  logoUrl = null,
  summary = null,
  businessType = null,
  headquartersAddress = null,
  primaryContactName = null,
  supportPhone = null,
  websiteUrl = null,
  registrationNumber = null,
  taxNumber = null,
  notes = null,
  status = "active",
  createdByUserId = null,
}) {
  const r = await q(
    `INSERT INTO company (
       name,
       legal_name,
       brand_name,
       code,
       contact_phone,
       contact_email,
       logo_url,
       summary,
       business_type,
       headquarters_address,
       primary_contact_name,
       support_phone,
       website_url,
       registration_number,
       tax_number,
       notes,
       status,
       created_by_user_id,
       updated_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)
     RETURNING *`,
    [
      toNonEmpty(name, 180),
      toNonEmpty(legalName, 220),
      toNonEmpty(brandName, 220),
      toNonEmpty(code, 40),
      toNonEmpty(contactPhone, 30),
      toNonEmpty(contactEmail, 180),
      toNonEmpty(logoUrl, 1200),
      toNonEmpty(summary, 4000),
      toNonEmpty(businessType, 80),
      toNonEmpty(headquartersAddress, 240),
      toNonEmpty(primaryContactName, 180),
      toNonEmpty(supportPhone, 30),
      toNonEmpty(websiteUrl, 1200),
      toNonEmpty(registrationNumber, 80),
      toNonEmpty(taxNumber, 80),
      toNonEmpty(notes, 4000),
      toNonEmpty(status, 24) || "active",
      toPositiveInt(createdByUserId),
      toPositiveInt(createdByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function updateCompany(companyId, patch = {}, { updatedByUserId = null } = {}) {
  const sets = [];
  const params = [];
  const push = (column, value) => {
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  };

  if (Object.prototype.hasOwnProperty.call(patch, "name")) {
    push("name", toNonEmpty(patch.name, 180));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "legalName")) {
    push("legal_name", toNonEmpty(patch.legalName, 220));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "brandName")) {
    push("brand_name", toNonEmpty(patch.brandName, 220));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "code")) {
    push("code", toNonEmpty(patch.code, 40));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "contactPhone")) {
    push("contact_phone", toNonEmpty(patch.contactPhone, 30));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "contactEmail")) {
    push("contact_email", toNonEmpty(patch.contactEmail, 180));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "logoUrl")) {
    push("logo_url", toNonEmpty(patch.logoUrl, 1200));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "summary")) {
    push("summary", toNonEmpty(patch.summary, 4000));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "businessType")) {
    push("business_type", toNonEmpty(patch.businessType, 80));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "headquartersAddress")) {
    push("headquarters_address", toNonEmpty(patch.headquartersAddress, 240));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "primaryContactName")) {
    push("primary_contact_name", toNonEmpty(patch.primaryContactName, 180));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "supportPhone")) {
    push("support_phone", toNonEmpty(patch.supportPhone, 30));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "websiteUrl")) {
    push("website_url", toNonEmpty(patch.websiteUrl, 1200));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "registrationNumber")) {
    push("registration_number", toNonEmpty(patch.registrationNumber, 80));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "taxNumber")) {
    push("tax_number", toNonEmpty(patch.taxNumber, 80));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "notes")) {
    push("notes", toNonEmpty(patch.notes, 4000));
  }
  if (Object.prototype.hasOwnProperty.call(patch, "status")) {
    push("status", toNonEmpty(patch.status, 24));
  }
  push("updated_by_user_id", toPositiveInt(updatedByUserId));

  params.push(Number(companyId));
  const r = await q(
    `UPDATE company
     SET ${sets.join(", ")}
     WHERE id = $${params.length}
     RETURNING *`,
    params
  );
  return r.rows[0] || null;
}

export async function deleteCompany(companyId) {
  const r = await q(
    `DELETE FROM company
     WHERE id = $1
     RETURNING *`,
    [Number(companyId)]
  );
  return r.rows[0] || null;
}

export async function findCompanyUser(companyId, userId) {
  const r = await q(
    `SELECT *
     FROM company_user
     WHERE company_id = $1
       AND user_id = $2
     LIMIT 1`,
    [Number(companyId), Number(userId)]
  );
  return r.rows[0] || null;
}

export async function addOrUpdateCompanyUser({
  companyId,
  userId,
  role,
  permissionsJson = {},
  isActive = true,
  invitedByUserId = null,
}) {
  const r = await q(
    `INSERT INTO company_user (
       company_id,
       user_id,
       role,
       permissions_json,
       is_active,
       invited_by_user_id
     )
     VALUES ($1,$2,$3,$4::jsonb,$5,$6)
     ON CONFLICT (company_id, user_id)
     DO UPDATE SET
       role = EXCLUDED.role,
       permissions_json = EXCLUDED.permissions_json,
       is_active = EXCLUDED.is_active,
       invited_by_user_id = EXCLUDED.invited_by_user_id,
       joined_at = CASE WHEN company_user.is_active = FALSE AND EXCLUDED.is_active = TRUE THEN NOW() ELSE company_user.joined_at END,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(companyId),
      Number(userId),
      toNonEmpty(role, 40),
      JSON.stringify(toJson(permissionsJson)),
      isActive === true,
      toPositiveInt(invitedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function listCompanyUsers(companyId) {
  const r = await q(
    `SELECT cu.*, u.full_name, u.username, u.phone, u.image_url, u.work_title, u.work_company
     FROM company_user cu
     JOIN app_user u ON u.id = cu.user_id
     WHERE cu.company_id = $1
     ORDER BY cu.is_active DESC, cu.role ASC, cu.id ASC`,
    [Number(companyId)]
  );
  return r.rows;
}

export async function getCompanyDefaultPolicy(companyId) {
  const r = await q(
    `SELECT *
     FROM company_default_policy
     WHERE company_id = $1
     LIMIT 1`,
    [Number(companyId)]
  );
  return r.rows[0] || null;
}
export async function upsertCompanyDefaultPolicy(companyId, patch = {}, { updatedByUserId = null } = {}) {
  const current = await getCompanyDefaultPolicy(companyId);
  const next = {
    commissionRate: patch.commissionRate ?? current?.commission_rate ?? null,
    serviceFeeMode: patch.serviceFeeMode ?? current?.service_fee_mode ?? null,
    serviceFeeValue: patch.serviceFeeValue ?? current?.service_fee_value ?? null,
    deliveryFeeMode: patch.deliveryFeeMode ?? current?.delivery_fee_mode ?? null,
    deliveryFeeValue: patch.deliveryFeeValue ?? current?.delivery_fee_value ?? null,
    appDeliveryEnabled: patch.appDeliveryEnabled ?? current?.app_delivery_enabled ?? null,
    merchantDeliveryEnabled:
      patch.merchantDeliveryEnabled ?? current?.merchant_delivery_enabled ?? null,
    settlementCycle: patch.settlementCycle ?? current?.settlement_cycle ?? null,
    inventoryEnabled: patch.inventoryEnabled ?? current?.inventory_enabled ?? false,
    inventoryUpdateMode:
      patch.inventoryUpdateMode ?? current?.inventory_update_mode ?? "manual_override",
    lowStockThreshold: patch.lowStockThreshold ?? current?.low_stock_threshold ?? 5,
    autoDisableOutOfStock:
      patch.autoDisableOutOfStock ?? current?.auto_disable_out_of_stock ?? true,
    showAllWithoutAutoDisable:
      patch.showAllWithoutAutoDisable ?? current?.show_all_without_auto_disable ?? false,
  };

  const r = await q(
    `INSERT INTO company_default_policy (
       company_id,
       commission_rate,
       service_fee_mode,
       service_fee_value,
       delivery_fee_mode,
       delivery_fee_value,
       app_delivery_enabled,
       merchant_delivery_enabled,
       settlement_cycle,
       inventory_enabled,
       inventory_update_mode,
       low_stock_threshold,
       auto_disable_out_of_stock,
       show_all_without_auto_disable,
       updated_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
     ON CONFLICT (company_id)
     DO UPDATE SET
       commission_rate = EXCLUDED.commission_rate,
       service_fee_mode = EXCLUDED.service_fee_mode,
       service_fee_value = EXCLUDED.service_fee_value,
       delivery_fee_mode = EXCLUDED.delivery_fee_mode,
       delivery_fee_value = EXCLUDED.delivery_fee_value,
       app_delivery_enabled = EXCLUDED.app_delivery_enabled,
       merchant_delivery_enabled = EXCLUDED.merchant_delivery_enabled,
       settlement_cycle = EXCLUDED.settlement_cycle,
       inventory_enabled = EXCLUDED.inventory_enabled,
       inventory_update_mode = EXCLUDED.inventory_update_mode,
       low_stock_threshold = EXCLUDED.low_stock_threshold,
       auto_disable_out_of_stock = EXCLUDED.auto_disable_out_of_stock,
       show_all_without_auto_disable = EXCLUDED.show_all_without_auto_disable,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(companyId),
      next.commissionRate,
      next.serviceFeeMode,
      next.serviceFeeValue,
      next.deliveryFeeMode,
      next.deliveryFeeValue,
      next.appDeliveryEnabled,
      next.merchantDeliveryEnabled,
      next.settlementCycle,
      next.inventoryEnabled === true,
      next.inventoryUpdateMode,
      Number(next.lowStockThreshold || 0),
      next.autoDisableOutOfStock !== false,
      next.showAllWithoutAutoDisable === true,
      toPositiveInt(updatedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function findMerchantById(merchantId) {
  const r = await q(
    `SELECT m.*, u.full_name AS owner_full_name, u.phone AS owner_phone
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     WHERE m.id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function linkMerchantToCompany({ companyId, merchantId }) {
  const r = await q(
    `UPDATE merchant
     SET company_id = $1
     WHERE id = $2
     RETURNING *`,
    [Number(companyId), Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function unlinkMerchantFromCompany({ companyId, merchantId }) {
  const r = await q(
    `UPDATE merchant
     SET company_id = NULL
     WHERE id = $1
       AND company_id = $2
     RETURNING *`,
    [Number(merchantId), Number(companyId)]
  );
  return r.rows[0] || null;
}

export async function listCompanyBranches(companyId, { search = null, limit = 50, offset = 0 } = {}) {
  const params = [Number(companyId)];
  let searchSql = "";
  if (toNonEmpty(search, 180)) {
    params.push(`%${toNonEmpty(search, 180)}%`);
    searchSql = `AND (
      m.name ILIKE $${params.length}
      OR COALESCE(m.description, '') ILIKE $${params.length}
      OR COALESCE(m.phone, '') ILIKE $${params.length}
      OR COALESCE(u.full_name, '') ILIKE $${params.length}
    )`;
  }
  params.push(Math.max(1, Math.min(200, Number(limit) || 50)));
  const limitIndex = params.length;
  params.push(Math.max(0, Number(offset) || 0));
  const offsetIndex = params.length;

  const r = await q(
    `WITH sales AS (
       SELECT
         merchant_id,
         COUNT(*)::INT AS total_orders,
         COUNT(*) FILTER (WHERE status IN ('delivered','delivered_by_courier','received_by_customer','completed'))::INT AS completed_orders,
         COUNT(*) FILTER (WHERE status IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin'))::INT AS cancelled_orders,
         COUNT(*) FILTER (WHERE status NOT IN ('delivered','delivered_by_courier','received_by_customer','completed','cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin'))::INT AS active_orders,
         COALESCE(SUM(total_amount) FILTER (WHERE status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')), 0)::NUMERIC AS gross_sales
       FROM customer_order
       GROUP BY merchant_id
     ),
     receivables AS (
       SELECT
         inv.merchant_id,
         COALESCE(SUM(inv.app_receivable_amount), 0)::NUMERIC AS app_due,
         COALESCE(SUM(inv.outstanding_amount), 0)::NUMERIC AS outstanding_amount
       FROM merchant_receivable_invoice inv
       GROUP BY inv.merchant_id
     ),
     collections AS (
       SELECT
         pr.merchant_id,
         COALESCE(SUM(pr.amount) FILTER (WHERE pr.status = 'approved'), 0)::NUMERIC AS total_collected
       FROM merchant_payment_request pr
       GROUP BY pr.merchant_id
     ),
     inventory AS (
       SELECT
         si.merchant_id,
         COUNT(*)::INT AS tracked_items,
         COUNT(*) FILTER (WHERE si.stock_status = 'out_of_stock')::INT AS out_of_stock_items,
         COUNT(*) FILTER (WHERE si.stock_status = 'low_stock')::INT AS low_stock_items,
         MAX(si.updated_at) AS last_inventory_update_at
       FROM store_inventory_item si
       GROUP BY si.merchant_id
     )
     SELECT
       m.*,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone,
       COALESCE(s.total_orders, 0)::INT AS total_orders,
       COALESCE(s.completed_orders, 0)::INT AS completed_orders,
       COALESCE(s.cancelled_orders, 0)::INT AS cancelled_orders,
       COALESCE(s.active_orders, 0)::INT AS active_orders,
       COALESCE(s.gross_sales, 0)::NUMERIC AS gross_sales,
       COALESCE(r.app_due, 0)::NUMERIC AS app_due,
       COALESCE(c.total_collected, 0)::NUMERIC AS total_collected,
       COALESCE(r.outstanding_amount, 0)::NUMERIC AS outstanding_amount,
       COALESCE(i.tracked_items, 0)::INT AS tracked_items,
       COALESCE(i.out_of_stock_items, 0)::INT AS out_of_stock_items,
       COALESCE(i.low_stock_items, 0)::INT AS low_stock_items,
       i.last_inventory_update_at,
       sset.inventory_enabled,
       sset.daily_update_mode,
       sset.last_daily_check_at,
       sset.show_all_without_auto_disable
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     LEFT JOIN sales s ON s.merchant_id = m.id
     LEFT JOIN receivables r ON r.merchant_id = m.id
     LEFT JOIN collections c ON c.merchant_id = m.id
     LEFT JOIN inventory i ON i.merchant_id = m.id
     LEFT JOIN inventory_settings sset ON sset.merchant_id = m.id
     WHERE m.company_id = $1
       ${searchSql}
     ORDER BY m.created_at DESC, m.id DESC
     LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
    params
  );
  return r.rows;
}

export async function getCompanyDashboard(companyId) {
  const r = await q(
    `WITH branch_scope AS (
       SELECT id, name
       FROM merchant
       WHERE company_id = $1
     ),
     sales AS (
       SELECT
         COUNT(*)::INT AS total_orders,
         COUNT(*) FILTER (WHERE status IN ('delivered','delivered_by_courier','received_by_customer','completed'))::INT AS completed_orders,
         COUNT(*) FILTER (WHERE status IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin'))::INT AS cancelled_orders,
         COUNT(*) FILTER (WHERE status NOT IN ('delivered','delivered_by_courier','received_by_customer','completed','cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin'))::INT AS active_orders,
         COALESCE(SUM(total_amount) FILTER (WHERE status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')), 0)::NUMERIC AS total_sales
       FROM customer_order
       WHERE merchant_id IN (SELECT id FROM branch_scope)
     ),
     invoice AS (
       SELECT
         COALESCE(SUM(service_fee_amount), 0)::NUMERIC AS total_service_fees,
         COALESCE(SUM(app_delivery_fee_amount), 0)::NUMERIC AS total_app_delivery_fees,
         COALESCE(SUM(app_receivable_amount), 0)::NUMERIC AS total_app_due,
         COALESCE(SUM(outstanding_amount), 0)::NUMERIC AS total_outstanding
       FROM merchant_receivable_invoice
       WHERE merchant_id IN (SELECT id FROM branch_scope)
     ),
     collections AS (
       SELECT COALESCE(SUM(amount) FILTER (WHERE status = 'approved'), 0)::NUMERIC AS total_collected
       FROM merchant_payment_request
       WHERE merchant_id IN (SELECT id FROM branch_scope)
     ),
     branches AS (
       SELECT
         m.id,
         m.name,
         COALESCE(SUM(o.total_amount) FILTER (WHERE o.status NOT IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin')), 0)::NUMERIC AS branch_sales,
         COUNT(o.id)::INT AS branch_orders
       FROM merchant m
       LEFT JOIN customer_order o ON o.merchant_id = m.id
       WHERE m.company_id = $1
       GROUP BY m.id, m.name
     )
     SELECT
       (SELECT COUNT(*)::INT FROM branch_scope) AS branches_count,
       (SELECT total_orders FROM sales) AS total_orders,
       (SELECT completed_orders FROM sales) AS completed_orders,
       (SELECT cancelled_orders FROM sales) AS cancelled_orders,
       (SELECT active_orders FROM sales) AS active_orders,
       (SELECT total_sales FROM sales) AS total_sales,
       (SELECT total_service_fees FROM invoice) AS total_service_fees,
       (SELECT total_app_delivery_fees FROM invoice) AS total_app_delivery_fees,
       (SELECT total_app_due FROM invoice) AS total_app_due,
       (SELECT total_collected FROM collections) AS total_collected,
       (SELECT total_outstanding FROM invoice) AS total_outstanding,
       (
         SELECT row_to_json(b)
         FROM (
           SELECT id, name, branch_sales, branch_orders
           FROM branches
           ORDER BY branch_sales DESC, branch_orders DESC, id DESC
           LIMIT 1
         ) b
       ) AS best_branch,
       (
         SELECT row_to_json(b)
         FROM (
           SELECT id, name, branch_sales, branch_orders
           FROM branches
           ORDER BY branch_sales ASC, branch_orders ASC, id ASC
           LIMIT 1
         ) b
       ) AS weakest_branch`,
    [Number(companyId)]
  );
  return r.rows[0] || null;
}
export async function createCompanyBranchRequest({
  companyId,
  body,
  ownerPinHash,
  createdByUserId,
}) {
  const r = await q(
    `INSERT INTO company_branch_request (
       company_id,
       requested_name,
       requested_type,
       requested_description,
       requested_phone,
       requested_image_url,
       requested_tagline,
       requested_working_hours,
       requested_service_area_note,
       branch_location_label,
       proposed_owner_full_name,
       proposed_owner_phone,
       proposed_owner_pin_hash,
       proposed_owner_block,
       proposed_owner_building_number,
       proposed_owner_apartment,
       requested_policy_override_json,
       created_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17::jsonb,$18)
     RETURNING *`,
    [
      Number(companyId),
      toNonEmpty(body.name, 180),
      toNonEmpty(body.type, 40),
      toNonEmpty(body.description, 2000),
      toNonEmpty(body.phone, 30),
      toNonEmpty(body.imageUrl, 1200),
      toNonEmpty(body.tagline, 160),
      toNonEmpty(body.workingHours, 160),
      toNonEmpty(body.serviceAreaNote, 240),
      toNonEmpty(body.branchLocationLabel, 180),
      toNonEmpty(body.ownerFullName, 180),
      toNonEmpty(body.ownerPhone, 30),
      ownerPinHash,
      toNonEmpty(body.ownerBlock, 20),
      toNonEmpty(body.ownerBuildingNumber, 20),
      toNonEmpty(body.ownerApartment, 20),
      JSON.stringify(toJson(body.policyOverrideJson)),
      toPositiveInt(createdByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function listCompanyBranchRequests(companyId, { status = null } = {}) {
  const params = [Number(companyId)];
  let statusSql = "";
  if (toNonEmpty(status, 30)) {
    params.push(toNonEmpty(status, 30));
    statusSql = `AND cbr.status = $${params.length}`;
  }
  const r = await q(
    `SELECT cbr.*,
            u.full_name AS created_by_full_name,
            reviewer.full_name AS reviewed_by_full_name,
            m.name AS approved_merchant_name
     FROM company_branch_request cbr
     LEFT JOIN app_user u ON u.id = cbr.created_by_user_id
     LEFT JOIN app_user reviewer ON reviewer.id = cbr.reviewed_by_user_id
     LEFT JOIN merchant m ON m.id = cbr.approved_merchant_id
     WHERE cbr.company_id = $1
       ${statusSql}
     ORDER BY cbr.created_at DESC, cbr.id DESC`,
    params
  );
  return r.rows;
}

export async function listPendingCompanyBranchRequestsAdmin() {
  const r = await q(
    `SELECT cbr.*, c.name AS company_name, c.code AS company_code, u.full_name AS created_by_full_name
     FROM company_branch_request cbr
     JOIN company c ON c.id = cbr.company_id
     LEFT JOIN app_user u ON u.id = cbr.created_by_user_id
     WHERE cbr.status = 'pending_admin_review'
     ORDER BY cbr.created_at DESC, cbr.id DESC`
  );
  return r.rows;
}

export async function findCompanyBranchRequestById(requestId) {
  const r = await q(
    `SELECT cbr.*, c.name AS company_name, c.code AS company_code
     FROM company_branch_request cbr
     JOIN company c ON c.id = cbr.company_id
     WHERE cbr.id = $1
     LIMIT 1`,
    [Number(requestId)]
  );
  return r.rows[0] || null;
}

export async function markCompanyBranchRequestReviewed({
  requestId,
  status,
  reviewNote = null,
  reviewedByUserId = null,
  approvedMerchantId = null,
}) {
  const r = await q(
    `UPDATE company_branch_request
     SET status = $2,
         review_note = $3,
         reviewed_by_user_id = $4,
         reviewed_at = NOW(),
         approved_merchant_id = $5,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(requestId),
      toNonEmpty(status, 30),
      toNonEmpty(reviewNote, 2000),
      toPositiveInt(reviewedByUserId),
      toPositiveInt(approvedMerchantId),
    ]
  );
  return r.rows[0] || null;
}

export async function listMerchantCategories(merchantId) {
  const r = await q(
    `SELECT *
     FROM merchant_category
     WHERE merchant_id = $1
     ORDER BY sort_order ASC, id ASC`,
    [Number(merchantId)]
  );
  return r.rows;
}

export async function createMerchantCategory({ merchantId, name, sortOrder = 0 }) {
  const r = await q(
    `INSERT INTO merchant_category (merchant_id, name, sort_order)
     VALUES ($1,$2,$3)
     ON CONFLICT (merchant_id, name)
     DO UPDATE SET sort_order = EXCLUDED.sort_order, updated_at = NOW()
     RETURNING *`,
    [Number(merchantId), toNonEmpty(name, 120), Number(sortOrder || 0)]
  );
  return r.rows[0] || null;
}

export async function listMerchantProducts(merchantId, { productIds = null } = {}) {
  const params = [Number(merchantId)];
  let productSql = "";
  if (Array.isArray(productIds) && productIds.length) {
    params.push(productIds.map((id) => Number(id)));
    productSql = `AND p.id = ANY($${params.length}::bigint[])`;
  }
  const r = await q(
    `SELECT p.*, c.name AS category_name
     FROM product p
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.merchant_id = $1
       ${productSql}
     ORDER BY p.sort_order ASC, p.id ASC`,
    params
  );
  return r.rows;
}

export async function findProductConflict({ merchantId, name, categoryId = null }) {
  const r = await q(
    `SELECT *
     FROM product
     WHERE merchant_id = $1
       AND LOWER(name) = LOWER($2)
       AND (
         ($3::bigint IS NULL AND category_id IS NULL)
         OR category_id = $3
       )
     ORDER BY id ASC
     LIMIT 1`,
    [Number(merchantId), toNonEmpty(name, 150), toPositiveInt(categoryId)]
  );
  return r.rows[0] || null;
}

export async function createProductCopy(copy) {
  const r = await q(
    `INSERT INTO product (
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
      Number(copy.merchantId),
      toPositiveInt(copy.categoryId),
      toNonEmpty(copy.name, 150),
      toNonEmpty(copy.description, 5000),
      Number(copy.price || 0),
      copy.discountedPrice == null ? null : Number(copy.discountedPrice),
      toNonEmpty(copy.imageUrl, 1200),
      copy.freeDelivery === true,
      toNonEmpty(copy.offerLabel, 80),
      copy.isAvailable !== false,
      Number(copy.sortOrder || 0),
    ]
  );
  return r.rows[0] || null;
}

export async function updateProductCopy(productId, copy) {
  const r = await q(
    `UPDATE product
     SET category_id = $2,
         name = $3,
         description = $4,
         price = $5,
         discounted_price = $6,
         image_url = $7,
         free_delivery = $8,
         offer_label = $9,
         is_available = $10,
         sort_order = $11,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      Number(productId),
      toPositiveInt(copy.categoryId),
      toNonEmpty(copy.name, 150),
      toNonEmpty(copy.description, 5000),
      Number(copy.price || 0),
      copy.discountedPrice == null ? null : Number(copy.discountedPrice),
      toNonEmpty(copy.imageUrl, 1200),
      copy.freeDelivery === true,
      toNonEmpty(copy.offerLabel, 80),
      copy.isAvailable !== false,
      Number(copy.sortOrder || 0),
    ]
  );
  return r.rows[0] || null;
}
export async function createCompanyCoupon({
  companyId,
  code,
  description = null,
  discountType,
  discountValue,
  minOrderTotal = 0,
  maxUses = null,
  validFrom = null,
  validUntil = null,
  appliesToAllBranches = false,
  createdByUserId,
}) {
  const r = await q(
    `INSERT INTO coupon (
       code,
       description,
       discount_type,
       discount_value,
       min_order_total,
       max_uses,
       merchant_id,
       valid_from,
       valid_until,
       created_by,
       scope_kind,
       company_id,
       company_applies_to_all_branches
     )
     VALUES ($1,$2,$3,$4,$5,$6,NULL,$7,$8,$9,'company',$10,$11)
     RETURNING *`,
    [
      toNonEmpty(code, 50)?.toUpperCase(),
      toNonEmpty(description, 1000),
      toNonEmpty(discountType, 20),
      Number(discountValue || 0),
      Number(minOrderTotal || 0),
      maxUses == null || maxUses === "" ? null : Number(maxUses),
      validFrom,
      validUntil,
      toPositiveInt(createdByUserId),
      Number(companyId),
      appliesToAllBranches === true,
    ]
  );
  return r.rows[0] || null;
}

export async function replaceCompanyCouponTargets({ couponId, companyId, merchantIds = [] }) {
  await q(`DELETE FROM company_coupon_target WHERE coupon_id = $1`, [Number(couponId)]);
  for (const merchantId of merchantIds) {
    await q(
      `INSERT INTO company_coupon_target (coupon_id, company_id, merchant_id)
       VALUES ($1,$2,$3)
       ON CONFLICT (coupon_id, merchant_id) DO NOTHING`,
      [Number(couponId), Number(companyId), Number(merchantId)]
    );
  }
}

export async function listCompanyCoupons(companyId) {
  const r = await q(
    `SELECT c.*,
            ${couponLifecycleStatusSql("c")} AS coupon_status,
            COALESCE(
              json_agg(
                json_build_object('merchantId', t.merchant_id, 'merchantName', m.name)
                ORDER BY m.name ASC, t.merchant_id ASC
              ) FILTER (WHERE t.id IS NOT NULL),
              '[]'::json
            ) AS targets
     FROM coupon c
     LEFT JOIN company_coupon_target t ON t.coupon_id = c.id
     LEFT JOIN merchant m ON m.id = t.merchant_id
     WHERE c.scope_kind = 'company'
       AND c.company_id = $1
     GROUP BY c.id
     ORDER BY c.created_at DESC, c.id DESC`,
    [Number(companyId)]
  );
  return r.rows.map((row) => ({
    ...row,
    coupon_status: row.coupon_status || "unknown",
  }));
}

export async function createCompanyCampaign({
  companyId,
  title,
  description = null,
  offerType,
  discountValue = null,
  buyQuantity = null,
  getQuantity = null,
  startsAt = null,
  endsAt = null,
  status = 'draft',
  appliesToAllBranches = false,
  maxUsage = null,
  createdByUserId,
}) {
  const r = await q(
    `INSERT INTO company_campaign (
       company_id,
       title,
       description,
       offer_type,
       discount_value,
       buy_quantity,
       get_quantity,
       starts_at,
       ends_at,
       status,
       applies_to_all_branches,
       max_usage,
       created_by_user_id,
       updated_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
     RETURNING *`,
    [
      Number(companyId),
      toNonEmpty(title, 160),
      toNonEmpty(description, 600),
      toNonEmpty(offerType, 32),
      discountValue == null ? null : Number(discountValue),
      buyQuantity == null ? null : Number(buyQuantity),
      getQuantity == null ? null : Number(getQuantity),
      startsAt,
      endsAt,
      toNonEmpty(status, 24) || 'draft',
      appliesToAllBranches === true,
      maxUsage == null ? null : Number(maxUsage),
      toPositiveInt(createdByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function replaceCompanyCampaignTargets({ companyCampaignId, merchantIds = [] }) {
  await q(`DELETE FROM company_campaign_target WHERE company_campaign_id = $1`, [Number(companyCampaignId)]);
  for (const merchantId of merchantIds) {
    await q(
      `INSERT INTO company_campaign_target (company_campaign_id, merchant_id)
       VALUES ($1,$2)
       ON CONFLICT (company_campaign_id, merchant_id) DO NOTHING`,
      [Number(companyCampaignId), Number(merchantId)]
    );
  }
}

export async function listCompanyCampaigns(companyId) {
  const r = await q(
    `SELECT cc.*,
            COALESCE(
              json_agg(
                json_build_object('merchantId', t.merchant_id, 'merchantName', m.name)
                ORDER BY m.name ASC, t.merchant_id ASC
              ) FILTER (WHERE t.id IS NOT NULL),
              '[]'::json
            ) AS targets
     FROM company_campaign cc
     LEFT JOIN company_campaign_target t ON t.company_campaign_id = cc.id
     LEFT JOIN merchant m ON m.id = t.merchant_id
     WHERE cc.company_id = $1
     GROUP BY cc.id
     ORDER BY cc.created_at DESC, cc.id DESC`,
    [Number(companyId)]
  );
  return r.rows;
}

export async function materializeCompanyCampaignOffer({
  merchantId,
  companyCampaignId,
  campaign,
  actorUserId,
}) {
  const existing = await q(
    `SELECT id
     FROM merchant_offer
     WHERE merchant_id = $1
       AND company_campaign_id = $2
     LIMIT 1`,
    [Number(merchantId), Number(companyCampaignId)]
  );

  if (existing.rows[0]?.id) {
    const updated = await q(
      `UPDATE merchant_offer
       SET title = $3,
           description = $4,
           offer_type = $5,
           discount_value = $6,
           buy_quantity = $7,
           get_quantity = $8,
           starts_at = $9,
           ends_at = $10,
           status = $11,
           max_usage = $12,
           updated_by_user_id = $13,
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(existing.rows[0].id),
        Number(merchantId),
        toNonEmpty(campaign.title, 160),
        toNonEmpty(campaign.description, 600),
        toNonEmpty(campaign.offer_type, 32),
        campaign.discount_value == null ? null : Number(campaign.discount_value),
        campaign.buy_quantity == null ? null : Number(campaign.buy_quantity),
        campaign.get_quantity == null ? null : Number(campaign.get_quantity),
        campaign.starts_at,
        campaign.ends_at,
        toNonEmpty(campaign.status, 24),
        campaign.max_usage == null ? null : Number(campaign.max_usage),
        toPositiveInt(actorUserId),
      ]
    );
    return updated.rows[0] || null;
  }

  const inserted = await q(
    `INSERT INTO merchant_offer (
       merchant_id,
       company_campaign_id,
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
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
     RETURNING *`,
    [
      Number(merchantId),
      Number(companyCampaignId),
      toNonEmpty(campaign.title, 160),
      toNonEmpty(campaign.description, 600),
      toNonEmpty(campaign.offer_type, 32),
      campaign.discount_value == null ? null : Number(campaign.discount_value),
      campaign.buy_quantity == null ? null : Number(campaign.buy_quantity),
      campaign.get_quantity == null ? null : Number(campaign.get_quantity),
      campaign.starts_at,
      campaign.ends_at,
      toNonEmpty(campaign.status, 24),
      campaign.max_usage == null ? null : Number(campaign.max_usage),
      toPositiveInt(actorUserId),
    ]
  );
  return inserted.rows[0] || null;
}
export async function ensureInventorySettings(merchantId, { companyId = null, updatedByUserId = null } = {}) {
  const r = await q(
    `INSERT INTO inventory_settings (
       merchant_id,
       company_id,
       updated_by_user_id
     )
     VALUES ($1,$2,$3)
     ON CONFLICT (merchant_id)
     DO UPDATE SET company_id = COALESCE(EXCLUDED.company_id, inventory_settings.company_id)
     RETURNING *`,
    [Number(merchantId), toPositiveInt(companyId), toPositiveInt(updatedByUserId)]
  );
  return r.rows[0] || null;
}

export async function getInventorySettings(merchantId) {
  const r = await q(
    `SELECT *
     FROM inventory_settings
     WHERE merchant_id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function upsertInventorySettings(merchantId, patch = {}, { companyId = null, updatedByUserId = null } = {}) {
  const current = await ensureInventorySettings(merchantId, { companyId, updatedByUserId });
  const next = {
    inventoryEnabled: patch.inventoryEnabled ?? current.inventory_enabled,
    dailyUpdateMode: patch.dailyUpdateMode ?? current.daily_update_mode,
    lowStockThreshold: patch.lowStockThreshold ?? current.low_stock_threshold,
    autoDisableOutOfStock: patch.autoDisableOutOfStock ?? current.auto_disable_out_of_stock,
    showAllWithoutAutoDisable:
      patch.showAllWithoutAutoDisable ?? current.show_all_without_auto_disable,
    lastDailyCheckAt: patch.lastDailyCheckAt ?? current.last_daily_check_at,
    lastStockUpdateAt: patch.lastStockUpdateAt ?? current.last_stock_update_at,
  };
  const r = await q(
    `UPDATE inventory_settings
     SET company_id = COALESCE($2, company_id),
         inventory_enabled = $3,
         daily_update_mode = $4,
         low_stock_threshold = $5,
         auto_disable_out_of_stock = $6,
         show_all_without_auto_disable = $7,
         last_daily_check_at = $8,
         last_stock_update_at = $9,
         updated_by_user_id = $10,
         updated_at = NOW()
     WHERE merchant_id = $1
     RETURNING *`,
    [
      Number(merchantId),
      toPositiveInt(companyId),
      next.inventoryEnabled === true,
      toNonEmpty(next.dailyUpdateMode, 30) || 'manual_override',
      Number(next.lowStockThreshold || 0),
      next.autoDisableOutOfStock !== false,
      next.showAllWithoutAutoDisable === true,
      next.lastDailyCheckAt,
      next.lastStockUpdateAt,
      toPositiveInt(updatedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function listMerchantInventoryItems(merchantId) {
  const r = await q(
    `SELECT si.*, p.name AS product_name, p.image_url AS product_image_url, p.is_available, p.price, p.discounted_price
     FROM store_inventory_item si
     JOIN product p ON p.id = si.product_id
     WHERE si.merchant_id = $1
     ORDER BY p.sort_order ASC, p.id ASC`,
    [Number(merchantId)]
  );
  return r.rows;
}

export async function upsertInventoryItem({
  merchantId,
  productId,
  quantity,
  reorderThreshold = null,
  manualDisabled = false,
  autoDisabled = false,
  stockStatus,
  updatedByUserId,
}) {
  const r = await q(
    `INSERT INTO store_inventory_item (
       merchant_id,
       product_id,
       quantity,
       reorder_threshold,
       manual_disabled,
       auto_disabled,
       stock_status,
       last_quantity_update_at,
       updated_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,NOW(),$8)
     ON CONFLICT (merchant_id, product_id)
     DO UPDATE SET
       quantity = EXCLUDED.quantity,
       reorder_threshold = EXCLUDED.reorder_threshold,
       manual_disabled = EXCLUDED.manual_disabled,
       auto_disabled = EXCLUDED.auto_disabled,
       stock_status = EXCLUDED.stock_status,
       last_quantity_update_at = NOW(),
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(merchantId),
      Number(productId),
      Number(quantity || 0),
      reorderThreshold == null ? null : Number(reorderThreshold),
      manualDisabled === true,
      autoDisabled === true,
      toNonEmpty(stockStatus, 24) || 'in_stock',
      toPositiveInt(updatedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function updateProductAvailability(productId, isAvailable) {
  const r = await q(
    `UPDATE product
     SET is_available = $2,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(productId), isAvailable === true]
  );
  return r.rows[0] || null;
}

export async function upsertInventoryDailyCheck({ merchantId, note = null, modeAtCheck, confirmedByUserId }) {
  const r = await q(
    `INSERT INTO inventory_daily_check (
       merchant_id,
       check_date,
       confirmed_by_user_id,
       mode_at_check,
       note
     )
     VALUES ($1, CURRENT_DATE, $2, $3, $4)
     ON CONFLICT (merchant_id, check_date)
     DO UPDATE SET
       confirmed_by_user_id = EXCLUDED.confirmed_by_user_id,
       mode_at_check = EXCLUDED.mode_at_check,
       note = EXCLUDED.note,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(merchantId),
      toPositiveInt(confirmedByUserId),
      toNonEmpty(modeAtCheck, 30) || 'manual_override',
      toNonEmpty(note, 2000),
    ]
  );
  return r.rows[0] || null;
}

export async function insertInventoryAuditLog({
  merchantId,
  productId = null,
  actorUserId = null,
  actorContext,
  actionKey,
  summary,
  actorRole = null,
  variantId = null,
  reason = null,
  unavailableUntil = null,
  oldValue = {},
  newValue = {},
  note = null,
}) {
  await q(
    `INSERT INTO inventory_audit_log (
       merchant_id,
       product_id,
       actor_user_id,
       actor_context,
       action_key,
       summary,
       actor_role,
       variant_id,
       reason,
       unavailable_until,
       old_value,
       new_value,
       note
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::timestamptz,$11::jsonb,$12::jsonb,$13)`,
    [
      Number(merchantId),
      toPositiveInt(productId),
      toPositiveInt(actorUserId),
      toNonEmpty(actorContext, 40),
      toNonEmpty(actionKey, 120),
      toNonEmpty(summary, 2000),
      toNonEmpty(actorRole, 40),
      toPositiveInt(variantId),
      toNonEmpty(reason, 2000),
      unavailableUntil ? new Date(unavailableUntil).toISOString() : null,
      JSON.stringify(toJson(oldValue)),
      JSON.stringify(toJson(newValue)),
      toNonEmpty(note, 2000),
    ]
  );
}

export async function insertCompanyAuditLog({
  companyId,
  actorUserId = null,
  actorRole = null,
  actionKey,
  summary,
  targetType = null,
  targetId = null,
  targetLabel = null,
  metadata = {},
}) {
  await q(
    `INSERT INTO company_audit_log (
       company_id,
       actor_user_id,
       actor_role,
       action_key,
       summary,
       target_type,
       target_id,
       target_label,
       metadata
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)`,
    [
      Number(companyId),
      toPositiveInt(actorUserId),
      toNonEmpty(actorRole, 40),
      toNonEmpty(actionKey, 120),
      toNonEmpty(summary, 2000),
      toNonEmpty(targetType, 80),
      toPositiveInt(targetId),
      toNonEmpty(targetLabel, 240),
      JSON.stringify(toJson(metadata)),
    ]
  );
}
