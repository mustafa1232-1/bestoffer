function isOptionalString(v, max = 1000) {
  return (
    v === undefined ||
    v === null ||
    (typeof v === "string" && v.trim().length <= max)
  );
}

function validateItems(items, pathPrefix, errors) {
  if (!Array.isArray(items) || items.length === 0) {
    errors.push(pathPrefix);
    return;
  }

  for (let index = 0; index < items.length; index += 1) {
    const item = items[index] || {};
    const productId = Number(item.productId);
    const quantity = Number(item.quantity);
    if (!Number.isInteger(productId) || productId <= 0) {
      errors.push(`${pathPrefix}.${index}.productId`);
    }
    if (!Number.isInteger(quantity) || quantity <= 0) {
      errors.push(`${pathPrefix}.${index}.quantity`);
    }
    if (
      item.selectedModifiers !== undefined &&
      !Array.isArray(item.selectedModifiers)
    ) {
      errors.push(`${pathPrefix}.${index}.selectedModifiers`);
    }
  }
}

export function validateCreateOrder(body) {
  const errors = [];
  const storeOrders = Array.isArray(body?.storeOrders) ? body.storeOrders : null;

  if (storeOrders) {
    if (storeOrders.length === 0 || storeOrders.length > 3) {
      errors.push("storeOrders");
    } else {
      for (let storeIndex = 0; storeIndex < storeOrders.length; storeIndex += 1) {
        const storeOrder = storeOrders[storeIndex] || {};
        const merchantId = Number(storeOrder.merchantId);
        if (!Number.isInteger(merchantId) || merchantId <= 0) {
          errors.push(`storeOrders.${storeIndex}.merchantId`);
        }
        validateItems(
          storeOrder.items,
          `storeOrders.${storeIndex}.items`,
          errors
        );
        if (
          storeOrder.note !== undefined &&
          storeOrder.note !== null &&
          (typeof storeOrder.note !== "string" || storeOrder.note.trim().length > 1000)
        ) {
          errors.push(`storeOrders.${storeIndex}.note`);
        }
      }
    }
  } else {
    const merchantId = Number(body?.merchantId);
    if (!Number.isInteger(merchantId) || merchantId <= 0) {
      errors.push("merchantId");
    }
    validateItems(body?.items, "items", errors);
  }

  if (body?.note !== undefined && body?.note !== null) {
    if (typeof body.note !== "string") {
      errors.push("note");
    } else if (body.note.trim().length > 1000) {
      errors.push("note");
    }
  }

  if (
    body?.imageUrl !== undefined &&
    body?.imageUrl !== null &&
    (typeof body.imageUrl !== "string" || body.imageUrl.trim().length > 1000)
  ) {
    errors.push("imageUrl");
  }

  if (body?.addressId !== undefined && body?.addressId !== null) {
    const addressId = Number(body.addressId);
    if (!Number.isInteger(addressId) || addressId <= 0) {
      errors.push("addressId");
    }
  }

  if (
    body?.couponId !== undefined &&
    body?.couponId !== null &&
    body?.couponId !== ""
  ) {
    const couponId = Number(body.couponId);
    if (!Number.isInteger(couponId) || couponId <= 0) {
      errors.push("couponId");
    }
  }

  if (
    body?.couponCode !== undefined &&
    body?.couponCode !== null &&
    (typeof body.couponCode !== "string" || body.couponCode.trim().length > 80)
  ) {
    errors.push("couponCode");
  }

  return { ok: errors.length === 0, errors };
}

export function validatePreviewOrder(body) {
  return validateCreateOrder(body);
}

export function validateRating(body) {
  const errors = [];
  const rating = Number(body.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) errors.push("rating");
  if (!isOptionalString(body.review, 1000)) {
    errors.push("review");
  }
  return { ok: errors.length === 0, errors };
}

export function validateReorder(body) {
  const errors = [];
  if (!isOptionalString(body.note, 1000)) {
    errors.push("note");
  }
  return { ok: errors.length === 0, errors };
}

export function validateOrderActionReason(body) {
  const errors = [];
  const reasonCode =
    body?.reasonCode == null ? "" : String(body.reasonCode).trim();
  const reasonText =
    body?.reasonText == null ? "" : String(body.reasonText).trim();
  if (!reasonCode) errors.push("reasonCode");
  if (reasonCode.toLowerCase() === "other" && !reasonText) {
    errors.push("reasonText");
  }
  if (reasonText.length > 1000) errors.push("reasonText");
  return { ok: errors.length === 0, errors };
}
