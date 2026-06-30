
-- 1. Module identifier
DO $$ BEGIN
  CREATE TYPE public.boss_module AS ENUM (
    'legal','hr','finance','lead','franchise','reseller','influencer',
    'marketing','seo','pro','server','demo','ams','security','system'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.boss_severity AS ENUM ('info','success','warning','critical');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.boss_approval_status AS ENUM ('pending','approved','rejected','cancelled','expired');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.boss_task_status AS ENUM ('open','in_progress','blocked','done','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Helper: is the current user a boss-level role
CREATE OR REPLACE FUNCTION public.is_boss_level(_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _uid
      AND role::text IN ('boss_owner','super_admin','admin','ceo')
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_role_text()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role::text FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
$$;

-- 2. boss_notifications
CREATE TABLE IF NOT EXISTS public.boss_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module public.boss_module NOT NULL,
  severity public.boss_severity NOT NULL DEFAULT 'info',
  title text NOT NULL,
  body text,
  link text,
  audience_user_id uuid,
  audience_role text,
  created_by uuid,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boss_notifications_module_idx ON public.boss_notifications(module, created_at DESC);
CREATE INDEX IF NOT EXISTS boss_notifications_user_idx ON public.boss_notifications(audience_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS boss_notifications_role_idx ON public.boss_notifications(audience_role, created_at DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boss_notifications TO authenticated;
GRANT ALL ON public.boss_notifications TO service_role;
ALTER TABLE public.boss_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boss reads all notifications" ON public.boss_notifications
  FOR SELECT TO authenticated USING (public.is_boss_level(auth.uid()));
CREATE POLICY "users read targeted notifications" ON public.boss_notifications
  FOR SELECT TO authenticated USING (
    audience_user_id = auth.uid()
    OR (audience_role IS NOT NULL AND audience_role = public.current_user_role_text())
  );
CREATE POLICY "users mark own notifications read" ON public.boss_notifications
  FOR UPDATE TO authenticated USING (audience_user_id = auth.uid()) WITH CHECK (audience_user_id = auth.uid());
CREATE POLICY "boss manages notifications" ON public.boss_notifications
  FOR ALL TO authenticated USING (public.is_boss_level(auth.uid())) WITH CHECK (public.is_boss_level(auth.uid()));

-- 3. boss_approvals
CREATE TABLE IF NOT EXISTS public.boss_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module public.boss_module NOT NULL,
  action_key text NOT NULL,
  title text NOT NULL,
  description text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  requested_by uuid,
  requested_by_role text,
  status public.boss_approval_status NOT NULL DEFAULT 'pending',
  decided_by uuid,
  decided_at timestamptz,
  decision_reason text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boss_approvals_module_status_idx ON public.boss_approvals(module, status, created_at DESC);
CREATE INDEX IF NOT EXISTS boss_approvals_requested_by_idx ON public.boss_approvals(requested_by);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boss_approvals TO authenticated;
GRANT ALL ON public.boss_approvals TO service_role;
ALTER TABLE public.boss_approvals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boss reads approvals" ON public.boss_approvals
  FOR SELECT TO authenticated USING (public.is_boss_level(auth.uid()));
CREATE POLICY "requester reads own approvals" ON public.boss_approvals
  FOR SELECT TO authenticated USING (requested_by = auth.uid());
CREATE POLICY "authenticated request approval" ON public.boss_approvals
  FOR INSERT TO authenticated WITH CHECK (requested_by = auth.uid());
CREATE POLICY "boss decides approvals" ON public.boss_approvals
  FOR UPDATE TO authenticated USING (public.is_boss_level(auth.uid())) WITH CHECK (public.is_boss_level(auth.uid()));
CREATE POLICY "boss deletes approvals" ON public.boss_approvals
  FOR DELETE TO authenticated USING (public.is_boss_level(auth.uid()));

-- 4. boss_tasks
CREATE TABLE IF NOT EXISTS public.boss_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module public.boss_module NOT NULL,
  title text NOT NULL,
  description text,
  assignee_user_id uuid,
  assignee_role text,
  priority int NOT NULL DEFAULT 3,
  status public.boss_task_status NOT NULL DEFAULT 'open',
  due_at timestamptz,
  created_by uuid,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boss_tasks_module_status_idx ON public.boss_tasks(module, status, due_at);
CREATE INDEX IF NOT EXISTS boss_tasks_assignee_user_idx ON public.boss_tasks(assignee_user_id, status);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boss_tasks TO authenticated;
GRANT ALL ON public.boss_tasks TO service_role;
ALTER TABLE public.boss_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boss manages tasks" ON public.boss_tasks
  FOR ALL TO authenticated USING (public.is_boss_level(auth.uid())) WITH CHECK (public.is_boss_level(auth.uid()));
CREATE POLICY "assignee reads tasks" ON public.boss_tasks
  FOR SELECT TO authenticated USING (
    assignee_user_id = auth.uid()
    OR (assignee_role IS NOT NULL AND assignee_role = public.current_user_role_text())
  );
CREATE POLICY "assignee updates own task status" ON public.boss_tasks
  FOR UPDATE TO authenticated USING (assignee_user_id = auth.uid()) WITH CHECK (assignee_user_id = auth.uid());

-- 5. boss_announcements
CREATE TABLE IF NOT EXISTS public.boss_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module public.boss_module NOT NULL,
  title text NOT NULL,
  body text,
  audience_role text,
  severity public.boss_severity NOT NULL DEFAULT 'info',
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boss_announcements_active_idx ON public.boss_announcements(starts_at DESC, ends_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boss_announcements TO authenticated;
GRANT ALL ON public.boss_announcements TO service_role;
ALTER TABLE public.boss_announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boss manages announcements" ON public.boss_announcements
  FOR ALL TO authenticated USING (public.is_boss_level(auth.uid())) WITH CHECK (public.is_boss_level(auth.uid()));
CREATE POLICY "users read active announcements" ON public.boss_announcements
  FOR SELECT TO authenticated USING (
    starts_at <= now()
    AND (ends_at IS NULL OR ends_at >= now())
    AND (audience_role IS NULL OR audience_role = public.current_user_role_text())
  );

-- 6. boss_live_status
CREATE TABLE IF NOT EXISTS public.boss_live_status (
  module public.boss_module NOT NULL,
  key text NOT NULL,
  status text NOT NULL,
  value_num numeric,
  value_text text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (module, key)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boss_live_status TO authenticated;
GRANT ALL ON public.boss_live_status TO service_role;
ALTER TABLE public.boss_live_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone authenticated reads live status" ON public.boss_live_status
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "boss writes live status" ON public.boss_live_status
  FOR ALL TO authenticated USING (public.is_boss_level(auth.uid())) WITH CHECK (public.is_boss_level(auth.uid()));

-- 7. updated_at trigger
CREATE OR REPLACE FUNCTION public.boss_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS boss_approvals_touch ON public.boss_approvals;
CREATE TRIGGER boss_approvals_touch BEFORE UPDATE ON public.boss_approvals
  FOR EACH ROW EXECUTE FUNCTION public.boss_touch_updated_at();

DROP TRIGGER IF EXISTS boss_tasks_touch ON public.boss_tasks;
CREATE TRIGGER boss_tasks_touch BEFORE UPDATE ON public.boss_tasks
  FOR EACH ROW EXECUTE FUNCTION public.boss_touch_updated_at();

-- 8. Dispatcher functions
CREATE OR REPLACE FUNCTION public.boss_notify(
  _module public.boss_module,
  _title text,
  _body text DEFAULT NULL,
  _severity public.boss_severity DEFAULT 'info',
  _audience_user_id uuid DEFAULT NULL,
  _audience_role text DEFAULT NULL,
  _link text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  INSERT INTO public.boss_notifications(module,severity,title,body,link,audience_user_id,audience_role,created_by)
  VALUES (_module,_severity,_title,_body,_link,_audience_user_id,_audience_role,auth.uid())
  RETURNING id INTO _id;
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.boss_request_approval(
  _module public.boss_module,
  _action_key text,
  _title text,
  _description text DEFAULT NULL,
  _payload jsonb DEFAULT '{}'::jsonb,
  _expires_at timestamptz DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  INSERT INTO public.boss_approvals(module,action_key,title,description,payload,requested_by,requested_by_role,expires_at)
  VALUES (_module,_action_key,_title,_description,COALESCE(_payload,'{}'::jsonb),auth.uid(),public.current_user_role_text(),_expires_at)
  RETURNING id INTO _id;
  PERFORM public.boss_notify(_module,'Approval requested: '||_title,_description,'warning',NULL,'boss_owner','/boss?section=pending');
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.boss_decide_approval(
  _id uuid, _approved boolean, _reason text DEFAULT NULL
) RETURNS public.boss_approvals LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _row public.boss_approvals;
BEGIN
  IF NOT public.is_boss_level(auth.uid()) THEN
    RAISE EXCEPTION 'only boss-level can decide approvals';
  END IF;
  UPDATE public.boss_approvals
    SET status = CASE WHEN _approved THEN 'approved'::public.boss_approval_status ELSE 'rejected'::public.boss_approval_status END,
        decided_by = auth.uid(),
        decided_at = now(),
        decision_reason = _reason
    WHERE id = _id AND status = 'pending'
    RETURNING * INTO _row;
  IF _row.id IS NULL THEN RAISE EXCEPTION 'approval not pending or not found'; END IF;
  PERFORM public.boss_notify(
    _row.module,
    CASE WHEN _approved THEN 'Approved: '||_row.title ELSE 'Rejected: '||_row.title END,
    _reason,
    CASE WHEN _approved THEN 'success'::public.boss_severity ELSE 'warning'::public.boss_severity END,
    _row.requested_by, NULL, NULL
  );
  RETURN _row;
END $$;

CREATE OR REPLACE FUNCTION public.boss_create_task(
  _module public.boss_module,
  _title text,
  _description text DEFAULT NULL,
  _assignee_user_id uuid DEFAULT NULL,
  _assignee_role text DEFAULT NULL,
  _priority int DEFAULT 3,
  _due_at timestamptz DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  INSERT INTO public.boss_tasks(module,title,description,assignee_user_id,assignee_role,priority,due_at,created_by)
  VALUES (_module,_title,_description,_assignee_user_id,_assignee_role,_priority,_due_at,auth.uid())
  RETURNING id INTO _id;
  IF _assignee_user_id IS NOT NULL OR _assignee_role IS NOT NULL THEN
    PERFORM public.boss_notify(_module,'New task: '||_title,_description,'info',_assignee_user_id,_assignee_role,NULL);
  END IF;
  RETURN _id;
END $$;

CREATE OR REPLACE FUNCTION public.boss_update_live_status(
  _module public.boss_module,
  _key text,
  _status text,
  _value_num numeric DEFAULT NULL,
  _value_text text DEFAULT NULL,
  _meta jsonb DEFAULT '{}'::jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.boss_live_status(module,key,status,value_num,value_text,meta,updated_at)
  VALUES (_module,_key,_status,_value_num,_value_text,COALESCE(_meta,'{}'::jsonb),now())
  ON CONFLICT (module,key) DO UPDATE
    SET status = EXCLUDED.status,
        value_num = EXCLUDED.value_num,
        value_text = EXCLUDED.value_text,
        meta = EXCLUDED.meta,
        updated_at = now();
END $$;

CREATE OR REPLACE FUNCTION public.boss_announce(
  _module public.boss_module,
  _title text,
  _body text DEFAULT NULL,
  _audience_role text DEFAULT NULL,
  _severity public.boss_severity DEFAULT 'info',
  _ends_at timestamptz DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _id uuid;
BEGIN
  IF NOT public.is_boss_level(auth.uid()) THEN
    RAISE EXCEPTION 'only boss-level can announce';
  END IF;
  INSERT INTO public.boss_announcements(module,title,body,audience_role,severity,ends_at,created_by)
  VALUES (_module,_title,_body,_audience_role,_severity,_ends_at,auth.uid())
  RETURNING id INTO _id;
  RETURN _id;
END $$;

-- 9. Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.boss_notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.boss_approvals;
ALTER PUBLICATION supabase_realtime ADD TABLE public.boss_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.boss_announcements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.boss_live_status;
