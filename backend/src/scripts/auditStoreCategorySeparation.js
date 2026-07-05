/* eslint-disable no-console */
import { pool, q } from "../config/db.js";
import {
  inferCatalogTypeFromName,
  isCatalogTypeAllowedForActivity,
  normalizeCatalogType,
} from "../modules/merchants/catalog-taxonomy.js";

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    applySafe: args.includes("--apply-safe"),
  };
}

function normalizeActivityType(value) {
  return String(value || "").trim().toLowerCase();
}

function safeCatalogType(row) {
  const stored = normalizeCatalogType(row.catalog_type, "generic");
  const inferred = normalizeCatalogType(
    inferCatalogTypeFromName(row.name),
    "generic"
  );
  const merchantActivityType = normalizeActivityType(row.activity_type);
  const activityKnown =
    merchantActivityType.length > 0 && row.activity_is_known === true;

  return {
    stored,
    inferred,
    merchantActivityType,
    activityKnown,
    canFix:
      activityKnown &&
      stored === "generic" &&
      inferred !== "generic" &&
      isCatalogTypeAllowedForActivity(merchantActivityType, inferred),
  };
}

async function main() {
  const { applySafe } = parseArgs();
  const activityRows = await q(
    `SELECT activity_type
     FROM store_activity_definition
     WHERE is_active = TRUE`
  );
  const validActivities = new Set(
    activityRows.rows.map((row) => normalizeActivityType(row.activity_type))
  );

  const merchantRows = await q(
    `SELECT id, name, type, activity_type
     FROM merchant
     ORDER BY id ASC`
  );
  const categoryRows = await q(
    `SELECT
       c.id,
       c.merchant_id,
       c.name,
       c.catalog_type,
       m.name AS merchant_name,
       m.type AS merchant_type,
       m.activity_type,
       EXISTS (
         SELECT 1
         FROM store_activity_definition sad
         WHERE sad.activity_type = m.activity_type
           AND sad.is_active = TRUE
       ) AS activity_is_known
     FROM merchant_category c
     JOIN merchant m ON m.id = c.merchant_id
     ORDER BY c.merchant_id ASC, c.id ASC`
  );
  const productRows = await q(
    `SELECT
       p.id,
       p.name,
       p.merchant_id,
       p.category_id,
       c.name AS category_name,
       c.catalog_type AS category_catalog_type,
       m.name AS merchant_name,
       m.activity_type
     FROM product p
     JOIN merchant m ON m.id = p.merchant_id
     LEFT JOIN merchant_category c ON c.id = p.category_id
     ORDER BY p.merchant_id ASC, p.id ASC`
  );

  const merchantIssues = merchantRows.rows
    .map((row) => ({
      id: Number(row.id),
      name: row.name || "",
      type: row.type || "",
      activityType: normalizeActivityType(row.activity_type),
      activityKnown: validActivities.has(normalizeActivityType(row.activity_type)),
    }))
    .filter((row) => !row.activityType || !row.activityKnown);

  const categorySafeFixes = [];
  const categoryReview = [];
  const categoryById = new Map();

  for (const row of categoryRows.rows) {
    const classification = safeCatalogType(row);
    const record = {
      id: Number(row.id),
      merchantId: Number(row.merchant_id),
      merchantName: row.merchant_name || "",
      merchantType: row.merchant_type || "",
      activityType: classification.merchantActivityType,
      name: row.name || "",
      storedCatalogType: classification.stored,
      inferredCatalogType: classification.inferred,
      action: classification.canFix ? "update-catalog-type" : "review",
    };
    categoryById.set(record.id, record);
    if (classification.canFix) {
      categorySafeFixes.push(record);
      continue;
    }
    if (
      classification.activityKnown &&
      !isCatalogTypeAllowedForActivity(
        classification.merchantActivityType,
        classification.stored
      )
    ) {
      categoryReview.push(record);
      continue;
    }
    if (classification.stored === "generic") {
      categoryReview.push(record);
    }
  }

  const productReview = [];
  for (const row of productRows.rows) {
    const merchantActivityType = normalizeActivityType(row.activity_type);
    const categoryId = row.category_id == null ? null : Number(row.category_id);
    const category = categoryId == null ? null : categoryById.get(categoryId);
    const categoryType = normalizeCatalogType(
      row.category_catalog_type ?? category?.storedCatalogType,
      "generic"
    );
    const categoryAllowed =
      categoryId != null &&
      isCatalogTypeAllowedForActivity(merchantActivityType, categoryType);
    if (categoryAllowed) continue;

    productReview.push({
      id: Number(row.id),
      merchantId: Number(row.merchant_id),
      merchantName: row.merchant_name || "",
      activityType: merchantActivityType,
      name: row.name || "",
      categoryId,
      categoryName: row.category_name || "",
      categoryCatalogType: categoryType,
      safeCategoryFixAvailable: Boolean(category && category.action === "update-catalog-type"),
    });
  }

  if (applySafe && categorySafeFixes.length > 0) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      for (const item of categorySafeFixes) {
        await client.query(
          `UPDATE merchant_category
           SET catalog_type = $1
           WHERE id = $2`,
          [item.inferredCatalogType, item.id]
        );
      }
      await client.query("COMMIT");
      console.log(
        `Applied ${categorySafeFixes.length} safe category catalog_type updates.`
      );
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  const summary = {
    dryRun: !applySafe,
    merchantsWithMissingOrInvalidActivityType: merchantIssues,
    safeCategoryFixes: categorySafeFixes,
    manualCategoryReview: categoryReview,
    productReview,
  };

  console.log(JSON.stringify(summary, null, 2));
  if (merchantIssues.length === 0 && categorySafeFixes.length === 0 && categoryReview.length === 0 && productReview.length === 0) {
    console.log("Store/category separation audit: clean");
  }
}

main()
  .catch((error) => {
    console.error("[audit-store-category-separation] failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end().catch(() => {});
  });
