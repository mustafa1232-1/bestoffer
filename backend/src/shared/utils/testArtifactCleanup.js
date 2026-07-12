import { pool } from "../../config/db.js";

async function hasTable(client, tableName) {
  const result = await client.query(
    `SELECT to_regclass($1) IS NOT NULL AS present`,
    [tableName]
  );
  return result.rows[0]?.present === true;
}

export async function cleanupLoadArtifactsByRunTag(runTag) {
  if (!runTag) {
    throw new Error("LOAD_RUN_TAG_REQUIRED");
  }
  const pattern = `%${runTag}%`;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const usersResult = await client.query(
      `SELECT id
       FROM app_user
       WHERE full_name ILIKE $1`,
      [pattern]
    );
    const userIds = usersResult.rows.map((row) => Number(row.id)).filter(Boolean);

    const merchantsResult = await client.query(
      `SELECT id
       FROM merchant
       WHERE name ILIKE $1
          OR COALESCE(description, '') ILIKE $1
          OR COALESCE(tagline, '') ILIKE $1
          OR COALESCE(service_area_note, '') ILIKE $1`,
      [pattern]
    );
    const merchantIds = merchantsResult.rows.map((row) => Number(row.id)).filter(Boolean);

    const pharmacyConversationResult = await client.query(
      `SELECT id
       FROM pharmacy_conversation
       WHERE merchant_id = ANY($1::bigint[])
          OR customer_user_id = ANY($2::bigint[])`,
      [merchantIds, userIds]
    );
    const pharmacyConversationIds = pharmacyConversationResult.rows
      .map((row) => Number(row.id))
      .filter(Boolean);

    if (pharmacyConversationIds.length > 0) {
      await client.query(
        `DELETE FROM pharmacy_attachment_access_audit
         WHERE attachment_id IN (
           SELECT id FROM pharmacy_attachment WHERE conversation_id = ANY($1::bigint[])
         )`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_message
         WHERE conversation_id = ANY($1::bigint[])`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_proposed_cart_item
         WHERE proposed_cart_id IN (
           SELECT id FROM pharmacy_proposed_cart WHERE conversation_id = ANY($1::bigint[])
         )`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_proposed_cart
         WHERE conversation_id = ANY($1::bigint[])`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_conversation_event_history
         WHERE conversation_id = ANY($1::bigint[])`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_attachment
         WHERE conversation_id = ANY($1::bigint[])`,
        [pharmacyConversationIds]
      );
      await client.query(
        `DELETE FROM pharmacy_conversation
         WHERE id = ANY($1::bigint[])`,
        [pharmacyConversationIds]
      );
    }

    const hasSocialSavedContent = await hasTable(client, "social_saved_content");
    const hasCouponTable = await hasTable(client, "coupon");
    const hasFavoriteProductTable = await hasTable(client, "customer_favorite_product");
    const hasMerchantSettlementTable = await hasTable(client, "merchant_settlement");
    const hasSocialSavedItemTable = await hasTable(client, "social_saved_item");
    const hasSocialSavedCollectionTable = await hasTable(
      client,
      "social_saved_collection"
    );
    const hasSocialSavedCollectionItemTable = await hasTable(
      client,
      "social_saved_collection_item"
    );
    const hasSocialSearchRecentTable = await hasTable(client, "social_search_recent");
    const hasSocialChatThreadTable = await hasTable(client, "social_chat_thread");
    const hasSocialChatGroupTable = await hasTable(client, "social_chat_group");
    const hasSocialChatMessageTable = await hasTable(client, "social_chat_message");
    const hasSocialChatScheduledMessageTable = await hasTable(
      client,
      "social_chat_scheduled_message"
    );
    const hasSocialChatThreadMemberTable = await hasTable(
      client,
      "social_chat_thread_member"
    );
    const hasSocialChatThreadStateTable = await hasTable(
      client,
      "social_chat_thread_participant_state"
    );
    const hasSocialChatThreadPinnedMessageTable = await hasTable(
      client,
      "social_chat_thread_pinned_message"
    );
    const hasSocialChatMessageReactionTable = await hasTable(
      client,
      "social_chat_message_reaction"
    );
    const hasSocialChatMessageTranslationTable = await hasTable(
      client,
      "social_chat_message_translation"
    );
    const hasSocialUserRelationTable = await hasTable(client, "social_user_relation");
    const hasSocialContentTagTable = await hasTable(client, "social_content_tag");
    const hasSocialEntityHashtagTable = await hasTable(
      client,
      "social_entity_hashtag"
    );
    const hasSocialMentionTable = await hasTable(client, "social_mention");
    const hasSocialContentLinkTable = await hasTable(client, "social_content_link");
    const hasSocialContentImpressionTable = await hasTable(
      client,
      "social_content_impression"
    );
    const hasSocialReelViewEventTable = await hasTable(
      client,
      "social_reel_view_event"
    );
    const hasSocialMediaAssetTable = await hasTable(client, "social_media_asset");
    const hasSocialMediaJobTable = await hasTable(
      client,
      "social_media_processing_job"
    );
    const hasSocialStoryTable = await hasTable(client, "social_story");
    const hasSocialStoryViewTable = await hasTable(client, "social_story_view");
    const hasSocialStoryLikeTable = await hasTable(client, "social_story_like");
    const hasSocialStoryCommentTable = await hasTable(client, "social_story_comment");
    const hasSocialStoryReportTable = await hasTable(client, "social_story_report");
    const hasSocialStoryHighlightTable = await hasTable(
      client,
      "social_story_highlight"
    );
    const hasSocialStoryReportReviewLogTable = await hasTable(
      client,
      "social_story_report_review_log"
    );
    const hasSocialPostReportReviewLogTable = await hasTable(
      client,
      "social_post_report_review_log"
    );

    if (userIds.length > 0) {
      if (hasSocialUserRelationTable) {
        await client.query(
          `DELETE FROM social_user_relation
           WHERE user_a_id = ANY($1::bigint[])
              OR user_b_id = ANY($1::bigint[])`,
          [userIds]
        );
      }
      await client.query(
        `DELETE FROM social_post_comment_like
         WHERE post_comment_id IN (
           SELECT id FROM social_post_comment WHERE user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM social_post_like WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      if (hasSocialSavedContent) {
        await client.query(
          `DELETE FROM social_saved_content WHERE user_id = ANY($1::bigint[])`,
          [userIds]
        );
      }
      await client.query(
        `DELETE FROM social_post_comment WHERE user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(
        `DELETE FROM social_post
         WHERE user_id = ANY($1::bigint[])
            OR caption ILIKE $2`,
        [userIds, pattern]
      );
    }

    const chatThreadRows = [];
    if (hasSocialChatGroupTable) {
      const groupRows = await client.query(
        `SELECT thread_id AS id
         FROM social_chat_group
         WHERE title ILIKE $1
            OR COALESCE(image_url, '') ILIKE $1`,
        [pattern]
      );
      chatThreadRows.push(...groupRows.rows);
    }
    if (hasSocialChatMessageTable) {
      const messageRows = await client.query(
        `SELECT DISTINCT thread_id AS id
         FROM social_chat_message
         WHERE COALESCE(body, '') ILIKE $1
            OR COALESCE(attachment_name, '') ILIKE $1
            OR COALESCE(attachment_mime_type, '') ILIKE $1`,
        [pattern]
      );
      chatThreadRows.push(...messageRows.rows);
    }
    const chatThreadIds = [...new Set(
      chatThreadRows.map((row) => Number(row.id)).filter((value) => Number.isFinite(value) && value > 0)
    )];

    if (chatThreadIds.length > 0) {
      if (hasSocialChatScheduledMessageTable) {
        await client.query(
          `DELETE FROM social_chat_scheduled_message
           WHERE thread_id = ANY($1::bigint[])`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatMessageReactionTable) {
        await client.query(
          `DELETE FROM social_chat_message_reaction
           WHERE message_id IN (
             SELECT id FROM social_chat_message WHERE thread_id = ANY($1::bigint[])
           )`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatMessageTranslationTable) {
        await client.query(
          `DELETE FROM social_chat_message_translation
           WHERE message_id IN (
             SELECT id FROM social_chat_message WHERE thread_id = ANY($1::bigint[])
           )`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatThreadPinnedMessageTable) {
        await client.query(
          `DELETE FROM social_chat_thread_pinned_message
           WHERE thread_id = ANY($1::bigint[])
              OR message_id IN (
                SELECT id FROM social_chat_message WHERE thread_id = ANY($1::bigint[])
              )`,
          [chatThreadIds]
        );
      }
      await client.query(
        `DELETE FROM social_chat_message
         WHERE thread_id = ANY($1::bigint[])`,
        [chatThreadIds]
      );
      if (hasSocialChatThreadStateTable) {
        await client.query(
          `DELETE FROM social_chat_thread_participant_state
           WHERE thread_id = ANY($1::bigint[])`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatThreadMemberTable) {
        await client.query(
          `DELETE FROM social_chat_thread_member
           WHERE thread_id = ANY($1::bigint[])`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatGroupTable) {
        await client.query(
          `DELETE FROM social_chat_group
           WHERE thread_id = ANY($1::bigint[])`,
          [chatThreadIds]
        );
      }
      if (hasSocialChatThreadTable) {
        await client.query(
          `DELETE FROM social_chat_thread
           WHERE id = ANY($1::bigint[])`,
          [chatThreadIds]
        );
      }
    }

    if (userIds.length > 0 || merchantIds.length > 0) {
      await client.query(
        `DELETE FROM merchant_offer_usage
         WHERE order_id IN (
           SELECT id FROM customer_order
           WHERE customer_user_id = ANY($1::bigint[])
              OR merchant_id = ANY($2::bigint[])
              OR COALESCE(note, '') ILIKE $3
         )`,
        [userIds, merchantIds, pattern]
      );
      await client.query(
        `DELETE FROM coupon_redemption
         WHERE order_id IN (
           SELECT id FROM customer_order
           WHERE customer_user_id = ANY($1::bigint[])
              OR merchant_id = ANY($2::bigint[])
              OR COALESCE(note, '') ILIKE $3
         )`,
        [userIds, merchantIds, pattern]
      );
      await client.query(
        `DELETE FROM order_item
         WHERE order_id IN (
           SELECT id FROM customer_order
           WHERE customer_user_id = ANY($1::bigint[])
              OR merchant_id = ANY($2::bigint[])
              OR COALESCE(note, '') ILIKE $3
         )`,
        [userIds, merchantIds, pattern]
      );
      await client.query(
        `DELETE FROM customer_order
         WHERE customer_user_id = ANY($1::bigint[])
            OR merchant_id = ANY($2::bigint[])
            OR COALESCE(note, '') ILIKE $3`,
        [userIds, merchantIds, pattern]
      );
    }

    if (userIds.length > 0) {
      await client.query(
        `DELETE FROM taxi_ride_decline
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_chat_message
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_friend_share
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_location_log
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_event
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_bid
         WHERE ride_request_id IN (
           SELECT id FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])
         )`,
        [userIds]
      );
      await client.query(
        `DELETE FROM taxi_ride_request WHERE customer_user_id = ANY($1::bigint[])`,
        [userIds]
      );
    }

    if (merchantIds.length > 0) {
      await client.query(
        `DELETE FROM merchant_offer_product
         WHERE offer_id IN (SELECT id FROM merchant_offer WHERE merchant_id = ANY($1::bigint[]))`,
        [merchantIds]
      );
      await client.query(
        `DELETE FROM merchant_offer WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      if (hasCouponTable) {
        await client.query(`DELETE FROM coupon WHERE merchant_id = ANY($1::bigint[])`, [
          merchantIds,
        ]);
      }
      if (hasFavoriteProductTable) {
        await client.query(
          `DELETE FROM customer_favorite_product
           WHERE product_id IN (SELECT id FROM product WHERE merchant_id = ANY($1::bigint[]))`,
          [merchantIds]
        );
      }
      await client.query(`DELETE FROM product WHERE merchant_id = ANY($1::bigint[])`, [
        merchantIds,
      ]);
      await client.query(
        `DELETE FROM merchant_category WHERE merchant_id = ANY($1::bigint[])`,
        [merchantIds]
      );
      if (hasMerchantSettlementTable) {
        await client.query(
          `DELETE FROM merchant_settlement WHERE merchant_id = ANY($1::bigint[])`,
          [merchantIds]
        );
      }
      await client.query(`DELETE FROM merchant WHERE id = ANY($1::bigint[])`, [merchantIds]);
    }

    const postRows = await client.query(
      `SELECT id, media_asset_id
       FROM social_post
       WHERE caption ILIKE $1`,
      [pattern]
    );
    const storyRows = hasSocialStoryTable
      ? await client.query(
          `SELECT id, media_asset_id
           FROM social_story
           WHERE caption ILIKE $1`,
          [pattern]
        )
      : { rows: [] };
    const socialPostIds = postRows.rows.map((row) => Number(row.id)).filter(Boolean);
    const socialStoryIds = storyRows.rows.map((row) => Number(row.id)).filter(Boolean);
    const socialAssetIds = [
      ...postRows.rows.map((row) => Number(row.media_asset_id)).filter(Boolean),
      ...storyRows.rows.map((row) => Number(row.media_asset_id)).filter(Boolean),
    ].filter((value, index, array) => Number.isFinite(value) && value > 0 && array.indexOf(value) === index);

    const savedCollectionRows = hasSocialSavedCollectionTable
      ? await client.query(
          `SELECT id
           FROM social_saved_collection
           WHERE title ILIKE $1
              OR COALESCE(description, '') ILIKE $1
              OR COALESCE(system_key, '') ILIKE $1`,
          [pattern]
        )
      : { rows: [] };
    const socialSavedCollectionIds = savedCollectionRows.rows
      .map((row) => Number(row.id))
      .filter(Boolean);

    if (socialPostIds.length > 0) {
      if (hasSocialSavedItemTable && hasSocialSavedCollectionItemTable) {
        await client.query(
          `DELETE FROM social_saved_collection_item
           WHERE saved_item_id IN (
             SELECT id
             FROM social_saved_item
             WHERE entity_type IN ('post', 'reel')
               AND entity_id = ANY($1::bigint[])
           )`,
          [socialPostIds]
        );
      }
      if (hasSocialSavedItemTable) {
        await client.query(
          `DELETE FROM social_saved_item
           WHERE entity_type IN ('post', 'reel')
             AND entity_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialPostReportReviewLogTable) {
        await client.query(
          `DELETE FROM social_post_report_review_log
           WHERE post_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      await client.query(
        `DELETE FROM social_post_comment_like
         WHERE post_comment_id IN (
           SELECT id FROM social_post_comment WHERE post_id = ANY($1::bigint[])
         )`,
        [socialPostIds]
      );
      await client.query(
        `DELETE FROM social_post_comment
         WHERE post_id = ANY($1::bigint[])`,
        [socialPostIds]
      );
      await client.query(
        `DELETE FROM social_post_like WHERE post_id = ANY($1::bigint[])`,
        [socialPostIds]
      );
      await client.query(
        `DELETE FROM social_post_report WHERE post_id = ANY($1::bigint[])`,
        [socialPostIds]
      );
      if (hasSocialContentTagTable) {
        await client.query(
          `DELETE FROM social_content_tag
           WHERE entity_type IN ('post', 'reel')
             AND entity_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialEntityHashtagTable) {
        await client.query(
          `DELETE FROM social_entity_hashtag
           WHERE entity_type IN ('post', 'reel')
             AND entity_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialMentionTable) {
        await client.query(
          `DELETE FROM social_mention
           WHERE entity_type IN ('post', 'reel')
             AND entity_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialContentLinkTable) {
        await client.query(
          `DELETE FROM social_content_link
           WHERE entity_type IN ('post', 'reel')
             AND entity_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialContentImpressionTable) {
        await client.query(
          `DELETE FROM social_content_impression
           WHERE content_type IN ('post', 'reel')
             AND content_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialReelViewEventTable) {
        await client.query(
          `DELETE FROM social_reel_view_event
           WHERE post_id = ANY($1::bigint[])`,
          [socialPostIds]
        );
      }
      if (hasSocialMediaJobTable && socialAssetIds.length > 0) {
        await client.query(
          `DELETE FROM social_media_processing_job
           WHERE asset_id = ANY($1::bigint[])`,
          [socialAssetIds]
        );
      }
      if (hasSocialMediaAssetTable && socialAssetIds.length > 0) {
        await client.query(`DELETE FROM social_media_asset WHERE id = ANY($1::bigint[])`, [
          socialAssetIds,
        ]);
      }
      await client.query(`DELETE FROM social_post_media WHERE post_id = ANY($1::bigint[])`, [
        socialPostIds,
      ]);
      await client.query(`DELETE FROM social_post WHERE id = ANY($1::bigint[])`, [
        socialPostIds,
      ]);
    }

    if (socialStoryIds.length > 0) {
      if (hasSocialStoryReportReviewLogTable) {
        await client.query(
          `DELETE FROM social_story_report_review_log
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialStoryReportTable) {
        await client.query(
          `DELETE FROM social_story_report
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialStoryCommentTable) {
        await client.query(
          `DELETE FROM social_story_comment
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialStoryLikeTable) {
        await client.query(
          `DELETE FROM social_story_like
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialStoryViewTable) {
        await client.query(
          `DELETE FROM social_story_view
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialStoryHighlightTable) {
        await client.query(
          `DELETE FROM social_story_highlight
           WHERE story_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialContentTagTable) {
        await client.query(
          `DELETE FROM social_content_tag
           WHERE entity_type IN ('story', 'story_comment')
             AND entity_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialEntityHashtagTable) {
        await client.query(
          `DELETE FROM social_entity_hashtag
           WHERE entity_type IN ('story', 'story_comment')
             AND entity_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialMentionTable) {
        await client.query(
          `DELETE FROM social_mention
           WHERE entity_type IN ('story', 'story_comment')
             AND entity_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialContentLinkTable) {
        await client.query(
          `DELETE FROM social_content_link
           WHERE entity_type = 'story'
             AND entity_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialContentImpressionTable) {
        await client.query(
          `DELETE FROM social_content_impression
           WHERE content_type = 'story'
             AND content_id = ANY($1::bigint[])`,
          [socialStoryIds]
        );
      }
      if (hasSocialMediaJobTable && socialAssetIds.length > 0) {
        await client.query(
          `DELETE FROM social_media_processing_job
           WHERE asset_id = ANY($1::bigint[])`,
          [socialAssetIds]
        );
      }
      if (hasSocialMediaAssetTable && socialAssetIds.length > 0) {
        await client.query(`DELETE FROM social_media_asset WHERE id = ANY($1::bigint[])`, [
          socialAssetIds,
        ]);
      }
      await client.query(`DELETE FROM social_story WHERE id = ANY($1::bigint[])`, [
        socialStoryIds,
      ]);
    }

    if (socialSavedCollectionIds.length > 0 && hasSocialSavedCollectionItemTable) {
      await client.query(
        `DELETE FROM social_saved_collection_item
         WHERE collection_id = ANY($1::bigint[])`,
        [socialSavedCollectionIds]
      );
      await client.query(
        `DELETE FROM social_saved_collection WHERE id = ANY($1::bigint[])`,
        [socialSavedCollectionIds]
      );
    }

    if (hasSocialSearchRecentTable) {
      await client.query(
        `DELETE FROM social_search_recent
         WHERE raw_query ILIKE $1`,
        [pattern]
      );
    }

    if (hasCouponTable) {
      await client.query(
        `DELETE FROM coupon
         WHERE code ILIKE $1
            OR COALESCE(description, '') ILIKE $1`,
        [pattern]
      );
    }

    if (userIds.length > 0) {
      await client.query(`DELETE FROM app_notification WHERE user_id = ANY($1::bigint[])`, [
        userIds,
      ]);
      await client.query(
        `DELETE FROM social_user_notification_pref
         WHERE user_id = ANY($1::bigint[])
            OR actor_user_id = ANY($1::bigint[])`,
        [userIds]
      );
      await client.query(`DELETE FROM user_activity_event WHERE user_id = ANY($1::bigint[])`, [
        userIds,
      ]);
      await client.query(`DELETE FROM customer_address WHERE customer_user_id = ANY($1::bigint[])`, [
        userIds,
      ]);
      await client.query(`DELETE FROM user_push_token WHERE user_id = ANY($1::bigint[])`, [
        userIds,
      ]);
      await client.query(`DELETE FROM user_session WHERE user_id = ANY($1::bigint[])`, [
        userIds,
      ]);
      await client.query(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
    }

    await client.query("COMMIT");
    return {
      runTag,
      removedUsers: userIds.length,
      removedMerchants: merchantIds.length,
      removedPharmacyConversations: pharmacyConversationIds.length,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
