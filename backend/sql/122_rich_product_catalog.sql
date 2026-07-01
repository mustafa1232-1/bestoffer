-- Rich product catalog: normalized attributes, variant groups/options, media,
-- and additive order item variant snapshot columns.

ALTER TABLE product
  ADD COLUMN IF NOT EXISTS metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS product_attribute (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  attribute_code VARCHAR(80) NOT NULL,
  label_ar VARCHAR(120),
  label_en VARCHAR(120),
  value_text VARCHAR(240) NOT NULL,
  value_unit VARCHAR(40),
  show_in_card BOOLEAN NOT NULL DEFAULT FALSE,
  show_in_details BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_attribute_unique_value
  ON product_attribute (product_id, attribute_code, value_text);

CREATE INDEX IF NOT EXISTS idx_product_attribute_product_sort
  ON product_attribute (product_id, show_in_card, sort_order, id);

CREATE TABLE IF NOT EXISTS product_variant_group (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  group_code VARCHAR(80) NOT NULL,
  label_ar VARCHAR(120),
  label_en VARCHAR(120),
  display_mode VARCHAR(32) NOT NULL DEFAULT 'chips',
  selection_mode VARCHAR(32) NOT NULL DEFAULT 'single',
  required BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variant_group_unique_code
  ON product_variant_group (product_id, group_code);

CREATE INDEX IF NOT EXISTS idx_product_variant_group_product_sort
  ON product_variant_group (product_id, sort_order, id);

CREATE TABLE IF NOT EXISTS product_variant_option (
  id BIGSERIAL PRIMARY KEY,
  group_id BIGINT NOT NULL REFERENCES product_variant_group(id) ON DELETE CASCADE,
  option_code VARCHAR(80) NOT NULL,
  label_ar VARCHAR(120),
  label_en VARCHAR(120),
  swatch_hex VARCHAR(16),
  price_delta NUMERIC(12,2) NOT NULL DEFAULT 0,
  image_url TEXT,
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variant_option_unique_code
  ON product_variant_option (group_id, option_code);

CREATE INDEX IF NOT EXISTS idx_product_variant_option_group_sort
  ON product_variant_option (group_id, is_available, sort_order, id);

CREATE TABLE IF NOT EXISTS product_media (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  alt_text VARCHAR(180),
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  variant_group_code VARCHAR(80),
  variant_option_code VARCHAR(80),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_media_unique_image
  ON product_media (product_id, image_url);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_media_single_primary
  ON product_media (product_id)
  WHERE is_primary = TRUE;

CREATE INDEX IF NOT EXISTS idx_product_media_product_sort
  ON product_media (product_id, is_primary, sort_order, id);

ALTER TABLE order_item
  ADD COLUMN IF NOT EXISTS selected_variant_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS selected_variant_options_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS variant_price_delta_total NUMERIC(12,2) NOT NULL DEFAULT 0;

INSERT INTO product_media (product_id, image_url, alt_text, is_primary, sort_order, metadata_json)
SELECT
  p.id,
  p.image_url,
  p.name,
  TRUE,
  0,
  jsonb_build_object('source', 'legacy_image_url')
FROM product p
WHERE p.image_url IS NOT NULL
  AND btrim(p.image_url) <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM product_media pm
    WHERE pm.product_id = p.id
  )
ON CONFLICT (product_id, image_url) DO NOTHING;
