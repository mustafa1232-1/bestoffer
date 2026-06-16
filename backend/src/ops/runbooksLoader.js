import fs from "fs/promises";
import path from "path";

import { q } from "../config/db.js";

const RUNBOOKS_DIR = path.resolve(process.cwd(), "src", "ops", "runbooks");

function toTitle(slug) {
  return String(slug || "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (s) => s.toUpperCase())
    .trim();
}

export async function seedOpsRunbooks() {
  let files = [];
  try {
    files = await fs.readdir(RUNBOOKS_DIR, { withFileTypes: true });
  } catch (_) {
    return { loaded: 0, reason: "runbooks_dir_missing" };
  }

  let loaded = 0;
  for (const file of files) {
    if (!file.isFile() || !file.name.toLowerCase().endsWith(".md")) continue;
    const slug = file.name.replace(/\.md$/i, "");
    const title = toTitle(slug);
    const content = await fs.readFile(path.join(RUNBOOKS_DIR, file.name), "utf8");

    // eslint-disable-next-line no-await-in-loop
    await q(
      `INSERT INTO ops_runbooks (slug, title, content)
       VALUES ($1,$2,$3)
       ON CONFLICT (slug)
       DO UPDATE SET
         title = EXCLUDED.title,
         content = EXCLUDED.content,
         updated_at = NOW()`,
      [slug, title, content]
    );
    loaded += 1;
  }

  return { loaded };
}
