import { deriveBasmayaHierarchy } from "../../shared/utils/basmaya-address.js";

import * as repo from "./feed.discovery.repo.js";

function mapSuggestedUserRow(row, viewerUserId) {
  const hierarchy = deriveBasmayaHierarchy({
    block: row.block,
    buildingNumber: row.building_number,
    apartment: row.apartment,
  });
  return {
    id: Number(row.id),
    fullName: row.full_name || "",
    imageUrl: row.image_url || null,
    phone: "",
    role: row.role || "user",
    relation: {
      state: String(row.status || "").trim().toLowerCase() || "none",
      rawStatus: String(row.status || "").trim().toLowerCase() || null,
      requestDirection: null,
      canChat: false,
      canCall: false,
      canSendRequest: !String(row.status || "").trim(),
      blockedByMe: false,
      blockedByOther: false,
      otherUserId: Number(row.id),
    },
    recommendation: {
      hasMutuals: row.has_mutuals === true,
      recentPostsCount: Number(row.recent_posts_count || 0),
      locality: {
        block: hierarchy.block || null,
        compound: hierarchy.compound || null,
        building: hierarchy.building || null,
      },
    },
  };
}

export async function listSuggestedPeople({ viewerUserId, limit = 18 }) {
  const rows = await repo.listSuggestedPeopleCandidates({ viewerUserId, limit });
  return {
    users: rows.map((row) => mapSuggestedUserRow(row, viewerUserId)),
  };
}
