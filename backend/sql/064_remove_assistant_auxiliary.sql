-- Remove assistant/AI footprint from the auxiliary AI database if it still exists.
-- This file is safe to execute on the primary database as well.

DROP TRIGGER IF EXISTS trg_ai_training_memory_updated ON ai_training_memory;
DROP TRIGGER IF EXISTS trg_ai_user_learning_profile_updated ON ai_user_learning_profile;

DROP FUNCTION IF EXISTS set_ai_training_memory_updated_at();
DROP FUNCTION IF EXISTS set_ai_user_learning_profile_updated_at();

DROP TABLE IF EXISTS ai_learning_cycle_run CASCADE;
DROP TABLE IF EXISTS ai_learning_fact CASCADE;
DROP TABLE IF EXISTS ai_user_learning_profile CASCADE;
DROP TABLE IF EXISTS ai_system_finding CASCADE;
DROP TABLE IF EXISTS ai_post_moderation_finding CASCADE;
DROP TABLE IF EXISTS ai_recommendation_snapshot CASCADE;
DROP TABLE IF EXISTS ai_chat_observation CASCADE;
DROP TABLE IF EXISTS ai_training_memory CASCADE;
DROP TABLE IF EXISTS ai_schema_migration CASCADE;
