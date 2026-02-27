import { hashPin } from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";
import { findUserByPhone } from "../auth/auth.repo.js";
import * as analyticsRepo from "../analytics/analytics.repo.js";
import * as ordersRepo from "../orders/orders.repo.js";
import * as repo from "./owner.repo.js";

function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    role: u.role,
    isSuperAdmin: u.is_super_admin === true,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
    imageUrl: u.image_url,
  };
}

function mapMerchant(m) {
  return {
    id: m.id,
    name: m.name,
    type: m.type,
    description: m.description,
    phone: m.phone,
    imageUrl: m.image_url,
    isOpen: m.is_open,
    isApproved: m.is_approved,
    approvedByUserId: m.approved_by_user_id,
    approvedAt: m.approved_at,
    ownerUserId: m.owner_user_id,
    createdAt: m.created_at,
    updatedAt: m.updated_at,
  };
}

function normalizeOptional(v) {
  if (v === undefined || v === null) return null;
  const out = String(v).trim();
  return out.length ? out : null;
}

function toNumberOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toPositiveIntOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function normalizeConsentAccepted(value) {
  if (value === true) return true;
  if (typeof value !== "string") return false;
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes";
}

function mapCategory(c) {
  return {
    id: c.id,
    merchantId: c.merchant_id,
    name: c.name,
    sortOrder: c.sort_order,
    createdAt: c.created_at,
    updatedAt: c.updated_at,
  };
}

export async function registerOwner(dto) {
  const analyticsConsentAccepted = normalizeConsentAccepted(
    dto.analyticsConsentAccepted
  );
  const analyticsConsentVersion =
    typeof dto.analyticsConsentVersion === "string" &&
    dto.analyticsConsentVersion.trim().length > 0
      ? dto.analyticsConsentVersion.trim().slice(0, 32)
      : "analytics_v1";

  if (!analyticsConsentAccepted) {
    const err = new Error("ANALYTICS_CONSENT_REQUIRED");
    err.status = 400;
    throw err;
  }

  const exists = await findUserByPhone(dto.phone.trim());
  if (exists) {
    const err = new Error("PHONE_EXISTS");
    err.status = 409;
    throw err;
  }

  const pinHash = await hashPin(dto.pin);

  const out = await repo.createOwnerWithMerchant({
    fullName: dto.fullName.trim(),
    phone: dto.phone.trim(),
    pinHash,
    block: dto.block.trim(),
    buildingNumber: dto.buildingNumber.trim(),
    apartment: dto.apartment.trim(),
    ownerImageUrl: normalizeOptional(dto.ownerImageUrl),
    merchantName: dto.merchantName.trim(),
    merchantType: dto.merchantType,
    merchantDescription: normalizeOptional(dto.merchantDescription),
    merchantPhone: normalizeOptional(dto.merchantPhone) || dto.phone.trim(),
    merchantImageUrl: normalizeOptional(dto.merchantImageUrl),
    analyticsConsentGranted: true,
    analyticsConsentVersion,
    analyticsConsentGrantedAt: new Date(),
  });

  const token = signAccessToken({
    id: out.user.id,
    role: out.user.role || "owner",
    isSuperAdmin: out.user.is_super_admin === true,
  });

  return {
    token,
    user: mapUser(out.user),
    merchant: mapMerchant(out.merchant),
  };
}

export async function getOwnerMerchant(ownerUserId) {
  const merchant = await repo.findMerchantByOwnerUserId(ownerUserId);
  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return mapMerchant(merchant);
}

export async function updateOwnerMerchant(ownerUserId, dto) {
  const patch = {};
  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.type !== undefined) patch.type = dto.type;
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.phone !== undefined) patch.phone = normalizeOptional(dto.phone);
  if (dto.imageUrl !== undefined) patch.imageUrl = normalizeOptional(dto.imageUrl);
  if (dto.isOpen !== undefined) patch.isOpen = dto.isOpen;

  const merchant = await repo.updateOwnerMerchant(ownerUserId, patch);

  if (!merchant) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return mapMerchant(merchant);
}

export async function listOwnerProducts(ownerUserId) {
  return repo.listOwnerProducts(ownerUserId);
}

export async function listOwnerCategories(ownerUserId) {
  const rows = await repo.listOwnerCategories(ownerUserId);
  return rows.map(mapCategory);
}

export async function createOwnerCategory(ownerUserId, dto) {
  let created;
  try {
    created = await repo.createOwnerCategory(ownerUserId, {
      name: dto.name.trim(),
      sortOrder: Number(dto.sortOrder ?? 0),
    });
  } catch (e) {
    if (e?.code === "23505" && String(e.constraint || "").includes("merchant_category_merchant_id_name")) {
      const err = new Error("CATEGORY_NAME_EXISTS");
      err.status = 409;
      throw err;
    }
    throw e;
  }

  if (!created) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return mapCategory(created);
}

export async function updateOwnerCategory(ownerUserId, categoryId, dto) {
  const patch = {};
  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);

  let updated;
  try {
    updated = await repo.updateOwnerCategory(ownerUserId, categoryId, patch);
  } catch (e) {
    if (e?.code === "23505" && String(e.constraint || "").includes("merchant_category_merchant_id_name")) {
      const err = new Error("CATEGORY_NAME_EXISTS");
      err.status = 409;
      throw err;
    }
    throw e;
  }
  if (!updated) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return mapCategory(updated);
}

export async function deleteOwnerCategory(ownerUserId, categoryId) {
  const ok = await repo.deleteOwnerCategory(ownerUserId, categoryId);
  if (!ok) {
    const err = new Error("CATEGORY_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function createOwnerProduct(ownerUserId, dto) {
  const price = toNumberOrNull(dto.price);
  const discountedPrice = toNumberOrNull(dto.discountedPrice);
  const categoryId = toPositiveIntOrNull(dto.categoryId);

  if (price === null) {
    const err = new Error("PRICE_INVALID");
    err.status = 400;
    throw err;
  }

  if (discountedPrice !== null && discountedPrice > price) {
    const err = new Error("DISCOUNT_PRICE_INVALID");
    err.status = 400;
    throw err;
  }

  if (dto.categoryId !== undefined && dto.categoryId !== null && dto.categoryId !== "" && categoryId === null) {
    const err = new Error("CATEGORY_INVALID");
    err.status = 400;
    throw err;
  }

  if (categoryId !== null) {
    const category = await repo.findOwnerCategoryById(ownerUserId, categoryId);
    if (!category) {
      const err = new Error("CATEGORY_NOT_FOUND");
      err.status = 404;
      throw err;
    }
  }

  const product = await repo.createOwnerProduct(ownerUserId, {
    name: dto.name.trim(),
    description: normalizeOptional(dto.description),
    categoryId,
    price,
    discountedPrice,
    imageUrl: normalizeOptional(dto.imageUrl),
    freeDelivery: dto.freeDelivery === true,
    offerLabel: normalizeOptional(dto.offerLabel),
    isAvailable: dto.isAvailable ?? true,
    sortOrder: Number(dto.sortOrder ?? 0),
  });

  if (!product) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return product;
}

export async function updateOwnerProduct(ownerUserId, productId, dto) {
  const patch = {};

  if (dto.name !== undefined) patch.name = dto.name.trim();
  if (dto.description !== undefined) patch.description = normalizeOptional(dto.description);
  if (dto.imageUrl !== undefined) patch.imageUrl = normalizeOptional(dto.imageUrl);
  if (dto.offerLabel !== undefined) patch.offerLabel = normalizeOptional(dto.offerLabel);
  if (dto.isAvailable !== undefined) patch.isAvailable = dto.isAvailable;
  if (dto.freeDelivery !== undefined) patch.freeDelivery = dto.freeDelivery === true;
  if (dto.sortOrder !== undefined) patch.sortOrder = Number(dto.sortOrder);

  if (dto.categoryId !== undefined) {
    if (dto.categoryId === null || dto.categoryId === "") {
      patch.categoryId = null;
    } else {
      const categoryId = toPositiveIntOrNull(dto.categoryId);
      if (categoryId === null) {
        const err = new Error("CATEGORY_INVALID");
        err.status = 400;
        throw err;
      }
      const category = await repo.findOwnerCategoryById(ownerUserId, categoryId);
      if (!category) {
        const err = new Error("CATEGORY_NOT_FOUND");
        err.status = 404;
        throw err;
      }
      patch.categoryId = categoryId;
    }
  }

  if (dto.price !== undefined) {
    const p = toNumberOrNull(dto.price);
    if (p === null) {
      const err = new Error("PRICE_INVALID");
      err.status = 400;
      throw err;
    }
    patch.price = p;
  }

  if (dto.discountedPrice !== undefined) {
    const d = toNumberOrNull(dto.discountedPrice);
    patch.discountedPrice = d;
  }

  if (patch.price !== undefined || patch.discountedPrice !== undefined) {
    const current = await repo.findOwnerProductById(ownerUserId, productId);
    if (!current) {
      const err = new Error("PRODUCT_NOT_FOUND");
      err.status = 404;
      throw err;
    }

    const basePrice = patch.price ?? Number(current.price);
    const nextDiscount = patch.discountedPrice ?? (current.discounted_price === null ? null : Number(current.discounted_price));
    if (nextDiscount !== null && nextDiscount > basePrice) {
      const err = new Error("DISCOUNT_PRICE_INVALID");
      err.status = 400;
      throw err;
    }
  }

  const updated = await repo.updateOwnerProduct(ownerUserId, productId, patch);
  if (!updated) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return updated;
}

export async function deleteOwnerProduct(ownerUserId, productId) {
  const ok = await repo.deleteOwnerProduct(ownerUserId, productId);
  if (!ok) {
    const err = new Error("PRODUCT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function listDeliveryAgents() {
  return ordersRepo.listDeliveryAgents();
}

export async function listCurrentOrders(ownerUserId) {
  return ordersRepo.listOwnerCurrentOrders(ownerUserId);
}

export async function listOrderHistory(ownerUserId, archiveDate) {
  return ordersRepo.listOwnerOrderHistory(ownerUserId, archiveDate || null);
}

export async function updateOrderStatus(
  ownerUserId,
  orderId,
  status,
  estimatedPrepMinutes,
  estimatedDeliveryMinutes
) {
  const ok = await ordersRepo.updateOwnerOrderStatus(
    ownerUserId,
    Number(orderId),
    status,
    estimatedPrepMinutes === undefined ? null : Number(estimatedPrepMinutes),
    estimatedDeliveryMinutes === undefined ? null : Number(estimatedDeliveryMinutes)
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function assignDelivery(ownerUserId, orderId, deliveryUserId) {
  const ok = await ordersRepo.assignDeliveryToOwnerOrder(
    ownerUserId,
    Number(orderId),
    Number(deliveryUserId)
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }
}

export async function ownerAnalytics(ownerUserId) {
  return analyticsRepo.getOwnerAnalytics(ownerUserId);
}

export async function printOrdersReport(ownerUserId, period) {
  const normalizedPeriod = String(period || "day").toLowerCase();
  return ordersRepo.listOwnerOrdersForReport(ownerUserId, normalizedPeriod);
}

export async function settlementSummary(ownerUserId) {
  return analyticsRepo.getOwnerOutstanding(ownerUserId);
}

export async function requestSettlement(ownerUserId, note) {
  const out = await analyticsRepo.createOwnerSettlementRequest(
    ownerUserId,
    note?.trim()
  );
  if (!out) {
    const err = new Error("MERCHANT_NOT_FOUND");
    err.status = 404;
    throw err;
  }
  return out;
}
