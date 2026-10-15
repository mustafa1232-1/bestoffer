import { pool } from "../config/db.js";

const checks = {
  serviceOfferingDuplicates: `
    SELECT COUNT(*)::int AS groups
    FROM (
      SELECT provider_id, subcategory_id_resolved, normalized_name, COUNT(*)
      FROM service_offerings
      GROUP BY provider_id, subcategory_id_resolved, normalized_name
      HAVING COUNT(*) > 1
    ) duplicates
  `,
  receivableInvoiceDuplicates: `
    SELECT COUNT(*)::int AS groups
    FROM (
      SELECT order_id, COUNT(*)
      FROM merchant_receivable_invoice
      GROUP BY order_id
      HAVING COUNT(*) > 1
    ) duplicates
  `,
  exactPhoneDuplicates: `
    SELECT COUNT(*)::int AS groups
    FROM (
      SELECT phone, COUNT(*)
      FROM app_user
      GROUP BY phone
      HAVING COUNT(*) > 1
    ) duplicates
  `,
  normalizedPhoneDuplicates: `
    SELECT COUNT(*)::int AS groups
    FROM (
      SELECT REGEXP_REPLACE(phone, '[^0-9]', '', 'g') AS normalized_phone,
             COUNT(*)
      FROM app_user
      GROUP BY normalized_phone
      HAVING COUNT(*) > 1
    ) duplicates
  `,
  runtimeConflictOfferings: `
    SELECT COUNT(*)::int AS groups
    FROM service_offerings
    WHERE name LIKE 'Runtime conflict %'
  `,
  runtimeConflictSessions: `
    SELECT COUNT(*)::int AS groups
    FROM user_session
    WHERE user_agent LIKE 'runtime-conflict/%'
  `,
  recentSecurityUsers: `
    SELECT COUNT(*)::int AS groups
    FROM app_user
    WHERE full_name LIKE 'Security % security-%'
      AND created_at >= NOW() - INTERVAL '1 hour'
  `,
  recentSecurityMerchants: `
    SELECT COUNT(*)::int AS groups
    FROM merchant
    WHERE name LIKE 'Security Merchant security-%'
      AND created_at >= NOW() - INTERVAL '1 hour'
  `,
  activeSecuritySessions: `
    SELECT COUNT(*)::int AS groups
    FROM user_session
    WHERE user_agent LIKE 'security-check/%'
      AND created_at >= NOW() - INTERVAL '1 hour'
  `,
};

const result = {};
try {
  for (const [key, sql] of Object.entries(checks)) {
    const query = await pool.query(sql);
    result[key] = Number(query.rows[0]?.groups || 0);
  }
  console.log(JSON.stringify(result));
} finally {
  await pool.end();
}
