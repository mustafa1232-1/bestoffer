BEGIN;

INSERT INTO social_chat_thread_member
  (thread_id, user_id, member_role, added_by_user_id)
SELECT id, user_a_id, 'owner', user_a_id
FROM social_chat_thread
WHERE thread_kind IN ('private', 'business')
  AND user_a_id IS NOT NULL
  AND user_a_id > 0
ON CONFLICT (thread_id, user_id) DO NOTHING;

INSERT INTO social_chat_thread_member
  (thread_id, user_id, member_role, added_by_user_id)
SELECT id, user_b_id, 'member', user_a_id
FROM social_chat_thread
WHERE thread_kind IN ('private', 'business')
  AND user_b_id IS NOT NULL
  AND user_b_id > 0
  AND user_b_id <> user_a_id
ON CONFLICT (thread_id, user_id) DO NOTHING;

COMMIT;
