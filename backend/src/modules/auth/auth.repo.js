import { pool, q } from "../../config/db.js";
import { getRedisClient } from "../../config/redis.js";

const USER_PUBLIC_TTL = 300; // 5 minutes

async function cachedGet(key, ttlSec, fetcher) {
  const redis = await getRedisClient().catch(() => null);
  if (redis) {
    try {
      const hit = await redis.get(key);
      if (hit !== null) return JSON.parse(hit);
    } catch (_) { /* cache miss — fall through */ }
  }
  const value = await fetcher();
  if (redis && value !== null && value !== undefined) {
    redis.set(key, JSON.stringify(value), "EX", ttlSec).catch(() => {});
  }
  return value;
}

export async function invalidateUserPublicCache(userId) {
  const redis = await getRedisClient().catch(() => null);
  if (redis) redis.del(`user:pub:${userId}`).catch(() => {});
}

export async function findUserByPhone(phone) {
  const r = await q(
    `SELECT
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.preferred_locale,
       u.pin_hash,
       u.role,
       u.block,
       u.building_number,
       u.apartment,
       u.image_url,
       u.work_title,
       u.work_company,
       u.is_super_admin,
       u.is_account_disabled,
       u.account_disabled_note,
       u.delivery_account_approved,
       u.failed_login_attempts,
       u.locked_until,
       u.last_failed_login_at,
       u.last_login_at,
       EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       ) AS is_taxi_captain
     FROM app_user u
     WHERE u.phone_normalized = $1
     LIMIT 1`,
    [phone]
  );

  return r.rows[0] || null;
}

export async function findUserByIdWithAuthFields(id) {
  const r = await q(
    `SELECT
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.preferred_locale,
       u.pin_hash,
       u.role,
       u.block,
       u.building_number,
       u.apartment,
       u.image_url,
       u.work_title,
       u.work_company,
       u.is_super_admin,
       u.is_account_disabled,
       u.account_disabled_note,
       u.delivery_account_approved,
       u.failed_login_attempts,
       u.locked_until,
       u.last_failed_login_at,
       u.last_login_at,
       EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       ) AS is_taxi_captain
     FROM app_user u
     WHERE u.id = $1
     LIMIT 1`,
    [id]
  );

  return r.rows[0] || null;
}

export async function createUser({
  fullName,
  username,
  phone,
  pinHash,
  block,
  buildingNumber,
  apartment,
  imageUrl = null,
  workTitle = null,
  workCompany = null,
  role = "user",
  analyticsConsentGranted = false,
  analyticsConsentVersion = null,
  analyticsConsentGrantedAt = null,
  chatQualityReviewConsent = false,
}) {
  const r = await q(
    `INSERT INTO app_user
      (
        full_name,
        username,
        phone,
        pin_hash,
        block,
        building_number,
        apartment,
        image_url,
        work_title,
        work_company,
        role,
        analytics_consent_granted,
        analytics_consent_version,
        analytics_consent_granted_at,
        chat_quality_review_consent
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
     RETURNING id, username, full_name, phone, preferred_locale, role, block, building_number, apartment, image_url, work_title, work_company, is_super_admin`,
    [
      fullName,
      username,
      phone,
      pinHash,
      block,
      buildingNumber,
      apartment,
      imageUrl,
      workTitle,
      workCompany,
      role,
      analyticsConsentGranted === true,
      analyticsConsentVersion,
      analyticsConsentGrantedAt,
      chatQualityReviewConsent === true,
    ]
  );

  return r.rows[0];
}

export async function isUsernameTaken(username) {
  const normalized = String(username || "").trim().toLowerCase();
  if (!normalized) return false;
  const r = await q(
    `SELECT 1
     FROM app_user
     WHERE LOWER(username) = $1
     LIMIT 1`,
    [normalized]
  );
  return Boolean(r.rows[0]);
}

export async function upsertUserResidenceInfo({
  userId,
  documentType = "residence_card",
  fullName = null,
  town = null,
  buildingNumber = null,
  issueDate = null,
  contractNumber = null,
  floorNumber = null,
  apartmentNumber = null,
  visibleIdNumber = null,
  imageUrl = null,
  extractionConfidence = 0,
  extractedPayload = {},
}) {
  const r = await q(
    `INSERT INTO user_residence_info
      (
        user_id,
        document_type,
        full_name,
        town,
        building_number,
        issue_date,
        contract_number,
        floor_number,
        apartment_number,
        visible_id_number,
        image_url,
        extraction_confidence,
        extracted_payload,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,NOW(),NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET
       document_type = EXCLUDED.document_type,
       full_name = EXCLUDED.full_name,
       town = EXCLUDED.town,
       building_number = EXCLUDED.building_number,
       issue_date = EXCLUDED.issue_date,
       contract_number = EXCLUDED.contract_number,
       floor_number = EXCLUDED.floor_number,
       apartment_number = EXCLUDED.apartment_number,
       visible_id_number = EXCLUDED.visible_id_number,
       image_url = EXCLUDED.image_url,
       extraction_confidence = EXCLUDED.extraction_confidence,
       extracted_payload = EXCLUDED.extracted_payload,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(userId),
      String(documentType || "residence_card").slice(0, 40),
      fullName,
      town,
      buildingNumber,
      issueDate,
      contractNumber,
      floorNumber,
      apartmentNumber,
      visibleIdNumber,
      imageUrl,
      Number(extractionConfidence) || 0,
      extractedPayload || {},
    ]
  );

  return r.rows[0] || null;
}

export async function getUserPublicById(id) {
  return cachedGet(`user:pub:${id}`, USER_PUBLIC_TTL, async () => {
    const r = await q(
      `SELECT
         u.id,
         u.username,
         u.full_name,
         u.phone,
         u.role,
         u.block,
         u.building_number,
         u.apartment,
         u.image_url,
         u.work_title,
         u.work_company,
         u.is_super_admin,
         EXISTS (
           SELECT 1
           FROM taxi_captain_profile tcp
           WHERE tcp.user_id = u.id
         ) AS is_taxi_captain
       FROM app_user u
       WHERE u.id = $1`,
      [id]
    );
    return r.rows[0] || null;
  });
}

export async function updateUserAccount({ id, phone, pinHash }) {
  const fields = [];
  const values = [];
  let idx = 1;

  if (typeof phone === "string" && phone.trim()) {
    fields.push(`phone = $${idx++}`);
    values.push(phone.trim());
  }

  if (typeof pinHash === "string" && pinHash.trim()) {
    fields.push(`pin_hash = $${idx++}`);
    values.push(pinHash.trim());
  }

  if (fields.length === 0) return getUserPublicById(id);

  invalidateUserPublicCache(id);

  values.push(id);
  const r = await q(
    `UPDATE app_user
     SET ${fields.join(", ")}
     WHERE id = $${idx}
     RETURNING id, full_name, phone, preferred_locale, role, block, building_number, apartment, image_url, work_title, work_company, is_super_admin`,
    values
  );

  return r.rows[0] || null;
}

export async function registerFailedLoginAttempt(userId, { maxAttempts, lockMinutes }) {
  const max = Math.max(1, Number(maxAttempts) || 1);
  const lock = Math.max(1, Number(lockMinutes) || 1);
  const r = await q(
    `UPDATE app_user
     SET
       failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
       last_failed_login_at = NOW(),
       locked_until = CASE
         WHEN COALESCE(locked_until, NOW() - INTERVAL '1 second') > NOW() THEN locked_until
         WHEN COALESCE(failed_login_attempts, 0) + 1 >= $2
           THEN NOW() + ($3::text || ' minutes')::interval
         ELSE NULL
       END
     WHERE id = $1
     RETURNING failed_login_attempts, locked_until`,
    [Number(userId), max, lock]
  );
  return r.rows[0] || null;
}

export async function resetLoginProtection(userId) {
  await q(
    `UPDATE app_user
     SET failed_login_attempts = 0,
         locked_until = NULL,
         last_login_at = NOW()
     WHERE id = $1`,
    [Number(userId)]
  );
}

export async function createUserSession({
  userId,
  refreshToken,
  tokenJti,
  deviceFingerprint,
  userAgent,
  ipAddress,
  expiresAt,
  accessExpiresAt,
}) {
  const r = await q(
    `INSERT INTO user_session
      (
        user_id,
        refresh_token,
        token_jti,
        device_fingerprint,
        user_agent,
        ip,
        created_at,
        updated_at,
        last_seen_at,
        expires_at,
        access_expires_at,
        is_revoked
      )
     VALUES ($1,$2,$3,$4,$5,$6,NOW(),NOW(),NOW(),$7,$8,FALSE)
     RETURNING id, user_id, token_jti, device_fingerprint, is_revoked, expires_at, access_expires_at, last_seen_at`,
    [
      Number(userId),
      String(refreshToken || ""),
      tokenJti || null,
      deviceFingerprint || null,
      userAgent || null,
      ipAddress || null,
      expiresAt,
      accessExpiresAt || null,
    ]
  );
  return r.rows[0] || null;
}

export async function findActiveSessionByRefreshToken(refreshToken) {
  const token = String(refreshToken || "").trim();
  if (!token) return null;
  const r = await q(
    `SELECT
       s.id AS session_id,
       s.user_id AS session_user_id,
       s.refresh_token,
       s.token_jti,
       s.device_fingerprint,
       s.expires_at AS session_expires_at,
       s.is_revoked,
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.preferred_locale,
       u.role,
       u.block,
       u.building_number,
       u.apartment,
       u.image_url,
       u.work_title,
       u.work_company,
       u.is_super_admin,
       u.is_account_disabled,
       u.account_disabled_note,
       u.delivery_account_approved,
       EXISTS (
         SELECT 1
         FROM taxi_captain_profile tcp
         WHERE tcp.user_id = u.id
       ) AS is_taxi_captain
     FROM user_session s
     JOIN app_user u ON u.id = s.user_id
     WHERE s.refresh_token = $1
       AND s.is_revoked = FALSE
       AND s.expires_at > NOW()
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
     LIMIT 1`,
    [token]
  );
  return r.rows[0] || null;
}

export async function rotateUserSessionTokens({
  sessionId,
  userId,
  refreshToken,
  tokenJti,
  ipAddress = null,
  userAgent = null,
}) {
  const r = await q(
    `UPDATE user_session
     SET refresh_token = $3,
         token_jti = $4,
         ip = COALESCE($5, ip),
         user_agent = COALESCE($6, user_agent),
         last_seen_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND is_revoked = FALSE
       AND expires_at > NOW()
     RETURNING id, user_id, token_jti, device_fingerprint, is_revoked, expires_at, access_expires_at, last_seen_at`,
    [
      Number(sessionId),
      Number(userId),
      String(refreshToken || ""),
      tokenJti || null,
      ipAddress || null,
      userAgent || null,
    ]
  );
  return r.rows[0] || null;
}

export async function pruneUserSessions(userId, { maxActive }) {
  const cap = Math.max(1, Number(maxActive) || 1);
  const rows = await q(
    `SELECT id
     FROM user_session
     WHERE user_id = $1
       AND is_revoked = FALSE
       AND expires_at > NOW()
     ORDER BY last_seen_at DESC NULLS LAST, id DESC`,
    [Number(userId)]
  );

  if (rows.rowCount <= cap) {
    return {
      revokedCount: 0,
      revokedSessionIds: [],
    };
  }
  const staleIds = rows.rows.slice(cap).map((row) => Number(row.id));
  if (staleIds.length === 0) {
    return {
      revokedCount: 0,
      revokedSessionIds: [],
    };
  }

  const out = await q(
    `UPDATE user_session
     SET is_revoked = TRUE,
         revoked_at = NOW(),
         revoked_reason = 'session_pruned',
         updated_at = NOW()
     WHERE id = ANY($1::bigint[])`,
    [staleIds]
  );
  return {
    revokedCount: out.rowCount || 0,
    revokedSessionIds: staleIds,
  };
}

export async function getActiveSessionByAccess({
  sessionId,
  userId,
  tokenJti,
}) {
  const r = await q(
    `SELECT
       s.id,
       s.user_id,
       s.token_jti,
       s.device_fingerprint,
       s.expires_at,
       s.access_expires_at,
       s.is_revoked,
       s.revoked_at
     FROM user_session s
     JOIN app_user u ON u.id = s.user_id
     WHERE s.id = $1
       AND s.user_id = $2
       AND s.is_revoked = FALSE
       AND s.expires_at > NOW()
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND (s.token_jti IS NULL OR s.token_jti = $3)
     LIMIT 1`,
    [Number(sessionId), Number(userId), tokenJti || null]
  );
  return r.rows[0] || null;
}

export async function touchUserSession(sessionId, { ipAddress, userAgent } = {}) {
  await q(
    `UPDATE user_session
     SET last_seen_at = NOW(),
         ip = COALESCE($2, ip),
         user_agent = COALESCE($3, user_agent),
         updated_at = NOW()
     WHERE id = $1
       AND is_revoked = FALSE`,
    [Number(sessionId), ipAddress || null, userAgent || null]
  );
}

export async function revokeUserSession({
  userId,
  sessionId,
  reason = "logout",
}) {
  const r = await q(
    `UPDATE user_session
     SET is_revoked = TRUE,
         revoked_at = NOW(),
         revoked_reason = $3,
         updated_at = NOW()
     WHERE id = $2
       AND user_id = $1
       AND is_revoked = FALSE
     RETURNING id`,
    [Number(userId), Number(sessionId), String(reason || "logout").slice(0, 80)]
  );
  return r.rows[0] || null;
}

export async function revokeAllUserSessions({
  userId,
  exceptSessionId = null,
  reason = "logout_all",
}) {
  const params = [Number(userId), String(reason || "logout_all").slice(0, 80)];
  let sql = `UPDATE user_session
    SET is_revoked = TRUE,
        revoked_at = NOW(),
        revoked_reason = $2,
        updated_at = NOW()
    WHERE user_id = $1
      AND is_revoked = FALSE`;
  if (exceptSessionId != null) {
    params.push(Number(exceptSessionId));
    sql += ` AND id <> $3`;
  }
  const r = await q(sql, params);
  return r.rowCount || 0;
}

export async function listUserActiveSessions(userId) {
  const r = await q(
    `SELECT
       id,
       user_id,
       user_agent,
       ip,
       device_fingerprint,
       created_at,
       last_seen_at,
       expires_at,
       access_expires_at
     FROM user_session
     WHERE user_id = $1
       AND is_revoked = FALSE
       AND expires_at > NOW()
     ORDER BY last_seen_at DESC NULLS LAST, id DESC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function listCustomerAddresses(customerUserId) {
  const r = await q(
    `SELECT
       id,
       customer_user_id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default,
       is_active,
       created_at,
       updated_at
     FROM customer_address
     WHERE customer_user_id = $1
       AND is_active = TRUE
     ORDER BY is_default DESC, id DESC`,
    [Number(customerUserId)]
  );
  return r.rows;
}

export async function getCustomerAddressById(customerUserId, addressId) {
  const r = await q(
    `SELECT
       id,
       customer_user_id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default,
       is_active,
       created_at,
       updated_at
     FROM customer_address
     WHERE customer_user_id = $1
       AND id = $2
       AND is_active = TRUE
     LIMIT 1`,
    [Number(customerUserId), Number(addressId)]
  );
  return r.rows[0] || null;
}

export async function getCustomerDefaultAddress(customerUserId) {
  const r = await q(
    `SELECT
       id,
       customer_user_id,
       label,
       city,
       block,
       building_number,
       apartment,
       is_default,
       is_active,
       created_at,
       updated_at
     FROM customer_address
     WHERE customer_user_id = $1
       AND is_active = TRUE
     ORDER BY is_default DESC, id DESC
     LIMIT 1`,
    [Number(customerUserId)]
  );
  return r.rows[0] || null;
}

export async function createCustomerAddress(customerUserId, dto) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const countResult = await client.query(
      `SELECT COUNT(*)::int AS count
       FROM customer_address
       WHERE customer_user_id = $1
         AND is_active = TRUE`,
      [Number(customerUserId)]
    );
    const activeCount = Number(countResult.rows[0]?.count || 0);
    const makeDefault = dto.isDefault === true || activeCount === 0;

    if (makeDefault) {
      await client.query(
        `UPDATE customer_address
         SET is_default = FALSE
         WHERE customer_user_id = $1
           AND is_active = TRUE`,
        [Number(customerUserId)]
      );
    }

    const insertResult = await client.query(
      `INSERT INTO customer_address
        (
          customer_user_id,
          label,
          city,
          block,
          building_number,
          apartment,
          is_default,
          is_active
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,TRUE)
       RETURNING
         id,
         customer_user_id,
         label,
         city,
         block,
         building_number,
         apartment,
         is_default,
         is_active,
         created_at,
         updated_at`,
      [
        Number(customerUserId),
        dto.label,
        dto.city,
        dto.block,
        dto.buildingNumber,
        dto.apartment,
        makeDefault,
      ]
    );

    await client.query("COMMIT");
    return insertResult.rows[0] || null;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function updateCustomerAddress(customerUserId, addressId, dto) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const targetResult = await client.query(
      `SELECT id
       FROM customer_address
       WHERE customer_user_id = $1
         AND id = $2
         AND is_active = TRUE
       LIMIT 1`,
      [Number(customerUserId), Number(addressId)]
    );
    if (!targetResult.rows[0]) {
      await client.query("ROLLBACK");
      return null;
    }

    if (dto.isDefault === true) {
      await client.query(
        `UPDATE customer_address
         SET is_default = FALSE
         WHERE customer_user_id = $1
           AND is_active = TRUE`,
        [Number(customerUserId)]
      );
    }

    const fields = [];
    const values = [];
    let idx = 1;

    const map = {
      label: "label",
      city: "city",
      block: "block",
      buildingNumber: "building_number",
      apartment: "apartment",
      isDefault: "is_default",
    };

    for (const [key, column] of Object.entries(map)) {
      if (dto[key] !== undefined) {
        fields.push(`${column} = $${idx++}`);
        values.push(dto[key]);
      }
    }

    if (fields.length === 0) {
      const currentResult = await client.query(
        `SELECT
           id,
           customer_user_id,
           label,
           city,
           block,
           building_number,
           apartment,
           is_default,
           is_active,
           created_at,
           updated_at
         FROM customer_address
         WHERE customer_user_id = $1
           AND id = $2
           AND is_active = TRUE
         LIMIT 1`,
        [Number(customerUserId), Number(addressId)]
      );
      await client.query("COMMIT");
      return currentResult.rows[0] || null;
    }

    values.push(Number(customerUserId), Number(addressId));
    const updateResult = await client.query(
      `UPDATE customer_address
       SET ${fields.join(", ")}
       WHERE customer_user_id = $${idx++}
         AND id = $${idx}
         AND is_active = TRUE
       RETURNING
         id,
         customer_user_id,
         label,
         city,
         block,
         building_number,
         apartment,
         is_default,
         is_active,
         created_at,
         updated_at`,
      values
    );

    await client.query("COMMIT");
    return updateResult.rows[0] || null;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function setCustomerDefaultAddress(customerUserId, addressId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const targetResult = await client.query(
      `SELECT id
       FROM customer_address
       WHERE customer_user_id = $1
         AND id = $2
         AND is_active = TRUE
       LIMIT 1`,
      [Number(customerUserId), Number(addressId)]
    );
    if (!targetResult.rows[0]) {
      await client.query("ROLLBACK");
      return null;
    }

    await client.query(
      `UPDATE customer_address
       SET is_default = FALSE
       WHERE customer_user_id = $1
         AND is_active = TRUE`,
      [Number(customerUserId)]
    );

    const updateResult = await client.query(
      `UPDATE customer_address
       SET is_default = TRUE
       WHERE customer_user_id = $1
         AND id = $2
         AND is_active = TRUE
       RETURNING
         id,
         customer_user_id,
         label,
         city,
         block,
         building_number,
         apartment,
         is_default,
         is_active,
         created_at,
         updated_at`,
      [Number(customerUserId), Number(addressId)]
    );

    await client.query("COMMIT");
    return updateResult.rows[0] || null;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function deactivateCustomerAddress(customerUserId, addressId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const targetResult = await client.query(
      `SELECT id, is_default
       FROM customer_address
       WHERE customer_user_id = $1
         AND id = $2
         AND is_active = TRUE
       LIMIT 1`,
      [Number(customerUserId), Number(addressId)]
    );
    const target = targetResult.rows[0];
    if (!target) {
      await client.query("ROLLBACK");
      return false;
    }

    await client.query(
      `UPDATE customer_address
       SET is_active = FALSE,
           is_default = FALSE
       WHERE customer_user_id = $1
         AND id = $2`,
      [Number(customerUserId), Number(addressId)]
    );

    if (target.is_default) {
      const nextDefaultResult = await client.query(
        `SELECT id
         FROM customer_address
         WHERE customer_user_id = $1
           AND is_active = TRUE
         ORDER BY id DESC
         LIMIT 1`,
        [Number(customerUserId)]
      );
      const nextId = nextDefaultResult.rows[0]?.id;
      if (nextId) {
        await client.query(
          `UPDATE customer_address
           SET is_default = TRUE
           WHERE id = $1`,
          [Number(nextId)]
        );
      }
    }

    await client.query("COMMIT");
    return true;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
