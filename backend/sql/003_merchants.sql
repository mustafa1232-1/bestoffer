BEGIN;

CREATE TYPE merchant_type AS ENUM ('restaurant', 'market');

CREATE TABLE IF NOT EXISTS merchant (
  id              BIGSERIAL PRIMARY KEY,
  name            VARCHAR(150) NOT NULL,
  type            merchant_type NOT NULL,
  description     TEXT,
  phone           VARCHAR(20),
  image_url       TEXT,
  is_open         BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION set_merchant_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_merchant_updated ON merchant;
CREATE TRIGGER trg_merchant_updated
BEFORE UPDATE ON merchant
FOR EACH ROW
EXECUTE FUNCTION set_merchant_updated_at();

COMMIT;