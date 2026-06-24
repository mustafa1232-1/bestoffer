export function mapSocialPostProductRow(row) {
  if (!row) return null;
  const authorBadges = [];
  if (row.author_is_resident_verified === true) {
    authorBadges.push("resident_verified");
  }
  if (row.author_is_merchant === true) {
    authorBadges.push("merchant_verified");
  }
  if (row.author_has_premium === true) {
    authorBadges.push("premium_creator");
  }
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    postKind: String(row.post_kind || "text").trim().toLowerCase(),
    audienceScopeType: String(row.audience_scope_type || "global").trim().toLowerCase(),
    audienceScopeCode:
      row.audience_scope_code == null
        ? null
        : String(row.audience_scope_code).trim().toUpperCase(),
    caption: row.caption || "",
    mediaUrl: row.asset_normalized_url || row.normalized_url || row.media_url || null,
    mediaKind: row.media_kind || null,
    merchantId: row.merchant_id == null ? null : Number(row.merchant_id),
    merchantName: row.merchant_name || null,
    merchantType: row.merchant_type || null,
    merchantImageUrl: row.merchant_image_url || null,
    reviewRating: row.review_rating == null ? null : Number(row.review_rating),
    archivedAt: row.archived_by_owner_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    moderationStatus: row.moderation_status || null,
    moderationNote: row.moderation_note || null,
    moderationRequestedAt: row.moderation_requested_at || null,
    author: {
      id: Number(row.user_id),
      username: row.user_username || null,
      fullName: row.user_full_name || "",
      imageUrl: row.user_image_url || null,
      role: row.user_role || "user",
      phone: row.user_phone || "",
      badges: authorBadges,
      isResidentVerified: row.author_is_resident_verified === true,
      isMerchantVerified: row.author_is_merchant === true,
      isPremiumCreator: row.author_has_premium === true,
    },
    likesCount: Number(row.likes_count || 0),
    commentsCount: Number(row.comments_count || 0),
    savesCount: Number(row.saves_count || 0),
    impressionsCount: Number(row.impressions_count || 0),
    reelViewsCount: Number(row.reel_views_count || 0),
    isLiked: row.is_liked === true,
    isSaved: row.is_saved === true,
    rankingScore: row.ranking_score == null ? null : Number(row.ranking_score),
    reportCount: Number(row.report_count || 0),
    asset: row.media_asset_id || row.poster_url || row.asset_poster_url
      ? {
          id: row.media_asset_id == null ? null : Number(row.media_asset_id),
          normalizedUrl: row.asset_normalized_url || row.normalized_url || row.media_url || null,
          posterUrl: row.asset_poster_url || row.poster_url || null,
          durationMs: row.asset_duration_ms == null ? null : Number(row.asset_duration_ms),
          processingStatus: row.asset_processing_status || row.processing_status || null,
        }
      : null,
    mediaGallery: Array.isArray(row.media_gallery)
      ? row.media_gallery.map((item) => ({
          id: Number(item.id),
          sortOrder: Number(item.sortOrder ?? item.sort_order ?? 0),
          mediaUrl: item.mediaUrl || item.media_url || null,
          mediaKind: item.mediaKind || item.media_kind || null,
          asset:
            item.asset && typeof item.asset === "object"
              ? {
                  id: item.asset.id == null ? null : Number(item.asset.id),
                  normalizedUrl:
                    item.asset.normalizedUrl || item.asset.normalized_url || null,
                  posterUrl: item.asset.posterUrl || item.asset.poster_url || null,
                  durationMs:
                    item.asset.durationMs == null &&
                    item.asset.duration_ms == null
                      ? null
                      : Number(item.asset.durationMs ?? item.asset.duration_ms),
                  processingStatus:
                    item.asset.processingStatus ||
                    item.asset.processing_status ||
                    null,
                }
              : null,
        }))
      : [],
    contentLink:
      row.link_target_type || row.target_type
        ? {
            targetType: row.link_target_type || row.target_type,
            merchantId: row.link_merchant_id == null ? null : Number(row.link_merchant_id),
            productId: row.link_product_id == null ? null : Number(row.link_product_id),
            offerId: row.link_offer_id == null ? null : Number(row.link_offer_id),
            couponId: row.link_coupon_id == null ? null : Number(row.link_coupon_id),
          }
        : null,
  };
}

export function mapHashtagRow(row) {
  return {
    id: Number(row.id),
    tag: row.tag || "",
    normalizedTag: row.normalized_tag || row.tag || "",
    usageCount: Number(row.usage_count || 0),
    lastUsedAt: row.last_used_at || null,
  };
}

export function mapSavedCollectionRow(row) {
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    title: row.title || "",
    description: row.description || null,
    systemKey: row.system_key || null,
    itemsCount: Number(row.items_count || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}
