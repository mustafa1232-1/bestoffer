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
    ownerPhone: row.owner_phone || null,
    purpose: String(row.purpose || ""),
    status: String(row.status || ""),
    title: String(row.title || ""),
    description: row.description || null,
    areaSqm: Number(row.area_sqm || 0),
    bankSettlementAmount: Number(row.bank_settlement_amount || 0),
    bankSettlementMode: String(row.bank_settlement_mode || "none"),
    furnished: row.furnished === true,
    furnishingDescription: row.furnishing_description || null,
    phone: row.phone || null,
    price: Number(row.price || 0),
    city: row.city || null,
    block: row.block || null,
    buildingNumber: row.building_number || null,
    apartmentNumber: row.apartment_number || null,
    roomsCount: row.rooms_count == null ? null : Number(row.rooms_count),
    bathroomsCount:
      row.bathrooms_count == null ? null : Number(row.bathrooms_count),
    floorNumber: row.floor_number == null ? null : Number(row.floor_number),
    paymentMethod: String(row.payment_method || "cash"),
    isFeatured: row.is_featured === true,
    viewCount: Number(row.view_count || 0),
    isSaved: row.is_saved === true,
    detailsJson: row.details_json || {},
    reviewNote: row.review_note || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    lastVisibleStatus: row.last_visible_status || null,
    hiddenDueSubscriptionExpiryAt: row.hidden_due_subscription_expiry_at || null,
    soldAt: row.sold_at || null,
    rentedAt: row.rented_at || null,
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
    ? listingIds
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0)
    : [];
  if (!ids.length) return new Map();
  const run = txRunner(client);
  const r = await run(
    `SELECT *
     FROM real_estate_listing_media
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

async function listSavedIdsForUser(client, userId, listingIds) {
  const ids = Array.isArray(listingIds)
    ? listingIds
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0)
    : [];
  if (!userId || !ids.length) return new Set();
  const run = txRunner(client);
  const r = await run(
    `SELECT listing_id
     FROM real_estate_saved_listing
     WHERE user_id = $1
       AND listing_id = ANY($2::bigint[])`,
    [Number(userId), ids]
  );
  return new Set(r.rows.map((row) => Number(row.listing_id)));
}

async function hydrateListings(client, rows, { viewerUserId = null } = {}) {
  const ids = rows.map((row) => row.id);
  const [mediaMap, savedIds] = await Promise.all([
    listMediaForListings(client, ids),
    listSavedIdsForUser(client, viewerUserId, ids),
  ]);
  return rows.map((row) =>
    toListingRow({
      ...row,
      is_saved: savedIds.has(Number(row.id)),
      media: mediaMap.get(Number(row.id)) || [],
    })
  );
}

async function recordStatusHistoryTx(
  client,
  listingId,
  previousStatus,
  nextStatus,
  note,
  actorUserId
) {
  await client.query(
    `INSERT INTO real_estate_listing_status_history (
       listing_id,
       previous_status,
       next_status,
       note,
       changed_by_user_id
     )
     VALUES ($1,$2,$3,$4,$5)`,
    [
      Number(listingId),
      previousStatus || null,
      nextStatus,
      note || null,
      actorUserId == null ? null : Number(actorUserId),
    ]
  );
}

function buildListFilters(query = {}, params) {
  const filters = [`l.status = 'active'`];

  if (query.purpose) {
    params.push(query.purpose);
    filters.push(`l.purpose = $${params.length}`);
  }
  if (query.search) {
    params.push(`%${query.search}%`);
    filters.push(
      `(l.title ILIKE $${params.length}
        OR COALESCE(l.description, '') ILIKE $${params.length}
        OR COALESCE(l.city, '') ILIKE $${params.length}
        OR COALESCE(l.block, '') ILIKE $${params.length}
        OR COALESCE(l.building_number, '') ILIKE $${params.length})`
    );
  }
  if (query.city) {
    params.push(`%${query.city}%`);
    filters.push(`COALESCE(l.city, '') ILIKE $${params.length}`);
  }
  if (query.block) {
    params.push(`%${query.block}%`);
    filters.push(`COALESCE(l.block, '') ILIKE $${params.length}`);
  }
  if (query.areaSqm) {
    params.push(Number(query.areaSqm));
    filters.push(`l.area_sqm = $${params.length}`);
  }
  if (query.areaMin != null) {
    params.push(Number(query.areaMin));
    filters.push(`l.area_sqm >= $${params.length}`);
  }
  if (query.areaMax != null) {
    params.push(Number(query.areaMax));
    filters.push(`l.area_sqm <= $${params.length}`);
  }
  if (query.furnished !== null && query.furnished !== undefined) {
    params.push(Boolean(query.furnished));
    filters.push(`l.furnished = $${params.length}`);
  }
  if (query.availableOnly === true) {
    filters.push(`l.status = 'active'`);
  }
  if (query.featuredOnly === true) {
    filters.push(`l.is_featured = TRUE`);
  }
  if (query.bankSettlementMode) {
    params.push(query.bankSettlementMode);
    filters.push(`l.bank_settlement_mode = $${params.length}`);
  }
  if (query.paymentMethod) {
    params.push(query.paymentMethod);
    filters.push(`l.payment_method = $${params.length}`);
  }
  if (query.minPrice != null) {
    params.push(Number(query.minPrice));
    filters.push(`l.price >= $${params.length}`);
  }
  if (query.maxPrice != null) {
    params.push(Number(query.maxPrice));
    filters.push(`l.price <= $${params.length}`);
  }
  if (query.roomsCount != null) {
    params.push(Number(query.roomsCount));
    filters.push(`COALESCE(l.rooms_count, 0) >= $${params.length}`);
  }
  if (query.bathroomsCount != null) {
    params.push(Number(query.bathroomsCount));
    filters.push(`COALESCE(l.bathrooms_count, 0) >= $${params.length}`);
  }
  if (query.floorMin != null) {
    params.push(Number(query.floorMin));
    filters.push(`COALESCE(l.floor_number, 0) >= $${params.length}`);
  }
  if (query.floorMax != null) {
    params.push(Number(query.floorMax));
    filters.push(`COALESCE(l.floor_number, 0) <= $${params.length}`);
  }

  return filters;
}

function listOrderBy(sort) {
  if (sort === "oldest") return "l.created_at ASC, l.id ASC";
  if (sort === "price_low") return "l.price ASC, l.created_at DESC";
  if (sort === "price_high") return "l.price DESC, l.created_at DESC";
  if (sort === "most_viewed") return "l.view_count DESC, l.created_at DESC";
  return "l.created_at DESC, l.id DESC";
}

export async function hasPropertySellerUpgrade(userId, { client = null } = {}) {
  const [propertySellerMonthly, premiumMonthly] = await Promise.all([
    hasPaidUpgrade(userId, "property_seller_monthly", { client }),
    hasPaidUpgrade(userId, "premium_monthly", { client }),
  ]);
  return propertySellerMonthly || premiumMonthly;
}

export async function syncVisibilityForOwner(userId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const active = await hasPropertySellerUpgrade(userId, { client });
    const changedRows = [];

    if (!active) {
      const r = await client.query(
        `UPDATE real_estate_listing
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
        await recordStatusHistoryTx(
          client,
          row.id,
          "active",
          "hidden_due_subscription_expiry",
          "subscription_expired",
          Number(userId)
        );
        changedRows.push(Number(row.id));
      }
    } else {
      const r = await client.query(
        `UPDATE real_estate_listing
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
        await recordStatusHistoryTx(
          client,
          row.id,
          "hidden_due_subscription_expiry",
          "active",
          "subscription_restored",
          Number(userId)
        );
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

export async function listPublicListings(query = {}, { viewerUserId = null } = {}) {
  const client = await pool.connect();
  try {
    const params = [];
    const filters = buildListFilters(query, params);
    const orderBy = listOrderBy(String(query.sort || "recent").trim().toLowerCase());

    params.push(Math.max(1, Math.min(100, Number(query.limit) || 24)));
    params.push(Math.max(0, Number(query.offset) || 0));

    const r = await client.query(
      `SELECT l.*, u.full_name AS owner_full_name, u.phone AS owner_phone
       FROM real_estate_listing l
       LEFT JOIN app_user u ON u.id = l.owner_user_id
       WHERE ${filters.join(" AND ")}
       ORDER BY ${orderBy}
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return await hydrateListings(client, r.rows, { viewerUserId });
  } finally {
    client.release();
  }
}

export async function getListingById(listingId, { viewerUserId = null } = {}) {
  const id = toInt(listingId);
  if (!id) return null;
  const client = await pool.connect();
  try {
    const r = await client.query(
      `SELECT l.*, u.full_name AS owner_full_name, u.phone AS owner_phone
       FROM real_estate_listing l
       LEFT JOIN app_user u ON u.id = l.owner_user_id
       WHERE l.id = $1
       LIMIT 1`,
      [id]
    );
    const row = r.rows[0] || null;
    if (!row) return null;

    const isOwner =
      viewerUserId != null && Number(viewerUserId) === Number(row.owner_user_id);

    if (!isOwner && row.status !== "active") return null;

    if (!isOwner && row.status === "active") {
      await client.query(
        `UPDATE real_estate_listing
         SET view_count = view_count + 1,
             updated_at = NOW()
         WHERE id = $1`,
        [id]
      );
      row.view_count = Number(row.view_count || 0) + 1;
    }

    const hydrated = await hydrateListings(client, [row], { viewerUserId });
    return hydrated[0] || null;
  } finally {
    client.release();
  }
}

export async function listSimilarListings(
  listingId,
  { viewerUserId = null, limit = 6 } = {}
) {
  const listing = await getListingById(listingId, { viewerUserId });
  if (!listing || listing.status !== "active") return [];
  const client = await pool.connect();
  try {
    const params = [listing.id, listing.purpose, listing.block || ""];
    const filters = [
      "l.id <> $1",
      "l.status = 'active'",
      "l.purpose = $2",
    ];
    if (listing.city) {
      params.push(listing.city);
      filters.push(`l.city = $${params.length}`);
    }
    params.push(Math.max(1, Math.min(12, Number(limit) || 6)));
    const limitParamIndex = params.length;
    const r = await client.query(
      `SELECT l.*, u.full_name AS owner_full_name, u.phone AS owner_phone
       FROM real_estate_listing l
       LEFT JOIN app_user u ON u.id = l.owner_user_id
       WHERE ${filters.join(" AND ")}
       ORDER BY
         CASE WHEN COALESCE(l.block, '') = $3 THEN 0 ELSE 1 END,
         l.is_featured DESC,
         ABS(l.price - ${Number(listing.price)}) ASC,
         l.created_at DESC
       LIMIT $${limitParamIndex}`,
      params
    );
    return await hydrateListings(client, r.rows, { viewerUserId });
  } finally {
    client.release();
  }
}

export async function listSavedListings(
  userId,
  { limit = 40, offset = 0 } = {}
) {
  const client = await pool.connect();
  try {
    const r = await client.query(
      `SELECT l.*, u.full_name AS owner_full_name, u.phone AS owner_phone, TRUE AS is_saved
       FROM real_estate_saved_listing s
       JOIN real_estate_listing l ON l.id = s.listing_id
       LEFT JOIN app_user u ON u.id = l.owner_user_id
       WHERE s.user_id = $1
         AND l.status = 'active'
       ORDER BY s.created_at DESC, s.listing_id DESC
       LIMIT $2 OFFSET $3`,
      [
        Number(userId),
        Math.max(1, Math.min(100, Number(limit) || 40)),
        Math.max(0, Number(offset) || 0),
      ]
    );
    return await hydrateListings(client, r.rows, { viewerUserId: userId });
  } finally {
    client.release();
  }
}

export async function saveListing(userId, listingId) {
  const id = toInt(listingId);
  if (!id) return null;
  const existing = await getListingById(id, { viewerUserId: userId });
  if (!existing || existing.status !== "active") return null;
  await q(
    `INSERT INTO real_estate_saved_listing (user_id, listing_id)
     VALUES ($1, $2)
     ON CONFLICT (user_id, listing_id) DO NOTHING`,
    [Number(userId), id]
  );
  return { listingId: id, saved: true };
}

export async function unsaveListing(userId, listingId) {
  const id = toInt(listingId);
  if (!id) return null;
  await q(
    `DELETE FROM real_estate_saved_listing
     WHERE user_id = $1
       AND listing_id = $2`,
    [Number(userId), id]
  );
  return { listingId: id, saved: false };
}

export async function getWorkspace(userId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const syncChanged = await syncVisibilityForOwner(userId);
    const active = await hasPropertySellerUpgrade(userId, { client });
    const counts = await client.query(
      `SELECT status, COUNT(*)::int AS total
       FROM real_estate_listing
       WHERE owner_user_id = $1
       GROUP BY status`,
      [Number(userId)]
    );
    const rows = await client.query(
      `SELECT *
       FROM real_estate_listing
       WHERE owner_user_id = $1
       ORDER BY created_at DESC, id DESC`,
      [Number(userId)]
    );
    const hydrated = await hydrateListings(client, rows.rows, {
      viewerUserId: userId,
    });
    await client.query("COMMIT");
    return {
      entitlement: {
        propertySellerMonthly: active,
      },
      syncChangedListingIds: syncChanged,
      counts: counts.rows.reduce((acc, row) => {
        acc[String(row.status)] = Number(row.total || 0);
        return acc;
      }, {}),
      listings: hydrated,
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
    const active = await hasPropertySellerUpgrade(userId, { client });
    if (!active) {
      const error = new Error("PROPERTY_SELLER_SUBSCRIPTION_REQUIRED");
      error.status = 403;
      error.code = "PROPERTY_SELLER_SUBSCRIPTION_REQUIRED";
      throw error;
    }

    const insert = await client.query(
      `INSERT INTO real_estate_listing (
         owner_user_id,
         purpose,
         status,
         title,
         description,
         area_sqm,
         bank_settlement_amount,
         bank_settlement_mode,
         furnished,
         furnishing_description,
         phone,
         price,
         city,
         block,
         building_number,
         apartment_number,
         rooms_count,
         bathrooms_count,
         floor_number,
         payment_method,
         details_json
       )
       VALUES (
         $1,$2,'pending_admin_review',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,
         $14,$15,$16,$17,$18,$19,$20::jsonb
       )
       RETURNING *`,
      [
        Number(userId),
        dto.purpose,
        dto.title,
        dto.description,
        Number(dto.areaSqm),
        Number(dto.bankSettlementAmount || 0),
        dto.bankSettlementMode || "none",
        dto.furnished === true,
        dto.furnishingDescription,
        dto.phone,
        Number(dto.price || 0),
        dto.city || null,
        dto.block || null,
        dto.buildingNumber || null,
        dto.apartmentNumber || null,
        dto.roomsCount == null ? null : Number(dto.roomsCount),
        dto.bathroomsCount == null ? null : Number(dto.bathroomsCount),
        dto.floorNumber == null ? null : Number(dto.floorNumber),
        dto.paymentMethod || "cash",
        JSON.stringify(dto.detailsJson || {}),
      ]
    );
    const listing = insert.rows[0];

    for (const media of toMediaRows(files)) {
      await client.query(
        `INSERT INTO real_estate_listing_media (listing_id, image_url, sort_order)
         VALUES ($1,$2,$3)`,
        [Number(listing.id), media.imageUrl, media.sortOrder]
      );
    }

    await recordStatusHistoryTx(
      client,
      listing.id,
      null,
      "pending_admin_review",
      "created",
      Number(userId)
    );

    await client.query("COMMIT");
    const hydrated = await getListingById(listing.id, { viewerUserId: userId });
    return hydrated;
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
    const active = await hasPropertySellerUpgrade(userId, { client });
    const current = await client.query(
      `SELECT *
       FROM real_estate_listing
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

    if (
      ["active", "pending_admin_review", "hidden_due_subscription_expiry"].includes(
        listing.status
      ) &&
      !active
    ) {
      const error = new Error("PROPERTY_SELLER_SUBSCRIPTION_REQUIRED");
      error.status = 403;
      error.code = "PROPERTY_SELLER_SUBSCRIPTION_REQUIRED";
      throw error;
    }

    const columns = {
      purpose: "purpose",
      title: "title",
      description: "description",
      areaSqm: "area_sqm",
      bankSettlementAmount: "bank_settlement_amount",
      bankSettlementMode: "bank_settlement_mode",
      paymentMethod: "payment_method",
      furnished: "furnished",
      furnishingDescription: "furnishing_description",
      phone: "phone",
      price: "price",
      city: "city",
      block: "block",
      buildingNumber: "building_number",
      apartmentNumber: "apartment_number",
      roomsCount: "rooms_count",
      bathroomsCount: "bathrooms_count",
      floorNumber: "floor_number",
      detailsJson: "details_json",
    };
    const values = [];
    const sets = [];
    let idx = 1;
    for (const [key, column] of Object.entries(columns)) {
      if (!Object.prototype.hasOwnProperty.call(dto, key)) continue;
      values.push(
        key === "detailsJson" ? JSON.stringify(dto[key] || {}) : dto[key]
      );
      sets.push(`${column} = $${idx++}`);
    }
    if (sets.length > 0) {
      sets.push(`updated_at = NOW()`);
      values.push(Number(listingId));
      values.push(Number(userId));
      const updated = await client.query(
        `UPDATE real_estate_listing
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
      await client.query(`DELETE FROM real_estate_listing_media WHERE listing_id = $1`, [
        Number(listingId),
      ]);
      for (const media of toMediaRows(files)) {
        await client.query(
          `INSERT INTO real_estate_listing_media (listing_id, image_url, sort_order)
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

export async function markListingStatus(userId, listingId, nextStatus, note = null) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM real_estate_listing
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

    if (!["sold", "rented", "archived", "active"].includes(nextStatus)) {
      const error = new Error("INVALID_LISTING_STATUS");
      error.status = 400;
      error.code = "INVALID_LISTING_STATUS";
      throw error;
    }

    if (nextStatus === "active") {
      const active = await hasPropertySellerUpgrade(userId, { client });
      if (!active) {
        const error = new Error("PROPERTY_SELLER_SUBSCRIPTION_REQUIRED");
        error.status = 403;
        error.code = "PROPERTY_SELLER_SUBSCRIPTION_REQUIRED";
        throw error;
      }
    }

    const patch = {
      status: nextStatus,
      review_note: note || listing.review_note || null,
      updated_at: new Date().toISOString(),
      sold_at: nextStatus === "sold" ? new Date().toISOString() : null,
      rented_at: nextStatus === "rented" ? new Date().toISOString() : null,
      archived_at: nextStatus === "archived" ? new Date().toISOString() : null,
      hidden_due_subscription_expiry_at:
        nextStatus === "active" ? null : listing.hidden_due_subscription_expiry_at,
    };

    const columns = [];
    const values = [];
    let idx = 1;
    for (const [key, value] of Object.entries(patch)) {
      columns.push(`${key} = $${idx++}`);
      values.push(value);
    }
    if (nextStatus === "active") {
      columns.push(`last_visible_status = NULL`);
    }
    values.push(Number(listingId));
    values.push(Number(userId));

    const updated = await client.query(
      `UPDATE real_estate_listing
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

    await recordStatusHistoryTx(
      client,
      listingId,
      listing.status,
      nextStatus,
      note,
      Number(userId)
    );

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

export async function listPendingListings({ limit = 30, offset = 0 } = {}) {
  const r = await q(
    `SELECT
       l.*,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone
     FROM real_estate_listing l
     JOIN app_user u ON u.id = l.owner_user_id
     WHERE l.status = 'pending_admin_review'
     ORDER BY l.created_at DESC, l.id DESC
     LIMIT $1 OFFSET $2`,
    [
      Math.max(1, Math.min(100, Number(limit) || 30)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return hydrateListings(null, r.rows);
}

export async function countPendingListings() {
  const r = await q(
    `SELECT COUNT(*)::int AS total
     FROM real_estate_listing
     WHERE status = 'pending_admin_review'`
  );
  return Number(r.rows[0]?.total || 0);
}

export async function adminReviewListing(listingId, { status, note, actorUserId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT *
       FROM real_estate_listing
       WHERE id = $1
       FOR UPDATE`,
      [Number(listingId)]
    );
    const listing = current.rows[0] || null;
    if (!listing) {
      await client.query("ROLLBACK");
      return null;
    }

    let nextStatus = status;
    if (status === "approved") {
      const active = await hasPropertySellerUpgrade(listing.owner_user_id, { client });
      nextStatus = active ? "active" : "hidden_due_subscription_expiry";
    } else if (status === "rejected") {
      nextStatus = "archived";
    }

    const patch = {
      status: nextStatus,
      review_note: note || null,
      reviewed_by_user_id: Number(actorUserId),
      reviewed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      hidden_due_subscription_expiry_at:
        nextStatus === "hidden_due_subscription_expiry"
          ? new Date().toISOString()
          : null,
      archived_at: nextStatus === "archived" ? new Date().toISOString() : null,
      last_visible_status:
        nextStatus === "hidden_due_subscription_expiry" ? "active" : null,
    };

    const columns = [];
    const values = [];
    let idx = 1;
    for (const [key, value] of Object.entries(patch)) {
      columns.push(`${key} = $${idx++}`);
      values.push(value);
    }
    values.push(Number(listingId));

    const updated = await client.query(
      `UPDATE real_estate_listing
       SET ${columns.join(", ")}
       WHERE id = $${idx}
       RETURNING *`,
      values
    );
    if (!updated.rows[0]) {
      await client.query("ROLLBACK");
      return null;
    }

    await recordStatusHistoryTx(
      client,
      listingId,
      listing.status,
      nextStatus,
      note,
      Number(actorUserId)
    );

    await client.query("COMMIT");
    return getListingById(listingId, { viewerUserId: listing.owner_user_id });
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
