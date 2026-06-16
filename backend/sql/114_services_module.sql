BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = 'service_provider'
    ) THEN
      ALTER TYPE user_role ADD VALUE 'service_provider';
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS service_categories (
  id BIGSERIAL PRIMARY KEY,
  parent_id BIGINT REFERENCES service_categories(id) ON DELETE CASCADE,
  level SMALLINT NOT NULL,
  name VARCHAR(120) NOT NULL,
  name_en VARCHAR(120),
  normalized_name TEXT GENERATED ALWAYS AS (
    lower(regexp_replace(name, '\\s+', '', 'g'))
  ) STORED,
  parent_id_resolved BIGINT GENERATED ALWAYS AS (COALESCE(parent_id, 0)) STORED,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_public BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_categories_level_chk CHECK (level IN (1,2)),
  CONSTRAINT service_categories_parent_shape_chk CHECK (
    (level = 1 AND parent_id IS NULL)
    OR
    (level = 2 AND parent_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_categories_parent_name
  ON service_categories (parent_id_resolved, normalized_name);

CREATE INDEX IF NOT EXISTS idx_service_categories_parent_sort
  ON service_categories (parent_id, sort_order ASC, id ASC);

CREATE TABLE IF NOT EXISTS service_category_suggestions (
  id BIGSERIAL PRIMARY KEY,
  suggested_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  parent_category_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  suggestion_type VARCHAR(20) NOT NULL,
  name VARCHAR(120) NOT NULL,
  normalized_name TEXT GENERATED ALWAYS AS (
    lower(regexp_replace(name, '\\s+', '', 'g'))
  ) STORED,
  details TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  merge_target_category_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_category_suggestions_type_chk CHECK (
    suggestion_type IN ('main', 'sub')
  ),
  CONSTRAINT service_category_suggestions_status_chk CHECK (
    status IN ('pending', 'approved', 'rejected', 'merged')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_category_suggestions_status_created
  ON service_category_suggestions (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_category_suggestions_lookup
  ON service_category_suggestions (parent_category_id, normalized_name);

CREATE TABLE IF NOT EXISTS service_provider_profiles (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
  business_name VARCHAR(180) NOT NULL,
  logo_url TEXT,
  cover_image_url TEXT,
  main_category_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  bio TEXT,
  phone VARCHAR(32) NOT NULL,
  whatsapp_phone VARCHAR(32),
  city VARCHAR(120) NOT NULL,
  area VARCHAR(120),
  address_line TEXT,
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  service_radius_km NUMERIC(8,2),
  serves_at_home BOOLEAN NOT NULL DEFAULT TRUE,
  serves_at_shop BOOLEAN NOT NULL DEFAULT FALSE,
  serves_remote BOOLEAN NOT NULL DEFAULT FALSE,
  has_emergency_service BOOLEAN NOT NULL DEFAULT FALSE,
  booking_policy VARCHAR(30) NOT NULL DEFAULT 'approval_required',
  pricing_mode VARCHAR(30) NOT NULL DEFAULT 'mixed',
  provider_approval_status VARCHAR(30) NOT NULL DEFAULT 'pending',
  approval_note TEXT,
  approved_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  years_experience INTEGER,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  has_team BOOLEAN NOT NULL DEFAULT FALSE,
  team_size INTEGER,
  coverage_geo_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  accepts_cash BOOLEAN NOT NULL DEFAULT TRUE,
  accepts_electronic BOOLEAN NOT NULL DEFAULT FALSE,
  average_response_minutes INTEGER,
  is_available_24_7 BOOLEAN NOT NULL DEFAULT FALSE,
  languages_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  provider_gender VARCHAR(24),
  completed_orders_count INTEGER NOT NULL DEFAULT 0,
  rating_avg NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  is_featured BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_temporarily_paused BOOLEAN NOT NULL DEFAULT FALSE,
  pause_reason TEXT,
  search_text TEXT,
  search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector(
      'simple',
      COALESCE(business_name, '') || ' ' ||
      COALESCE(bio, '') || ' ' ||
      COALESCE(city, '') || ' ' ||
      COALESCE(area, '') || ' ' ||
      COALESCE(search_text, '')
    )
  ) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_profiles_booking_policy_chk CHECK (
    booking_policy IN ('instant', 'approval_required')
  ),
  CONSTRAINT service_provider_profiles_pricing_mode_chk CHECK (
    pricing_mode IN ('fixed', 'starting_from', 'inspection_required', 'custom_quote', 'mixed')
  ),
  CONSTRAINT service_provider_profiles_approval_chk CHECK (
    provider_approval_status IN ('pending', 'approved', 'rejected', 'suspended')
  ),
  CONSTRAINT service_provider_profiles_gender_chk CHECK (
    provider_gender IS NULL
    OR provider_gender IN ('male', 'female', 'mixed', 'not_applicable')
  ),
  CONSTRAINT service_provider_profiles_rating_chk CHECK (
    rating_avg >= 0 AND rating_avg <= 5
  )
);

CREATE INDEX IF NOT EXISTS idx_service_provider_profiles_status
  ON service_provider_profiles (provider_approval_status, is_active, is_temporarily_paused);

CREATE INDEX IF NOT EXISTS idx_service_provider_profiles_city_area
  ON service_provider_profiles (city, area);

CREATE INDEX IF NOT EXISTS idx_service_provider_profiles_rating
  ON service_provider_profiles (rating_avg DESC, rating_count DESC);

CREATE INDEX IF NOT EXISTS idx_service_provider_profiles_search
  ON service_provider_profiles USING GIN (search_vector);

CREATE TABLE IF NOT EXISTS service_provider_areas (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  city VARCHAR(120) NOT NULL,
  area VARCHAR(120),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider_id, city, area)
);

CREATE TABLE IF NOT EXISTS service_provider_availability_rules (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_availability_day_chk CHECK (
    day_of_week BETWEEN 0 AND 6
  ),
  CONSTRAINT service_provider_availability_time_chk CHECK (
    end_time > start_time
  )
);

CREATE INDEX IF NOT EXISTS idx_service_provider_availability_provider_day
  ON service_provider_availability_rules (provider_id, day_of_week);

CREATE TABLE IF NOT EXISTS service_provider_unavailable_slots (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_provider_unavailable_slots_time_chk CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_service_provider_unavailable_slots_window
  ON service_provider_unavailable_slots (provider_id, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS service_offerings (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  main_category_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  subcategory_id BIGINT REFERENCES service_categories(id) ON DELETE SET NULL,
  name VARCHAR(180) NOT NULL,
  normalized_name TEXT GENERATED ALWAYS AS (
    lower(regexp_replace(name, '\\s+', '', 'g'))
  ) STORED,
  subcategory_id_resolved BIGINT GENERATED ALWAYS AS (COALESCE(subcategory_id, 0)) STORED,
  description TEXT,
  execution_mode VARCHAR(32) NOT NULL DEFAULT 'both',
  requires_schedule BOOLEAN NOT NULL DEFAULT TRUE,
  requires_provider_approval BOOLEAN NOT NULL DEFAULT TRUE,
  estimated_duration_minutes INTEGER,
  has_fixed_price BOOLEAN NOT NULL DEFAULT FALSE,
  starts_from_price NUMERIC(14,2),
  inspection_required BOOLEAN NOT NULL DEFAULT FALSE,
  custom_quote_only BOOLEAN NOT NULL DEFAULT FALSE,
  workers_count INTEGER,
  includes_text TEXT,
  excludes_text TEXT,
  materials_text TEXT,
  notes TEXT,
  supports_hourly_booking BOOLEAN NOT NULL DEFAULT FALSE,
  supports_daily_booking BOOLEAN NOT NULL DEFAULT FALSE,
  supports_visit_booking BOOLEAN NOT NULL DEFAULT TRUE,
  supports_full_day_booking BOOLEAN NOT NULL DEFAULT FALSE,
  search_text TEXT,
  search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector(
      'simple',
      COALESCE(name, '') || ' ' ||
      COALESCE(description, '') || ' ' ||
      COALESCE(search_text, '') || ' ' ||
      COALESCE(includes_text, '') || ' ' ||
      COALESCE(materials_text, '')
    )
  ) STORED,
  moderation_status VARCHAR(30) NOT NULL DEFAULT 'pending',
  moderation_note TEXT,
  moderated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  moderated_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_temporarily_paused BOOLEAN NOT NULL DEFAULT FALSE,
  pause_reason TEXT,
  completed_orders_count INTEGER NOT NULL DEFAULT 0,
  rating_avg NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_offerings_execution_mode_chk CHECK (
    execution_mode IN ('home', 'provider_location', 'both', 'remote')
  ),
  CONSTRAINT service_offerings_moderation_chk CHECK (
    moderation_status IN ('pending', 'approved', 'rejected', 'hidden')
  ),
  CONSTRAINT service_offerings_rating_chk CHECK (
    rating_avg >= 0 AND rating_avg <= 5
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_offerings_provider_name_per_sub
  ON service_offerings (provider_id, subcategory_id_resolved, normalized_name);

CREATE INDEX IF NOT EXISTS idx_service_offerings_provider_status
  ON service_offerings (provider_id, moderation_status, is_active);

CREATE INDEX IF NOT EXISTS idx_service_offerings_category
  ON service_offerings (main_category_id, subcategory_id);

CREATE INDEX IF NOT EXISTS idx_service_offerings_search
  ON service_offerings USING GIN (search_vector);

CREATE TABLE IF NOT EXISTS service_offering_media (
  id BIGSERIAL PRIMARY KEY,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL,
  media_kind VARCHAR(20) NOT NULL DEFAULT 'image',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_offering_media_kind_chk CHECK (
    media_kind IN ('image', 'video')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_offering_media_offering
  ON service_offering_media (offering_id, sort_order ASC, id ASC);

CREATE TABLE IF NOT EXISTS service_pricing_options (
  id BIGSERIAL PRIMARY KEY,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  pricing_model VARCHAR(40) NOT NULL,
  pricing_unit VARCHAR(40) NOT NULL,
  label VARCHAR(120),
  amount NUMERIC(14,2),
  min_amount NUMERIC(14,2),
  max_amount NUMERIC(14,2),
  visit_fee NUMERIC(14,2),
  currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  min_quantity NUMERIC(12,2),
  max_quantity NUMERIC(12,2),
  inspection_required BOOLEAN NOT NULL DEFAULT FALSE,
  notes TEXT,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_pricing_options_model_chk CHECK (
    pricing_model IN (
      'per_hour',
      'per_visit',
      'per_day',
      'per_device',
      'per_room',
      'per_meter',
      'per_item',
      'fixed_package',
      'starting_from',
      'inspection_required',
      'custom_quote'
    )
  ),
  CONSTRAINT service_pricing_options_unit_chk CHECK (
    pricing_unit IN (
      'hour',
      'visit',
      'day',
      'device',
      'room',
      'meter',
      'item',
      'package',
      'job',
      'custom'
    )
  ),
  CONSTRAINT service_pricing_options_amount_chk CHECK (
    (
      pricing_model IN ('inspection_required', 'custom_quote')
      AND amount IS NULL
    )
    OR
    (
      pricing_model NOT IN ('inspection_required', 'custom_quote')
      AND amount IS NOT NULL
      AND amount >= 0
    )
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_pricing_options_single_default
  ON service_pricing_options (offering_id)
  WHERE is_default = TRUE;

CREATE INDEX IF NOT EXISTS idx_service_pricing_options_offering
  ON service_pricing_options (offering_id, is_active, sort_order ASC, id ASC);

CREATE TABLE IF NOT EXISTS service_promotions (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  title VARCHAR(160) NOT NULL,
  description TEXT,
  discount_type VARCHAR(24) NOT NULL,
  discount_value NUMERIC(14,2),
  special_price NUMERIC(14,2),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  badge_color VARCHAR(32),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  auto_deactivated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_promotions_type_chk CHECK (
    discount_type IN ('percentage', 'fixed', 'special_price')
  ),
  CONSTRAINT service_promotions_time_chk CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_service_promotions_provider_window
  ON service_promotions (provider_id, is_active, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS service_promotion_targets (
  promotion_id BIGINT NOT NULL REFERENCES service_promotions(id) ON DELETE CASCADE,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  PRIMARY KEY (promotion_id, offering_id)
);

CREATE TABLE IF NOT EXISTS service_portfolio_items (
  id BIGSERIAL PRIMARY KEY,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  offering_id BIGINT REFERENCES service_offerings(id) ON DELETE SET NULL,
  title VARCHAR(180),
  description TEXT,
  media_url TEXT NOT NULL,
  media_kind VARCHAR(20) NOT NULL DEFAULT 'image',
  before_media_url TEXT,
  after_media_url TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_portfolio_items_media_kind_chk CHECK (
    media_kind IN ('image', 'video')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_portfolio_items_provider
  ON service_portfolio_items (provider_id, is_pinned DESC, sort_order ASC, id ASC);

CREATE TABLE IF NOT EXISTS service_requests (
  id BIGSERIAL PRIMARY KEY,
  request_code VARCHAR(40) UNIQUE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  pricing_option_id BIGINT REFERENCES service_pricing_options(id) ON DELETE SET NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'pending',
  requested_execution_mode VARCHAR(32),
  requested_date DATE,
  requested_time TIME,
  quantity NUMERIC(12,2),
  duration_hours NUMERIC(8,2),
  notes TEXT,
  address_line TEXT,
  city VARCHAR(120),
  area VARCHAR(120),
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  requires_home_service BOOLEAN NOT NULL DEFAULT FALSE,
  requires_quote BOOLEAN NOT NULL DEFAULT FALSE,
  final_price NUMERIC(14,2),
  final_currency VARCHAR(8),
  final_pricing_model VARCHAR(40),
  final_pricing_unit VARCHAR(40),
  accepted_quote_id BIGINT,
  scheduled_start_at TIMESTAMPTZ,
  scheduled_end_at TIMESTAMPTZ,
  cancelled_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  cancel_reason TEXT,
  rejected_reason TEXT,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_requests_status_chk CHECK (
    status IN (
      'pending',
      'awaiting_provider',
      'accepted',
      'scheduled',
      'in_progress',
      'completed',
      'cancelled',
      'rejected'
    )
  ),
  CONSTRAINT service_requests_execution_mode_chk CHECK (
    requested_execution_mode IS NULL
    OR requested_execution_mode IN ('home', 'provider_location', 'both', 'remote')
  ),
  CONSTRAINT service_requests_schedule_chk CHECK (
    scheduled_end_at IS NULL
    OR scheduled_start_at IS NULL
    OR scheduled_end_at > scheduled_start_at
  )
);

CREATE INDEX IF NOT EXISTS idx_service_requests_customer_status
  ON service_requests (customer_user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_requests_provider_status
  ON service_requests (provider_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_requests_provider_schedule
  ON service_requests (provider_id, scheduled_start_at DESC)
  WHERE scheduled_start_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS service_request_attachments (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  media_url TEXT NOT NULL,
  media_kind VARCHAR(20) NOT NULL DEFAULT 'image',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_request_attachments_kind_chk CHECK (
    media_kind IN ('image', 'video', 'file')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_request_attachments_request
  ON service_request_attachments (request_id, id ASC);

CREATE TABLE IF NOT EXISTS service_request_quotes (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  quoted_by_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  round_no INTEGER NOT NULL,
  quote_status VARCHAR(30) NOT NULL DEFAULT 'pending_customer',
  pricing_model VARCHAR(40) NOT NULL,
  pricing_unit VARCHAR(40) NOT NULL,
  amount NUMERIC(14,2),
  min_amount NUMERIC(14,2),
  max_amount NUMERIC(14,2),
  visit_fee NUMERIC(14,2),
  currency VARCHAR(8) NOT NULL DEFAULT 'IQD',
  inspection_required BOOLEAN NOT NULL DEFAULT FALSE,
  proposed_visit_at TIMESTAMPTZ,
  proposed_start_at TIMESTAMPTZ,
  proposed_end_at TIMESTAMPTZ,
  note TEXT,
  expires_at TIMESTAMPTZ,
  responded_at TIMESTAMPTZ,
  responded_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_request_quotes_status_chk CHECK (
    quote_status IN ('pending_customer', 'accepted', 'rejected', 'expired', 'cancelled')
  ),
  CONSTRAINT service_request_quotes_model_chk CHECK (
    pricing_model IN (
      'per_hour',
      'per_visit',
      'per_day',
      'per_device',
      'per_room',
      'per_meter',
      'per_item',
      'fixed_package',
      'starting_from',
      'inspection_required',
      'custom_quote'
    )
  ),
  CONSTRAINT service_request_quotes_unit_chk CHECK (
    pricing_unit IN ('hour', 'visit', 'day', 'device', 'room', 'meter', 'item', 'package', 'job', 'custom')
  ),
  CONSTRAINT service_request_quotes_window_chk CHECK (
    proposed_end_at IS NULL
    OR proposed_start_at IS NULL
    OR proposed_end_at > proposed_start_at
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_service_request_quotes_round
  ON service_request_quotes (request_id, round_no);

CREATE INDEX IF NOT EXISTS idx_service_request_quotes_status
  ON service_request_quotes (request_id, quote_status, created_at DESC);

ALTER TABLE service_requests
  DROP CONSTRAINT IF EXISTS service_requests_accepted_quote_fk;

ALTER TABLE service_requests
  ADD CONSTRAINT service_requests_accepted_quote_fk
  FOREIGN KEY (accepted_quote_id) REFERENCES service_request_quotes(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS service_request_status_history (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  previous_status VARCHAR(30),
  next_status VARCHAR(30) NOT NULL,
  changed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_request_status_history_request
  ON service_request_status_history (request_id, created_at DESC);

CREATE TABLE IF NOT EXISTS service_reviews (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL UNIQUE REFERENCES service_requests(id) ON DELETE CASCADE,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL,
  comment TEXT,
  service_as_described BOOLEAN,
  on_time BOOLEAN,
  price_fair BOOLEAN,
  recommend BOOLEAN,
  image_urls_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_reviews_rating_chk CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX IF NOT EXISTS idx_service_reviews_provider
  ON service_reviews (provider_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_reviews_offering
  ON service_reviews (offering_id, created_at DESC);

CREATE TABLE IF NOT EXISTS service_saved_providers (
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  provider_id BIGINT NOT NULL REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, provider_id)
);

CREATE TABLE IF NOT EXISTS service_saved_offerings (
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  offering_id BIGINT NOT NULL REFERENCES service_offerings(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, offering_id)
);

CREATE TABLE IF NOT EXISTS service_recent_views (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  provider_id BIGINT REFERENCES service_provider_profiles(id) ON DELETE CASCADE,
  offering_id BIGINT REFERENCES service_offerings(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_recent_views_target_chk CHECK (
    provider_id IS NOT NULL OR offering_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_service_recent_views_user
  ON service_recent_views (user_id, viewed_at DESC);

CREATE TABLE IF NOT EXISTS service_reports (
  id BIGSERIAL PRIMARY KEY,
  reporter_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  target_type VARCHAR(24) NOT NULL,
  target_id BIGINT NOT NULL,
  reason VARCHAR(160),
  details TEXT,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  reviewed_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT service_reports_target_type_chk CHECK (
    target_type IN ('provider', 'offering', 'request', 'review', 'message')
  ),
  CONSTRAINT service_reports_status_chk CHECK (
    status IN ('pending', 'resolved', 'rejected')
  )
);

CREATE INDEX IF NOT EXISTS idx_service_reports_status_created
  ON service_reports (status, created_at DESC);

CREATE TABLE IF NOT EXISTS service_module_settings (
  id BIGSERIAL PRIMARY KEY,
  key VARCHAR(120) NOT NULL UNIQUE,
  value_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO service_module_settings (key, value_json)
VALUES ('services_enabled', '{"enabled": true}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Seed root categories
INSERT INTO service_categories (parent_id, level, name, sort_order, is_active, is_public)
VALUES
  (NULL, 1, 'صيانة منزلية', 1, TRUE, TRUE),
  (NULL, 1, 'كهرباء', 2, TRUE, TRUE),
  (NULL, 1, 'سباكة', 3, TRUE, TRUE),
  (NULL, 1, 'تكييف وتبريد', 4, TRUE, TRUE),
  (NULL, 1, 'تنظيف', 5, TRUE, TRUE),
  (NULL, 1, 'خدمات منزلية', 6, TRUE, TRUE),
  (NULL, 1, 'صيانة أجهزة', 7, TRUE, TRUE),
  (NULL, 1, 'أثاث ونجارة', 8, TRUE, TRUE),
  (NULL, 1, 'دهان وديكور', 9, TRUE, TRUE),
  (NULL, 1, 'بناء وترميم', 10, TRUE, TRUE),
  (NULL, 1, 'إنترنت وكاميرات وستلايت', 11, TRUE, TRUE),
  (NULL, 1, 'نقل وتحميل', 12, TRUE, TRUE),
  (NULL, 1, 'ضيافة وطعام', 13, TRUE, TRUE),
  (NULL, 1, 'تجميل وعناية', 14, TRUE, TRUE),
  (NULL, 1, 'رعاية ومساعدة', 15, TRUE, TRUE),
  (NULL, 1, 'خدمات سيارات متنقلة', 16, TRUE, TRUE),
  (NULL, 1, 'خدمات مناسبات', 17, TRUE, TRUE),
  (NULL, 1, 'خدمات عمالة وتأجير', 18, TRUE, TRUE)
ON CONFLICT (parent_id_resolved, normalized_name) DO UPDATE
SET
  is_active = EXCLUDED.is_active,
  is_public = EXCLUDED.is_public,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();

WITH root AS (
  SELECT id, name
  FROM service_categories
  WHERE level = 1 AND parent_id IS NULL
),
subs(parent_name, name, sort_order) AS (
  VALUES
    ('صيانة منزلية', 'صيانة عامة', 1),
    ('صيانة منزلية', 'أعمال بسيطة منزلية', 2),
    ('صيانة منزلية', 'تركيب رفوف', 3),
    ('صيانة منزلية', 'تركيب ستائر', 4),
    ('صيانة منزلية', 'تركيب أبواب', 5),
    ('صيانة منزلية', 'تبديل مفصلات', 6),

    ('كهرباء', 'تمديدات', 1),
    ('كهرباء', 'تبديل مفاتيح', 2),
    ('كهرباء', 'أعطال كهرباء', 3),
    ('كهرباء', 'تركيب إنارة', 4),
    ('كهرباء', 'صيانة مولدات صغيرة', 5),

    ('سباكة', 'تصليح تسريبات', 1),
    ('سباكة', 'تركيب مغاسل', 2),
    ('سباكة', 'تركيب سخانات', 3),
    ('سباكة', 'فتح مجاري', 4),
    ('سباكة', 'صيانة مضخات', 5),

    ('تكييف وتبريد', 'تنظيف سبالت', 1),
    ('تكييف وتبريد', 'تعبئة غاز', 2),
    ('تكييف وتبريد', 'صيانة أعطال', 3),
    ('تكييف وتبريد', 'تركيب مكيفات', 4),
    ('تكييف وتبريد', 'فك ونقل مكيف', 5),

    ('تنظيف', 'تنظيف شقق', 1),
    ('تنظيف', 'تنظيف مجالس', 2),
    ('تنظيف', 'تنظيف مكاتب', 3),
    ('تنظيف', 'تنظيف خزانات', 4),
    ('تنظيف', 'تنظيف واجهات', 5),
    ('تنظيف', 'تعقيم', 6),

    ('خدمات منزلية', 'عاملات تنظيف', 1),
    ('خدمات منزلية', 'جليسة أطفال', 2),
    ('خدمات منزلية', 'جليسة كبار السن', 3),
    ('خدمات منزلية', 'سائق خاص', 4),
    ('خدمات منزلية', 'مساعد منزلي', 5),

    ('صيانة أجهزة', 'تصليح طباخات', 1),
    ('صيانة أجهزة', 'تصليح غسالات', 2),
    ('صيانة أجهزة', 'تصليح ثلاجات', 3),
    ('صيانة أجهزة', 'تصليح أفران', 4),
    ('صيانة أجهزة', 'صيانة مجففات', 5),
    ('صيانة أجهزة', 'صيانة أجهزة صغيرة', 6),

    ('أثاث ونجارة', 'نجارة منزلية', 1),
    ('أثاث ونجارة', 'تركيب أثاث', 2),
    ('أثاث ونجارة', 'تفصيل أثاث', 3),
    ('أثاث ونجارة', 'تصليح أبواب', 4),
    ('أثاث ونجارة', 'تصليح خزائن', 5),

    ('دهان وديكور', 'دهان داخلي', 1),
    ('دهان وديكور', 'دهان خارجي', 2),
    ('دهان وديكور', 'جبسن بورد', 3),
    ('دهان وديكور', 'ورق جدران', 4),
    ('دهان وديكور', 'ديكورات بسيطة', 5),

    ('بناء وترميم', 'ترميم', 1),
    ('بناء وترميم', 'تبليط', 2),
    ('بناء وترميم', 'قصارة', 3),
    ('بناء وترميم', 'بناء', 4),
    ('بناء وترميم', 'صبغ واجهات', 5),
    ('بناء وترميم', 'أعمال إسمنتية', 6),

    ('إنترنت وكاميرات وستلايت', 'تمديد إنترنت', 1),
    ('إنترنت وكاميرات وستلايت', 'صيانة راوتر', 2),
    ('إنترنت وكاميرات وستلايت', 'تركيب كاميرات', 3),
    ('إنترنت وكاميرات وستلايت', 'صيانة ستلايت', 4),
    ('إنترنت وكاميرات وستلايت', 'شبكات منزلية', 5),

    ('نقل وتحميل', 'نقل أثاث', 1),
    ('نقل وتحميل', 'تحميل وتنزيل', 2),
    ('نقل وتحميل', 'فك وتركيب أثاث', 3),
    ('نقل وتحميل', 'نقل أجهزة', 4),

    ('ضيافة وطعام', 'طباخ منزلي', 1),
    ('ضيافة وطعام', 'إعداد ولائم', 2),
    ('ضيافة وطعام', 'شيف خاص', 3),
    ('ضيافة وطعام', 'معجنات منزلية', 4),
    ('ضيافة وطعام', 'ضيافة مناسبات', 5),

    ('تجميل وعناية', 'حلاقة منزلية', 1),
    ('تجميل وعناية', 'مكياج منزلي', 2),
    ('تجميل وعناية', 'عناية بالبشرة', 3),
    ('تجميل وعناية', 'تصفيف شعر', 4),
    ('تجميل وعناية', 'خدمات عرائس', 5),

    ('رعاية ومساعدة', 'جليسة مريض', 1),
    ('رعاية ومساعدة', 'مساعد شخصي', 2),
    ('رعاية ومساعدة', 'رعاية كبار السن', 3),
    ('رعاية ومساعدة', 'رعاية ما بعد العمليات', 4),

    ('خدمات سيارات متنقلة', 'كهربائي سيارات', 1),
    ('خدمات سيارات متنقلة', 'بنچرجي متنقل', 2),
    ('خدمات سيارات متنقلة', 'تبديل بطارية', 3),
    ('خدمات سيارات متنقلة', 'سحب سيارة', 4),
    ('خدمات سيارات متنقلة', 'غسيل متنقل', 5),

    ('خدمات مناسبات', 'تنظيم مناسبات', 1),
    ('خدمات مناسبات', 'تأجير كراسي وطاولات', 2),
    ('خدمات مناسبات', 'زينة', 3),
    ('خدمات مناسبات', 'تجهيز مجالس', 4),
    ('خدمات مناسبات', 'صوتيات', 5),

    ('خدمات عمالة وتأجير', 'تأجير عامل تنظيف', 1),
    ('خدمات عمالة وتأجير', 'تأجير عمال تحميل', 2),
    ('خدمات عمالة وتأجير', 'تأجير عمال يوميين', 3),
    ('خدمات عمالة وتأجير', 'فني بالساعة', 4),
    ('خدمات عمالة وتأجير', 'عاملة يوم كامل', 5)
)
INSERT INTO service_categories (parent_id, level, name, sort_order, is_active, is_public)
SELECT r.id, 2, s.name, s.sort_order, TRUE, TRUE
FROM subs s
JOIN root r ON r.name = s.parent_name
ON CONFLICT (parent_id_resolved, normalized_name) DO UPDATE
SET
  sort_order = EXCLUDED.sort_order,
  is_active = TRUE,
  is_public = TRUE,
  updated_at = NOW();

-- Extend business thread context and shared entities for services module
ALTER TABLE social_chat_thread
  DROP CONSTRAINT IF EXISTS social_chat_thread_context_type_chk;

ALTER TABLE social_chat_thread
  ADD CONSTRAINT social_chat_thread_context_type_chk
  CHECK (
    context_type IN (
      'none',
      'car_listing',
      'real_estate_listing',
      'service_offering',
      'service_provider',
      'service_request'
    )
  );

ALTER TABLE social_chat_message
  DROP CONSTRAINT IF EXISTS social_chat_message_shared_entity_type_chk;

ALTER TABLE social_chat_message
  ADD CONSTRAINT social_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN (
      'post',
      'reel',
      'review',
      'car_listing',
      'real_estate_listing',
      'location',
      'service_offering',
      'service_provider',
      'service_request'
    )
  );

ALTER TABLE social_scope_chat_message
  DROP CONSTRAINT IF EXISTS social_scope_chat_message_shared_entity_type_chk;

ALTER TABLE social_scope_chat_message
  ADD CONSTRAINT social_scope_chat_message_shared_entity_type_chk
  CHECK (
    shared_entity_type IS NULL
    OR shared_entity_type IN (
      'post',
      'reel',
      'review',
      'car_listing',
      'real_estate_listing',
      'location',
      'service_offering',
      'service_provider',
      'service_request'
    )
  );

COMMIT;
