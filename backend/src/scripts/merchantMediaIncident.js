/* eslint-disable no-console */
import "dotenv/config";

import { pool, q } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { invalidateMerchantBrowseCache } from "../modules/merchants/merchants.repo.js";
import { isTrustedMerchantMediaUrl } from "../shared/utils/merchant-media-url-policy.js";

const CONFIRM_TOKEN = "MERCHANT_MEDIA_INCIDENT";
const ALLOWED_FIELDS = new Set(["image_url", "logo_url", "cover_image_url"]);

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    execute: args.includes("--execute"),
    confirm: "",
    clear: args.includes("--clear"),
    all: args.includes("--all"),
    setUrl: "",
    fields: ["image_url", "logo_url", "cover_image_url"],
    limit: null,
  };

  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--confirm" && next) {
      out.confirm = next;
      i += 1;
      continue;
    }
    if (key === "--set-url" && next) {
      out.setUrl = next;
      i += 1;
      continue;
    }
    if (key === "--fields" && next) {
      out.fields = next
        .split(",")
        .map((field) => field.trim())
        .filter((field) => ALLOWED_FIELDS.has(field));
      i += 1;
      continue;
    }
    if (key === "--limit" && next) {
      const parsed = Number(next);
      out.limit = Number.isInteger(parsed) && parsed > 0 ? parsed : null;
      i += 1;
    }
  }

  if (!out.clear && !out.setUrl) {
    out.clear = true;
  }
  if (out.clear && out.setUrl) {
    throw new Error("Use either --clear or --set-url, not both.");
  }
  if (out.setUrl && !isTrustedMerchantMediaUrl(out.setUrl)) {
    throw new Error("Replacement URL is not trusted by merchant media policy.");
  }
  if (out.fields.length === 0) {
    throw new Error("No valid fields selected. Use image_url,logo_url,cover_image_url.");
  }

  return out;
}

function summarizeRow(row, fields, includeTrusted = false) {
  if (includeTrusted) return [...fields];

  const badFields = [];
  for (const field of fields) {
    if (row[field] && !isTrustedMerchantMediaUrl(row[field])) {
      badFields.push(field);
    }
  }
  return badFields;
}

async function main() {
  const options = parseArgs();
  const params = [];
  const limitSql =
    options.limit == null
      ? ""
      : (() => {
          params.push(options.limit);
          return "LIMIT $1";
        })();
  const result = await q(
    `SELECT id, name, image_url, logo_url, cover_image_url
     FROM merchant
     ORDER BY id ASC
     ${limitSql}`,
    params
  );

  const impacted = result.rows
    .map((row) => ({
      row,
      fields: summarizeRow(row, options.fields, options.all),
    }))
    .filter((entry) => entry.fields.length > 0);

  console.log(
    `[merchant-media] scanned=${result.rows.length} mode=${options.all ? "all" : "untrusted"} impacted=${impacted.length}`
  );
  for (const entry of impacted.slice(0, 50)) {
    console.log(
      `[merchant-media] merchant=${entry.row.id} name="${entry.row.name}" fields=${entry.fields.join(",")}`
    );
  }
  if (impacted.length > 50) {
    console.log(`[merchant-media] showing first 50 of ${impacted.length}`);
  }

  if (!options.execute) {
    console.log(
      "[merchant-media] dry-run only. Add --execute --confirm MERCHANT_MEDIA_INCIDENT to update."
    );
    return;
  }

  if (options.confirm !== CONFIRM_TOKEN) {
    throw new Error(`Missing --confirm ${CONFIRM_TOKEN}`);
  }

  let updatedFields = 0;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const entry of impacted) {
      const sets = [];
      const values = [];
      let idx = 1;
      for (const field of entry.fields) {
        sets.push(`${field}=$${idx++}`);
        values.push(options.clear ? null : options.setUrl);
        updatedFields += 1;
      }
      if (sets.length === 0) continue;
      values.push(Number(entry.row.id));
      await client.query(
        `UPDATE merchant
         SET ${sets.join(", ")}, updated_at = NOW()
         WHERE id = $${idx}`,
        values
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    client.release();
  }

  await invalidateMerchantBrowseCache().catch(() => {});
  console.log(`[merchant-media] updated_merchants=${impacted.length} updated_fields=${updatedFields}`);
}

main()
  .catch((error) => {
    console.error(`[merchant-media] failed: ${error?.message || error}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  });
