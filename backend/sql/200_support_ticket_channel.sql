-- 200_support_ticket_channel.sql
-- P0-1 (كول سنتر): تسجيل قناة التذكرة + من أنشأها (موظف نيابةً عن العميل) +
-- نتيجة المكالمة. يسمح للموظف بفتح تذكرة للمتصل هاتفياً وتوثيقها. Forward-only.

BEGIN;

ALTER TABLE support_ticket
  ADD COLUMN IF NOT EXISTS channel VARCHAR(16) NOT NULL DEFAULT 'app',
  ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS call_outcome VARCHAR(24);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_support_ticket_channel'
  ) THEN
    ALTER TABLE support_ticket
      ADD CONSTRAINT chk_support_ticket_channel CHECK (channel IN (
        'app','phone','whatsapp','email','social','other'
      ));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_support_ticket_call_outcome'
  ) THEN
    ALTER TABLE support_ticket
      ADD CONSTRAINT chk_support_ticket_call_outcome CHECK (call_outcome IS NULL OR call_outcome IN (
        'resolved_on_call','needs_follow_up','callback_requested','transferred','info_only'
      ));
  END IF;
END $$;

-- تسريع لوحة المشرف: التذاكر الواردة عبر الهاتف/الموظف.
CREATE INDEX IF NOT EXISTS idx_support_ticket_channel
  ON support_ticket (channel, created_at DESC);

COMMIT;
