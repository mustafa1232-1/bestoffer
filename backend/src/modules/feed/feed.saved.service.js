import { AppError } from "../../shared/utils/errors.js";

import * as discoveryRepo from "./feed.discovery.repo.js";
import { mapSavedCollectionRow, mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as repo from "./feed.saved.repo.js";

function normalizeSavedEntityType(entityType) {
  const normalized = String(entityType || "").trim().toLowerCase();
  if (normalized === "reel" || normalized === "video") return "reel";
  if (normalized === "merchant_review" || normalized === "review") return "review";
  return "post";
}

export async function listSavedCollections(userId) {
  const rows = await repo.listSavedCollectionsByUser(userId);
  return { collections: rows.map(mapSavedCollectionRow) };
}

export async function createSavedCollection(userId, dto) {
  const created = await repo.createSavedCollection({
    userId,
    title: dto.title,
    description: dto.description,
    systemKey: dto.systemKey,
  });
  return { collection: mapSavedCollectionRow(created) };
}

export async function updateSavedCollection({ userId, collectionId, dto }) {
  const updated = await repo.updateSavedCollection({
    userId,
    collectionId,
    title: dto.title,
    description: dto.description,
  });
  if (!updated) throw new AppError("SAVED_COLLECTION_NOT_FOUND", { status: 404 });
  return { collection: mapSavedCollectionRow(updated) };
}

export async function deleteSavedCollection({ userId, collectionId }) {
  const ok = await repo.deleteSavedCollection({ userId, collectionId });
  if (!ok) throw new AppError("SAVED_COLLECTION_NOT_FOUND", { status: 404 });
  return { ok: true };
}

export async function toggleSavedContent({ userId, dto, viewerScopeCodes }) {
  const entityType = normalizeSavedEntityType(dto.entityType);
  const visibleRows = await discoveryRepo.listVisiblePostsByIds({
    viewerUserId: userId,
    viewerBlockCode: viewerScopeCodes?.blockCode || null,
    viewerCompoundCode: viewerScopeCodes?.compoundCode || null,
    viewerBuildingCode: viewerScopeCodes?.buildingCode || null,
    postIds: [dto.entityId],
  });
  if (visibleRows.length <= 0) {
    throw new AppError("SOCIAL_CONTENT_NOT_FOUND", { status: 404 });
  }
  const existing = await repo.findSavedItem({ userId, entityType, entityId: dto.entityId });
  if (existing) {
    await repo.deleteSavedItem({ userId, entityType, entityId: dto.entityId });
    return { saved: false, itemId: Number(existing.id) };
  }
  const inserted = await repo.insertSavedItem({ userId, entityType, entityId: dto.entityId });
  await repo.replaceSavedItemCollections({
    userId,
    savedItemId: inserted.id,
    collectionIds: dto.collectionIds,
  });
  return {
    saved: true,
    itemId: Number(inserted.id),
  };
}

export async function listSavedContent({ userId, query, viewerScopeCodes }) {
  const rows = await repo.listSavedItems({
    userId,
    collectionId: query.collectionId,
    entityType: query.entityType,
    beforeId: query.beforeId,
    limit: query.limit,
  });
  const entityIds = rows.map((row) => Number(row.entity_id)).filter((value) => value > 0);
  const contentRows = await discoveryRepo.listVisiblePostsByIds({
    viewerUserId: userId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    postIds: entityIds,
  });
  const contentById = new Map(contentRows.map((row) => [Number(row.id), mapSocialPostProductRow(row)]));
  const items = [];
  for (const row of rows) {
    const savedId = Number(row.id);
    const entityId = Number(row.entity_id);
    const content = contentById.get(entityId);
    if (!content) continue;
    items.push({
      id: savedId,
      entityType: row.entity_type,
      entityId,
      createdAt: row.created_at || null,
      collectionIds: await repo.listSavedItemCollectionIds(savedId),
      content,
    });
  }
  return {
    items,
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}
