-- Remove assistant/AI footprint from the primary application database.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'social_post_report'
      AND column_name = 'source'
  ) THEN
    UPDATE social_post_report
    SET source = 'system'
    WHERE source = 'ai';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'social_post_report'
      AND column_name = 'source'
  ) THEN
    ALTER TABLE social_post_report
      ALTER COLUMN source DROP DEFAULT;

    ALTER TABLE social_post_report
      ALTER COLUMN source SET DEFAULT 'user';
  END IF;
END $$;

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT tc.constraint_name
    INTO constraint_name
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema = tc.table_schema
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'social_post_report'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = 'ai_post_moderation_finding'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE social_post_report DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE IF EXISTS social_post_report
  DROP COLUMN IF EXISTS ai_finding_id,
  DROP COLUMN IF EXISTS source_model,
  DROP COLUMN IF EXISTS source_confidence;

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname
    INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'social_post_report'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%source%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE social_post_report DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'social_post_report'
      AND column_name = 'source'
  ) THEN
    ALTER TABLE social_post_report
      ADD CONSTRAINT social_post_report_source_check
      CHECK (source IN ('user', 'system'));
  END IF;
END $$;

ALTER TABLE IF EXISTS app_user
  DROP COLUMN IF EXISTS ai_chat_review_consent,
  DROP COLUMN IF EXISTS ai_terms_version;

DROP TRIGGER IF EXISTS trg_ai_chat_session_updated ON ai_chat_session;
DROP TRIGGER IF EXISTS trg_ai_customer_profile_updated ON ai_customer_profile;
DROP TRIGGER IF EXISTS trg_ai_order_draft_updated ON ai_order_draft;
DROP TRIGGER IF EXISTS trg_ai_training_memory_updated ON ai_training_memory;
DROP TRIGGER IF EXISTS trg_ai_user_learning_profile_updated ON ai_user_learning_profile;

DROP FUNCTION IF EXISTS set_ai_chat_session_updated_at();
DROP FUNCTION IF EXISTS set_ai_customer_profile_updated_at();
DROP FUNCTION IF EXISTS set_ai_order_draft_updated_at();
DROP FUNCTION IF EXISTS set_ai_training_memory_updated_at();
DROP FUNCTION IF EXISTS set_ai_user_learning_profile_updated_at();

DROP TABLE IF EXISTS ai_order_draft CASCADE;
DROP TABLE IF EXISTS ai_customer_profile CASCADE;
DROP TABLE IF EXISTS ai_chat_message CASCADE;
DROP TABLE IF EXISTS ai_chat_session CASCADE;
DROP TABLE IF EXISTS ai_training_memory CASCADE;
DROP TABLE IF EXISTS ai_chat_observation CASCADE;
DROP TABLE IF EXISTS ai_recommendation_snapshot CASCADE;
DROP TABLE IF EXISTS ai_post_moderation_finding CASCADE;
DROP TABLE IF EXISTS ai_system_finding CASCADE;
DROP TABLE IF EXISTS ai_user_learning_profile CASCADE;
DROP TABLE IF EXISTS ai_learning_fact CASCADE;
DROP TABLE IF EXISTS ai_learning_cycle_run CASCADE;

DROP TYPE IF EXISTS ai_chat_role;
DROP TYPE IF EXISTS ai_draft_status;
