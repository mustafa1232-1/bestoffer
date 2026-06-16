import { q } from "../../config/db.js";

export async function findHashtagByNormalizedTag(normalizedTag) {
  const r = await q(
    `SELECT
       h.*,
       COALESCE((
         SELECT COUNT(*)::int
         FROM social_entity_hashtag eh
         WHERE eh.hashtag_id = h.id
       ), 0)::int AS usage_count,
       (
         SELECT MAX(eh.created_at)
         FROM social_entity_hashtag eh
         WHERE eh.hashtag_id = h.id
       ) AS last_used_at
     FROM social_hashtag h
     WHERE normalized_tag = $1
     LIMIT 1`,
    [String(normalizedTag || "").trim().toLowerCase()]
  );
  return r.rows[0] || null;
}

export async function upsertHashtag(tag) {
  const rawTag = String(tag || "").trim().replace(/^#+/, "");
  const normalizedTag = rawTag.toLowerCase();
  const r = await q(
    `INSERT INTO social_hashtag (tag, normalized_tag)
     VALUES ($1, $2)
     ON CONFLICT (normalized_tag)
     DO UPDATE SET tag = EXCLUDED.tag
     RETURNING *`,
    [rawTag, normalizedTag]
  );
  return r.rows[0] || null;
}

export async function replaceEntityHashtags({
  entityType,
  entityId,
  tags,
  createdByUserId,
}) {
  await q(
    `DELETE FROM social_entity_hashtag
     WHERE entity_type = $1
       AND entity_id = $2`,
    [String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  if (!Array.isArray(tags) || tags.length <= 0) return;
  for (const tag of tags) {
    const hashtag = await upsertHashtag(tag);
    if (!hashtag?.id) continue;
    await q(
      `INSERT INTO social_entity_hashtag
        (hashtag_id, entity_type, entity_id, created_by_user_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (hashtag_id, entity_type, entity_id) DO NOTHING`,
      [
        Number(hashtag.id),
        String(entityType || "").trim().toLowerCase(),
        Number(entityId),
        Number(createdByUserId),
      ]
    );
  }
}

export async function replaceEntityMentions({
  entityType,
  entityId,
  mentions,
  mentionedByUserId,
}) {
  await q(
    `DELETE FROM social_mention
     WHERE entity_type = $1
       AND entity_id = $2`,
    [String(entityType || "").trim().toLowerCase(), Number(entityId)]
  );
  if (!Array.isArray(mentions) || mentions.length <= 0) return [];
  const inserted = [];
  for (const mention of mentions) {
    const userId = Number(mention.userId);
    if (!Number.isInteger(userId) || userId <= 0) continue;
    const r = await q(
      `INSERT INTO social_mention
        (entity_type, entity_id, mentioned_user_id, mentioned_by_user_id, display_label)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (entity_type, entity_id, mentioned_user_id)
       DO UPDATE SET display_label = EXCLUDED.display_label
       RETURNING *`,
      [
        String(entityType || "").trim().toLowerCase(),
        Number(entityId),
        userId,
        Number(mentionedByUserId),
        mention.displayLabel == null ? null : String(mention.displayLabel).trim() || null,
      ]
    );
    if (r.rows[0]) inserted.push(r.rows[0]);
  }
  return inserted;
}

export async function replaceEntityTags({
  entityType,
  entityId,
  taggedUserIds,
  taggedByUserId,
}) {
  const normalizedType = String(entityType || "").trim().toLowerCase();
  await q(
    `DELETE FROM social_content_tag
     WHERE entity_type = $1
       AND entity_id = $2`,
    [normalizedType, Number(entityId)]
  );
  if (!Array.isArray(taggedUserIds) || taggedUserIds.length <= 0) return [];
  const inserted = [];
  const seen = new Set();
  for (const rawUserId of taggedUserIds) {
    const userId = Number(rawUserId);
    if (!Number.isInteger(userId) || userId <= 0) continue;
    if (seen.has(userId)) continue;
    seen.add(userId);
    const r = await q(
      `INSERT INTO social_content_tag
        (entity_type, entity_id, tagged_user_id, tagged_by_user_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (entity_type, entity_id, tagged_user_id) DO NOTHING
       RETURNING *`,
      [normalizedType, Number(entityId), userId, Number(taggedByUserId)]
    );
    if (r.rows[0]) inserted.push(r.rows[0]);
  }
  return inserted;
}

export async function listTaggedPostIdsForUser({ userId, limit = 40 }) {
  const r = await q(
    `SELECT DISTINCT entity_id
     FROM social_content_tag
     WHERE tagged_user_id = $1
       AND entity_type IN ('post', 'reel')
     ORDER BY entity_id DESC
     LIMIT $2`,
    [Number(userId), Math.max(1, Math.min(80, Number(limit) || 40))]
  );
  return r.rows.map((row) => Number(row.entity_id)).filter((value) => value > 0);
}
