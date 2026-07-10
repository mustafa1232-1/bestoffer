const SNAPSHOT_VERSION = 1;

function asText(value, maxLength = 240) {
  if (value === undefined || value === null) return null;
  const out = String(value).trim();
  if (!out) return null;
  return out.length > maxLength ? out.slice(0, maxLength).trim() : out;
}

function asNumber(value, fallback = 0) {
  if (value === undefined || value === null || value === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function asInt(value, fallback = null) {
  if (value === undefined || value === null || value === "") return fallback;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : fallback;
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (value === undefined || value === null || value === "") return [];
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

function asObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value;
}

function normalizeEntry(input) {
  const source = asObject(input) || {};
  const label = asText(
    source.label ??
      source.labelAr ??
      source.label_ar ??
      source.groupLabel ??
      source.group_label ??
      source.optionLabel ??
      source.option_label ??
      source.title ??
      source.name ??
      source.code ??
      source.key,
    160
  );
  const value = asText(
    source.value ??
      source.valueText ??
      source.value_text ??
      source.optionLabel ??
      source.option_label ??
      source.optionCode ??
      source.option_code ??
      source.code ??
      source.text ??
      source.description,
    240
  );
  const hex = asText(source.hex ?? source.swatchHex ?? source.swatch_hex, 32);
  const entry = {
    label: label || value || null,
    value: value || label || null,
  };
  if (hex) {
    entry.hex = hex;
  }
  return Object.values(entry).some((item) => item != null) ? entry : null;
}

function normalizeEntryList(value) {
  return asArray(value)
    .map((entry) => normalizeEntry(entry))
    .filter(Boolean);
}

function normalizeChoice(input, { includeHex = false } = {}) {
  const normalized = normalizeEntry(input);
  if (!normalized) return null;
  const out = {
    label: normalized.label,
    value: normalized.value,
  };
  if (includeHex) {
    out.hex = normalized.hex || null;
  }
  return out;
}

function normalizeModifierLists(value) {
  const entries = asArray(value)
    .map((entry) => asObject(entry))
    .filter(Boolean);
  const options = [];
  const addons = [];
  const removals = [];

  for (const entry of entries) {
    const normalized = normalizeEntry(entry);
    if (!normalized) continue;
    options.push(normalized);

    const kind = asText(entry.kind ?? entry.type, 32)?.toLowerCase();
    const isRemoval =
      entry.isRemoval === true ||
      entry.removed === true ||
      kind === "removal" ||
      kind === "remove" ||
      Number(entry.quantity || 0) < 0;
    if (isRemoval) {
      removals.push(normalized);
      continue;
    }

    const isAddon =
      entry.isAddon === true ||
      entry.addon === true ||
      kind === "addon" ||
      kind === "add_on" ||
      Number(entry.priceDelta ?? entry.price_delta ?? entry.price ?? 0) > 0;
    if (isAddon) {
      addons.push(normalized);
    }
  }

  return { options, addons, removals };
}

function deriveVariantName({
  variantName,
  selectedColor,
  selectedSize,
  specs,
  variantSku,
}) {
  const explicit = asText(variantName, 240);
  if (explicit) return explicit;
  const pieces = [];
  const push = (value) => {
    const text = asText(value, 120);
    if (text && !pieces.includes(text)) pieces.push(text);
  };
  push(selectedColor?.value);
  push(selectedSize?.value);
  for (const entry of asArray(specs)) {
    const normalized = normalizeEntry(entry);
    if (normalized?.value) push(normalized.value);
  }
  if (pieces.length) return pieces.join(" / ");
  return asText(variantSku, 120);
}

export function buildOrderItemDisplaySnapshot(input = {}) {
  const selectedColor = normalizeChoice(input.selectedColor, {
    includeHex: true,
  });
  const selectedSize = normalizeChoice(input.selectedSize);
  const specs = normalizeEntryList(input.specs);
  const options = normalizeEntryList(input.options);
  const addons = normalizeEntryList(input.addons);
  const removals = normalizeEntryList(input.removals);
  const normalizedSpecs = specs.length ? specs : [selectedColor, selectedSize].filter(Boolean);

  return {
    version: SNAPSHOT_VERSION,
    productId: asInt(input.productId, null),
    productName: asText(input.productName, 240),
    productImageUrl: asText(input.productImageUrl, 1000),
    thumbnailUrl:
      asText(input.thumbnailUrl, 1000) || asText(input.productImageUrl, 1000),
    sku: asText(input.sku ?? input.variantSku, 160),
    variantId: asInt(input.variantId, null),
    variantName: deriveVariantName({
      variantName: input.variantName,
      selectedColor,
      selectedSize,
      specs: normalizedSpecs,
      variantSku: input.variantSku,
    }),
    variantSku: asText(input.variantSku, 160),
    quantity: Math.max(0, Math.trunc(asNumber(input.quantity, 0))),
    unitPrice: asNumber(input.unitPrice, 0),
    lineTotal: asNumber(input.lineTotal, 0),
    currency: asText(input.currency, 16) || "IQD",
    selectedColor,
    selectedSize,
    specs: normalizedSpecs,
    options,
    addons,
    removals,
    userNote: asText(input.userNote, 1000),
    activityType: asText(input.activityType, 80),
    storeId: asInt(input.storeId, null),
    storeName: asText(input.storeName, 240),
  };
}

function readMaybeSnapshot(value) {
  if (value == null || value === "") return null;
  if (typeof value === "string") {
    try {
      return JSON.parse(value);
    } catch (_) {
      return null;
    }
  }
  return asObject(value);
}

function selectionListFromSnapshot(snapshot) {
  const specs = normalizeEntryList(snapshot?.specs);
  if (specs.length) return specs;
  const color = normalizeChoice(snapshot?.selectedColor, { includeHex: true });
  const size = normalizeChoice(snapshot?.selectedSize);
  return [color, size].filter(Boolean);
}

function findSelectionByGroup(entries, groupName) {
  const normalizedGroup = String(groupName || "").trim().toLowerCase();
  if (!normalizedGroup) return null;
  return (
    asArray(entries).find((entry) => {
      const label = String(entry?.label || "").trim().toLowerCase();
      const value = String(entry?.value || "").trim().toLowerCase();
      return label.includes(normalizedGroup) || value.includes(normalizedGroup);
    }) || null
  );
}

function buildFallbackSnapshot(row = {}, order = null) {
  const snapshotSource = asObject(
    row.display_snapshot_json ?? row.displaySnapshotJson ?? row.display_snapshot
  );
  const selectedVariant = asObject(
    row.selected_variant_json ?? row.selectedVariant ?? snapshotSource?.selectedVariant
  ) || null;
  const selectedVariantOptions = asArray(
    row.selected_variant_options_json ??
      row.selectedVariantOptions ??
      row.selectedVariantSelections ??
      selectedVariant?.selections
  );
  const selectedModifiers = asArray(
    row.selected_modifiers_json ?? row.selectedModifiers
  );
  const pricingBreakdown = asObject(
    row.pricing_breakdown_json ?? row.pricingBreakdown
  ) || null;
  const sourceSelections = selectionListFromSnapshot(snapshotSource);
  const variantSelections =
    selectedVariantOptions.length > 0 ? selectedVariantOptions : sourceSelections;
  const colorSelection =
    findSelectionByGroup(variantSelections, "color") ||
    findSelectionByGroup(variantSelections, "لون") ||
    null;
  const sizeSelection =
    findSelectionByGroup(variantSelections, "size") ||
    findSelectionByGroup(variantSelections, "مقاس") ||
    null;
  const modifierLists = normalizeModifierLists(selectedModifiers);
  const orderInfo = asObject(order) || {};
  const selectedColor = snapshotSource?.selectedColor
    ? normalizeChoice(snapshotSource.selectedColor, { includeHex: true })
    : colorSelection
      ? normalizeChoice(colorSelection, { includeHex: true })
      : selectedVariant?.colorLabel
        ? {
            label: asText(selectedVariant.colorLabel, 160),
            value: asText(selectedVariant.colorLabel, 160),
            hex: asText(selectedVariant.colorHex, 32),
          }
        : null;
  const selectedSize = snapshotSource?.selectedSize
    ? normalizeChoice(snapshotSource.selectedSize)
    : sizeSelection
      ? normalizeChoice(sizeSelection)
      : selectedVariant?.sizeLabel
        ? {
            label: asText(selectedVariant.sizeLabel, 160),
            value: asText(selectedVariant.sizeLabel, 160),
          }
        : null;
  const specs = variantSelections.length
    ? variantSelections.map((entry) => normalizeEntry(entry)).filter(Boolean)
    : sourceSelections;

  return buildOrderItemDisplaySnapshot({
    productId:
      row.product_id ??
      row.productId ??
      snapshotSource?.productId ??
      orderInfo.product_id ??
      null,
    productName:
      row.product_name ??
      row.productName ??
      snapshotSource?.productName ??
      null,
    productImageUrl:
      snapshotSource?.productImageUrl ??
      row.product_image_url ??
      row.productImageUrl ??
      selectedVariant?.imageUrl ??
      pricingBreakdown?.selectedVariantSnapshot?.imageUrl ??
      null,
    thumbnailUrl:
      snapshotSource?.thumbnailUrl ??
      row.thumbnail_url ??
      row.thumbnailUrl ??
      selectedVariant?.imageUrl ??
      pricingBreakdown?.selectedVariantSnapshot?.imageUrl ??
      null,
    sku:
      snapshotSource?.sku ??
      row.sku ??
      selectedVariant?.sku ??
      pricingBreakdown?.selectedVariantSnapshot?.sku ??
      null,
    variantId:
      snapshotSource?.variantId ??
      row.variant_id ??
      row.variantId ??
      selectedVariant?.variantId ??
      null,
    variantName:
      snapshotSource?.variantName ??
      selectedVariant?.variantName ??
      selectedVariant?.signature ??
      null,
    variantSku:
      snapshotSource?.variantSku ??
      selectedVariant?.sku ??
      pricingBreakdown?.selectedVariantSnapshot?.sku ??
      null,
    quantity:
      snapshotSource?.quantity ??
      row.quantity ??
      0,
    unitPrice:
      snapshotSource?.unitPrice ??
      row.unit_price ??
      row.unitPrice ??
      0,
    lineTotal:
      snapshotSource?.lineTotal ??
      row.line_total ??
      row.lineTotal ??
      0,
    currency: snapshotSource?.currency ?? "IQD",
    selectedColor,
    selectedSize,
    specs,
    options: snapshotSource?.options ?? modifierLists.options,
    addons: snapshotSource?.addons ?? modifierLists.addons,
    removals: snapshotSource?.removals ?? modifierLists.removals,
    userNote:
      snapshotSource?.userNote ??
      row.user_note ??
      row.userNote ??
      null,
    activityType:
      snapshotSource?.activityType ??
      orderInfo.merchant_activity_type ??
      orderInfo.activity_type ??
      orderInfo.activityType ??
      null,
    storeId:
      snapshotSource?.storeId ??
      orderInfo.merchant_id ??
      orderInfo.store_id ??
      orderInfo.storeId ??
      null,
    storeName:
      snapshotSource?.storeName ??
      orderInfo.merchant_name ??
      orderInfo.store_name ??
      orderInfo.storeName ??
      null,
  });
}

function normalizeStoredSnapshot(row) {
  const snapshot = readMaybeSnapshot(
    row?.display_snapshot_json ?? row?.displaySnapshotJson ?? row?.display_snapshot
  );
  if (!snapshot) return null;
  return buildOrderItemDisplaySnapshot(snapshot);
}

export function hydrateOrderItemDisplaySnapshot(row, order = null) {
  if (!row || typeof row !== "object") return row;
  const displaySnapshot = normalizeStoredSnapshot(row) || buildFallbackSnapshot(row, order);
  return {
    ...row,
    display_snapshot_json: displaySnapshot,
    display_snapshot: displaySnapshot,
    displaySnapshot,
  };
}

export { SNAPSHOT_VERSION as ORDER_ITEM_DISPLAY_SNAPSHOT_VERSION };
