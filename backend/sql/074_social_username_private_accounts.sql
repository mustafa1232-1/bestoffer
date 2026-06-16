ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS username VARCHAR(24),
  ADD COLUMN IF NOT EXISTS social_account_private BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE app_user
  DROP CONSTRAINT IF EXISTS app_user_username_format_chk;

ALTER TABLE app_user
  ADD CONSTRAINT app_user_username_format_chk
  CHECK (
    username IS NULL
    OR (
      username ~ '^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$'
      AND username !~ '\.\.'
      AND username !~ '__'
    )
  );

DO $$
DECLARE
  rec RECORD;
  base_username TEXT;
  candidate TEXT;
  suffix INTEGER;
BEGIN
  FOR rec IN
    SELECT id, full_name, phone
    FROM app_user
    WHERE username IS NULL OR LENGTH(TRIM(username)) = 0
    ORDER BY id ASC
  LOOP
    base_username := LOWER(COALESCE(rec.full_name, ''));
    base_username := regexp_replace(base_username, '[^a-z0-9._]+', '.', 'g');
    base_username := regexp_replace(base_username, '\.{2,}', '.', 'g');
    base_username := regexp_replace(base_username, '^\.+|\.+$', '', 'g');
    base_username := regexp_replace(base_username, '_{2,}', '_', 'g');
    base_username := regexp_replace(base_username, '^_+|_+$', '', 'g');

    IF base_username IS NULL OR LENGTH(base_username) < 4 THEN
      base_username := 'user' || rec.id::text;
    END IF;

    IF LENGTH(base_username) > 24 THEN
      base_username := LEFT(base_username, 24);
      base_username := regexp_replace(base_username, '[._]+$', '', 'g');
    END IF;

    IF base_username ~ '^[._]' THEN
      base_username := 'u' || LEFT(base_username, 23);
    END IF;
    IF LENGTH(base_username) < 4 THEN
      base_username := RPAD(base_username, 4, '0');
    END IF;

    candidate := base_username;
    suffix := 0;

    WHILE EXISTS (
      SELECT 1 FROM app_user u
      WHERE LOWER(u.username) = LOWER(candidate)
        AND u.id <> rec.id
    ) LOOP
      suffix := suffix + 1;
      candidate := LEFT(base_username, GREATEST(1, 24 - LENGTH(suffix::text))) || suffix::text;
      candidate := regexp_replace(candidate, '[._]+$', '', 'g');
      IF LENGTH(candidate) < 4 THEN
        candidate := 'user' || rec.id::text;
      END IF;
    END LOOP;

    UPDATE app_user
    SET username = LOWER(candidate)
    WHERE id = rec.id;
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS app_user_username_unique_idx
  ON app_user (LOWER(username));

ALTER TABLE app_user
  ALTER COLUMN username SET NOT NULL;
