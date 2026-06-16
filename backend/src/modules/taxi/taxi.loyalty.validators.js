function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function toNum(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function optionalText(value, max = 1000) {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim().length <= max)
  );
}

function requiredText(value, max = 240) {
  return typeof value === "string" && value.trim().length > 0 && value.trim().length <= max;
}

function normalizeScheduleStatus(value) {
  const raw = String(value || "").trim().toLowerCase();
  return ["scheduled", "pending_dispatch", "assigned", "cancelled", "completed", "expired"].includes(raw)
    ? raw
    : "scheduled";
}

function normalizePlaceType(value) {
  const raw = String(value || "").trim().toLowerCase();
  if (["home", "work", "custom"].includes(raw)) return raw;
  return "custom";
}

const MIN_RIDE_FARE_IQD = 1500;

export function validateEntityId(paramValue, field = "id") {
  const id = toInt(paramValue);
  if (!id || id <= 0) return { ok: false, errors: [field] };
  return { ok: true, value: id, errors: [] };
}

export function validateSavedPlaceCreate(body = {}) {
  const errors = {};
  const latitude = toNum(body.latitude);
  const longitude = toNum(body.longitude);
  const placeType = normalizePlaceType(body.placeType || body.type);
  const label = typeof body.label === "string" ? body.label.trim() : "";
  const addressText = typeof body.addressText === "string" ? body.addressText.trim() : "";
  const note = body.note == null ? null : String(body.note).trim();
  const iconName = body.iconName == null ? null : String(body.iconName).trim();

  if (!requiredText(label, 80)) errors.label = "REQUIRED";
  if (!requiredText(addressText, 280)) errors.addressText = "REQUIRED";
  if (latitude == null || latitude < -90 || latitude > 90) errors.latitude = "SELECT_LOCATION";
  if (longitude == null || longitude < -180 || longitude > 180) {
    errors.longitude = "SELECT_LOCATION";
  }
  if (!optionalText(note, 1200)) errors.note = "TOO_LONG";
  if (!optionalText(iconName, 40)) errors.iconName = "TOO_LONG";

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      label,
      placeType,
      latitude,
      longitude,
      addressText,
      note: note || null,
      iconName: iconName || null,
    },
  };
}

export function validateSavedPlacePatch(body = {}) {
  const errors = {};
  const value = {};

  if (body.label !== undefined) {
    if (!requiredText(body.label, 80)) errors.label = "REQUIRED";
    else value.label = String(body.label).trim();
  }

  if (body.placeType !== undefined || body.type !== undefined) {
    value.placeType = normalizePlaceType(body.placeType || body.type);
  }

  if (body.latitude !== undefined) {
    const latitude = toNum(body.latitude);
    if (latitude == null || latitude < -90 || latitude > 90) {
      errors.latitude = "SELECT_LOCATION";
    } else {
      value.latitude = latitude;
    }
  }

  if (body.longitude !== undefined) {
    const longitude = toNum(body.longitude);
    if (longitude == null || longitude < -180 || longitude > 180) {
      errors.longitude = "SELECT_LOCATION";
    } else {
      value.longitude = longitude;
    }
  }

  if (body.addressText !== undefined) {
    if (!requiredText(body.addressText, 280)) errors.addressText = "REQUIRED";
    else value.addressText = String(body.addressText).trim();
  }

  if (body.note !== undefined) {
    if (!optionalText(body.note, 1200)) errors.note = "TOO_LONG";
    else value.note = body.note == null ? null : String(body.note).trim();
  }

  if (body.iconName !== undefined) {
    if (!optionalText(body.iconName, 40)) errors.iconName = "TOO_LONG";
    else value.iconName = body.iconName == null ? null : String(body.iconName).trim();
  }

  if (Object.keys(value).length === 0) {
    errors._form = "EMPTY_BODY";
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value,
  };
}

function parsePlaceSnapshot(raw, prefix, errors) {
  const fromInput = raw && typeof raw === "object" ? raw : {};
  const latitude = toNum(fromInput.latitude);
  const longitude = toNum(fromInput.longitude);
  const label = typeof fromInput.label === "string" ? fromInput.label.trim() : "";
  const addressText =
    typeof fromInput.addressText === "string"
      ? fromInput.addressText.trim()
      : typeof fromInput.address_text === "string"
      ? String(fromInput.address_text).trim()
      : label;

  if (latitude == null || latitude < -90 || latitude > 90) {
    errors[`${prefix}.latitude`] = "SELECT_LOCATION";
  }
  if (longitude == null || longitude < -180 || longitude > 180) {
    errors[`${prefix}.longitude`] = "SELECT_LOCATION";
  }
  if (!requiredText(label, 140)) errors[`${prefix}.label`] = "REQUIRED";
  if (!requiredText(addressText, 280)) errors[`${prefix}.addressText`] = "REQUIRED";

  return {
    latitude,
    longitude,
    label,
    addressText,
  };
}

export function validateFavoriteTripCreate(body = {}) {
  const errors = {};
  const label = typeof body.label === "string" ? body.label.trim() : "";
  const iconName = body.iconName == null ? null : String(body.iconName).trim();

  if (!requiredText(label, 120)) errors.label = "REQUIRED";
  if (!optionalText(iconName, 40)) errors.iconName = "TOO_LONG";

  const pickup = parsePlaceSnapshot(body.pickupSnapshot || body.pickup, "pickup", errors);
  const dropoff = parsePlaceSnapshot(body.dropoffSnapshot || body.dropoff, "dropoff", errors);

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      label,
      iconName: iconName || null,
      pickupSnapshot: pickup,
      dropoffSnapshot: dropoff,
    },
  };
}

export function validateFavoriteTripPatch(body = {}) {
  const errors = {};
  const value = {};

  if (body.label !== undefined) {
    if (!requiredText(body.label, 120)) errors.label = "REQUIRED";
    else value.label = String(body.label).trim();
  }

  if (body.iconName !== undefined) {
    if (!optionalText(body.iconName, 40)) errors.iconName = "TOO_LONG";
    else value.iconName = body.iconName == null ? null : String(body.iconName).trim();
  }

  if (body.pickupSnapshot !== undefined || body.pickup !== undefined) {
    value.pickupSnapshot = parsePlaceSnapshot(
      body.pickupSnapshot || body.pickup,
      "pickup",
      errors
    );
  }

  if (body.dropoffSnapshot !== undefined || body.dropoff !== undefined) {
    value.dropoffSnapshot = parsePlaceSnapshot(
      body.dropoffSnapshot || body.dropoff,
      "dropoff",
      errors
    );
  }

  if (Object.keys(value).length === 0) errors._form = "EMPTY_BODY";

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value,
  };
}

export function validateScheduledRideCreate(body = {}) {
  const errors = {};
  const pickup = parsePlaceSnapshot(body.pickupSnapshot || body.pickup, "pickup", errors);
  const dropoff = parsePlaceSnapshot(body.dropoffSnapshot || body.dropoff, "dropoff", errors);
  const proposedFareIqd = toInt(body.proposedFareIqd);
  const note = body.note == null ? null : String(body.note).trim();
  const couponCode = body.couponCode == null ? null : String(body.couponCode).trim().toUpperCase();
  const scheduleForRaw = body.scheduleFor || body.scheduledFor;
  const scheduleFor = scheduleForRaw ? new Date(scheduleForRaw) : null;

  if (
    proposedFareIqd == null ||
    proposedFareIqd < MIN_RIDE_FARE_IQD ||
    proposedFareIqd > 5000000
  ) {
    errors.proposedFareIqd = "INVALID_NUMBER";
  }
  if (!optionalText(note, 1000)) errors.note = "TOO_LONG";
  if (couponCode && !requiredText(couponCode, 64)) errors.couponCode = "INVALID_FORMAT";

  if (!scheduleFor || Number.isNaN(scheduleFor.getTime())) {
    errors.scheduleFor = "INVALID_DATE";
  } else if (scheduleFor.getTime() <= Date.now() + 60 * 1000) {
    errors.scheduleFor = "TIME_IN_PAST";
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      pickupSnapshot: pickup,
      dropoffSnapshot: dropoff,
      proposedFareIqd,
      note: note || null,
      couponCode: couponCode || null,
      scheduleFor: scheduleFor ? scheduleFor.toISOString() : null,
    },
  };
}

export function validateScheduledRideListQuery(query = {}) {
  const errors = [];
  const status = normalizeScheduleStatus(query.status);
  const limit = toInt(query.limit ?? 40);
  if (limit == null || limit < 1 || limit > 200) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: { status, limit: limit ?? 40 },
  };
}

export function validateCouponPreview(body = {}) {
  const errors = {};
  const couponCode = String(body.couponCode || body.code || "").trim().toUpperCase();
  const proposedFareIqd = toInt(body.proposedFareIqd);

  if (!requiredText(couponCode, 64)) errors.couponCode = "REQUIRED";
  if (
    proposedFareIqd == null ||
    proposedFareIqd < MIN_RIDE_FARE_IQD ||
    proposedFareIqd > 5000000
  ) {
    errors.proposedFareIqd = "INVALID_NUMBER";
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      couponCode,
      proposedFareIqd,
    },
  };
}

export function validateComplaintCreate(body = {}) {
  const errors = {};
  const tripId = toInt(body.tripId || body.rideId);
  const category = String(body.category || "").trim();
  const reason = String(body.reason || "").trim();
  const details = body.details == null ? null : String(body.details).trim();
  const attachmentUrl =
    body.attachmentUrl == null ? null : String(body.attachmentUrl).trim();

  if (!tripId || tripId <= 0) errors.tripId = "REQUIRED";
  if (!requiredText(category, 40)) errors.category = "REQUIRED";
  if (!requiredText(reason, 240)) errors.reason = "REQUIRED";
  if (!optionalText(details, 2000)) errors.details = "TOO_LONG";
  if (!optionalText(attachmentUrl, 2000)) errors.attachmentUrl = "TOO_LONG";

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      tripId,
      category,
      reason,
      details: details || null,
      attachmentUrl: attachmentUrl || null,
    },
  };
}

export function validateCaptainRiderRating(body = {}) {
  const errors = {};
  const rating = toInt(body.rating);
  const category = body.category == null ? null : String(body.category).trim();
  const note = body.note == null ? null : String(body.note).trim();

  if (rating == null || rating < 1 || rating > 5) errors.rating = "SELECT_OPTION";
  if (!optionalText(category, 40)) errors.category = "TOO_LONG";
  if (!optionalText(note, 1000)) errors.note = "TOO_LONG";

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value: {
      rating,
      category: category || null,
      note: note || null,
    },
  };
}
