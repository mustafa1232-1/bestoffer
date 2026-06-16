import { createManyNotifications } from "../notifications/notifications.repo.js";

import * as discoveryRepo from "./feed.discovery.repo.js";
import { mapHashtagRow, mapSocialPostProductRow } from "./feed.product.mappers.js";
import * as repo from "./feed.tags.repo.js";

const HASHTAG_REGEX = /(^|[\s\p{P}])#([\p{L}\p{N}_]{2,64})/gu;
const MENTION_REGEX = /@\[(.+?)\]\((\d+)\)/g;

export function extractHashtags(text) {
  const source = String(text || "");
  const out = new Set();
  for (const match of source.matchAll(HASHTAG_REGEX)) {
    const tag = String(match[2] || "").trim().replace(/^#+/, "");
    if (tag) out.add(tag);
  }
  return [...out];
}

export function extractMentions(text) {
  const source = String(text || "");
  const out = [];
  for (const match of source.matchAll(MENTION_REGEX)) {
    const displayLabel = String(match[1] || "").trim();
    const userId = Number(match[2]);
    if (!Number.isInteger(userId) || userId <= 0) continue;
    out.push({ userId, displayLabel: displayLabel || null });
  }
  return out;
}

export function extractMentionsFromStoryStyle(storyStyle) {
  if (!storyStyle || typeof storyStyle !== "object" || Array.isArray(storyStyle)) {
    return [];
  }
  const layers = Array.isArray(storyStyle.layers) ? storyStyle.layers : [];
  const out = [];
  const seen = new Set();
  for (const layer of layers) {
    if (!layer || typeof layer !== "object" || Array.isArray(layer)) continue;
    const type = String(layer.type || "").trim().toLowerCase();
    if (type !== "mention") continue;
    const userId = Number(layer.mentionedUserId ?? layer.mentioned_user_id);
    if (!Number.isInteger(userId) || userId <= 0) continue;
    const displayLabel = String(
      layer.displayLabel ?? layer.display_label ?? layer.text ?? "",
    )
      .trim()
      .replace(/^@+/, "");
    const key = `${userId}:${displayLabel}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ userId, displayLabel: displayLabel || null });
  }
  return out;
}

export function buildStoryTextForTagSync({ text, storyStyle }) {
  const caption = String(text || "").trim();
  const layerMentions = extractMentionsFromStoryStyle(storyStyle);
  if (layerMentions.length <= 0) return caption;
  const mentionMarkup = layerMentions
    .map((item) => `@[${item.displayLabel || "user"}](${item.userId})`)
    .join(" ");
  return [caption, mentionMarkup].filter(Boolean).join(" ").trim();
}

export async function syncTagsAndMentionsForEntity({
  entityType,
  entityId,
  text,
  actorUserId,
  notificationTarget = null,
}) {
  const hashtags = extractHashtags(text);
  const mentions = extractMentions(text);
  await repo.replaceEntityHashtags({
    entityType,
    entityId,
    tags: hashtags,
    createdByUserId: actorUserId,
  });
  const insertedMentions = await repo.replaceEntityMentions({
    entityType,
    entityId,
    mentions,
    mentionedByUserId: actorUserId,
  });
  if (insertedMentions.length > 0) {
    await createManyNotifications(
      insertedMentions
        .filter((item) => Number(item.mentioned_user_id) !== Number(actorUserId))
        .map((item) => ({
          userId: Number(item.mentioned_user_id),
          title: "تمت الإشارة إليك",
          body: "تمت الإشارة إلى حسابك داخل محتوى اجتماعي جديد.",
          type: "social.mention.created",
          payload: {
            target:
              notificationTarget ||
              (String(entityType || "").trim().toLowerCase() === "story" ||
              String(entityType || "").trim().toLowerCase() === "story_comment"
                ? "social_story"
                : String(entityType || "").trim().toLowerCase() === "reel"
                ? "social_reel"
                : "social_post"),
            entityType,
            entityId: Number(entityId),
            mentionedByUserId: Number(actorUserId),
          },
        }))
    );
  }
  return {
    hashtags,
    mentions: insertedMentions.map((item) => ({
      id: Number(item.id),
      userId: Number(item.mentioned_user_id),
      displayLabel: item.display_label || null,
    })),
  };
}

export async function syncExplicitContentTags({
  entityType,
  entityId,
  taggedUserIds,
  actorUserId,
}) {
  const normalizedType = String(entityType || "").trim().toLowerCase();
  const inserted = await repo.replaceEntityTags({
    entityType: normalizedType,
    entityId,
    taggedUserIds,
    taggedByUserId: actorUserId,
  });
  if (inserted.length > 0) {
    await createManyNotifications(
      inserted
        .filter((item) => Number(item.tagged_user_id) !== Number(actorUserId))
        .map((item) => ({
          userId: Number(item.tagged_user_id),
          title: "تمت إضافتك إلى محتوى",
          body: "تمت الإشارة إلى حسابك داخل منشور أو ريل.",
          type: "social.tag.created",
          payload: {
            target: normalizedType === "reel" ? "social_reel" : "social_post",
            entityType: normalizedType,
            entityId: Number(entityId),
            actorUserId: Number(actorUserId),
          },
        }))
    );
  }
  return inserted;
}

export async function listHashtagFeed({
  viewerUserId,
  tag,
  query,
  viewerScopeCodes,
}) {
  const hashtag = await repo.findHashtagByNormalizedTag(tag);
  if (!hashtag) {
    return {
      hashtag: {
        id: 0,
        tag: String(tag || "").trim().replace(/^#+/, ""),
        normalizedTag: String(tag || "").trim().toLowerCase(),
        usageCount: 0,
        lastUsedAt: null,
      },
      posts: [],
      nextCursor: null,
    };
  }
  const rows = await discoveryRepo.listVisiblePostCandidates({
    viewerUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    limit: query.limit,
    beforeId: query.beforeId,
    authorUserId: null,
    postKinds: query.kind ? [query.kind] : null,
    search: "",
    hashtagId: Number(hashtag.id),
    mentionedUserId: null,
  });
  return {
    hashtag: mapHashtagRow(hashtag),
    posts: rows.map(mapSocialPostProductRow),
    nextCursor: rows.length > 0 ? Number(rows[rows.length - 1].id) : null,
  };
}

export async function listTrendingHashtags({ limit = 12 }) {
  const rows = await discoveryRepo.listTrendingHashtags({ limit });
  return { hashtags: rows.map(mapHashtagRow) };
}

export async function listMentionSuggestions({ viewerUserId, query, searchUsers }) {
  const out = await searchUsers(viewerUserId, query);
  return {
    users: Array.isArray(out?.users)
      ? out.users.map((user) => ({
          id: Number(user.id),
          username: user.username || null,
          fullName: user.fullName || "",
          imageUrl: user.imageUrl || null,
          role: user.role || "user",
        }))
      : [],
  };
}

export async function listHashtagSuggestions({ query, limit = 16 }) {
  const normalized = String(query || "").trim().replace(/^#+/, "").toLowerCase();
  if (!normalized) return { hashtags: [] };
  const rows = await discoveryRepo.listTrendingHashtags({
    limit: Math.max(1, Math.min(40, Number(limit) || 16)),
    search: normalized,
  });
  return { hashtags: rows.map(mapHashtagRow) };
}

export async function listTaggedPosts({
  viewerUserId,
  targetUserId,
  viewerScopeCodes,
  limit = 24,
}) {
  const postIds = await repo.listTaggedPostIdsForUser({ userId: targetUserId, limit });
  if (postIds.length <= 0) return { posts: [] };
  const rows = await discoveryRepo.listVisiblePostsByIds({
    viewerUserId,
    viewerBlockCode: viewerScopeCodes.blockCode,
    viewerCompoundCode: viewerScopeCodes.compoundCode,
    viewerBuildingCode: viewerScopeCodes.buildingCode,
    postIds,
  });
  return { posts: rows.map(mapSocialPostProductRow) };
}

