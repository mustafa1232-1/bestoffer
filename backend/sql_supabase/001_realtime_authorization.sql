CREATE TABLE IF NOT EXISTS public.realtime_channel_member (
  channel TEXT NOT NULL,
  user_id BIGINT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (channel, user_id)
);

CREATE TABLE IF NOT EXISTS public.realtime_channel_audit (
  id BIGSERIAL PRIMARY KEY,
  channel TEXT NOT NULL,
  event TEXT NOT NULL,
  user_id BIGINT,
  entity_type TEXT,
  entity_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.realtime_channel_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realtime_channel_audit ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(
    COALESCE(
      (current_setting('request.jwt.claims', true))::json ->> 'app_user_id',
      ''
    ),
    ''
  )::bigint;
$$;

CREATE OR REPLACE FUNCTION public.realtime_topic_user_id(topic TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(substring(topic FROM '([0-9]+)$'), '')::bigint;
$$;

GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT SELECT ON public.realtime_channel_audit TO service_role;

DROP POLICY IF EXISTS "service_role_manage_realtime_members" ON public.realtime_channel_member;
CREATE POLICY "service_role_manage_realtime_members"
ON public.realtime_channel_member
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "service_role_manage_realtime_audit" ON public.realtime_channel_audit;
CREATE POLICY "service_role_manage_realtime_audit"
ON public.realtime_channel_audit
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_can_receive_authorized_private_realtime" ON realtime.messages;
CREATE POLICY "authenticated_can_receive_authorized_private_realtime"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.messages.extension IN ('broadcast', 'presence')
  AND (
    (
      realtime.topic() LIKE 'user:%'
      AND public.realtime_topic_user_id(realtime.topic()) = public.current_app_user_id()
    )
    OR (
      realtime.topic() LIKE 'notifications:user:%'
      AND public.realtime_topic_user_id(realtime.topic()) = public.current_app_user_id()
    )
    OR (
      realtime.topic() LIKE 'social:user:%'
      AND public.realtime_topic_user_id(realtime.topic()) = public.current_app_user_id()
    )
    OR (
      realtime.topic() LIKE 'taxi:user:%'
      AND public.realtime_topic_user_id(realtime.topic()) = public.current_app_user_id()
    )
    OR EXISTS (
      SELECT 1
      FROM public.realtime_channel_member member
      WHERE member.channel = realtime.topic()
        AND member.user_id = public.current_app_user_id()
        AND (member.expires_at IS NULL OR member.expires_at > NOW())
    )
  )
);

-- Clients only consume events in this pass. All official writes stay on Railway APIs.
DROP POLICY IF EXISTS "authenticated_cannot_broadcast_private_realtime" ON realtime.messages;
CREATE POLICY "authenticated_cannot_broadcast_private_realtime"
ON realtime.messages
FOR INSERT
TO authenticated
WITH CHECK (false);
