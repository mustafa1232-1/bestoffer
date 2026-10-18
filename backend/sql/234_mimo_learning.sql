-- 234_mimo_learning.sql
-- Mimo learns from usage without retraining the model:
--  * mimo_learning_event: every question, search miss, unmet need and 👍/👎
--    (user_id only when the user allowed "improve the assistant").
--    'usage' rows hold per-reply model/token/latency stats for the admin
--    dashboard; 'proactive_*' track Mimo's nudges.
--  * mimo_learned_synonym: words people use that the catalog spells
--    differently (e.g. برغر → برگر). Learned automatically when a search for
--    one word failed and another word in the same answer found what was shown.
-- Per-user memories reuse ai_user_memories (memory_type = 'mimo').

BEGIN;

CREATE TABLE IF NOT EXISTS mimo_learning_event (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NULL REFERENCES app_user(id) ON DELETE SET NULL,
  kind        VARCHAR(32) NOT NULL
    CHECK (kind IN ('question', 'search_miss', 'unmet_need', 'feedback_up', 'feedback_down', 'cart_added',
                    'usage', 'proactive_shown', 'proactive_tapped')),
  text        TEXT,
  detail      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mimo_learning_event_kind_time
  ON mimo_learning_event (kind, created_at DESC);

CREATE TABLE IF NOT EXISTS mimo_learned_synonym (
  term        TEXT NOT NULL,
  alias       TEXT NOT NULL,
  hits        INT NOT NULL DEFAULT 1,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (term, alias),
  CONSTRAINT mimo_learned_synonym_distinct CHECK (term <> alias)
);

CREATE INDEX IF NOT EXISTS idx_mimo_learned_synonym_term_hits
  ON mimo_learned_synonym (term, hits DESC);

COMMIT;
