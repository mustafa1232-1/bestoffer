import { deriveBasmayaHierarchy } from "../../shared/utils/basmaya-address.js";

function safeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function computeFreshnessScore(createdAt) {
  const createdMs = new Date(createdAt || 0).getTime();
  if (!Number.isFinite(createdMs) || createdMs <= 0) return 0;
  const ageHours = Math.max(0, (Date.now() - createdMs) / 3_600_000);
  if (ageHours <= 2) return 36;
  if (ageHours <= 8) return 26;
  if (ageHours <= 24) return 18;
  if (ageHours <= 72) return 8;
  return Math.max(-4, 4 - ageHours / 48);
}

function computeVelocityScore(row) {
  const likesRecent = safeNumber(row.likes_recent);
  const commentsRecent = safeNumber(row.comments_recent);
  const savesRecent = safeNumber(row.saves_recent);
  const viewsRecent = safeNumber(row.reel_views_recent);
  const impressionsRecent = Math.max(1, safeNumber(row.impressions_recent));
  const raw = likesRecent * 3 + commentsRecent * 4 + savesRecent * 5 + viewsRecent * 2;
  return Math.min(32, raw / Math.sqrt(impressionsRecent));
}

function computeLifetimeScore(row) {
  const likes = safeNumber(row.likes_count);
  const comments = safeNumber(row.comments_count);
  const saves = safeNumber(row.saves_count);
  const views = safeNumber(row.reel_views_count);
  return Math.min(20, likes * 0.08 + comments * 0.16 + saves * 0.2 + views * 0.02);
}

function computeRelationScore(row) {
  const status = String(row.relation_status || "").trim().toLowerCase();
  if (status === "accepted") return 18;
  if (status === "pending") return 6;
  return 0;
}

function computeLocalityScore(row, viewerScopeCodes = {}) {
  const hierarchy = deriveBasmayaHierarchy({
    block: row.user_block,
    buildingNumber: row.user_building_number,
    apartment: row.user_apartment,
  });
  if (viewerScopeCodes.buildingCode && hierarchy.building === viewerScopeCodes.buildingCode) {
    return 18;
  }
  if (viewerScopeCodes.compoundCode && hierarchy.compound === viewerScopeCodes.compoundCode) {
    return 12;
  }
  if (viewerScopeCodes.blockCode && hierarchy.block === viewerScopeCodes.blockCode) {
    return 8;
  }
  return 0;
}

function computePreferenceScore(row, preferenceWeights = {}) {
  const kind = String(row.post_kind || "").trim().toLowerCase();
  const normalizedKind =
    kind === "video"
      ? "reel"
      : kind === "merchant_review"
        ? "merchant_review"
        : kind || "text";
  const weight = safeNumber(preferenceWeights[normalizedKind]);
  return Math.min(12, weight * 1.25);
}

function computeTrustScore(row) {
  let score = 0;
  if (row.author_is_merchant === true) score += 3;
  if (row.author_has_premium === true) score += 2;
  if (row.author_is_resident_verified === true) score += 3;
  if (String(row.user_role || "").trim().toLowerCase() === "owner") score += 1;
  return score;
}

function computePenaltyScore(row) {
  let penalty = 0;
  if (String(row.social_visibility_tier || "").trim().toLowerCase() === "gray_zone") {
    penalty += 28;
  }
  if (safeNumber(row.report_count) > 0) {
    penalty += Math.min(18, safeNumber(row.report_count) * 2);
  }
  if ((String(row.caption || "").trim().length <= 4) && !row.media_url) {
    penalty += 6;
  }
  return penalty;
}

function computeMerchantReviewBoost(row) {
  if (String(row.post_kind || "").trim().toLowerCase() !== "merchant_review") return 0;
  const rating = safeNumber(row.review_rating);
  return 5 + Math.max(0, rating - 3) * 2;
}

export function buildPreferenceWeightMap(rows = []) {
  const out = Object.create(null);
  for (const row of rows) {
    const key = String(row.kind || "").trim().toLowerCase();
    if (!key) continue;
    out[key] = safeNumber(row.total_weight);
  }
  return out;
}

export function rankFeedRows(rows, { viewerScopeCodes = {}, preferenceWeights = {} } = {}) {
  if (!Array.isArray(rows) || rows.length <= 1) return Array.isArray(rows) ? rows : [];
  return [...rows]
    .map((row) => {
      const freshness = computeFreshnessScore(row.created_at);
      const velocity = computeVelocityScore(row);
      const lifetime = computeLifetimeScore(row);
      const relation = computeRelationScore(row);
      const locality = computeLocalityScore(row, viewerScopeCodes);
      const preference = computePreferenceScore(row, preferenceWeights);
      const trust = computeTrustScore(row);
      const merchantReview = computeMerchantReviewBoost(row);
      const penalty = computePenaltyScore(row);
      const score =
        freshness +
        velocity +
        lifetime +
        relation +
        locality +
        preference +
        trust +
        merchantReview -
        penalty;
      return { ...row, ranking_score: Number(score.toFixed(4)) };
    })
    .sort((a, b) => {
      if (b.ranking_score !== a.ranking_score) {
        return b.ranking_score - a.ranking_score;
      }
      return Number(b.id) - Number(a.id);
    });
}
