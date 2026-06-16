import { pool, q } from "../../config/db.js";

function toInt(value) {
  const out = Number(value);
  return Number.isInteger(out) ? out : null;
}

export async function getMerchantPharmacyConfig(merchantId) {
  const r = await q(
    `SELECT
       id,
       owner_user_id,
       name,
       image_url,
       type::text AS type,
       activity_type,
       supports_chat,
       supports_attachments,
       supports_pharmacy_workflow,
       service_flags_json,
       badges_json,
       is_approved,
       is_disabled
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listCustomerConversations({
  customerUserId,
  status,
  q: search = null,
  limit = 50,
}) {
  const normalizedSearch = String(search || "").trim();
  const searchPattern = normalizedSearch ? `%${normalizedSearch}%` : null;
  const r = await q(
    `SELECT
       c.*,
       m.name AS merchant_name,
       m.image_url AS merchant_image_url,
       m.activity_type,
       m.supports_attachments,
       m.supports_chat,
       m.supports_pharmacy_workflow,
       (
         SELECT COUNT(*)::int
         FROM pharmacy_message pm
         WHERE pm.conversation_id = c.id
       ) AS messages_count
     FROM pharmacy_conversation c
     JOIN merchant m ON m.id = c.merchant_id
     WHERE c.customer_user_id = $1
       AND ($2::text IS NULL OR c.status = $2::text)
       AND ($3::text IS NULL OR m.name ILIKE $3::text)
     ORDER BY COALESCE(c.last_message_at, c.created_at) DESC, c.id DESC
     LIMIT $4`,
    [Number(customerUserId), status || null, searchPattern, Number(limit)]
  );
  return r.rows;
}

export async function listOwnerConversations({
  ownerUserId,
  status,
  statuses = null,
  q: search = null,
  limit = 50,
}) {
  const list = Array.isArray(statuses) && statuses.length ? statuses : null;
  const normalizedSearch = String(search || "").trim();
  const searchPattern = normalizedSearch ? `%${normalizedSearch}%` : null;
  const r = await q(
    `SELECT
       c.*,
       m.name AS merchant_name,
       m.image_url AS merchant_image_url,
       m.activity_type,
       u.full_name AS customer_full_name,
       u.phone AS customer_phone,
       (
         SELECT COUNT(*)::int
         FROM pharmacy_message pm
         WHERE pm.conversation_id = c.id
       ) AS messages_count
     FROM pharmacy_conversation c
     JOIN merchant m
       ON m.id = c.merchant_id
      AND m.owner_user_id = $1
     JOIN app_user u ON u.id = c.customer_user_id
     WHERE ($2::text IS NULL OR c.status = $2::text)
       AND ($3::text[] IS NULL OR c.status = ANY($3::text[]))
       AND (
         $4::text IS NULL OR
         u.full_name ILIKE $4::text OR
         u.phone ILIKE $4::text OR
         m.name ILIKE $4::text
       )
     ORDER BY COALESCE(c.last_message_at, c.created_at) DESC, c.id DESC
     LIMIT $5`,
    [Number(ownerUserId), status || null, list, searchPattern, Number(limit)]
  );
  return r.rows;
}

export async function createConversation({
  merchantId,
  customerUserId,
  metadata = {},
}) {
  const r = await q(
    `INSERT INTO pharmacy_conversation
      (merchant_id, customer_user_id, activity_type, conversation_type, status, metadata_json, last_message_at)
     VALUES ($1,$2,'pharmacy','pharmacy_direct','open',$3::jsonb,NOW())
     RETURNING *`,
    [Number(merchantId), Number(customerUserId), JSON.stringify(metadata || {})]
  );
  return r.rows[0] || null;
}

export async function findConversationById(conversationId) {
  const r = await q(
    `SELECT
       c.*,
       m.owner_user_id,
       m.name AS merchant_name,
       m.activity_type,
       m.supports_pharmacy_workflow,
       m.supports_attachments,
       m.supports_chat
     FROM pharmacy_conversation c
     JOIN merchant m ON m.id = c.merchant_id
     WHERE c.id = $1
     LIMIT 1`,
    [Number(conversationId)]
  );
  return r.rows[0] || null;
}

export async function listConversationMessages(conversationId, { limit = 120, beforeId = null } = {}) {
  const r = await q(
    `SELECT
       pm.id,
       pm.conversation_id,
       pm.sender_user_id,
       pm.sender_type,
       pm.message_type,
       pm.text,
       pm.attachment_id,
       pm.proposed_cart_id,
       pm.metadata_json,
       pm.created_at,
       au.full_name AS sender_full_name,
       pa.file_url AS attachment_url,
       pa.attachment_mime_type AS attachment_mime_type,
       pa.original_file_name AS attachment_name
     FROM pharmacy_message pm
     LEFT JOIN app_user au ON au.id = pm.sender_user_id
     LEFT JOIN pharmacy_attachment pa ON pa.id = pm.attachment_id
     WHERE pm.conversation_id = $1
       AND ($2::bigint IS NULL OR pm.id < $2::bigint)
     ORDER BY pm.id DESC
     LIMIT $3`,
    [Number(conversationId), beforeId ? Number(beforeId) : null, Number(limit)]
  );
  return r.rows.reverse();
}

export async function appendConversationMessage({
  conversationId,
  senderUserId,
  senderType,
  messageType = "text",
  text = null,
  attachmentId = null,
  proposedCartId = null,
  metadata = {},
}) {
  const r = await q(
    `INSERT INTO pharmacy_message
      (conversation_id, sender_user_id, sender_type, message_type, text, attachment_id, proposed_cart_id, metadata_json)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
     RETURNING *`,
    [
      Number(conversationId),
      senderUserId == null ? null : Number(senderUserId),
      String(senderType || "system"),
      String(messageType || "text"),
      text == null ? null : String(text),
      attachmentId == null ? null : Number(attachmentId),
      proposedCartId == null ? null : Number(proposedCartId),
      JSON.stringify(metadata || {}),
    ]
  );
  await q(
    `UPDATE pharmacy_conversation
     SET last_message_at = NOW(), updated_at = NOW()
     WHERE id = $1`,
    [Number(conversationId)]
  );
  return r.rows[0] || null;
}

export async function createAttachment({
  conversationId,
  uploaderUserId,
  fileUrl,
  storageKey = null,
  mimeType = null,
  fileSizeBytes = null,
  originalFileName = null,
  isSensitive = true,
  retentionExpiresAt = null,
  metadata = {},
}) {
  const r = await q(
    `INSERT INTO pharmacy_attachment
      (
        conversation_id,
        uploader_user_id,
        file_url,
        storage_key,
        attachment_mime_type,
        file_size_bytes,
        original_file_name,
        is_sensitive,
        retention_expires_at,
        metadata_json
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)
     RETURNING *`,
    [
      Number(conversationId),
      uploaderUserId == null ? null : Number(uploaderUserId),
      String(fileUrl || ""),
      storageKey ? String(storageKey) : null,
      mimeType ? String(mimeType) : null,
      fileSizeBytes == null ? null : Number(fileSizeBytes),
      originalFileName ? String(originalFileName) : null,
      isSensitive === true,
      retentionExpiresAt,
      JSON.stringify(metadata || {}),
    ]
  );
  return r.rows[0] || null;
}

export async function findAttachmentById(attachmentId) {
  const r = await q(
    `SELECT
       pa.*,
       c.customer_user_id,
       m.owner_user_id,
       m.id AS merchant_id
     FROM pharmacy_attachment pa
     JOIN pharmacy_conversation c ON c.id = pa.conversation_id
     JOIN merchant m ON m.id = c.merchant_id
     WHERE pa.id = $1
     LIMIT 1`,
    [Number(attachmentId)]
  );
  return r.rows[0] || null;
}

export async function appendAttachmentAccessAudit({
  attachmentId,
  actorUserId = null,
  actorRole = null,
  action,
  accessGranted,
  ipAddress = null,
  userAgent = null,
}) {
  await q(
    `INSERT INTO pharmacy_attachment_access_audit
      (attachment_id, actor_user_id, actor_role, action, access_granted, ip_address, user_agent)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [
      Number(attachmentId),
      actorUserId == null ? null : Number(actorUserId),
      actorRole == null ? null : String(actorRole || "").trim().toLowerCase(),
      String(action || "view"),
      accessGranted === true,
      ipAddress ? String(ipAddress).slice(0, 64) : null,
      userAgent ? String(userAgent).slice(0, 400) : null,
    ]
  );
}

export async function appendConversationEvent({
  conversationId,
  actorUserId = null,
  eventType,
  fromStatus = null,
  toStatus = null,
  metadata = {},
}) {
  await q(
    `INSERT INTO pharmacy_conversation_event_history
      (conversation_id, actor_user_id, event_type, from_status, to_status, metadata_json)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb)`,
    [
      Number(conversationId),
      actorUserId == null ? null : Number(actorUserId),
      String(eventType || ""),
      fromStatus == null ? null : String(fromStatus || ""),
      toStatus == null ? null : String(toStatus || ""),
      JSON.stringify(metadata || {}),
    ]
  );
}

export async function updateConversationStatus(conversationId, status, { linkedOrderId = null } = {}) {
  const r = await q(
    `UPDATE pharmacy_conversation
     SET status = $2,
         linked_order_id = COALESCE($3, linked_order_id),
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(conversationId), String(status || "open"), linkedOrderId ? Number(linkedOrderId) : null]
  );
  return r.rows[0] || null;
}

export async function getLatestConversationCart(conversationId) {
  const r = await q(
    `SELECT *
     FROM pharmacy_proposed_cart
     WHERE conversation_id = $1
     ORDER BY version DESC, id DESC
     LIMIT 1`,
    [Number(conversationId)]
  );
  return r.rows[0] || null;
}

export async function getProposedCartById(cartId) {
  const r = await q(
    `SELECT
       pc.*,
       c.customer_user_id,
       c.merchant_id,
       pc.owner_user_id
     FROM (
       SELECT
         pc.*,
         m.owner_user_id
       FROM pharmacy_proposed_cart pc
       JOIN pharmacy_conversation c2 ON c2.id = pc.conversation_id
       JOIN merchant m ON m.id = c2.merchant_id
       WHERE pc.id = $1
     ) pc
     JOIN pharmacy_conversation c ON c.id = pc.conversation_id
     LIMIT 1`,
    [Number(cartId)]
  );
  return r.rows[0] || null;
}

export async function listProposedCartItems(cartId) {
  const r = await q(
    `SELECT *
     FROM pharmacy_proposed_cart_item
     WHERE proposed_cart_id = $1
     ORDER BY id ASC`,
    [Number(cartId)]
  );
  return r.rows;
}

export async function createProposedCartWithItems({
  conversationId,
  createdByUserId,
  items,
  deliveryFee,
  notes = null,
  expiresAt = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `SELECT id
       FROM pharmacy_conversation
       WHERE id = $1
       FOR UPDATE`,
      [Number(conversationId)]
    );
    const versionResult = await client.query(
      `SELECT version
       FROM pharmacy_proposed_cart
       WHERE conversation_id = $1
       ORDER BY version DESC, id DESC
       LIMIT 1
       FOR UPDATE`,
      [Number(conversationId)]
    );
    const nextVersion = Number(versionResult.rows[0]?.version || 0) + 1;
    const subtotal = items.reduce(
      (sum, item) => sum + Number(item.unitPrice || 0) * Number(item.quantity || 0),
      0
    );
    const total = subtotal + Number(deliveryFee || 0);

    const cartResult = await client.query(
      `INSERT INTO pharmacy_proposed_cart
        (
          conversation_id,
          version,
          status,
          subtotal,
          delivery_fee,
          total,
          notes,
          expires_at,
          created_by_user_id
        )
       VALUES ($1,$2,'proposed',$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        Number(conversationId),
        nextVersion,
        subtotal,
        Number(deliveryFee || 0),
        total,
        notes,
        expiresAt,
        Number(createdByUserId),
      ]
    );
    const cart = cartResult.rows[0];

    for (const item of items) {
      const quantity = Number(item.quantity || 0);
      const unitPrice = Number(item.unitPrice || 0);
      const lineTotal = quantity * unitPrice;
      await client.query(
        `INSERT INTO pharmacy_proposed_cart_item
          (
            proposed_cart_id,
            product_id,
            product_name,
            quantity,
            unit_price,
            line_total,
            alternative_group_id,
            note,
            requires_prescription,
            requires_review,
            metadata_json
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
        [
          Number(cart.id),
          item.productId == null ? null : Number(item.productId),
          String(item.productName || ""),
          quantity,
          unitPrice,
          lineTotal,
          item.alternativeGroupId ? String(item.alternativeGroupId) : null,
          item.note ? String(item.note) : null,
          item.requiresPrescription === true,
          item.requiresReview === true,
          JSON.stringify(item.metadata || {}),
        ]
      );
    }

    await client.query(
      `UPDATE pharmacy_conversation
       SET status = 'cart_proposed', updated_at = NOW(), last_message_at = NOW()
       WHERE id = $1`,
      [Number(conversationId)]
    );

    await client.query("COMMIT");
    return cart;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateProposedCartStatus(cartId, status, timestamps = {}) {
  const fields = [];
  const values = [Number(cartId), String(status || "").trim().toLowerCase()];
  let idx = 3;
  for (const [key, value] of Object.entries(timestamps || {})) {
    fields.push(`${key} = $${idx++}`);
    values.push(value);
  }
  const setClause = fields.length > 0 ? `, ${fields.join(", ")}` : "";
  const r = await q(
    `UPDATE pharmacy_proposed_cart
     SET status = $2${setClause}, updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    values
  );
  return r.rows[0] || null;
}

export async function convertAcceptedCartToOrder({ cartId, note = null }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const cartResult = await client.query(
      `SELECT
         pc.*,
         c.customer_user_id,
         c.merchant_id,
         c.linked_order_id,
         m.owner_user_id
       FROM pharmacy_proposed_cart pc
       JOIN pharmacy_conversation c ON c.id = pc.conversation_id
       JOIN merchant m ON m.id = c.merchant_id
       WHERE pc.id = $1
       FOR UPDATE`,
      [Number(cartId)]
    );
    const cart = cartResult.rows[0] || null;
    if (!cart) {
      await client.query("ROLLBACK");
      return { code: "CART_NOT_FOUND", order: null };
    }

    if (String(cart.status || "").toLowerCase() !== "accepted") {
      await client.query("ROLLBACK");
      return { code: "CART_NOT_ACCEPTED", order: null };
    }

    if (cart.linked_order_id) {
      await client.query("ROLLBACK");
      return { code: "ALREADY_CONVERTED", order: { id: Number(cart.linked_order_id) } };
    }

    const userResult = await client.query(
      `SELECT id, full_name, phone, block, building_number, apartment
       FROM app_user
       WHERE id = $1
       LIMIT 1`,
      [Number(cart.customer_user_id)]
    );
    const customer = userResult.rows[0] || null;
    if (!customer) {
      await client.query("ROLLBACK");
      return { code: "CUSTOMER_NOT_FOUND", order: null };
    }

    const orderResult = await client.query(
      `INSERT INTO customer_order
        (
          merchant_id,
          customer_user_id,
          status,
          customer_full_name,
          customer_phone,
          customer_block,
          customer_building_number,
          customer_apartment,
          note,
          subtotal,
          gross_subtotal,
          product_discount_total,
          coupon_discount_total,
          service_fee,
          delivery_fee,
          total_amount,
          source_type,
          order_flow_type,
          pharmacy_conversation_id,
          pharmacy_flow_status,
          pricing_breakdown_json
        )
       VALUES (
         $1,$2,'pending',$3,$4,$5,$6,$7,$8,$9::numeric,$9::numeric,0,0,0,$10::numeric,$11::numeric,
         'pharmacy_chat_cart','pharmacy',$12,'confirmed',
         jsonb_build_object(
           'sourceType','pharmacy_chat_cart',
           'subtotal', $9::numeric,
           'deliveryFee', $10::numeric,
           'totalAmount', $11::numeric
         )
       )
       RETURNING id`,
      [
        Number(cart.merchant_id),
        Number(cart.customer_user_id),
        customer.full_name || "Customer",
        customer.phone || "0000000000",
        customer.block || "N/A",
        customer.building_number || "N/A",
        customer.apartment || "N/A",
        note,
        Number(cart.subtotal || 0),
        Number(cart.delivery_fee || 0),
        Number(cart.total || 0),
        Number(cart.conversation_id),
      ]
    );
    const orderId = Number(orderResult.rows[0]?.id || 0);

    const itemRows = await client.query(
      `SELECT *
       FROM pharmacy_proposed_cart_item
       WHERE proposed_cart_id = $1
       ORDER BY id ASC`,
      [Number(cart.id)]
    );

    for (const item of itemRows.rows) {
      const quantity = Number(item.quantity || 0);
      const unitPrice = Number(item.unit_price || 0);
      const lineTotal = Number(item.line_total || quantity * unitPrice);
      await client.query(
        `INSERT INTO order_item
          (
            order_id,
            product_id,
            product_name,
            unit_price,
            base_unit_price,
            quantity,
            line_total,
            line_discount_total,
            pricing_breakdown_json
          )
         VALUES (
           $1,$2,$3,$4,$4,$5,$6,0,
           jsonb_build_object(
             'sourceType','pharmacy_chat_cart',
             'requiresPrescription',$7::boolean,
             'requiresReview',$8::boolean
           )
         )`,
        [
          orderId,
          item.product_id ? Number(item.product_id) : null,
          item.product_name,
          unitPrice,
          quantity,
          lineTotal,
          item.requires_prescription === true,
          item.requires_review === true,
        ]
      );
    }

    await client.query(
      `UPDATE pharmacy_conversation
       SET linked_order_id = $2, status = 'order_created', updated_at = NOW()
       WHERE id = $1`,
      [Number(cart.conversation_id), orderId]
    );

    await client.query(
      `UPDATE pharmacy_proposed_cart
       SET status = 'converted', updated_at = NOW()
       WHERE id = $1`,
      [Number(cart.id)]
    );

    await client.query("COMMIT");
    return { code: "OK", order: { id: orderId } };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export function hasConversationAccess(conversation, { userId, role }) {
  if (!conversation) return false;
  const numericUserId = toInt(userId);
  const normalizedRole = String(role || "").trim().toLowerCase();
  if (!numericUserId) return false;
  if (Number(conversation.customer_user_id) === numericUserId) return true;
  if (Number(conversation.owner_user_id) === numericUserId && normalizedRole === "owner") {
    return true;
  }
  if (normalizedRole === "admin") return true;
  return false;
}
