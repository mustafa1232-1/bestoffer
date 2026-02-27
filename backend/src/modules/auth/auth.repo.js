import { pool, q } from "../../config/db.js";

export async function findUserByPhone(phone) {
  const r = await q(
    `SELECT id, full_name, phone, pin_hash, role, block, building_number, apartment, image_url, is_super_admin
     FROM app_user
     WHERE regexp_replace(
       translate(
         phone,
         '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
         '01234567890123456789'
       ),
       '[^0-9]',
       '',
       'g'
     ) = $1
     LIMIT 1`,
    [phone]
  );

  return r.rows[0] || null;
}

export async function findUserByIdWithAuthFields(id) {
  const r = await q(
    `SELECT id, full_name, phone, pin_hash, role, block, building_number, apartment, image_url, is_super_admin
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [id]
  );

  return r.rows[0] || null;
}

export async function createUser({
  fullName,
  phone,
  pinHash,
  block,
  buildingNumber,
  apartment,
  imageUrl = null,
  role = "user",
  analyticsConsentGranted = false,
  analyticsConsentVersion = null,
  analyticsConsentGrantedAt = null,
}) {
  const r = await q(
    `INSERT INTO app_user
      (
        full_name,
        phone,
        pin_hash,
        block,
        building_number,
        apartment,
        image_url,
        role,
        analytics_consent_granted,
        analytics_consent_version,
        analytics_consent_granted_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING id, full_name, phone, role, block, building_number, apartment, image_url, is_super_admin`,
    [
      fullName,
      phone,
      pinHash,
      block,
      buildingNumber,
      apartment,
      imageUrl,
      role,
      analyticsConsentGranted === true,
      analyticsConsentVersion,
      analyticsConsentGrantedAt,
    ]
  );

  return r.rows[0];
}

export async function getUserPublicById(id) {
  const r = await q(
    `SELECT id, full_name, phone, role, block, building_number, apartment, image_url, is_super_admin
     FROM app_user
     WHERE id=$1`,
    [id]
  );

  return r.rows[0] || null;
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

  values.push(id);
  const r = await q(
    `UPDATE app_user
     SET ${fields.join(", ")}
     WHERE id = $${idx}
     RETURNING id, full_name, phone, role, block, building_number, apartment, image_url, is_super_admin`,
    values
  );

  return r.rows[0] || null;
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
