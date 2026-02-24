BEGIN;

CREATE TYPE user_role AS ENUM ('user', 'admin');

ALTER TABLE app_user
ADD COLUMN IF NOT EXISTS role user_role NOT NULL DEFAULT 'user';

COMMIT;