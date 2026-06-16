import { pool, q } from '../../config/db.js';
import {
  normalizeSectionStatus,
  normalizeSurfaceScope,
} from './sections.constants.js';

function asObj(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function mapSection(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    sectionKey: row.section_key,
    displayName: row.display_name,
    parentSectionKey: row.parent_section_key || null,
    surfaceScope: row.surface_scope,
    status: normalizeSectionStatus(row.status),
    isVisible: row.is_visible === true,
    userMessage: row.user_message || null,
    sortOrder: Number(row.sort_order || 0),
    allowExistingActiveAccess: row.allow_existing_active_access !== false,
    metadata: asObj(row.metadata_json),
    updatedByUserId:
      row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapAudit(row) {
  return {
    id: Number(row.id),
    sectionAvailabilityId: Number(row.section_availability_id),
    sectionKey: row.section_key,
    surfaceScope: row.surface_scope,
    actorUserId: row.actor_user_id == null ? null : Number(row.actor_user_id),
    fromStatus: row.from_status || null,
    toStatus: row.to_status || null,
    oldPayload: asObj(row.old_payload),
    newPayload: asObj(row.new_payload),
    createdAt: row.created_at || null,
  };
}

function sanitizeSectionKey(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^\w]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized;
}

export async function listSectionAvailability({
  surfaceScope = 'user',
  sectionKey = null,
}) {
  const params = [normalizeSurfaceScope(surfaceScope)];
  const filters = ['surface_scope = $1'];
  if (sectionKey) {
    params.push(sanitizeSectionKey(sectionKey));
    filters.push(`section_key = $${params.length}`);
  }
  const result = await q(
    `SELECT *
     FROM app_section_availability
     WHERE ${filters.join(' AND ')}
     ORDER BY sort_order ASC, id ASC`,
    params
  );
  return result.rows.map(mapSection);
}

export async function listSectionAvailabilityAudit({
  surfaceScope = 'user',
  sectionKey = null,
  limit = 80,
}) {
  const params = [normalizeSurfaceScope(surfaceScope)];
  const filters = ['surface_scope = $1'];
  if (sectionKey) {
    params.push(sanitizeSectionKey(sectionKey));
    filters.push(`section_key = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(200, Number(limit) || 80)));
  const result = await q(
    `SELECT *
     FROM app_section_availability_audit
     WHERE ${filters.join(' AND ')}
     ORDER BY created_at DESC, id DESC
     LIMIT $${params.length}`,
    params
  );
  return result.rows.map(mapAudit);
}

export async function upsertSectionAvailability({
  sectionKey,
  displayName,
  parentSectionKey = null,
  surfaceScope = 'user',
  status = 'open',
  isVisible = true,
  userMessage = null,
  sortOrder = 0,
  allowExistingActiveAccess = true,
  metadata = {},
  actorUserId = null,
}) {
  const key = sanitizeSectionKey(sectionKey);
  const scope = normalizeSurfaceScope(surfaceScope);
  const normalizedParent = sanitizeSectionKey(parentSectionKey);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const currentR = await client.query(
      `SELECT *
       FROM app_section_availability
       WHERE surface_scope = $1
         AND section_key = $2
       LIMIT 1
       FOR UPDATE`,
      [scope, key]
    );
    const current = currentR.rows[0] || null;
    const oldPayload = mapSection(current);
    let row = null;
    if (current) {
      const updatedR = await client.query(
        `UPDATE app_section_availability
         SET
           display_name = $3,
           parent_section_key = $4,
           status = $5,
           is_visible = $6,
           user_message = $7,
           sort_order = $8,
           allow_existing_active_access = $9,
           metadata_json = $10::jsonb,
           updated_by_user_id = $11,
           updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [
          Number(current.id),
          scope,
          displayName,
          normalizedParent || null,
          normalizeSectionStatus(status),
          isVisible === true,
          userMessage || null,
          Math.max(0, Number(sortOrder) || 0),
          allowExistingActiveAccess !== false,
          JSON.stringify(asObj(metadata)),
          actorUserId == null ? null : Number(actorUserId),
        ]
      );
      row = updatedR.rows[0] || null;
    } else {
      const insertR = await client.query(
        `INSERT INTO app_section_availability (
           section_key,
           display_name,
           parent_section_key,
           surface_scope,
           status,
           is_visible,
           user_message,
           sort_order,
           allow_existing_active_access,
           metadata_json,
           updated_by_user_id,
           created_at,
           updated_at
         )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11,NOW(),NOW())
         RETURNING *`,
        [
          key,
          displayName,
          normalizedParent || null,
          scope,
          normalizeSectionStatus(status),
          isVisible === true,
          userMessage || null,
          Math.max(0, Number(sortOrder) || 0),
          allowExistingActiveAccess !== false,
          JSON.stringify(asObj(metadata)),
          actorUserId == null ? null : Number(actorUserId),
        ]
      );
      row = insertR.rows[0] || null;
    }
    if (row) {
      const newPayload = mapSection(row);
      await client.query(
        `INSERT INTO app_section_availability_audit (
           section_availability_id,
           section_key,
           surface_scope,
           actor_user_id,
           from_status,
           to_status,
           old_payload,
           new_payload,
           created_at
         )
         VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,NOW())`,
        [
          Number(row.id),
          row.section_key,
          row.surface_scope,
          actorUserId == null ? null : Number(actorUserId),
          oldPayload?.status || null,
          normalizeSectionStatus(row.status),
          JSON.stringify(oldPayload || {}),
          JSON.stringify(newPayload || {}),
        ]
      );
    }
    await client.query('COMMIT');
    return mapSection(row);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore rollback failure
    }
    throw error;
  } finally {
    client.release();
  }
}
