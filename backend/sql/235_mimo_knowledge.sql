-- 235_mimo_knowledge.sql
-- What Mimo learned from people ("علمني").
--  verified  : checked online and correct (stored in Mimo's own dialect)
--  community : local/personal knowledge that isn't online (e.g. a bakery's
--              hours); trusted more as more different people confirm it
--  rejected  : turned out wrong — never used again
-- search_text holds normalized Arabic/English words for matching.

BEGIN;

CREATE TABLE IF NOT EXISTS mimo_knowledge (
  id             BIGSERIAL PRIMARY KEY,
  question       TEXT NOT NULL,
  question_key   TEXT NOT NULL,
  answer         TEXT NOT NULL,
  topic          VARCHAR(60),
  status         VARCHAR(16) NOT NULL
    CHECK (status IN ('verified', 'community', 'rejected')),
  confirmations  INT NOT NULL DEFAULT 1,
  disputes       INT NOT NULL DEFAULT 0,
  teachers       BIGINT[] NOT NULL DEFAULT '{}',
  evidence       JSONB NOT NULL DEFAULT '[]'::jsonb,
  search_text    TEXT NOT NULL DEFAULT '',
  uses           INT NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mimo_knowledge_question_key
  ON mimo_knowledge (question_key);

CREATE INDEX IF NOT EXISTS idx_mimo_knowledge_status_updated
  ON mimo_knowledge (status, updated_at DESC);

COMMIT;
