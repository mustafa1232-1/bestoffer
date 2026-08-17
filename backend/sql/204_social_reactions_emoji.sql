-- 204_social_reactions_emoji.sql
-- Allow arbitrary emoji as message reactions (was limited to like/heart/laugh/fire).
-- Drops the CHECK allowlist on both the direct-thread and scope/community reaction
-- tables and widens the reaction column so multi-codepoint emoji (ZWJ sequences,
-- skin-tone modifiers) fit. Legacy keys stay valid; the app maps them to emoji.

BEGIN;

-- Direct chat reactions (022_social_message_reactions.sql).
ALTER TABLE social_chat_message_reaction
  DROP CONSTRAINT IF EXISTS social_chat_message_reaction_kind_check;
ALTER TABLE social_chat_message_reaction
  ALTER COLUMN reaction TYPE VARCHAR(32);

-- Scope/community reactions (090a_social_scope_core.sql) — the CHECK there was
-- declared inline (unnamed), so Postgres auto-named it <table>_<column>_check.
ALTER TABLE social_scope_chat_message_reaction
  DROP CONSTRAINT IF EXISTS social_scope_chat_message_reaction_reaction_check;
ALTER TABLE social_scope_chat_message_reaction
  ALTER COLUMN reaction TYPE VARCHAR(32);

-- Defensive: drop any remaining CHECK constraint on either reaction column in
-- case an environment auto-named it differently.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname, rel.relname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE con.contype = 'c'
      AND rel.relname IN (
        'social_chat_message_reaction',
        'social_scope_chat_message_reaction'
      )
      AND pg_get_constraintdef(con.oid) ILIKE '%reaction%'
  LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', r.relname, r.conname);
  END LOOP;
END $$;

COMMIT;
