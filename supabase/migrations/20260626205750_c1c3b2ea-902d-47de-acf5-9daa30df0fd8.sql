-- =====================================================
-- Missing schema referenced by existing UI components
-- =====================================================

-- 1. demo_categories ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.demo_categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL UNIQUE,
  slug          TEXT UNIQUE,
  description   TEXT,
  icon          TEXT,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.demo_categories TO authenticated;
GRANT ALL ON public.demo_categories TO service_role;

ALTER TABLE public.demo_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "demo_categories_select_all_auth"
  ON public.demo_categories FOR SELECT TO authenticated USING (true);
CREATE POLICY "demo_categories_manage_demo_managers"
  ON public.demo_categories FOR ALL TO authenticated
  USING (public.can_manage_demos(auth.uid()))
  WITH CHECK (public.can_manage_demos(auth.uid()));

CREATE TRIGGER trg_demo_categories_updated_at
  BEFORE UPDATE ON public.demo_categories
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_demo_categories_active_order
  ON public.demo_categories(is_active, display_order);

-- 2. demo_login_credentials ---------------------------------------
CREATE TABLE IF NOT EXISTS public.demo_login_credentials (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  demo_id     UUID NOT NULL REFERENCES public.demos(id) ON DELETE CASCADE,
  role_type   TEXT NOT NULL,
  username    TEXT NOT NULL,
  password    TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  notes       TEXT,
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (demo_id, role_type, username)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.demo_login_credentials TO authenticated;
GRANT ALL ON public.demo_login_credentials TO service_role;

ALTER TABLE public.demo_login_credentials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "demo_credentials_select_demo_managers"
  ON public.demo_login_credentials FOR SELECT TO authenticated
  USING (public.can_manage_demos(auth.uid()) OR public.has_privileged_role(auth.uid()));
CREATE POLICY "demo_credentials_manage_demo_managers"
  ON public.demo_login_credentials FOR ALL TO authenticated
  USING (public.can_manage_demos(auth.uid()))
  WITH CHECK (public.can_manage_demos(auth.uid()));

CREATE TRIGGER trg_demo_login_credentials_updated_at
  BEFORE UPDATE ON public.demo_login_credentials
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_demo_login_credentials_demo_id
  ON public.demo_login_credentials(demo_id);

-- 3. demos: missing display columns -------------------------------
ALTER TABLE public.demos
  ADD COLUMN IF NOT EXISTS health_score          INTEGER NOT NULL DEFAULT 100 CHECK (health_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS response_time_ms      INTEGER,
  ADD COLUMN IF NOT EXISTS verification_status   TEXT NOT NULL DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS is_trending           BOOLEAN NOT NULL DEFAULT false;

-- Seed a single safe baseline category so the dropdown is never silently empty.
-- (Not business data — a structural anchor row required by the foreign-key UX.)
INSERT INTO public.demo_categories (name, slug, description, display_order)
VALUES ('General', 'general', 'Default category for newly registered demos', 0)
ON CONFLICT (name) DO NOTHING;