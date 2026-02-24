import { hashPin } from "../../shared/utils/hash.js";
import * as repo from "./merchants.repo.js";

function normalizeOptional(v) {
  if (v === undefined || v === null) return null;
  const out = String(v).trim();
  return out.length ? out : null;
}

function toPositiveIntOrNull(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

export async function createMerchant(dto, approvedByUserId) {
  const ownerUserId = toPositiveIntOrNull(dto.ownerUserId);
  const hasOwnerUserId = ownerUserId !== null;
  const hasOwnerObject = dto.owner && typeof dto.owner === "object";

  if (!hasOwnerUserId && !hasOwnerObject) {
    const err = new Error("OWNER_REQUIRED");
    err.status = 400;
    throw err;
  }

  if (hasOwnerUserId && hasOwnerObject) {
    const err = new Error("OWNER_CONFLICT");
    err.status = 400;
    throw err;
  }

  const merchant = {
    name: dto.name.trim(),
    type: dto.type,
    description: normalizeOptional(dto.description),
    phone: normalizeOptional(dto.phone),
    imageUrl: normalizeOptional(dto.imageUrl),
  };

  let ownerToCreate = null;
  let ownerPinHash = null;

  if (!hasOwnerUserId && hasOwnerObject) {
    ownerToCreate = {
      fullName: dto.owner.fullName.trim(),
      phone: dto.owner.phone.trim(),
      block: dto.owner.block.trim(),
      buildingNumber: dto.owner.buildingNumber.trim(),
      apartment: dto.owner.apartment.trim(),
      imageUrl: normalizeOptional(dto.owner.imageUrl),
    };
    ownerPinHash = await hashPin(dto.owner.pin);
  }

  try {
    return await repo.createMerchantWithOwnerLink({
      merchant,
      approvedByUserId,
      ownerUserId,
      ownerToCreate,
      ownerPinHash,
    });
  } catch (e) {
    if (e?.code === "23505") {
      const constraint = String(e.constraint || "");
      if (constraint.includes("app_user_phone")) {
        const err = new Error("PHONE_EXISTS");
        err.status = 409;
        throw err;
      }
      if (constraint.includes("merchant_owner_user_id")) {
        const err = new Error("OWNER_ALREADY_HAS_MERCHANT");
        err.status = 409;
        throw err;
      }
    }
    throw e;
  }
}

export async function listMerchants(type) {
  return repo.getAllMerchants(type);
}

export async function listMerchantProducts(merchantId) {
  return repo.getPublicMerchantProducts(merchantId);
}

export async function listMerchantCategories(merchantId) {
  return repo.getPublicMerchantCategories(merchantId);
}
