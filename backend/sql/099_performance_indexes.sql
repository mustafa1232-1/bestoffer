-- 099: Performance indexes and phone_normalized column for fast login lookup

-- Add phone_normalized as a generated stored column.
-- Eliminates full table scan on every login caused by calling functions on raw phone values.
ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS phone_normalized TEXT
GENERATED ALWAYS AS (
  regexp_replace(
    translate(phone, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'),
    '[^0-9]', '', 'g'
  )
) STORED;

CREATE INDEX IF NOT EXISTS idx_app_user_phone_normalized
ON app_user (phone_normalized);

-- Sessions: composite index for auth hot path (user_id + active + not expired)
-- Already created in ensureSchema but added here for explicit tracking
CREATE INDEX IF NOT EXISTS idx_user_session_active
ON user_session (user_id, is_revoked, expires_at DESC);

-- Order items: product join for review counts and stats queries
CREATE INDEX IF NOT EXISTS idx_order_item_product_id
ON order_item (product_id);

-- Post comments: filter for approved non-deleted comments (used in feed counts)
CREATE INDEX IF NOT EXISTS idx_social_post_comment_approved
ON social_post_comment (post_id, moderation_status, is_deleted);

-- Social user relations: normalized bi-directional join avoids LEAST/GREATEST scans
CREATE INDEX IF NOT EXISTS idx_social_user_relation_normalized
ON social_user_relation (LEAST(user_a_id, user_b_id), GREATEST(user_a_id, user_b_id));

-- Products: availability + recency (used in merchant product listings)
CREATE INDEX IF NOT EXISTS idx_product_merchant_available
ON product (merchant_id, is_available, created_at DESC);
