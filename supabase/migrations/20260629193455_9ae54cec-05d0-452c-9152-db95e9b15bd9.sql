
-- Health Engine schema
CREATE TABLE public.system_health_modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_key text UNIQUE NOT NULL,
  module_name text NOT NULL,
  category text NOT NULL,
  status text NOT NULL DEFAULT 'unknown' CHECK (status IN ('healthy','degraded','critical','unknown','recovering')),
  health_pct numeric NOT NULL DEFAULT 0 CHECK (health_pct >= 0 AND health_pct <= 100),
  last_checked_at timestamptz,
  last_healthy_at timestamptz,
  error_count integer NOT NULL DEFAULT 0,
  recovery_count integer NOT NULL DEFAULT 0,
  avg_repair_ms integer NOT NULL DEFAULT 0,
  warning_level integer NOT NULL DEFAULT 0,
  critical_level integer NOT NULL DEFAULT 0,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.system_health_modules TO authenticated;
GRANT ALL ON public.system_health_modules TO service_role;
ALTER TABLE public.system_health_modules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "boss reads health modules" ON public.system_health_modules FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.system_health_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_key text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('info','warning','critical','fatal')),
  title text NOT NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  detected_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  auto_resolved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_health_incidents_module ON public.system_health_incidents(module_key, detected_at DESC);
GRANT SELECT ON public.system_health_incidents TO authenticated;
GRANT ALL ON public.system_health_incidents TO service_role;
ALTER TABLE public.system_health_incidents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "boss reads incidents" ON public.system_health_incidents FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.system_health_repairs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid REFERENCES public.system_health_incidents(id) ON DELETE SET NULL,
  module_key text NOT NULL,
  action text NOT NULL,
  status text NOT NULL CHECK (status IN ('attempted','succeeded','failed','partial')),
  duration_ms integer NOT NULL DEFAULT 0,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_health_repairs_module ON public.system_health_repairs(module_key, attempted_at DESC);
GRANT SELECT ON public.system_health_repairs TO authenticated;
GRANT ALL ON public.system_health_repairs TO service_role;
ALTER TABLE public.system_health_repairs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "boss reads repairs" ON public.system_health_repairs FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'ceo'));

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_health_modules_touch ON public.system_health_modules;
CREATE TRIGGER trg_health_modules_touch BEFORE UPDATE ON public.system_health_modules
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_health_modules;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_health_incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_health_repairs;

-- Seed core modules
INSERT INTO public.system_health_modules (module_key, module_name, category) VALUES
  ('db.core','Database Core','database'),
  ('db.realtime','Realtime Publication','database'),
  ('auth.core','Authentication','auth'),
  ('storage.core','Storage Service','storage'),
  ('rls.policies','RLS Coverage','security'),
  ('queue.buzzer','Buzzer Queue','queue'),
  ('queue.approval','Approval Queue','queue'),
  ('queue.payouts','Payout Queue','queue'),
  ('table.audit_logs','Audit Logs','audit'),
  ('table.user_roles','User Roles','rbac'),
  ('table.profiles','Profiles','rbac'),
  ('sessions.active','Active Sessions','auth'),
  ('demos.health','Demo Health','marketplace'),
  ('notifications.user','User Notifications','notifications'),
  ('chat.realtime','Chat Realtime','chat')
ON CONFLICT (module_key) DO NOTHING;
