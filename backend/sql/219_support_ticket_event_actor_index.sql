CREATE INDEX IF NOT EXISTS idx_support_ticket_event_actor_user
  ON support_ticket_event (actor_user_id)
  WHERE actor_user_id IS NOT NULL;
