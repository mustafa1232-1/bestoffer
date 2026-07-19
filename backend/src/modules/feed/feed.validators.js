function asTrimmed(value) {
  if (value == null) return "";
  return String(value).trim();
}

function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function asApartmentCode(value) {
  const normalized = normalizeDigits(value).trim().toUpperCase();
  if (!normalized) return null;
  if (/^G(0[1-9]|1[0-2])$/.test(normalized)) return normalized;
  if (/^[1-9](0[1-9]|1[0-2])$/.test(normalized)) return normalized;
  return "__invalid__";
}

function asPositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function asClientMessageId(value) {
  if (value == null) return null;
  const text = asTrimmed(value);
  if (!text) return null;
  if (text.length > 120) return "__invalid__";
  return text;
}

function asPositiveIntArray(value) {
  if (value == null || value === "") return [];
  const raw = Array.isArray(value)
    ? value
    : String(value)
        .split(",")
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
  return [...new Set(raw.map(asPositiveInt).filter((item) => item != null))];
}

function isNonEmptyString(value, maxLen) {
  if (value == null) return false;
  const text = String(value).trim();
  if (!text) return false;
  return text.length <= Number(maxLen || 0);
}

function isOptionalString(value, maxLen) {
  if (value == null) return true;
  const text = String(value).trim();
  return text.length <= Number(maxLen || 0);
}

function asBooleanOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (value === 1) return true;
    if (value === 0) return false;
    return null;
  }
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return null;
}

function readBooleanField(body, keys, errors, fieldName, fallback = true) {
  for (const key of keys) {
    if (!(key in body)) continue;
    const parsed = asBooleanOrNull(body[key]);
    if (parsed == null) {
      errors.push(fieldName);
      return fallback;
    }
    return parsed;
  }
  return fallback;
}

const sharedEntityTypeAllowlist = new Set([
  "post",
  "reel",
  "story",
  "profile",
  "user",
  "review",
  "merchant_review",
  "car_listing",
  "real_estate_listing",
  "location",
  "service_offering",
  "service_provider",
  "service_request",
]);

function asFutureDateTimeOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "__invalid__";
  return parsed.toISOString();
}

function asSocialVisibilityOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const normalized = String(value).trim().toLowerCase();
  if (["everyone", "connections", "nobody"].includes(normalized)) {
    return normalized;
  }
  return null;
}

function asSocialAgeOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isInteger(n)) return Number.NaN;
  if (n < 13 || n > 100) return Number.NaN;
  return n;
}

function asResidenceCodeOrNull(value, maxLen = 24) {
  if (value === undefined || value === null || value === "") return null;
  const normalized = normalizeDigits(value).trim().toUpperCase();
  if (!normalized || normalized.length > maxLen) return "__invalid__";
  return normalized;
}

export function validateResidenceChangeBody(body = {}) {
  const errors = [];
  const block = asResidenceCodeOrNull(body.block ?? body.town, 20);
  const buildingNumber = asResidenceCodeOrNull(
    body.buildingNumber ?? body.building_number,
    24
  );
  const apartmentNumber = asResidenceCodeOrNull(
    body.apartmentNumber ?? body.apartment_number ?? body.apartment,
    24
  );
  const note =
    body.note === undefined || body.note === null ? null : String(body.note).trim();
  const documentImageUrl =
    body.documentImageUrl === undefined || body.documentImageUrl === null
      ? null
      : String(body.documentImageUrl).trim();

  if (!block || block === "__invalid__") errors.push("block");
  if (!buildingNumber || buildingNumber === "__invalid__") {
    errors.push("buildingNumber");
  }
  if (!apartmentNumber || apartmentNumber === "__invalid__") {
    errors.push("apartmentNumber");
  }
  if (note != null && note.length > 1000) errors.push("note");
  if (documentImageUrl != null && documentImageUrl.length > 1000) {
    errors.push("documentImageUrl");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      block: block && block !== "__invalid__" ? block : null,
      town:
        block && block !== "__invalid__"
          ? /^[AB]/.test(block)
            ? block.slice(0, 1)
            : block
          : null,
      buildingNumber:
        buildingNumber && buildingNumber !== "__invalid__" ? buildingNumber : null,
      apartmentNumber:
        apartmentNumber && apartmentNumber !== "__invalid__" ? apartmentNumber : null,
      note: note ? note : null,
      documentImageUrl: documentImageUrl ? documentImageUrl : null,
    },
  };
}

export function validateResidenceChangeId(value) {
  const parsed = asPositiveInt(value);
  return {
    ok: parsed != null,
    errors: parsed == null ? ["requestId"] : [],
    value: parsed,
  };
}

export function validateListPosts(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 20);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const kind = asTrimmed(query.kind).toLowerCase();

  if (!Number.isInteger(limit) || limit < 1 || limit > 50) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  if (kind && !["text", "image", "video", "reel", "merchant_review", "review"].includes(kind)) {
    errors.push("kind");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(50, Math.max(1, Number.isInteger(limit) ? limit : 20)),
      beforeId,
      kind: kind || null,
    },
  };
}

export function validateListStories(query = {}) {
  const limitUsers = Number(query.limitUsers ?? 30);
  const maxPerUser = Number(query.maxPerUser ?? 8);
  const errors = [];

  if (!Number.isInteger(limitUsers) || limitUsers < 1 || limitUsers > 80) {
    errors.push("limitUsers");
  }
  if (!Number.isInteger(maxPerUser) || maxPerUser < 1 || maxPerUser > 20) {
    errors.push("maxPerUser");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limitUsers: Math.min(
        80,
        Math.max(1, Number.isInteger(limitUsers) ? limitUsers : 30)
      ),
      maxPerUser: Math.min(
        20,
        Math.max(1, Number.isInteger(maxPerUser) ? maxPerUser : 8)
      ),
    },
  };
}

export function validateListStoryArchive(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 40);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);

  if (!Number.isInteger(limit) || limit < 1 || limit > 100) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(100, Math.max(1, Number.isInteger(limit) ? limit : 40)),
      beforeId,
    },
  };
}

export function validateCreatePost(body = {}) {
  const errors = [];
  const caption = asTrimmed(body.caption);
  const postKind = asTrimmed(body.postKind || body.post_kind).toLowerCase() || "text";
  const storyStyle = _parseStoryStyle(
    body.storyStyle ?? body.story_style ?? body.reelStyle ?? body.reel_style,
    errors
  );
  const requestedAudienceType = asTrimmed(
    body.audienceScopeType ??
      body.audience_scope_type ??
      body.scopeType ??
      body.scope_type
  ).toLowerCase();
  const requestedAudienceCode = asTrimmed(
    body.audienceScopeCode ??
      body.audience_scope_code ??
      body.scopeCode ??
      body.scope_code
  ).toUpperCase();
  const merchantId =
    body.merchantId == null || body.merchantId === ""
      ? null
      : asPositiveInt(body.merchantId);
  const mediaAssetId =
    body.mediaAssetId == null || body.mediaAssetId === ""
      ? null
      : asPositiveInt(body.mediaAssetId);
  const reviewRating =
    body.reviewRating == null || body.reviewRating === ""
      ? null
      : Number(body.reviewRating);
  const taggedUserIds = asPositiveIntArray(
    body.taggedUserIds ?? body.tagged_user_ids
  );
  const sharedEntityType = asTrimmed(
    body.sharedEntityType ?? body.shared_entity_type ?? body.sharedEntity?.type
  ).toLowerCase();
  const sharedEntityId = asPositiveInt(
    body.sharedEntityId ?? body.shared_entity_id ?? body.sharedEntity?.id
  );
  const sharedSnapshot =
    body.sharedEntity?.snapshot &&
    typeof body.sharedEntity.snapshot === "object" &&
    !Array.isArray(body.sharedEntity.snapshot)
      ? body.sharedEntity.snapshot
      : body.sharedSnapshot &&
          typeof body.sharedSnapshot === "object" &&
          !Array.isArray(body.sharedSnapshot)
      ? body.sharedSnapshot
      : body.shared_snapshot &&
          typeof body.shared_snapshot === "object" &&
          !Array.isArray(body.shared_snapshot)
      ? body.shared_snapshot
      : null;

  if (caption.length > 1200) errors.push("caption");
  if (!["text", "image", "video", "reel", "merchant_review"].includes(postKind)) {
    errors.push("postKind");
  }
  if (body.merchantId != null && merchantId == null) errors.push("merchantId");
  if (body.mediaAssetId != null && mediaAssetId == null) errors.push("mediaAssetId");
  if (
    body.reviewRating != null &&
    (!Number.isInteger(reviewRating) || reviewRating < 1 || reviewRating > 5)
  ) {
    errors.push("reviewRating");
  }

  if (postKind === "merchant_review") {
    if (merchantId == null) errors.push("merchantId_required");
    if (reviewRating == null) errors.push("reviewRating_required");
  }
  if (sharedEntityType.length > 0) {
    if (!sharedEntityTypeAllowlist.has(sharedEntityType)) {
      errors.push("sharedEntityType");
    }
    if (sharedEntityId == null) {
      errors.push("sharedEntityId");
    }
  } else if (sharedEntityId != null) {
    errors.push("sharedEntityType");
  }

  let audienceScopeType = null;
  let audienceScopeCode = null;
  if (requestedAudienceCode && !requestedAudienceType) {
    errors.push("audienceScopeType");
  }
  if (requestedAudienceType) {
    if (requestedAudienceType === "global") {
      audienceScopeType = "global";
      audienceScopeCode = null;
    } else {
      const normalizedScope = normalizeCommunityScope(
        requestedAudienceType,
        requestedAudienceCode
      );
      if (!normalizedScope.ok) {
        errors.push("audienceScopeType", "audienceScopeCode");
      } else {
        audienceScopeType = normalizedScope.scopeType;
        audienceScopeCode = normalizedScope.scopeCode;
      }
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption,
      postKind,
      storyStyle,
      merchantId,
      mediaAssetId,
      reviewRating: reviewRating == null ? null : Math.trunc(reviewRating),
      taggedUserIds,
      sharedEntity:
        sharedEntityType.length === 0 || sharedEntityId == null
          ? null
          : {
              type: sharedEntityType,
              id: sharedEntityId,
              snapshot: sharedSnapshot,
            },
      audienceScopeType,
      audienceScopeCode,
    },
  };
}

export function validateCreateStory(body = {}) {
  const errors = [];
  const caption = asTrimmed(body.caption);
  const storyStyle = _parseStoryStyle(body.storyStyle ?? body.story_style, errors);
  const storyInteractionSettings =
    body.storyInteractionSettings && typeof body.storyInteractionSettings === "object"
      ? body.storyInteractionSettings
      : body.story_interaction_settings &&
          typeof body.story_interaction_settings === "object"
        ? body.story_interaction_settings
        : {};
  const mediaAssetId =
    body.mediaAssetId == null || body.mediaAssetId === ""
      ? null
      : asPositiveInt(body.mediaAssetId);

  if (caption.length > 500) errors.push("caption");
  if (body.mediaAssetId != null && mediaAssetId == null) errors.push("mediaAssetId");

  // Authoritative audience scope (Social V3 §3). Mirrors validateCreatePost.
  // Relationship scopes (followers/close_friends/area/custom) are rejected —
  // only global/block/compound/building are supported for stories.
  const requestedAudienceType = asTrimmed(
    body.audienceScopeType ??
      body.audience_scope_type ??
      body.scopeType ??
      body.scope_type
  ).toLowerCase();
  const requestedAudienceCode = asTrimmed(
    body.audienceScopeCode ??
      body.audience_scope_code ??
      body.scopeCode ??
      body.scope_code
  ).toUpperCase();
  const isOfficial =
    body.isOfficial === true || body.isOfficial === "true" ||
    body.is_official === true || body.is_official === "true";

  let audienceScopeType = "global";
  let audienceScopeCode = null;
  if (requestedAudienceCode && !requestedAudienceType) {
    errors.push("audienceScopeType");
  }
  if (requestedAudienceType) {
    if (requestedAudienceType === "global") {
      audienceScopeType = "global";
      audienceScopeCode = null;
    } else {
      const normalizedScope = normalizeCommunityScope(
        requestedAudienceType,
        requestedAudienceCode
      );
      if (!normalizedScope.ok) {
        errors.push("audienceScopeType", "audienceScopeCode");
      } else {
        audienceScopeType = normalizedScope.scopeType;
        audienceScopeCode = normalizedScope.scopeCode;
      }
    }
  }

  const allowLikes = readBooleanField(
    { ...storyInteractionSettings, ...body },
    ["allowLikes", "allow_likes"],
    errors,
    "allowLikes",
    true
  );
  const allowPrivateReplies = readBooleanField(
    { ...storyInteractionSettings, ...body },
    ["allowPrivateReplies", "allow_private_replies"],
    errors,
    "allowPrivateReplies",
    true
  );
  const allowComments = readBooleanField(
    { ...storyInteractionSettings, ...body },
    ["allowComments", "allow_comments"],
    errors,
    "allowComments",
    true
  );
  const allowSharing = readBooleanField(
    { ...storyInteractionSettings, ...body },
    ["allowSharing", "allow_sharing"],
    errors,
    "allowSharing",
    true
  );
  const allowReshare = readBooleanField(
    { ...storyInteractionSettings, ...body },
    ["allowReshare", "allow_reshare"],
    errors,
    "allowReshare",
    true
  );

  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption,
      storyStyle,
      mediaAssetId,
      audienceScopeType,
      audienceScopeCode,
      allowLikes,
      allowPrivateReplies,
      allowComments,
      allowSharing,
      allowReshare,
      // NOTE: `isOfficial` is a *request* only. The service must re-authorize
      // it against the user's active building role before persisting — never
      // trust this flag from the client.
      isOfficialRequested: isOfficial,
    },
  };
}

export function validateStreamUploadSessionBody(body = {}) {
  const errors = [];
  const sourceType = asTrimmed(body.sourceType || body.source_type).toLowerCase();
  const sizeBytesRaw =
    body.sizeBytes ?? body.size_bytes ?? body.fileSizeBytes ?? body.file_size_bytes;
  const sizeBytes =
    sizeBytesRaw == null || sizeBytesRaw === "" ? null : Number(sizeBytesRaw);
  const title = asTrimmed(body.title);
  const fileName = asTrimmed(body.fileName || body.file_name);
  const mimeType = asTrimmed(body.mimeType || body.mime_type) || "video/mp4";

  if (!["story", "reel"].includes(sourceType)) errors.push("sourceType");
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) errors.push("sizeBytes");
  if (title.length > 180) errors.push("title");
  if (fileName.length > 180) errors.push("fileName");
  if (mimeType.length > 120) errors.push("mimeType");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      sourceType: sourceType || null,
      sizeBytes: sizeBytes == null ? null : Math.trunc(sizeBytes),
      title: title || null,
      fileName: fileName || null,
      mimeType: mimeType || "video/mp4",
    },
  };
}

export function validateMediaAssetId(value) {
  const parsed = value == null || value === "" ? null : asPositiveInt(value);
  return {
    ok: parsed != null,
    errors: parsed == null ? ["mediaAssetId"] : [],
    value: parsed,
  };
}

export function validateResubmitModeratedPost(body = {}, options = {}) {
  const hasMediaUpload = options?.hasMediaUpload === true;
  const errors = [];
  const captionRaw =
    body?.caption === undefined || body?.caption === null
      ? null
      : asTrimmed(body.caption);
  if (captionRaw != null && captionRaw.length > 1200) {
    errors.push("caption_length");
  }
  const clearMedia = asBooleanOrNull(body?.clearMedia);
  if (body?.clearMedia !== undefined && clearMedia == null) {
    errors.push("clearMedia");
  }
  if (hasMediaUpload && clearMedia === true) {
    errors.push("media_conflict");
  }
  if (
    captionRaw == null &&
    !hasMediaUpload &&
    clearMedia !== true
  ) {
    errors.push("no_changes");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption: captionRaw,
      clearMedia: clearMedia === true,
    },
  };
}

export function validateResubmitModeratedStory(body = {}, options = {}) {
  const hasMediaUpload = options?.hasMediaUpload === true;
  const errors = [];
  const captionRaw =
    body?.caption === undefined || body?.caption === null
      ? null
      : asTrimmed(body.caption);
  if (captionRaw != null && captionRaw.length > 500) {
    errors.push("caption_length");
  }
  const clearMedia = asBooleanOrNull(body?.clearMedia);
  if (body?.clearMedia !== undefined && clearMedia == null) {
    errors.push("clearMedia");
  }
  if (hasMediaUpload && clearMedia === true) {
    errors.push("media_conflict");
  }
  if (captionRaw == null && !hasMediaUpload && clearMedia !== true) {
    errors.push("no_changes");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      caption: captionRaw,
      clearMedia: clearMedia === true,
    },
  };
}

export function validatePostId(postId) {
  const value = asPositiveInt(postId);
  return {
    ok: value != null,
    errors: value == null ? ["postId"] : [],
    value,
  };
}

export function validateUserId(userId) {
  const value = asPositiveInt(userId);
  return {
    ok: value != null,
    errors: value == null ? ["userId"] : [],
    value,
  };
}

export function validateStoryId(storyId) {
  const value = asPositiveInt(storyId);
  return {
    ok: value != null,
    errors: value == null ? ["storyId"] : [],
    value,
  };
}

function _parseStoryStyle(rawStyle, errors) {
  if (rawStyle == null || rawStyle === "") return {};

  let style = rawStyle;
  if (typeof rawStyle === "string") {
    try {
      style = JSON.parse(rawStyle);
    } catch (_) {
      errors.push("storyStyle");
      return {};
    }
  }

  if (!style || typeof style !== "object" || Array.isArray(style)) {
    errors.push("storyStyle");
    return {};
  }

  const out = {};
  const hexColorPattern = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/;
  const textAlignAllowed = new Set(["left", "center", "right"]);
  const fontWeightAllowed = new Set(["normal", "bold", "heavy"]);
  const fontFamilyAllowed = new Set(["system", "serif", "monospace"]);
  const backgroundTypeMap = new Map([
    ["solid", "solid"],
    ["gradient", "gradient"],
    ["posterblur", "posterBlur"],
    ["poster_blur", "posterBlur"],
    ["posterblurred", "posterBlur"],
  ]);
  const modeMap = new Map([
    ["text", "text"],
    ["media", "media"],
    ["reelshare", "reelShare"],
    ["reel_share", "reelShare"],
    ["postshare", "postShare"],
    ["post_share", "postShare"],
  ]);
  const attachmentTypeAllowed = new Set([
    "reel_share",
    "reelshare",
    "post_share",
    "postshare",
  ]);
  const layerTypeMap = new Map([
    ["text", "text"],
    ["mention", "mention"],
    ["sticker", "sticker"],
    ["draw", "draw"],
    ["reelshare", "reelShare"],
    ["reel_share", "reelShare"],
    ["postshare", "postShare"],
    ["post_share", "postShare"],
  ]);

  function isHexColor(value) {
    return hexColorPattern.test(String(value || "").trim());
  }

  function readColor(value, fieldPath) {
    const text = asTrimmed(value);
    if (!text) return null;
    if (!isHexColor(text)) {
      errors.push(fieldPath);
      return null;
    }
    return text;
  }

  function readNumber(value, fieldPath, { min = null, max = null } = {}) {
    if (value == null || value === "") return null;
    const num = Number(value);
    if (!Number.isFinite(num)) {
      errors.push(fieldPath);
      return null;
    }
    if (min != null && num < min) {
      errors.push(fieldPath);
      return null;
    }
    if (max != null && num > max) {
      errors.push(fieldPath);
      return null;
    }
    return num;
  }

  function sanitizeLayer(layer, index) {
    if (!layer || typeof layer !== "object" || Array.isArray(layer)) {
      errors.push(`storyStyle.layers[${index}]`);
      return null;
    }
    const type = layerTypeMap.get(asTrimmed(layer.type).toLowerCase());
    if (!type) {
      errors.push(`storyStyle.layers[${index}].type`);
      return null;
    }
    const outLayer = {
      id: asTrimmed(layer.id).slice(0, 80) || `layer_${index + 1}`,
      type,
      x: readNumber(layer.x, `storyStyle.layers[${index}].x`, { min: -1.5, max: 1.5 }) ?? 0,
      y: readNumber(layer.y, `storyStyle.layers[${index}].y`, { min: -1.5, max: 1.5 }) ?? 0,
      scale:
        readNumber(layer.scale, `storyStyle.layers[${index}].scale`, {
          min: 0.2,
          max: 4,
        }) ?? 1,
      rotation:
        readNumber(layer.rotation, `storyStyle.layers[${index}].rotation`, {
          min: -6.4,
          max: 6.4,
        }) ?? 0,
      zIndex:
        readNumber(layer.zIndex, `storyStyle.layers[${index}].zIndex`, {
          min: -100,
          max: 100,
        }) ?? index,
      locked: asBooleanOrNull(layer.locked) === true,
    };

    const text = asTrimmed(layer.text);
    if (text) outLayer.text = text.slice(0, 800);
    const textColor = readColor(layer.color, `storyStyle.layers[${index}].color`);
    if (textColor) outLayer.color = textColor;
    const bgColor = readColor(
      layer.backgroundColor,
      `storyStyle.layers[${index}].backgroundColor`
    );
    if (bgColor) outLayer.backgroundColor = bgColor;
    const fontFamily = asTrimmed(layer.fontFamily).toLowerCase();
    if (fontFamily) {
      if (fontFamilyAllowed.has(fontFamily)) outLayer.fontFamily = fontFamily;
      else errors.push(`storyStyle.layers[${index}].fontFamily`);
    }
    const fontWeight = asTrimmed(layer.fontWeight).toLowerCase();
    if (fontWeight) {
      if (fontWeightAllowed.has(fontWeight)) outLayer.fontWeight = fontWeight;
      else errors.push(`storyStyle.layers[${index}].fontWeight`);
    }
    const textAlign = asTrimmed(layer.textAlign).toLowerCase();
    if (textAlign) {
      if (textAlignAllowed.has(textAlign)) outLayer.textAlign = textAlign;
      else errors.push(`storyStyle.layers[${index}].textAlign`);
    }
    const fontScale = readNumber(layer.fontScale, `storyStyle.layers[${index}].fontScale`, {
      min: 0.5,
      max: 4,
    });
    if (fontScale != null) outLayer.fontScale = fontScale;
    const mentionedUserId = asPositiveInt(layer.mentionedUserId ?? layer.mentioned_user_id);
    if (type === "mention") {
      if (mentionedUserId == null) {
        errors.push(`storyStyle.layers[${index}].mentionedUserId`);
      } else {
        outLayer.mentionedUserId = mentionedUserId;
      }
      const displayLabel = asTrimmed(layer.displayLabel ?? layer.display_label);
      if (!displayLabel) {
        errors.push(`storyStyle.layers[${index}].displayLabel`);
      } else {
        outLayer.displayLabel = displayLabel.slice(0, 80);
        outLayer.text = `@${outLayer.displayLabel}`;
      }
    }
    const widthFactor = readNumber(
      layer.widthFactor,
      `storyStyle.layers[${index}].widthFactor`,
      { min: 0.2, max: 1.4 }
    );
    if (widthFactor != null) outLayer.widthFactor = widthFactor;

    if (type === "sticker") {
      const sticker = asTrimmed(layer.sticker);
      if (!sticker) {
        errors.push(`storyStyle.layers[${index}].sticker`);
      } else {
        outLayer.sticker = sticker.slice(0, 48);
        if (!outLayer.text) outLayer.text = sticker.slice(0, 48);
      }
    }

    if (Array.isArray(layer.strokes) && type === "draw") {
      outLayer.strokes = layer.strokes
        .filter((stroke) => stroke && typeof stroke === "object" && !Array.isArray(stroke))
        .map((stroke, strokeIndex) => {
          const points = Array.isArray(stroke.points)
            ? stroke.points
                .filter((point) => point && typeof point === "object")
                .map((point, pointIndex) => ({
                  x:
                    readNumber(
                      point.x,
                      `storyStyle.layers[${index}].strokes[${strokeIndex}].points[${pointIndex}].x`,
                      { min: 0, max: 1 }
                    ) ?? 0,
                  y:
                    readNumber(
                      point.y,
                      `storyStyle.layers[${index}].strokes[${strokeIndex}].points[${pointIndex}].y`,
                      { min: 0, max: 1 }
                    ) ?? 0,
                }))
            : [];
          return {
            color:
              readColor(
                stroke.color,
                `storyStyle.layers[${index}].strokes[${strokeIndex}].color`
              ) || "#FFFFFF",
            width:
              readNumber(
                stroke.width,
                `storyStyle.layers[${index}].strokes[${strokeIndex}].width`,
                { min: 1, max: 32 }
              ) ?? 4,
            points,
          };
        })
        .filter((stroke) => stroke.points.length > 0);
    }

    return outLayer;
  }

  const backgroundColor = readColor(style.backgroundColor, "storyStyle.backgroundColor");
  if (backgroundColor) out.backgroundColor = backgroundColor;

  const textColor = readColor(style.textColor, "storyStyle.textColor");
  if (textColor) out.textColor = textColor;

  const fontFamily = asTrimmed(style.fontFamily).toLowerCase();
  if (fontFamily) {
    if (fontFamilyAllowed.has(fontFamily)) out.fontFamily = fontFamily;
    else errors.push("storyStyle.fontFamily");
  }

  const align = asTrimmed(style.textAlign).toLowerCase();
  if (align) {
    if (textAlignAllowed.has(align)) out.textAlign = align;
    else errors.push("storyStyle.textAlign");
  }

  const weight = asTrimmed(style.fontWeight).toLowerCase();
  if (weight) {
    if (fontWeightAllowed.has(weight)) out.fontWeight = weight;
    else errors.push("storyStyle.fontWeight");
  }

  const fontScaleRaw = readNumber(style.fontScale, "storyStyle.fontScale", {
    min: 0.8,
    max: 2.4,
  });
  if (fontScaleRaw != null) out.fontScale = fontScaleRaw;

  const clipStartSecRaw = readNumber(style.clipStartSec, "storyStyle.clipStartSec", {
    min: 0,
    max: 86400,
  });
  if (clipStartSecRaw != null) out.clipStartSec = clipStartSecRaw;

  const clipDurationSecRaw = readNumber(
    style.clipDurationSec,
    "storyStyle.clipDurationSec",
    { min: 0.001, max: 60 }
  );
  if (clipDurationSecRaw != null) out.clipDurationSec = clipDurationSecRaw;

  const sharedPostId = asPositiveInt(style.sharedPostId);
  if (style.sharedPostId != null && style.sharedPostId !== "") {
    if (sharedPostId != null) out.sharedPostId = sharedPostId;
    else errors.push("storyStyle.sharedPostId");
  }

  const sharedPostAuthor = asTrimmed(style.sharedPostAuthor);
  if (sharedPostAuthor) out.sharedPostAuthor = sharedPostAuthor.slice(0, 120);

  const sharedPostCaption = asTrimmed(style.sharedPostCaption);
  if (sharedPostCaption) out.sharedPostCaption = sharedPostCaption.slice(0, 800);

  const sharedPostMediaUrl = asTrimmed(style.sharedPostMediaUrl);
  if (sharedPostMediaUrl) out.sharedPostMediaUrl = sharedPostMediaUrl.slice(0, 1400);

  const sharedPostMediaKind = asTrimmed(style.sharedPostMediaKind).toLowerCase();
  if (sharedPostMediaKind) {
    const allowedKinds = new Set(["image", "video"]);
    if (allowedKinds.has(sharedPostMediaKind)) out.sharedPostMediaKind = sharedPostMediaKind;
    else errors.push("storyStyle.sharedPostMediaKind");
  }

  const version = readNumber(style.version, "storyStyle.version", { min: 1, max: 99 });
  if (version != null) out.version = Math.trunc(version);

  const mode = modeMap.get(asTrimmed(style.mode).toLowerCase());
  if (style.mode != null && style.mode !== "") {
    if (mode) out.mode = mode;
    else errors.push("storyStyle.mode");
  }

  if (style.background != null) {
    if (!style.background || typeof style.background !== "object" || Array.isArray(style.background)) {
      errors.push("storyStyle.background");
    } else {
      const backgroundType = backgroundTypeMap.get(
        asTrimmed(style.background.type).toLowerCase()
      );
      if (!backgroundType) {
        errors.push("storyStyle.background.type");
      } else {
        const background = { type: backgroundType };
        const primaryColor = readColor(
          style.background.primaryColor,
          "storyStyle.background.primaryColor"
        );
        if (primaryColor) background.primaryColor = primaryColor;
        const secondaryColor = readColor(
          style.background.secondaryColor,
          "storyStyle.background.secondaryColor"
        );
        if (secondaryColor) background.secondaryColor = secondaryColor;
        const imageUrl = asTrimmed(
          style.background.imageUrl ??
            style.background.image_url ??
            style.background.posterUrl ??
            style.background.poster_url
        );
        if (imageUrl) background.imageUrl = imageUrl.slice(0, 1400);
        out.background = background;
      }
    }
  }

  if (style.attachment != null) {
    if (!style.attachment || typeof style.attachment !== "object" || Array.isArray(style.attachment)) {
      errors.push("storyStyle.attachment");
    } else {
      const attachmentTypeRaw = asTrimmed(style.attachment.type).toLowerCase();
      const attachmentType = attachmentTypeRaw.replace(/[\s-]+/g, "");
      if (!attachmentTypeAllowed.has(attachmentType)) {
        errors.push("storyStyle.attachment.type");
      } else {
        const attachment = {
          type: attachmentType.includes("reel") ? "reel_share" : "post_share",
        };
        const reelId = asPositiveInt(style.attachment.reelId ?? style.attachment.reel_id);
        const postId = asPositiveInt(style.attachment.postId ?? style.attachment.post_id);
        if (attachmentType === "reel_share" || attachmentType === "reelshare") {
          if (reelId == null) errors.push("storyStyle.attachment.reelId");
          else attachment.reelId = reelId;
        }
        if (attachmentType === "post_share" || attachmentType === "postshare") {
          if (postId == null) errors.push("storyStyle.attachment.postId");
          else attachment.postId = postId;
        }
        const mediaAssetId = asPositiveInt(
          style.attachment.mediaAssetId ?? style.attachment.media_asset_id
        );
        if (mediaAssetId != null) attachment.mediaAssetId = mediaAssetId;
        const streamUid = asTrimmed(style.attachment.streamUid || style.attachment.stream_uid);
        if (streamUid) attachment.streamUid = streamUid.slice(0, 120);
        const authorId = asPositiveInt(style.attachment.authorId ?? style.attachment.author_id);
        if (authorId != null) attachment.authorId = authorId;
        const posterUrl = asTrimmed(style.attachment.posterUrl || style.attachment.poster_url);
        if (posterUrl) attachment.posterUrl = posterUrl.slice(0, 1400);
        const mediaUrl = asTrimmed(style.attachment.mediaUrl || style.attachment.media_url);
        if (mediaUrl) attachment.mediaUrl = mediaUrl.slice(0, 1400);
        const playbackUrl = asTrimmed(
          style.attachment.playbackUrl || style.attachment.playback_url
        );
        if (playbackUrl) attachment.playbackUrl = playbackUrl.slice(0, 1400);
        const thumbnailUrl = asTrimmed(
          style.attachment.thumbnailUrl || style.attachment.thumbnail_url
        );
        if (thumbnailUrl) attachment.thumbnailUrl = thumbnailUrl.slice(0, 1400);
        const mediaKind = asTrimmed(style.attachment.mediaKind || style.attachment.media_kind)
          .toLowerCase();
        if (mediaKind) {
          if (new Set(["image", "video", "reel"]).has(mediaKind)) {
            attachment.mediaKind = mediaKind;
          } else {
            errors.push("storyStyle.attachment.mediaKind");
          }
        }
        const authorName = asTrimmed(style.attachment.authorName || style.attachment.author_name);
        if (authorName) attachment.authorName = authorName.slice(0, 120);
        const aspectRatio = readNumber(
          style.attachment.aspectRatio ?? style.attachment.aspect_ratio,
          "storyStyle.attachment.aspectRatio",
          { min: 0.1, max: 20 }
        );
        if (aspectRatio != null) attachment.aspectRatio = aspectRatio;
        const captionText = asTrimmed(style.attachment.caption);
        if (captionText) attachment.caption = captionText.slice(0, 300);
        const label = asTrimmed(style.attachment.label);
        if (label) attachment.label = label.slice(0, 60);
        out.attachment = attachment;
      }
    }
  }

  if (Array.isArray(style.layers)) {
    out.layers = style.layers
      .map((layer, index) => sanitizeLayer(layer, index))
      .filter(Boolean);
  }

  return out;
}

export function validateCreateComment(body = {}) {
  const text = asTrimmed(body.body);
  const parentCommentId =
    body.parentCommentId == null ? null : asPositiveInt(body.parentCommentId);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 600) errors.push("body_length");
  if (body.parentCommentId != null && parentCommentId == null) {
    errors.push("parentCommentId");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      body: text,
      parentCommentId,
    },
  };
}

export function validateCommentId(commentId) {
  const value = asPositiveInt(commentId);
  return {
    ok: value != null,
    errors: value == null ? ["commentId"] : [],
    value,
  };
}

export function validateUpdateComment(body = {}) {
  const text = asTrimmed(body.body);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 600) errors.push("body_length");
  return {
    ok: errors.length === 0,
    errors,
    value: { body: text },
  };
}

export function validateReportBody(body = {}) {
  const reason = asTrimmed(body.reason);
  const details = asTrimmed(body.details);
  const errors = [];
  if (!reason) errors.push("reason");
  if (reason.length > 180) errors.push("reason_length");
  if (details.length > 1200) errors.push("details_length");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      reason,
      details: details || null,
    },
  };
}

export function validateMerchantSearch(query = {}) {
  const search = asTrimmed(query.search);
  const limit = Number(query.limit ?? 120);
  const errors = [];
  if (search.length > 80) errors.push("search");
  if (!Number.isInteger(limit) || limit < 1 || limit > 300) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Math.min(300, Math.max(1, Number.isInteger(limit) ? limit : 120)),
    },
  };
}

export function validateUserSearch(query = {}) {
  const search = asTrimmed(query.search);
  const limit = Number(query.limit ?? 60);
  const errors = [];
  if (search.length > 80) errors.push("search");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Math.min(200, Math.max(1, Number.isInteger(limit) ? limit : 60)),
    },
  };
}

export function validateCreateThread(body = {}) {
  const userId = asPositiveInt(body.userId);
  const kind = asTrimmed(body.kind).toLowerCase() || "private";
  const title = asTrimmed(body.title);
  const imageUrl = asTrimmed(body.imageUrl ?? body.image_url);
  const rawMemberIds = Array.isArray(body.memberIds ?? body.member_ids)
    ? body.memberIds ?? body.member_ids
    : [];
  const memberIds = [
    ...new Set(
      rawMemberIds
        .map((value) => asPositiveInt(value))
        .filter((value) => value != null)
    ),
  ];
  const contextType = asTrimmed(
    body.contextType ?? body.context_type ?? body.context?.type
  ).toLowerCase();
  const contextId = asPositiveInt(
    body.contextId ?? body.context_id ?? body.context?.id
  );
  const errors = [];
  if (!["private", "business", "group"].includes(kind)) errors.push("kind");
  if (kind === "business") {
    if (userId == null) errors.push("userId");
    if (
      ![
        "car_listing",
        "real_estate_listing",
        "service_offering",
        "service_provider",
        "service_request",
      ].includes(contextType)
    ) {
      errors.push("contextType");
    }
    if (contextId == null) errors.push("contextId");
  } else if (kind === "group") {
    if (!title || title.length > 80) errors.push("title");
    if (imageUrl.length > 2000) errors.push("imageUrl");
    if (memberIds.length < 1 || memberIds.length > 32) errors.push("memberIds");
    if (userId != null) errors.push("userId");
    if (contextType.length > 0) errors.push("contextType");
    if (contextId != null) errors.push("contextId");
  } else {
    if (userId == null) errors.push("userId");
    if (contextType.length > 0) errors.push("contextType");
    if (contextId != null) errors.push("contextId");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      userId,
      kind,
      title: kind === "group" ? title : null,
      imageUrl: kind === "group" && imageUrl.length > 0 ? imageUrl : null,
      memberIds: kind === "group" ? memberIds : [],
      context:
        kind === "business" && contextType.length > 0 && contextId != null
          ? { type: contextType, id: contextId }
          : null,
    },
  };
}

export function validateThreadId(threadId) {
  const value = asPositiveInt(threadId);
  return {
    ok: value != null,
    errors: value == null ? ["threadId"] : [],
    value,
  };
}

export function validateUpdateGroupThread(body = {}) {
  const title = asTrimmed(body.title);
  const errors = [];
  if (!title || title.length > 80) errors.push("title");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      title,
    },
  };
}

export function validateGroupThreadMembersBody(body = {}) {
  const rawMemberIds = Array.isArray(body.memberIds ?? body.member_ids)
    ? body.memberIds ?? body.member_ids
    : [];
  const memberIds = [
    ...new Set(
      rawMemberIds
        .map((value) => asPositiveInt(value))
        .filter((value) => value != null)
    ),
  ];
  const errors = [];
  if (memberIds.length < 1 || memberIds.length > 32) errors.push("memberIds");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      memberIds,
    },
  };
}

export function validateGroupThreadMemberRoleBody(body = {}) {
  const normalizedRole = asTrimmed(body.memberRole ?? body.member_role).toLowerCase();
  const errors = [];
  if (!["admin", "member"].includes(normalizedRole)) {
    errors.push("memberRole");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      memberRole: normalizedRole,
    },
  };
}

export function validateMessageId(messageId) {
  const value = asPositiveInt(messageId);
  return {
    ok: value != null,
    errors: value == null ? ["messageId"] : [],
    value,
  };
}

export function validateListMessages(query = {}) {
  const limit = Number(query.limit ?? 40);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const errors = [];
  if (!Number.isInteger(limit) || limit < 1 || limit > 80) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(80, Math.max(1, Number.isInteger(limit) ? limit : 40)),
      beforeId,
    },
  };
}

export function validateThreadMessageSearchQuery(query = {}) {
  const search = asTrimmed(query.search ?? query.q);
  const limit = Number(query.limit ?? 20);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const errors = [];
  if (!search || search.length < 1 || search.length > 120) {
    errors.push("search");
  }
  if (!Number.isInteger(limit) || limit < 1 || limit > 60) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Math.min(60, Math.max(1, Number.isInteger(limit) ? limit : 20)),
      beforeId,
    },
  };
}

export function validateSendMessage(body = {}) {
  const text = asTrimmed(body.body);
  const replyToMessageId =
    body.replyToMessageId == null || body.replyToMessageId === ""
      ? null
      : asPositiveInt(body.replyToMessageId);
  const clientMessageId = asClientMessageId(
    body.clientMessageId ?? body.client_message_id
  );
  const attachmentDurationMs =
    body.attachmentDurationMs == null || body.attachmentDurationMs === ""
      ? null
      : asPositiveInt(body.attachmentDurationMs);
  const errors = [];
  const sharedEntityType = asTrimmed(
    body.sharedEntityType ??
      body.shared_entity_type ??
      body.sharedEntity?.type
  ).toLowerCase();
  const sharedEntityId = asPositiveInt(
    body.sharedEntityId ?? body.shared_entity_id ?? body.sharedEntity?.id
  );
  const sharedSnapshot =
    body.sharedEntity?.snapshot &&
    typeof body.sharedEntity.snapshot === "object" &&
    !Array.isArray(body.sharedEntity.snapshot)
      ? body.sharedEntity.snapshot
      : body.sharedSnapshot &&
          typeof body.sharedSnapshot === "object" &&
          !Array.isArray(body.sharedSnapshot)
      ? body.sharedSnapshot
      : body.shared_snapshot &&
          typeof body.shared_snapshot === "object" &&
          !Array.isArray(body.shared_snapshot)
      ? body.shared_snapshot
      : null;
  if (!text && body.hasAttachment !== true && sharedEntityId == null) {
    errors.push("body");
  }
  if (text.length > 1200) errors.push("body_length");
  if (body.replyToMessageId != null && replyToMessageId == null) {
    errors.push("replyToMessageId");
  }
  if (body.clientMessageId != null && clientMessageId == null) {
    errors.push("clientMessageId");
  }
  if (clientMessageId === "__invalid__") {
    errors.push("clientMessageId");
  }
  if (body.attachmentDurationMs != null && attachmentDurationMs == null) {
    errors.push("attachmentDurationMs");
  }
  if (attachmentDurationMs != null && body.hasAttachment !== true) {
    errors.push("attachmentDurationMs_requiresAttachment");
  }
  if (sharedEntityType.length > 0) {
    if (!sharedEntityTypeAllowlist.has(sharedEntityType)) {
      errors.push("sharedEntityType");
    }
    if (sharedEntityId == null) {
      errors.push("sharedEntityId");
    }
  } else if (sharedEntityId != null) {
    errors.push("sharedEntityType");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      body: text,
      replyToMessageId,
      clientMessageId:
        clientMessageId == null || clientMessageId === "__invalid__"
          ? null
          : clientMessageId,
      attachmentDurationMs,
      sharedEntity:
        sharedEntityType.length === 0 || sharedEntityId == null
          ? null
          : {
              type: sharedEntityType,
              id: sharedEntityId,
              snapshot: sharedSnapshot,
            },
    },
  };
}

export function validateScheduledThreadMessageBody(body = {}) {
  const base = validateSendMessage(body);
  const scheduledFor = asFutureDateTimeOrNull(
    body.scheduledFor ?? body.scheduled_for
  );
  const errors = [...base.errors];
  if (scheduledFor == null || scheduledFor === "__invalid__") {
    errors.push("scheduledFor");
  } else {
    const scheduledAt = new Date(scheduledFor).getTime();
    if (scheduledAt <= Date.now() + 30 * 1000) {
      errors.push("scheduledFor_future");
    }
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      ...base.value,
      scheduledFor:
        scheduledFor && scheduledFor !== "__invalid__" ? scheduledFor : null,
    },
  };
}

export function validateScheduledThreadMessageListQuery(query = {}) {
  const limit = Number(query.limit ?? 20);
  const errors = [];
  if (!Number.isInteger(limit) || limit < 1 || limit > 60) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(60, Math.max(1, Number.isInteger(limit) ? limit : 20)),
    },
  };
}

export function validateScheduledThreadMessageId(value) {
  const parsed = asPositiveInt(value);
  return {
    ok: parsed != null,
    errors: parsed == null ? ["scheduledMessageId"] : [],
    value: parsed,
  };
}

export function validateThreadMessageUpdateBody(body = {}) {
  const text = asTrimmed(body.body);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 1200) errors.push("body_length");
  return {
    ok: errors.length === 0,
    errors,
    value: { body: text },
  };
}

export function validateQualityReviewConsentBody(body = {}) {
  const raw = body.enabled ?? body.consent ?? body.chatQualityReviewConsent;
  const normalized =
    raw === true
      ? true
      : raw === false
      ? false
      : typeof raw === "string"
      ? ["true", "1", "yes", "on"].includes(raw.trim().toLowerCase())
        ? true
        : ["false", "0", "no", "off"].includes(raw.trim().toLowerCase())
        ? false
        : null
      : null;

  return {
    ok: normalized != null,
    errors: normalized == null ? ["enabled"] : [],
    value: { enabled: normalized === true },
  };
}

export function validateAdminChatMonitorListQuery(query = {}) {
  const search = asTrimmed(query.search);
  const kind = asTrimmed(query.kind).toLowerCase() || "all";
  const limit = Number(query.limit ?? 60);
  const errors = [];
  if (search.length > 120) errors.push("search");
  if (!["all", "direct", "community"].includes(kind)) errors.push("kind");
  if (!Number.isInteger(limit) || limit < 1 || limit > 150) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      kind,
      limit: Math.min(150, Math.max(1, Number.isInteger(limit) ? limit : 60)),
    },
  };
}

export function validateMessageReaction(body = {}) {
  const reaction = asTrimmed(body.reaction).toLowerCase() || "like";
  const errors = [];
  if (!["like", "heart", "laugh", "fire"].includes(reaction)) {
    errors.push("reaction");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: { reaction },
  };
}

export function validateUpdateSocialProfile(body = {}, opts = {}) {
  const errors = [];
  const hasImageUpload = opts?.hasImageUpload === true;
  const hasUsername = body.username !== undefined;
  const hasFullName =
    body.fullName !== undefined && body.fullName !== null && String(body.fullName).trim().length > 0;
  const hasBio = body.bio !== undefined && body.bio !== null;
  const hasAge = body.age !== undefined;
  const hasImageUrl =
    body.imageUrl !== undefined && body.imageUrl !== null && String(body.imageUrl).trim().length > 0;
  const hasWorkTitle = body.workTitle !== undefined;
  const hasWorkCompany = body.workCompany !== undefined;
  const hasShowPhone = body.showPhone !== undefined;
  const hasAccountPrivate = body.accountPrivate !== undefined;
  const hasPostsPublic = body.postsPublic !== undefined;
  const hasStoriesPublic = body.storiesPublic !== undefined;
  const hasRelationsPublic = body.relationsPublic !== undefined;
  const hasOnlineStatusVisibility = body.onlineStatusVisibility !== undefined;
  const hasLastSeenVisibility = body.lastSeenVisibility !== undefined;
  const hasReadReceiptsEnabled = body.readReceiptsEnabled !== undefined;
  const hasTypingIndicatorsEnabled = body.typingIndicatorsEnabled !== undefined;
  const hasPreferredLocale = body.preferredLocale !== undefined;
  const showPhone = asBooleanOrNull(body.showPhone);
  const accountPrivate = asBooleanOrNull(body.accountPrivate);
  const postsPublic = asBooleanOrNull(body.postsPublic);
  const storiesPublic = asBooleanOrNull(body.storiesPublic);
  const relationsPublic = asBooleanOrNull(body.relationsPublic);
  const onlineStatusVisibility = asSocialVisibilityOrNull(
    body.onlineStatusVisibility
  );
  const lastSeenVisibility = asSocialVisibilityOrNull(body.lastSeenVisibility);
  const readReceiptsEnabled = asBooleanOrNull(body.readReceiptsEnabled);
  const typingIndicatorsEnabled = asBooleanOrNull(body.typingIndicatorsEnabled);
  const preferredLocale = asTrimmed(body.preferredLocale).toLowerCase() || null;
  const age = asSocialAgeOrNull(body.age);

  if (
    !hasFullName &&
    !hasBio &&
    !hasAge &&
    !hasImageUrl &&
    !hasWorkTitle &&
    !hasWorkCompany &&
    !hasImageUpload &&
    !hasUsername &&
    !hasShowPhone &&
    !hasAccountPrivate &&
    !hasPostsPublic &&
    !hasStoriesPublic &&
    !hasRelationsPublic &&
    !hasOnlineStatusVisibility &&
    !hasLastSeenVisibility &&
    !hasReadReceiptsEnabled &&
    !hasTypingIndicatorsEnabled &&
    !hasPreferredLocale
  ) {
    errors.push("changes_required");
  }

  if (
    hasUsername &&
    !/^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$/.test(
      String(body.username || "").trim().toLowerCase()
    )
  ) {
    errors.push("username");
  }
  if (hasFullName && !isNonEmptyString(body.fullName, 120)) {
    errors.push("fullName");
  }

  if (hasBio && !isOptionalString(body.bio, 280)) {
    errors.push("bio");
  }
  if (hasAge && Number.isNaN(age)) {
    errors.push("age");
  }

  if (hasImageUrl && !isOptionalString(body.imageUrl, 1000)) {
    errors.push("imageUrl");
  }
  if (hasWorkTitle && !isOptionalString(body.workTitle, 160)) {
    errors.push("workTitle");
  }
  if (hasWorkCompany && !isOptionalString(body.workCompany, 180)) {
    errors.push("workCompany");
  }
  if (hasShowPhone && showPhone == null) {
    errors.push("showPhone");
  }
  if (hasAccountPrivate && accountPrivate == null) {
    errors.push("accountPrivate");
  }
  if (hasPostsPublic && postsPublic == null) {
    errors.push("postsPublic");
  }
  if (hasStoriesPublic && storiesPublic == null) {
    errors.push("storiesPublic");
  }
  if (hasRelationsPublic && relationsPublic == null) {
    errors.push("relationsPublic");
  }
  if (hasOnlineStatusVisibility && onlineStatusVisibility == null) {
    errors.push("onlineStatusVisibility");
  }
  if (hasLastSeenVisibility && lastSeenVisibility == null) {
    errors.push("lastSeenVisibility");
  }
  if (hasReadReceiptsEnabled && readReceiptsEnabled == null) {
    errors.push("readReceiptsEnabled");
  }
  if (hasTypingIndicatorsEnabled && typingIndicatorsEnabled == null) {
    errors.push("typingIndicatorsEnabled");
  }
  if (
    hasPreferredLocale &&
    preferredLocale != null &&
    !["ar", "en"].includes(preferredLocale)
  ) {
    errors.push("preferredLocale");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      username: hasUsername ? String(body.username || "").trim().toLowerCase() : undefined,
      fullName: hasFullName ? String(body.fullName).trim() : undefined,
      bio: hasBio ? String(body.bio || "").trim() : undefined,
      age: hasAge ? age : undefined,
      imageUrl: hasImageUrl ? String(body.imageUrl).trim() : undefined,
      workTitle: hasWorkTitle ? String(body.workTitle || "").trim() : undefined,
      workCompany: hasWorkCompany
        ? String(body.workCompany || "").trim()
        : undefined,
      showPhone: hasShowPhone ? showPhone : undefined,
      accountPrivate: hasAccountPrivate ? accountPrivate : undefined,
      postsPublic: hasPostsPublic ? postsPublic : undefined,
      storiesPublic: hasStoriesPublic ? storiesPublic : undefined,
      relationsPublic: hasRelationsPublic ? relationsPublic : undefined,
      onlineStatusVisibility: hasOnlineStatusVisibility
        ? onlineStatusVisibility
        : undefined,
      lastSeenVisibility: hasLastSeenVisibility ? lastSeenVisibility : undefined,
      readReceiptsEnabled: hasReadReceiptsEnabled
        ? readReceiptsEnabled
        : undefined,
      typingIndicatorsEnabled: hasTypingIndicatorsEnabled
        ? typingIndicatorsEnabled
        : undefined,
      preferredLocale: hasPreferredLocale ? preferredLocale || "ar" : undefined,
    },
  };
}

export function validateUsernameQuery(query = {}) {
  const username = asTrimmed(query.username).toLowerCase();
  const ok =
    username.length >= 4 &&
    username.length <= 24 &&
    /^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$/.test(username);
  return {
    ok,
    errors: ok ? [] : ["username"],
    value: { username },
  };
}

export function validateHighlightStory(body = {}) {
  const title = asTrimmed(body.title);
  const errors = [];
  if (title.length > 60) errors.push("title");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      title: title || null,
    },
  };
}

export function validateHighlightId(highlightId) {
  const value = asPositiveInt(highlightId);
  return {
    ok: value != null,
    errors: value == null ? ["highlightId"] : [],
    value,
  };
}

export function validateRelationListQuery(query = {}) {
  const errors = [];
  const limit = Number(query.limit ?? 80);
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(200, Math.max(1, Number.isInteger(limit) ? limit : 80)),
    },
  };
}

export function validateThreadCallStateQuery(query = {}) {
  const errors = [];
  const signalLimit = Number(query.signalLimit ?? 160);
  if (!Number.isInteger(signalLimit) || signalLimit < 1 || signalLimit > 800) {
    errors.push("signalLimit");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      signalLimit: Math.min(
        800,
        Math.max(1, Number.isInteger(signalLimit) ? signalLimit : 160)
      ),
    },
  };
}

export function validateThreadCallSignal(body = {}) {
  const errors = [];
  const sessionId =
    body.sessionId == null || body.sessionId === ""
      ? null
      : asPositiveInt(body.sessionId);
  const signalType = asTrimmed(body.signalType).toLowerCase();
  const signalPayload =
    body.signalPayload && typeof body.signalPayload === "object"
      ? body.signalPayload
      : {};
  const allowedTypes = new Set([
    "offer",
    "answer",
    "ice",
    "accept",
    "decline",
    "hangup",
  ]);

  if (body.sessionId != null && sessionId == null) errors.push("sessionId");
  if (!allowedTypes.has(signalType)) errors.push("signalType");

  if (signalType === "offer" || signalType === "answer") {
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

export function validateThreadCallEnd(body = {}) {
  const errors = [];
  const status = asTrimmed(body.status).toLowerCase() || "ended";
  const reason = asTrimmed(body.reason);
  const allowedStatus = new Set(["ended", "declined", "missed"]);
  if (!allowedStatus.has(status)) errors.push("status");
  if (reason.length > 80) errors.push("reason");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      status,
      reason: reason || null,
    },
  };
}

function normalizeCommunityScope(scopeType, scopeCode) {
  const type = asTrimmed(scopeType).toLowerCase();
  const code = asTrimmed(scopeCode).toUpperCase();

  if (!["block", "compound", "building"].includes(type)) {
    return { ok: false, errors: ["scopeType"], scopeType: null, scopeCode: null };
  }

  if (type === "block") {
    if (!/^[AB]$/.test(code)) {
      return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
    }
    return { ok: true, errors: [], scopeType: type, scopeCode: code };
  }

  if (type === "compound") {
    const match = /^([AB])([1-9])$/.exec(code);
    if (!match) {
      return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
    }
    const letter = match[1];
    const sector = Number(match[2]);
    if (letter === "B" && sector > 8) {
      return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
    }
    return { ok: true, errors: [], scopeType: type, scopeCode: code };
  }

  const building = /^([AB])([1-9])(0[1-9]|1[0-9]|2[0-2])$/.exec(code);
  if (!building) {
    return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
  }
  const letter = building[1];
  const sector = Number(building[2]);
  const buildingNo = Number(building[3]);
  if (letter === "B" && sector > 8) {
    return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
  }
  const maxForLetter = letter === "A" ? 12 : 22;
  if (buildingNo < 1 || buildingNo > maxForLetter) {
    return { ok: false, errors: ["scopeCode"], scopeType: type, scopeCode: null };
  }
  return { ok: true, errors: [], scopeType: type, scopeCode: code };
}

function validateListCursorQuery(query = {}, opts = {}) {
  const maxLimit = Math.max(1, Number(opts.maxLimit || 120));
  const defaultLimit = Math.max(1, Number(opts.defaultLimit || 40));
  const errors = [];
  const limit = Number(query.limit ?? defaultLimit);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);

  if (!Number.isInteger(limit) || limit < 1 || limit > maxLimit) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(maxLimit, Math.max(1, Number.isInteger(limit) ? limit : defaultLimit)),
      beforeId,
    },
  };
}

export function validateCommunityScopeParams(params = {}) {
  const scope = normalizeCommunityScope(
    params.scopeType ?? params.scope_type,
    params.scopeCode ?? params.scope_code
  );
  return {
    ok: scope.ok,
    errors: scope.errors,
    value: {
      scopeType: scope.scopeType,
      scopeCode: scope.scopeCode,
    },
  };
}

export function validateCommunityFeedQuery(query = {}) {
  const base = validateListPosts(query);
  if (!base.ok) return base;
  return {
    ok: true,
    errors: [],
    value: {
      ...base.value,
      limit: Math.min(50, Math.max(1, Number(base.value.limit || 20))),
    },
  };
}

export function validateCommunityAnnouncementListQuery(query = {}) {
  return validateListCursorQuery(query, { defaultLimit: 40, maxLimit: 150 });
}

export function validateCommunityAnnouncementBody(body = {}) {
  const title = asTrimmed(body.title);
  const text = asTrimmed(body.body);
  const errors = [];

  if (!title || title.length > 180) errors.push("title");
  if (!text || text.length > 2500) errors.push("body");

  return {
    ok: errors.length === 0,
    errors,
    value: { title, body: text },
  };
}

export function validateCommunityChatListQuery(query = {}) {
  return validateListCursorQuery(query, { defaultLimit: 60, maxLimit: 200 });
}

export function validateCommunityChatMessageBody(body = {}) {
  const text = asTrimmed(body.body);
  const replyToMessageId =
    body.replyToMessageId == null || body.replyToMessageId === ""
      ? null
      : asPositiveInt(body.replyToMessageId);
  const clientMessageId = asClientMessageId(
    body.clientMessageId ?? body.client_message_id
  );
  const attachmentDurationMs =
    body.attachmentDurationMs == null || body.attachmentDurationMs === ""
      ? null
      : asPositiveInt(body.attachmentDurationMs);
  const sharedEntityType = asTrimmed(
    body.sharedEntityType ??
      body.shared_entity_type ??
      body.sharedEntity?.type
  ).toLowerCase();
  const sharedEntityId = asPositiveInt(
    body.sharedEntityId ?? body.shared_entity_id ?? body.sharedEntity?.id
  );
  const sharedSnapshot =
    body.sharedEntity?.snapshot &&
    typeof body.sharedEntity.snapshot === "object" &&
    !Array.isArray(body.sharedEntity.snapshot)
      ? body.sharedEntity.snapshot
      : body.sharedSnapshot &&
          typeof body.sharedSnapshot === "object" &&
          !Array.isArray(body.sharedSnapshot)
      ? body.sharedSnapshot
      : body.shared_snapshot &&
          typeof body.shared_snapshot === "object" &&
          !Array.isArray(body.shared_snapshot)
      ? body.shared_snapshot
      : null;
  const errors = [];
  if (!text && body.hasAttachment !== true && sharedEntityId == null) {
    errors.push("body");
  }
  if (text.length > 1400) errors.push("body_length");
  if (body.replyToMessageId != null && replyToMessageId == null) {
    errors.push("replyToMessageId");
  }
  if (body.clientMessageId != null && clientMessageId == null) {
    errors.push("clientMessageId");
  }
  if (clientMessageId === "__invalid__") {
    errors.push("clientMessageId");
  }
  if (body.attachmentDurationMs != null && attachmentDurationMs == null) {
    errors.push("attachmentDurationMs");
  }
  if (attachmentDurationMs != null && body.hasAttachment !== true) {
    errors.push("attachmentDurationMs_requiresAttachment");
  }
  if (sharedEntityType.length > 0) {
    if (!sharedEntityTypeAllowlist.has(sharedEntityType)) {
      errors.push("sharedEntityType");
    }
    if (sharedEntityId == null) {
      errors.push("sharedEntityId");
    }
  } else if (sharedEntityId != null) {
    errors.push("sharedEntityType");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      body: text,
      replyToMessageId,
      clientMessageId:
        clientMessageId == null || clientMessageId === "__invalid__"
          ? null
          : clientMessageId,
      attachmentDurationMs,
      sharedEntity:
        sharedEntityType.length === 0 || sharedEntityId == null
          ? null
          : {
              type: sharedEntityType,
              id: sharedEntityId,
              snapshot: sharedSnapshot,
            },
    },
  };
}

export function validateCommunityChatMessageUpdateBody(body = {}) {
  const text = asTrimmed(body.body);
  const errors = [];
  if (!text) errors.push("body");
  if (text.length > 1400) errors.push("body_length");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      body: text,
    },
  };
}

export function validateCommunityChatLockBody(body = {}) {
  const locked = asBooleanOrNull(body.locked);
  return {
    ok: locked != null,
    errors: locked == null ? ["locked"] : [],
    value: { locked: locked === true },
  };
}

export function validateCommunityChatBanBody(body = {}) {
  const userId = asPositiveInt(body.userId ?? body.user_id);
  const reason = asTrimmed(body.reason);
  const errors = [];
  if (userId == null) errors.push("userId");
  if (reason.length > 240) errors.push("reason");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      userId,
      reason: reason || null,
    },
  };
}

export function validateCommunityBillListQuery(query = {}) {
  const paging = validateListCursorQuery(query, { defaultLimit: 60, maxLimit: 200 });
  const categoryRaw = asTrimmed(query.category).toLowerCase();
  const allowed = new Set(["electricity", "water", "other"]);
  const category =
    !categoryRaw || categoryRaw === "all"
      ? null
      : allowed.has(categoryRaw)
      ? categoryRaw
      : "__invalid__";

  if (category === "__invalid__") {
    return {
      ok: false,
      errors: [...paging.errors, "category"],
      value: null,
    };
  }

  return {
    ok: paging.ok,
    errors: paging.errors,
    value: {
      ...paging.value,
      category,
    },
  };
}

export function validateCommunityBillBody(body = {}) {
  const category = asTrimmed(body.category ?? body.billCategory).toLowerCase();
  const title = asTrimmed(body.title);
  const details = asTrimmed(body.details);
  const dueDate = asTrimmed(body.dueDate ?? body.due_date);
  const apartment = asApartmentCode(
    body.apartmentCode ?? body.apartment_code ?? body.apartment
  );
  const amount =
    body.amount == null || body.amount === "" ? null : Number(body.amount);
  const errors = [];
  const allowed = new Set(["electricity", "water", "other"]);

  if (!allowed.has(category)) errors.push("category");
  if (!title || title.length > 180) errors.push("title");
  if (details.length > 2500) errors.push("details");
  if (body.amount != null && (!Number.isFinite(amount) || amount < 0)) {
    errors.push("amount");
  }
  if (dueDate) {
    const validDate = /^\d{4}-\d{2}-\d{2}$/.test(dueDate);
    if (!validDate || Number.isNaN(new Date(dueDate).getTime())) {
      errors.push("dueDate");
    }
  }
  if (apartment === "__invalid__") {
    errors.push("apartment");
  }

  return {
    ok: errors.length === 0,
    errors,
    value: {
      category,
      title,
      details: details || null,
      amount: amount == null ? null : Number(amount.toFixed(2)),
      dueDate: dueDate || null,
      apartment: apartment && apartment !== "__invalid__" ? apartment : null,
    },
  };
}

export function validateCommunityManagerBody(body = {}) {
  const managerUserId = asPositiveInt(body.managerUserId ?? body.manager_user_id);
  return {
    ok: managerUserId != null,
    errors: managerUserId == null ? ["managerUserId"] : [],
    value: {
      managerUserId,
    },
  };
}

export function validateCommunityUserSearchQuery(query = {}) {
  const search = asTrimmed(query.search);
  const limit = Number(query.limit ?? 80);
  const errors = [];

  if (search.length > 80) errors.push("search");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) errors.push("limit");

  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      limit: Math.min(200, Math.max(1, Number.isInteger(limit) ? limit : 80)),
    },
  };
}

export function validateUserNotificationPreferenceBody(body = {}) {
  const enabled = asBooleanOrNull(body.enabled);
  return {
    ok: enabled != null,
    errors: enabled == null ? ["enabled"] : [],
    value: {
      enabled: enabled === true,
    },
  };
}

export function validateSuperAdminUserActionBody(body = {}) {
  const action = asTrimmed(body.action).toLowerCase();
  const note = asTrimmed(body.note ?? body.reason);
  const allowed = new Set([
    "disable_account",
    "enable_account",
    "promote_admin",
    "demote_user",
    "grant_block_manager",
    "revoke_block_manager",
    "grant_compound_manager",
    "revoke_compound_manager",
    "grant_building_manager",
    "revoke_building_manager",
  ]);
  const errors = [];
  if (!allowed.has(action)) errors.push("action");
  if (note.length > 600) errors.push("note");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      action,
      note: note || null,
    },
  };
}

export function validateSocialSearchQuery(query = {}) {
  const search = asTrimmed(query.search);
  const tab = asTrimmed(query.tab).toLowerCase() || "all";
  const limit = Number(query.limit ?? 12);
  const errors = [];
  if (search.length > 160) errors.push("search");
  if (!["all", "users", "posts", "reels", "hashtags", "merchants", "reviews"].includes(tab)) {
    errors.push("tab");
  }
  if (!Number.isInteger(limit) || limit < 1 || limit > 40) errors.push("limit");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      search,
      tab,
      limit: Math.min(40, Math.max(1, Number.isInteger(limit) ? limit : 12)),
    },
  };
}

export function validateSavedCollectionBody(body = {}) {
  const title = asTrimmed(body.title);
  const description = asTrimmed(body.description);
  const systemKey = asTrimmed(body.systemKey ?? body.system_key).toLowerCase();
  const errors = [];
  if (!title || title.length > 120) errors.push("title");
  if (description.length > 400) errors.push("description");
  if (systemKey && systemKey.length > 32) errors.push("systemKey");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      title,
      description: description || null,
      systemKey: systemKey || null,
    },
  };
}

export function validateSavedCollectionId(value) {
  const parsed = asPositiveInt(value);
  return {
    ok: parsed != null,
    errors: parsed == null ? ["collectionId"] : [],
    value: parsed,
  };
}

export function validateSavedToggleBody(body = {}) {
  const entityType = asTrimmed(body.entityType ?? body.entity_type).toLowerCase();
  const entityId = asPositiveInt(body.entityId ?? body.entity_id);
  const rawCollectionIds = body.collectionIds ?? body.collection_ids;
  const collectionIds = Array.isArray(rawCollectionIds)
    ? [...new Set(rawCollectionIds.map((value) => asPositiveInt(value)).filter((value) => value != null))]
    : [];
  const errors = [];
  if (!["post", "reel", "review", "video", "merchant_review"].includes(entityType)) {
    errors.push("entityType");
  }
  if (entityId == null) errors.push("entityId");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      entityType,
      entityId,
      collectionIds,
    },
  };
}

export function validateSavedListQuery(query = {}) {
  const limit = Number(query.limit ?? 24);
  const beforeId = query.beforeId == null ? null : asPositiveInt(query.beforeId);
  const collectionId =
    query.collectionId == null && query.collection_id == null
      ? null
      : asPositiveInt(query.collectionId ?? query.collection_id);
  const entityType = asTrimmed(query.entityType ?? query.entity_type).toLowerCase();
  const errors = [];
  if (!Number.isInteger(limit) || limit < 1 || limit > 60) errors.push("limit");
  if (query.beforeId != null && beforeId == null) errors.push("beforeId");
  if ((query.collectionId != null || query.collection_id != null) && collectionId == null) {
    errors.push("collectionId");
  }
  if (entityType && !["post", "reel", "review"].includes(entityType)) {
    errors.push("entityType");
  }
  return {
    ok: errors.length === 0,
    errors,
    value: {
      limit: Math.min(60, Math.max(1, Number.isInteger(limit) ? limit : 24)),
      beforeId,
      collectionId,
      entityType: entityType || null,
    },
  };
}

export function validateHashtagParam(value) {
  const tag = asTrimmed(value).replace(/^#+/, "");
  return {
    ok: !!tag && tag.length <= 80,
    errors: !tag || tag.length > 80 ? ["tag"] : [],
    value: tag,
  };
}

export function validateSimpleLimitQuery(
  query = {},
  { defaultLimit = 12, maxLimit = 40 } = {}
) {
  const limit = Number(query.limit ?? defaultLimit);
  return {
    ok: Number.isInteger(limit) && limit >= 1 && limit <= maxLimit,
    errors:
      Number.isInteger(limit) && limit >= 1 && limit <= maxLimit ? [] : ["limit"],
    value: {
      limit: Math.min(maxLimit, Math.max(1, Number.isInteger(limit) ? limit : defaultLimit)),
    },
  };
}

export function validateReelViewBody(body = {}) {
  const watchDurationMs = Number(body.watchDurationMs ?? body.watch_duration_ms ?? 0);
  const completionRate = Number(body.completionRate ?? body.completion_rate ?? 0);
  const replayCount = Number(body.replayCount ?? body.replay_count ?? 0);
  const completed = asBooleanOrNull(body.completed);
  const errors = [];
  if (!Number.isFinite(watchDurationMs) || watchDurationMs < 0) {
    errors.push("watchDurationMs");
  }
  if (!Number.isFinite(completionRate) || completionRate < 0 || completionRate > 100) {
    errors.push("completionRate");
  }
  if (!Number.isFinite(replayCount) || replayCount < 0) {
    errors.push("replayCount");
  }
  if (body.completed != null && completed == null) errors.push("completed");
  return {
    ok: errors.length === 0,
    errors,
    value: {
      watchDurationMs: Math.max(0, Math.trunc(watchDurationMs || 0)),
      completionRate: Math.max(0, Math.min(100, Number(completionRate || 0))),
      replayCount: Math.max(0, Math.trunc(replayCount || 0)),
      completed: completed === true,
      context: asTrimmed(body.context).toLowerCase() || "reel_viewer",
    },
  };
}

export function validateThreadTypingBody(body = {}) {
  const typing = asBooleanOrNull(body.typing);
  return {
    ok: typing != null,
    errors: typing == null ? ["typing"] : [],
    value: { typing: typing === true },
  };
}

export function validateThreadMuteBody(body = {}) {
  const enabled = asBooleanOrNull(body.enabled ?? body.muted);
  return {
    ok: enabled != null,
    errors: enabled == null ? ["enabled"] : [],
    value: { enabled: enabled === true },
  };
}

export function validateThreadPinBody(body = {}) {
  const enabled = asBooleanOrNull(body.enabled ?? body.pinned);
  return {
    ok: enabled != null,
    errors: enabled == null ? ["enabled"] : [],
    value: { enabled: enabled === true },
  };
}

export function validateThreadThemeBody(body = {}) {
  const themeKey = asTrimmed(body.themeKey ?? body.theme_key).toLowerCase();
  const allowed = new Set([
    "default",
    "sunset",
    "ocean",
    "forest",
    "violet",
  ]);
  return {
    ok: allowed.has(themeKey),
    errors: allowed.has(themeKey) ? [] : ["themeKey"],
    value: { themeKey: allowed.has(themeKey) ? themeKey : "default" },
  };
}

export function validateTranslateThreadMessageBody(body = {}) {
  const targetLanguage = asTrimmed(
    body.targetLanguage ?? body.target_language ?? body.language
  ).toLowerCase();
  const refresh = asBooleanOrNull(body.refresh);
  const validLanguage =
    /^[a-z]{2,8}(?:-[a-z]{2,8})?$/.test(targetLanguage) && targetLanguage.length <= 12;
  return {
    ok: validLanguage,
    errors: validLanguage ? [] : ["targetLanguage"],
    value: {
      targetLanguage: validLanguage ? targetLanguage : null,
      refresh: refresh === true,
    },
  };
}
