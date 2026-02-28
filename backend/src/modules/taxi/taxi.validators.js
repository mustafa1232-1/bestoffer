function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function toBool(value) {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes"].includes(normalized)) return true;
    if (["0", "false", "no"].includes(normalized)) return false;
  }
  return null;
}

function hasText(value, max = 240) {
  return typeof value === "string" && value.trim().length > 0 && value.trim().length <= max;
}

function optionalText(value, max = 1000) {
  return (
    value === undefined ||
    value === null ||
    (typeof value === "string" && value.trim().length <= max)
  );
}

function resolveCoordinate(body, keys = []) {
  for (const key of keys) {
    const n = toNumber(body?.[key]);
    if (n != null) return n;
  }
  return null;
}

function resolveNestedCoordinate(body, nestedKey, keys = []) {
  const nested = body?.[nestedKey];
  for (const key of keys) {
    const n = toNumber(nested?.[key]);
    if (n != null) return n;
  }
  return null;
}

export function validateRideId(paramValue) {
  const rideId = toInt(paramValue);
  if (!rideId || rideId <= 0) {
    return { ok: false, errors: ["rideId"] };
  }
  return { ok: true, value: rideId, errors: [] };
}

export function validateBidId(paramValue) {
  const bidId = toInt(paramValue);
  if (!bidId || bidId <= 0) {
    return { ok: false, errors: ["bidId"] };
  }
  return { ok: true, value: bidId, errors: [] };
}

export function validateCreateRide(body) {
  const errors = [];

  const pickupLatitude =
    resolveCoordinate(body, ["pickupLatitude", "pickupLat"]) ??
    resolveNestedCoordinate(body, "pickup", ["latitude", "lat"]);
  const pickupLongitude =
    resolveCoordinate(body, ["pickupLongitude", "pickupLng", "pickupLongitude"]) ??
    resolveNestedCoordinate(body, "pickup", ["longitude", "lng", "lon"]);

  const dropoffLatitude =
    resolveCoordinate(body, ["dropoffLatitude", "dropoffLat"]) ??
    resolveNestedCoordinate(body, "dropoff", ["latitude", "lat"]);
  const dropoffLongitude =
    resolveCoordinate(body, ["dropoffLongitude", "dropoffLng", "dropoffLongitude"]) ??
    resolveNestedCoordinate(body, "dropoff", ["longitude", "lng", "lon"]);

  const pickupLabel =
    typeof body?.pickupLabel === "string"
      ? body.pickupLabel
      : typeof body?.pickup?.label === "string"
      ? body.pickup.label
      : "";

  const dropoffLabel =
    typeof body?.dropoffLabel === "string"
      ? body.dropoffLabel
      : typeof body?.dropoff?.label === "string"
      ? body.dropoff.label
      : "";

  const proposedFareIqd = toInt(body?.proposedFareIqd);
  const searchRadiusM = toInt(body?.searchRadiusM ?? 2000);

  if (pickupLatitude == null || pickupLatitude < -90 || pickupLatitude > 90) {
    errors.push("pickupLatitude");
  }
  if (pickupLongitude == null || pickupLongitude < -180 || pickupLongitude > 180) {
    errors.push("pickupLongitude");
  }
  if (dropoffLatitude == null || dropoffLatitude < -90 || dropoffLatitude > 90) {
    errors.push("dropoffLatitude");
  }
  if (dropoffLongitude == null || dropoffLongitude < -180 || dropoffLongitude > 180) {
    errors.push("dropoffLongitude");
  }

  if (!hasText(pickupLabel, 240)) errors.push("pickupLabel");
  if (!hasText(dropoffLabel, 240)) errors.push("dropoffLabel");

  if (proposedFareIqd == null || proposedFareIqd < 0 || proposedFareIqd > 5000000) {
    errors.push("proposedFareIqd");
  }

  if (searchRadiusM == null || searchRadiusM < 500 || searchRadiusM > 10000) {
    errors.push("searchRadiusM");
  }

  if (!optionalText(body?.note, 1000)) errors.push("note");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      pickupLatitude,
      pickupLongitude,
      dropoffLatitude,
      dropoffLongitude,
      pickupLabel: String(pickupLabel || "").trim(),
      dropoffLabel: String(dropoffLabel || "").trim(),
      proposedFareIqd,
      searchRadiusM,
      note: body?.note == null ? null : String(body.note).trim(),
    },
  };
}

export function validateCaptainPresence(body) {
  const errors = [];

  const isOnline = toBool(body?.isOnline);
  const latitude = resolveCoordinate(body, ["latitude", "lat"]);
  const longitude = resolveCoordinate(body, ["longitude", "lng", "lon"]);
  const headingDeg = resolveCoordinate(body, ["headingDeg", "heading"]);
  const speedKmh = resolveCoordinate(body, ["speedKmh", "speed"]);
  const accuracyM = resolveCoordinate(body, ["accuracyM", "accuracy"]);
  const radiusM = toInt(body?.radiusM ?? 3000);

  if (isOnline == null) errors.push("isOnline");

  if (isOnline === true) {
    if (latitude == null || latitude < -90 || latitude > 90) errors.push("latitude");
    if (longitude == null || longitude < -180 || longitude > 180) errors.push("longitude");
  }

  if (headingDeg != null && (headingDeg < 0 || headingDeg > 360)) errors.push("headingDeg");
  if (speedKmh != null && (speedKmh < 0 || speedKmh > 300)) errors.push("speedKmh");
  if (accuracyM != null && (accuracyM < 0 || accuracyM > 5000)) errors.push("accuracyM");

  if (radiusM == null || radiusM < 500 || radiusM > 10000) errors.push("radiusM");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      isOnline,
      latitude,
      longitude,
      headingDeg,
      speedKmh,
      accuracyM,
      radiusM,
    },
  };
}

export function validateNearbyQuery(query) {
  const errors = [];

  const radiusM = toInt(query?.radiusM ?? 3000);
  const limit = toInt(query?.limit ?? 40);

  if (radiusM == null || radiusM < 500 || radiusM > 10000) errors.push("radiusM");
  if (limit == null || limit < 1 || limit > 200) errors.push("limit");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      radiusM,
      limit,
    },
  };
}

export function validateCreateBid(body) {
  const errors = [];
  const offeredFareIqd = toInt(body?.offeredFareIqd);
  const etaMinutes = body?.etaMinutes == null ? null : toInt(body?.etaMinutes);

  if (offeredFareIqd == null || offeredFareIqd < 0 || offeredFareIqd > 5000000) {
    errors.push("offeredFareIqd");
  }

  if (etaMinutes != null && (etaMinutes < 1 || etaMinutes > 180)) {
    errors.push("etaMinutes");
  }

  if (!optionalText(body?.note, 500)) errors.push("note");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      offeredFareIqd,
      etaMinutes,
      note: body?.note == null ? null : String(body.note).trim(),
    },
  };
}

export function validateLocationUpdate(body) {
  const errors = [];

  const latitude = resolveCoordinate(body, ["latitude", "lat"]);
  const longitude = resolveCoordinate(body, ["longitude", "lng", "lon"]);
  const headingDeg = resolveCoordinate(body, ["headingDeg", "heading"]);
  const speedKmh = resolveCoordinate(body, ["speedKmh", "speed"]);
  const accuracyM = resolveCoordinate(body, ["accuracyM", "accuracy"]);

  if (latitude == null || latitude < -90 || latitude > 90) errors.push("latitude");
  if (longitude == null || longitude < -180 || longitude > 180) errors.push("longitude");

  if (headingDeg != null && (headingDeg < 0 || headingDeg > 360)) errors.push("headingDeg");
  if (speedKmh != null && (speedKmh < 0 || speedKmh > 300)) errors.push("speedKmh");
  if (accuracyM != null && (accuracyM < 0 || accuracyM > 5000)) errors.push("accuracyM");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      latitude,
      longitude,
      headingDeg,
      speedKmh,
      accuracyM,
    },
  };
}

export function validateHistoryQuery(query) {
  const errors = [];
  const limit = toInt(query?.limit ?? 20);
  const periodRaw = String(query?.period ?? "month").trim().toLowerCase();
  const period = ["day", "week", "month", "all"].includes(periodRaw)
    ? periodRaw
    : "month";

  if (limit == null || limit < 1 || limit > 200) {
    errors.push("limit");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      period,
      limit,
    },
  };
}

export function validateCaptainProfileEditRequest(body) {
  const errors = [];
  const requestedChanges =
    body?.requestedChanges && typeof body.requestedChanges === "object"
      ? body.requestedChanges
      : {};
  const captainNote = body?.captainNote;

  if (
    requestedChanges == null ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    errors.push("requestedChanges");
  } else if (Object.keys(requestedChanges).length === 0) {
    errors.push("requestedChanges");
  }

  if (
    captainNote !== undefined &&
    captainNote !== null &&
    (typeof captainNote !== "string" || captainNote.trim().length > 1200)
  ) {
    errors.push("captainNote");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      requestedChanges,
      captainNote:
        typeof captainNote === "string" ? captainNote.trim() : null,
    },
  };
}

export function validateShareToken(token) {
  const value = String(token || "").trim();
  if (!value || value.length < 10 || value.length > 120) {
    return { ok: false, errors: ["token"] };
  }
  return { ok: true, errors: [], value };
}

export function validateCounterOffer(body) {
  const errors = [];
  const offeredFareIqd = toInt(body?.offeredFareIqd);

  if (offeredFareIqd == null || offeredFareIqd < 0 || offeredFareIqd > 5000000) {
    errors.push("offeredFareIqd");
  }
  if (!optionalText(body?.note, 500)) {
    errors.push("note");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      offeredFareIqd,
      note: body?.note == null ? null : String(body.note).trim(),
    },
  };
}

export function validateRideChatMessage(body) {
  const errors = [];
  const messageText = typeof body?.messageText === "string" ? body.messageText.trim() : "";

  if (!messageText || messageText.length > 1200) {
    errors.push("messageText");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: { messageText },
  };
}

export function validateRideChatQuery(query) {
  const errors = [];
  const limit = toInt(query?.limit ?? 120);
  if (limit == null || limit < 1 || limit > 400) {
    errors.push("limit");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: limit ?? 120,
    },
  };
}

export function validateRideCallSignal(body) {
  const errors = [];
  const sessionId =
    body?.sessionId == null ? null : toInt(body?.sessionId);
  const signalType = String(body?.signalType || "").trim().toLowerCase();
  const signalPayload =
    body?.signalPayload && typeof body.signalPayload === "object"
      ? body.signalPayload
      : null;

  const allowedTypes = new Set([
    "offer",
    "answer",
    "ice",
    "ringing",
    "accept",
    "hangup",
    "decline",
  ]);

  if (!allowedTypes.has(signalType)) {
    errors.push("signalType");
  }

  if (sessionId != null && sessionId <= 0) {
    errors.push("sessionId");
  }

  if (["offer", "answer"].includes(signalType)) {
    const sdp = String(signalPayload?.sdp || "").trim();
    const sdpType = String(signalPayload?.type || "").trim().toLowerCase();
    if (!sdp || sdp.length < 10) errors.push("signalPayload.sdp");
    if (!["offer", "answer"].includes(sdpType)) errors.push("signalPayload.type");
  }

  if (signalType === "ice") {
    const candidate = String(signalPayload?.candidate || "").trim();
    if (!candidate) errors.push("signalPayload.candidate");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      sessionId,
      signalType,
      signalPayload,
    },
  };
}

export function validateRideCallEnd(body) {
  const errors = [];
  const reasonRaw = body?.reason;
  const statusRaw = String(body?.status || "ended").trim().toLowerCase();
  const status = ["ended", "declined", "missed"].includes(statusRaw)
    ? statusRaw
    : "ended";

  if (
    reasonRaw !== undefined &&
    reasonRaw !== null &&
    (typeof reasonRaw !== "string" || reasonRaw.trim().length > 200)
  ) {
    errors.push("reason");
  }

  if (!["ended", "declined", "missed"].includes(status)) {
    errors.push("status");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      reason: typeof reasonRaw === "string" ? reasonRaw.trim() : null,
      status,
    },
  };
}

export function validateRideCallStateQuery(query) {
  const errors = [];
  const signalLimit = toInt(query?.signalLimit ?? 160);
  if (signalLimit == null || signalLimit < 1 || signalLimit > 800) {
    errors.push("signalLimit");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      signalLimit: signalLimit ?? 160,
    },
  };
}
