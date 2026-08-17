-- 205_social_stickers.sql
-- Server-seeded sticker catalog so every user sees the same pack without an app
-- update. Stickers are emoji glyphs (rendered large & borderless by the client);
-- kind='image' rows may later hold uploaded/custom sticker URLs.

BEGIN;

CREATE TABLE IF NOT EXISTS social_sticker (
  id          BIGSERIAL PRIMARY KEY,
  pack        VARCHAR(40) NOT NULL DEFAULT 'classic',
  kind        VARCHAR(16) NOT NULL DEFAULT 'emoji'
    CHECK (kind IN ('emoji', 'image')),
  content     TEXT NOT NULL,
  label       VARCHAR(60),
  sort_order  INT NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT social_sticker_pack_content_unique UNIQUE (pack, content)
);

CREATE INDEX IF NOT EXISTS idx_social_sticker_active
  ON social_sticker (is_active, pack, sort_order);

INSERT INTO social_sticker (pack, kind, content, label, sort_order) VALUES
  ('classic', 'emoji', '😀', 'grin', 1),
  ('classic', 'emoji', '😂', 'laugh', 2),
  ('classic', 'emoji', '🥰', 'love', 3),
  ('classic', 'emoji', '😍', 'heart-eyes', 4),
  ('classic', 'emoji', '😎', 'cool', 5),
  ('classic', 'emoji', '😭', 'cry', 6),
  ('classic', 'emoji', '😡', 'angry', 7),
  ('classic', 'emoji', '🥳', 'party', 8),
  ('classic', 'emoji', '🤔', 'thinking', 9),
  ('classic', 'emoji', '👍', 'thumbs-up', 10),
  ('classic', 'emoji', '👎', 'thumbs-down', 11),
  ('classic', 'emoji', '👏', 'clap', 12),
  ('classic', 'emoji', '🙏', 'pray', 13),
  ('classic', 'emoji', '🔥', 'fire', 14),
  ('classic', 'emoji', '💯', 'hundred', 15),
  ('classic', 'emoji', '❤️', 'heart', 16),
  ('classic', 'emoji', '🎉', 'tada', 17),
  ('classic', 'emoji', '😴', 'sleep', 18),
  ('classic', 'emoji', '🤗', 'hug', 19),
  ('classic', 'emoji', '😅', 'sweat-smile', 20),
  ('classic', 'emoji', '😉', 'wink', 21),
  ('classic', 'emoji', '😜', 'tongue', 22),
  ('classic', 'emoji', '🤩', 'star-struck', 23),
  ('classic', 'emoji', '😱', 'scream', 24),
  ('classic', 'emoji', '🤯', 'mind-blown', 25),
  ('classic', 'emoji', '🥺', 'pleading', 26),
  ('classic', 'emoji', '😇', 'angel', 27),
  ('classic', 'emoji', '🤣', 'rofl', 28),
  ('classic', 'emoji', '💪', 'strong', 29),
  ('classic', 'emoji', '👀', 'eyes', 30)
ON CONFLICT (pack, content) DO NOTHING;

COMMIT;
