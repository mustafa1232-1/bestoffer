import { pool, q } from "../../config/db.js";
import {
  buildProductMetadataSnapshot,
  buildProductSnapshotFromRow,
  extractRichCatalogFromMetadata,
  hasRichProductInput,
  normalizeArray,
  normalizeAttributeInput,
  normalizeMediaInput,
  normalizeRichProductPayload,
  normalizeVariantGroupInput,
  normalizeVariantInput,
  normalizeText,
  normalizeObject,
} from "./product-catalog.logic.js";

function toRichProductBaseRow(row) {
  if (!row) return null;
  return {
    ...row,
    id: Number(row.id),
    merchant_id: Number(row.merchant_id),
    category_id: row.category_id == null ? null : Number(row.category_id),
    category_sort_order:
      row.category_sort_order == null ? null : Number(row.category_sort_order),
    price: Number(row.price || 0),
    discounted_price:
      row.discounted_price == null ? null : Number(row.discounted_price),
    free_delivery: row.free_delivery === true,
    requires_prescription: row.requires_prescription === true,
    requires_review: row.requires_review === true,
    is_available: row.is_available !== false,
    sort_order: Number(row.sort_order || 0),
  };
}

async function loadProductCatalogByProductIdTx(client, productId) {
  return loadProductCatalogByProductIdsTx(client, [Number(productId)]);
}

async function loadProductCatalogByProductIdsTx(client, productIds) {
  const normalizedIds = Array.from(
    new Set(
      (productIds || [])
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    )
  );
  if (!normalizedIds.length) return new Map();

  // نفس pg client داخل transaction: الاستعلامات تنفذ تسلسلياً بشكل صريح.
  // Promise.all على client واحد يطلق تحذير deprecation في pg ويخفي ترتيب التنفيذ.
  const attributesResult = await client.query(
    `SELECT
       id,
       product_id,
       attribute_code,
       label_ar,
       label_en,
       value_text,
       value_unit,
       show_in_card,
       show_in_details,
       sort_order,
       metadata_json
     FROM product_attribute
     WHERE product_id = ANY($1::bigint[])
     ORDER BY sort_order ASC, id ASC`,
    [normalizedIds]
  );
  const groupsResult = await client.query(
      `SELECT
         g.id AS group_id,
         g.product_id,
         g.group_code,
         g.label_ar AS group_label_ar,
         g.label_en AS group_label_en,
         g.display_mode,
         g.selection_mode,
         g.required,
         g.sort_order AS group_sort_order,
         g.metadata_json AS group_metadata_json,
         o.id AS option_id,
         o.option_code,
         o.label_ar AS option_label_ar,
         o.label_en AS option_label_en,
         o.swatch_hex,
         o.price_delta,
         o.image_url,
         o.is_available,
         o.sort_order AS option_sort_order,
         o.metadata_json AS option_metadata_json
       FROM product_variant_group g
       LEFT JOIN product_variant_option o
         ON o.group_id = g.id
       WHERE g.product_id = ANY($1::bigint[])
       ORDER BY g.sort_order ASC, g.id ASC, o.sort_order ASC, o.id ASC`,
    [normalizedIds]
  );
  const mediaResult = await client.query(
    `SELECT
       id,
       product_id,
       image_url,
       alt_text,
       is_primary,
       sort_order,
       variant_group_code,
       variant_option_code,
       metadata_json
     FROM product_media
     WHERE product_id = ANY($1::bigint[])
     ORDER BY is_primary DESC, sort_order ASC, id ASC`,
    [normalizedIds]
  );
  const variantsResult = await client.query(
    `SELECT id, product_id, selections_json, sku, barcode, material,
            price_override, discounted_price_override, stock_quantity,
            image_url, is_available, sort_order, metadata_json
     FROM product_variant
     WHERE product_id = ANY($1::bigint[])
     ORDER BY sort_order ASC, id ASC`,
    [normalizedIds]
  );
  const catalogByProductId = new Map();
  for (const row of attributesResult.rows) {
    const productId = Number(row.product_id);
    let catalog = catalogByProductId.get(productId);
    if (!catalog) {
      catalog = { attributes: [], variantGroups: [], variants: [], media: [] };
      catalogByProductId.set(productId, catalog);
    }
    const attrIndex = catalog.attributes.length;
    const attr = normalizeAttributeInput(
      {
        code: row.attribute_code,
        labelAr: row.label_ar,
        labelEn: row.label_en,
        valueText: row.value_text,
        valueUnit: row.value_unit,
        showInCard: row.show_in_card === true,
        showInDetails: row.show_in_details !== false,
        sortOrder: row.sort_order ?? attrIndex,
        metadata: row.metadata_json || {},
      },
      attrIndex
    );
    if (attr) catalog.attributes.push(attr);
  }

  const grouped = new Map();
  for (const row of groupsResult.rows) {
    const productId = Number(row.product_id);
    let catalog = catalogByProductId.get(productId);
    if (!catalog) {
      catalog = { attributes: [], variantGroups: [], variants: [], media: [] };
      catalogByProductId.set(productId, catalog);
    }
    const key = Number(row.group_id);
    if (!grouped.has(`${productId}:${key}`)) {
      grouped.set(`${productId}:${key}`, {
        productId,
        code: row.group_code,
        labelAr: row.group_label_ar,
        labelEn: row.group_label_en,
        displayMode: row.display_mode,
        selectionMode: row.selection_mode,
        required: row.required === true,
        sortOrder: row.group_sort_order,
        metadata: row.group_metadata_json || {},
        options: [],
      });
      catalog.variantGroups.push(grouped.get(`${productId}:${key}`));
    }
    if (row.option_id == null) continue;
    grouped.get(`${productId}:${key}`).options.push({
      code: row.option_code,
      labelAr: row.option_label_ar,
      labelEn: row.option_label_en,
      swatchHex: row.swatch_hex,
      priceDelta: row.price_delta,
      imageUrl: row.image_url,
      isAvailable: row.is_available !== false,
      sortOrder: row.option_sort_order,
      metadata: row.option_metadata_json || {},
    });
  }

  for (const row of mediaResult.rows) {
    const productId = Number(row.product_id);
    let catalog = catalogByProductId.get(productId);
    if (!catalog) {
      catalog = { attributes: [], variantGroups: [], variants: [], media: [] };
      catalogByProductId.set(productId, catalog);
    }
    const mediaIndex = catalog.media.length;
    const media = normalizeMediaInput(
      {
        imageUrl: row.image_url,
        altText: row.alt_text,
        isPrimary: row.is_primary === true,
        sortOrder: row.sort_order ?? mediaIndex,
        variantGroupCode: row.variant_group_code,
        variantOptionCode: row.variant_option_code,
        metadata: row.metadata_json || {},
      },
      mediaIndex
    );
    if (media) catalog.media.push(media);
  }

  for (const row of variantsResult.rows) {
    const productId = Number(row.product_id);
    let catalog = catalogByProductId.get(productId);
    if (!catalog) {
      catalog = { attributes: [], variantGroups: [], variants: [], media: [] };
      catalogByProductId.set(productId, catalog);
    }
    const variant = normalizeVariantInput({
      id: row.id,
      selections: row.selections_json,
      sku: row.sku,
      barcode: row.barcode,
      material: row.material,
      priceOverride: row.price_override,
      discountedPriceOverride: row.discounted_price_override,
      stockQuantity: row.stock_quantity,
      imageUrl: row.image_url,
      isAvailable: row.is_available,
      sortOrder: row.sort_order,
      metadata: row.metadata_json,
    }, catalog.variants.length);
    if (variant) catalog.variants.push(variant);
  }

  return catalogByProductId;
}

function ensurePrimaryMediaRows(media, fallbackImageUrl) {
  const normalized = media
    .map((entry, index) => ({
      ...entry,
      isPrimary: entry.isPrimary === true,
      sortOrder: Number.isInteger(Number(entry.sortOrder))
        ? Number(entry.sortOrder)
        : index,
    }))
    .filter((entry) => entry.imageUrl);
  if (!normalized.length && fallbackImageUrl) {
    normalized.push({
      imageUrl: String(fallbackImageUrl).trim(),
      altText: null,
      isPrimary: true,
      sortOrder: 0,
      variantGroupCode: null,
      variantOptionCode: null,
      metadata: {},
    });
  }
  if (!normalized.some((entry) => entry.isPrimary) && normalized.length) {
    normalized[0].isPrimary = true;
  }
  return normalized;
}

export async function getProductById(productId) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS category_name,
       c.sort_order AS category_sort_order
     FROM product p
     LEFT JOIN merchant_category c ON c.id = p.category_id
     WHERE p.id = $1
     LIMIT 1`,
    [Number(productId)]
  );
  return toRichProductBaseRow(r.rows[0] || null);
}

export async function getProductSummaryById(productId) {
  const row = await getProductById(productId);
  if (!row) return null;
  const catalogMap = await loadProductCatalogByProductIdsTx(pool, [productId]);
  return buildProductSnapshotFromRow(row, catalogMap.get(Number(productId)) || {});
}

export async function getProductDetailsById(productId) {
  return getProductSummaryById(productId);
}

export async function syncProductRichCatalogTx(client, productId, dto = {}) {
  if (!hasRichProductInput(dto)) {
    return null;
  }

  const rich = normalizeRichProductPayload(dto);
  const media = ensurePrimaryMediaRows(
    rich.media,
    normalizeText(dto.imageUrl ?? dto.image_url, 1000)
  );
  const snapshotBody = {
    ...dto,
    attributes: rich.attributes,
    variantGroups: rich.variantGroups,
    variants: rich.variants,
    media,
    metadataJson: rich.metadata,
  };
  const metadataJson = buildProductMetadataSnapshot(snapshotBody);

  await client.query("DELETE FROM product_attribute WHERE product_id = $1", [
    Number(productId),
  ]);
  await client.query("DELETE FROM product_variant_option WHERE group_id IN (SELECT id FROM product_variant_group WHERE product_id = $1)", [
    Number(productId),
  ]);
  await client.query("DELETE FROM product_variant_group WHERE product_id = $1", [
    Number(productId),
  ]);
  await client.query("DELETE FROM product_variant WHERE product_id = $1", [
    Number(productId),
  ]);
  await client.query("DELETE FROM product_media WHERE product_id = $1", [
    Number(productId),
  ]);

  for (const attr of rich.attributes) {
    await client.query(
      `INSERT INTO product_attribute
       (product_id, attribute_code, label_ar, label_en, value_text, value_unit, show_in_card, show_in_details, sort_order, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [
        Number(productId),
        attr.code,
        attr.labelAr,
        attr.labelEn,
        attr.valueText,
        attr.valueUnit,
        attr.showInCard === true,
        attr.showInDetails !== false,
        Number(attr.sortOrder || 0),
        JSON.stringify(attr.metadata || {}),
      ]
    );
  }

  for (const group of rich.variantGroups) {
    const groupResult = await client.query(
      `INSERT INTO product_variant_group
       (product_id, group_code, label_ar, label_en, display_mode, selection_mode, required, sort_order, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       RETURNING id, group_code`,
      [
        Number(productId),
        group.code,
        group.labelAr,
        group.labelEn,
        group.displayMode || "chips",
        group.selectionMode || "single",
        group.required === true,
        Number(group.sortOrder || 0),
        JSON.stringify(group.metadata || {}),
      ]
    );
    const insertedGroup = groupResult.rows[0];
    for (const option of group.options || []) {
      await client.query(
        `INSERT INTO product_variant_option
         (group_id, option_code, label_ar, label_en, swatch_hex, price_delta, image_url, is_available, sort_order, metadata_json)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
        [
          Number(insertedGroup.id),
          option.code,
          option.labelAr,
          option.labelEn,
          option.swatchHex,
          Number(option.priceDelta || 0),
          option.imageUrl,
          option.isAvailable !== false,
          Number(option.sortOrder || 0),
          JSON.stringify(option.metadata || {}),
        ]
      );
    }
  }

  for (const variant of rich.variants || []) {
    await client.query(
      `INSERT INTO product_variant
       (product_id, signature, selections_json, sku, barcode, material, price_override,
        discounted_price_override, stock_quantity, image_url, is_available, sort_order, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
      [
        Number(productId),
        variant.signature,
        JSON.stringify(variant.selections || []),
        variant.sku,
        variant.barcode,
        variant.material,
        variant.priceOverride,
        variant.discountedPriceOverride,
        Number(variant.stockQuantity || 0),
        variant.imageUrl,
        variant.isAvailable !== false,
        Number(variant.sortOrder || 0),
        JSON.stringify(variant.metadata || {}),
      ]
    );
  }

  for (const mediaItem of media) {
    await client.query(
      `INSERT INTO product_media
       (product_id, image_url, alt_text, is_primary, sort_order, variant_group_code, variant_option_code, metadata_json)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        Number(productId),
        mediaItem.imageUrl,
        mediaItem.altText,
        mediaItem.isPrimary === true,
        Number(mediaItem.sortOrder || 0),
        mediaItem.variantGroupCode,
        mediaItem.variantOptionCode,
        JSON.stringify(mediaItem.metadata || {}),
      ]
    );
  }

  const primaryMedia = media.find((item) => item.isPrimary) || media[0] || null;
  await client.query(
    `UPDATE product
     SET metadata_json = $2,
         image_url = COALESCE($3, image_url),
         updated_at = NOW()
     WHERE id = $1`,
    [
      Number(productId),
      JSON.stringify(metadataJson),
      primaryMedia?.imageUrl || normalizeText(dto.imageUrl ?? dto.image_url, 1000),
    ]
  );

  return {
    metadataJson,
    richCatalog: {
      attributes: rich.attributes,
      variantGroups: rich.variantGroups,
      variants: rich.variants || [],
      media,
      primaryMedia,
    },
  };
}

export async function loadProductRichCatalogById(productId) {
  const client = await pool.connect();
  try {
    const row = await getProductById(productId);
    if (!row) return null;
    const catalogMap = await loadProductCatalogByProductIdsTx(client, [productId]);
    return buildProductSnapshotFromRow(row, catalogMap.get(Number(productId)) || {});
  } finally {
    client.release();
  }
}

export async function loadProductRichCatalogByIds(productIds) {
  const client = await pool.connect();
  try {
    const normalizedIds = Array.from(
      new Set(
        (productIds || [])
          .map((value) => Number(value))
          .filter((value) => Number.isInteger(value) && value > 0)
      )
    );
    if (!normalizedIds.length) return new Map();
    const rows = await client.query(
      `SELECT
         p.*,
         c.name AS category_name,
         c.sort_order AS category_sort_order
       FROM product p
       LEFT JOIN merchant_category c ON c.id = p.category_id
       WHERE p.id = ANY($1::bigint[])`,
      [normalizedIds]
    );
    const catalogMap = await loadProductCatalogByProductIdsTx(client, normalizedIds);
    const out = new Map();
    for (const row of rows.rows) {
      const normalized = toRichProductBaseRow(row);
      if (!normalized) continue;
      out.set(
        Number(normalized.id),
        buildProductSnapshotFromRow(
          normalized,
          catalogMap.get(Number(normalized.id)) || extractRichCatalogFromMetadata(normalized.metadata_json)
        )
      );
    }
    return out;
  } finally {
    client.release();
  }
}
