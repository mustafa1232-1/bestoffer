-- 100: Materialized post stats table with triggers
-- Replaces 5 LATERAL COUNT subqueries per feed request (was ~900 queries for 60 posts).

CREATE TABLE IF NOT EXISTS social_post_stats (
  post_id           BIGINT PRIMARY KEY REFERENCES social_post(id) ON DELETE CASCADE,
  likes_count       INT NOT NULL DEFAULT 0 CHECK (likes_count >= 0),
  comments_count    INT NOT NULL DEFAULT 0 CHECK (comments_count >= 0),
  saves_count       INT NOT NULL DEFAULT 0 CHECK (saves_count >= 0),
  impressions_count INT NOT NULL DEFAULT 0 CHECK (impressions_count >= 0),
  reel_views_count  INT NOT NULL DEFAULT 0 CHECK (reel_views_count >= 0),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure every new post gets a stats row automatically
CREATE OR REPLACE FUNCTION create_post_stats_row()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO social_post_stats (post_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_post_create_stats ON social_post;
CREATE TRIGGER trg_social_post_create_stats
AFTER INSERT ON social_post
FOR EACH ROW EXECUTE FUNCTION create_post_stats_row();

-- LIKES -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_post_stats_likes()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO social_post_stats (post_id, likes_count, updated_at)
    VALUES (NEW.post_id, 1, NOW())
    ON CONFLICT (post_id) DO UPDATE
    SET likes_count = GREATEST(0, social_post_stats.likes_count + 1),
        updated_at  = NOW();
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE social_post_stats
    SET likes_count = GREATEST(0, likes_count - 1),
        updated_at  = NOW()
    WHERE post_id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_post_like_stats ON social_post_like;
CREATE TRIGGER trg_social_post_like_stats
AFTER INSERT OR DELETE ON social_post_like
FOR EACH ROW EXECUTE FUNCTION update_post_stats_likes();

-- COMMENTS (approved + non-deleted only) -------------------------------------
CREATE OR REPLACE FUNCTION update_post_stats_comments()
RETURNS TRIGGER AS $$
DECLARE
  old_counted BOOLEAN;
  new_counted BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_deleted = FALSE AND NEW.moderation_status = 'approved' THEN
      INSERT INTO social_post_stats (post_id, comments_count, updated_at)
      VALUES (NEW.post_id, 1, NOW())
      ON CONFLICT (post_id) DO UPDATE
      SET comments_count = GREATEST(0, social_post_stats.comments_count + 1),
          updated_at      = NOW();
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    old_counted := (OLD.is_deleted = FALSE AND OLD.moderation_status = 'approved');
    new_counted := (NEW.is_deleted = FALSE AND NEW.moderation_status = 'approved');
    IF old_counted <> new_counted THEN
      UPDATE social_post_stats
      SET comments_count = GREATEST(0, comments_count + (CASE WHEN new_counted THEN 1 ELSE -1 END)),
          updated_at      = NOW()
      WHERE post_id = NEW.post_id;
    END IF;

  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.is_deleted = FALSE AND OLD.moderation_status = 'approved' THEN
      UPDATE social_post_stats
      SET comments_count = GREATEST(0, comments_count - 1),
          updated_at      = NOW()
      WHERE post_id = OLD.post_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_post_comment_stats ON social_post_comment;
CREATE TRIGGER trg_social_post_comment_stats
AFTER INSERT OR UPDATE OF is_deleted, moderation_status OR DELETE ON social_post_comment
FOR EACH ROW EXECUTE FUNCTION update_post_stats_comments();

-- SAVES -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_post_stats_saves()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.entity_type IN ('post', 'reel', 'review') THEN
      INSERT INTO social_post_stats (post_id, saves_count, updated_at)
      VALUES (NEW.entity_id, 1, NOW())
      ON CONFLICT (post_id) DO UPDATE
      SET saves_count = GREATEST(0, social_post_stats.saves_count + 1),
          updated_at  = NOW();
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.entity_type IN ('post', 'reel', 'review') THEN
      UPDATE social_post_stats
      SET saves_count = GREATEST(0, saves_count - 1),
          updated_at  = NOW()
      WHERE post_id = OLD.entity_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_saved_item_stats ON social_saved_item;
CREATE TRIGGER trg_social_saved_item_stats
AFTER INSERT OR DELETE ON social_saved_item
FOR EACH ROW
EXECUTE FUNCTION update_post_stats_saves();

-- IMPRESSIONS -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_post_stats_impressions()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO social_post_stats (post_id, impressions_count, updated_at)
    VALUES (NEW.content_id, 1, NOW())
    ON CONFLICT (post_id) DO UPDATE
    SET impressions_count = GREATEST(0, social_post_stats.impressions_count + 1),
        updated_at        = NOW();
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE social_post_stats
    SET impressions_count = GREATEST(0, impressions_count - 1),
        updated_at        = NOW()
    WHERE post_id = OLD.content_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_content_impression_stats ON social_content_impression;
CREATE TRIGGER trg_social_content_impression_stats
AFTER INSERT OR DELETE ON social_content_impression
FOR EACH ROW EXECUTE FUNCTION update_post_stats_impressions();

-- REEL VIEWS ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_post_stats_reel_views()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO social_post_stats (post_id, reel_views_count, updated_at)
    VALUES (NEW.post_id, 1, NOW())
    ON CONFLICT (post_id) DO UPDATE
    SET reel_views_count = GREATEST(0, social_post_stats.reel_views_count + 1),
        updated_at       = NOW();
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE social_post_stats
    SET reel_views_count = GREATEST(0, reel_views_count - 1),
        updated_at       = NOW()
    WHERE post_id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_social_reel_view_stats ON social_reel_view_event;
CREATE TRIGGER trg_social_reel_view_stats
AFTER INSERT OR DELETE ON social_reel_view_event
FOR EACH ROW EXECUTE FUNCTION update_post_stats_reel_views();

-- Populate initial data for all existing posts
INSERT INTO social_post_stats (
  post_id,
  likes_count,
  comments_count,
  saves_count,
  impressions_count,
  reel_views_count
)
SELECT
  p.id,
  COALESCE((SELECT COUNT(*)::int FROM social_post_like l WHERE l.post_id = p.id), 0),
  COALESCE((
    SELECT COUNT(*)::int FROM social_post_comment c
    WHERE c.post_id = p.id AND c.is_deleted = FALSE AND c.moderation_status = 'approved'
  ), 0),
  COALESCE((
    SELECT COUNT(*)::int FROM social_saved_item s
    WHERE s.entity_id = p.id AND s.entity_type IN ('post', 'reel', 'review')
  ), 0),
  COALESCE((
    SELECT COUNT(*)::int FROM social_content_impression i
    WHERE i.content_id = p.id
  ), 0),
  COALESCE((
    SELECT COUNT(*)::int FROM social_reel_view_event rv WHERE rv.post_id = p.id
  ), 0)
FROM social_post p
ON CONFLICT (post_id) DO UPDATE
SET
  likes_count       = EXCLUDED.likes_count,
  comments_count    = EXCLUDED.comments_count,
  saves_count       = EXCLUDED.saves_count,
  impressions_count = EXCLUDED.impressions_count,
  reel_views_count  = EXCLUDED.reel_views_count,
  updated_at        = NOW();
