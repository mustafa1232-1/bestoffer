function parseJsonMaybe(value, fallback = null) {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value === "object") return value;
  if (typeof value !== "string") return fallback;
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function normalizeText(value, maxLength = 200) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  if (!out) return null;
  return out.length > maxLength ? out.slice(0, maxLength).trim() : out;
}

function normalizeBool(value, fallback = false) {
  if (value === true || value === false) return value;
  if (typeof value !== "string") return fallback;
  const normalized = value.trim().toLowerCase();
  if (["true", "1", "yes", "y", "on"].includes(normalized)) return true;
  if (["false", "0", "no", "n", "off"].includes(normalized)) return false;
  return fallback;
}

function normalizeNumber(value, fallback = 0) {
  if (value === undefined || value === null || value === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizePositiveInt(value, fallback = null) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function normalizeOptionalNumber(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeArray(value) {
  if (Array.isArray(value)) return value;
  const parsed = parseJsonMaybe(value, null);
  return Array.isArray(parsed) ? parsed : [];
}

function normalizeObject(value) {
  const parsed = parseJsonMaybe(value, null);
  return parsed && typeof parsed === "object" && !Array.isArray(parsed)
    ? parsed
    : {};
}

function canonicalAttributeCode(code) {
  return normalizeText(code, 80)?.toLowerCase().replace(/\s+/g, "_") || null;
}

function attributeDisplayLabel(code, labelAr, labelEn) {
  const normalized = canonicalAttributeCode(code);
  if (labelAr || labelEn) return { labelAr, labelEn };
  switch (normalized) {
    case "brand":
      return { labelAr: "العلامة التجارية", labelEn: "Brand" };
    case "warranty":
      return { labelAr: "الضمان", labelEn: "Warranty" };
    case "dimensions":
      return { labelAr: "الأبعاد", labelEn: "Dimensions" };
    case "material":
      return { labelAr: "الخامة", labelEn: "Material" };
    case "pack_size":
      return { labelAr: "حجم العبوة", labelEn: "Pack size" };
    case "color":
      return { labelAr: "اللون", labelEn: "Color" };
    case "size":
      return { labelAr: "المقاس", labelEn: "Size" };
    default:
      return { labelAr: "تفصيل", labelEn: "Detail" };
  }
}

function normalizeAttributeInput(input, index = 0) {
  const source = normalizeObject(input);
  const code = canonicalAttributeCode(
    source.code ?? source.attributeCode ?? source.key ?? source.name
  ) || `attr_${index + 1}`;
  const labels = attributeDisplayLabel(
    code,
    normalizeText(source.labelAr ?? source.label_ar, 120),
    normalizeText(source.labelEn ?? source.label_en, 120)
  );
  const valueText = normalizeText(
    source.valueText ?? source.value_text ?? source.value ?? source.text,
    240
  );
  if (!valueText) return null;
  return {
    code,
    labelAr: labels.labelAr,
    labelEn: labels.labelEn,
    valueText,
    valueUnit: normalizeText(source.valueUnit ?? source.value_unit, 40),
    showInCard: normalizeBool(source.showInCard ?? source.show_in_card, false),
    showInDetails: normalizeBool(
      source.showInDetails ?? source.show_in_details,
      true
    ),
    sortOrder: Number.isInteger(Number(source.sortOrder ?? source.sort_order))
      ? Number(source.sortOrder ?? source.sort_order)
      : index,
    metadata:
      source.metadata && typeof source.metadata === "object"
        ? source.metadata
        : source.metadata_json && typeof source.metadata_json === "object"
          ? source.metadata_json
          : {},
  };
}

function normalizeVariantOptionInput(input, index = 0) {
  const source = normalizeObject(input);
  const code = canonicalAttributeCode(
    source.code ?? source.optionCode ?? source.valueCode ?? source.name
  ) || `option_${index + 1}`;
  const labelAr = normalizeText(source.labelAr ?? source.label_ar, 120);
  const labelEn = normalizeText(source.labelEn ?? source.label_en, 120);
  const displayLabel =
    labelAr || labelEn || normalizeText(source.label ?? source.valueText, 120);
  if (!displayLabel) return null;
  return {
    code,
    labelAr: labelAr || displayLabel,
    labelEn: labelEn || displayLabel,
    swatchHex: normalizeText(
      source.swatchHex ?? source.swatch_hex ?? source.colorHex,
      16
    ),
    priceDelta: normalizeOptionalNumber(
      source.priceDelta ?? source.price_delta ?? 0
    ) || 0,
    imageUrl: normalizeText(source.imageUrl ?? source.image_url, 1000),
    isAvailable: normalizeBool(source.isAvailable ?? source.is_available, true),
    sortOrder: Number.isInteger(Number(source.sortOrder ?? source.sort_order))
      ? Number(source.sortOrder ?? source.sort_order)
      : index,
    metadata:
      source.metadata && typeof source.metadata === "object"
        ? source.metadata
        : source.metadata_json && typeof source.metadata_json === "object"
          ? source.metadata_json
          : {},
  };
}

function normalizeVariantGroupInput(input, index = 0) {
  const source = normalizeObject(input);
  const code = canonicalAttributeCode(
    source.code ?? source.groupCode ?? source.variantGroupCode ?? source.name
  ) || `group_${index + 1}`;
  const labelAr = normalizeText(source.labelAr ?? source.label_ar, 120);
  const labelEn = normalizeText(source.labelEn ?? source.label_en, 120);
  const displayLabel =
    labelAr || labelEn || normalizeText(source.label ?? source.title, 120);
  if (!displayLabel) return null;
  const options = normalizeArray(source.options ?? source.values).map((option, i) =>
    normalizeVariantOptionInput(option, i)
  ).filter(Boolean);
  if (!options.length) return null;
  return {
    code,
    labelAr: labelAr || displayLabel,
    labelEn: labelEn || displayLabel,
    displayMode: normalizeText(
      source.displayMode ?? source.display_mode ?? "chips",
      32
    ) || "chips",
    selectionMode: normalizeText(
      source.selectionMode ?? source.selection_mode ?? "single",
      32
    ) || "single",
    required: normalizeBool(source.required, true),
    sortOrder: Number.isInteger(Number(source.sortOrder ?? source.sort_order))
      ? Number(source.sortOrder ?? source.sort_order)
      : index,
    metadata:
      source.metadata && typeof source.metadata === "object"
        ? source.metadata
        : source.metadata_json && typeof source.metadata_json === "object"
          ? source.metadata_json
          : {},
    options,
  };
}

function normalizeMediaInput(input, index = 0) {
  const source = normalizeObject(input);
  const imageUrl = normalizeText(source.imageUrl ?? source.image_url, 1000);
  if (!imageUrl) return null;
  return {
    imageUrl,
    altText: normalizeText(source.altText ?? source.alt_text, 180),
    isPrimary: normalizeBool(source.isPrimary ?? source.is_primary, index === 0),
    sortOrder: Number.isInteger(Number(source.sortOrder ?? source.sort_order))
      ? Number(source.sortOrder ?? source.sort_order)
      : index,
    variantGroupCode: normalizeText(
      source.variantGroupCode ?? source.variant_group_code,
      80
    ),
    variantOptionCode: normalizeText(
      source.variantOptionCode ?? source.variant_option_code,
      80
    ),
    metadata:
      source.metadata && typeof source.metadata === "object"
        ? source.metadata
        : source.metadata_json && typeof source.metadata_json === "object"
          ? source.metadata_json
          : {},
  };
}

function collectLegacyAttributeValues(body) {
  const attrs = [];
  const push = (code, labelAr, labelEn, value, options = {}) => {
    const normalized = normalizeText(value, 240);
    if (!normalized) return;
    attrs.push({
      code,
      labelAr,
      labelEn,
      valueText: normalized,
      valueUnit: normalizeText(options.valueUnit, 40),
      showInCard: options.showInCard === true,
      showInDetails: options.showInDetails !== false,
      sortOrder: options.sortOrder ?? attrs.length,
      metadata: options.metadata || {},
    });
  };

  push("brand", "العلامة التجارية", "Brand", body.brand, { showInCard: true });
  push("warranty", "الضمان", "Warranty", body.warranty, { showInCard: true });
  push("dimensions", "الأبعاد", "Dimensions", body.dimensions, {
    showInCard: true,
  });
  push("material", "الخامة", "Material", body.material, { showInCard: true });
  push("pack_size", "حجم العبوة", "Pack size", body.packSize, {
    showInCard: true,
  });
  push("color", "اللون", "Color", body.color, { showInCard: true });
  push("size", "المقاس", "Size", body.size, { showInCard: true });
  push("origin", "بلد المنشأ", "Origin", body.origin);
  push("weight", "الوزن", "Weight", body.weight);
  push("capacity", "السعة", "Capacity", body.capacity);
  push("voltage", "الجهد الكهربائي", "Voltage", body.voltage);
  push("memory", "الذاكرة", "Memory", body.memory);
  return attrs;
}

export function normalizeRichProductPayload(body = {}) {
  const richSource =
    body.richCatalog && typeof body.richCatalog === "object"
      ? body.richCatalog
      : {};
  const rawAttributes = normalizeArray(
    body.attributes ??
      body.summaryAttributes ??
      richSource.attributes ??
      richSource.summaryAttributes
  );
  const rawVariantGroups = normalizeArray(
    body.variantGroups ?? richSource.variantGroups
  );
  const rawMedia = normalizeArray(body.media ?? richSource.media);

  const attributes = [
    ...collectLegacyAttributeValues(body),
    ...rawAttributes.map((item, index) => normalizeAttributeInput(item, index)),
  ].filter(Boolean);

  const variantGroups = rawVariantGroups
    .map((item, index) => normalizeVariantGroupInput(item, index))
    .filter(Boolean);

  const media = rawMedia.map((item, index) => normalizeMediaInput(item, index)).filter(Boolean);

  return {
    attributes,
    variantGroups,
    media,
    metadata:
      body.metadataJson && typeof body.metadataJson === "object"
        ? body.metadataJson
        : richSource.metadata && typeof richSource.metadata === "object"
          ? richSource.metadata
          : {},
  };
}

export function hasRichProductInput(body = {}) {
  const keys = [
    "attributes",
    "summaryAttributes",
    "variantGroups",
    "media",
    "richCatalog",
    "metadataJson",
    "metadata_json",
    "brand",
    "warranty",
    "dimensions",
    "material",
    "packSize",
    "pack_size",
    "color",
    "size",
    "origin",
    "weight",
    "capacity",
    "voltage",
    "memory",
    "storage",
    "display",
    "processor",
    "battery",
    "model",
  ];
  return keys.some((key) => body[key] !== undefined && body[key] !== null);
}

export function validateRichProductPayload(body = {}) {
  const errors = [];
  const rich = normalizeRichProductPayload(body);
  if (Array.isArray(body.attributes) && body.attributes.length > 60) {
    errors.push("attributes");
  }
  if (Array.isArray(body.variantGroups) && body.variantGroups.length > 12) {
    errors.push("variantGroups");
  }
  if (Array.isArray(body.media) && body.media.length > 30) {
    errors.push("media");
  }
  for (const attr of rich.attributes) {
    if (!attr.code) errors.push("attributes.code");
    if (!attr.valueText) errors.push("attributes.valueText");
  }
  for (const group of rich.variantGroups) {
    if (!group.code) errors.push("variantGroups.code");
    if (!Array.isArray(group.options) || group.options.length === 0) {
      errors.push("variantGroups.options");
    }
    for (const option of group.options) {
      if (!option.code) errors.push("variantGroups.options.code");
      if (!option.labelAr && !option.labelEn) {
        errors.push("variantGroups.options.label");
      }
    }
  }
  for (const media of rich.media) {
    if (!media.imageUrl) errors.push("media.imageUrl");
  }
  return { ok: errors.length === 0, errors };
}

export function buildProductMetadataSnapshot(body = {}) {
  const rich = normalizeRichProductPayload(body);
  return {
    richCatalog: {
      attributes: rich.attributes,
      variantGroups: rich.variantGroups,
      media: rich.media,
    },
    richCatalogVersion: 1,
    updatedAt: new Date().toISOString(),
    compatibility: normalizeObject(rich.metadata),
  };
}

export function normalizeVariantSelectionInput(input = {}) {
  const source = Array.isArray(input)
    ? { selections: input }
    : normalizeObject(input);
  const rawSelections = normalizeArray(
    source.selections ??
      source.options ??
      source.items ??
      source.values ??
      source.selectedOptions
  );

  const selections = rawSelections
    .map((item, index) => {
      const entry = normalizeObject(item);
      const groupCode = canonicalAttributeCode(
        entry.groupCode ??
          entry.variantGroupCode ??
          entry.variant_group_code ??
          entry.code ??
          entry.name ??
          entry.group
      ) || `group_${index + 1}`;
      const optionCode = canonicalAttributeCode(
        entry.optionCode ??
          entry.variantOptionCode ??
          entry.variant_option_code ??
          entry.valueCode ??
          entry.selectedOptionCode ??
          entry.option ??
          entry.value
      ) || `option_${index + 1}`;
      const optionLabel =
        normalizeText(
          entry.optionLabel ??
            entry.variantOptionLabel ??
            entry.variant_option_label ??
            entry.label ??
            entry.valueText,
          160
        ) || optionCode;
      const groupLabel =
        normalizeText(
          entry.groupLabel ??
            entry.variantGroupLabel ??
            entry.variant_group_label ??
            entry.groupName ??
            entry.name,
          160
        ) || groupCode;
      return {
        groupCode,
        groupLabel,
        optionCode,
        optionLabel,
        swatchHex: normalizeText(entry.swatchHex ?? entry.swatch_hex, 16),
        imageUrl: normalizeText(entry.imageUrl ?? entry.image_url, 1000),
        priceDelta:
          normalizeOptionalNumber(entry.priceDelta ?? entry.price_delta) || 0,
        optionId: normalizePositiveInt(
          entry.optionId ?? entry.option_id ?? entry.id
        ),
      };
    })
    .filter((item) => item.groupCode && item.optionCode);

  const signature = selections
    .slice()
    .sort((a, b) => {
      const groupDiff = a.groupCode.localeCompare(b.groupCode);
      if (groupDiff !== 0) return groupDiff;
      return a.optionCode.localeCompare(b.optionCode);
    })
    .map(
      (item) =>
        `${item.groupCode}:${item.optionCode}:${Number(item.priceDelta || 0).toFixed(2)}`
    )
    .join("|");

  const priceDeltaTotal = selections.reduce(
    (sum, item) => sum + Number(item.priceDelta || 0),
    0
  );

  return {
    selections,
    signature,
    priceDeltaTotal,
    hasSelections: selections.length > 0,
    groupCodes: selections.map((item) => item.groupCode),
    optionCodes: selections.map((item) => item.optionCode),
    optionIds: selections.map((item) => item.optionId).filter((value) => value != null),
  };
}

export function extractRichCatalogFromMetadata(metadataJson) {
  const metadata = normalizeObject(metadataJson);
  const richCatalog = normalizeObject(metadata.richCatalog);
  const attributes = normalizeArray(richCatalog.attributes).map((item, index) =>
    normalizeAttributeInput(item, index)
  ).filter(Boolean);
  const variantGroups = normalizeArray(richCatalog.variantGroups).map((item, index) =>
    normalizeVariantGroupInput(item, index)
  ).filter(Boolean);
  const media = normalizeArray(richCatalog.media).map((item, index) =>
    normalizeMediaInput(item, index)
  ).filter(Boolean);
  return {
    attributes,
    variantGroups,
    media,
  };
}

export function buildProductSnapshotFromRow(row, catalog = {}) {
  const snapshot = normalizeProductSnapshotRow(row, catalog);
  return {
    ...row,
    ...snapshot,
    imageUrl: snapshot.primaryMedia?.imageUrl || row?.image_url || row?.imageUrl || null,
    summaryAttributes: snapshot.highlights,
  };
}

export function normalizeProductSnapshotRow(row, catalog = {}) {
  const metadata = normalizeObject(row?.metadata_json);
  const metadataFallback = extractRichCatalogFromMetadata(metadata);
  const attributes = (catalog.attributes || metadataFallback.attributes || []).map(
    (item, index) => normalizeAttributeInput(item, index)
  ).filter(Boolean);
  const variantGroups = (catalog.variantGroups || metadataFallback.variantGroups || []).map(
    (item, index) => normalizeVariantGroupInput(item, index)
  ).filter(Boolean);
  const media = (catalog.media || metadataFallback.media || []).map(
    (item, index) => normalizeMediaInput(item, index)
  ).filter(Boolean);
  const primaryMedia = media.find((item) => item.isPrimary) || media[0] || null;
  return {
    attributes,
    variantGroups,
    media,
    primaryMedia,
    metadata,
    hasVariants: variantGroups.length > 0,
    highlights: attributes.filter((attr) => attr.showInCard).slice(0, 5),
  };
}

export {
  canonicalAttributeCode,
  normalizeArray,
  normalizeBool,
  normalizeAttributeInput,
  normalizeMediaInput,
  normalizeObject,
  normalizeOptionalNumber,
  normalizePositiveInt,
  normalizeVariantGroupInput,
  normalizeVariantOptionInput,
  normalizeText,
  parseJsonMaybe,
};
