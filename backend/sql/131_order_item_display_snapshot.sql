ALTER TABLE IF EXISTS order_item
  ADD COLUMN IF NOT EXISTS display_snapshot_json JSONB;
