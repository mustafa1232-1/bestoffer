-- Reconcile the realtime outbox de-duplication contract in databases where
-- migration 117 was applied before dedupe_key and its partial index were added
-- to that historical file. This forward-only migration is safe to re-run.
ALTER TABLE realtime_outbox
  ADD COLUMN IF NOT EXISTS dedupe_key TEXT;

-- Preserve every queued event. If a partially upgraded database already has
-- duplicate active keys, only clear the duplicate keys; do not delete rows.
-- The processing row wins so an in-flight publish is never displaced.
WITH ranked_active_keys AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY dedupe_key
      ORDER BY
        CASE WHEN status = 'processing' THEN 0 ELSE 1 END,
        created_at ASC,
        id ASC
    ) AS duplicate_rank
  FROM realtime_outbox
  WHERE status IN ('pending', 'processing')
    AND dedupe_key IS NOT NULL
)
UPDATE realtime_outbox AS outbox
SET dedupe_key = NULL
FROM ranked_active_keys AS ranked
WHERE outbox.id = ranked.id
  AND ranked.duplicate_rank > 1;

-- The predicate deliberately matches realtime-outbox.js exactly. PostgreSQL
-- requires that match to infer this partial index for ON CONFLICT.
CREATE UNIQUE INDEX IF NOT EXISTS uq_realtime_outbox_dedupe_active
  ON realtime_outbox (dedupe_key)
  WHERE status IN ('pending', 'processing') AND dedupe_key IS NOT NULL;
