BEGIN;

CREATE TABLE IF NOT EXISTS service_provider_subscription_requests (
  id BIGSERIAL PRIMARY KEY,
  request_code VARCHAR(40) NOT NULL UNIQUE,
  full_name VARCHAR(120) NOT NULL,
  business_name VARCHAR(180) NOT NULL,
  phone VARCHAR(32) NOT NULL,
  pin_hash TEXT NOT NULL,
  logo_url TEXT,
  cover_image_url TEXT,
  main_category_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  city VARCHAR(120) NOT NULL,
  area VARCHAR(120),
  address_line TEXT,
  bio TEXT,
  whatsapp_phone VARCHAR(32),
  serves_at_home BOOLEAN NOT NULL DEFAULT TRUE,
  serves_at_shop BOOLEAN NOT NULL DEFAULT FALSE,
  serves_remote BOOLEAN NOT NULL DEFAULT FALSE,
  has_emergency_service BOOLEAN NOT NULL DEFAULT FALSE,
  booking_policy VARCHAR(30) NOT NULL DEFAULT 'approval_required',
  pricing_mode VARCHAR(30) NOT NULL DEFAULT 'mixed',
  years_experience INTEGER,
  has_team BOOLEAN NOT NULL DEFAULT FALSE,
  team_size INTEGER,
  accepts_cash BOOLEAN NOT NULL DEFAULT TRUE,
  accepts_electronic BOOLEAN NOT NULL DEFAULT FALSE,
  average_response_minutes INTEGER,
  is_available_24_7 BOOLEAN NOT NULL DEFAULT FALSE,
  provider_gender VARCHAR(24),
  languages_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  areas_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  availability_rules_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  status VARCHAR(40) NOT NULL DEFAULT 'pending_offer',
  status_note TEXT,
  selected_offer_id BIGINT,
  offered_amount NUMERIC(14,2),
  offered_currency VARCHAR(8),
  offered_title VARCHAR(160),
  offered_description TEXT,
  offered_valid_until TIMESTAMPTZ,
  offer_sent_at TIMESTAMPTZ,
  offer_accepted_at TIMESTAMPTZ,
  offer_rejected_at TIMESTAMPTZ,
  payment_confirmed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  payment_confirmed_at TIMESTAMPTZ,
  account_created_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  account_created_at TIMESTAMPTZ,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_subscription_requests_booking_policy_chk CHECK (
    booking_policy IN ('instant', 'approval_required')
  ),
  CONSTRAINT service_provider_subscription_requests_pricing_mode_chk CHECK (
    pricing_mode IN ('fixed', 'starting_from', 'inspection_required', 'custom_quote', 'mixed')
  ),
  CONSTRAINT service_provider_subscription_requests_gender_chk CHECK (
    provider_gender IS NULL
    OR provider_gender IN ('male', 'female', 'mixed', 'not_applicable')
  ),
  CONSTRAINT service_provider_subscription_requests_status_chk CHECK (
    status IN (
      'pending_offer',
      'offer_sent',
      'offer_accepted',
      'offer_rejected',
      'payment_pending_confirmation',
      'payment_confirmed',
      'account_created',
      'cancelled',
      'rejected'
    )
  ),
  CONSTRAINT service_provider_subscription_requests_profile_modes_chk CHECK (
    serves_at_home = TRUE OR serves_at_shop = TRUE OR serves_remote = TRUE
  )
);

CREATE TABLE IF NOT EXISTS service_provider_subscription_offers (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_provider_subscription_requests(id) ON DELETE CASCADE,
  offered_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  amount NUMERIC(14,2) NOT NULL,
  currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  title VARCHAR(160),
  description TEXT,
  valid_until TIMESTAMPTZ,
  status VARCHAR(30) NOT NULL DEFAULT 'pending_provider',
  provider_response_note TEXT,
  provider_responded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_subscription_offers_amount_chk CHECK (amount >= 0),
  CONSTRAINT service_provider_subscription_offers_status_chk CHECK (
    status IN ('pending_provider', 'accepted', 'rejected', 'superseded', 'cancelled', 'expired')
  )
);

CREATE TABLE IF NOT EXISTS service_provider_subscription_status_history (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_provider_subscription_requests(id) ON DELETE CASCADE,
  from_status VARCHAR(40),
  to_status VARCHAR(40) NOT NULL,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  changed_by_actor VARCHAR(24) NOT NULL DEFAULT 'system',
  note TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_subscription_status_history_actor_chk CHECK (
    changed_by_actor IN ('provider', 'admin', 'system')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_provider_subscription_requests_phone_status
  ON service_provider_subscription_requests (phone, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_provider_subscription_requests_status_created
  ON service_provider_subscription_requests (status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_provider_subscription_requests_active_phone
  ON service_provider_subscription_requests (phone)
  WHERE status IN (
    'pending_offer',
    'offer_sent',
    'offer_accepted',
    'payment_pending_confirmation',
    'payment_confirmed'
  );

CREATE INDEX IF NOT EXISTS idx_service_provider_subscription_offers_request_status
  ON service_provider_subscription_offers (request_id, status, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_provider_subscription_offers_single_pending
  ON service_provider_subscription_offers (request_id)
  WHERE status = 'pending_provider';

CREATE INDEX IF NOT EXISTS idx_service_provider_subscription_status_history_request
  ON service_provider_subscription_status_history (request_id, created_at DESC);

COMMIT;
