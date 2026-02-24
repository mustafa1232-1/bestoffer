import { getUserPublicById } from "../auth/auth.repo.js";
import { resolveOrderAddress } from "../auth/auth.service.js";
import * as repo from "./orders.repo.js";

function normalizeItems(items) {
  const map = new Map();
  for (const raw of items) {
    const productId = Number(raw.productId);
    const quantity = Number(raw.quantity);
    const prev = map.get(productId) || 0;
    map.set(productId, prev + quantity);
  }
  return Array.from(map.entries()).map(([productId, quantity]) => ({
    productId,
    quantity,
  }));
}

export async function createOrder(customerUserId, dto) {
  const customer = await getUserPublicById(customerUserId);
  if (!customer) {
    const err = new Error("CUSTOMER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  const deliveryAddress = await resolveOrderAddress(
    customerUserId,
    dto.addressId == null ? null : Number(dto.addressId)
  );

  const order = await repo.createOrderWithItems({
    customer,
    deliveryAddress,
    merchantId: Number(dto.merchantId),
    note: dto.note?.trim(),
    imageUrl: dto.imageUrl || null,
    normalizedItems: normalizeItems(dto.items),
  });

  return order;
}

export async function listMyOrders(customerUserId) {
  return repo.listCustomerOrders(customerUserId);
}

export async function confirmDelivered(customerUserId, orderId) {
  const ok = await repo.confirmOrderDelivered(customerUserId, Number(orderId));
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_DELIVERED");
    err.status = 404;
    throw err;
  }
}

export async function rateDelivery(customerUserId, orderId, rating, review) {
  const ok = await repo.rateDelivery(
    customerUserId,
    Number(orderId),
    Number(rating),
    review?.trim()
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_RATEABLE");
    err.status = 404;
    throw err;
  }
}

export async function rateMerchant(customerUserId, orderId, rating, review) {
  const ok = await repo.rateMerchant(
    customerUserId,
    Number(orderId),
    Number(rating),
    review?.trim()
  );
  if (!ok) {
    const err = new Error("ORDER_NOT_FOUND_OR_NOT_RATEABLE");
    err.status = 404;
    throw err;
  }
}

export async function listFavoriteProductIds(customerUserId) {
  return repo.listFavoriteProductIds(customerUserId);
}

export async function listFavoriteProducts(customerUserId, merchantId) {
  return repo.listFavoriteProducts(customerUserId, merchantId || null);
}

export async function addFavoriteProduct(customerUserId, productId) {
  return repo.addFavoriteProduct(customerUserId, Number(productId));
}

export async function removeFavoriteProduct(customerUserId, productId) {
  return repo.removeFavoriteProduct(customerUserId, Number(productId));
}

export async function reorderOrder(customerUserId, orderId, note) {
  const source = await repo.getOrderForReorder(customerUserId, Number(orderId));
  if (!source) {
    const err = new Error("ORDER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  if (!source.items.length) {
    const err = new Error("ORDER_HAS_NO_REORDERABLE_ITEMS");
    err.status = 400;
    throw err;
  }

  const customer = await getUserPublicById(customerUserId);
  if (!customer) {
    const err = new Error("CUSTOMER_NOT_FOUND");
    err.status = 404;
    throw err;
  }

  return repo.createOrderWithItems({
    customer,
    deliveryAddress: {
      city: source.customerCity || "مدينة بسماية",
      block: source.customerBlock || customer.block,
      building_number: source.customerBuildingNumber || customer.building_number,
      apartment: source.customerApartment || customer.apartment,
    },
    merchantId: source.merchantId,
    note: note?.trim() || source.note || null,
    normalizedItems: source.items,
  });
}
