import { AppError } from "../../shared/utils/errors.js";
import { hashPin } from "../../shared/utils/hash.js";
import * as authService from "../auth/auth.service.js";
import {
  createUser,
  findUserByPhone,
  findUserByIdWithAuthFields,
  getUserPublicById,
  isUsernameTaken,
} from "../auth/auth.repo.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import { createMerchant as createMerchantByAdmin } from "../merchants/merchants.service.js";
import {
  createMerchantWithOwnerLink,
  invalidateMerchantCatalogCache,
} from "../merchants/merchants.repo.js";
import { updateMerchantBillingProfile } from "../commerce/commerce.repo.js";
import * as repo from "./company.repo.js";

const COMPANY_ROLES = new Set([
  "company_owner",
  "company_manager",
  "finance_viewer",
  "operations_viewer",
]);

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

function normalizeCompanyCode(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized ? normalized.slice(0, 40) : null;
}

function normalizeUsernameCandidate(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._]+/g, ".")
    .replace(/[._]{2,}/g, ".")
    .replace(/^[._]+|[._]+$/g, "");
}

function sanitizeUsernameBase(value) {
  const normalized = normalizeUsernameCandidate(value);
  if (normalized.length < 4) return null;
  const sliced = normalized
    .replace(/^[._]+|[._]+$/g, "")
    .slice(0, 24)
    .replace(/^[._]+|[._]+$/g, "");
  return sliced.length >= 4 ? sliced : null;
}

function buildUsernameVariant(base, suffix) {
  const normalizedBase = sanitizeUsernameBase(base);
  const normalizedSuffix = String(suffix || "")
    .trim()
    .replace(/[^\d]/g, "");
  if (!normalizedBase) return null;
  if (!normalizedSuffix) return normalizedBase;
  const separator = ".";
  const maxBaseLength = Math.max(
    1,
    24 - separator.length - normalizedSuffix.length
  );
  const trimmedBase = normalizedBase
    .slice(0, maxBaseLength)
    .replace(/[._]+$/g, "");
  const candidate = `${trimmedBase}${separator}${normalizedSuffix}`.replace(
    /^[._]+|[._]+$/g,
    ""
  );
  return candidate.length >= 4 ? candidate : null;
}

async function allocateCompanyUsername({ fullName, phone }) {
  const phoneDigits = String(phone || "").replace(/[^0-9]/g, "");
  const phoneSuffix = phoneDigits.slice(-4) || "0001";
  const baseCandidates = [
    sanitizeUsernameBase(fullName),
    sanitizeUsernameBase(`company.${phoneSuffix}`),
    sanitizeUsernameBase(`hq.${phoneSuffix}`),
  ].filter(Boolean);

  for (const baseCandidate of baseCandidates) {
    if (!(await isUsernameTaken(baseCandidate))) return baseCandidate;
    for (let i = 2; i <= 9999; i += 1) {
      const candidate = buildUsernameVariant(baseCandidate, i);
      if (!candidate || candidate.length < 4) continue;
      if (!(await isUsernameTaken(candidate))) return candidate;
    }
  }

  throw new AppError("COMPANY_USERNAME_GENERATION_FAILED", { status: 500 });
}

function mapCompany(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    name: row.name,
    legalName: row.legal_name || null,
    brandName: row.brand_name || null,
    code: row.code,
    contactPhone: row.contact_phone || null,
    contactEmail: row.contact_email || null,
    logoUrl: row.logo_url || null,
    summary: row.summary || null,
    businessType: row.business_type || null,
    headquartersAddress: row.headquarters_address || null,
    primaryContactName: row.primary_contact_name || null,
    supportPhone: row.support_phone || null,
    websiteUrl: row.website_url || null,
    registrationNumber: row.registration_number || null,
    taxNumber: row.tax_number || null,
    status: row.status,
    notes: row.notes || null,
    branchesCount:
      row.branches_count == null ? undefined : Number(row.branches_count || 0),
    usersCount: row.users_count == null ? undefined : Number(row.users_count || 0),
    activeUsersCount:
      row.active_users_count == null
        ? undefined
        : Number(row.active_users_count || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapMembership(row) {
  return {
    id: Number(row.id),
    companyId: Number(row.company_id),
    userId: Number(row.user_id),
    role: row.role,
    permissions: row.permissions_json || {},
    isActive: row.is_active === true,
    companyName: row.company_name || null,
    companyCode: row.company_code || null,
    companyStatus: row.company_status || null,
    joinedAt: row.joined_at || null,
  };
}

function mapCompanyUser(row) {
  return {
    id: Number(row.id),
    companyId: Number(row.company_id),
    userId: Number(row.user_id),
    role: row.role,
    permissions: row.permissions_json || {},
    isActive: row.is_active === true,
    joinedAt: row.joined_at,
    user: {
      id: Number(row.user_id),
      fullName: row.full_name,
      username: row.username || null,
      phone: row.phone,
      imageUrl: row.image_url || null,
      workTitle: row.work_title || null,
      workCompany: row.work_company || null,
    },
  };
}

function mapBranch(row) {
  return {
    id: Number(row.id),
    name: row.name,
    type: row.type,
    description: row.description || null,
    phone: row.phone || null,
    imageUrl: row.image_url || null,
    isOpen: row.is_open === true,
    isApproved: row.is_approved === true,
    isDisabled: row.is_disabled === true,
    ownerUserId: row.owner_user_id ? Number(row.owner_user_id) : null,
    ownerFullName: row.owner_full_name || null,
    ownerPhone: row.owner_phone || null,
    totalOrders: Number(row.total_orders || 0),
    completedOrders: Number(row.completed_orders || 0),
    cancelledOrders: Number(row.cancelled_orders || 0),
    activeOrders: Number(row.active_orders || 0),
    grossSales: Number(row.gross_sales || 0),
    appDue: Number(row.app_due || 0),
    totalCollected: Number(row.total_collected || 0),
    outstandingAmount: Number(row.outstanding_amount || 0),
    trackedItems: Number(row.tracked_items || 0),
    outOfStockItems: Number(row.out_of_stock_items || 0),
    lowStockItems: Number(row.low_stock_items || 0),
    inventoryEnabled: row.inventory_enabled === true,
    dailyUpdateMode: row.daily_update_mode || null,
    lastDailyCheckAt: row.last_daily_check_at || null,
    lastInventoryUpdateAt: row.last_inventory_update_at || null,
    showAllWithoutAutoDisable: row.show_all_without_auto_disable === true,
    createdAt: row.created_at,
  };
}

function mapBranchRequest(row) {
  return {
    id: Number(row.id),
    companyId: Number(row.company_id),
    companyName: row.company_name || null,
    companyCode: row.company_code || null,
    requestedName: row.requested_name,
    requestedType: row.requested_type,
    requestedDescription: row.requested_description || null,
    requestedPhone: row.requested_phone || null,
    requestedImageUrl: row.requested_image_url || null,
    requestedTagline: row.requested_tagline || null,
    requestedWorkingHours: row.requested_working_hours || null,
    requestedServiceAreaNote: row.requested_service_area_note || null,
    branchLocationLabel: row.branch_location_label || null,
    ownerFullName: row.proposed_owner_full_name || null,
    ownerPhone: row.proposed_owner_phone || null,
    ownerBlock: row.proposed_owner_block || null,
    ownerBuildingNumber: row.proposed_owner_building_number || null,
    ownerApartment: row.proposed_owner_apartment || null,
    policyOverrideJson: row.requested_policy_override_json || {},
    status: row.status,
    reviewNote: row.review_note || null,
    approvedMerchantId: row.approved_merchant_id ? Number(row.approved_merchant_id) : null,
    approvedMerchantName: row.approved_merchant_name || null,
    createdByFullName: row.created_by_full_name || null,
    reviewedByFullName: row.reviewed_by_full_name || null,
    createdAt: row.created_at,
    reviewedAt: row.reviewed_at || null,
  };
}

function ensureCompanyRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  if (!COMPANY_ROLES.has(normalized)) {
    throw new AppError("INVALID_COMPANY_ROLE", { status: 400 });
  }
  return normalized;
}
async function ensureCompanyBranch(companyId, merchantId) {
  const merchant = await repo.findMerchantById(merchantId);
  if (!merchant || Number(merchant.company_id || 0) !== Number(companyId)) {
    throw new AppError("COMPANY_BRANCH_NOT_FOUND", { status: 404 });
  }
  return merchant;
}

async function resolveCompanyTargetMerchantIds(companyId, { appliesToAllBranches = false, targetMerchantIds = [] } = {}) {
  const branches = await repo.listCompanyBranches(companyId, { limit: 5000, offset: 0 });
  const branchIds = new Set(branches.map((row) => Number(row.id)));
  if (appliesToAllBranches) return [...branchIds];
  const ids = [...new Set((Array.isArray(targetMerchantIds) ? targetMerchantIds : []).map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0))];
  if (!ids.length) {
    throw new AppError("COMPANY_TARGET_BRANCHES_REQUIRED", { status: 400 });
  }
  for (const id of ids) {
    if (!branchIds.has(id)) {
      throw new AppError("FORBIDDEN_COMPANY_BRANCH_SCOPE", { status: 403 });
    }
  }
  return ids;
}

async function createCompanyPortalUser({ fullName, phone, pin, workTitle = null, workCompany = null }) {
  const existing = await findUserByPhone(phone);
  if (existing) {
    if (String(existing.role || "").trim().toLowerCase() === "company_portal") {
      return existing;
    }
    throw new AppError("COMPANY_OWNER_PHONE_ROLE_CONFLICT", { status: 409 });
  }
  const pinHash = await hashPin(pin);
  const normalizedFullName = toNonEmpty(fullName, 180);
  const normalizedPhone = toNonEmpty(phone, 30);
  return authService.runWithGeneratedAppUserUsername({
    fullName: normalizedFullName,
    phone: normalizedPhone,
    allocator: allocateCompanyUsername,
    execute: (username) =>
      createUser({
        fullName: normalizedFullName,
        username,
        phone: normalizedPhone,
        pinHash,
        block: "HQ",
        buildingNumber: "1",
        apartment: "1",
        workTitle: toNonEmpty(workTitle, 160),
        workCompany: toNonEmpty(workCompany, 180),
        role: "company_portal",
        analyticsConsentGranted: true,
        analyticsConsentVersion: "company_portal_admin_v1",
        analyticsConsentGrantedAt: new Date(),
      }),
  });
}

async function resolveCompanyOwnerUser({ ownerUserId, owner = {}, companyName }) {
  const normalizedOwnerUserId = toPositiveInt(ownerUserId);
  if (normalizedOwnerUserId) {
    const ownerUser = await findUserByIdWithAuthFields(normalizedOwnerUserId);
    if (!ownerUser || String(ownerUser.role || "").trim().toLowerCase() !== "company_portal") {
      throw new AppError("COMPANY_OWNER_ACCOUNT_REQUIRED", { status: 400 });
    }
    return Number(ownerUser.id);
  }

  if (!owner || !owner.fullName || !owner.phone || !owner.pin) {
    throw new AppError("COMPANY_OWNER_REQUIRED", { status: 400 });
  }

  const ownerUser = await createCompanyPortalUser({
    fullName: owner.fullName,
    phone: owner.phone,
    pin: owner.pin,
    workTitle: owner.workTitle || "Company Owner",
    workCompany: companyName,
  });
  return Number(ownerUser.id);
}

async function resolveBranchOwnerApprovalUserId({
  ownerUserId,
  ownerPhone,
}) {
  const normalizedOwnerUserId = toPositiveInt(ownerUserId);
  if (normalizedOwnerUserId) return normalizedOwnerUserId;

  const normalizedPhone = toNonEmpty(ownerPhone, 30);
  if (!normalizedPhone) return null;

  const existingUser = await findUserByPhone(normalizedPhone);
  if (!existingUser) return null;

  const existingRole = String(existingUser.role || "").trim().toLowerCase();
  if (existingRole !== "owner") {
    throw new AppError("COMPANY_BRANCH_OWNER_PHONE_ROLE_CONFLICT", {
      status: 409,
    });
  }

  return Number(existingUser.id);
}

async function applyEffectiveBranchPolicy({ merchantId, companyId, policyOverrideJson = {}, actorUserId }) {
  const defaults = (await repo.getCompanyDefaultPolicy(companyId)) || null;
  const overrides = policyOverrideJson && typeof policyOverrideJson === "object" ? policyOverrideJson : {};
  if (defaults) {
    await updateMerchantBillingProfile({
      adminUserId: Number(actorUserId),
      merchantId: Number(merchantId),
      commissionRate:
        overrides.commissionRate ?? defaults.commission_rate ?? null,
      serviceFeeMode:
        overrides.serviceFeeMode ?? defaults.service_fee_mode ?? null,
      serviceFeeValue:
        overrides.serviceFeeValue ?? defaults.service_fee_value ?? null,
      deliveryFeeMode:
        overrides.deliveryFeeMode ?? defaults.delivery_fee_mode ?? null,
      deliveryFeeValue:
        overrides.deliveryFeeValue ?? defaults.delivery_fee_value ?? null,
      appDeliveryEnabled:
        overrides.appDeliveryEnabled ?? defaults.app_delivery_enabled ?? null,
      merchantDeliveryEnabled:
        overrides.merchantDeliveryEnabled ?? defaults.merchant_delivery_enabled ?? null,
      settlementCycle:
        overrides.settlementCycle ?? defaults.settlement_cycle ?? null,
      changeKind: "company_policy_inheritance",
    });
  }

  await repo.upsertInventorySettings(
    Number(merchantId),
    {
      inventoryEnabled:
        overrides.inventoryEnabled ?? defaults?.inventory_enabled ?? false,
      dailyUpdateMode:
        overrides.inventoryUpdateMode ?? defaults?.inventory_update_mode ?? "manual_override",
      lowStockThreshold:
        overrides.lowStockThreshold ?? defaults?.low_stock_threshold ?? 5,
      autoDisableOutOfStock:
        overrides.autoDisableOutOfStock ?? defaults?.auto_disable_out_of_stock ?? true,
      showAllWithoutAutoDisable:
        overrides.showAllWithoutAutoDisable ?? defaults?.show_all_without_auto_disable ?? false,
    },
    {
      companyId: Number(companyId),
      updatedByUserId: Number(actorUserId),
    }
  );
}

export async function loginCompany(credentials, deviceContext = {}) {
  const out = await authService.login(credentials, deviceContext);
  if (String(out?.user?.role || "").trim().toLowerCase() !== "company_portal") {
    throw new AppError("FORBIDDEN_COMPANY_PORTAL_ONLY", { status: 403 });
  }
  const memberships = await repo.listActiveMembershipsByUserId(out.user.id);
  return {
    ...out,
    memberships: memberships.map(mapMembership),
  };
}

export async function bootstrapCompanyPortal(userId) {
  const user = await findUserByIdWithAuthFields(Number(userId));
  if (!user) {
    throw new AppError("USER_NOT_FOUND", { status: 404 });
  }
  if (String(user.role || "").trim().toLowerCase() !== "company_portal") {
    throw new AppError("FORBIDDEN_COMPANY_PORTAL_ONLY", { status: 403 });
  }
  const memberships = await repo.listActiveMembershipsByUserId(Number(userId));
  return {
    user: {
      id: Number(user.id),
      fullName: user.full_name,
      username: user.username || null,
      phone: user.phone,
      role: user.role,
      imageUrl: user.image_url || null,
      workTitle: user.work_title || null,
      workCompany: user.work_company || null,
    },
    memberships: memberships.map(mapMembership),
  };
}

export async function listAdminCompanies(query = {}) {
  const rows = await repo.listCompaniesAdmin(query || {});
  return { companies: rows.map(mapCompany) };
}
export async function createAdminCompany(dto, actor = {}) {
  const actorUserId = Number(actor.userId || 0);
  const ownerRole = ensureCompanyRole(dto.owner?.role || "company_owner");

  const codeBase = normalizeCompanyCode(dto.code) || normalizeCompanyCode(dto.name);
  if (!codeBase) {
    throw new AppError("COMPANY_CODE_REQUIRED", { status: 400 });
  }
  const existingCode = await repo.findCompanyByCode(codeBase);
  if (existingCode) {
    throw new AppError("COMPANY_CODE_EXISTS", { status: 409 });
  }

  const ownerUserId = await resolveCompanyOwnerUser({
    ownerUserId: dto.ownerUserId,
    owner: dto.owner,
    companyName: dto.name,
  });

  const company = await repo.createCompany({
    name: dto.name,
    legalName: dto.legalName,
    brandName: dto.brandName,
    code: codeBase,
    contactPhone: dto.contactPhone,
    contactEmail: dto.contactEmail,
    logoUrl: dto.logoUrl,
    summary: dto.summary,
    businessType: dto.businessType,
    headquartersAddress: dto.headquartersAddress,
    primaryContactName: dto.primaryContactName,
    supportPhone: dto.supportPhone,
    websiteUrl: dto.websiteUrl,
    registrationNumber: dto.registrationNumber,
    taxNumber: dto.taxNumber,
    notes: dto.notes,
    status: dto.status || "active",
    createdByUserId: actorUserId || null,
  });

  await repo.addOrUpdateCompanyUser({
    companyId: Number(company.id),
    userId: ownerUserId,
    role: ownerRole,
    permissionsJson: dto.owner?.permissionsJson || {},
    isActive: true,
    invitedByUserId: actorUserId || null,
  });

  await repo.upsertCompanyDefaultPolicy(Number(company.id), dto.defaultPolicy || {}, {
    updatedByUserId: actorUserId || ownerUserId,
  });

  await repo.insertCompanyAuditLog({
    companyId: Number(company.id),
    actorUserId: actorUserId || ownerUserId,
    actorRole: actor.role || "admin",
    actionKey: "company.admin.created",
    summary: `Created company ${company.name}`,
    targetType: "company",
    targetId: Number(company.id),
    targetLabel: company.name,
  });

  return {
    company: mapCompany(await repo.findCompanyById(Number(company.id))),
  };
}

export async function updateAdminCompany(companyId, dto, actor = {}) {
  if (dto.code !== undefined) {
    const normalizedCode = normalizeCompanyCode(dto.code);
    if (!normalizedCode) {
      throw new AppError("COMPANY_CODE_REQUIRED", { status: 400 });
    }
    const existingCode = await repo.findCompanyByCode(normalizedCode);
    if (existingCode && Number(existingCode.id) !== Number(companyId)) {
      throw new AppError("COMPANY_CODE_EXISTS", { status: 409 });
    }
    dto = { ...dto, code: normalizedCode };
  }
  const updated = await repo.updateCompany(companyId, dto, {
    updatedByUserId: actor.userId || null,
  });
  if (!updated) {
    throw new AppError("COMPANY_NOT_FOUND", { status: 404 });
  }
  if (dto.defaultPolicy) {
    await repo.upsertCompanyDefaultPolicy(Number(companyId), dto.defaultPolicy, {
      updatedByUserId: actor.userId || null,
    });
  }
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || "admin",
    actionKey: "company.admin.updated",
    summary: `Updated company ${updated.name}`,
    targetType: "company",
    targetId: Number(companyId),
    targetLabel: updated.name,
    metadata: { patch: dto },
  });
  return {
    company: mapCompany(await repo.findCompanyById(Number(companyId))),
    defaultPolicy: await repo.getCompanyDefaultPolicy(Number(companyId)),
  };
}

export async function deleteAdminCompany(companyId, actor = {}) {
  const found = await repo.findCompanyById(Number(companyId));
  if (!found) {
    throw new AppError("COMPANY_NOT_FOUND", { status: 404 });
  }
  const deleted = await repo.deleteCompany(Number(companyId));
  if (!deleted) {
    throw new AppError("COMPANY_NOT_FOUND", { status: 404 });
  }
  return {
    ok: true,
    deletedCompany: mapCompany(found),
  };
}

export async function linkAdminCompanyBranch({ companyId, merchantId }, actor = {}) {
  const company = await repo.findCompanyById(Number(companyId));
  if (!company) throw new AppError("COMPANY_NOT_FOUND", { status: 404 });
  const merchant = await repo.findMerchantById(Number(merchantId));
  if (!merchant) throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
  const linked = await repo.linkMerchantToCompany({ companyId, merchantId });
  await applyEffectiveBranchPolicy({
    merchantId: Number(merchantId),
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || "admin",
    actionKey: "company.branch.linked",
    summary: `Linked branch ${merchant.name}`,
    targetType: "merchant",
    targetId: Number(merchantId),
    targetLabel: merchant.name,
  });
  return { branch: mapBranch(linked) };
}

export async function unlinkAdminCompanyBranch({ companyId, merchantId }, actor = {}) {
  const merchant = await ensureCompanyBranch(companyId, merchantId);
  await repo.unlinkMerchantFromCompany({ companyId, merchantId });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || "admin",
    actionKey: "company.branch.unlinked",
    summary: `Unlinked branch ${merchant.name}`,
    targetType: "merchant",
    targetId: Number(merchantId),
    targetLabel: merchant.name,
  });
  return { ok: true };
}
export async function getCompanyHome(companyId) {
  const company = await repo.findCompanyById(Number(companyId));
  if (!company) throw new AppError("COMPANY_NOT_FOUND", { status: 404 });
  const [dashboard, policy] = await Promise.all([
    repo.getCompanyDashboard(Number(companyId)),
    repo.getCompanyDefaultPolicy(Number(companyId)),
  ]);
  return {
    company: mapCompany(company),
    dashboard: {
      branchesCount: Number(dashboard?.branches_count || 0),
      totalOrders: Number(dashboard?.total_orders || 0),
      completedOrders: Number(dashboard?.completed_orders || 0),
      cancelledOrders: Number(dashboard?.cancelled_orders || 0),
      activeOrders: Number(dashboard?.active_orders || 0),
      totalSales: Number(dashboard?.total_sales || 0),
      totalServiceFees: Number(dashboard?.total_service_fees || 0),
      totalAppDeliveryFees: Number(dashboard?.total_app_delivery_fees || 0),
      totalAppDue: Number(dashboard?.total_app_due || 0),
      totalCollected: Number(dashboard?.total_collected || 0),
      totalOutstanding: Number(dashboard?.total_outstanding || 0),
      bestBranch: dashboard?.best_branch || null,
      weakestBranch: dashboard?.weakest_branch || null,
    },
    defaultPolicy: policy,
  };
}

export async function listCompanyBranches(companyId, query = {}) {
  const rows = await repo.listCompanyBranches(Number(companyId), query || {});
  return { branches: rows.map(mapBranch) };
}

export async function getCompanyBranchDetail(companyId, merchantId) {
  const merchant = await ensureCompanyBranch(companyId, merchantId);
  const [inventorySettings, inventoryItems, products, categories] = await Promise.all([
    repo.getInventorySettings(Number(merchantId)),
    repo.listMerchantInventoryItems(Number(merchantId)),
    repo.listMerchantProducts(Number(merchantId)),
    repo.listMerchantCategories(Number(merchantId)),
  ]);
  return {
    branch: mapBranch(merchant),
    inventorySettings,
    inventoryItems: inventoryItems.map((row) => ({
      id: Number(row.id),
      productId: Number(row.product_id),
      productName: row.product_name,
      productImageUrl: row.product_image_url || null,
      price: Number(row.price || 0),
      discountedPrice: row.discounted_price == null ? null : Number(row.discounted_price),
      quantity: Number(row.quantity || 0),
      stockStatus: row.stock_status,
      reorderThreshold: row.reorder_threshold == null ? null : Number(row.reorder_threshold),
      manualDisabled: row.manual_disabled === true,
      autoDisabled: row.auto_disabled === true,
      productIsAvailable: row.is_available === true,
      updatedAt: row.updated_at,
    })),
    products,
    categories,
  };
}

export async function listCompanyUsers(companyId) {
  const rows = await repo.listCompanyUsers(Number(companyId));
  return { users: rows.map(mapCompanyUser) };
}

export async function createCompanyUser(companyId, body, actor = {}) {
  const role = ensureCompanyRole(body.role);
  const created = await createCompanyPortalUser({
    fullName: body.fullName,
    phone: body.phone,
    pin: body.pin,
    workTitle: body.workTitle || null,
    workCompany: body.workCompany || null,
  });
  await repo.addOrUpdateCompanyUser({
    companyId: Number(companyId),
    userId: Number(created.id),
    role,
    permissionsJson: body.permissionsJson || {},
    isActive: true,
    invitedByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.user.created",
    summary: `Added company user ${created.full_name}`,
    targetType: "user",
    targetId: Number(created.id),
    targetLabel: created.full_name,
    metadata: { role },
  });
  return listCompanyUsers(companyId);
}

export async function updateCompanyPolicy(companyId, patch, actor = {}) {
  const policy = await repo.upsertCompanyDefaultPolicy(Number(companyId), patch || {}, {
    updatedByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.policy.updated",
    summary: "Updated company default policy",
    metadata: { patch },
  });
  return { defaultPolicy: policy };
}

export async function createCompanyBranchRequest(companyId, body, actor = {}) {
  const ownerPinHash = await hashPin(body.ownerPin);
  const created = await repo.createCompanyBranchRequest({
    companyId: Number(companyId),
    body,
    ownerPinHash,
    createdByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.branch_request.created",
    summary: `Requested new branch ${created.requested_name}`,
    targetType: "branch_request",
    targetId: Number(created.id),
    targetLabel: created.requested_name,
  });
  return { request: mapBranchRequest(created) };
}

export async function listCompanyBranchRequests(companyId, query = {}) {
  const rows = await repo.listCompanyBranchRequests(Number(companyId), query || {});
  return { requests: rows.map(mapBranchRequest) };
}
export async function listAdminPendingBranchRequests() {
  const rows = await repo.listPendingCompanyBranchRequestsAdmin();
  return { requests: rows.map(mapBranchRequest) };
}

export async function approveAdminBranchRequest(requestId, review = {}, actor = {}) {
  const row = await repo.findCompanyBranchRequestById(Number(requestId));
  if (!row) throw new AppError("COMPANY_BRANCH_REQUEST_NOT_FOUND", { status: 404 });
  if (row.status !== "pending_admin_review") {
    throw new AppError("COMPANY_BRANCH_REQUEST_ALREADY_REVIEWED", { status: 409 });
  }

  const existingOwnerUserId = await resolveBranchOwnerApprovalUserId({
    ownerUserId: review.ownerUserId,
    ownerPhone: row.proposed_owner_phone,
  });

  let merchant = null;
  if (existingOwnerUserId) {
    merchant = await createMerchantByAdmin(
      {
        name: row.requested_name,
        type: row.requested_type,
        description: row.requested_description || null,
        phone: row.requested_phone || row.proposed_owner_phone || null,
        imageUrl: row.requested_image_url || null,
        ownerUserId: Number(existingOwnerUserId),
      },
      actor.userId || null
    );
  } else {
    merchant = await authService.runWithGeneratedAppUserUsername({
      fullName: row.proposed_owner_full_name,
      phone: row.proposed_owner_phone,
      execute: (username) =>
        createMerchantWithOwnerLink({
          merchant: {
            name: row.requested_name,
            type: row.requested_type,
            description: row.requested_description || null,
            phone: row.requested_phone || row.proposed_owner_phone || null,
            imageUrl: row.requested_image_url || null,
          },
          approvedByUserId: actor.userId || null,
          ownerUserId: null,
          ownerToCreate: {
            fullName: row.proposed_owner_full_name,
            username,
            phone: row.proposed_owner_phone,
            block: row.proposed_owner_block,
            buildingNumber: row.proposed_owner_building_number,
            apartment: row.proposed_owner_apartment,
            imageUrl: null,
          },
          ownerPinHash: row.proposed_owner_pin_hash,
        }),
    });
  }

  await repo.linkMerchantToCompany({ companyId: Number(row.company_id), merchantId: Number(merchant.id) });
  await applyEffectiveBranchPolicy({
    merchantId: Number(merchant.id),
    companyId: Number(row.company_id),
    policyOverrideJson: row.requested_policy_override_json || {},
    actorUserId: actor.userId || null,
  });
  const reviewed = await repo.markCompanyBranchRequestReviewed({
    requestId: Number(requestId),
    status: "approved",
    reviewNote: review.reviewNote || null,
    reviewedByUserId: actor.userId || null,
    approvedMerchantId: Number(merchant.id),
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(row.company_id),
    actorUserId: actor.userId || null,
    actorRole: actor.role || "admin",
    actionKey: "company.branch_request.approved",
    summary: `Approved branch request ${row.requested_name}`,
    targetType: "merchant",
    targetId: Number(merchant.id),
    targetLabel: merchant.name,
    metadata: { requestId: Number(requestId) },
  });
  return {
    request: mapBranchRequest(reviewed),
    branch: mapBranch(await repo.findMerchantById(Number(merchant.id))),
  };
}

export async function rejectAdminBranchRequest(requestId, review = {}, actor = {}) {
  const row = await repo.findCompanyBranchRequestById(Number(requestId));
  if (!row) throw new AppError("COMPANY_BRANCH_REQUEST_NOT_FOUND", { status: 404 });
  if (row.status !== "pending_admin_review") {
    throw new AppError("COMPANY_BRANCH_REQUEST_ALREADY_REVIEWED", { status: 409 });
  }
  const reviewed = await repo.markCompanyBranchRequestReviewed({
    requestId: Number(requestId),
    status: "rejected",
    reviewNote: review.reviewNote || null,
    reviewedByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(row.company_id),
    actorUserId: actor.userId || null,
    actorRole: actor.role || "admin",
    actionKey: "company.branch_request.rejected",
    summary: `Rejected branch request ${row.requested_name}`,
    targetType: "branch_request",
    targetId: Number(requestId),
    targetLabel: row.requested_name,
    metadata: { reviewNote: review.reviewNote || null },
  });
  return { request: mapBranchRequest(reviewed) };
}

export async function copyProductsBetweenBranches(companyId, dto, actor = {}) {
  await ensureCompanyBranch(companyId, dto.sourceMerchantId);
  const targetMerchantIds = await resolveCompanyTargetMerchantIds(companyId, {
    targetMerchantIds: dto.targetMerchantIds,
  });
  const conflictStrategy = String(dto.conflictStrategy || "skip").trim().toLowerCase();
  const sourceCategories = await repo.listMerchantCategories(Number(dto.sourceMerchantId));
  const sourceProducts = await repo.listMerchantProducts(Number(dto.sourceMerchantId), {
    productIds: Array.isArray(dto.productIds) && dto.productIds.length ? dto.productIds : null,
  });
  const summary = [];
  const modifiedMerchantIds = new Set();

  for (const targetMerchantId of targetMerchantIds) {
    const targetCategories = await repo.listMerchantCategories(Number(targetMerchantId));
    const categoryMap = new Map(targetCategories.map((c) => [String(c.name || "").trim().toLowerCase(), c]));
    let createdCount = 0;
    let updatedCount = 0;
    let skippedCount = 0;
    for (const sourceProduct of sourceProducts) {
      const sourceCategory = sourceCategories.find((cat) => Number(cat.id) === Number(sourceProduct.category_id)) || null;
      let targetCategoryId = null;
      if (sourceCategory?.name) {
        const normalized = String(sourceCategory.name).trim().toLowerCase();
        let targetCategory = categoryMap.get(normalized) || null;
        if (!targetCategory) {
          targetCategory = await repo.createMerchantCategory({
            merchantId: Number(targetMerchantId),
            name: sourceCategory.name,
            sortOrder: Number(sourceCategory.sort_order || 0),
          });
          categoryMap.set(normalized, targetCategory);
          modifiedMerchantIds.add(Number(targetMerchantId));
        }
        targetCategoryId = Number(targetCategory.id);
      }

      const conflict = await repo.findProductConflict({
        merchantId: Number(targetMerchantId),
        name: sourceProduct.name,
        categoryId: targetCategoryId,
      });

      const payload = {
        merchantId: Number(targetMerchantId),
        categoryId: targetCategoryId,
        name: sourceProduct.name,
        description: sourceProduct.description,
        price: dto.copyPrices === false && conflict ? conflict.price : sourceProduct.price,
        discountedPrice:
          dto.copyPrices === false && conflict
            ? conflict.discounted_price
            : sourceProduct.discounted_price,
        imageUrl: dto.copyImages === false ? conflict?.image_url || null : sourceProduct.image_url,
        freeDelivery: sourceProduct.free_delivery === true,
        offerLabel: sourceProduct.offer_label,
        isAvailable: sourceProduct.is_available === true,
        sortOrder: Number(sourceProduct.sort_order || 0),
      };

      if (!conflict) {
        await repo.createProductCopy(payload);
        createdCount += 1;
        modifiedMerchantIds.add(Number(targetMerchantId));
        continue;
      }
      if (conflictStrategy === "skip") {
        skippedCount += 1;
        continue;
      }
      if (conflictStrategy === "update") {
        await repo.updateProductCopy(Number(conflict.id), payload);
        updatedCount += 1;
        modifiedMerchantIds.add(Number(targetMerchantId));
        continue;
      }
      await repo.createProductCopy(payload);
      createdCount += 1;
      modifiedMerchantIds.add(Number(targetMerchantId));
    }
    summary.push({ targetMerchantId: Number(targetMerchantId), createdCount, updatedCount, skippedCount });
  }

  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.product_copy.executed",
    summary: `Copied products from branch ${dto.sourceMerchantId}`,
    metadata: { sourceMerchantId: Number(dto.sourceMerchantId), summary, conflictStrategy },
  });
  await Promise.all(
    [...modifiedMerchantIds].map((merchantId) =>
      invalidateMerchantCatalogCache(merchantId)
    )
  );
  return { summary };
}
export async function listCompanyCoupons(companyId) {
  const coupons = await repo.listCompanyCoupons(Number(companyId));
  return { coupons };
}

export async function createCompanyCoupon(companyId, dto, actor = {}) {
  const targetMerchantIds = await resolveCompanyTargetMerchantIds(Number(companyId), {
    appliesToAllBranches: dto.appliesToAllBranches === true,
    targetMerchantIds: dto.targetMerchantIds,
  });
  const coupon = await repo.createCompanyCoupon({
    companyId: Number(companyId),
    code: dto.code,
    description: dto.description,
    discountType: dto.discountType,
    discountValue: dto.discountValue,
    minOrderTotal: dto.minOrderTotal || 0,
    maxUses: dto.maxUses,
    validFrom: dto.validFrom || null,
    validUntil: dto.validUntil || null,
    appliesToAllBranches: dto.appliesToAllBranches === true,
    createdByUserId: actor.userId || null,
  });
  if (dto.appliesToAllBranches !== true) {
    await repo.replaceCompanyCouponTargets({
      couponId: Number(coupon.id),
      companyId: Number(companyId),
      merchantIds: targetMerchantIds,
    });
  }
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.coupon.created",
    summary: `Created company coupon ${coupon.code}`,
    targetType: "coupon",
    targetId: Number(coupon.id),
    targetLabel: coupon.code,
    metadata: { targetMerchantIds, appliesToAllBranches: dto.appliesToAllBranches === true },
  });
  return { coupon, targetMerchantIds };
}

export async function listCompanyCampaigns(companyId) {
  const campaigns = await repo.listCompanyCampaigns(Number(companyId));
  return { campaigns };
}

export async function createCompanyCampaign(companyId, dto, actor = {}) {
  const targetMerchantIds = await resolveCompanyTargetMerchantIds(Number(companyId), {
    appliesToAllBranches: dto.appliesToAllBranches === true,
    targetMerchantIds: dto.targetMerchantIds,
  });
  const campaign = await repo.createCompanyCampaign({
    companyId: Number(companyId),
    title: dto.title,
    description: dto.description,
    offerType: dto.offerType,
    discountValue: dto.discountValue,
    buyQuantity: dto.buyQuantity,
    getQuantity: dto.getQuantity,
    startsAt: dto.startsAt || null,
    endsAt: dto.endsAt || null,
    status: dto.status || "draft",
    appliesToAllBranches: dto.appliesToAllBranches === true,
    maxUsage: dto.maxUsage,
    createdByUserId: actor.userId || null,
  });
  if (dto.appliesToAllBranches !== true) {
    await repo.replaceCompanyCampaignTargets({
      companyCampaignId: Number(campaign.id),
      merchantIds: targetMerchantIds,
    });
  }
  for (const merchantId of targetMerchantIds) {
    await repo.materializeCompanyCampaignOffer({
      merchantId: Number(merchantId),
      companyCampaignId: Number(campaign.id),
      campaign,
      actorUserId: actor.userId || null,
    });
  }
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.campaign.created",
    summary: `Created company campaign ${campaign.title}`,
    targetType: "company_campaign",
    targetId: Number(campaign.id),
    targetLabel: campaign.title,
    metadata: { targetMerchantIds, appliesToAllBranches: dto.appliesToAllBranches === true },
  });
  return { campaign, targetMerchantIds };
}

function computeStockStatus({ quantity, reorderThreshold, manualDisabled, inventoryEnabled, dailyUpdateMode, autoDisableOutOfStock, showAllWithoutAutoDisable }) {
  const qty = Math.max(0, Number(quantity || 0));
  const threshold = Math.max(0, Number(reorderThreshold || 0));
  if (manualDisabled === true) {
    return { stockStatus: 'manual_disabled', productIsAvailable: false, autoDisabled: false };
  }
  if (inventoryEnabled !== true) {
    return { stockStatus: qty <= 0 ? 'out_of_stock' : qty <= threshold ? 'low_stock' : 'in_stock', productIsAvailable: null, autoDisabled: false };
  }
  if (qty <= 0) {
    if (dailyUpdateMode === 'manual_override' || showAllWithoutAutoDisable === true) {
      return { stockStatus: 'out_of_stock', productIsAvailable: null, autoDisabled: false };
    }
    return { stockStatus: 'out_of_stock', productIsAvailable: autoDisableOutOfStock !== false ? false : null, autoDisabled: autoDisableOutOfStock !== false };
  }
  if (qty <= threshold) {
    return { stockStatus: 'low_stock', productIsAvailable: true, autoDisabled: false };
  }
  return { stockStatus: 'in_stock', productIsAvailable: true, autoDisabled: false };
}

export async function getCompanyInventoryOverview(companyId) {
  const branches = await repo.listCompanyBranches(Number(companyId), { limit: 5000, offset: 0 });
  const totals = {
    branchesCount: branches.length,
    inventoryEnabledBranches: 0,
    trackedItems: 0,
    outOfStockItems: 0,
    lowStockItems: 0,
    staleBranches: 0,
  };
  const now = Date.now();
  const branchSummaries = branches.map((branch) => {
    if (branch.inventory_enabled === true) totals.inventoryEnabledBranches += 1;
    totals.trackedItems += Number(branch.tracked_items || 0);
    totals.outOfStockItems += Number(branch.out_of_stock_items || 0);
    totals.lowStockItems += Number(branch.low_stock_items || 0);
    const stale = !branch.last_daily_check_at || now - new Date(branch.last_daily_check_at).getTime() > 24 * 60 * 60 * 1000;
    if (stale) totals.staleBranches += 1;
    return { ...mapBranch(branch), staleDailyCheck: stale };
  });
  return { totals, branches: branchSummaries };
}
export async function getCompanyBranchInventory(companyId, merchantId) {
  await ensureCompanyBranch(companyId, merchantId);
  const [settings, items, products] = await Promise.all([
    repo.getInventorySettings(Number(merchantId)),
    repo.listMerchantInventoryItems(Number(merchantId)),
    repo.listMerchantProducts(Number(merchantId)),
  ]);
  return {
    settings,
    items: items.map((row) => ({
      id: Number(row.id),
      productId: Number(row.product_id),
      productName: row.product_name,
      productImageUrl: row.product_image_url || null,
      quantity: Number(row.quantity || 0),
      reorderThreshold: row.reorder_threshold == null ? null : Number(row.reorder_threshold),
      stockStatus: row.stock_status,
      manualDisabled: row.manual_disabled === true,
      autoDisabled: row.auto_disabled === true,
      productIsAvailable: row.is_available === true,
      updatedAt: row.updated_at,
    })),
    products,
  };
}

export async function patchCompanyBranchInventorySettings(companyId, merchantId, patch, actor = {}) {
  await ensureCompanyBranch(companyId, merchantId);
  const settings = await repo.upsertInventorySettings(Number(merchantId), patch || {}, {
    companyId: Number(companyId),
    updatedByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.inventory.settings.updated",
    summary: `Updated inventory settings for branch #${merchantId}`,
    targetType: "merchant",
    targetId: Number(merchantId),
    metadata: { patch },
  });
  return { settings };
}

export async function patchCompanyInventoryItem(companyId, merchantId, productId, patch, actor = {}) {
  await ensureCompanyBranch(companyId, merchantId);
  const settings = await repo.getInventorySettings(Number(merchantId));
  const threshold = patch.reorderThreshold ?? settings?.low_stock_threshold ?? 5;
  const computed = computeStockStatus({
    quantity: patch.quantity,
    reorderThreshold: threshold,
    manualDisabled: patch.manualDisabled === true,
    inventoryEnabled: settings?.inventory_enabled === true,
    dailyUpdateMode: settings?.daily_update_mode || 'manual_override',
    autoDisableOutOfStock: settings?.auto_disable_out_of_stock !== false,
    showAllWithoutAutoDisable: settings?.show_all_without_auto_disable === true,
  });
  const item = await repo.upsertInventoryItem({
    merchantId: Number(merchantId),
    productId: Number(productId),
    quantity: patch.quantity,
    reorderThreshold: threshold,
    manualDisabled: patch.manualDisabled === true,
    autoDisabled: computed.autoDisabled === true,
    stockStatus: computed.stockStatus,
    updatedByUserId: actor.userId || null,
  });
  if (computed.productIsAvailable !== null) {
    await repo.updateProductAvailability(Number(productId), computed.productIsAvailable === true);
  }
  await repo.insertInventoryAuditLog({
    merchantId: Number(merchantId),
    productId: Number(productId),
    actorUserId: actor.userId || null,
    actorContext: "company_portal",
    actionKey: "inventory.item.updated",
    summary: `Updated inventory for product #${productId}`,
    newValue: { item, effectiveAvailability: computed.productIsAvailable },
  });
  return { item, effectiveAvailability: computed.productIsAvailable };
}

export async function confirmCompanyBranchDailyCheck(companyId, merchantId, note, actor = {}) {
  await ensureCompanyBranch(companyId, merchantId);
  const settings = await repo.getInventorySettings(Number(merchantId));
  const check = await repo.upsertInventoryDailyCheck({
    merchantId: Number(merchantId),
    note,
    modeAtCheck: settings?.daily_update_mode || 'manual_override',
    confirmedByUserId: actor.userId || null,
  });
  await repo.upsertInventorySettings(Number(merchantId), {
    lastDailyCheckAt: new Date().toISOString(),
  }, {
    companyId: Number(companyId),
    updatedByUserId: actor.userId || null,
  });
  await repo.insertCompanyAuditLog({
    companyId: Number(companyId),
    actorUserId: actor.userId || null,
    actorRole: actor.role || null,
    actionKey: "company.inventory.daily_check.confirmed",
    summary: `Confirmed daily stock update for branch #${merchantId}`,
    targetType: "merchant",
    targetId: Number(merchantId),
    metadata: { note: note || null },
  });
  return { check };
}
