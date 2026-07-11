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

    if (userIds.length > 0) {
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
