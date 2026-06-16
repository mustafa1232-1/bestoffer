import { q } from "../../config/db.js";

function asPositiveInt(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

export async function listSavedCollectionsByUser(userId) {
  const r = await q(
    `SELECT
       c.*,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_saved_collection_item ci
         WHERE ci.collection_id = c.id
       ), 0)::int AS items_count
     FROM social_saved_collection c
     WHERE c.user_id = $1
     ORDER BY COALESCE(c.system_key, ''), c.updated_at DESC, c.id DESC`,
    [Number(userId)]
  );
  return r.rows;
}

export async function createSavedCollection({ userId, title, description = null, systemKey = null }) {
  const r = await q(
    `INSERT INTO social_saved_collection
      (user_id, title, description, system_key)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [
      Number(userId),
      String(title || "").trim(),
      description == null ? null : String(description).trim() || null,
      systemKey == null ? null : String(systemKey).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function updateSavedCollection({
  userId,
  collectionId,
  title,
  description = null,
}) {
  const r = await q(
    `UPDATE social_saved_collection
     SET title = $3,
         description = $4,
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
     RETURNING *`,
    [
      Number(collectionId),
      Number(userId),
      String(title || "").trim(),
      description == null ? null : String(description).trim() || null,
    ]
  );
  return r.rows[0] || null;
}

export async function deleteSavedCollection({ userId, collectionId }) {
  const r = await q(
    `DELETE FROM social_saved_collection
     WHERE id = $1
       AND user_id = $2
     RETURNING id`,
    [Number(collectionId), Number(userId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function findSavedItem({ userId, entityType, entityId }) {
  const r = await q(
    `SELECT *
     FROM social_saved_item
     WHERE user_id = $1
       AND entity_type = $2
       AND entity_id = $3
     LIMIT 1`,
    [Number(userId), String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  return r.rows[0] || null;
}

export async function insertSavedItem({ userId, entityType, entityId }) {
  const r = await q(
    `INSERT INTO social_saved_item (user_id, entity_type, entity_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, entity_type, entity_id)
     DO UPDATE SET entity_id = EXCLUDED.entity_id
     RETURNING *`,
    [Number(userId), String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  return r.rows[0] || null;
}

export async function deleteSavedItem({ userId, entityType, entityId }) {
  const r = await q(
    `DELETE FROM social_saved_item
     WHERE user_id = $1
       AND entity_type = $2
       AND entity_id = $3
     RETURNING id`,
    [Number(userId), String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  return (r.rowCount || 0) > 0;
}

export async function replaceSavedItemCollections({
  userId,
  savedItemId,
  collectionIds = [],
}) {
  const normalizedCollectionIds = Array.isArray(collectionIds)
    ? [...new Set(collectionIds.map((value) => asPositiveInt(value)).filter((value) => value != null))]
    : [];
  await q(
    `DELETE FROM social_saved_collection_item ci
     USING social_saved_collection c
     WHERE ci.collection_id = c.id
       AND ci.saved_item_id = $1
       AND c.user_id = $2`,
    [Number(savedItemId), Number(userId)]
  );
  if (normalizedCollectionIds.length <= 0) return;
  await q(
    `INSERT INTO social_saved_collection_item (collection_id, saved_item_id)
     SELECT c.id, $1
     FROM social_saved_collection c
     WHERE c.user_id = $2
       AND c.id = ANY($3::bigint[])
     ON CONFLICT (collection_id, saved_item_id) DO NOTHING`,
    [Number(savedItemId), Number(userId), normalizedCollectionIds]
  );
}

export async function listSavedItemCollectionIds(savedItemId) {
  const r = await q(
    `SELECT collection_id
     FROM social_saved_collection_item
     WHERE saved_item_id = $1`,
    [Number(savedItemId)]
  );
  return r.rows.map((row) => Number(row.collection_id)).filter((value) => value > 0);
}

export async function listSavedItems({
  userId,
  collectionId = null,
  entityType = null,
  beforeId = null,
  limit = 24,
}) {
  const r = await q(
    `SELECT DISTINCT si.*
     FROM social_saved_item si
     LEFT JOIN social_saved_collection_item ci
       ON ci.saved_item_id = si.id
     WHERE si.user_id = $1
       AND ($2::bigint IS NULL OR ci.collection_id = $2::bigint)
       AND ($3::text IS NULL OR si.entity_type = $3::text)
       AND ($4::bigint IS NULL OR si.id < $4::bigint)
     ORDER BY si.id DESC
     LIMIT $5`,
    [
      Number(userId),
      collectionId == null ? null : Number(collectionId),
      entityType == null ? null : String(entityType).trim().toLowerCase(),
      beforeId == null ? null : Number(beforeId),
      Math.max(1, Math.min(60, Number(limit) || 24)),
    ]
  );
  return r.rows;
}
