function isNonEmptyString(v, max = 300) {
  return typeof v === "string" && v.trim().length > 0 && v.trim().length <= max;
}

function isOptionalString(v, max = 1000) {
  return (
    v === undefined ||
    v === null ||
    (typeof v === "string" && v.trim().length <= max)
  );
}

export function validateCreateOrder(body) {
  const errors = [];

  const merchantId = Number(body.merchantId);
  if (!Number.isInteger(merchantId) || merchantId <= 0) errors.push("merchantId");

  if (!Array.isArray(body.items) || body.items.length === 0) {
    errors.push("items");
  } else {
    for (const item of body.items) {
      const productId = Number(item.productId);
      const quantity = Number(item.quantity);
      if (!Number.isInteger(productId) || productId <= 0) errors.push("productId");
      if (!Number.isInteger(quantity) || quantity <= 0) errors.push("quantity");
    }
  }

  if (body.note !== undefined && body.note !== null) {
    if (typeof body.note !== "string") {
      errors.push("note");
    } else if (body.note.trim().length > 1000) {
      errors.push("note");
    }
  }

  if (
    body.imageUrl !== undefined &&
    body.imageUrl !== null &&
    (typeof body.imageUrl !== "string" || body.imageUrl.trim().length > 1000)
  ) {
    errors.push("imageUrl");
  }

  if (body.addressId !== undefined && body.addressId !== null) {
    const addressId = Number(body.addressId);
    if (!Number.isInteger(addressId) || addressId <= 0) errors.push("addressId");
  }

  return { ok: errors.length === 0, errors };
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
