import "dotenv/config";

import { q } from "../config/db.js";

const limit = Math.max(1, Math.min(20, Number(process.argv[2]) || 5));

const rows = await q(
  `SELECT id, user_id, app_role, platform, app_version, source, message,
          stack_trace, extra, created_at
     FROM app_crash_event
    ORDER BY id DESC
    LIMIT $1`,
  [limit]
);

console.log(JSON.stringify(rows.rows, null, 2));
process.exit(0);
