BEGIN;

CREATE OR REPLACE FUNCTION set_ai_intelligence_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS ai_user_profiles (
  user_id BIGINT PRIMARY KEY,
  display_name VARCHAR(160),
  real_name VARCHAR(160),
  nickname VARCHAR(160),
  preferred_language VARCHAR(12) NOT NULL DEFAULT 'ar',
  dialect VARCHAR(32) NOT NULL DEFAULT 'iraqi',
  gender VARCHAR(20),
  age_range VARCHAR(40),
  city VARCHAR(120),
  bio_summary TEXT,
  occupation VARCHAR(160),
  interests JSONB NOT NULL DEFAULT '[]'::jsonb,
  goals JSONB NOT NULL DEFAULT '[]'::jsonb,
  personality_notes TEXT,
  family_notes TEXT,
  pain_points JSONB NOT NULL DEFAULT '[]'::jsonb,
  preferences_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  consent_flags_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_conversations (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  session_id BIGINT,
  title VARCHAR(220),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  summary TEXT,
  topics_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  sentiment VARCHAR(24),
  important_notes_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_conversations_user_session
ON ai_conversations (user_id, session_id)
WHERE session_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ai_messages (
  id BIGSERIAL PRIMARY KEY,
  conversation_id BIGINT NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL,
  role VARCHAR(24) NOT NULL,
  message_text TEXT NOT NULL,
  message_type VARCHAR(40) NOT NULL DEFAULT 'text',
  metadata_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_conversation_id
ON ai_messages (conversation_id, id);

CREATE TABLE IF NOT EXISTS ai_user_memories (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  memory_type VARCHAR(40) NOT NULL DEFAULT 'fact',
  memory_key VARCHAR(120) NOT NULL DEFAULT 'general',
  memory_value TEXT NOT NULL,
  confidence_score NUMERIC(6,5) NOT NULL DEFAULT 0.6,
  source_conversation_id BIGINT REFERENCES ai_conversations(id) ON DELETE SET NULL,
  source_message_id BIGINT REFERENCES ai_messages(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_user_memories_user_active
ON ai_user_memories (user_id, is_active, updated_at DESC);

CREATE TABLE IF NOT EXISTS ai_user_topics (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  topic_name VARCHAR(120) NOT NULL,
  topic_category VARCHAR(64),
  interest_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  mention_count INTEGER NOT NULL DEFAULT 0,
  last_discussed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, topic_name)
);

CREATE INDEX IF NOT EXISTS idx_ai_user_topics_user_score
ON ai_user_topics (user_id, interest_score DESC, mention_count DESC);

CREATE TABLE IF NOT EXISTS ai_user_preference_history (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  preference_key VARCHAR(120) NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_by VARCHAR(24) NOT NULL DEFAULT 'system',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_admin_user_insights (
  user_id BIGINT PRIMARY KEY,
  generated_summary TEXT,
  key_patterns_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  product_feedback_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  service_recommendations_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_memory_audit_log (
  id BIGSERIAL PRIMARY KEY,
  actor_user_id BIGINT,
  actor_role VARCHAR(24),
  target_user_id BIGINT,
  action_key VARCHAR(80) NOT NULL,
  details_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_memory_audit_target
ON ai_memory_audit_log (target_user_id, id DESC);

CREATE TABLE IF NOT EXISTS ai_chat_observation (
  id BIGSERIAL PRIMARY KEY,
  session_id BIGINT,
  customer_user_id BIGINT NOT NULL,
  user_message TEXT NOT NULL,
  assistant_reply TEXT NOT NULL,
  detected_intent VARCHAR(64),
  conversation_mode VARCHAR(40),
  language VARCHAR(8),
  style_signature VARCHAR(80),
  model_name VARCHAR(120),
  latency_ms INTEGER,
  tokens_prompt INTEGER,
  tokens_completion INTEGER,
  metadata JSONB,
  normalized_user_message TEXT,
  message_hash VARCHAR(128),
  intent_confidence NUMERIC(6,5),
  extraction_confidence NUMERIC(6,5),
  quality_score NUMERIC(6,5),
  response_quality NUMERIC(6,5),
  extracted_entities JSONB NOT NULL DEFAULT '{}'::jsonb,
  extracted_slots JSONB NOT NULL DEFAULT '{}'::jsonb,
  extracted_topics JSONB NOT NULL DEFAULT '[]'::jsonb,
  derived_signals JSONB NOT NULL DEFAULT '{}'::jsonb,
  origin_channel VARCHAR(40),
  assistant_action VARCHAR(64),
  learning_version VARCHAR(24),
  learned_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_chat_observation_user_created
ON ai_chat_observation (customer_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_user_learning_profile (
  user_id BIGINT PRIMARY KEY,
  intents_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  preferences_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  topics_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  language_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  style_signature VARCHAR(80),
  summary TEXT,
  confidence NUMERIC(6,5) NOT NULL DEFAULT 0.6,
  samples_count INTEGER NOT NULL DEFAULT 0,
  last_observation_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_learning_fact (
  id BIGSERIAL PRIMARY KEY,
  customer_user_id BIGINT,
  scope VARCHAR(16) NOT NULL DEFAULT 'user',
  fact_key VARCHAR(64) NOT NULL,
  fact_value VARCHAR(700) NOT NULL,
  fact_type VARCHAR(40) NOT NULL DEFAULT 'preference',
  confidence NUMERIC(6,5) NOT NULL DEFAULT 0.6,
  occurrences INTEGER NOT NULL DEFAULT 1,
  source_observation_id BIGINT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_learning_fact_lookup
ON ai_learning_fact (customer_user_id, scope, fact_key, is_active);

CREATE TABLE IF NOT EXISTS ai_knowledge_entry (
  id BIGSERIAL PRIMARY KEY,
  source_type VARCHAR(32) NOT NULL DEFAULT 'faq',
  intent_cluster VARCHAR(80),
  language VARCHAR(8) NOT NULL DEFAULT 'ar',
  dialect VARCHAR(32),
  query_text TEXT NOT NULL,
  answer_text TEXT NOT NULL,
  tags_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  embedding_json JSONB,
  retrieval_weight DOUBLE PRECISION NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  search_tsv TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('simple', COALESCE(query_text, '') || ' ' || COALESCE(answer_text, ''))
  ) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_knowledge_entry_search
ON ai_knowledge_entry USING GIN (search_tsv);

CREATE INDEX IF NOT EXISTS idx_ai_knowledge_entry_active_language
ON ai_knowledge_entry (is_active, language, intent_cluster);

DO $$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'ai_user_profiles',
    'ai_conversations',
    'ai_user_memories',
    'ai_user_topics',
    'ai_admin_user_insights',
    'ai_user_learning_profile',
    'ai_knowledge_entry'
  ]
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON %I',
      'trg_' || table_name || '_updated_at',
      table_name
    );
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_ai_intelligence_updated_at()',
      'trg_' || table_name || '_updated_at',
      table_name
    );
  END LOOP;
END $$;

COMMIT;
