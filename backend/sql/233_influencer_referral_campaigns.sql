BEGIN;

-- Per-user coupon limits are shared by all coupons. Influencer marketing
-- coupons use a value of 1, independently from referral attribution.
ALTER TABLE coupon
  ADD COLUMN IF NOT EXISTS max_uses_per_user INT;

ALTER TABLE coupon
  DROP CONSTRAINT IF EXISTS coupon_max_uses_per_user_positive;

ALTER TABLE coupon
  ADD CONSTRAINT coupon_max_uses_per_user_positive
  CHECK (max_uses_per_user IS NULL OR max_uses_per_user > 0);

-- The influencer profile owns the permanent tracking/referral code. This code
-- never grants a discount and is only used to attribute a new account.
CREATE TABLE IF NOT EXISTS influencer_profile (
  id                         BIGSERIAL PRIMARY KEY,
  tracking_code              VARCHAR(64) NOT NULL UNIQUE,
  display_name               VARCHAR(160) NOT NULL,
  handle                     VARCHAR(160),
  contact_phone              VARCHAR(40),
  notes                      TEXT,
  reward_per_qualified_user  NUMERIC(14,2) NOT NULL DEFAULT 0,
  qualification_rule         VARCHAR(32) NOT NULL DEFAULT 'first_completed_order',
  is_active                  BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_user_id         BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT influencer_profile_name_chk
    CHECK (CHAR_LENGTH(BTRIM(display_name)) BETWEEN 2 AND 160),
  CONSTRAINT influencer_profile_tracking_code_chk
    CHECK (tracking_code ~ '^[A-Z0-9-]{4,64}$'),
  CONSTRAINT influencer_profile_reward_chk
    CHECK (reward_per_qualified_user >= 0),
  CONSTRAINT influencer_profile_rule_chk
    CHECK (qualification_rule IN ('claim', 'first_completed_order'))
);

-- Marketing coupons are separate records. An influencer may own multiple
-- campaigns over time, while every coupon remains limited to one use per user.
CREATE TABLE IF NOT EXISTS influencer_coupon_campaign (
  id                  BIGSERIAL PRIMARY KEY,
  influencer_id       BIGINT NOT NULL REFERENCES influencer_profile(id) ON DELETE RESTRICT,
  coupon_id            INT NOT NULL UNIQUE REFERENCES coupon(id) ON DELETE RESTRICT,
  label                VARCHAR(160),
  created_by_user_id   BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS influencer_referral_attribution (
  id                  BIGSERIAL PRIMARY KEY,
  influencer_id       BIGINT NOT NULL REFERENCES influencer_profile(id) ON DELETE RESTRICT,
  user_id             BIGINT NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  device_fingerprint  VARCHAR(128) NOT NULL,
  auth_session_id     BIGINT REFERENCES user_session(id) ON DELETE SET NULL,
  claimed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT influencer_referral_attribution_device_chk
    CHECK (CHAR_LENGTH(BTRIM(device_fingerprint)) BETWEEN 32 AND 128),
  CONSTRAINT influencer_referral_attribution_user_unique UNIQUE (user_id),
  CONSTRAINT influencer_referral_attribution_device_unique UNIQUE (device_fingerprint),
  CONSTRAINT influencer_referral_attribution_influencer_user_unique
    UNIQUE (influencer_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_influencer_profile_active
  ON influencer_profile (is_active, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_influencer_coupon_campaign_influencer
  ON influencer_coupon_campaign (influencer_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_influencer_referral_attribution_influencer
  ON influencer_referral_attribution (influencer_id, claimed_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_customer_order_referral_qualification
  ON customer_order (customer_user_id, created_at ASC)
  WHERE status IN ('delivered','delivered_by_courier','received_by_customer','completed');

CREATE OR REPLACE FUNCTION prevent_influencer_attribution_reassignment()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'INFLUENCER_ATTRIBUTION_IMMUTABLE' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_influencer_attribution_immutable
  ON influencer_referral_attribution;

CREATE TRIGGER trg_influencer_attribution_immutable
BEFORE UPDATE ON influencer_referral_attribution
FOR EACH ROW
EXECUTE FUNCTION prevent_influencer_attribution_reassignment();

COMMIT;
