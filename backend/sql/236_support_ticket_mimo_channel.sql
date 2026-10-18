-- 236_support_ticket_mimo_channel.sql
-- Mimo (the in-app assistant) can open support tickets on the user's behalf
-- when he can't solve a problem himself; they arrive with channel = 'mimo'.

BEGIN;

ALTER TABLE support_ticket DROP CONSTRAINT IF EXISTS chk_support_ticket_channel;
ALTER TABLE support_ticket
  ADD CONSTRAINT chk_support_ticket_channel CHECK (channel IN (
    'app','phone','whatsapp','email','social','other','mimo'
  ));

COMMIT;
