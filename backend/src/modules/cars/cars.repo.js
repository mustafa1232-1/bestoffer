import { pool, q } from "../../config/db.js";
import { hasPaidUpgrade } from "../paid-upgrades/paid-upgrades.repo.js";

function txRunner(client) {
  if (client?.query) {
    return (sql, params = []) => client.query(sql, params);
  }
  return (sql, params = []) => q(sql, params);
}

function toInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return Math.floor(parsed);
}

function toListingRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    ownerId: Number(row.owner_user_id),
    ownerFullName: row.owner_full_name || null,
    status: String(row.status || ""),
    title: String(row.title || ""),
    description: row.description || null,
    brand: String(row.brand || ""),
    model: String(row.model || ""),
    modelYear: Number(row.model_year || 0),
    condition: String(row.condition || "used"),
    price: Number(row.price || 0),
    mileageKm: row.mileage_km == null ? null : Number(row.mileage_km),
    city: row.city || null,
    phone: row.phone || null,
    transmission: String(row.transmission || "automatic"),
    fuelType: String(row.fuel_type || "fuel"),
    bodyType: String(row.body_type || "sedan"),
    color: row.color || null,
    lastVisibleStatus: row.last_visible_status || null,
    hiddenDueSubscriptionExpiryAt: row.hidden_due_subscription_expiry_at || null,
    soldAt: row.sold_at || null,
    archivedAt: row.archived_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    media: Array.isArray(row.media) ? row.media : [],
  };
}

function toMediaRows(files = []) {
  return files
    .map((item, index) => ({
      imageUrl: item.imageUrl,
      sortOrder: index,
    }))
    .filter((item) => String(item.imageUrl || "").trim().length > 0);
}

async function listMediaForListings(client, listingIds) {
  const ids = Array.isArray(listingIds)
    ? listingIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0)
    : [];
  if (!ids.length) return new Map();
  const run = txRunner(client);
  const r = await run(
    `SELECT *
     FROM car_listing_media
     WHERE listing_id = ANY($1::bigint[])
     ORDER BY listing_id ASC, sort_order ASC, id ASC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const listingId = Number(row.listing_id);
    const list = map.get(listingId) || [];
    list.push({
      id: Number(row.id),
      imageUrl: row.image_url,
      sortOrder: Number(row.sort_order || 0),
      createdAt: row.created_at || null,
    });
    map.set(listingId, list);
  }
  return map;
}

async function hydrateListings(client, rows) {
  const mediaMap = await listMediaForListings(
    client,
    rows.map((row) => row.id)
  );
  return rows.map((row) =>
    toListingRow({
      ...row,
      media: mediaMap.get(Number(row.id)) || [],
    })
  );
}

export async function hasCarSellerUpgrade(userId, { client = null } = {}) {
  const [carSellerMonthly, premiumMonthly] = await Promise.all([
    hasPaidUpgrade(userId, "car_seller_monthly", { client }),
    hasPaidUpgrade(userId, "premium_monthly", { client }),
  ]);
  return carSellerMonthly || premiumMonthly;
}

export async function syncVisibilityForOwner(userId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const active = await hasCarSellerUpgrade(userId, { client });
    const changedRows = [];

    if (!active) {
      const r = await client.query(
        `UPDATE car_listing
         SET last_visible_status = COALESCE(last_visible_status, status),
             status = 'hidden_due_subscription_expiry',
             hidden_due_subscription_expiry_at = COALESCE(hidden_due_subscription_expiry_at, NOW()),
             updated_at = NOW()
         WHERE owner_user_id = $1
           AND status = 'active'
         RETURNING id`,
        [Number(userId)]
      );
      for (const row of r.rows) {
        changedRows.push(Number(row.id));
      }
    } else {
      const r = await client.query(
        `UPDATE car_listing
         SET status = COALESCE(NULLIF(last_visible_status, ''), 'active'),
             last_visible_status = NULL,
             hidden_due_subscription_expiry_at = NULL,
             updated_at = NOW()
         WHERE owner_user_id = $1
           AND status = 'hidden_due_subscription_expiry'
         RETURNING id`,
        [Number(userId)]
      );
      for (const row of r.rows) {
        changedRows.push(Number(row.id));
      }
    }

    await client.query("COMMIT");
    return changedRows;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function listPublicListings(query = {}) {
  const client = await pool.connect();
  try {
    const filters = [`l.status = 'active'`];
    const params = [];

    if (query.brand) {
      params.push(String(query.brand).trim());
      filters.push(`l.brand ILIKE $${params.length}`);
    }
    if (query.model) {
      params.push(String(query.model).trim());
      filters.push(`l.model ILIKE $${params.length}`);
    }
    if (query.search) {
      params.push(`%${String(query.search).trim()}%`);
      filters.push(
        `(l.title ILIKE $${params.length} OR COALESCE(l.description, '') ILIKE $${params.length} OR l.brand ILIKE $${params.length} OR l.model ILIKE $${params.length} OR COALESCE(l.city, '') ILIKE $${params.length})`
      );
    }
    if (query.city) {
      params.push(String(query.city).trim());
      filters.push(`l.city ILIKE $${params.length}`);
    }
    if (query.condition) {
      params.push(String(query.condition).trim());
      filters.push(`l.condition = $${params.length}`);
    }
    if (query.bodyType) {
      params.push(String(query.bodyType).trim());
      filters.push(`l.body_type = $${params.length}`);
    }
    if (query.minPrice != null) {
      params.push(Number(query.minPrice));
      filters.push(`l.price >= $${params.length}`);
    }
    if (query.maxPrice != null) {
      params.push(Number(query.maxPrice));
      filters.push(`l.price <= $${params.length}`);
    }

    const sort = String(query.sort || "recent").trim().toLowerCase();
    const orderBy =
      sort === "oldest"
        ? "l.created_at ASC, l.id ASC"
        : sort === "price_low"
          ? "l.price ASC, l.created_at DESC"
          : sort === "price_high"
            ? "l.price DESC, l.created_at DESC"
            : "l.created_at DESC, l.id DESC";

    params.push(Math.max(1, Math.min(100, Number(query.limit) || 20)));
    params.push(Math.max(0, Number(query.offset) || 0));

    const r = await client.query(
      `SELECT l.*, u.full_name AS owner_full_name
       FROM car_listing l
       JOIN app_user u ON u.id = l.owner_user_id
       WHERE ${filters.join(" AND ")}
       ORDER BY ${orderBy}
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return await hydrateListings(client, r.rows);
  } finally {
    client.release();
  }
}

export async function getListingById(listingId, { viewerUserId = null } = {}) {
  const id = toInt(listingId);
  if (!id) return null;
  const r = await q(
    `SELECT l.*, u.full_name AS owner_full_name
     FROM car_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     WHERE l.id = $1
     LIMIT 1`,
    [id]
  );
  const row = r.rows[0] || null;
  if (!row) return null;

  if (viewerUserId != null && Number(viewerUserId) === Number(row.owner_user_id)) {
    const media = await listMediaForListings(null, [id]);
    return toListingRow({ ...row, media: media.get(id) || [] });
  }

  if (row.status !== "active") return null;
  const media = await listMediaForListings(null, [id]);
  return toListingRow({ ...row, media: media.get(id) || [] });
}

export async function getWorkspace(userId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const syncChanged = await syncVisibilityForOwner(userId);
    const active = await hasCarSellerUpgrade(userId, { client });
    const counts = await client.query(
      `SELECT status, COUNT(*)::int AS total
       FROM car_listing
       WHERE owner_user_id = $1
       GROUP BY status`,
      [Number(userId)]
    );
    const rows = await client.query(
      `SELECT *
       FROM car_listing
       WHERE owner_user_id = $1
       ORDER BY created_at DESC, id DESC`,
      [Number(userId)]
    );
    const mediaMap = await listMediaForListings(client, rows.rows.map((row) => row.id));
    await client.query("COMMIT");
    return {
      entitlement: {
        carSellerMonthly: active,
      },
      syncChangedListingIds: syncChanged,
      counts: counts.rows.reduce((acc, row) => {
        acc[String(row.status)] = Number(row.total || 0);
        return acc;
      }, {}),
      listings: rows.rows.map((row) =>
        toListingRow({
          ...row,
          media: mediaMap.get(Number(row.id)) || [],
        })
      ),
    };
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function createListing(userId, dto, files = []) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const active = await hasCarSellerUpgrade(userId, { client });
    if (!active) {
      const error = new Error("CAR_SELLER_SUBSCRIPTION_REQUIRED");
      error.status = 403;
      error.code = "CAR_SELLER_SUBSCRIPTION_REQUIRED";
      throw error;
    }

    const insert = await client.query(
      `INSERT INTO car_listing (
         owner_user_id,
         status,
         title,
         description,
         brand,
         model,
         model_year,
         condition,
         price,
         mileage_km,
         city,
         phone,
         transmission,
         fuel_type,
         body_type,
         color
       )
       VALUES ($1,'active',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       RETURNING *`,
      [
        Number(userId),
        dto.title,
        dto.description,
        dto.brand,
        dto.model,
        Number(dto.modelYear),
        dto.condition,
        Number(dto.price || 0),
        dto.mileageKm == null ? null : Number(dto.mileageKm),
        dto.city || null,
        dto.phone,
        dto.transmission,
        dto.fuelType,
        dto.bodyType,
        dto.color || null,
      ]
    );
    const listing = insert.rows[0];

    for (const media of toMediaRows(files)) {
      await client.query(
        `INSERT INTO car_listing_media (listing_id, image_url, sort_order)
         VALUES ($1,$2,$3)`,
        [Number(listing.id), media.imageUrl, media.sortOrder]
      );
    }

    await client.query("COMMIT");
    const mediaMap = await listMediaForListings(null, [listing.id]);
    return toListingRow({
      ...listing,
      media: mediaMap.get(Number(listing.id)) || [],
    });
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updateListing(userId, listingId, dto, files = []) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM car_listing
       WHERE id = $1
         AND owner_user_id = $2
       FOR UPDATE`,
      [Number(listingId), Number(userId)]
    );
    const listing = current.rows[0] || null;
    if (!listing) {
      await client.query("ROLLBACK");
      return null;
    }

    const requiresActiveEntitlement = ["active", "hidden_due_subscription_expiry"].includes(
      String(listing.status || "")
    );
    if (requiresActiveEntitlement) {
      const active = await hasCarSellerUpgrade(userId, { client });
      if (!active) {
        const error = new Error("CAR_SELLER_SUBSCRIPTION_REQUIRED");
        error.status = 403;
        error.code = "CAR_SELLER_SUBSCRIPTION_REQUIRED";
        throw error;
      }
    }

    const columns = {
      title: "title",
      description: "description",
      brand: "brand",
      model: "model",
      modelYear: "model_year",
      condition: "condition",
      price: "price",
      mileageKm: "mileage_km",
      city: "city",
      phone: "phone",
      transmission: "transmission",
      fuelType: "fuel_type",
      bodyType: "body_type",
      color: "color",
    };
    const values = [];
    const sets = [];
    let idx = 1;
    for (const [key, column] of Object.entries(columns)) {
      if (!Object.prototype.hasOwnProperty.call(dto, key)) continue;
      values.push(dto[key]);
      sets.push(`${column} = $${idx++}`);
    }
    if (sets.length > 0) {
      values.push(Number(listingId));
      values.push(Number(userId));
      const updated = await client.query(
        `UPDATE car_listing
         SET ${sets.join(", ")}
         WHERE id = $${idx++}
           AND owner_user_id = $${idx}
         RETURNING *`,
        values
      );
      if (!updated.rows[0]) {
        await client.query("ROLLBACK");
        return null;
      }
    }

    if (files.length > 0) {
      await client.query(`DELETE FROM car_listing_media WHERE listing_id = $1`, [
        Number(listingId),
      ]);
      for (const media of toMediaRows(files)) {
        await client.query(
          `INSERT INTO car_listing_media (listing_id, image_url, sort_order)
           VALUES ($1,$2,$3)`,
          [Number(listingId), media.imageUrl, media.sortOrder]
        );
      }
    }

    await client.query("COMMIT");
    return getListingById(listingId, { viewerUserId: userId });
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function markListingStatus(userId, listingId, nextStatus) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM car_listing
       WHERE id = $1
         AND owner_user_id = $2
       FOR UPDATE`,
      [Number(listingId), Number(userId)]
    );
    const listing = current.rows[0] || null;
    if (!listing) {
      await client.query("ROLLBACK");
      return null;
    }

    if (!["active", "sold", "archived"].includes(nextStatus)) {
      const error = new Error("INVALID_CAR_LISTING_STATUS");
      error.status = 400;
      error.code = "INVALID_CAR_LISTING_STATUS";
      throw error;
    }

    if (nextStatus === "active") {
      const active = await hasCarSellerUpgrade(userId, { client });
      if (!active) {
        const error = new Error("CAR_SELLER_SUBSCRIPTION_REQUIRED");
        error.status = 403;
        error.code = "CAR_SELLER_SUBSCRIPTION_REQUIRED";
        throw error;
      }
    }

    const patch = {
      status: nextStatus,
      updated_at: new Date().toISOString(),
      sold_at: nextStatus === "sold" ? new Date().toISOString() : null,
      archived_at: nextStatus === "archived" ? new Date().toISOString() : null,
      hidden_due_subscription_expiry_at: null,
      last_visible_status: null,
    };

    const columns = [];
    const values = [];
    let idx = 1;
    for (const [key, value] of Object.entries(patch)) {
      columns.push(`${key} = $${idx++}`);
      values.push(value);
    }
    values.push(Number(listingId));
    values.push(Number(userId));

    const updated = await client.query(
      `UPDATE car_listing
       SET ${columns.join(", ")}
       WHERE id = $${idx++}
         AND owner_user_id = $${idx}
       RETURNING *`,
      values
    );
    if (!updated.rows[0]) {
      await client.query("ROLLBACK");
      return null;
    }

    await client.query("COMMIT");
    return getListingById(listingId, { viewerUserId: userId });
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}
