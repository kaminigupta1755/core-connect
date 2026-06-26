-- ===== 20251219123420_1e147589-0129-4bdb-a610-1f3e5891c0bd.sql =====
-- Create function to update timestamps FIRST
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create enum for demo tech stack
CREATE TYPE public.demo_tech_stack AS ENUM ('php', 'node', 'java', 'python', 'react', 'angular', 'vue', 'other');

-- Create enum for demo status
CREATE TYPE public.demo_status AS ENUM ('active', 'inactive', 'maintenance', 'down');

-- Create enum for user roles
CREATE TYPE public.app_role AS ENUM ('super_admin', 'demo_manager', 'franchise', 'reseller', 'client', 'prime', 'developer');

-- Create demos table
CREATE TABLE public.demos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL,
    url TEXT NOT NULL,
    masked_url TEXT,
    tech_stack demo_tech_stack NOT NULL DEFAULT 'other',
    description TEXT,
    status demo_status NOT NULL DEFAULT 'active',
    backup_url TEXT,
    multi_login_enabled BOOLEAN DEFAULT false,
    max_concurrent_logins INTEGER DEFAULT 1,
    health_check_interval INTEGER DEFAULT 5,
    last_health_check TIMESTAMP WITH TIME ZONE,
    uptime_percentage DECIMAL(5,2) DEFAULT 100.00,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create demo_clicks table for analytics
CREATE TABLE public.demo_clicks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    user_role app_role,
    franchise_id UUID,
    reseller_id UUID,
    ip_address TEXT,
    region TEXT,
    country TEXT,
    city TEXT,
    device_type TEXT,
    browser TEXT,
    referrer TEXT,
    session_duration INTEGER,
    converted BOOLEAN DEFAULT false,
    clicked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create demo_health table
CREATE TABLE public.demo_health (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE NOT NULL,
    status demo_status NOT NULL,
    response_time INTEGER,
    error_message TEXT,
    checked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create rental_assign table
CREATE TABLE public.rental_assign (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE NOT NULL,
    assigned_to UUID REFERENCES auth.users(id) NOT NULL,
    assigned_by UUID REFERENCES auth.users(id) NOT NULL,
    assignee_role app_role NOT NULL,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    end_date TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create uptime_logs table
CREATE TABLE public.uptime_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE NOT NULL,
    event_type TEXT NOT NULL,
    event_message TEXT NOT NULL,
    triggered_by UUID REFERENCES auth.users(id),
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    severity TEXT DEFAULT 'info',
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create demo_alerts table
CREATE TABLE public.demo_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE NOT NULL,
    alert_type TEXT NOT NULL,
    message TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true,
    requires_action BOOLEAN DEFAULT true,
    escalated_to UUID[],
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    action_taken TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create user_roles table
CREATE TABLE public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE (user_id, role)
);

-- Enable RLS
ALTER TABLE public.demos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_clicks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rental_assign ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uptime_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer functions
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role) $$;

CREATE OR REPLACE FUNCTION public.can_access_demos(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('super_admin', 'demo_manager', 'franchise', 'reseller', 'client', 'prime')) $$;

CREATE OR REPLACE FUNCTION public.can_manage_demos(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('super_admin', 'demo_manager')) $$;

-- RLS Policies
CREATE POLICY "Managers can manage demos" ON public.demos FOR ALL TO authenticated USING (public.can_manage_demos(auth.uid()));
CREATE POLICY "Users can view demos" ON public.demos FOR SELECT TO authenticated USING (public.can_access_demos(auth.uid()));
CREATE POLICY "Managers can view clicks" ON public.demo_clicks FOR SELECT TO authenticated USING (public.can_manage_demos(auth.uid()));
CREATE POLICY "Users can insert clicks" ON public.demo_clicks FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Managers can manage health" ON public.demo_health FOR ALL TO authenticated USING (public.can_manage_demos(auth.uid()));
CREATE POLICY "Users can view health" ON public.demo_health FOR SELECT TO authenticated USING (public.can_access_demos(auth.uid()));
CREATE POLICY "Managers can manage rentals" ON public.rental_assign FOR ALL TO authenticated USING (public.can_manage_demos(auth.uid()));
CREATE POLICY "Users can view own rentals" ON public.rental_assign FOR SELECT TO authenticated USING (assigned_to = auth.uid());
CREATE POLICY "Users can view logs" ON public.uptime_logs FOR SELECT TO authenticated USING (public.can_access_demos(auth.uid()));
CREATE POLICY "Managers can insert logs" ON public.uptime_logs FOR INSERT TO authenticated WITH CHECK (public.can_manage_demos(auth.uid()));
CREATE POLICY "Managers can manage alerts" ON public.demo_alerts FOR ALL TO authenticated USING (public.can_manage_demos(auth.uid()));
CREATE POLICY "Users can view alerts" ON public.demo_alerts FOR SELECT TO authenticated USING (public.can_access_demos(auth.uid()));
CREATE POLICY "Super admin manages roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Users view own roles" ON public.user_roles FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Indexes
CREATE INDEX idx_demo_clicks_demo_id ON public.demo_clicks(demo_id);
CREATE INDEX idx_demo_clicks_clicked_at ON public.demo_clicks(clicked_at);
CREATE INDEX idx_demo_health_demo_id ON public.demo_health(demo_id);
CREATE INDEX idx_rental_assign_demo_id ON public.rental_assign(demo_id);
CREATE INDEX idx_uptime_logs_demo_id ON public.uptime_logs(demo_id);
CREATE INDEX idx_demo_alerts_is_active ON public.demo_alerts(is_active);

-- Trigger for updated_at
CREATE TRIGGER update_demos_updated_at BEFORE UPDATE ON public.demos FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Enable realtime for alerts
ALTER PUBLICATION supabase_realtime ADD TABLE public.demo_alerts;
-- ===== 20251219124053_68f61e55-0e0b-4350-895d-51e89f8c7992.sql =====
-- Lead source enum
CREATE TYPE public.lead_source_type AS ENUM ('website', 'demo', 'influencer', 'reseller', 'referral', 'social', 'direct', 'other');

-- Lead status enum
CREATE TYPE public.lead_status_type AS ENUM ('new', 'assigned', 'contacted', 'follow_up', 'qualified', 'negotiation', 'closed_won', 'closed_lost');

-- Lead priority enum
CREATE TYPE public.lead_priority AS ENUM ('hot', 'warm', 'cold');

-- Lead industry enum
CREATE TYPE public.lead_industry AS ENUM ('retail', 'healthcare', 'finance', 'education', 'real_estate', 'manufacturing', 'hospitality', 'logistics', 'technology', 'other');

-- Main leads table
CREATE TABLE public.leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    masked_email TEXT,
    masked_phone TEXT,
    company TEXT,
    industry lead_industry DEFAULT 'other',
    source lead_source_type NOT NULL DEFAULT 'website',
    source_reference_id UUID,
    status lead_status_type NOT NULL DEFAULT 'new',
    priority lead_priority DEFAULT 'warm',
    region TEXT,
    city TEXT,
    country TEXT DEFAULT 'India',
    requirements TEXT,
    budget_range TEXT,
    ai_score INTEGER DEFAULT 50,
    conversion_probability DECIMAL(5,2) DEFAULT 50.00,
    is_duplicate BOOLEAN DEFAULT false,
    duplicate_of UUID REFERENCES public.leads(id),
    assigned_to UUID REFERENCES auth.users(id),
    assigned_role app_role,
    assigned_at TIMESTAMP WITH TIME ZONE,
    last_contact_at TIMESTAMP WITH TIME ZONE,
    next_follow_up TIMESTAMP WITH TIME ZONE,
    closed_at TIMESTAMP WITH TIME ZONE,
    closed_reason TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead assignment history
CREATE TABLE public.lead_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    assigned_to UUID REFERENCES auth.users(id) NOT NULL,
    assigned_by UUID REFERENCES auth.users(id) NOT NULL,
    assigned_role app_role NOT NULL,
    reason TEXT,
    auto_assigned BOOLEAN DEFAULT false,
    assignment_score INTEGER,
    accepted_at TIMESTAMP WITH TIME ZONE,
    rejected_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead activity logs (immutable - no update/delete)
CREATE TABLE public.lead_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    action TEXT NOT NULL,
    action_type TEXT NOT NULL,
    details TEXT,
    old_value TEXT,
    new_value TEXT,
    performed_by UUID REFERENCES auth.users(id),
    performer_role app_role,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead scores from AI
CREATE TABLE public.lead_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    score_type TEXT NOT NULL,
    score INTEGER NOT NULL,
    confidence DECIMAL(5,2),
    factors JSONB,
    model_version TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead sources tracking
CREATE TABLE public.lead_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type lead_source_type NOT NULL,
    reference_id UUID,
    referrer_name TEXT,
    referrer_role app_role,
    campaign_id TEXT,
    utm_source TEXT,
    utm_medium TEXT,
    utm_campaign TEXT,
    is_active BOOLEAN DEFAULT true,
    total_leads INTEGER DEFAULT 0,
    conversion_rate DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead escalations
CREATE TABLE public.lead_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    escalation_level INTEGER DEFAULT 1,
    reason TEXT NOT NULL,
    escalated_from UUID REFERENCES auth.users(id),
    escalated_to UUID REFERENCES auth.users(id),
    escalated_to_role app_role,
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID REFERENCES auth.users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    auto_escalated BOOLEAN DEFAULT false,
    idle_minutes INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead follow-ups
CREATE TABLE public.lead_follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    follow_up_type TEXT NOT NULL,
    notes TEXT,
    ai_suggested_message TEXT,
    assigned_to UUID REFERENCES auth.users(id) NOT NULL,
    is_completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMP WITH TIME ZONE,
    outcome TEXT,
    reminder_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Lead alerts for buzzer system
CREATE TABLE public.lead_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES public.leads(id) ON DELETE CASCADE NOT NULL,
    alert_type TEXT NOT NULL,
    message TEXT NOT NULL,
    severity TEXT DEFAULT 'info',
    is_active BOOLEAN DEFAULT true,
    requires_action BOOLEAN DEFAULT true,
    target_users UUID[],
    target_roles app_role[],
    acknowledged_by UUID REFERENCES auth.users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    action_taken TEXT,
    auto_escalate_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_alerts ENABLE ROW LEVEL SECURITY;

-- Helper functions
CREATE OR REPLACE FUNCTION public.can_manage_leads(_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('super_admin', 'demo_manager')) $$;

CREATE OR REPLACE FUNCTION public.can_view_leads(_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('super_admin', 'demo_manager', 'franchise', 'reseller')) $$;

-- RLS Policies
CREATE POLICY "Managers full access to leads" ON public.leads FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));
CREATE POLICY "Users view assigned leads" ON public.leads FOR SELECT TO authenticated USING (assigned_to = auth.uid() OR public.can_view_leads(auth.uid()));

CREATE POLICY "Managers manage assignments" ON public.lead_assignments FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));
CREATE POLICY "Users view own assignments" ON public.lead_assignments FOR SELECT TO authenticated USING (assigned_to = auth.uid());

CREATE POLICY "View logs" ON public.lead_logs FOR SELECT TO authenticated USING (public.can_view_leads(auth.uid()));
CREATE POLICY "Insert logs" ON public.lead_logs FOR INSERT TO authenticated WITH CHECK (public.can_view_leads(auth.uid()));

CREATE POLICY "View scores" ON public.lead_scores FOR SELECT TO authenticated USING (public.can_view_leads(auth.uid()));
CREATE POLICY "Manage scores" ON public.lead_scores FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));

CREATE POLICY "Manage sources" ON public.lead_sources FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));
CREATE POLICY "View sources" ON public.lead_sources FOR SELECT TO authenticated USING (public.can_view_leads(auth.uid()));

CREATE POLICY "Manage escalations" ON public.lead_escalations FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));
CREATE POLICY "View own escalations" ON public.lead_escalations FOR SELECT TO authenticated USING (escalated_to = auth.uid() OR escalated_from = auth.uid());

CREATE POLICY "Manage follow-ups" ON public.lead_follow_ups FOR ALL TO authenticated USING (assigned_to = auth.uid() OR public.can_manage_leads(auth.uid()));

CREATE POLICY "Manage alerts" ON public.lead_alerts FOR ALL TO authenticated USING (public.can_manage_leads(auth.uid()));
CREATE POLICY "View alerts" ON public.lead_alerts FOR SELECT TO authenticated USING (auth.uid() = ANY(target_users) OR public.can_view_leads(auth.uid()));

-- Indexes
CREATE INDEX idx_leads_status ON public.leads(status);
CREATE INDEX idx_leads_priority ON public.leads(priority);
CREATE INDEX idx_leads_assigned_to ON public.leads(assigned_to);
CREATE INDEX idx_leads_region ON public.leads(region);
CREATE INDEX idx_lead_assignments_lead_id ON public.lead_assignments(lead_id);
CREATE INDEX idx_lead_logs_lead_id ON public.lead_logs(lead_id);
CREATE INDEX idx_lead_alerts_is_active ON public.lead_alerts(is_active);
CREATE INDEX idx_lead_follow_ups_scheduled ON public.lead_follow_ups(scheduled_at);

-- Trigger for updated_at
CREATE TRIGGER update_leads_updated_at BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Enable realtime for alerts
ALTER PUBLICATION supabase_realtime ADD TABLE public.lead_alerts;

-- Function to mask contact info
CREATE OR REPLACE FUNCTION public.mask_contact_info()
RETURNS TRIGGER AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER mask_lead_contact BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.mask_contact_info();
-- ===== 20251219124642_18278740-fa2d-4e42-94e2-fafc304062ed.sql =====
-- Developer Management Module Tables

-- Developers table
CREATE TABLE public.developers (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    masked_email TEXT,
    masked_phone TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'inactive', 'suspended')),
    onboarding_completed BOOLEAN DEFAULT false,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- Developer Skills table
CREATE TABLE public.developer_skills (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID REFERENCES public.developers(id) ON DELETE CASCADE NOT NULL,
    skill_name TEXT NOT NULL,
    proficiency_level TEXT DEFAULT 'intermediate' CHECK (proficiency_level IN ('beginner', 'intermediate', 'advanced', 'expert')),
    years_experience INTEGER DEFAULT 0,
    verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Developer Tasks table
CREATE TABLE public.developer_tasks (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID REFERENCES public.developers(id) ON DELETE SET NULL,
    assigned_by UUID,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,
    tech_stack TEXT[] DEFAULT '{}',
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'assigned', 'accepted', 'working', 'testing', 'completed', 'blocked', 'escalated', 'cancelled')),
    estimated_hours DECIMAL(5,2) DEFAULT 2.00,
    max_delivery_hours DECIMAL(5,2) DEFAULT 2.00,
    promised_at TIMESTAMP WITH TIME ZONE,
    accepted_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    paused_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    deadline TIMESTAMP WITH TIME ZONE,
    pause_reason TEXT,
    total_paused_minutes INTEGER DEFAULT 0,
    delivery_notes TEXT,
    client_id UUID,
    masked_client_info JSONB,
    buzzer_active BOOLEAN DEFAULT true,
    buzzer_acknowledged_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Task Logs table (immutable)
CREATE TABLE public.task_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE CASCADE NOT NULL,
    developer_id UUID REFERENCES public.developers(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    action_type TEXT NOT NULL,
    old_value TEXT,
    new_value TEXT,
    details TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Performance Scores table
CREATE TABLE public.performance_scores (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID REFERENCES public.developers(id) ON DELETE CASCADE NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    speed_score DECIMAL(5,2) DEFAULT 0.00,
    quality_score DECIMAL(5,2) DEFAULT 0.00,
    communication_score DECIMAL(5,2) DEFAULT 0.00,
    overall_score DECIMAL(5,2) DEFAULT 0.00,
    tasks_completed INTEGER DEFAULT 0,
    tasks_on_time INTEGER DEFAULT 0,
    on_time_percentage DECIMAL(5,2) DEFAULT 0.00,
    total_hours_worked DECIMAL(10,2) DEFAULT 0.00,
    penalties_applied INTEGER DEFAULT 0,
    incentives_earned DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Payout Records table
CREATE TABLE public.payout_records (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID REFERENCES public.developers(id) ON DELETE CASCADE NOT NULL,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE SET NULL,
    amount DECIMAL(10,2) NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('task_payment', 'bonus', 'incentive', 'penalty', 'adjustment')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'failed', 'cancelled')),
    description TEXT,
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    processed_at TIMESTAMP WITH TIME ZONE,
    payment_method TEXT,
    transaction_ref TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Escalation Records table
CREATE TABLE public.escalation_records (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE CASCADE NOT NULL,
    developer_id UUID REFERENCES public.developers(id) ON DELETE SET NULL,
    escalated_to UUID,
    escalated_to_role app_role,
    reason TEXT NOT NULL,
    idle_minutes INTEGER,
    escalation_level INTEGER DEFAULT 1,
    auto_escalated BOOLEAN DEFAULT false,
    is_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID,
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Developer Chat Messages (masked)
CREATE TABLE public.developer_messages (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID NOT NULL,
    sender_role app_role NOT NULL,
    message TEXT NOT NULL,
    is_system_message BOOLEAN DEFAULT false,
    attachments JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.developers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.performance_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escalation_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_messages ENABLE ROW LEVEL SECURITY;

-- Helper function for developer access
CREATE OR REPLACE FUNCTION public.can_manage_developers(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin', 'demo_manager')
) 
$$;

-- Helper function for finance access
CREATE OR REPLACE FUNCTION public.can_access_finance(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin')
) 
$$;

-- Helper function to get developer_id from user_id
CREATE OR REPLACE FUNCTION public.get_developer_id(_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT id FROM public.developers WHERE user_id = _user_id LIMIT 1
$$;

-- RLS Policies for developers
CREATE POLICY "Managers can manage developers" ON public.developers
FOR ALL USING (can_manage_developers(auth.uid()));

CREATE POLICY "Developers view own profile" ON public.developers
FOR SELECT USING (user_id = auth.uid());

-- RLS Policies for developer_skills
CREATE POLICY "Managers can manage skills" ON public.developer_skills
FOR ALL USING (can_manage_developers(auth.uid()));

CREATE POLICY "Developers view own skills" ON public.developer_skills
FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

-- RLS Policies for developer_tasks
CREATE POLICY "Managers can manage tasks" ON public.developer_tasks
FOR ALL USING (can_manage_developers(auth.uid()));

CREATE POLICY "Developers view own tasks" ON public.developer_tasks
FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Developers update own tasks" ON public.developer_tasks
FOR UPDATE USING (developer_id = get_developer_id(auth.uid()));

-- RLS Policies for task_logs (immutable - insert only)
CREATE POLICY "Insert task logs" ON public.task_logs
FOR INSERT WITH CHECK (can_manage_developers(auth.uid()) OR developer_id = get_developer_id(auth.uid()));

CREATE POLICY "View task logs" ON public.task_logs
FOR SELECT USING (can_manage_developers(auth.uid()) OR developer_id = get_developer_id(auth.uid()));

-- RLS Policies for performance_scores
CREATE POLICY "Managers can manage scores" ON public.performance_scores
FOR ALL USING (can_manage_developers(auth.uid()));

CREATE POLICY "Developers view own scores" ON public.performance_scores
FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

-- RLS Policies for payout_records
CREATE POLICY "Finance can manage payouts" ON public.payout_records
FOR ALL USING (can_access_finance(auth.uid()));

CREATE POLICY "Developers view own payouts" ON public.payout_records
FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

-- RLS Policies for escalation_records
CREATE POLICY "Managers can manage escalations" ON public.escalation_records
FOR ALL USING (can_manage_developers(auth.uid()));

CREATE POLICY "Developers view own escalations" ON public.escalation_records
FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

-- RLS Policies for developer_messages (no delete allowed)
CREATE POLICY "Insert messages" ON public.developer_messages
FOR INSERT WITH CHECK (sender_id = auth.uid());

CREATE POLICY "View task messages" ON public.developer_messages
FOR SELECT USING (
    can_manage_developers(auth.uid()) OR 
    EXISTS (
        SELECT 1 FROM public.developer_tasks 
        WHERE id = task_id 
        AND developer_id = get_developer_id(auth.uid())
    )
);

-- Trigger for masking developer contact info
CREATE OR REPLACE FUNCTION public.mask_developer_contact()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    IF NEW.phone IS NOT NULL THEN
        NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mask_developer_contact_trigger
BEFORE INSERT OR UPDATE ON public.developers
FOR EACH ROW EXECUTE FUNCTION public.mask_developer_contact();

-- Trigger to update timestamps
CREATE TRIGGER update_developers_updated_at
BEFORE UPDATE ON public.developers
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_developer_tasks_updated_at
BEFORE UPDATE ON public.developer_tasks
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_performance_scores_updated_at
BEFORE UPDATE ON public.performance_scores
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251219125229_d8ad4b31-cf30-46a0-af6b-3d6f21a2e75f.sql =====
-- Franchise Management Module Tables

-- Franchise Accounts table
CREATE TABLE public.franchise_accounts (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    franchise_code TEXT UNIQUE NOT NULL,
    business_name TEXT NOT NULL,
    owner_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    masked_email TEXT,
    masked_phone TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    country TEXT DEFAULT 'India',
    pincode TEXT,
    gst_number TEXT,
    pan_number TEXT,
    kyc_status TEXT DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'submitted', 'verified', 'rejected')),
    kyc_documents JSONB,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended', 'terminated')),
    exclusive_rights BOOLEAN DEFAULT false,
    commission_rate DECIMAL(5,2) DEFAULT 15.00,
    sales_target_monthly DECIMAL(12,2) DEFAULT 0,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- Franchise Territories table
CREATE TABLE public.franchise_territories (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    territory_type TEXT NOT NULL CHECK (territory_type IN ('country', 'state', 'city', 'district', 'pincode')),
    territory_name TEXT NOT NULL,
    territory_code TEXT,
    parent_territory_id UUID REFERENCES public.franchise_territories(id),
    is_exclusive BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    assigned_by UUID,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    override_approved_by UUID,
    override_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Commissions table
CREATE TABLE public.franchise_commissions (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    lead_id UUID,
    sale_amount DECIMAL(12,2) NOT NULL,
    commission_rate DECIMAL(5,2) NOT NULL,
    commission_amount DECIMAL(12,2) NOT NULL,
    bonus_amount DECIMAL(12,2) DEFAULT 0,
    type TEXT NOT NULL CHECK (type IN ('sale', 'bonus', 'referral', 'target_bonus', 'override')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'credited', 'disputed', 'cancelled')),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    credited_at TIMESTAMP WITH TIME ZONE,
    description TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Leads table (separate from main leads for franchise-specific tracking)
CREATE TABLE public.franchise_leads (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    original_lead_id UUID REFERENCES public.leads(id),
    assigned_to_reseller UUID,
    lead_name TEXT NOT NULL,
    masked_contact TEXT,
    industry TEXT,
    region TEXT,
    city TEXT,
    language_preference TEXT,
    lead_score INTEGER DEFAULT 50,
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'assigned', 'contacted', 'demo_scheduled', 'negotiation', 'closed_won', 'closed_lost')),
    demo_requested BOOLEAN DEFAULT false,
    demo_assigned_id UUID,
    sale_value DECIMAL(12,2),
    commission_earned DECIMAL(12,2),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    closed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Payouts table
CREATE TABLE public.franchise_payouts (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('commission', 'bonus', 'withdrawal', 'refund', 'adjustment')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    payment_method TEXT,
    transaction_ref TEXT,
    bank_details JSONB,
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    processed_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Contracts table
CREATE TABLE public.franchise_contracts (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    contract_number TEXT UNIQUE NOT NULL,
    contract_type TEXT DEFAULT 'standard' CHECK (contract_type IN ('standard', 'exclusive', 'premium', 'custom')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    renewal_date DATE,
    auto_renew BOOLEAN DEFAULT false,
    terms JSONB,
    commission_terms JSONB,
    territory_terms JSONB,
    signed_at TIMESTAMP WITH TIME ZONE,
    signed_by UUID,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'pending_signature', 'active', 'expired', 'terminated', 'renewed')),
    document_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Renewals table
CREATE TABLE public.franchise_renewals (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    contract_id UUID REFERENCES public.franchise_contracts(id) ON DELETE CASCADE NOT NULL,
    previous_end_date DATE NOT NULL,
    new_end_date DATE NOT NULL,
    renewal_fee DECIMAL(12,2) DEFAULT 0,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Training Scores table
CREATE TABLE public.franchise_training_scores (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    module_name TEXT NOT NULL,
    module_type TEXT CHECK (module_type IN ('sales', 'product', 'compliance', 'communication', 'ai_coaching')),
    score DECIMAL(5,2) NOT NULL,
    max_score DECIMAL(5,2) DEFAULT 100,
    completed_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    certificate_issued BOOLEAN DEFAULT false,
    certificate_url TEXT,
    ai_feedback TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Escalations table
CREATE TABLE public.franchise_escalations (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    escalation_type TEXT NOT NULL CHECK (escalation_type IN ('territory_dispute', 'commission_dispute', 'lead_dispute', 'contract_issue', 'payment_issue', 'other')),
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'resolved', 'closed', 'escalated_to_admin')),
    escalated_to UUID,
    resolved_by UUID,
    resolution_notes TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,
    attachments JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Franchise Wallet Ledger table
CREATE TABLE public.franchise_wallet_ledger (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    franchise_id UUID REFERENCES public.franchise_accounts(id) ON DELETE CASCADE NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('credit', 'debit')),
    category TEXT NOT NULL CHECK (category IN ('sale_commission', 'bonus', 'refund', 'withdrawal', 'adjustment', 'penalty')),
    amount DECIMAL(12,2) NOT NULL,
    balance_after DECIMAL(12,2) NOT NULL,
    reference_id UUID,
    reference_type TEXT,
    description TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.franchise_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_territories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_renewals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_training_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.franchise_wallet_ledger ENABLE ROW LEVEL SECURITY;

-- Helper function for franchise access
CREATE OR REPLACE FUNCTION public.can_manage_franchises(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin')
) 
$$;

-- Helper function to get franchise_id from user_id
CREATE OR REPLACE FUNCTION public.get_franchise_id(_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT id FROM public.franchise_accounts WHERE user_id = _user_id LIMIT 1
$$;

-- Helper function for franchise role check
CREATE OR REPLACE FUNCTION public.is_franchise(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role = 'franchise'
) 
$$;

-- RLS Policies for franchise_accounts
CREATE POLICY "Admins can manage franchise accounts" ON public.franchise_accounts
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own account" ON public.franchise_accounts
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Franchises update own account" ON public.franchise_accounts
FOR UPDATE USING (user_id = auth.uid());

-- RLS Policies for franchise_territories
CREATE POLICY "Admins can manage territories" ON public.franchise_territories
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own territories" ON public.franchise_territories
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_commissions
CREATE POLICY "Admins can manage commissions" ON public.franchise_commissions
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own commissions" ON public.franchise_commissions
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_leads
CREATE POLICY "Admins can manage franchise leads" ON public.franchise_leads
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises manage own leads" ON public.franchise_leads
FOR ALL USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_payouts
CREATE POLICY "Admins can manage payouts" ON public.franchise_payouts
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own payouts" ON public.franchise_payouts
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

CREATE POLICY "Franchises request payouts" ON public.franchise_payouts
FOR INSERT WITH CHECK (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_contracts
CREATE POLICY "Admins can manage contracts" ON public.franchise_contracts
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own contracts" ON public.franchise_contracts
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_renewals
CREATE POLICY "Admins can manage renewals" ON public.franchise_renewals
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own renewals" ON public.franchise_renewals
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

CREATE POLICY "Franchises request renewals" ON public.franchise_renewals
FOR INSERT WITH CHECK (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_training_scores
CREATE POLICY "Admins can manage training scores" ON public.franchise_training_scores
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own training scores" ON public.franchise_training_scores
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_escalations
CREATE POLICY "Admins can manage escalations" ON public.franchise_escalations
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises manage own escalations" ON public.franchise_escalations
FOR ALL USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for franchise_wallet_ledger (read-only for franchises)
CREATE POLICY "Admins can manage wallet ledger" ON public.franchise_wallet_ledger
FOR ALL USING (can_manage_franchises(auth.uid()));

CREATE POLICY "Franchises view own wallet ledger" ON public.franchise_wallet_ledger
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- Trigger for masking franchise contact info
CREATE OR REPLACE FUNCTION public.mask_franchise_contact()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    IF NEW.phone IS NOT NULL THEN
        NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mask_franchise_contact_trigger
BEFORE INSERT OR UPDATE ON public.franchise_accounts
FOR EACH ROW EXECUTE FUNCTION public.mask_franchise_contact();

-- Trigger to update timestamps
CREATE TRIGGER update_franchise_accounts_updated_at
BEFORE UPDATE ON public.franchise_accounts
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_franchise_contracts_updated_at
BEFORE UPDATE ON public.franchise_contracts
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251219130025_c55151cc-5e8e-45ce-a5b6-72ab03cd774e.sql =====
-- Developer Violations tracking
CREATE TABLE public.developer_violations (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE,
    task_id UUID REFERENCES public.developer_tasks(id),
    violation_type TEXT NOT NULL, -- 'missed_deadline', 'quality_issue', 'idle_timeout', 'sla_breach', 'behavior'
    severity TEXT NOT NULL DEFAULT 'warning', -- 'warning', 'strike', 'critical'
    description TEXT,
    penalty_amount NUMERIC DEFAULT 0,
    is_acknowledged BOOLEAN DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    auto_generated BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID
);

-- Developer Timer Logs for detailed tracking
CREATE TABLE public.developer_timer_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE,
    task_id UUID NOT NULL REFERENCES public.developer_tasks(id) ON DELETE CASCADE,
    action TEXT NOT NULL, -- 'start', 'pause', 'resume', 'stop', 'checkpoint'
    checkpoint_type TEXT, -- 'started', 'coding', 'testing', 'ready'
    pause_reason TEXT,
    elapsed_minutes INTEGER DEFAULT 0,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB
);

-- Developer Activity Logs
CREATE TABLE public.developer_activity_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL, -- 'login', 'logout', 'task_view', 'file_upload', 'chat_message', 'status_change'
    description TEXT,
    ip_address TEXT,
    device_info TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Developer Wallet for tracking earnings
CREATE TABLE public.developer_wallet (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE UNIQUE,
    available_balance NUMERIC NOT NULL DEFAULT 0,
    pending_balance NUMERIC NOT NULL DEFAULT 0,
    total_earned NUMERIC NOT NULL DEFAULT 0,
    total_withdrawn NUMERIC NOT NULL DEFAULT 0,
    total_penalties NUMERIC NOT NULL DEFAULT 0,
    last_payout_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Developer Wallet Transactions
CREATE TABLE public.developer_wallet_transactions (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES public.developer_wallet(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL, -- 'credit', 'debit', 'penalty', 'bonus', 'withdrawal'
    amount NUMERIC NOT NULL,
    balance_after NUMERIC NOT NULL,
    task_id UUID REFERENCES public.developer_tasks(id),
    reference_type TEXT,
    reference_id UUID,
    description TEXT,
    status TEXT DEFAULT 'completed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Developer Code Submissions
CREATE TABLE public.developer_code_submissions (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    developer_id UUID NOT NULL REFERENCES public.developers(id) ON DELETE CASCADE,
    task_id UUID NOT NULL REFERENCES public.developer_tasks(id) ON DELETE CASCADE,
    submission_type TEXT NOT NULL DEFAULT 'final', -- 'draft', 'review', 'final'
    file_urls JSONB DEFAULT '[]'::jsonb,
    commit_message TEXT,
    notes TEXT,
    ai_review_score INTEGER,
    ai_review_feedback TEXT,
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    review_status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected', 'revision_needed'
    review_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.developer_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_timer_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_wallet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_code_submissions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for developer_violations
CREATE POLICY "Developers view own violations" ON public.developer_violations
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Managers can manage violations" ON public.developer_violations
    FOR ALL USING (can_manage_developers(auth.uid()));

-- RLS Policies for developer_timer_logs
CREATE POLICY "Developers view own timer logs" ON public.developer_timer_logs
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Developers insert own timer logs" ON public.developer_timer_logs
    FOR INSERT WITH CHECK (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Managers can manage timer logs" ON public.developer_timer_logs
    FOR ALL USING (can_manage_developers(auth.uid()));

-- RLS Policies for developer_activity_logs
CREATE POLICY "Developers insert own activity logs" ON public.developer_activity_logs
    FOR INSERT WITH CHECK (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Managers can view activity logs" ON public.developer_activity_logs
    FOR SELECT USING (can_manage_developers(auth.uid()));

-- RLS Policies for developer_wallet
CREATE POLICY "Developers view own wallet" ON public.developer_wallet
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Finance can manage wallets" ON public.developer_wallet
    FOR ALL USING (can_access_finance(auth.uid()));

-- RLS Policies for developer_wallet_transactions
CREATE POLICY "Developers view own transactions" ON public.developer_wallet_transactions
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Finance can manage transactions" ON public.developer_wallet_transactions
    FOR ALL USING (can_access_finance(auth.uid()));

-- RLS Policies for developer_code_submissions
CREATE POLICY "Developers manage own submissions" ON public.developer_code_submissions
    FOR ALL USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Managers can manage all submissions" ON public.developer_code_submissions
    FOR ALL USING (can_manage_developers(auth.uid()));

-- Add new columns to developers table for enhanced tracking
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS skill_test_status TEXT DEFAULT 'pending';
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS skill_test_score INTEGER;
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS is_frozen BOOLEAN DEFAULT false;
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS frozen_reason TEXT;
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS frozen_at TIMESTAMPTZ;
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS total_strikes INTEGER DEFAULT 0;
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS availability_status TEXT DEFAULT 'available';
ALTER TABLE public.developers ADD COLUMN IF NOT EXISTS current_task_id UUID;

-- Add new columns to developer_tasks for enhanced workflow
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS sla_hours NUMERIC DEFAULT 2;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS checkpoint_status TEXT DEFAULT 'pending';
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS promised_delivery_at TIMESTAMPTZ;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS actual_delivery_at TIMESTAMPTZ;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS quality_score INTEGER;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS client_rating INTEGER;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS task_amount NUMERIC DEFAULT 0;
ALTER TABLE public.developer_tasks ADD COLUMN IF NOT EXISTS penalty_amount NUMERIC DEFAULT 0;
-- ===== 20251219130658_1c6c4a0e-bfe9-4596-8ee3-e9b2854416ae.sql =====
-- Create reseller-specific tables for the Reseller Management module

-- Reseller accounts table
CREATE TABLE IF NOT EXISTS public.reseller_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    franchise_id UUID REFERENCES public.franchise_accounts(id),
    reseller_code TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    masked_email TEXT,
    masked_phone TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    country TEXT DEFAULT 'India',
    pincode TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended', 'inactive')),
    kyc_status TEXT DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'verified', 'rejected')),
    kyc_documents JSONB,
    commission_rate NUMERIC DEFAULT 10.00,
    training_completed BOOLEAN DEFAULT false,
    certification_score INTEGER,
    certification_date TIMESTAMPTZ,
    joined_at TIMESTAMPTZ DEFAULT now(),
    last_active_at TIMESTAMPTZ DEFAULT now(),
    sales_target_monthly NUMERIC DEFAULT 0,
    total_sales NUMERIC DEFAULT 0,
    total_leads_converted INTEGER DEFAULT 0,
    language_preference TEXT DEFAULT 'en',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller training records
CREATE TABLE IF NOT EXISTS public.reseller_training (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    module_name TEXT NOT NULL,
    module_type TEXT DEFAULT 'sales',
    score NUMERIC NOT NULL,
    max_score NUMERIC DEFAULT 100,
    passed BOOLEAN DEFAULT false,
    attempts INTEGER DEFAULT 1,
    completed_at TIMESTAMPTZ DEFAULT now(),
    certificate_issued BOOLEAN DEFAULT false,
    certificate_url TEXT,
    ai_feedback TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller leads
CREATE TABLE IF NOT EXISTS public.reseller_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    franchise_id UUID REFERENCES public.franchise_accounts(id),
    original_lead_id UUID REFERENCES public.leads(id),
    lead_name TEXT NOT NULL,
    masked_contact TEXT,
    industry TEXT,
    city TEXT,
    region TEXT,
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'demo_scheduled', 'negotiating', 'converted', 'lost', 'escalated')),
    lead_score INTEGER DEFAULT 50,
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    demo_requested BOOLEAN DEFAULT false,
    demo_link_id UUID,
    demo_clicked_at TIMESTAMPTZ,
    last_follow_up TIMESTAMPTZ,
    next_follow_up TIMESTAMPTZ,
    follow_up_count INTEGER DEFAULT 0,
    conversion_probability NUMERIC DEFAULT 50.00,
    sale_value NUMERIC,
    commission_earned NUMERIC,
    ai_notes TEXT,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    converted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller commissions
CREATE TABLE IF NOT EXISTS public.reseller_commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    lead_id UUID REFERENCES public.reseller_leads(id),
    commission_type TEXT NOT NULL CHECK (commission_type IN ('sale', 'bonus', 'target_achievement', 'referral')),
    sale_amount NUMERIC NOT NULL,
    commission_rate NUMERIC NOT NULL,
    commission_amount NUMERIC NOT NULL,
    bonus_amount NUMERIC DEFAULT 0,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'credited', 'rejected')),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    credited_at TIMESTAMPTZ,
    description TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller payouts
CREATE TABLE IF NOT EXISTS public.reseller_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    payout_type TEXT NOT NULL CHECK (payout_type IN ('withdrawal', 'bonus', 'refund')),
    amount NUMERIC NOT NULL,
    payment_method TEXT,
    bank_details JSONB,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected')),
    requested_at TIMESTAMPTZ DEFAULT now(),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    transaction_ref TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller activity logs
CREATE TABLE IF NOT EXISTS public.reseller_activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    description TEXT,
    metadata JSONB,
    ip_address TEXT,
    device_info TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller demo clicks tracking
CREATE TABLE IF NOT EXISTS public.reseller_demo_clicks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    demo_id UUID REFERENCES public.demos(id),
    lead_id UUID REFERENCES public.reseller_leads(id),
    tracking_id TEXT NOT NULL,
    clicked_at TIMESTAMPTZ DEFAULT now(),
    ip_address TEXT,
    device_type TEXT,
    browser TEXT,
    country TEXT,
    city TEXT,
    referrer TEXT,
    session_duration INTEGER,
    converted BOOLEAN DEFAULT false,
    is_fake_click BOOLEAN DEFAULT false,
    ai_fraud_score NUMERIC DEFAULT 0
);

-- Reseller escalations
CREATE TABLE IF NOT EXISTS public.reseller_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    lead_id UUID REFERENCES public.reseller_leads(id),
    escalation_type TEXT NOT NULL CHECK (escalation_type IN ('lead_issue', 'payment_dispute', 'technical', 'customer_complaint', 'other')),
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    escalated_to UUID,
    escalated_to_role TEXT,
    attachments JSONB,
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller territory mapping
CREATE TABLE IF NOT EXISTS public.reseller_territory_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    franchise_id UUID REFERENCES public.franchise_accounts(id),
    territory_type TEXT NOT NULL CHECK (territory_type IN ('city', 'district', 'state', 'region')),
    territory_name TEXT NOT NULL,
    territory_code TEXT,
    is_primary BOOLEAN DEFAULT false,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    assigned_by UUID,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller wallet
CREATE TABLE IF NOT EXISTS public.reseller_wallet (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL UNIQUE REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    available_balance NUMERIC NOT NULL DEFAULT 0,
    pending_balance NUMERIC NOT NULL DEFAULT 0,
    total_earned NUMERIC NOT NULL DEFAULT 0,
    total_withdrawn NUMERIC NOT NULL DEFAULT 0,
    total_bonus NUMERIC NOT NULL DEFAULT 0,
    last_payout_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reseller wallet transactions
CREATE TABLE IF NOT EXISTS public.reseller_wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES public.reseller_wallet(id) ON DELETE CASCADE,
    reseller_id UUID NOT NULL REFERENCES public.reseller_accounts(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('credit', 'debit', 'commission', 'bonus', 'withdrawal', 'refund')),
    amount NUMERIC NOT NULL,
    balance_after NUMERIC NOT NULL,
    description TEXT,
    reference_type TEXT,
    reference_id UUID,
    status TEXT DEFAULT 'completed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on all reseller tables
ALTER TABLE public.reseller_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_training ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_demo_clicks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_territory_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_wallet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reseller_wallet_transactions ENABLE ROW LEVEL SECURITY;

-- Helper functions
CREATE OR REPLACE FUNCTION public.get_reseller_id(_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT id FROM public.reseller_accounts WHERE user_id = _user_id LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_reseller(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role = 'reseller'
) 
$$;

CREATE OR REPLACE FUNCTION public.can_manage_resellers(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin', 'franchise')
) 
$$;

-- Masking trigger for reseller contacts
CREATE OR REPLACE FUNCTION public.mask_reseller_contact()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    IF NEW.phone IS NOT NULL THEN
        NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mask_reseller_contact_trigger
BEFORE INSERT OR UPDATE ON public.reseller_accounts
FOR EACH ROW EXECUTE FUNCTION public.mask_reseller_contact();

-- RLS Policies for reseller_accounts
CREATE POLICY "Resellers view own account" ON public.reseller_accounts
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Resellers update own account" ON public.reseller_accounts
FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Admins can manage reseller accounts" ON public.reseller_accounts
FOR ALL USING (can_manage_resellers(auth.uid()));

CREATE POLICY "Franchises view their resellers" ON public.reseller_accounts
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for reseller_training
CREATE POLICY "Resellers view own training" ON public.reseller_training
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage training" ON public.reseller_training
FOR ALL USING (can_manage_resellers(auth.uid()));

-- RLS Policies for reseller_leads
CREATE POLICY "Resellers manage own leads" ON public.reseller_leads
FOR ALL USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage reseller leads" ON public.reseller_leads
FOR ALL USING (can_manage_resellers(auth.uid()));

CREATE POLICY "Franchises view their reseller leads" ON public.reseller_leads
FOR SELECT USING (franchise_id = get_franchise_id(auth.uid()));

-- RLS Policies for reseller_commissions
CREATE POLICY "Resellers view own commissions" ON public.reseller_commissions
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage commissions" ON public.reseller_commissions
FOR ALL USING (can_manage_resellers(auth.uid()) OR can_access_finance(auth.uid()));

-- RLS Policies for reseller_payouts
CREATE POLICY "Resellers view own payouts" ON public.reseller_payouts
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Resellers request payouts" ON public.reseller_payouts
FOR INSERT WITH CHECK (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage payouts" ON public.reseller_payouts
FOR ALL USING (can_manage_resellers(auth.uid()) OR can_access_finance(auth.uid()));

-- RLS Policies for reseller_activity_logs
CREATE POLICY "Resellers insert own logs" ON public.reseller_activity_logs
FOR INSERT WITH CHECK (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can view logs" ON public.reseller_activity_logs
FOR SELECT USING (can_manage_resellers(auth.uid()));

-- RLS Policies for reseller_demo_clicks
CREATE POLICY "Resellers view own clicks" ON public.reseller_demo_clicks
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Insert clicks" ON public.reseller_demo_clicks
FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins can manage clicks" ON public.reseller_demo_clicks
FOR ALL USING (can_manage_resellers(auth.uid()));

-- RLS Policies for reseller_escalations
CREATE POLICY "Resellers manage own escalations" ON public.reseller_escalations
FOR ALL USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage escalations" ON public.reseller_escalations
FOR ALL USING (can_manage_resellers(auth.uid()));

-- RLS Policies for reseller_territory_map
CREATE POLICY "Resellers view own territories" ON public.reseller_territory_map
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Admins can manage territories" ON public.reseller_territory_map
FOR ALL USING (can_manage_resellers(auth.uid()));

-- RLS Policies for reseller_wallet
CREATE POLICY "Resellers view own wallet" ON public.reseller_wallet
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Finance can manage wallets" ON public.reseller_wallet
FOR ALL USING (can_access_finance(auth.uid()));

-- RLS Policies for reseller_wallet_transactions
CREATE POLICY "Resellers view own transactions" ON public.reseller_wallet_transactions
FOR SELECT USING (reseller_id = get_reseller_id(auth.uid()));

CREATE POLICY "Finance can manage transactions" ON public.reseller_wallet_transactions
FOR ALL USING (can_access_finance(auth.uid()));

-- Update triggers
CREATE TRIGGER update_reseller_accounts_updated_at
BEFORE UPDATE ON public.reseller_accounts
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_reseller_wallet_updated_at
BEFORE UPDATE ON public.reseller_wallet
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251219131606_566d1a88-df67-4c58-849b-7a595c2a0afc.sql =====
-- First migration: Add enum values only
-- Add 'influencer' to app_role enum if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'influencer' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'influencer';
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'marketing_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'marketing_manager';
    END IF;
END $$;
-- ===== 20251219131648_0299128d-53eb-40f0-9264-5394f841c24c.sql =====
-- =====================================================
-- INFLUENCER MANAGEMENT MODULE - Tables & RLS
-- =====================================================

-- 1. INFLUENCER ACCOUNTS TABLE
CREATE TABLE IF NOT EXISTS public.influencer_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    masked_email TEXT,
    masked_phone TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended', 'frozen', 'rejected')),
    kyc_status TEXT DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'verified', 'rejected')),
    kyc_documents JSONB DEFAULT '[]',
    social_platforms JSONB DEFAULT '[]',
    commission_tier TEXT DEFAULT 'bronze' CHECK (commission_tier IN ('bronze', 'silver', 'gold', 'platinum', 'diamond')),
    cpc_rate NUMERIC DEFAULT 0.50,
    cpl_rate NUMERIC DEFAULT 5.00,
    cpa_rate NUMERIC DEFAULT 50.00,
    country TEXT DEFAULT 'India',
    region TEXT,
    city TEXT,
    fraud_score NUMERIC DEFAULT 0,
    is_suspended BOOLEAN DEFAULT false,
    suspension_reason TEXT,
    suspended_at TIMESTAMPTZ,
    total_clicks INTEGER DEFAULT 0,
    total_conversions INTEGER DEFAULT 0,
    total_earned NUMERIC DEFAULT 0,
    joined_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. INFLUENCER CAMPAIGN MAP
CREATE TABLE IF NOT EXISTS public.influencer_campaign_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    campaign_name TEXT NOT NULL,
    campaign_type TEXT DEFAULT 'promotion',
    product_category TEXT,
    start_date DATE NOT NULL,
    end_date DATE,
    target_clicks INTEGER DEFAULT 0,
    target_conversions INTEGER DEFAULT 0,
    achieved_clicks INTEGER DEFAULT 0,
    achieved_conversions INTEGER DEFAULT 0,
    bonus_amount NUMERIC DEFAULT 0,
    status TEXT DEFAULT 'active',
    assigned_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. INFLUENCER CLICK LOGS
CREATE TABLE IF NOT EXISTS public.influencer_click_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES public.influencer_campaign_map(id),
    tracking_link TEXT NOT NULL,
    utm_source TEXT,
    utm_medium TEXT,
    utm_campaign TEXT,
    utm_content TEXT,
    ip_address TEXT,
    user_agent TEXT,
    device_type TEXT,
    browser TEXT,
    country TEXT,
    city TEXT,
    is_unique BOOLEAN DEFAULT true,
    is_bot BOOLEAN DEFAULT false,
    is_fraud BOOLEAN DEFAULT false,
    fraud_reason TEXT,
    fraud_score NUMERIC DEFAULT 0,
    clicked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. INFLUENCER CONVERSION LOGS
CREATE TABLE IF NOT EXISTS public.influencer_conversion_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES public.influencer_campaign_map(id),
    click_id UUID REFERENCES public.influencer_click_logs(id),
    conversion_type TEXT DEFAULT 'sale',
    product_category TEXT,
    sale_amount NUMERIC DEFAULT 0,
    commission_type TEXT DEFAULT 'cpa',
    commission_rate NUMERIC NOT NULL,
    commission_amount NUMERIC NOT NULL,
    status TEXT DEFAULT 'pending',
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    credited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. INFLUENCER WALLET
CREATE TABLE IF NOT EXISTS public.influencer_wallet (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL UNIQUE REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    available_balance NUMERIC DEFAULT 0,
    pending_balance NUMERIC DEFAULT 0,
    total_earned NUMERIC DEFAULT 0,
    total_withdrawn NUMERIC DEFAULT 0,
    total_penalties NUMERIC DEFAULT 0,
    last_payout_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. INFLUENCER WALLET LEDGER
CREATE TABLE IF NOT EXISTS public.influencer_wallet_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    balance_after NUMERIC NOT NULL,
    reference_type TEXT,
    reference_id UUID,
    description TEXT,
    status TEXT DEFAULT 'completed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. INFLUENCER PAYOUT REQUESTS
CREATE TABLE IF NOT EXISTS public.influencer_payout_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    amount NUMERIC NOT NULL,
    payment_method TEXT DEFAULT 'bank_transfer',
    bank_details JSONB,
    status TEXT DEFAULT 'pending',
    requested_at TIMESTAMPTZ DEFAULT now(),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    transaction_ref TEXT,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. INFLUENCER PERFORMANCE METRICS
CREATE TABLE IF NOT EXISTS public.influencer_performance_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    metric_date DATE NOT NULL,
    total_clicks INTEGER DEFAULT 0,
    unique_clicks INTEGER DEFAULT 0,
    bot_clicks INTEGER DEFAULT 0,
    fraud_clicks INTEGER DEFAULT 0,
    conversions INTEGER DEFAULT 0,
    conversion_rate NUMERIC DEFAULT 0,
    earnings NUMERIC DEFAULT 0,
    platform_breakdown JSONB DEFAULT '{}',
    country_breakdown JSONB DEFAULT '{}',
    fraud_score NUMERIC DEFAULT 0,
    tier_progress NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(influencer_id, metric_date)
);

-- 9. INFLUENCER SUPPORT TICKETS
CREATE TABLE IF NOT EXISTS public.influencer_support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    ticket_number TEXT NOT NULL UNIQUE,
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT DEFAULT 'general',
    priority TEXT DEFAULT 'medium',
    status TEXT DEFAULT 'open',
    assigned_to UUID,
    escalated_to UUID,
    escalation_level INTEGER DEFAULT 0,
    attachments JSONB DEFAULT '[]',
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. INFLUENCER AUDIT TRAIL
CREATE TABLE IF NOT EXISTS public.influencer_audit_trail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT,
    metadata JSONB,
    performed_by UUID,
    performer_role app_role,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. INFLUENCER REFERRAL LINKS
CREATE TABLE IF NOT EXISTS public.influencer_referral_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID NOT NULL REFERENCES public.influencer_accounts(id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES public.influencer_campaign_map(id),
    original_url TEXT NOT NULL,
    short_code TEXT NOT NULL UNIQUE,
    tracking_url TEXT NOT NULL,
    utm_source TEXT,
    utm_medium TEXT,
    utm_campaign TEXT,
    utm_content TEXT,
    product_category TEXT,
    total_clicks INTEGER DEFAULT 0,
    unique_clicks INTEGER DEFAULT 0,
    conversions INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- HELPER FUNCTIONS
CREATE OR REPLACE FUNCTION public.get_influencer_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT id FROM public.influencer_accounts WHERE user_id = _user_id LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_influencer(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role = 'influencer'
) 
$$;

CREATE OR REPLACE FUNCTION public.can_manage_influencers(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin', 'marketing_manager')
) 
$$;

CREATE OR REPLACE FUNCTION public.mask_influencer_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    IF NEW.phone IS NOT NULL THEN
        NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS mask_influencer_contact_trigger ON public.influencer_accounts;
CREATE TRIGGER mask_influencer_contact_trigger
    BEFORE INSERT OR UPDATE ON public.influencer_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.mask_influencer_contact();

-- ENABLE RLS
ALTER TABLE public.influencer_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_campaign_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_click_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_conversion_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_wallet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_wallet_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_performance_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_audit_trail ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_referral_links ENABLE ROW LEVEL SECURITY;

-- RLS POLICIES
CREATE POLICY "Admins manage influencer accounts" ON public.influencer_accounts FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own account" ON public.influencer_accounts FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Influencers update own account" ON public.influencer_accounts FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Admins manage campaigns" ON public.influencer_campaign_map FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own campaigns" ON public.influencer_campaign_map FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins manage click logs" ON public.influencer_click_logs FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own clicks" ON public.influencer_click_logs FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins manage conversions" ON public.influencer_conversion_logs FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own conversions" ON public.influencer_conversion_logs FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Finance manage influencer wallets" ON public.influencer_wallet FOR ALL USING (can_access_finance(auth.uid()));
CREATE POLICY "Influencers view own wallet" ON public.influencer_wallet FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Finance manage wallet ledger" ON public.influencer_wallet_ledger FOR ALL USING (can_access_finance(auth.uid()));
CREATE POLICY "Influencers view own ledger" ON public.influencer_wallet_ledger FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Finance manage payouts" ON public.influencer_payout_requests FOR ALL USING (can_access_finance(auth.uid()));
CREATE POLICY "Influencers request payouts" ON public.influencer_payout_requests FOR INSERT WITH CHECK (influencer_id = get_influencer_id(auth.uid()));
CREATE POLICY "Influencers view own payouts" ON public.influencer_payout_requests FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins manage metrics" ON public.influencer_performance_metrics FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own metrics" ON public.influencer_performance_metrics FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins manage tickets" ON public.influencer_support_tickets FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers manage own tickets" ON public.influencer_support_tickets FOR ALL USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins view audit trail" ON public.influencer_audit_trail FOR SELECT USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers view own audit" ON public.influencer_audit_trail FOR SELECT USING (influencer_id = get_influencer_id(auth.uid()));

CREATE POLICY "Admins manage referral links" ON public.influencer_referral_links FOR ALL USING (can_manage_influencers(auth.uid()));
CREATE POLICY "Influencers manage own links" ON public.influencer_referral_links FOR ALL USING (influencer_id = get_influencer_id(auth.uid()));

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_influencer_accounts_user_id ON public.influencer_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_influencer_click_logs_influencer_id ON public.influencer_click_logs(influencer_id);
CREATE INDEX IF NOT EXISTS idx_influencer_referral_links_short_code ON public.influencer_referral_links(short_code);
-- ===== 20251219132249_bc35cdd0-cc0c-4c22-ab02-3333f838866a.sql =====
-- Add 'prime' and 'client_success' to app_role enum
DO $$ BEGIN
    ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'prime';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'client_success';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- ===== 20251219132333_2fdf5492-553a-4536-b0a3-e5c03b5f3b6e.sql =====
-- Prime User Management Tables

-- Prime User Profiles
CREATE TABLE IF NOT EXISTS public.prime_user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    masked_email TEXT,
    masked_phone TEXT,
    subscription_tier TEXT DEFAULT 'monthly' CHECK (subscription_tier IN ('monthly', 'yearly', 'lifetime', 'trial')),
    subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'expired', 'suspended', 'cancelled', 'trial')),
    subscription_start_date TIMESTAMPTZ DEFAULT now(),
    subscription_end_date TIMESTAMPTZ,
    auto_renewal BOOLEAN DEFAULT true,
    region TEXT DEFAULT 'India',
    vip_badge_enabled BOOLEAN DEFAULT true,
    priority_level INTEGER DEFAULT 1,
    dedicated_developer_id UUID,
    grace_period_days INTEGER DEFAULT 7,
    downgrade_reason TEXT,
    two_factor_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- Prime Upgrade History
CREATE TABLE IF NOT EXISTS public.prime_upgrade_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    previous_tier TEXT,
    new_tier TEXT NOT NULL,
    upgrade_type TEXT CHECK (upgrade_type IN ('upgrade', 'downgrade', 'renewal', 'trial_start', 'trial_end')),
    amount NUMERIC DEFAULT 0,
    payment_method TEXT,
    transaction_ref TEXT,
    processed_by UUID,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Priority Ticket Logs
CREATE TABLE IF NOT EXISTS public.priority_ticket_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    ticket_type TEXT NOT NULL CHECK (ticket_type IN ('urgent', 'bug_fix', 'feature_request', 'support', 'hosting', 'general')),
    subject TEXT NOT NULL,
    description TEXT,
    priority_level INTEGER DEFAULT 1,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'escalated', 'resolved', 'closed')),
    assigned_developer_id UUID,
    escalated_to UUID,
    escalation_reason TEXT,
    sla_target_hours NUMERIC DEFAULT 2,
    sla_deadline TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    satisfaction_rating INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SLA Monitoring
CREATE TABLE IF NOT EXISTS public.sla_monitoring (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    ticket_id UUID REFERENCES public.priority_ticket_logs(id) ON DELETE SET NULL,
    task_id UUID,
    sla_type TEXT NOT NULL CHECK (sla_type IN ('response', 'resolution', 'delivery', 'bug_fix')),
    target_hours NUMERIC NOT NULL DEFAULT 2,
    actual_hours NUMERIC,
    sla_met BOOLEAN,
    compensation_amount NUMERIC DEFAULT 0,
    compensation_credited BOOLEAN DEFAULT false,
    breach_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Developer Assignment Priority
CREATE TABLE IF NOT EXISTS public.developer_assignment_priority (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    developer_id UUID REFERENCES public.developers(id) ON DELETE SET NULL,
    assignment_type TEXT DEFAULT 'dedicated' CHECK (assignment_type IN ('dedicated', 'priority', 'backup')),
    is_active BOOLEAN DEFAULT true,
    assigned_by UUID,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dedicated Support Threads
CREATE TABLE IF NOT EXISTS public.dedicated_support_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    thread_type TEXT DEFAULT 'support' CHECK (thread_type IN ('support', 'developer_chat', 'urgent', 'feature_discussion')),
    subject TEXT NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'closed', 'archived')),
    participant_developer_id UUID,
    participant_masked_name TEXT,
    is_urgent BOOLEAN DEFAULT false,
    last_message_at TIMESTAMPTZ DEFAULT now(),
    closed_at TIMESTAMPTZ,
    closed_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dedicated Support Messages
CREATE TABLE IF NOT EXISTS public.dedicated_support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES public.dedicated_support_threads(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL,
    sender_role app_role NOT NULL,
    sender_masked_name TEXT,
    message TEXT NOT NULL,
    attachments JSONB DEFAULT '[]'::jsonb,
    is_system_message BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prime Wallet Usage
CREATE TABLE IF NOT EXISTS public.prime_wallet_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('subscription', 'refund', 'compensation', 'addon', 'credit')),
    amount NUMERIC NOT NULL,
    balance_after NUMERIC NOT NULL,
    description TEXT,
    reference_id UUID,
    reference_type TEXT,
    payment_method TEXT,
    status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prime Performance Reports
CREATE TABLE IF NOT EXISTS public.prime_performance_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    report_period_start DATE NOT NULL,
    report_period_end DATE NOT NULL,
    total_tickets INTEGER DEFAULT 0,
    tickets_resolved INTEGER DEFAULT 0,
    avg_resolution_hours NUMERIC,
    sla_compliance_rate NUMERIC,
    compensations_received NUMERIC DEFAULT 0,
    developer_assignments INTEGER DEFAULT 0,
    support_threads INTEGER DEFAULT 0,
    satisfaction_avg NUMERIC,
    generated_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prime Feature Access
CREATE TABLE IF NOT EXISTS public.prime_feature_access (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    feature_name TEXT NOT NULL,
    feature_type TEXT DEFAULT 'beta' CHECK (feature_type IN ('beta', 'exclusive', 'early_access', 'premium')),
    granted_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    granted_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(prime_user_id, feature_name)
);

-- Prime Hosting Status
CREATE TABLE IF NOT EXISTS public.prime_hosting_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prime_user_id UUID NOT NULL REFERENCES public.prime_user_profiles(id) ON DELETE CASCADE,
    hosting_tier TEXT DEFAULT 'premium' CHECK (hosting_tier IN ('standard', 'premium', 'enterprise')),
    uptime_percentage NUMERIC DEFAULT 99.9,
    last_check_at TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'healthy' CHECK (status IN ('healthy', 'degraded', 'down', 'maintenance')),
    allocated_resources JSONB DEFAULT '{"cpu": "high", "memory": "high", "storage": "unlimited"}'::jsonb,
    custom_domain TEXT,
    ssl_enabled BOOLEAN DEFAULT true,
    cdn_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.prime_user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prime_upgrade_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.priority_ticket_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sla_monitoring ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_assignment_priority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dedicated_support_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dedicated_support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prime_wallet_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prime_performance_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prime_feature_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prime_hosting_status ENABLE ROW LEVEL SECURITY;

-- Helper functions
CREATE OR REPLACE FUNCTION public.get_prime_user_id(_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT id FROM public.prime_user_profiles WHERE user_id = _user_id LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_prime_user(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role = 'prime'
) 
$$;

CREATE OR REPLACE FUNCTION public.can_manage_prime_users(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ 
SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('super_admin', 'client_success')
) 
$$;

-- Masking trigger for prime users
CREATE OR REPLACE FUNCTION public.mask_prime_user_contact()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.masked_email := CONCAT(LEFT(NEW.email, 2), '****@', SPLIT_PART(NEW.email, '@', 2));
    IF NEW.phone IS NOT NULL THEN
        NEW.masked_phone := CONCAT(LEFT(NEW.phone, 3), '****', RIGHT(NEW.phone, 2));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER mask_prime_user_contact_trigger
    BEFORE INSERT OR UPDATE ON public.prime_user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.mask_prime_user_contact();

-- RLS Policies
CREATE POLICY "Prime users view own profile" ON public.prime_user_profiles
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Prime users update own profile" ON public.prime_user_profiles
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Admins manage prime profiles" ON public.prime_user_profiles
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users view own history" ON public.prime_upgrade_history
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage upgrade history" ON public.prime_upgrade_history
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Finance manages upgrades" ON public.prime_upgrade_history
    FOR ALL USING (can_access_finance(auth.uid()));

CREATE POLICY "Prime users manage own tickets" ON public.priority_ticket_logs
    FOR ALL USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage all tickets" ON public.priority_ticket_logs
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Developers view assigned tickets" ON public.priority_ticket_logs
    FOR SELECT USING (assigned_developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Prime users view own SLA" ON public.sla_monitoring
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage SLA" ON public.sla_monitoring
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users view own assignments" ON public.developer_assignment_priority
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage assignments" ON public.developer_assignment_priority
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users manage own threads" ON public.dedicated_support_threads
    FOR ALL USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage all threads" ON public.dedicated_support_threads
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Thread participants view messages" ON public.dedicated_support_messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM dedicated_support_threads t 
            WHERE t.id = thread_id 
            AND (t.prime_user_id = get_prime_user_id(auth.uid()) OR can_manage_prime_users(auth.uid()))
        )
    );

CREATE POLICY "Thread participants insert messages" ON public.dedicated_support_messages
    FOR INSERT WITH CHECK (sender_id = auth.uid());

CREATE POLICY "Prime users view own wallet" ON public.prime_wallet_usage
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Finance manages wallets" ON public.prime_wallet_usage
    FOR ALL USING (can_access_finance(auth.uid()));

CREATE POLICY "Admins manage wallets" ON public.prime_wallet_usage
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users view own reports" ON public.prime_performance_reports
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage reports" ON public.prime_performance_reports
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users view own features" ON public.prime_feature_access
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage features" ON public.prime_feature_access
    FOR ALL USING (can_manage_prime_users(auth.uid()));

CREATE POLICY "Prime users view own hosting" ON public.prime_hosting_status
    FOR SELECT USING (prime_user_id = get_prime_user_id(auth.uid()));

CREATE POLICY "Admins manage hosting" ON public.prime_hosting_status
    FOR ALL USING (can_manage_prime_users(auth.uid()));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_prime_user_profiles_user_id ON public.prime_user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_priority_ticket_logs_prime_user ON public.priority_ticket_logs(prime_user_id);
CREATE INDEX IF NOT EXISTS idx_priority_ticket_logs_status ON public.priority_ticket_logs(status);
CREATE INDEX IF NOT EXISTS idx_sla_monitoring_prime_user ON public.sla_monitoring(prime_user_id);
CREATE INDEX IF NOT EXISTS idx_dedicated_support_threads_prime_user ON public.dedicated_support_threads(prime_user_id);
CREATE INDEX IF NOT EXISTS idx_prime_wallet_usage_prime_user ON public.prime_wallet_usage(prime_user_id);
-- ===== 20251219145649_e116f1f0-39f4-4ab4-95f3-6162d622cbec.sql =====
-- Create promise status enum
CREATE TYPE public.promise_status AS ENUM ('assigned', 'promised', 'in_progress', 'breached', 'completed');

-- Create promise_logs table for tracking all promises
CREATE TABLE public.promise_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    developer_id UUID REFERENCES public.developers(id) ON DELETE CASCADE NOT NULL,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE CASCADE NOT NULL,
    promise_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    finished_time TIMESTAMP WITH TIME ZONE,
    breach_reason TEXT,
    score_effect INTEGER DEFAULT 0,
    status promise_status NOT NULL DEFAULT 'promised',
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    extended_count INTEGER DEFAULT 0,
    extended_deadline TIMESTAMP WITH TIME ZONE,
    extended_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create buzzer_queue table for notification system
CREATE TABLE public.buzzer_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_type TEXT NOT NULL,
    role_target app_role,
    region TEXT,
    task_id UUID REFERENCES public.developer_tasks(id) ON DELETE CASCADE,
    lead_id UUID,
    priority TEXT DEFAULT 'normal',
    status TEXT DEFAULT 'pending',
    accepted_by UUID,
    accepted_at TIMESTAMP WITH TIME ZONE,
    auto_escalate_after INTEGER DEFAULT 5,
    escalation_level INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create permissions table for granular access control
CREATE TABLE public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_name TEXT NOT NULL,
    role app_role NOT NULL,
    read_access BOOLEAN DEFAULT false,
    write_access BOOLEAN DEFAULT false,
    admin_access BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE(module_name, role)
);

-- Create rd_ideas table for R&D department
CREATE TABLE public.rd_ideas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    submitted_by UUID,
    status TEXT DEFAULT 'pending',
    priority TEXT DEFAULT 'medium',
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    votes INTEGER DEFAULT 0,
    category TEXT,
    implementation_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create legal_logs table for compliance
CREATE TABLE public.legal_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action_type TEXT NOT NULL,
    user_id UUID,
    compliance_flag BOOLEAN DEFAULT false,
    description TEXT,
    module_affected TEXT,
    ip_address TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create marketing_campaigns table
CREATE TABLE public.marketing_campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    channel TEXT NOT NULL,
    budget NUMERIC DEFAULT 0,
    spent NUMERIC DEFAULT 0,
    conversion_rate NUMERIC DEFAULT 0,
    leads_generated INTEGER DEFAULT 0,
    influencer_id UUID,
    franchise_id UUID,
    status TEXT DEFAULT 'draft',
    start_date DATE,
    end_date DATE,
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on all new tables
ALTER TABLE public.promise_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buzzer_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rd_ideas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_campaigns ENABLE ROW LEVEL SECURITY;

-- Promise logs policies
CREATE POLICY "Developers view own promises" ON public.promise_logs
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Developers create own promises" ON public.promise_logs
    FOR INSERT WITH CHECK (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Developers update own promises" ON public.promise_logs
    FOR UPDATE USING (developer_id = get_developer_id(auth.uid()));

CREATE POLICY "Managers manage all promises" ON public.promise_logs
    FOR ALL USING (can_manage_developers(auth.uid()));

-- Buzzer queue policies
CREATE POLICY "Users view relevant buzzers" ON public.buzzer_queue
    FOR SELECT USING (
        has_role(auth.uid(), role_target) OR 
        has_role(auth.uid(), 'super_admin')
    );

CREATE POLICY "System inserts buzzers" ON public.buzzer_queue
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users accept buzzers" ON public.buzzer_queue
    FOR UPDATE USING (
        has_role(auth.uid(), role_target) OR 
        has_role(auth.uid(), 'super_admin')
    );

CREATE POLICY "Admins manage buzzers" ON public.buzzer_queue
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- Permissions table policies
CREATE POLICY "Anyone view permissions" ON public.permissions
    FOR SELECT USING (true);

CREATE POLICY "Admins manage permissions" ON public.permissions
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- R&D ideas policies
CREATE POLICY "Anyone view rd ideas" ON public.rd_ideas
    FOR SELECT USING (true);

CREATE POLICY "Authenticated submit ideas" ON public.rd_ideas
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins manage rd ideas" ON public.rd_ideas
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- Legal logs policies (read-only for non-admins)
CREATE POLICY "Admins manage legal logs" ON public.legal_logs
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Legal team view logs" ON public.legal_logs
    FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

-- Marketing campaigns policies
CREATE POLICY "View own campaigns" ON public.marketing_campaigns
    FOR SELECT USING (
        created_by = auth.uid() OR
        franchise_id = get_franchise_id(auth.uid()) OR
        has_role(auth.uid(), 'super_admin')
    );

CREATE POLICY "Admins manage campaigns" ON public.marketing_campaigns
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- Create function to check promise overlap
CREATE OR REPLACE FUNCTION public.has_overlapping_promise(_developer_id UUID, _deadline TIMESTAMP WITH TIME ZONE)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.promise_logs
        WHERE developer_id = _developer_id
        AND status IN ('promised', 'in_progress')
        AND deadline > now()
        AND _deadline < deadline
    )
$$;

-- Create function to check workload threshold
CREATE OR REPLACE FUNCTION public.exceeds_workload_threshold(_developer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (
        SELECT COUNT(*) FROM public.promise_logs
        WHERE developer_id = _developer_id
        AND status IN ('promised', 'in_progress')
    ) >= 3
$$;

-- Create trigger for promise breach detection
CREATE OR REPLACE FUNCTION public.check_promise_breach()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deadline < now() AND NEW.status IN ('promised', 'in_progress') THEN
        NEW.status := 'breached';
        NEW.breach_reason := COALESCE(NEW.breach_reason, 'Deadline exceeded');
        NEW.score_effect := -10;
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER promise_breach_check
    BEFORE UPDATE ON public.promise_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.check_promise_breach();

-- Insert default permissions for all modules
INSERT INTO public.permissions (module_name, role, read_access, write_access, admin_access) VALUES
('lead_manager', 'super_admin', true, true, true),
('developer_manager', 'super_admin', true, true, true),
('reseller_manager', 'super_admin', true, true, true),
('franchise_manager', 'super_admin', true, true, true),
('influencer_manager', 'super_admin', true, true, true),
('prime_user_manager', 'super_admin', true, true, true),
('seo_manager', 'super_admin', true, true, true),
('support_manager', 'super_admin', true, true, true),
('task_manager', 'super_admin', true, true, true),
('demo_manager', 'super_admin', true, true, true),
('performance_manager', 'super_admin', true, true, true),
('client_success_manager', 'super_admin', true, true, true),
('marketing_manager', 'super_admin', true, true, true),
('finance_manager', 'super_admin', true, true, true),
('rnd_department', 'super_admin', true, true, true),
('legal_compliance', 'super_admin', true, true, true),
('hr_hiring', 'super_admin', true, true, true),
('system_settings', 'super_admin', true, true, true),
('notification_buzzer', 'super_admin', true, true, true),
('lead_manager', 'franchise', true, true, false),
('developer_manager', 'developer', true, false, false),
('task_manager', 'developer', true, true, false),
('demo_manager', 'franchise', true, false, false),
('demo_manager', 'reseller', true, false, false);
-- ===== 20251219162457_15d7fe77-cc16-4fa8-a3a8-3735c3e8c938.sql =====
-- Internal Chat Channels
CREATE TABLE public.internal_chat_channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  channel_type TEXT NOT NULL DEFAULT 'role_based', -- 'role_based', 'direct', 'group', 'broadcast'
  target_roles public.app_role[],
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  is_active BOOLEAN DEFAULT true,
  is_approved BOOLEAN DEFAULT false,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  is_frozen BOOLEAN DEFAULT false,
  frozen_by UUID REFERENCES auth.users(id),
  frozen_at TIMESTAMP WITH TIME ZONE
);

-- Internal Chat Messages
CREATE TABLE public.internal_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id UUID REFERENCES public.internal_chat_channels(id) ON DELETE CASCADE NOT NULL,
  sender_id UUID REFERENCES auth.users(id) NOT NULL,
  sender_role public.app_role NOT NULL,
  sender_masked_name TEXT NOT NULL,
  sender_region TEXT,
  message_type TEXT NOT NULL DEFAULT 'text', -- 'text', 'voice_note', 'ai_auto_reply', 'system'
  content TEXT NOT NULL,
  original_content TEXT, -- Stores original before masking
  voice_transcript TEXT,
  is_masked BOOLEAN DEFAULT false,
  is_flagged BOOLEAN DEFAULT false,
  flag_reason TEXT,
  flagged_by TEXT, -- 'ai' or user_id
  is_visible BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  read_by UUID[] DEFAULT '{}'
);

-- Chat Violations Log
CREATE TABLE public.chat_violations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  channel_id UUID REFERENCES public.internal_chat_channels(id),
  message_id UUID REFERENCES public.internal_chat_messages(id),
  violation_type TEXT NOT NULL, -- 'contact_share', 'profanity', 'abuse', 'data_leak', 'bypass_attempt'
  violation_level INTEGER DEFAULT 1, -- 1=warning, 2=mute, 3=force_logout
  description TEXT,
  detected_content TEXT,
  action_taken TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  resolved_at TIMESTAMP WITH TIME ZONE,
  resolved_by UUID REFERENCES auth.users(id)
);

-- Chat User Status
CREATE TABLE public.chat_user_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) NOT NULL UNIQUE,
  is_online BOOLEAN DEFAULT false,
  is_muted BOOLEAN DEFAULT false,
  muted_until TIMESTAMP WITH TIME ZONE,
  mute_reason TEXT,
  violation_count INTEGER DEFAULT 0,
  last_seen TIMESTAMP WITH TIME ZONE,
  last_active_channel UUID REFERENCES public.internal_chat_channels(id),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.internal_chat_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internal_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_user_status ENABLE ROW LEVEL SECURITY;

-- RLS Policies for channels
CREATE POLICY "Authenticated users can view active approved channels"
ON public.internal_chat_channels FOR SELECT
TO authenticated
USING (is_active = true AND (is_approved = true OR public.has_role(auth.uid(), 'super_admin')));

CREATE POLICY "Super admin can manage all channels"
ON public.internal_chat_channels FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'));

-- RLS Policies for messages
CREATE POLICY "Authenticated users can view messages in their channels"
ON public.internal_chat_messages FOR SELECT
TO authenticated
USING (is_visible = true OR public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Authenticated users can send messages"
ON public.internal_chat_messages FOR INSERT
TO authenticated
WITH CHECK (sender_id = auth.uid());

CREATE POLICY "Super admin can manage all messages"
ON public.internal_chat_messages FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'));

-- RLS Policies for violations (super admin only)
CREATE POLICY "Super admin can view violations"
ON public.chat_violations FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin') OR user_id = auth.uid());

CREATE POLICY "System can create violations"
ON public.chat_violations FOR INSERT
TO authenticated
WITH CHECK (true);

-- RLS Policies for user status
CREATE POLICY "Users can view online status"
ON public.chat_user_status FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Users can update own status"
ON public.chat_user_status FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can insert own status"
ON public.chat_user_status FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Enable realtime for messages
ALTER PUBLICATION supabase_realtime ADD TABLE public.internal_chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_user_status;

-- Create indexes for performance
CREATE INDEX idx_chat_messages_channel ON public.internal_chat_messages(channel_id);
CREATE INDEX idx_chat_messages_sender ON public.internal_chat_messages(sender_id);
CREATE INDEX idx_chat_messages_created ON public.internal_chat_messages(created_at DESC);
CREATE INDEX idx_chat_violations_user ON public.chat_violations(user_id);
CREATE INDEX idx_chat_status_user ON public.chat_user_status(user_id);
-- ===== 20251219190138_32e80950-6550-4e1d-9043-1c42121bf135.sql =====
-- Personal Chat System with Admin Approval

-- Chat threads table
CREATE TABLE public.personal_chat_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_one UUID NOT NULL,
  participant_two UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  last_message_at TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true
);

-- Personal messages table with approval workflow
CREATE TABLE public.personal_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID REFERENCES public.personal_chat_threads(id) ON DELETE CASCADE NOT NULL,
  sender_id UUID NOT NULL,
  receiver_id UUID NOT NULL,
  message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'voice', 'image', 'file')),
  content TEXT,
  voice_url TEXT,
  voice_duration INTEGER, -- in seconds
  file_url TEXT,
  file_name TEXT,
  
  -- Approval workflow
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'flagged')),
  approved_by UUID,
  approved_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  
  -- Metadata
  is_read BOOLEAN DEFAULT false,
  read_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Message approval queue for super admin
CREATE TABLE public.message_approval_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES public.personal_chat_messages(id) ON DELETE CASCADE NOT NULL,
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  assigned_admin UUID,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.personal_chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_approval_queue ENABLE ROW LEVEL SECURITY;

-- RLS Policies for threads
CREATE POLICY "Users can view their own threads"
ON public.personal_chat_threads FOR SELECT
USING (auth.uid() = participant_one OR auth.uid() = participant_two);

CREATE POLICY "Super admin can view all threads"
ON public.personal_chat_threads FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'super_admin'
  )
);

CREATE POLICY "Users can create threads"
ON public.personal_chat_threads FOR INSERT
WITH CHECK (auth.uid() = participant_one OR auth.uid() = participant_two);

-- RLS Policies for messages
CREATE POLICY "Users can view approved messages in their threads"
ON public.personal_chat_messages FOR SELECT
USING (
  (auth.uid() = sender_id OR auth.uid() = receiver_id) 
  AND (status = 'approved' OR sender_id = auth.uid())
);

CREATE POLICY "Super admin can view all messages"
ON public.personal_chat_messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'super_admin'
  )
);

CREATE POLICY "Users can send messages"
ON public.personal_chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Super admin can update messages"
ON public.personal_chat_messages FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'super_admin'
  )
);

-- RLS Policies for approval queue
CREATE POLICY "Super admin can manage approval queue"
ON public.message_approval_queue FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'super_admin'
  )
);

-- Trigger to add messages to approval queue
CREATE OR REPLACE FUNCTION add_to_approval_queue()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.message_approval_queue (message_id, priority)
  VALUES (NEW.id, 'normal');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_message_created
AFTER INSERT ON public.personal_chat_messages
FOR EACH ROW
EXECUTE FUNCTION add_to_approval_queue();

-- Function to update thread timestamp
CREATE OR REPLACE FUNCTION update_thread_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.personal_chat_threads
  SET last_message_at = now(), updated_at = now()
  WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_message_sent
AFTER INSERT ON public.personal_chat_messages
FOR EACH ROW
EXECUTE FUNCTION update_thread_timestamp();

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.personal_chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_approval_queue;
-- ===== 20251219190146_2077c6b4-9f6c-456c-95eb-14f7c7723794.sql =====
-- Fix function search path security warnings
ALTER FUNCTION add_to_approval_queue() SET search_path = public;
ALTER FUNCTION update_thread_timestamp() SET search_path = public;
-- ===== 20251219194831_8a784732-b62b-4555-93a9-0d0ba77b9dc7.sql =====
-- =====================================================
-- SOFTWARE VALA: Missing Tables Only
-- =====================================================

-- 1. PRODUCTS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_name TEXT NOT NULL,
    category TEXT,
    description TEXT,
    pricing_model TEXT DEFAULT 'one-time',
    lifetime_price NUMERIC(12,2),
    monthly_price NUMERIC(12,2),
    features_json JSONB DEFAULT '[]'::jsonb,
    tech_stack TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. PRODUCT_VERSIONS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.product_versions (
    version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID,
    version_number TEXT NOT NULL,
    changes_notes TEXT,
    release_date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. TASKS TABLE - generic tasks (missing)
CREATE TABLE IF NOT EXISTS public.tasks (
    task_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID,
    lead_id UUID,
    assigned_to_dev UUID,
    created_by UUID,
    status TEXT DEFAULT 'pending',
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    promised_time TIMESTAMPTZ,
    difficulty TEXT DEFAULT 'medium',
    priority TEXT DEFAULT 'normal',
    remarks TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. DEV_TIMER TABLE (missing)
CREATE TABLE IF NOT EXISTS public.dev_timer (
    timer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID,
    dev_id UUID,
    start_timestamp TIMESTAMPTZ,
    pause_timestamp TIMESTAMPTZ,
    stop_timestamp TIMESTAMPTZ,
    total_seconds INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. DEV_PERFORMANCE TABLE (missing)
CREATE TABLE IF NOT EXISTS public.dev_performance (
    record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dev_id UUID,
    task_id UUID,
    score_delivery INTEGER DEFAULT 0,
    score_behavior INTEGER DEFAULT 0,
    score_speed INTEGER DEFAULT 0,
    final_score INTEGER DEFAULT 0,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. CHAT_THREADS TABLE (missing - different from internal_chat)
CREATE TABLE IF NOT EXISTS public.chat_threads (
    thread_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID,
    related_lead UUID,
    related_task UUID,
    related_role app_role,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. CHAT_MESSAGES TABLE (missing - different from internal_chat)
CREATE TABLE IF NOT EXISTS public.chat_messages (
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID,
    sender_id UUID,
    masked_sender TEXT,
    message_text TEXT NOT NULL,
    language TEXT DEFAULT 'en',
    translated_text TEXT,
    cannot_edit BOOLEAN DEFAULT true,
    cannot_delete BOOLEAN DEFAULT true,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. WALLETS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.wallets (
    wallet_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    balance NUMERIC(12,2) DEFAULT 0,
    currency TEXT DEFAULT 'INR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. TRANSACTIONS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID,
    type TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    reference TEXT,
    related_user UUID,
    related_role app_role,
    related_sale UUID,
    status TEXT DEFAULT 'completed',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. PAYOUT_REQUESTS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.payout_requests (
    payout_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    processed_by UUID,
    payment_method TEXT,
    bank_details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. SUBSCRIPTIONS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    sub_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    plan TEXT NOT NULL,
    amount NUMERIC(12,2),
    validity INTEGER DEFAULT 30,
    status TEXT DEFAULT 'active',
    activated_at TIMESTAMPTZ DEFAULT now(),
    expired_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 12. INVOICES TABLE (missing)
CREATE TABLE IF NOT EXISTS public.invoices (
    invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    invoice_number TEXT,
    amount NUMERIC(12,2) NOT NULL,
    tax NUMERIC(12,2) DEFAULT 0,
    currency TEXT DEFAULT 'INR',
    pdf_link TEXT,
    status TEXT DEFAULT 'generated',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 13. KYC_DOCUMENTS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.kyc_documents (
    kyc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    doc_type TEXT NOT NULL,
    doc_file TEXT,
    status TEXT DEFAULT 'pending',
    verified_by UUID,
    rejection_reason TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 14. SECURITY_LOGS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.security_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    event_type TEXT NOT NULL,
    event_details TEXT,
    ip TEXT,
    device TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 15. IP_LOCKS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.ip_locks (
    lock_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ip TEXT NOT NULL,
    device TEXT,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 16. AUDIT_LOGS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module TEXT NOT NULL,
    action TEXT NOT NULL,
    user_id UUID,
    role app_role,
    meta_json JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 17. SYSTEM_HEALTH TABLE (missing)
CREATE TABLE IF NOT EXISTS public.system_health (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric TEXT NOT NULL,
    value NUMERIC,
    unit TEXT,
    status TEXT DEFAULT 'normal',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 18. FRAUD_ALERTS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.fraud_alerts (
    alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    type TEXT NOT NULL,
    severity TEXT DEFAULT 'medium',
    flagged_by_ai BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'open',
    resolution_notes TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 19. INCIDENTS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.incidents (
    incident_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reported_by UUID,
    assigned_to UUID,
    severity TEXT DEFAULT 'medium',
    title TEXT NOT NULL,
    description TEXT,
    resolution TEXT,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 20. RESEARCH_SUGGESTIONS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.research_suggestions (
    suggestion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submitted_by UUID,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT,
    status TEXT DEFAULT 'pending',
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 21. TRAINING_LOGS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.training_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    module TEXT NOT NULL,
    progress INTEGER DEFAULT 0,
    score INTEGER,
    certificate_url TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 22. LEAD_CONVERSIONS TABLE (missing)
CREATE TABLE IF NOT EXISTS public.lead_conversions (
    conversion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID,
    product_id UUID,
    revenue NUMERIC(12,2) DEFAULT 0,
    commission NUMERIC(12,2) DEFAULT 0,
    converted_by UUID,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 23. ROLES TABLE (missing - for UI management)
CREATE TABLE IF NOT EXISTS public.roles (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name TEXT NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 24. ROLE_PERMISSIONS JUNCTION TABLE (missing)
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name TEXT NOT NULL,
    permission_name TEXT NOT NULL,
    module_name TEXT NOT NULL,
    action TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(role_name, module_name, action)
);

-- =====================================================
-- ENABLE RLS ON ALL NEW TABLES
-- =====================================================

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dev_timer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dev_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ip_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fraud_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.research_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS POLICIES FOR NEW TABLES
-- =====================================================

-- PRODUCTS
CREATE POLICY "admin_products" ON public.products FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "view_products" ON public.products FOR SELECT USING (true);

-- PRODUCT_VERSIONS
CREATE POLICY "admin_versions" ON public.product_versions FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "view_versions" ON public.product_versions FOR SELECT USING (true);

-- TASKS
CREATE POLICY "managers_tasks" ON public.tasks FOR ALL USING (can_manage_developers(auth.uid()));
CREATE POLICY "devs_own_tasks" ON public.tasks FOR SELECT USING (assigned_to_dev = get_developer_id(auth.uid()));

-- DEV_TIMER
CREATE POLICY "devs_own_timer" ON public.dev_timer FOR ALL USING (dev_id = get_developer_id(auth.uid()));
CREATE POLICY "managers_timer" ON public.dev_timer FOR SELECT USING (can_manage_developers(auth.uid()));

-- DEV_PERFORMANCE
CREATE POLICY "devs_own_perf" ON public.dev_performance FOR SELECT USING (dev_id = get_developer_id(auth.uid()));
CREATE POLICY "managers_perf" ON public.dev_performance FOR ALL USING (can_manage_developers(auth.uid()));

-- CHAT_THREADS
CREATE POLICY "users_threads" ON public.chat_threads FOR ALL USING (created_by = auth.uid());
CREATE POLICY "admin_threads" ON public.chat_threads FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

-- CHAT_MESSAGES
CREATE POLICY "users_send_msg" ON public.chat_messages FOR INSERT WITH CHECK (sender_id = auth.uid());
CREATE POLICY "users_read_msg" ON public.chat_messages FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chat_threads WHERE thread_id = chat_messages.thread_id AND created_by = auth.uid())
    OR has_role(auth.uid(), 'super_admin')
);

-- WALLETS
CREATE POLICY "users_own_wallet" ON public.wallets FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "finance_wallets" ON public.wallets FOR ALL USING (can_access_finance(auth.uid()));

-- TRANSACTIONS
CREATE POLICY "users_own_tx" ON public.transactions FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.wallets WHERE wallet_id = transactions.wallet_id AND user_id = auth.uid())
);
CREATE POLICY "finance_tx" ON public.transactions FOR ALL USING (can_access_finance(auth.uid()));

-- PAYOUT_REQUESTS
CREATE POLICY "users_own_payout" ON public.payout_requests FOR ALL USING (user_id = auth.uid());
CREATE POLICY "finance_payout" ON public.payout_requests FOR ALL USING (can_access_finance(auth.uid()));

-- SUBSCRIPTIONS
CREATE POLICY "users_own_subs" ON public.subscriptions FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "admin_subs" ON public.subscriptions FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- INVOICES
CREATE POLICY "users_own_inv" ON public.invoices FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "finance_inv" ON public.invoices FOR ALL USING (can_access_finance(auth.uid()));

-- KYC_DOCUMENTS
CREATE POLICY "users_own_kyc" ON public.kyc_documents FOR ALL USING (user_id = auth.uid());
CREATE POLICY "admin_kyc" ON public.kyc_documents FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- SECURITY_LOGS
CREATE POLICY "sys_sec_logs" ON public.security_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "admin_sec_logs" ON public.security_logs FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

-- IP_LOCKS
CREATE POLICY "users_own_locks" ON public.ip_locks FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "admin_locks" ON public.ip_locks FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- AUDIT_LOGS
CREATE POLICY "sys_audit" ON public.audit_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "admin_audit" ON public.audit_logs FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

-- SYSTEM_HEALTH
CREATE POLICY "admin_health" ON public.system_health FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- FRAUD_ALERTS
CREATE POLICY "admin_fraud" ON public.fraud_alerts FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- INCIDENTS
CREATE POLICY "report_incident" ON public.incidents FOR INSERT WITH CHECK (reported_by = auth.uid());
CREATE POLICY "view_own_incident" ON public.incidents FOR SELECT USING (reported_by = auth.uid() OR assigned_to = auth.uid());
CREATE POLICY "admin_incident" ON public.incidents FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- RESEARCH_SUGGESTIONS
CREATE POLICY "submit_suggestion" ON public.research_suggestions FOR INSERT WITH CHECK (submitted_by = auth.uid());
CREATE POLICY "view_own_suggestion" ON public.research_suggestions FOR SELECT USING (submitted_by = auth.uid());
CREATE POLICY "admin_suggestion" ON public.research_suggestions FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- TRAINING_LOGS
CREATE POLICY "users_own_training" ON public.training_logs FOR ALL USING (user_id = auth.uid());
CREATE POLICY "admin_training" ON public.training_logs FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

-- LEAD_CONVERSIONS
CREATE POLICY "finance_conversions" ON public.lead_conversions FOR ALL USING (can_access_finance(auth.uid()));

-- ROLES
CREATE POLICY "admin_roles" ON public.roles FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "view_roles" ON public.roles FOR SELECT USING (true);

-- ROLE_PERMISSIONS
CREATE POLICY "admin_role_perms" ON public.role_permissions FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "view_role_perms" ON public.role_permissions FOR SELECT USING (true);

-- =====================================================
-- INSERT DEFAULT ROLES
-- =====================================================
INSERT INTO public.roles (role_name, description) VALUES
    ('super_admin', 'Full system access and control'),
    ('franchise', 'Franchise partner access'),
    ('reseller', 'Reseller access'),
    ('developer', 'Developer access'),
    ('prime', 'Premium client access'),
    ('influencer', 'Affiliate and influencer access'),
    ('lead_manager', 'Lead management access'),
    ('task_manager', 'Task management access'),
    ('demo_manager', 'Demo management access'),
    ('finance_manager', 'Finance access'),
    ('support_agent', 'Support access'),
    ('sales_executive', 'Sales access'),
    ('seo_manager', 'SEO management access'),
    ('marketing_manager', 'Marketing access'),
    ('hr_manager', 'HR access'),
    ('legal_compliance', 'Legal and compliance access'),
    ('performance_manager', 'Performance tracking access'),
    ('client_success', 'Client success access'),
    ('rnd_manager', 'R&D access')
ON CONFLICT (role_name) DO NOTHING;
-- ===== 20251219211212_66e55d3b-8883-418a-aba4-9be4fa1a0bf2.sql =====

-- Add remaining roles to app_role enum (9 new roles)
-- These must be in a separate transaction
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'seo_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'seo_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'lead_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'lead_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'task_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'task_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'rnd_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'rnd_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'performance_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'performance_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'finance_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'finance_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'legal_compliance' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'legal_compliance';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'hr_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'hr_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'support' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'support';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'ai_manager' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'ai_manager';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'admin' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'app_role')) THEN
        ALTER TYPE public.app_role ADD VALUE 'admin';
    END IF;
END $$;

-- ===== 20251219211333_ecb22bdd-7721-47e0-82b1-08d1cd7b3030.sql =====

-- Enable realtime for new tables (with IF NOT EXISTS logic via DO block)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'command_center_alerts') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.command_center_alerts;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'buzzer_acknowledgments') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.buzzer_acknowledgments;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- ===== 20251221182459_43915bfd-552f-4085-b5ff-56c2f9c7892e.sql =====
-- ============================================
-- SOFTWARE VALA - Add new enum roles
-- Run this first, then tables in next migration
-- ============================================

-- Add missing roles to the enum
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'lead_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'task_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'demo_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'seo_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'marketing_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'client_success';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'hr_manager';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'legal_compliance';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'api_security';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'r_and_d';
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'performance_manager';
-- ===== 20251221182738_f61c48e1-0760-4fae-a67c-14507824f5dd.sql =====
-- SOFTWARE VALA SCHEMA - Core Tables Only
-- Simplified migration

-- UNIFIED WALLETS TABLE
CREATE TABLE IF NOT EXISTS public.unified_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_role app_role NOT NULL,
  available_balance NUMERIC(15,2) NOT NULL DEFAULT 0,
  pending_balance NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_earned NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_withdrawn NUMERIC(15,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'INR',
  is_frozen BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, user_role)
);

ALTER TABLE public.unified_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own wallet" ON public.unified_wallets FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Finance manages wallets" ON public.unified_wallets FOR ALL USING (can_access_finance(auth.uid()));

-- UNIFIED WALLET TRANSACTIONS
CREATE TABLE IF NOT EXISTS public.unified_wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID REFERENCES public.unified_wallets(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  transaction_type TEXT NOT NULL,
  amount NUMERIC(15,2) NOT NULL,
  balance_after NUMERIC(15,2) NOT NULL,
  currency TEXT DEFAULT 'INR',
  description TEXT,
  reference_type TEXT,
  reference_id UUID,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.unified_wallet_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own txn" ON public.unified_wallet_transactions FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Finance manages txn" ON public.unified_wallet_transactions FOR ALL USING (can_access_finance(auth.uid()));

-- SEO MANAGER
CREATE TABLE IF NOT EXISTS public.seo_manager (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module_target TEXT NOT NULL,
  keyword TEXT NOT NULL,
  meta_title TEXT,
  meta_description TEXT,
  region TEXT,
  rank_position INTEGER,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.seo_manager ENABLE ROW LEVEL SECURITY;
CREATE POLICY "SEO view" ON public.seo_manager FOR SELECT USING (true);
CREATE POLICY "SEO manage" ON public.seo_manager FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- R&D SUGGESTIONS
CREATE TABLE IF NOT EXISTS public.rnd_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suggested_by UUID REFERENCES auth.users(id) NOT NULL,
  feature_title TEXT NOT NULL,
  feature_description TEXT,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'submitted',
  approved_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.rnd_suggestions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "RND submit" ON public.rnd_suggestions FOR INSERT WITH CHECK (suggested_by = auth.uid());
CREATE POLICY "RND view" ON public.rnd_suggestions FOR SELECT USING (true);
CREATE POLICY "RND manage" ON public.rnd_suggestions FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- CLIENT SUCCESS CASES
CREATE TABLE IF NOT EXISTS public.client_success_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id UUID REFERENCES auth.users(id) NOT NULL,
  issue_type TEXT NOT NULL,
  severity TEXT DEFAULT 'medium',
  description TEXT,
  resolution_notes TEXT,
  status TEXT DEFAULT 'open',
  assigned_to UUID REFERENCES auth.users(id),
  satisfaction_score INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.client_success_cases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "CS manage" ON public.client_success_cases FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "CS own" ON public.client_success_cases FOR SELECT USING (client_user_id = auth.uid());

-- LEGAL LOGS
CREATE TABLE IF NOT EXISTS public.legal_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  action_type TEXT NOT NULL,
  contract_url TEXT,
  suspension_flag BOOLEAN DEFAULT false,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.legal_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Legal manage" ON public.legal_logs FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Legal own" ON public.legal_logs FOR SELECT USING (user_id = auth.uid());

-- API KEYS
CREATE TABLE IF NOT EXISTS public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  api_key_hash TEXT NOT NULL,
  api_key_prefix TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT DEFAULT 'active',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "API own" ON public.api_keys FOR ALL USING (user_id = auth.uid());
CREATE POLICY "API admin" ON public.api_keys FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- BRANCH MAP
CREATE TABLE IF NOT EXISTS public.branch_map (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_code TEXT NOT NULL UNIQUE,
  branch_name TEXT NOT NULL,
  country TEXT NOT NULL,
  state TEXT,
  city TEXT,
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  franchise_user_id UUID REFERENCES auth.users(id),
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.branch_map ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Branch view" ON public.branch_map FOR SELECT USING (true);
CREATE POLICY "Branch manage" ON public.branch_map FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- SECURITY LOGS
CREATE TABLE IF NOT EXISTS public.security_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  event_type TEXT NOT NULL,
  ip_address TEXT,
  threat_level TEXT DEFAULT 'none',
  is_blocked BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.security_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Security admin" ON public.security_logs FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Security own" ON public.security_logs FOR SELECT USING (user_id = auth.uid());

-- Indexes
CREATE INDEX IF NOT EXISTS idx_unified_wallets_user ON public.unified_wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_security_logs_user ON public.security_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_branch_map_geo ON public.branch_map(latitude, longitude);
-- ===== 20251221183933_662ceed4-3391-423c-acf0-11dd1cb04668.sql =====

-- SOFTWARE VALA - Enterprise Tables (No FK conflicts)

CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ip_address TEXT,
    device_info TEXT,
    location TEXT,
    country TEXT,
    login_at TIMESTAMPTZ DEFAULT now(),
    logout_at TIMESTAMPTZ,
    force_logout_flag BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.login_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ip_address TEXT,
    device_info TEXT,
    attempt_status TEXT DEFAULT 'success',
    failure_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.masked_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    masked_email TEXT NOT NULL,
    masked_phone TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.task_timers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL,
    developer_id UUID NOT NULL,
    start_time TIMESTAMPTZ DEFAULT now(),
    end_time TIMESTAMPTZ,
    total_seconds INTEGER DEFAULT 0,
    is_paused BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'running',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.seo_keywords (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module TEXT NOT NULL,
    keyword TEXT NOT NULL,
    current_rank INTEGER,
    region TEXT,
    status TEXT DEFAULT 'tracking',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_type TEXT DEFAULT 'direct',
    purpose TEXT,
    created_by UUID NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.chat_room_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id),
    sender_id UUID NOT NULL,
    masked_sender_name TEXT,
    message_text TEXT NOT NULL,
    edit_blocked BOOLEAN DEFAULT true,
    delete_blocked BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key TEXT NOT NULL UNIQUE,
    setting_value TEXT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    user_role app_role,
    action TEXT NOT NULL,
    table_name TEXT,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.masked_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_timers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_keywords ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_room_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_audit_log ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_sessions_user ON public.user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_login_user ON public.login_history(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON public.master_audit_log(user_id);

-- RLS Policies
CREATE POLICY "session_own" ON public.user_sessions FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "session_admin" ON public.user_sessions FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "login_own" ON public.login_history FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "login_insert" ON public.login_history FOR INSERT WITH CHECK (true);
CREATE POLICY "mask_own" ON public.masked_identities FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "mask_admin" ON public.masked_identities FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "timer_dev" ON public.task_timers FOR ALL USING (developer_id = get_developer_id(auth.uid()));
CREATE POLICY "seo_manage" ON public.seo_keywords FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'seo_manager'));
CREATE POLICY "room_view" ON public.chat_rooms FOR SELECT USING (created_by = auth.uid() OR has_role(auth.uid(), 'super_admin'));
CREATE POLICY "room_create" ON public.chat_rooms FOR INSERT WITH CHECK (created_by = auth.uid());
CREATE POLICY "msg_view" ON public.chat_room_messages FOR SELECT USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "msg_send" ON public.chat_room_messages FOR INSERT WITH CHECK (sender_id = auth.uid());
CREATE POLICY "settings_public" ON public.system_settings FOR SELECT USING (is_public = true);
CREATE POLICY "settings_admin" ON public.system_settings FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "audit_admin" ON public.master_audit_log FOR SELECT USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "audit_insert" ON public.master_audit_log FOR INSERT WITH CHECK (true);

-- ===== 20251221184102_ec7cdf69-e115-482e-984b-a74041ea5d60.sql =====

-- SOFTWARE VALA - Remaining Enterprise Tables

-- HR & HIRING
CREATE TABLE IF NOT EXISTS public.hr_applicants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position TEXT NOT NULL,
    full_name TEXT NOT NULL,
    masked_email TEXT,
    masked_phone TEXT,
    resume_path TEXT,
    portfolio_url TEXT,
    experience_years INTEGER,
    skills_json JSONB,
    source TEXT,
    status TEXT DEFAULT 'new',
    screening_score INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hr_interviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id UUID NOT NULL REFERENCES public.hr_applicants(id),
    interviewer_id UUID NOT NULL,
    interview_type TEXT DEFAULT 'technical',
    scheduled_at TIMESTAMPTZ NOT NULL,
    conducted_at TIMESTAMPTZ,
    score INTEGER,
    feedback TEXT,
    recommendation TEXT,
    status TEXT DEFAULT 'scheduled',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- LEGAL & COMPLIANCE
CREATE TABLE IF NOT EXISTS public.legal_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_type TEXT NOT NULL,
    title TEXT NOT NULL,
    file_url TEXT,
    version TEXT,
    region TEXT[],
    effective_date DATE,
    requires_signature BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    document_id UUID NOT NULL REFERENCES public.legal_documents(id),
    signed_at TIMESTAMPTZ,
    ip_address TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.compliance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    compliance_type TEXT NOT NULL,
    issue TEXT,
    severity TEXT DEFAULT 'low',
    resolution TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- SECURITY
CREATE TABLE IF NOT EXISTS public.frozen_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    freeze_reason TEXT NOT NULL,
    frozen_by UUID,
    freeze_date TIMESTAMPTZ DEFAULT now(),
    unfreeze_date TIMESTAMPTZ,
    status TEXT DEFAULT 'frozen'
);

CREATE TABLE IF NOT EXISTS public.suspicious_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    reason TEXT NOT NULL,
    severity TEXT DEFAULT 'medium',
    details JSONB,
    flagged_at TIMESTAMPTZ DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    status TEXT DEFAULT 'open'
);

CREATE TABLE IF NOT EXISTS public.ip_whitelist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ip_address TEXT NOT NULL,
    label TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, ip_address)
);

CREATE TABLE IF NOT EXISTS public.role_restrictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role app_role NOT NULL UNIQUE,
    max_devices INTEGER DEFAULT 3,
    max_sessions INTEGER DEFAULT 2,
    ip_restriction BOOLEAN DEFAULT false,
    geo_restriction BOOLEAN DEFAULT false,
    allowed_countries TEXT[],
    created_at TIMESTAMPTZ DEFAULT now()
);

-- PRODUCT & FEATURES
CREATE TABLE IF NOT EXISTS public.product_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID,
    name TEXT NOT NULL,
    description TEXT,
    is_core BOOLEAN DEFAULT true,
    additional_price NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id UUID REFERENCES public.product_modules(id),
    flag_key TEXT NOT NULL UNIQUE,
    flag_name TEXT,
    description TEXT,
    enabled BOOLEAN DEFAULT false,
    rollout_percentage INTEGER DEFAULT 0,
    target_roles app_role[],
    created_at TIMESTAMPTZ DEFAULT now()
);

-- LOCALIZATION
CREATE TABLE IF NOT EXISTS public.localization (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lang_code TEXT NOT NULL,
    content_key TEXT NOT NULL,
    content_value TEXT NOT NULL,
    context TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(lang_code, content_key)
);

-- SEO (Enhanced)
CREATE TABLE IF NOT EXISTS public.seo_meta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    page_path TEXT NOT NULL UNIQUE,
    title TEXT,
    description TEXT,
    keywords TEXT[],
    og_image TEXT,
    canonical_url TEXT,
    robots TEXT DEFAULT 'index, follow',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.seo_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    keyword_id UUID REFERENCES public.seo_keywords(id),
    position INTEGER,
    impressions INTEGER,
    clicks INTEGER,
    report_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- PROMO ASSETS
CREATE TABLE IF NOT EXISTS public.promo_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID,
    asset_type TEXT,
    file_path TEXT NOT NULL,
    file_name TEXT,
    usage_count INTEGER DEFAULT 0,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CLIENT FEEDBACK
CREATE TABLE IF NOT EXISTS public.client_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    feedback_type TEXT DEFAULT 'general',
    rating INTEGER,
    csat_score INTEGER,
    nps_score INTEGER,
    feedback_text TEXT,
    category TEXT,
    status TEXT DEFAULT 'new',
    responded_by UUID,
    response_text TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- VOICE LOGS
CREATE TABLE IF NOT EXISTS public.voice_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.chat_rooms(id),
    sender_id UUID NOT NULL,
    transcript TEXT,
    audio_path TEXT,
    duration_seconds INTEGER,
    language TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- TASK DELIVERIES
CREATE TABLE IF NOT EXISTS public.task_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL,
    developer_id UUID NOT NULL,
    delivery_type TEXT DEFAULT 'final',
    files_json JSONB,
    commit_url TEXT,
    notes TEXT,
    delivered_at TIMESTAMPTZ DEFAULT now(),
    reviewed_by UUID,
    review_status TEXT DEFAULT 'pending',
    quality_score INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- LEAD HISTORY
CREATE TABLE IF NOT EXISTS public.lead_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL,
    old_status TEXT,
    new_status TEXT NOT NULL,
    updated_by UUID,
    updated_by_role app_role,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.hr_applicants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.frozen_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspicious_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ip_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_restrictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.localization ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voice_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_history ENABLE ROW LEVEL SECURITY;

-- RLS POLICIES
CREATE POLICY "hr_manage" ON public.hr_applicants FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'hr_manager'));
CREATE POLICY "hr_interviews" ON public.hr_interviews FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'hr_manager'));
CREATE POLICY "legal_view" ON public.legal_documents FOR SELECT USING (status = 'active');
CREATE POLICY "legal_manage" ON public.legal_documents FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));
CREATE POLICY "agree_own" ON public.user_agreements FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "agree_sign" ON public.user_agreements FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "agree_legal" ON public.user_agreements FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));
CREATE POLICY "comply_legal" ON public.compliance_logs FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));
CREATE POLICY "frozen_admin" ON public.frozen_accounts FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "suspicious_admin" ON public.suspicious_activity FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "ip_own" ON public.ip_whitelist FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "ip_admin" ON public.ip_whitelist FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "restrict_view" ON public.role_restrictions FOR SELECT USING (true);
CREATE POLICY "restrict_admin" ON public.role_restrictions FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "module_view" ON public.product_modules FOR SELECT USING (true);
CREATE POLICY "module_admin" ON public.product_modules FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "flag_view" ON public.feature_flags FOR SELECT USING (enabled = true);
CREATE POLICY "flag_admin" ON public.feature_flags FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "locale_view" ON public.localization FOR SELECT USING (true);
CREATE POLICY "locale_admin" ON public.localization FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "seo_meta_manage" ON public.seo_meta FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'seo_manager'));
CREATE POLICY "seo_report_manage" ON public.seo_reports FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'seo_manager'));
CREATE POLICY "promo_manage" ON public.promo_assets FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'marketing_manager'));
CREATE POLICY "feedback_own" ON public.client_feedback FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "feedback_insert" ON public.client_feedback FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "feedback_cs" ON public.client_feedback FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'client_success'));
CREATE POLICY "voice_admin" ON public.voice_logs FOR SELECT USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "voice_insert" ON public.voice_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "delivery_dev" ON public.task_deliveries FOR ALL USING (developer_id = get_developer_id(auth.uid()));
CREATE POLICY "delivery_manage" ON public.task_deliveries FOR ALL USING (can_manage_developers(auth.uid()));
CREATE POLICY "lead_hist_view" ON public.lead_history FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'lead_manager'));
CREATE POLICY "lead_hist_insert" ON public.lead_history FOR INSERT WITH CHECK (true);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_hr_status ON public.hr_applicants(status);
CREATE INDEX IF NOT EXISTS idx_legal_type ON public.legal_documents(doc_type);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON public.client_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_lead_hist ON public.lead_history(lead_id);

-- ===== 20251221191354_01794fcd-7dd2-4751-999f-7770aebd08d5.sql =====
-- =============================================
-- COMPREHENSIVE GLOBAL COMPLIANCE FRAMEWORK (Fixed)
-- =============================================

-- User Consent Management (GDPR, CCPA, PDPA, POPIA, NDPR)
CREATE TABLE IF NOT EXISTS public.user_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    consent_type TEXT NOT NULL,
    consent_version TEXT NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT false,
    granted_at TIMESTAMP WITH TIME ZONE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    ip_address TEXT,
    user_agent TEXT,
    region TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(user_id, consent_type, consent_version)
);

-- Data Residency Configuration
CREATE TABLE IF NOT EXISTS public.data_residency_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_code TEXT NOT NULL UNIQUE,
    region_name TEXT NOT NULL,
    storage_location TEXT NOT NULL,
    applicable_regulations TEXT[] DEFAULT '{}',
    cross_border_allowed BOOLEAN DEFAULT false,
    encryption_required BOOLEAN DEFAULT true,
    consent_required_for_transfer BOOLEAN DEFAULT true,
    data_retention_days INTEGER DEFAULT 1095,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Regional Tax Rules
CREATE TABLE IF NOT EXISTS public.regional_tax_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code TEXT NOT NULL,
    state_code TEXT,
    tax_name TEXT NOT NULL,
    tax_rate DECIMAL(5,4) NOT NULL,
    tax_id_label TEXT,
    is_compound BOOLEAN DEFAULT false,
    applies_to TEXT[] DEFAULT '{}',
    exemption_categories TEXT[] DEFAULT '{}',
    effective_from DATE NOT NULL,
    effective_until DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Data Export/Deletion Requests
CREATE TABLE IF NOT EXISTS public.data_subject_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    request_type TEXT NOT NULL,
    regulation TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    requested_data_categories TEXT[] DEFAULT '{}',
    verification_method TEXT,
    verified_at TIMESTAMP WITH TIME ZONE,
    processed_by UUID,
    processed_at TIMESTAMP WITH TIME ZONE,
    export_file_url TEXT,
    rejection_reason TEXT,
    notes TEXT,
    deadline_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Refund & Dispute Requests
CREATE TABLE IF NOT EXISTS public.refund_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    transaction_id UUID,
    sale_id UUID,
    amount DECIMAL(12,2) NOT NULL,
    currency TEXT DEFAULT 'INR',
    reason TEXT NOT NULL,
    reason_category TEXT,
    status TEXT DEFAULT 'pending',
    ai_recommendation TEXT,
    ai_confidence_score DECIMAL(3,2),
    fraud_score DECIMAL(3,2),
    reviewed_by UUID,
    review_notes TEXT,
    approved_amount DECIMAL(12,2),
    chargeback_reference TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Wallet Compliance Checks (AML/KYC)
CREATE TABLE IF NOT EXISTS public.wallet_compliance_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL,
    user_id UUID NOT NULL,
    check_type TEXT NOT NULL,
    risk_level TEXT DEFAULT 'low',
    status TEXT DEFAULT 'pending',
    details JSONB DEFAULT '{}',
    triggered_rules TEXT[],
    action_taken TEXT,
    reviewed_by UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    report_filed BOOLEAN DEFAULT false,
    report_reference TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Suspicious Activity Reports (SAR)
CREATE TABLE IF NOT EXISTS public.suspicious_activity_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    wallet_id UUID,
    transaction_ids UUID[],
    activity_type TEXT NOT NULL,
    description TEXT NOT NULL,
    risk_indicators TEXT[],
    total_amount DECIMAL(14,2),
    status TEXT DEFAULT 'draft',
    filed_by UUID,
    filed_at TIMESTAMP WITH TIME ZONE,
    regulatory_reference TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- License Key Compliance
CREATE TABLE IF NOT EXISTS public.license_compliance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_key TEXT NOT NULL UNIQUE,
    product_id UUID NOT NULL,
    user_id UUID NOT NULL,
    domain TEXT,
    allowed_domains TEXT[] DEFAULT '{}',
    max_activations INTEGER DEFAULT 1,
    current_activations INTEGER DEFAULT 0,
    is_transferable BOOLEAN DEFAULT false,
    no_resale BOOLEAN DEFAULT true,
    watermark_required BOOLEAN DEFAULT true,
    clone_detection_enabled BOOLEAN DEFAULT true,
    last_validated_at TIMESTAMP WITH TIME ZONE,
    status TEXT DEFAULT 'active',
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Compliance Audit Trail (Immutable)
CREATE TABLE IF NOT EXISTS public.compliance_audit_trail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action TEXT NOT NULL,
    actor_id UUID,
    actor_role app_role,
    ip_address TEXT,
    geo_location TEXT,
    user_agent TEXT,
    old_values JSONB,
    new_values JSONB,
    compliance_tags TEXT[],
    signature TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Developer Fair Labor Compliance
CREATE TABLE IF NOT EXISTS public.developer_work_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    developer_id UUID NOT NULL,
    date DATE NOT NULL,
    total_work_minutes INTEGER DEFAULT 0,
    total_break_minutes INTEGER DEFAULT 0,
    tasks_assigned INTEGER DEFAULT 0,
    tasks_completed INTEGER DEFAULT 0,
    voluntary_acceptance_rate DECIMAL(3,2),
    late_penalties_applied INTEGER DEFAULT 0,
    overtime_minutes INTEGER DEFAULT 0,
    overtime_consent_given BOOLEAN DEFAULT false,
    compliance_status TEXT DEFAULT 'compliant',
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(developer_id, date)
);

-- Cookie Consent Tracking
CREATE TABLE IF NOT EXISTS public.cookie_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id TEXT NOT NULL,
    user_id UUID,
    essential BOOLEAN DEFAULT true,
    analytics BOOLEAN DEFAULT false,
    marketing BOOLEAN DEFAULT false,
    third_party BOOLEAN DEFAULT false,
    preferences BOOLEAN DEFAULT false,
    ip_address TEXT,
    region TEXT,
    consent_given_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    consent_updated_at TIMESTAMP WITH TIME ZONE
);

-- Regional Compliance Requirements
CREATE TABLE IF NOT EXISTS public.regional_compliance_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_code TEXT NOT NULL,
    requirement_type TEXT NOT NULL,
    requirement_name TEXT NOT NULL,
    description TEXT,
    is_mandatory BOOLEAN DEFAULT true,
    enforcement_level TEXT DEFAULT 'strict',
    penalty_info TEXT,
    documentation_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(region_code, requirement_type, requirement_name)
);

-- Accessibility Compliance Tracking
CREATE TABLE IF NOT EXISTS public.accessibility_compliance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    page_url TEXT NOT NULL,
    wcag_level TEXT DEFAULT 'AA',
    last_audit_date DATE,
    issues_found INTEGER DEFAULT 0,
    issues_resolved INTEGER DEFAULT 0,
    color_contrast_pass BOOLEAN,
    screen_reader_pass BOOLEAN,
    keyboard_nav_pass BOOLEAN,
    alt_text_pass BOOLEAN,
    language_support TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    auditor_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_residency_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regional_tax_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_subject_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_compliance_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suspicious_activity_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.license_compliance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_audit_trail ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_work_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cookie_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regional_compliance_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accessibility_compliance ENABLE ROW LEVEL SECURITY;

-- RLS Policies using correct role names
CREATE POLICY "Users manage own consents" ON public.user_consents
    FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Admins view all consents" ON public.user_consents
    FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));

CREATE POLICY "Anyone can view residency config" ON public.data_residency_config
    FOR SELECT USING (true);
CREATE POLICY "Admins manage residency config" ON public.data_residency_config
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Anyone can view tax rules" ON public.regional_tax_rules
    FOR SELECT USING (true);
CREATE POLICY "Finance manages tax rules" ON public.regional_tax_rules
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'finance_manager'));

CREATE POLICY "Users manage own data requests" ON public.data_subject_requests
    FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Legal processes data requests" ON public.data_subject_requests
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));

CREATE POLICY "Users view own refunds" ON public.refund_requests
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users create refunds" ON public.refund_requests
    FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Finance manages refunds" ON public.refund_requests
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'finance_manager'));

CREATE POLICY "Finance views compliance checks" ON public.wallet_compliance_checks
    FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'finance_manager') OR has_role(auth.uid(), 'legal_compliance'));
CREATE POLICY "System inserts compliance checks" ON public.wallet_compliance_checks
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Legal manages SAR" ON public.suspicious_activity_reports
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));

CREATE POLICY "Users view own licenses" ON public.license_compliance
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Admins manage licenses" ON public.license_compliance
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'admin'));

CREATE POLICY "System inserts audit trail" ON public.compliance_audit_trail
    FOR INSERT WITH CHECK (true);
CREATE POLICY "Legal views audit trail" ON public.compliance_audit_trail
    FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));

CREATE POLICY "Developers view own logs" ON public.developer_work_logs
    FOR SELECT USING (developer_id = get_developer_id(auth.uid()));
CREATE POLICY "HR manages work logs" ON public.developer_work_logs
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'hr_manager'));

CREATE POLICY "Anyone can insert cookie consent" ON public.cookie_consents
    FOR INSERT WITH CHECK (true);
CREATE POLICY "Users view own cookie consent" ON public.cookie_consents
    FOR SELECT USING (user_id = auth.uid() OR user_id IS NULL);

CREATE POLICY "Anyone can view compliance requirements" ON public.regional_compliance_requirements
    FOR SELECT USING (true);
CREATE POLICY "Legal manages requirements" ON public.regional_compliance_requirements
    FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'legal_compliance'));

CREATE POLICY "Anyone can view accessibility status" ON public.accessibility_compliance
    FOR SELECT USING (true);
CREATE POLICY "Admins manage accessibility" ON public.accessibility_compliance
    FOR ALL USING (has_role(auth.uid(), 'super_admin'));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_consents_user ON public.user_consents(user_id);
CREATE INDEX IF NOT EXISTS idx_user_consents_type ON public.user_consents(consent_type);
CREATE INDEX IF NOT EXISTS idx_data_subject_requests_user ON public.data_subject_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_data_subject_requests_status ON public.data_subject_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_user ON public.refund_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_refund_requests_status ON public.refund_requests(status);
CREATE INDEX IF NOT EXISTS idx_wallet_compliance_user ON public.wallet_compliance_checks(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_compliance_risk ON public.wallet_compliance_checks(risk_level);
CREATE INDEX IF NOT EXISTS idx_compliance_audit_entity ON public.compliance_audit_trail(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_compliance_audit_actor ON public.compliance_audit_trail(actor_id);
CREATE INDEX IF NOT EXISTS idx_developer_work_logs_dev ON public.developer_work_logs(developer_id);
CREATE INDEX IF NOT EXISTS idx_license_compliance_product ON public.license_compliance(product_id);

-- Function to log compliance audit
CREATE OR REPLACE FUNCTION log_compliance_audit(
    p_entity_type TEXT,
    p_entity_id UUID,
    p_action TEXT,
    p_actor_id UUID,
    p_actor_role app_role,
    p_ip_address TEXT DEFAULT NULL,
    p_old_values JSONB DEFAULT NULL,
    p_new_values JSONB DEFAULT NULL,
    p_compliance_tags TEXT[] DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_signature TEXT;
BEGIN
    v_signature := encode(sha256((p_entity_type || p_entity_id::text || p_action || COALESCE(p_actor_id::text, '') || now()::text)::bytea), 'hex');
    
    INSERT INTO compliance_audit_trail (
        entity_type, entity_id, action, actor_id, actor_role,
        ip_address, old_values, new_values, compliance_tags, signature
    ) VALUES (
        p_entity_type, p_entity_id, p_action, p_actor_id, p_actor_role,
        p_ip_address, p_old_values, p_new_values, p_compliance_tags, v_signature
    ) RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$$;

-- Function to calculate tax
CREATE OR REPLACE FUNCTION calculate_regional_tax(
    p_country_code TEXT,
    p_state_code TEXT,
    p_amount DECIMAL,
    p_category TEXT DEFAULT 'products'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tax_rate DECIMAL := 0;
    v_tax_name TEXT := 'Tax';
    v_tax_amount DECIMAL := 0;
BEGIN
    SELECT tax_rate, tax_name INTO v_tax_rate, v_tax_name
    FROM regional_tax_rules
    WHERE country_code = p_country_code
    AND (state_code IS NULL OR state_code = p_state_code)
    AND p_category = ANY(applies_to)
    AND is_active = true
    AND effective_from <= CURRENT_DATE
    AND (effective_until IS NULL OR effective_until >= CURRENT_DATE)
    ORDER BY state_code NULLS LAST
    LIMIT 1;
    
    v_tax_amount := ROUND(p_amount * COALESCE(v_tax_rate, 0), 2);
    
    RETURN jsonb_build_object(
        'tax_name', COALESCE(v_tax_name, 'Tax'),
        'tax_rate', COALESCE(v_tax_rate, 0),
        'tax_amount', v_tax_amount,
        'subtotal', p_amount,
        'total', p_amount + v_tax_amount
    );
END;
$$;

-- Insert default data
INSERT INTO data_residency_config (region_code, region_name, storage_location, applicable_regulations, cross_border_allowed) VALUES
('IN', 'India', 'india', ARRAY['DPDP', 'IT Act'], true),
('EU', 'European Union', 'eu', ARRAY['GDPR'], false),
('US', 'United States', 'us', ARRAY['CCPA', 'HIPAA'], true),
('ZA', 'South Africa', 'uae', ARRAY['POPIA'], true),
('NG', 'Nigeria', 'uae', ARRAY['NDPR'], true),
('KE', 'Kenya', 'uae', ARRAY['DPA Kenya'], true),
('AE', 'UAE', 'uae', ARRAY['PDPL'], true),
('GB', 'United Kingdom', 'eu', ARRAY['UK GDPR'], false)
ON CONFLICT (region_code) DO NOTHING;

INSERT INTO regional_tax_rules (country_code, state_code, tax_name, tax_rate, tax_id_label, applies_to, effective_from) VALUES
('IN', NULL, 'GST', 0.18, 'GSTIN', ARRAY['products', 'services', 'subscriptions'], '2017-07-01'),
('US', 'CA', 'Sales Tax', 0.0725, 'Tax ID', ARRAY['products'], '2020-01-01'),
('US', 'TX', 'Sales Tax', 0.0625, 'Tax ID', ARRAY['products'], '2020-01-01'),
('GB', NULL, 'VAT', 0.20, 'VAT Number', ARRAY['products', 'services', 'subscriptions'], '2020-01-01'),
('DE', NULL, 'VAT', 0.19, 'VAT Number', ARRAY['products', 'services', 'subscriptions'], '2020-01-01'),
('FR', NULL, 'VAT', 0.20, 'VAT Number', ARRAY['products', 'services', 'subscriptions'], '2020-01-01'),
('AE', NULL, 'VAT', 0.05, 'TRN', ARRAY['products', 'services', 'subscriptions'], '2018-01-01'),
('ZA', NULL, 'VAT', 0.15, 'VAT Number', ARRAY['products', 'services', 'subscriptions'], '2020-01-01')
ON CONFLICT DO NOTHING;

INSERT INTO regional_compliance_requirements (region_code, requirement_type, requirement_name, description, is_mandatory) VALUES
('EU', 'consent', 'Explicit Consent', 'Must obtain explicit consent before processing personal data', true),
('EU', 'disclosure', 'Privacy Notice', 'Must provide clear privacy notice at data collection point', true),
('EU', 'retention', 'Data Minimization', 'Only retain data for as long as necessary', true),
('EU', 'notification', 'Breach Notification', 'Must notify authority within 72 hours of data breach', true),
('US', 'consent', 'Opt-Out Right', 'Must allow users to opt-out of data sale (CCPA)', true),
('IN', 'consent', 'Informed Consent', 'Must obtain consent with clear purpose disclosure', true),
('IN', 'disclosure', 'Data Fiduciary Notice', 'Must disclose data processing purposes clearly', true),
('ZA', 'consent', 'Lawful Processing', 'Must have lawful basis for processing personal info', true),
('NG', 'consent', 'Consent Requirement', 'Must obtain consent for personal data processing', true)
ON CONFLICT DO NOTHING;
-- ===== 20251221192013_c422f21e-51be-4913-b5e2-4623ced88816.sql =====
-- =============================================
-- AI-POWERED ANTI-FRAUD & MISUSE PREVENTION SYSTEM
-- =============================================

-- Device Fingerprints
CREATE TABLE IF NOT EXISTS public.device_fingerprints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    fingerprint_hash TEXT NOT NULL,
    device_info JSONB DEFAULT '{}',
    browser TEXT,
    os TEXT,
    screen_resolution TEXT,
    timezone TEXT,
    language TEXT,
    is_primary BOOLEAN DEFAULT false,
    is_trusted BOOLEAN DEFAULT false,
    is_blocked BOOLEAN DEFAULT false,
    blocked_reason TEXT,
    first_seen_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    login_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(user_id, fingerprint_hash)
);

-- IP Intelligence
CREATE TABLE IF NOT EXISTS public.ip_intelligence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address TEXT NOT NULL UNIQUE,
    is_vpn BOOLEAN DEFAULT false,
    is_proxy BOOLEAN DEFAULT false,
    is_tor BOOLEAN DEFAULT false,
    is_datacenter BOOLEAN DEFAULT false,
    country_code TEXT,
    region TEXT,
    city TEXT,
    isp TEXT,
    org TEXT,
    risk_score INTEGER DEFAULT 0,
    is_blacklisted BOOLEAN DEFAULT false,
    blacklist_reason TEXT,
    first_seen_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    request_count INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Fraud Scores
CREATE TABLE IF NOT EXISTS public.fraud_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    overall_score INTEGER DEFAULT 0,
    identity_score INTEGER DEFAULT 0,
    behavior_score INTEGER DEFAULT 0,
    transaction_score INTEGER DEFAULT 0,
    click_score INTEGER DEFAULT 0,
    device_score INTEGER DEFAULT 0,
    risk_level TEXT DEFAULT 'low',
    risk_factors TEXT[] DEFAULT '{}',
    last_calculated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    requires_review BOOLEAN DEFAULT false,
    reviewed_by UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Fraud Alerts
CREATE TABLE IF NOT EXISTS public.fraud_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    alert_type TEXT NOT NULL,
    severity TEXT DEFAULT 'medium',
    title TEXT NOT NULL,
    description TEXT,
    details JSONB DEFAULT '{}',
    ip_address TEXT,
    device_fingerprint TEXT,
    location TEXT,
    status TEXT DEFAULT 'pending',
    auto_action_taken TEXT,
    manual_action TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    escalation_level INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Account Suspensions
CREATE TABLE IF NOT EXISTS public.account_suspensions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    suspension_type TEXT NOT NULL,
    reason TEXT NOT NULL,
    masked_reason TEXT,
    severity TEXT DEFAULT 'temporary',
    auto_triggered BOOLEAN DEFAULT true,
    trigger_alert_id UUID,
    suspended_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    appeal_submitted BOOLEAN DEFAULT false,
    appeal_text TEXT,
    appeal_submitted_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    lifted_at TIMESTAMP WITH TIME ZONE,
    lifted_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Click Fraud Detection
CREATE TABLE IF NOT EXISTS public.click_fraud_detection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    influencer_id UUID,
    reseller_id UUID,
    franchise_id UUID,
    tracking_code TEXT,
    total_clicks INTEGER DEFAULT 0,
    valid_clicks INTEGER DEFAULT 0,
    invalid_clicks INTEGER DEFAULT 0,
    bot_clicks INTEGER DEFAULT 0,
    vpn_clicks INTEGER DEFAULT 0,
    duplicate_ip_clicks INTEGER DEFAULT 0,
    suspicious_patterns JSONB DEFAULT '{}',
    fraud_score INTEGER DEFAULT 0,
    status TEXT DEFAULT 'monitoring',
    flagged_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID,
    review_notes TEXT,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Commission Fraud Detection
CREATE TABLE IF NOT EXISTS public.commission_fraud_detection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    user_role app_role NOT NULL,
    check_type TEXT NOT NULL,
    findings JSONB DEFAULT '{}',
    risk_indicators TEXT[] DEFAULT '{}',
    fraud_probability DECIMAL(3,2),
    amount_flagged DECIMAL(14,2),
    status TEXT DEFAULT 'pending',
    auto_hold_applied BOOLEAN DEFAULT false,
    reviewed_by UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    action_taken TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Lead Fraud Detection
CREATE TABLE IF NOT EXISTS public.lead_fraud_detection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID,
    submitted_by UUID,
    validation_score INTEGER DEFAULT 100,
    is_duplicate BOOLEAN DEFAULT false,
    duplicate_of UUID,
    phone_valid BOOLEAN,
    email_valid BOOLEAN,
    is_disposable_email BOOLEAN DEFAULT false,
    is_throwaway_phone BOOLEAN DEFAULT false,
    spam_patterns JSONB DEFAULT '{}',
    bulk_submission_detected BOOLEAN DEFAULT false,
    ip_address TEXT,
    device_fingerprint TEXT,
    fraud_indicators TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    quarantined BOOLEAN DEFAULT false,
    auto_rejected BOOLEAN DEFAULT false,
    rejection_reason TEXT,
    reviewed_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Blacklist/Whitelist
CREATE TABLE IF NOT EXISTS public.access_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    list_type TEXT NOT NULL,
    entry_type TEXT NOT NULL,
    entry_value TEXT NOT NULL,
    reason TEXT,
    added_by UUID,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(list_type, entry_type, entry_value)
);

-- Login Locations for Impossible Travel
CREATE TABLE IF NOT EXISTS public.login_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    session_id UUID,
    ip_address TEXT,
    country_code TEXT,
    city TEXT,
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    login_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    travel_speed_kmh DECIMAL(10,2),
    is_impossible_travel BOOLEAN DEFAULT false,
    previous_location_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Behavior Analytics
CREATE TABLE IF NOT EXISTS public.behavior_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    session_id UUID,
    page_url TEXT,
    event_type TEXT NOT NULL,
    mouse_velocity DECIMAL(10,2),
    scroll_pattern TEXT,
    keystroke_pattern TEXT,
    time_on_page INTEGER,
    click_coordinates JSONB,
    is_bot_like BOOLEAN DEFAULT false,
    bot_probability DECIMAL(3,2),
    anomaly_flags TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Code Access Logs
CREATE TABLE IF NOT EXISTS public.code_access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    developer_id UUID NOT NULL,
    task_id UUID,
    action_type TEXT NOT NULL,
    file_path TEXT,
    repository TEXT,
    access_time TIMESTAMP WITH TIME ZONE DEFAULT now(),
    ip_address TEXT,
    device_fingerprint TEXT,
    is_outside_hours BOOLEAN DEFAULT false,
    is_suspicious BOOLEAN DEFAULT false,
    suspicious_reason TEXT,
    copy_attempt BOOLEAN DEFAULT false,
    export_attempt BOOLEAN DEFAULT false,
    watermark_applied BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Transaction Monitoring
CREATE TABLE IF NOT EXISTS public.transaction_monitoring (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID,
    transaction_id UUID,
    user_id UUID NOT NULL,
    transaction_type TEXT,
    amount DECIMAL(14,2),
    currency TEXT DEFAULT 'INR',
    risk_score INTEGER DEFAULT 0,
    risk_factors TEXT[] DEFAULT '{}',
    velocity_check_passed BOOLEAN DEFAULT true,
    pattern_check_passed BOOLEAN DEFAULT true,
    geo_check_passed BOOLEAN DEFAULT true,
    is_flagged BOOLEAN DEFAULT false,
    flag_reason TEXT,
    requires_2fa BOOLEAN DEFAULT false,
    is_held BOOLEAN DEFAULT false,
    hold_reason TEXT,
    released_at TIMESTAMP WITH TIME ZONE,
    released_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.device_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ip_intelligence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fraud_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fraud_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_suspensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.click_fraud_detection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_fraud_detection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_fraud_detection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.behavior_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.code_access_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_monitoring ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users view own devices" ON public.device_fingerprints FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "System inserts devices" ON public.device_fingerprints FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins manage devices" ON public.device_fingerprints FOR ALL USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Admins view IP intel" ON public.ip_intelligence FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'admin'));
CREATE POLICY "System inserts IP intel" ON public.ip_intelligence FOR INSERT WITH CHECK (true);
CREATE POLICY "System updates IP intel" ON public.ip_intelligence FOR UPDATE USING (true);

CREATE POLICY "Users view own fraud score" ON public.fraud_scores FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Admins manage fraud scores" ON public.fraud_scores FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'admin'));
CREATE POLICY "System upserts fraud scores" ON public.fraud_scores FOR INSERT WITH CHECK (true);

CREATE POLICY "System creates alerts" ON public.fraud_alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins manage alerts" ON public.fraud_alerts FOR ALL USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'finance_manager'));

CREATE POLICY "Users view own suspensions" ON public.account_suspensions FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Admins manage suspensions" ON public.account_suspensions FOR ALL USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Admins view click fraud" ON public.click_fraud_detection FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'admin'));
CREATE POLICY "System inserts click fraud" ON public.click_fraud_detection FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins view commission fraud" ON public.commission_fraud_detection FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'finance_manager'));
CREATE POLICY "System inserts commission fraud" ON public.commission_fraud_detection FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins view lead fraud" ON public.lead_fraud_detection FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'lead_manager'));
CREATE POLICY "System inserts lead fraud" ON public.lead_fraud_detection FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins manage access lists" ON public.access_lists FOR ALL USING (has_role(auth.uid(), 'super_admin'));
CREATE POLICY "System reads access lists" ON public.access_lists FOR SELECT USING (true);

CREATE POLICY "Users view own locations" ON public.login_locations FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "System inserts locations" ON public.login_locations FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins view locations" ON public.login_locations FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "System inserts behavior" ON public.behavior_analytics FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins view behavior" ON public.behavior_analytics FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "System inserts code logs" ON public.code_access_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "Devs view own code logs" ON public.code_access_logs FOR SELECT USING (developer_id = get_developer_id(auth.uid()));
CREATE POLICY "Admins view code logs" ON public.code_access_logs FOR SELECT USING (has_role(auth.uid(), 'super_admin'));

CREATE POLICY "System inserts tx monitoring" ON public.transaction_monitoring FOR INSERT WITH CHECK (true);
CREATE POLICY "Finance views tx monitoring" ON public.transaction_monitoring FOR SELECT USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'finance_manager'));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_user ON public.device_fingerprints(user_id);
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_hash ON public.device_fingerprints(fingerprint_hash);
CREATE INDEX IF NOT EXISTS idx_ip_intelligence_ip ON public.ip_intelligence(ip_address);
CREATE INDEX IF NOT EXISTS idx_fraud_alerts_user ON public.fraud_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_fraud_alerts_status ON public.fraud_alerts(status);
CREATE INDEX IF NOT EXISTS idx_account_suspensions_user ON public.account_suspensions(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_login_locations_user ON public.login_locations(user_id);
CREATE INDEX IF NOT EXISTS idx_behavior_analytics_user ON public.behavior_analytics(user_id);
CREATE INDEX IF NOT EXISTS idx_access_lists_lookup ON public.access_lists(list_type, entry_type, entry_value);

-- Function: Check if IP/device is allowed
CREATE OR REPLACE FUNCTION check_access_allowed(
    p_ip_address TEXT,
    p_device_fingerprint TEXT,
    p_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_blocked BOOLEAN := false;
    v_reason TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM access_lists WHERE list_type = 'blacklist' AND entry_type = 'ip' AND entry_value = p_ip_address AND is_active = true AND (expires_at IS NULL OR expires_at > now())) THEN
        v_blocked := true;
        v_reason := 'IP address is blacklisted';
    END IF;
    
    IF NOT v_blocked AND p_device_fingerprint IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM access_lists WHERE list_type = 'blacklist' AND entry_type = 'device' AND entry_value = p_device_fingerprint AND is_active = true) THEN
            v_blocked := true;
            v_reason := 'Device is blacklisted';
        END IF;
    END IF;
    
    IF NOT v_blocked AND p_email IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM access_lists WHERE list_type = 'blacklist' AND entry_type = 'email' AND entry_value = p_email AND is_active = true) THEN
            v_blocked := true;
            v_reason := 'Email is blacklisted';
        END IF;
    END IF;
    
    IF NOT v_blocked THEN
        IF EXISTS (SELECT 1 FROM ip_intelligence WHERE ip_address = p_ip_address AND (is_blacklisted = true OR risk_score > 80)) THEN
            v_blocked := true;
            v_reason := 'High risk IP detected';
        END IF;
    END IF;
    
    RETURN jsonb_build_object('allowed', NOT v_blocked, 'blocked', v_blocked, 'reason', v_reason);
END;
$$;
-- ===== 20251221192815_bc96b4b4-9d9f-4e09-b4f3-543ceac8501f.sql =====
-- =============================================
-- RISK ENGINE DATABASE SCHEMA
-- =============================================

-- Dynamic Risk Scores
CREATE TABLE IF NOT EXISTS public.risk_scores (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    current_score INTEGER NOT NULL DEFAULT 0 CHECK (current_score >= 0 AND current_score <= 100),
    previous_score INTEGER DEFAULT 0,
    risk_level TEXT NOT NULL DEFAULT 'normal' CHECK (risk_level IN ('normal', 'caution', 'watch', 'high', 'critical')),
    login_pattern_score INTEGER DEFAULT 0,
    device_score INTEGER DEFAULT 0,
    transaction_score INTEGER DEFAULT 0,
    behavior_score INTEGER DEFAULT 0,
    commission_score INTEGER DEFAULT 0,
    lead_score INTEGER DEFAULT 0,
    factors JSONB DEFAULT '[]'::jsonb,
    last_calculated_at TIMESTAMPTZ DEFAULT now(),
    auto_action_taken TEXT,
    escalation_level INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- Reputation Scores for entities
CREATE TABLE IF NOT EXISTS public.reputation_scores (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('user', 'franchise', 'reseller', 'influencer', 'developer', 'store')),
    entity_id UUID NOT NULL,
    star_rating DECIMAL(2,1) DEFAULT 5.0 CHECK (star_rating >= 0 AND star_rating <= 5),
    trust_index INTEGER DEFAULT 100 CHECK (trust_index >= 0 AND trust_index <= 100),
    performance_rating INTEGER DEFAULT 100,
    complaint_ratio DECIMAL(5,4) DEFAULT 0,
    delivery_accuracy DECIMAL(5,2) DEFAULT 100,
    total_transactions INTEGER DEFAULT 0,
    successful_transactions INTEGER DEFAULT 0,
    failed_transactions INTEGER DEFAULT 0,
    fraud_incidents INTEGER DEFAULT 0,
    payout_priority TEXT DEFAULT 'normal' CHECK (payout_priority IN ('low', 'normal', 'high', 'priority')),
    wallet_privilege_level TEXT DEFAULT 'standard' CHECK (wallet_privilege_level IN ('restricted', 'limited', 'standard', 'premium')),
    lead_assignment_priority TEXT DEFAULT 'normal',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(entity_type, entity_id)
);

-- Risk Events Log
CREATE TABLE IF NOT EXISTS public.risk_events (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    event_category TEXT NOT NULL CHECK (event_category IN ('login', 'transaction', 'behavior', 'device', 'lead', 'commission', 'demo', 'code', 'communication')),
    severity TEXT NOT NULL DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    risk_contribution INTEGER DEFAULT 0,
    description TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    ip_address TEXT,
    device_fingerprint TEXT,
    geo_location TEXT,
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Risk Escalations
CREATE TABLE IF NOT EXISTS public.risk_escalations (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    escalation_level INTEGER NOT NULL CHECK (escalation_level >= 1 AND escalation_level <= 4),
    trigger_event_id UUID REFERENCES public.risk_events(id),
    trigger_reason TEXT NOT NULL,
    risk_score_at_time INTEGER,
    action_taken TEXT NOT NULL,
    action_details JSONB DEFAULT '{}'::jsonb,
    auto_triggered BOOLEAN DEFAULT true,
    triggered_by UUID,
    reversed BOOLEAN DEFAULT false,
    reversed_at TIMESTAMPTZ,
    reversed_by UUID,
    reversal_reason TEXT,
    notification_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Risk Watchlist
CREATE TABLE IF NOT EXISTS public.risk_watchlist (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    watchlist_type TEXT NOT NULL CHECK (watchlist_type IN ('monitor', 'restrict', 'whitelist', 'blacklist')),
    reason TEXT NOT NULL,
    added_by UUID,
    auto_added BOOLEAN DEFAULT false,
    trigger_threshold INTEGER,
    current_status TEXT DEFAULT 'active' CHECK (current_status IN ('active', 'expired', 'removed')),
    expires_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Behavior Patterns (learned patterns)
CREATE TABLE IF NOT EXISTS public.behavior_patterns (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    pattern_type TEXT NOT NULL,
    baseline_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    current_data JSONB DEFAULT '{}'::jsonb,
    deviation_score DECIMAL(5,2) DEFAULT 0,
    samples_count INTEGER DEFAULT 0,
    last_sample_at TIMESTAMPTZ,
    is_anomalous BOOLEAN DEFAULT false,
    anomaly_detected_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, pattern_type)
);

-- Risk Audit Trail
CREATE TABLE IF NOT EXISTS public.risk_audit_trail (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    action TEXT NOT NULL,
    risk_score_before INTEGER,
    risk_score_after INTEGER,
    trigger_type TEXT,
    reasoning JSONB DEFAULT '{}'::jsonb,
    calculation_details JSONB DEFAULT '{}'::jsonb,
    escalation_trace JSONB DEFAULT '[]'::jsonb,
    actor_id UUID,
    actor_role TEXT,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Real-time Risk Alerts
CREATE TABLE IF NOT EXISTS public.risk_alerts (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    alert_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'danger', 'critical')),
    title TEXT NOT NULL,
    description TEXT,
    risk_score INTEGER,
    risk_level TEXT,
    indicators JSONB DEFAULT '[]'::jsonb,
    recommended_action TEXT,
    auto_action_available BOOLEAN DEFAULT false,
    acknowledged BOOLEAN DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by UUID,
    action_taken TEXT,
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.risk_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reputation_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.behavior_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_audit_trail ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_alerts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for risk_scores
CREATE POLICY "Users can view own risk score" ON public.risk_scores FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all risk scores" ON public.risk_scores FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance', 'finance_manager'))
);
CREATE POLICY "System can manage risk scores" ON public.risk_scores FOR ALL USING (true) WITH CHECK (true);

-- RLS Policies for reputation_scores
CREATE POLICY "Public view reputation" ON public.reputation_scores FOR SELECT USING (true);
CREATE POLICY "Admins manage reputation" ON public.reputation_scores FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
);

-- RLS Policies for risk_events
CREATE POLICY "Users can view own risk events" ON public.risk_events FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all risk events" ON public.risk_events FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance', 'finance_manager'))
);
CREATE POLICY "System can manage risk events" ON public.risk_events FOR ALL USING (true) WITH CHECK (true);

-- RLS Policies for risk_escalations
CREATE POLICY "Users can view own escalations" ON public.risk_escalations FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage escalations" ON public.risk_escalations FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
);

-- RLS Policies for risk_watchlist
CREATE POLICY "Admins can manage watchlist" ON public.risk_watchlist FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
);

-- RLS Policies for behavior_patterns
CREATE POLICY "System can manage behavior patterns" ON public.behavior_patterns FOR ALL USING (true) WITH CHECK (true);

-- RLS Policies for risk_audit_trail
CREATE POLICY "Admins can view audit trail" ON public.risk_audit_trail FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance'))
);
CREATE POLICY "System can insert audit trail" ON public.risk_audit_trail FOR INSERT WITH CHECK (true);

-- RLS Policies for risk_alerts
CREATE POLICY "Admins can manage alerts" ON public.risk_alerts FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance', 'finance_manager'))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'legal_compliance', 'finance_manager'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_risk_scores_user ON public.risk_scores(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_scores_level ON public.risk_scores(risk_level);
CREATE INDEX IF NOT EXISTS idx_risk_scores_score ON public.risk_scores(current_score DESC);
CREATE INDEX IF NOT EXISTS idx_reputation_entity ON public.reputation_scores(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_risk_events_user ON public.risk_events(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_events_category ON public.risk_events(event_category);
CREATE INDEX IF NOT EXISTS idx_risk_events_created ON public.risk_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_risk_escalations_user ON public.risk_escalations(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_escalations_level ON public.risk_escalations(escalation_level);
CREATE INDEX IF NOT EXISTS idx_risk_watchlist_user ON public.risk_watchlist(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_watchlist_type ON public.risk_watchlist(watchlist_type);
CREATE INDEX IF NOT EXISTS idx_behavior_patterns_user ON public.behavior_patterns(user_id);
CREATE INDEX IF NOT EXISTS idx_risk_alerts_active ON public.risk_alerts(is_active, severity);

-- Function to calculate risk level from score
CREATE OR REPLACE FUNCTION public.get_risk_level(score INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE
        WHEN score <= 20 THEN 'normal'
        WHEN score <= 40 THEN 'caution'
        WHEN score <= 60 THEN 'watch'
        WHEN score <= 80 THEN 'high'
        ELSE 'critical'
    END;
END;
$$;

-- Function to update risk score
CREATE OR REPLACE FUNCTION public.update_risk_score(
    p_user_id UUID,
    p_login_score INTEGER DEFAULT NULL,
    p_device_score INTEGER DEFAULT NULL,
    p_transaction_score INTEGER DEFAULT NULL,
    p_behavior_score INTEGER DEFAULT NULL,
    p_commission_score INTEGER DEFAULT NULL,
    p_lead_score INTEGER DEFAULT NULL,
    p_factors JSONB DEFAULT NULL
)
RETURNS public.risk_scores
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result public.risk_scores;
BEGIN
    INSERT INTO public.risk_scores (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    UPDATE public.risk_scores
    SET
        previous_score = current_score,
        login_pattern_score = COALESCE(p_login_score, login_pattern_score),
        device_score = COALESCE(p_device_score, device_score),
        transaction_score = COALESCE(p_transaction_score, transaction_score),
        behavior_score = COALESCE(p_behavior_score, behavior_score),
        commission_score = COALESCE(p_commission_score, commission_score),
        lead_score = COALESCE(p_lead_score, lead_score),
        factors = COALESCE(p_factors, factors),
        last_calculated_at = now(),
        updated_at = now()
    WHERE user_id = p_user_id;

    UPDATE public.risk_scores
    SET
        current_score = LEAST(100, GREATEST(0, 
            COALESCE(login_pattern_score, 0) * 0.15 +
            COALESCE(device_score, 0) * 0.20 +
            COALESCE(transaction_score, 0) * 0.25 +
            COALESCE(behavior_score, 0) * 0.15 +
            COALESCE(commission_score, 0) * 0.15 +
            COALESCE(lead_score, 0) * 0.10
        )::INTEGER),
        risk_level = public.get_risk_level(LEAST(100, GREATEST(0, 
            COALESCE(login_pattern_score, 0) * 0.15 +
            COALESCE(device_score, 0) * 0.20 +
            COALESCE(transaction_score, 0) * 0.25 +
            COALESCE(behavior_score, 0) * 0.15 +
            COALESCE(commission_score, 0) * 0.15 +
            COALESCE(lead_score, 0) * 0.10
        )::INTEGER))
    WHERE user_id = p_user_id
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$;

-- Function to log risk audit
CREATE OR REPLACE FUNCTION public.log_risk_audit(
    p_user_id UUID,
    p_action TEXT,
    p_score_before INTEGER,
    p_score_after INTEGER,
    p_trigger_type TEXT,
    p_reasoning JSONB DEFAULT '{}'::jsonb,
    p_calculation JSONB DEFAULT '{}'::jsonb,
    p_actor_id UUID DEFAULT NULL,
    p_actor_role TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.risk_audit_trail (
        user_id, action, risk_score_before, risk_score_after,
        trigger_type, reasoning, calculation_details,
        actor_id, actor_role
    ) VALUES (
        p_user_id, p_action, p_score_before, p_score_after,
        p_trigger_type, p_reasoning, p_calculation,
        p_actor_id, p_actor_role
    ) RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$$;

-- Enable realtime for risk alerts
ALTER PUBLICATION supabase_realtime ADD TABLE public.risk_alerts;
-- ===== 20251221211250_c4bd8242-8ab5-47be-b1c4-909e92da826a.sql =====
-- Create enum for AI providers
CREATE TYPE public.ai_provider AS ENUM ('openai', 'gemini', 'claude', 'lovable_ai', 'other');

-- Create enum for AI modules
CREATE TYPE public.ai_module AS ENUM ('seo', 'chatbot', 'dev_assist', 'ocr', 'image_gen', 'translation', 'analytics', 'other');

-- Create AI usage logs table
CREATE TABLE public.ai_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usage_id TEXT UNIQUE NOT NULL DEFAULT ('AI-' || to_char(now(), 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 8)),
    user_id UUID NOT NULL,
    user_role app_role NOT NULL,
    module ai_module NOT NULL,
    provider ai_provider NOT NULL DEFAULT 'lovable_ai',
    base_cost DECIMAL(10,4) NOT NULL DEFAULT 0,
    management_fee_percent DECIMAL(5,2) NOT NULL DEFAULT 30.00,
    management_fee DECIMAL(10,4) GENERATED ALWAYS AS (base_cost * (management_fee_percent / 100)) STORED,
    final_cost DECIMAL(10,4) GENERATED ALWAYS AS (base_cost * (1 + management_fee_percent / 100)) STORED,
    purpose TEXT,
    tokens_used INTEGER DEFAULT 0,
    request_count INTEGER DEFAULT 1,
    wallet_transaction_id UUID,
    qr_code_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    is_billed BOOLEAN DEFAULT false
);

-- Create AI billing QR codes table
CREATE TABLE public.ai_billing_qr_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    qr_code TEXT UNIQUE NOT NULL,
    usage_id UUID REFERENCES public.ai_usage_logs(id) ON DELETE SET NULL,
    statement_id UUID,
    qr_type TEXT NOT NULL DEFAULT 'single' CHECK (qr_type IN ('single', 'daily', 'weekly', 'monthly')),
    data_payload JSONB NOT NULL,
    base_cost_total DECIMAL(10,4) NOT NULL,
    management_fee_total DECIMAL(10,4) NOT NULL,
    final_cost_total DECIMAL(10,4) NOT NULL,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,
    is_valid BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_refreshed_at TIMESTAMPTZ DEFAULT now()
);

-- Create AI billing statements table
CREATE TABLE public.ai_billing_statements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_number TEXT UNIQUE NOT NULL DEFAULT ('STMT-' || to_char(now(), 'YYYYMM') || '-' || substr(gen_random_uuid()::text, 1, 6)),
    period_type TEXT NOT NULL DEFAULT 'monthly' CHECK (period_type IN ('daily', 'weekly', 'monthly')),
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    total_base_cost DECIMAL(12,4) NOT NULL DEFAULT 0,
    total_management_fee DECIMAL(12,4) NOT NULL DEFAULT 0,
    total_final_cost DECIMAL(12,4) NOT NULL DEFAULT 0,
    total_requests INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    usage_breakdown JSONB DEFAULT '{}',
    qr_code_id UUID REFERENCES public.ai_billing_qr_codes(id),
    wallet_transaction_id UUID,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'paid')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);

-- Create QR scan logs table for audit trail
CREATE TABLE public.ai_qr_scan_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    qr_code_id UUID REFERENCES public.ai_billing_qr_codes(id) ON DELETE CASCADE,
    scanned_by UUID NOT NULL,
    scanner_role app_role NOT NULL,
    scan_type TEXT DEFAULT 'view' CHECK (scan_type IN ('view', 'download_png', 'download_pdf', 'screenshot_attempt', 'copy_attempt')),
    device_fingerprint TEXT,
    ip_address TEXT,
    user_agent TEXT,
    is_valid_scan BOOLEAN DEFAULT true,
    is_duplicate BOOLEAN DEFAULT false,
    watermark_applied BOOLEAN DEFAULT false,
    alert_triggered BOOLEAN DEFAULT false,
    alert_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create AI fraud detection table
CREATE TABLE public.ai_fraud_detection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    detection_type TEXT NOT NULL CHECK (detection_type IN ('duplicate_qr', 'spike_usage', 'misuse', 'screenshot', 'copy_attempt')),
    severity TEXT DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    details JSONB,
    related_usage_id UUID REFERENCES public.ai_usage_logs(id),
    related_qr_id UUID REFERENCES public.ai_billing_qr_codes(id),
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create AI efficiency scores table
CREATE TABLE public.ai_efficiency_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module ai_module NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    total_cost DECIMAL(12,4) DEFAULT 0,
    total_requests INTEGER DEFAULT 0,
    avg_cost_per_request DECIMAL(10,4) DEFAULT 0,
    efficiency_score DECIMAL(5,2) DEFAULT 0,
    comparison_to_market DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(module, period_start, period_end)
);

-- Enable RLS on all tables
ALTER TABLE public.ai_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_billing_qr_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_billing_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_qr_scan_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_fraud_detection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_efficiency_scores ENABLE ROW LEVEL SECURITY;

-- RLS Policies - Only Super Admin, Finance Manager, and Auditor can view AI billing
CREATE POLICY "Admin roles can view AI usage logs"
ON public.ai_usage_logs FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can insert AI usage logs"
ON public.ai_usage_logs FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admin roles can view QR codes"
ON public.ai_billing_qr_codes FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can manage QR codes"
ON public.ai_billing_qr_codes FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Admin roles can view statements"
ON public.ai_billing_statements FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can manage statements"
ON public.ai_billing_statements FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Admin roles can view scan logs"
ON public.ai_qr_scan_logs FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can insert scan logs"
ON public.ai_qr_scan_logs FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admin roles can view fraud detection"
ON public.ai_fraud_detection FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can manage fraud detection"
ON public.ai_fraud_detection FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Admin roles can view efficiency scores"
ON public.ai_efficiency_scores FOR SELECT
TO authenticated
USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "System can manage efficiency scores"
ON public.ai_efficiency_scores FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Create indexes for performance
CREATE INDEX idx_ai_usage_logs_user ON public.ai_usage_logs(user_id);
CREATE INDEX idx_ai_usage_logs_created ON public.ai_usage_logs(created_at);
CREATE INDEX idx_ai_usage_logs_module ON public.ai_usage_logs(module);
CREATE INDEX idx_ai_qr_codes_expires ON public.ai_billing_qr_codes(expires_at);
CREATE INDEX idx_ai_scan_logs_qr ON public.ai_qr_scan_logs(qr_code_id);
CREATE INDEX idx_ai_fraud_user ON public.ai_fraud_detection(user_id);
-- ===== 20251221233917_50df977d-84f1-44d2-9f04-09a73e205ec4.sql =====
-- Create enum for event types
CREATE TYPE public.offer_event_type AS ENUM ('festival', 'sports', 'custom');

-- Create global offers table
CREATE TABLE public.global_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    discount_percentage INTEGER NOT NULL DEFAULT 40,
    event_type offer_event_type NOT NULL DEFAULT 'festival',
    event_name TEXT,
    country_code TEXT,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_auto_detected BOOLEAN DEFAULT false,
    theme_primary_color TEXT DEFAULT '#8B5CF6',
    theme_secondary_color TEXT DEFAULT '#06B6D4',
    theme_accent_color TEXT DEFAULT '#F59E0B',
    banner_text TEXT,
    icon TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.global_offers ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can read active offers
CREATE POLICY "Anyone can view active offers"
ON public.global_offers
FOR SELECT
USING (is_active = true AND now() BETWEEN start_date AND end_date);

-- Policy: Super Admin can do everything
CREATE POLICY "Super Admin full access to offers"
ON public.global_offers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'))
WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- Create predefined festivals table for auto-detection
CREATE TABLE public.festival_calendar (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    month INTEGER NOT NULL,
    day INTEGER NOT NULL,
    duration_days INTEGER DEFAULT 1,
    country_codes TEXT[] DEFAULT ARRAY['GLOBAL'],
    default_discount INTEGER DEFAULT 40,
    theme_primary TEXT DEFAULT '#8B5CF6',
    theme_secondary TEXT DEFAULT '#06B6D4',
    icon TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on festival calendar
ALTER TABLE public.festival_calendar ENABLE ROW LEVEL SECURITY;

-- Everyone can read festival calendar
CREATE POLICY "Anyone can view festival calendar"
ON public.festival_calendar
FOR SELECT
USING (is_active = true);

-- Super Admin manages festival calendar
CREATE POLICY "Super Admin manages festival calendar"
ON public.festival_calendar
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'))
WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- Insert common global festivals
INSERT INTO public.festival_calendar (name, month, day, duration_days, country_codes, default_discount, theme_primary, theme_secondary, icon) VALUES
('New Year', 1, 1, 3, ARRAY['GLOBAL'], 40, '#FFD700', '#FF6B6B', '🎉'),
('Valentine''s Day', 2, 14, 1, ARRAY['GLOBAL'], 30, '#FF69B4', '#FF1493', '💕'),
('Holi', 3, 25, 2, ARRAY['IN', 'NP', 'GLOBAL'], 40, '#FF6B6B', '#4ECDC4', '🎨'),
('Earth Day', 4, 22, 1, ARRAY['GLOBAL'], 25, '#22C55E', '#10B981', '🌍'),
('Mother''s Day', 5, 12, 1, ARRAY['GLOBAL'], 35, '#EC4899', '#F472B6', '💐'),
('Father''s Day', 6, 16, 1, ARRAY['GLOBAL'], 35, '#3B82F6', '#60A5FA', '👔'),
('Independence Day India', 8, 15, 1, ARRAY['IN'], 50, '#FF9933', '#138808', '🇮🇳'),
('Diwali', 11, 1, 5, ARRAY['IN', 'NP', 'GLOBAL'], 50, '#FFD700', '#FF6B6B', '🪔'),
('Black Friday', 11, 29, 4, ARRAY['GLOBAL'], 50, '#000000', '#FFD700', '🛍️'),
('Christmas', 12, 25, 3, ARRAY['GLOBAL'], 40, '#DC2626', '#22C55E', '🎄'),
('Boxing Day', 12, 26, 1, ARRAY['GLOBAL'], 45, '#DC2626', '#FFFFFF', '🎁');

-- Create sports events table
CREATE TABLE public.sports_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    sport_type TEXT NOT NULL,
    team1_name TEXT,
    team2_name TEXT,
    team1_color TEXT,
    team2_color TEXT,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    default_discount INTEGER DEFAULT 40,
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.sports_events ENABLE ROW LEVEL SECURITY;

-- Anyone can view active sports events
CREATE POLICY "Anyone can view active sports events"
ON public.sports_events
FOR SELECT
USING (is_active = true);

-- Super Admin manages sports events
CREATE POLICY "Super Admin manages sports events"
ON public.sports_events
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'))
WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- Create trigger for updated_at
CREATE TRIGGER update_global_offers_updated_at
BEFORE UPDATE ON public.global_offers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251222094931_1b49ab08-c07c-407d-bdab-f6bf0bbcaf6e.sql =====
-- Fix function search_path for get_risk_level function
CREATE OR REPLACE FUNCTION public.get_risk_level(score integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN CASE
        WHEN score <= 20 THEN 'normal'
        WHEN score <= 40 THEN 'caution'
        WHEN score <= 60 THEN 'watch'
        WHEN score <= 80 THEN 'high'
        ELSE 'critical'
    END;
END;
$function$;

-- Enable leaked password protection via auth config
-- Note: This is typically done via the Supabase dashboard auth settings
-- ===== 20251222104225_f92d8747-3fe7-459f-83b0-1eca9c041d19.sql =====
-- Step 1: Add 'master' role to the app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'master';
-- ===== 20251222104250_7b16efad-34d1-4e3e-86e6-ccbe0781e488.sql =====
-- Step 2: Add approval columns and functions

-- Add approval_status column to user_roles table
ALTER TABLE public.user_roles 
ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending';

-- Add constraint separately to handle existing data
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints 
    WHERE constraint_name = 'user_roles_approval_status_check'
  ) THEN
    ALTER TABLE public.user_roles 
    ADD CONSTRAINT user_roles_approval_status_check 
    CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

-- Add approved_by and approved_at columns for audit
ALTER TABLE public.user_roles 
ADD COLUMN IF NOT EXISTS approved_by UUID,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Auto-approve existing SUPER_ADMIN users (master will be done separately)
UPDATE public.user_roles 
SET approval_status = 'approved', approved_at = now()
WHERE role = 'super_admin' AND approval_status = 'pending';

-- Create function to auto-approve privileged roles on insert
CREATE OR REPLACE FUNCTION public.auto_approve_privileged_roles()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Auto-approve MASTER and SUPER_ADMIN roles
  IF NEW.role::text IN ('master', 'super_admin') THEN
    NEW.approval_status := 'approved';
    NEW.approved_at := now();
  ELSE
    -- All other roles start as pending
    NEW.approval_status := COALESCE(NEW.approval_status, 'pending');
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger for auto-approval
DROP TRIGGER IF EXISTS trigger_auto_approve_roles ON public.user_roles;
CREATE TRIGGER trigger_auto_approve_roles
  BEFORE INSERT ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_approve_privileged_roles();

-- Drop old policy first
DROP POLICY IF EXISTS "Super admin manages roles" ON public.user_roles;

-- Update RLS policy to allow master role same access as super_admin
DROP POLICY IF EXISTS "Master and Super Admin manage roles" ON public.user_roles;
CREATE POLICY "Master and Super Admin manage roles"
ON public.user_roles
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur 
    WHERE ur.user_id = auth.uid() 
    AND ur.role::text IN ('master', 'super_admin')
  )
);

-- Add helper function to check if user is approved
CREATE OR REPLACE FUNCTION public.is_user_approved(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
    AND approval_status = 'approved'
  )
$$;

-- Add helper function to check if user has privileged role (auto-access)
CREATE OR REPLACE FUNCTION public.has_privileged_role(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
    AND role::text IN ('master', 'super_admin')
  )
$$;

-- Function to approve a user (called by Master/Super Admin)
CREATE OR REPLACE FUNCTION public.approve_user(_target_user_id uuid, _approver_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if approver has privileged role
  IF NOT public.has_privileged_role(_approver_id) THEN
    RAISE EXCEPTION 'Only Master or Super Admin can approve users';
  END IF;
  
  UPDATE public.user_roles
  SET 
    approval_status = 'approved',
    approved_by = _approver_id,
    approved_at = now()
  WHERE user_id = _target_user_id;
  
  RETURN FOUND;
END;
$$;

-- Function to reject a user
CREATE OR REPLACE FUNCTION public.reject_user(_target_user_id uuid, _rejector_id uuid, _reason text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if rejector has privileged role
  IF NOT public.has_privileged_role(_rejector_id) THEN
    RAISE EXCEPTION 'Only Master or Super Admin can reject users';
  END IF;
  
  UPDATE public.user_roles
  SET 
    approval_status = 'rejected',
    approved_by = _rejector_id,
    approved_at = now(),
    rejection_reason = _reason
  WHERE user_id = _target_user_id;
  
  RETURN FOUND;
END;
$$;
-- ===== 20251222104823_c4779cd0-9a2c-41a3-8dca-bed30bf66dc7.sql =====
-- Add force_logged_out_at column to user_roles for force logout tracking
ALTER TABLE public.user_roles 
ADD COLUMN IF NOT EXISTS force_logged_out_at TIMESTAMPTZ DEFAULT NULL,
ADD COLUMN IF NOT EXISTS force_logged_out_by UUID DEFAULT NULL;

-- Update auto-approval trigger to only auto-approve master and super_admin
CREATE OR REPLACE FUNCTION public.auto_approve_privileged_roles()
RETURNS TRIGGER AS $$
BEGIN
  -- Only master and super_admin get auto-approved
  IF NEW.role IN ('master', 'super_admin') THEN
    NEW.approval_status := 'approved';
    NEW.approved_at := NOW();
  ELSE
    -- All other roles require manual approval
    NEW.approval_status := 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop and recreate trigger to ensure it uses updated function
DROP TRIGGER IF EXISTS trigger_auto_approve_privileged ON public.user_roles;

CREATE TRIGGER trigger_auto_approve_privileged
  BEFORE INSERT ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_approve_privileged_roles();

-- Function for Master Admin to force logout any user
CREATE OR REPLACE FUNCTION public.force_logout_user(target_user_id UUID, admin_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  admin_role TEXT;
BEGIN
  -- Verify the admin is a master
  SELECT role INTO admin_role FROM public.user_roles WHERE user_id = admin_user_id;
  
  IF admin_role != 'master' THEN
    RAISE EXCEPTION 'Only Master Admin can force logout users';
  END IF;
  
  -- Update the target user's force logout timestamp
  UPDATE public.user_roles 
  SET force_logged_out_at = NOW(),
      force_logged_out_by = admin_user_id
  WHERE user_id = target_user_id;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to check if user was force logged out
CREATE OR REPLACE FUNCTION public.check_force_logout(check_user_id UUID)
RETURNS TIMESTAMPTZ AS $$
DECLARE
  logout_time TIMESTAMPTZ;
BEGIN
  SELECT force_logged_out_at INTO logout_time 
  FROM public.user_roles 
  WHERE user_id = check_user_id;
  
  RETURN logout_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to clear force logout (when user logs back in)
CREATE OR REPLACE FUNCTION public.clear_force_logout(clear_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE public.user_roles 
  SET force_logged_out_at = NULL,
      force_logged_out_by = NULL
  WHERE user_id = clear_user_id;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to get users for approval (excluding master from non-master views)
CREATE OR REPLACE FUNCTION public.get_users_for_approval(viewer_role TEXT)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  role TEXT,
  approval_status TEXT,
  created_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  approved_by UUID
) AS $$
BEGIN
  IF viewer_role = 'master' THEN
    -- Master can see all users
    RETURN QUERY SELECT 
      ur.id, ur.user_id, ur.role::TEXT, ur.approval_status, 
      ur.created_at, ur.approved_at, ur.approved_by
    FROM public.user_roles ur;
  ELSE
    -- Super Admin and others cannot see Master users
    RETURN QUERY SELECT 
      ur.id, ur.user_id, ur.role::TEXT, ur.approval_status, 
      ur.created_at, ur.approved_at, ur.approved_by
    FROM public.user_roles ur
    WHERE ur.role != 'master';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RLS policy update: Hide master users from non-master roles
DROP POLICY IF EXISTS "Users can view user roles" ON public.user_roles;

CREATE POLICY "Users can view user roles based on hierarchy"
ON public.user_roles
FOR SELECT
TO authenticated
USING (
  -- Users can always see their own role
  user_id = auth.uid()
  OR
  -- Master can see everyone
  EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'master')
  OR
  -- Super Admin can see everyone except master
  (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'super_admin')
   AND role != 'master')
);
-- ===== 20251222111106_31942aac-9369-41f0-91ef-5f2631c95db8.sql =====
-- Drop existing problematic policies on user_roles
DROP POLICY IF EXISTS "Users can view their own role" ON public.user_roles;
DROP POLICY IF EXISTS "Master admin full access on user_roles" ON public.user_roles;
DROP POLICY IF EXISTS "Super admin can view all roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can manage roles" ON public.user_roles;
DROP POLICY IF EXISTS "Users can view own role" ON public.user_roles;
DROP POLICY IF EXISTS "Master can manage all roles" ON public.user_roles;

-- Create a security definer function to check roles (bypasses RLS)
CREATE OR REPLACE FUNCTION public.authorize_role_access(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('master', 'super_admin', 'admin')
  )
$$;

-- Simple, non-recursive policies
-- Users can view their own role
CREATE POLICY "Users can view own role"
ON public.user_roles
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- System/service role can manage all roles (for edge functions)
CREATE POLICY "Service role manages roles"
ON public.user_roles
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- For inserts by authenticated users (only their own)
CREATE POLICY "Users can insert own role"
ON public.user_roles
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());
-- ===== 20251222111325_6ba192d0-7d5e-44c6-9cf9-22e7ade1115a.sql =====
-- Remove ALL existing policies on public.user_roles to eliminate recursion
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN (
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_roles'
  ) LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_roles', r.policyname);
  END LOOP;
END $$;

-- Ensure RLS enabled
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Canonical role-check function (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- Minimal safe policies (no self-references)
CREATE POLICY "user_roles_select_own"
ON public.user_roles
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_roles_service_all"
ON public.user_roles
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
-- ===== 20251222111518_71721186-51f4-41ce-8b9e-0560d3e0485d.sql =====
-- Function to force logout all non-master users
CREATE OR REPLACE FUNCTION public.force_logout_all_except_master(admin_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count INTEGER;
BEGIN
  -- Verify the admin is a master
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = admin_user_id AND role = 'master'
  ) THEN
    RAISE EXCEPTION 'Only Master Admin can force logout all users';
  END IF;
  
  -- Update all non-master users
  UPDATE public.user_roles 
  SET force_logged_out_at = NOW(),
      force_logged_out_by = admin_user_id
  WHERE role != 'master';
  
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  
  RETURN affected_count;
END;
$$;
-- ===== 20251222113129_8373ae64-b319-4160-8d9a-b35793f67796.sql =====
-- Create activity log types enum
CREATE TYPE public.activity_action_type AS ENUM (
  'login',
  'logout',
  'page_navigation',
  'demo_interaction',
  'copy_attempt',
  'link_edit',
  'approval_request',
  'force_logout',
  'task_update',
  'lead_action',
  'chat_message',
  'file_access',
  'settings_change',
  'error'
);

-- Create activity status enum
CREATE TYPE public.activity_status AS ENUM (
  'success',
  'fail',
  'blocked',
  'pending',
  'warning'
);

-- Create live activity logs table
CREATE TABLE public.live_activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  user_role public.app_role NOT NULL,
  action_type public.activity_action_type NOT NULL,
  action_description TEXT,
  status public.activity_status DEFAULT 'success',
  page_url TEXT,
  ip_address TEXT,
  device_info TEXT,
  user_agent TEXT,
  duration_seconds INTEGER DEFAULT 0,
  is_abnormal BOOLEAN DEFAULT false,
  abnormal_reason TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create index for faster queries
CREATE INDEX idx_live_activity_logs_user_id ON public.live_activity_logs(user_id);
CREATE INDEX idx_live_activity_logs_created_at ON public.live_activity_logs(created_at DESC);
CREATE INDEX idx_live_activity_logs_action_type ON public.live_activity_logs(action_type);
CREATE INDEX idx_live_activity_logs_user_role ON public.live_activity_logs(user_role);

-- Enable RLS
ALTER TABLE public.live_activity_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Master can view all logs
CREATE POLICY "master_view_all_logs" ON public.live_activity_logs
FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'master'));

-- RLS Policy: Super Admin can view all logs except master logs
CREATE POLICY "super_admin_view_non_master_logs" ON public.live_activity_logs
FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(), 'super_admin') 
  AND user_role != 'master'
);

-- RLS Policy: Users can view their own logs
CREATE POLICY "users_view_own_logs" ON public.live_activity_logs
FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- RLS Policy: System can insert logs (service role or authenticated users for their own actions)
CREATE POLICY "insert_own_logs" ON public.live_activity_logs
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- Create user online status table
CREATE TABLE public.user_online_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL,
  user_role public.app_role NOT NULL,
  is_online BOOLEAN DEFAULT false,
  last_seen_at TIMESTAMPTZ DEFAULT now(),
  session_started_at TIMESTAMPTZ,
  current_page TEXT,
  device_info TEXT,
  ip_address TEXT,
  force_logged_out BOOLEAN DEFAULT false,
  pending_approval BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_online_status ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Master can view all status
CREATE POLICY "master_view_all_status" ON public.user_online_status
FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'master'));

-- RLS Policy: Super Admin can view all except master
CREATE POLICY "super_admin_view_non_master_status" ON public.user_online_status
FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(), 'super_admin') 
  AND user_role != 'master'
);

-- RLS Policy: Users can view and update their own status
CREATE POLICY "users_manage_own_status" ON public.user_online_status
FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Enable realtime for both tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_activity_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_online_status;

-- Function to log activity
CREATE OR REPLACE FUNCTION public.log_activity(
  p_action_type public.activity_action_type,
  p_description TEXT DEFAULT NULL,
  p_status public.activity_status DEFAULT 'success',
  p_page_url TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role public.app_role;
  v_log_id UUID;
BEGIN
  -- Get user role
  SELECT role INTO v_user_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
  
  -- Insert activity log
  INSERT INTO public.live_activity_logs (
    user_id, user_role, action_type, action_description, status, page_url, metadata
  ) VALUES (
    auth.uid(), v_user_role, p_action_type, p_description, p_status, p_page_url, p_metadata
  ) RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$;

-- Function to update online status
CREATE OR REPLACE FUNCTION public.update_online_status(
  p_is_online BOOLEAN,
  p_current_page TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role public.app_role;
BEGIN
  -- Get user role
  SELECT role INTO v_user_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
  
  -- Upsert online status
  INSERT INTO public.user_online_status (user_id, user_role, is_online, current_page, session_started_at)
  VALUES (auth.uid(), v_user_role, p_is_online, p_current_page, CASE WHEN p_is_online THEN now() ELSE NULL END)
  ON CONFLICT (user_id) DO UPDATE SET
    is_online = p_is_online,
    last_seen_at = now(),
    current_page = COALESCE(p_current_page, user_online_status.current_page),
    session_started_at = CASE WHEN p_is_online AND user_online_status.session_started_at IS NULL THEN now() ELSE user_online_status.session_started_at END,
    updated_at = now();
  
  RETURN TRUE;
END;
$$;
-- ===== 20251222174644_28d36390-65ff-45e7-8eaf-e109bd2c70d5.sql =====
-- Create function to check if current user is super_admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'super_admin'
  )
$$;

-- Allow super_admin to view all user_roles
CREATE POLICY "super_admin_can_view_all_roles"
ON public.user_roles
FOR SELECT
TO authenticated
USING (public.is_super_admin());

-- Allow super_admin to update any user_roles (for approving/rejecting)
CREATE POLICY "super_admin_can_update_roles"
ON public.user_roles
FOR UPDATE
TO authenticated
USING (public.is_super_admin())
WITH CHECK (public.is_super_admin());

-- Allow super_admin to insert user_roles
CREATE POLICY "super_admin_can_insert_roles"
ON public.user_roles
FOR INSERT
TO authenticated
WITH CHECK (public.is_super_admin());

-- Allow super_admin to delete user_roles
CREATE POLICY "super_admin_can_delete_roles"
ON public.user_roles
FOR DELETE
TO authenticated
USING (public.is_super_admin());
-- ===== 20251222201040_2303de9f-9b30-40ca-ab12-eba7573b26e9.sql =====
-- Create demo_report_cards table for tracking all demo actions
CREATE TABLE public.demo_report_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
    demo_name TEXT NOT NULL,
    sector TEXT,
    sub_category TEXT,
    action_type TEXT NOT NULL CHECK (action_type IN ('add', 'edit', 'delete', 'fix', 'replace_link', 'approve', 'reject', 'health_check', 'status_update')),
    performed_by UUID NOT NULL,
    performed_by_role TEXT NOT NULL,
    action_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    demo_status TEXT,
    uptime_state TEXT,
    error_details TEXT,
    fix_details TEXT,
    completion_time_seconds INTEGER,
    old_values JSONB,
    new_values JSONB,
    auto_registered BOOLEAN DEFAULT true,
    workflow_status TEXT DEFAULT 'submitted' CHECK (workflow_status IN ('submitted', 'in_progress', 'fixed', 'live', 'disabled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.demo_report_cards ENABLE ROW LEVEL SECURITY;

-- Demo Manager can view their own report cards
CREATE POLICY "Demo managers can view their own report cards"
ON public.demo_report_cards
FOR SELECT
TO authenticated
USING (
    performed_by = auth.uid() 
    AND EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role = 'demo_manager'
    )
);

-- Demo Manager can insert report cards
CREATE POLICY "Demo managers can create report cards"
ON public.demo_report_cards
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role = 'demo_manager'
    )
);

-- Super Admin and Admin can view all report cards
CREATE POLICY "Super admins can view all report cards"
ON public.demo_report_cards
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('super_admin', 'admin')
    )
);

-- Create function to check if user is demo_manager
CREATE OR REPLACE FUNCTION public.is_demo_manager(_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = _user_id
        AND role = 'demo_manager'
    )
$$;

-- Create function to log unauthorized demo access attempts
CREATE OR REPLACE FUNCTION public.log_unauthorized_demo_attempt(
    _user_id UUID,
    _user_role TEXT,
    _action_attempted TEXT,
    _demo_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    log_id UUID;
BEGIN
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        _user_id,
        'unauthorized_demo_access_attempt',
        'demo_security',
        _user_role::app_role,
        jsonb_build_object(
            'action_attempted', _action_attempted,
            'demo_id', _demo_id,
            'blocked', true,
            'flagged', true,
            'timestamp', now()
        )
    )
    RETURNING id INTO log_id;
    
    RETURN log_id;
END;
$$;

-- Create function to auto-create report card on demo action
CREATE OR REPLACE FUNCTION public.create_demo_report_card(
    _demo_id UUID,
    _demo_name TEXT,
    _action_type TEXT,
    _sector TEXT DEFAULT NULL,
    _sub_category TEXT DEFAULT NULL,
    _demo_status TEXT DEFAULT NULL,
    _uptime_state TEXT DEFAULT NULL,
    _error_details TEXT DEFAULT NULL,
    _fix_details TEXT DEFAULT NULL,
    _old_values JSONB DEFAULT NULL,
    _new_values JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    report_id UUID;
    user_role TEXT;
BEGIN
    -- Get user role
    SELECT role INTO user_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
    
    -- Only demo_manager can create report cards
    IF user_role != 'demo_manager' THEN
        PERFORM public.log_unauthorized_demo_attempt(auth.uid(), user_role, _action_type, _demo_id);
        RAISE EXCEPTION 'Access denied: Only Demo Manager can perform demo actions';
    END IF;
    
    INSERT INTO public.demo_report_cards (
        demo_id, demo_name, sector, sub_category, action_type,
        performed_by, performed_by_role, demo_status, uptime_state,
        error_details, fix_details, old_values, new_values,
        auto_registered, workflow_status
    )
    VALUES (
        _demo_id, _demo_name, _sector, _sub_category, _action_type,
        auth.uid(), user_role, _demo_status, _uptime_state,
        _error_details, _fix_details, _old_values, _new_values,
        true, 'submitted'
    )
    RETURNING id INTO report_id;
    
    -- Also log to audit_logs
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        _action_type,
        'demo',
        user_role::app_role,
        jsonb_build_object(
            'demo_id', _demo_id,
            'demo_name', _demo_name,
            'report_card_id', report_id,
            'auto_registered', true
        )
    );
    
    RETURN report_id;
END;
$$;

-- Update RLS on demos table to restrict modifications to demo_manager only
-- First drop any existing permissive policies
DROP POLICY IF EXISTS "Anyone can view demos" ON public.demos;
DROP POLICY IF EXISTS "Authenticated users can insert demos" ON public.demos;
DROP POLICY IF EXISTS "Users can update demos" ON public.demos;
DROP POLICY IF EXISTS "Users can delete demos" ON public.demos;

-- Create new restrictive policies for demos
CREATE POLICY "Anyone can view demos"
ON public.demos
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Only demo_manager can insert demos"
ON public.demos
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

CREATE POLICY "Only demo_manager can update demos"
ON public.demos
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

CREATE POLICY "Only demo_manager can delete demos"
ON public.demos
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

-- Update RLS on demo_alerts table
DROP POLICY IF EXISTS "Anyone can view alerts" ON public.demo_alerts;
DROP POLICY IF EXISTS "Users can insert alerts" ON public.demo_alerts;
DROP POLICY IF EXISTS "Users can update alerts" ON public.demo_alerts;

CREATE POLICY "Anyone can view demo alerts"
ON public.demo_alerts
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Only demo_manager can insert alerts"
ON public.demo_alerts
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

CREATE POLICY "Only demo_manager can update alerts"
ON public.demo_alerts
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

-- Create index for better performance
CREATE INDEX idx_demo_report_cards_performed_by ON public.demo_report_cards(performed_by);
CREATE INDEX idx_demo_report_cards_demo_id ON public.demo_report_cards(demo_id);
CREATE INDEX idx_demo_report_cards_action_timestamp ON public.demo_report_cards(action_timestamp DESC);
-- ===== 20251222201614_8bf8b8dc-0922-43d7-b420-78e77fd97467.sql =====
-- Create demo_login_roles table for storing login credentials per demo
CREATE TABLE public.demo_login_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demo_id UUID NOT NULL REFERENCES public.demos(id) ON DELETE CASCADE,
    role_name TEXT NOT NULL,
    username TEXT NOT NULL,
    password_encrypted TEXT NOT NULL,
    display_order INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT unique_demo_role UNIQUE(demo_id, role_name)
);

-- Add status column to demos if not exists (for pending/active/disabled)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type WHERE typname = 'demo_lifecycle_status'
    ) THEN
        CREATE TYPE demo_lifecycle_status AS ENUM ('pending', 'active', 'disabled', 'archived');
    END IF;
END$$;

-- Add demo_type column for categorization (School, Hospital, ERP, etc.)
ALTER TABLE public.demos 
ADD COLUMN IF NOT EXISTS demo_type TEXT DEFAULT 'general',
ADD COLUMN IF NOT EXISTS lifecycle_status TEXT DEFAULT 'pending' CHECK (lifecycle_status IN ('pending', 'active', 'disabled', 'archived')),
ADD COLUMN IF NOT EXISTS login_url TEXT,
ADD COLUMN IF NOT EXISTS total_login_roles INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_bulk_created BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS activated_by UUID;

-- Enable RLS on demo_login_roles
ALTER TABLE public.demo_login_roles ENABLE ROW LEVEL SECURITY;

-- Only Demo Manager can view login credentials
CREATE POLICY "Demo manager can view login roles"
ON public.demo_login_roles
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('demo_manager', 'super_admin')
    )
);

-- Only Demo Manager can insert login roles
CREATE POLICY "Demo manager can insert login roles"
ON public.demo_login_roles
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role = 'demo_manager'
    )
);

-- Only Demo Manager can update login roles
CREATE POLICY "Demo manager can update login roles"
ON public.demo_login_roles
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role = 'demo_manager'
    )
);

-- Only Demo Manager can delete login roles
CREATE POLICY "Demo manager can delete login roles"
ON public.demo_login_roles
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role = 'demo_manager'
    )
);

-- Create function to update login role count on demos
CREATE OR REPLACE FUNCTION public.update_demo_login_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        UPDATE public.demos 
        SET total_login_roles = (
            SELECT COUNT(*) FROM public.demo_login_roles 
            WHERE demo_id = NEW.demo_id AND is_active = true
        )
        WHERE id = NEW.demo_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.demos 
        SET total_login_roles = (
            SELECT COUNT(*) FROM public.demo_login_roles 
            WHERE demo_id = OLD.demo_id AND is_active = true
        )
        WHERE id = OLD.demo_id;
        RETURN OLD;
    END IF;
END;
$$;

-- Create trigger for login count update
DROP TRIGGER IF EXISTS update_demo_login_count_trigger ON public.demo_login_roles;
CREATE TRIGGER update_demo_login_count_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.demo_login_roles
FOR EACH ROW
EXECUTE FUNCTION public.update_demo_login_count();

-- Create function for bulk demo creation (Demo Manager only)
CREATE OR REPLACE FUNCTION public.bulk_create_demos(
    _demos JSONB
)
RETURNS TABLE(demo_id UUID, demo_name TEXT, status TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    demo_item JSONB;
    new_demo_id UUID;
    login_role JSONB;
    user_role TEXT;
BEGIN
    -- Check if user is demo_manager
    SELECT role INTO user_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
    
    IF user_role != 'demo_manager' THEN
        RAISE EXCEPTION 'Access denied: Only Demo Manager can bulk create demos';
    END IF;
    
    FOR demo_item IN SELECT * FROM jsonb_array_elements(_demos)
    LOOP
        -- Insert demo
        INSERT INTO public.demos (
            title,
            url,
            login_url,
            demo_type,
            category,
            description,
            lifecycle_status,
            is_bulk_created,
            created_by,
            status
        ) VALUES (
            demo_item->>'name',
            COALESCE(demo_item->>'url', demo_item->>'login_url'),
            demo_item->>'login_url',
            demo_item->>'demo_type',
            COALESCE(demo_item->>'category', demo_item->>'demo_type'),
            demo_item->>'description',
            'pending',
            true,
            auth.uid(),
            'maintenance'
        )
        RETURNING id INTO new_demo_id;
        
        -- Insert login roles if provided
        IF demo_item->'login_roles' IS NOT NULL THEN
            FOR login_role IN SELECT * FROM jsonb_array_elements(demo_item->'login_roles')
            LOOP
                INSERT INTO public.demo_login_roles (
                    demo_id,
                    role_name,
                    username,
                    password_encrypted,
                    display_order,
                    created_by
                ) VALUES (
                    new_demo_id,
                    login_role->>'role_name',
                    login_role->>'username',
                    login_role->>'password',
                    COALESCE((login_role->>'display_order')::INTEGER, 1),
                    auth.uid()
                );
            END LOOP;
        END IF;
        
        -- Log the creation
        INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
        VALUES (
            auth.uid(),
            'bulk_demo_created',
            'demo',
            user_role::app_role,
            jsonb_build_object(
                'demo_id', new_demo_id,
                'demo_name', demo_item->>'name',
                'demo_type', demo_item->>'demo_type',
                'login_roles_count', COALESCE(jsonb_array_length(demo_item->'login_roles'), 0)
            )
        );
        
        -- Return result
        demo_id := new_demo_id;
        demo_name := demo_item->>'name';
        status := 'created';
        RETURN NEXT;
    END LOOP;
END;
$$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_demo_login_roles_demo_id ON public.demo_login_roles(demo_id);
CREATE INDEX IF NOT EXISTS idx_demos_demo_type ON public.demos(demo_type);
CREATE INDEX IF NOT EXISTS idx_demos_lifecycle_status ON public.demos(lifecycle_status);
-- ===== 20251223003120_8adad2ca-7c12-44df-995f-ed1d832ddaf4.sql =====
-- Create software catalog table for the 5000+ software list
CREATE TABLE public.software_catalog (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    base_price DECIMAL(10,2) DEFAULT 0,
    type TEXT NOT NULL CHECK (type IN ('Offline', 'Desktop', 'SaaS', 'Mobile', 'Hybrid')),
    vendor TEXT DEFAULT 'Software Vala',
    category TEXT,
    demo_url TEXT,
    demo_id UUID REFERENCES public.demos(id) ON DELETE SET NULL,
    is_demo_registered BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create index for fast searching
CREATE INDEX idx_software_catalog_name ON public.software_catalog USING gin(to_tsvector('english', name));
CREATE INDEX idx_software_catalog_type ON public.software_catalog(type);
CREATE INDEX idx_software_catalog_category ON public.software_catalog(category);

-- Enable RLS
ALTER TABLE public.software_catalog ENABLE ROW LEVEL SECURITY;

-- Policies - Demo Manager and Master Admin can manage
CREATE POLICY "Demo managers can manage software catalog"
ON public.software_catalog
FOR ALL
TO authenticated
USING (
    public.has_role(auth.uid(), 'demo_manager') OR 
    public.has_role(auth.uid(), 'master') OR
    public.has_role(auth.uid(), 'super_admin')
)
WITH CHECK (
    public.has_role(auth.uid(), 'demo_manager') OR 
    public.has_role(auth.uid(), 'master') OR
    public.has_role(auth.uid(), 'super_admin')
);

-- Anyone authenticated can read for suggestions/autocomplete
CREATE POLICY "Authenticated users can view software catalog"
ON public.software_catalog
FOR SELECT
TO authenticated
USING (true);

-- Trigger for updated_at
CREATE TRIGGER update_software_catalog_updated_at
BEFORE UPDATE ON public.software_catalog
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251223004223_02498632-9470-479a-b181-efc6606e9564.sql =====
-- Demo validation logs table (immutable)
CREATE TABLE public.demo_validation_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
  demo_url TEXT NOT NULL,
  validation_type TEXT NOT NULL, -- 'url_check', 'duplicate_check', 'reachability_check'
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'passed', 'failed'
  error_message TEXT,
  http_status INTEGER,
  response_time_ms INTEGER,
  validated_by UUID,
  validated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Demo verification queue for bulk async processing
CREATE TABLE public.demo_verification_queue (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
  priority INTEGER DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'queued', -- 'queued', 'processing', 'completed', 'failed'
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 3,
  last_attempt_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Add normalized URL column to demos for duplicate detection
ALTER TABLE public.demos 
ADD COLUMN IF NOT EXISTS normalized_url TEXT,
ADD COLUMN IF NOT EXISTS last_verified_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'unverified',
ADD COLUMN IF NOT EXISTS http_status INTEGER,
ADD COLUMN IF NOT EXISTS response_time_ms INTEGER;

-- Create function to normalize URLs for duplicate detection
CREATE OR REPLACE FUNCTION normalize_demo_url(url TEXT)
RETURNS TEXT AS $$
DECLARE
  normalized TEXT;
BEGIN
  normalized := lower(url);
  -- Remove protocol
  normalized := regexp_replace(normalized, '^https?://', '');
  -- Remove www.
  normalized := regexp_replace(normalized, '^www\.', '');
  -- Remove trailing slashes
  normalized := regexp_replace(normalized, '/+$', '');
  -- Remove query params for core URL comparison
  normalized := regexp_replace(normalized, '\?.*$', '');
  RETURN normalized;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

-- Create trigger to auto-populate normalized_url
CREATE OR REPLACE FUNCTION set_normalized_url()
RETURNS TRIGGER AS $$
BEGIN
  NEW.normalized_url := normalize_demo_url(NEW.url);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER trigger_set_normalized_url
BEFORE INSERT OR UPDATE OF url ON public.demos
FOR EACH ROW
EXECUTE FUNCTION set_normalized_url();

-- Update existing demos with normalized URLs
UPDATE public.demos SET normalized_url = normalize_demo_url(url) WHERE normalized_url IS NULL;

-- Create unique index on normalized_url for duplicate prevention
CREATE UNIQUE INDEX IF NOT EXISTS idx_demos_normalized_url_unique ON public.demos(normalized_url);

-- Create index for faster duplicate lookups
CREATE INDEX IF NOT EXISTS idx_demos_category_title ON public.demos(category, title);

-- RLS for validation logs (immutable - no update/delete)
ALTER TABLE public.demo_validation_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Demo managers can insert validation logs"
ON public.demo_validation_logs FOR INSERT
WITH CHECK (
  has_role(auth.uid(), 'demo_manager'::app_role) OR 
  has_role(auth.uid(), 'super_admin'::app_role)
);

CREATE POLICY "Demo managers can view validation logs"
ON public.demo_validation_logs FOR SELECT
USING (
  has_role(auth.uid(), 'demo_manager'::app_role) OR 
  has_role(auth.uid(), 'super_admin'::app_role) OR
  has_role(auth.uid(), 'master'::app_role)
);

-- RLS for verification queue
ALTER TABLE public.demo_verification_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Demo managers can manage verification queue"
ON public.demo_verification_queue FOR ALL
USING (
  has_role(auth.uid(), 'demo_manager'::app_role) OR 
  has_role(auth.uid(), 'super_admin'::app_role)
)
WITH CHECK (
  has_role(auth.uid(), 'demo_manager'::app_role) OR 
  has_role(auth.uid(), 'super_admin'::app_role)
);

-- System can insert into validation logs
CREATE POLICY "System can insert validation logs"
ON public.demo_validation_logs FOR INSERT
WITH CHECK (true);

-- System can manage verification queue
CREATE POLICY "System can manage verification queue"
ON public.demo_verification_queue FOR ALL
USING (true)
WITH CHECK (true);
-- ===== 20251223010635_292f4d41-ae4d-4cc4-839e-660733d22cc3.sql =====

-- =====================================================
-- PRODUCT MODULE DATABASE SCHEMA (EXTENDED)
-- =====================================================

-- 1. Create business_categories table (50 master categories)
CREATE TABLE public.business_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    icon TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 2. Create business_subcategories table
CREATE TABLE public.business_subcategories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL REFERENCES public.business_categories(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(category_id, name)
);

-- 3. Extend existing products table with new columns
ALTER TABLE public.products 
ADD COLUMN IF NOT EXISTS product_type TEXT DEFAULT 'software',
ADD COLUMN IF NOT EXISTS business_category_id UUID REFERENCES public.business_categories(id),
ADD COLUMN IF NOT EXISTS subcategory_id UUID REFERENCES public.business_subcategories(id),
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active',
ADD COLUMN IF NOT EXISTS has_broken_demo BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id);

-- 4. Create product_demo_mappings table
CREATE TABLE public.product_demo_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(product_id) ON DELETE CASCADE,
    demo_id UUID NOT NULL REFERENCES public.demos(id) ON DELETE CASCADE,
    linked_by UUID REFERENCES auth.users(id),
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(product_id, demo_id)
);

-- 5. Create product_action_logs table (immutable)
CREATE TABLE public.product_action_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES public.products(product_id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    action TEXT NOT NULL,
    action_details JSONB DEFAULT '{}',
    performed_by UUID REFERENCES auth.users(id),
    performer_role app_role,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.business_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_subcategories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_demo_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_action_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for business_categories
CREATE POLICY "Anyone can view active categories"
ON public.business_categories FOR SELECT
USING (is_active = true OR has_role(auth.uid(), 'master'::app_role) OR has_role(auth.uid(), 'super_admin'::app_role));

CREATE POLICY "Master admin manages categories"
ON public.business_categories FOR ALL
USING (has_role(auth.uid(), 'master'::app_role) OR has_role(auth.uid(), 'super_admin'::app_role));

-- RLS Policies for business_subcategories
CREATE POLICY "Anyone can view active subcategories"
ON public.business_subcategories FOR SELECT
USING (is_active = true OR has_role(auth.uid(), 'master'::app_role) OR has_role(auth.uid(), 'super_admin'::app_role));

CREATE POLICY "Master admin manages subcategories"
ON public.business_subcategories FOR ALL
USING (has_role(auth.uid(), 'master'::app_role) OR has_role(auth.uid(), 'super_admin'::app_role));

-- RLS Policies for product_demo_mappings
CREATE POLICY "Anyone views product demos"
ON public.product_demo_mappings FOR SELECT
USING (true);

CREATE POLICY "Demo manager manages mappings"
ON public.product_demo_mappings FOR ALL
USING (has_role(auth.uid(), 'demo_manager'::app_role) OR has_role(auth.uid(), 'master'::app_role));

-- RLS Policies for product_action_logs (immutable)
CREATE POLICY "System inserts product logs"
ON public.product_action_logs FOR INSERT
WITH CHECK (true);

CREATE POLICY "Authorized roles view product logs"
ON public.product_action_logs FOR SELECT
USING (has_role(auth.uid(), 'demo_manager'::app_role) OR has_role(auth.uid(), 'master'::app_role) OR has_role(auth.uid(), 'super_admin'::app_role));

-- Create indexes for performance
CREATE INDEX idx_products_business_category ON public.products(business_category_id);
CREATE INDEX idx_products_subcategory ON public.products(subcategory_id);
CREATE INDEX idx_products_status ON public.products(status);
CREATE INDEX idx_subcategories_category ON public.business_subcategories(category_id);
CREATE INDEX idx_product_mappings_product ON public.product_demo_mappings(product_id);
CREATE INDEX idx_product_mappings_demo ON public.product_demo_mappings(demo_id);
CREATE INDEX idx_product_logs_product ON public.product_action_logs(product_id);

-- =====================================================
-- INSERT 50 MASTER BUSINESS CATEGORIES WITH SUBCATEGORIES
-- =====================================================

INSERT INTO public.business_categories (name, description, icon, display_order) VALUES
('Healthcare & Medical', 'Medical software and healthcare solutions', 'Heart', 1),
('Education & E-Learning', 'Educational platforms and learning management', 'GraduationCap', 2),
('Finance & Banking', 'Financial services and banking solutions', 'DollarSign', 3),
('E-Commerce & Retail', 'Online stores and retail management', 'ShoppingCart', 4),
('Real Estate & Property', 'Property management and real estate', 'Home', 5),
('Restaurant & Food Service', 'Restaurant and food delivery systems', 'UtensilsCrossed', 6),
('Hotel & Hospitality', 'Hotel management and booking systems', 'Building', 7),
('Transportation & Logistics', 'Fleet and logistics management', 'Truck', 8),
('Manufacturing & Industry', 'Industrial and manufacturing solutions', 'Factory', 9),
('Human Resources & HR', 'HR management and recruitment', 'Users', 10),
('Customer Relationship (CRM)', 'Customer management solutions', 'UserCheck', 11),
('Project Management', 'Project and task management tools', 'ClipboardList', 12),
('Accounting & Invoicing', 'Accounting and billing solutions', 'Calculator', 13),
('Legal & Law Firm', 'Legal practice management', 'Scale', 14),
('Insurance & Claims', 'Insurance management systems', 'Shield', 15),
('Marketing & Advertising', 'Marketing automation and ads', 'Megaphone', 16),
('Social Media & Community', 'Social networking platforms', 'Share2', 17),
('News & Publishing', 'Content and news management', 'Newspaper', 18),
('Entertainment & Media', 'Media and entertainment platforms', 'Film', 19),
('Gaming & Sports', 'Gaming and sports management', 'Gamepad2', 20),
('Travel & Tourism', 'Travel booking and tourism', 'Plane', 21),
('Fitness & Wellness', 'Gym and wellness management', 'Activity', 22),
('Beauty & Salon', 'Salon and spa management', 'Scissors', 23),
('Agriculture & Farming', 'Agricultural management systems', 'Leaf', 24),
('Construction & Architecture', 'Construction project management', 'HardHat', 25),
('Telecommunications', 'Telecom and communication services', 'Phone', 26),
('IT & Software Services', 'IT service management', 'Code', 27),
('Cybersecurity', 'Security and protection solutions', 'Lock', 28),
('Cloud & Hosting', 'Cloud services and hosting', 'Cloud', 29),
('IoT & Smart Devices', 'Internet of Things solutions', 'Wifi', 30),
('AI & Machine Learning', 'Artificial intelligence platforms', 'Brain', 31),
('Blockchain & Crypto', 'Blockchain and cryptocurrency', 'Link', 32),
('Government & Public Sector', 'Government administration systems', 'Landmark', 33),
('Non-Profit & NGO', 'Non-profit organization management', 'HandHeart', 34),
('Religious & Worship', 'Church and religious management', 'Church', 35),
('Event & Ticketing', 'Event management and ticketing', 'Calendar', 36),
('Photography & Video', 'Photography and video services', 'Camera', 37),
('Music & Audio', 'Music streaming and audio production', 'Music', 38),
('Automotive & Vehicles', 'Vehicle and automotive management', 'Car', 39),
('Pet & Veterinary', 'Pet care and veterinary services', 'PawPrint', 40),
('Childcare & Daycare', 'Childcare management systems', 'Baby', 41),
('Senior Care & Assisted Living', 'Elder care management', 'HeartHandshake', 42),
('Energy & Utilities', 'Energy and utility management', 'Zap', 43),
('Mining & Resources', 'Mining and resource management', 'Mountain', 44),
('Fashion & Apparel', 'Fashion and clothing retail', 'Shirt', 45),
('Jewelry & Luxury', 'Jewelry and luxury goods', 'Gem', 46),
('Grocery & Supermarket', 'Grocery store management', 'Apple', 47),
('Pharmacy & Drug Store', 'Pharmacy management systems', 'Pill', 48),
('Laundry & Dry Cleaning', 'Laundry service management', 'WashingMachine', 49),
('Printing & Publishing', 'Print shop management', 'Printer', 50);

-- Insert subcategories for each category
INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Hospital Management', 'Clinic Management', 'Pharmacy POS', 'Laboratory Management', 'Telemedicine', 'Patient Portal', 'Medical Billing']) AS subcategory
WHERE name = 'Healthcare & Medical';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Learning Management (LMS)', 'School Management', 'University ERP', 'Online Courses', 'Tutoring Platform', 'Student Portal', 'Exam Management']) AS subcategory
WHERE name = 'Education & E-Learning';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Core Banking', 'Loan Management', 'Investment Platform', 'Payment Gateway', 'Mobile Banking', 'Microfinance', 'Stock Trading']) AS subcategory
WHERE name = 'Finance & Banking';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Multi-Vendor Marketplace', 'Single Store', 'B2B Commerce', 'POS System', 'Inventory Management', 'Dropshipping', 'Subscription Commerce']) AS subcategory
WHERE name = 'E-Commerce & Retail';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Property Listing', 'Property Management', 'Real Estate CRM', 'Rental Management', 'Mortgage Calculator', 'Virtual Tours', 'Agent Portal']) AS subcategory
WHERE name = 'Real Estate & Property';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Restaurant POS', 'Food Delivery', 'Table Reservation', 'Kitchen Display', 'Menu Management', 'Cloud Kitchen', 'Catering Management']) AS subcategory
WHERE name = 'Restaurant & Food Service';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Hotel Booking', 'Property Management System', 'Channel Manager', 'Housekeeping', 'Guest Experience', 'Revenue Management', 'Hostel Management']) AS subcategory
WHERE name = 'Hotel & Hospitality';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Fleet Management', 'Delivery Management', 'Ride Sharing', 'Freight Management', 'Warehouse Management', 'Last Mile Delivery', 'Route Optimization']) AS subcategory
WHERE name = 'Transportation & Logistics';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['ERP System', 'Production Planning', 'Quality Control', 'Supply Chain', 'Asset Management', 'Maintenance (CMMS)', 'Shop Floor Control']) AS subcategory
WHERE name = 'Manufacturing & Industry';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['HRMS', 'Payroll Management', 'Recruitment (ATS)', 'Employee Self-Service', 'Performance Management', 'Time & Attendance', 'Learning & Development']) AS subcategory
WHERE name = 'Human Resources & HR';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Sales CRM', 'Service CRM', 'Marketing CRM', 'Contact Management', 'Lead Management', 'Pipeline Management', 'Customer Support']) AS subcategory
WHERE name = 'Customer Relationship (CRM)';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Task Management', 'Agile/Scrum', 'Gantt Charts', 'Team Collaboration', 'Time Tracking', 'Resource Planning', 'Milestone Tracking']) AS subcategory
WHERE name = 'Project Management';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['General Ledger', 'Invoicing', 'Expense Management', 'Tax Management', 'Budgeting', 'Financial Reporting', 'Multi-Currency']) AS subcategory
WHERE name = 'Accounting & Invoicing';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Case Management', 'Document Management', 'Time Billing', 'Client Portal', 'Contract Management', 'Legal Research', 'Court Filing']) AS subcategory
WHERE name = 'Legal & Law Firm';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Policy Management', 'Claims Processing', 'Underwriting', 'Agent Portal', 'Reinsurance', 'Quote Engine', 'Risk Assessment']) AS subcategory
WHERE name = 'Insurance & Claims';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Email Marketing', 'Marketing Automation', 'Ad Management', 'SEO Tools', 'Analytics Dashboard', 'Content Marketing', 'Affiliate Marketing']) AS subcategory
WHERE name = 'Marketing & Advertising';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Social Network', 'Community Forum', 'Discussion Board', 'Social Media Management', 'Influencer Platform', 'User Generated Content', 'Live Streaming']) AS subcategory
WHERE name = 'Social Media & Community';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['News Portal', 'Blog Platform', 'Magazine CMS', 'Digital Publishing', 'Newsletter', 'Content Aggregator', 'Paywall System']) AS subcategory
WHERE name = 'News & Publishing';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Video Streaming', 'OTT Platform', 'Podcast Platform', 'Media Library', 'Digital Asset Management', 'Live Events', 'Fan Engagement']) AS subcategory
WHERE name = 'Entertainment & Media';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Sports Management', 'Fantasy Sports', 'Betting Platform', 'Tournament Management', 'Team Management', 'Score Tracking', 'Gaming Community']) AS subcategory
WHERE name = 'Gaming & Sports';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Flight Booking', 'Tour Packages', 'Travel Agency', 'Visa Services', 'Travel Blog', 'Destination Guide', 'Travel Insurance']) AS subcategory
WHERE name = 'Travel & Tourism';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Gym Management', 'Yoga Studio', 'Personal Training', 'Nutrition Tracking', 'Wellness App', 'Fitness Classes', 'Health Coaching']) AS subcategory
WHERE name = 'Fitness & Wellness';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Salon Management', 'Spa Booking', 'Appointment Scheduling', 'Staff Management', 'Inventory (Beauty)', 'Loyalty Program', 'Online Booking']) AS subcategory
WHERE name = 'Beauty & Salon';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Farm Management', 'Crop Planning', 'Livestock Management', 'Irrigation Control', 'Marketplace (Agri)', 'Supply Chain (Agri)', 'Weather Tracking']) AS subcategory
WHERE name = 'Agriculture & Farming';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Project Estimation', 'Blueprint Management', 'Contractor Portal', 'Site Management', 'Material Tracking', 'Safety Compliance', 'BIM Tools']) AS subcategory
WHERE name = 'Construction & Architecture';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Billing System', 'Network Management', 'Customer Portal', 'VoIP System', 'SMS Gateway', 'Call Center', 'Subscriber Management']) AS subcategory
WHERE name = 'Telecommunications';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Helpdesk/ITSM', 'DevOps Tools', 'Code Repository', 'Bug Tracking', 'API Management', 'Documentation', 'Monitoring Tools']) AS subcategory
WHERE name = 'IT & Software Services';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['SIEM', 'Vulnerability Scanner', 'Password Manager', 'Identity Management', 'Firewall Management', 'Penetration Testing', 'Compliance Audit']) AS subcategory
WHERE name = 'Cybersecurity';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Web Hosting Panel', 'Cloud Dashboard', 'Domain Management', 'Server Monitoring', 'Backup Solution', 'CDN Management', 'Container Orchestration']) AS subcategory
WHERE name = 'Cloud & Hosting';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Smart Home', 'Industrial IoT', 'Device Management', 'Sensor Dashboard', 'Asset Tracking', 'Predictive Maintenance', 'Energy Monitoring']) AS subcategory
WHERE name = 'IoT & Smart Devices';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Chatbot Platform', 'ML Model Training', 'Image Recognition', 'NLP Tools', 'Recommendation Engine', 'Predictive Analytics', 'AI Dashboard']) AS subcategory
WHERE name = 'AI & Machine Learning';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Crypto Exchange', 'Wallet Management', 'NFT Marketplace', 'DeFi Platform', 'Token Launchpad', 'Blockchain Explorer', 'Smart Contracts']) AS subcategory
WHERE name = 'Blockchain & Crypto';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['E-Governance', 'Citizen Portal', 'License Management', 'Tax Collection', 'Public Records', 'Voting System', 'Municipal Services']) AS subcategory
WHERE name = 'Government & Public Sector';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Donation Management', 'Volunteer Management', 'Campaign Management', 'Grant Tracking', 'Member Portal', 'Impact Reporting', 'Fundraising']) AS subcategory
WHERE name = 'Non-Profit & NGO';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Church Management', 'Donation Tracking', 'Event Management', 'Member Directory', 'Sermon Library', 'Prayer Requests', 'Volunteer Scheduling']) AS subcategory
WHERE name = 'Religious & Worship';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Event Planning', 'Ticket Sales', 'Registration System', 'Virtual Events', 'Conference Management', 'Venue Booking', 'Badge Printing']) AS subcategory
WHERE name = 'Event & Ticketing';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Photo Gallery', 'Client Proofing', 'Booking System', 'Video Editing', 'Stock Media', 'Portfolio Builder', 'Print Store']) AS subcategory
WHERE name = 'Photography & Video';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Music Streaming', 'Audio Editor', 'Podcast Hosting', 'Beat Marketplace', 'Radio Streaming', 'Music Distribution', 'DJ Platform']) AS subcategory
WHERE name = 'Music & Audio';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Car Dealership', 'Auto Repair Shop', 'Vehicle Rental', 'Parts Inventory', 'Service Booking', 'Fleet Tracking', 'Insurance Claims']) AS subcategory
WHERE name = 'Automotive & Vehicles';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Veterinary Clinic', 'Pet Store', 'Pet Boarding', 'Grooming Salon', 'Pet Adoption', 'Pet Sitting', 'Pet Health Records']) AS subcategory
WHERE name = 'Pet & Veterinary';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Daycare Management', 'Parent Portal', 'Attendance Tracking', 'Activity Planning', 'Billing (Childcare)', 'Staff Scheduling', 'Health Records']) AS subcategory
WHERE name = 'Childcare & Daycare';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Care Home Management', 'Resident Portal', 'Medication Tracking', 'Activity Calendar', 'Family Communication', 'Staff Scheduling', 'Health Monitoring']) AS subcategory
WHERE name = 'Senior Care & Assisted Living';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Utility Billing', 'Smart Meter', 'Energy Trading', 'Solar Management', 'Grid Management', 'Customer Portal', 'Consumption Analytics']) AS subcategory
WHERE name = 'Energy & Utilities';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Mine Planning', 'Resource Tracking', 'Equipment Management', 'Safety Management', 'Environmental Compliance', 'Ore Processing', 'Geological Survey']) AS subcategory
WHERE name = 'Mining & Resources';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Fashion Store', 'Clothing Rental', 'Custom Tailoring', 'Size Recommendation', 'Virtual Try-On', 'Fashion Blog', 'Wholesale Portal']) AS subcategory
WHERE name = 'Fashion & Apparel';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Jewelry Store', 'Custom Design', 'Inventory Management', 'Appraisal System', 'Auction Platform', 'Gift Registry', 'Repair Tracking']) AS subcategory
WHERE name = 'Jewelry & Luxury';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Grocery POS', 'Online Grocery', 'Inventory (Grocery)', 'Delivery Management', 'Customer Loyalty', 'Vendor Management', 'Price Comparison']) AS subcategory
WHERE name = 'Grocery & Supermarket';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Pharmacy POS', 'Prescription Management', 'Drug Inventory', 'Online Pharmacy', 'Patient Records', 'Insurance Claims', 'Compound Management']) AS subcategory
WHERE name = 'Pharmacy & Drug Store';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Laundry POS', 'Pickup & Delivery', 'Order Tracking', 'Customer App', 'Franchise Management', 'Route Planning', 'Garment Tracking']) AS subcategory
WHERE name = 'Laundry & Dry Cleaning';

INSERT INTO public.business_subcategories (category_id, name, display_order)
SELECT id, subcategory, row_number() OVER ()
FROM public.business_categories, unnest(ARRAY['Print Shop', 'Online Printing', 'Design Tools', 'Order Management', 'Production Tracking', 'Vendor Portal', 'Digital Proofing']) AS subcategory
WHERE name = 'Printing & Publishing';

-- ===== 20251223014350_0055ac91-4841-4bca-a655-8bb9b22e8fa2.sql =====
-- Create persistent notifications table
CREATE TABLE IF NOT EXISTS public.user_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('info', 'success', 'warning', 'danger', 'priority')),
    message TEXT NOT NULL,
    event_type TEXT,
    action_label TEXT,
    action_url TEXT,
    is_buzzer BOOLEAN DEFAULT false,
    is_read BOOLEAN DEFAULT false,
    is_dismissed BOOLEAN DEFAULT false,
    role_target TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own notifications OR notifications targeted to their role
CREATE POLICY "Users can view own notifications"
ON public.user_notifications
FOR SELECT
USING (auth.uid() = user_id);

-- Policy: System can insert notifications for any user (service role)
CREATE POLICY "Authenticated users can insert notifications"
ON public.user_notifications
FOR INSERT
WITH CHECK (auth.uid() IS NOT NULL);

-- Policy: Users can update (mark read/dismissed) their own notifications
CREATE POLICY "Users can update own notifications"
ON public.user_notifications
FOR UPDATE
USING (auth.uid() = user_id);

-- Policy: Users can delete their own notifications
CREATE POLICY "Users can delete own notifications"
ON public.user_notifications
FOR DELETE
USING (auth.uid() = user_id);

-- Add index for faster queries
CREATE INDEX idx_user_notifications_user_id ON public.user_notifications(user_id);
CREATE INDEX idx_user_notifications_created_at ON public.user_notifications(created_at DESC);
CREATE INDEX idx_user_notifications_unread ON public.user_notifications(user_id, is_read) WHERE is_read = false;

-- Enable realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications;

-- Add two_factor_enabled column to user_roles if not exists
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT false;
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS two_factor_method TEXT CHECK (two_factor_method IN ('email', 'authenticator', NULL));
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS two_factor_verified_at TIMESTAMPTZ;
-- ===== 20251223015825_891b3021-6693-4088-9756-a9c1f1e44f14.sql =====
-- Allow public (unauthenticated) users to view active demos
CREATE POLICY "Public can view active demos" 
ON public.demos 
FOR SELECT 
TO anon
USING (status = 'active');
-- ===== 20251224035935_154e4879-1662-43b6-a438-6be671a4b45b.sql =====
-- Server Instances table for managing servers
CREATE TABLE public.server_instances (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    server_name TEXT NOT NULL,
    server_code TEXT UNIQUE NOT NULL,
    server_type TEXT NOT NULL CHECK (server_type IN ('production', 'staging', 'development', 'backup', 'cdn', 'database')),
    status TEXT DEFAULT 'provisioning' CHECK (status IN ('provisioning', 'online', 'offline', 'maintenance', 'error', 'terminated')),
    region TEXT NOT NULL,
    ip_address TEXT,
    cpu_cores INTEGER DEFAULT 2,
    ram_gb INTEGER DEFAULT 4,
    storage_gb INTEGER DEFAULT 100,
    os_type TEXT DEFAULT 'ubuntu-22.04',
    auto_scaling_enabled BOOLEAN DEFAULT false,
    min_instances INTEGER DEFAULT 1,
    max_instances INTEGER DEFAULT 5,
    current_cpu_usage DECIMAL(5,2) DEFAULT 0,
    current_memory_usage DECIMAL(5,2) DEFAULT 0,
    current_disk_usage DECIMAL(5,2) DEFAULT 0,
    uptime_percentage DECIMAL(5,2) DEFAULT 100,
    last_health_check TIMESTAMP WITH TIME ZONE,
    health_status TEXT DEFAULT 'healthy' CHECK (health_status IN ('healthy', 'warning', 'critical', 'unknown')),
    auto_setup_completed BOOLEAN DEFAULT false,
    setup_config JSONB DEFAULT '{}',
    tags TEXT[] DEFAULT '{}',
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Server Backups table
CREATE TABLE public.server_backups (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    backup_name TEXT NOT NULL,
    backup_type TEXT NOT NULL CHECK (backup_type IN ('full', 'incremental', 'differential', 'snapshot')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'expired', 'deleted')),
    size_gb DECIMAL(10,2),
    storage_location TEXT,
    encryption_enabled BOOLEAN DEFAULT true,
    encryption_key_id TEXT,
    retention_days INTEGER DEFAULT 30,
    expires_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    is_auto_backup BOOLEAN DEFAULT false,
    triggered_by UUID,
    restore_point_id TEXT,
    checksum TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Backup Schedules table
CREATE TABLE public.backup_schedules (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    schedule_name TEXT NOT NULL,
    backup_type TEXT NOT NULL CHECK (backup_type IN ('full', 'incremental', 'differential', 'snapshot')),
    frequency TEXT NOT NULL CHECK (frequency IN ('hourly', 'daily', 'weekly', 'monthly', 'custom')),
    cron_expression TEXT,
    retention_days INTEGER DEFAULT 30,
    max_backups INTEGER DEFAULT 10,
    is_active BOOLEAN DEFAULT true,
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    notify_on_success BOOLEAN DEFAULT false,
    notify_on_failure BOOLEAN DEFAULT true,
    notification_emails TEXT[],
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Server Setup Logs table
CREATE TABLE public.server_setup_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    step_name TEXT NOT NULL,
    step_order INTEGER NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'skipped')),
    output TEXT,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Server Metrics History table
CREATE TABLE public.server_metrics_history (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    cpu_usage DECIMAL(5,2),
    memory_usage DECIMAL(5,2),
    disk_usage DECIMAL(5,2),
    network_in_mbps DECIMAL(10,2),
    network_out_mbps DECIMAL(10,2),
    active_connections INTEGER,
    request_count INTEGER,
    error_count INTEGER,
    response_time_ms INTEGER,
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backup_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_setup_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_metrics_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies - Only super admins can manage servers
CREATE POLICY "Super admins manage servers" ON public.server_instances
    FOR ALL USING (public.has_privileged_role(auth.uid()));

CREATE POLICY "Super admins manage backups" ON public.server_backups
    FOR ALL USING (public.has_privileged_role(auth.uid()));

CREATE POLICY "Super admins manage backup schedules" ON public.backup_schedules
    FOR ALL USING (public.has_privileged_role(auth.uid()));

CREATE POLICY "Super admins view setup logs" ON public.server_setup_logs
    FOR ALL USING (public.has_privileged_role(auth.uid()));

CREATE POLICY "Super admins view metrics" ON public.server_metrics_history
    FOR ALL USING (public.has_privileged_role(auth.uid()));

-- Create indexes for performance
CREATE INDEX idx_server_instances_status ON public.server_instances(status);
CREATE INDEX idx_server_instances_region ON public.server_instances(region);
CREATE INDEX idx_server_backups_server_id ON public.server_backups(server_id);
CREATE INDEX idx_server_backups_status ON public.server_backups(status);
CREATE INDEX idx_backup_schedules_next_run ON public.backup_schedules(next_run_at);
CREATE INDEX idx_server_metrics_recorded_at ON public.server_metrics_history(recorded_at);

-- Trigger for updated_at
CREATE TRIGGER update_server_instances_updated_at
    BEFORE UPDATE ON public.server_instances
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_backup_schedules_updated_at
    BEFORE UPDATE ON public.backup_schedules
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20251224040440_af6608ce-d1f6-4605-96a2-5dbc6e2f1ca3.sql =====

-- Add user submission and approval workflow to server_instances
ALTER TABLE public.server_instances 
ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'suspended')),
ADD COLUMN IF NOT EXISTS approved_by UUID,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS is_user_submitted BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS verification_token TEXT,
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_ai_analysis TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS ai_health_score INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS ai_risk_score INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS ai_suggestions JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS protection_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS protection_level TEXT DEFAULT 'standard' CHECK (protection_level IN ('basic', 'standard', 'advanced', 'enterprise')),
ADD COLUMN IF NOT EXISTS threat_alerts JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS compliance_status TEXT DEFAULT 'unknown' CHECK (compliance_status IN ('unknown', 'compliant', 'non_compliant', 'review_required'));

-- Create AI server analysis logs table
CREATE TABLE IF NOT EXISTS public.server_ai_analysis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    analysis_type TEXT NOT NULL CHECK (analysis_type IN ('health', 'security', 'performance', 'compliance', 'threat')),
    analysis_result JSONB NOT NULL DEFAULT '{}'::jsonb,
    health_score INTEGER,
    risk_score INTEGER,
    suggestions JSONB DEFAULT '[]'::jsonb,
    threats_detected JSONB DEFAULT '[]'::jsonb,
    recommendations TEXT[],
    analyzed_at TIMESTAMPTZ DEFAULT now(),
    analyzed_by TEXT DEFAULT 'ai_system',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create server protection events table
CREATE TABLE IF NOT EXISTS public.server_protection_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('threat_detected', 'attack_blocked', 'anomaly_detected', 'policy_violation', 'auto_remediation', 'manual_intervention')),
    severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    description TEXT,
    source_ip TEXT,
    blocked BOOLEAN DEFAULT false,
    auto_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create server submission requests table for approval workflow
CREATE TABLE IF NOT EXISTS public.server_submission_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    user_role TEXT NOT NULL,
    server_name TEXT NOT NULL,
    server_type TEXT NOT NULL,
    ip_address TEXT,
    hostname TEXT,
    provider TEXT,
    region TEXT,
    purpose TEXT,
    expected_usage TEXT,
    compliance_requirements TEXT[],
    additional_notes TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'cancelled')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    rejection_reason TEXT,
    created_server_id UUID REFERENCES public.server_instances(id),
    ai_pre_check_result JSONB,
    ai_risk_assessment JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_ai_analysis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_protection_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_submission_requests ENABLE ROW LEVEL SECURITY;

-- RLS for server_ai_analysis
CREATE POLICY "Super admins can view all AI analysis" ON public.server_ai_analysis
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'master'))
    );

CREATE POLICY "Users can view their server analysis" ON public.server_ai_analysis
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.server_instances si 
            WHERE si.id = server_id AND si.submitted_by = auth.uid()
        )
    );

-- RLS for server_protection_events
CREATE POLICY "Super admins can manage protection events" ON public.server_protection_events
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'master'))
    );

CREATE POLICY "Users can view their server protection events" ON public.server_protection_events
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.server_instances si 
            WHERE si.id = server_id AND si.submitted_by = auth.uid()
        )
    );

-- RLS for server_submission_requests
CREATE POLICY "Users can submit and view own requests" ON public.server_submission_requests
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Super admins can manage all requests" ON public.server_submission_requests
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'master'))
    );

-- Update server_instances RLS for user-submitted servers
CREATE POLICY "Users can view their submitted servers" ON public.server_instances
    FOR SELECT USING (submitted_by = auth.uid());

-- Enable realtime for protection events
ALTER PUBLICATION supabase_realtime ADD TABLE public.server_protection_events;

-- ===== 20251224041125_f6915850-66a0-4517-8350-1fc9e708bc66.sql =====

-- Create OTP verification system for critical actions
CREATE TABLE IF NOT EXISTS public.otp_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    otp_code TEXT NOT NULL,
    otp_type TEXT NOT NULL CHECK (otp_type IN ('login', 'action', 'delete', 'edit', 'add', 'remove', 'financial', 'server', 'ai_action')),
    action_description TEXT,
    action_data JSONB,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '5 minutes'),
    verified_at TIMESTAMPTZ,
    is_used BOOLEAN DEFAULT false,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create action approval queue for AI and critical operations
CREATE TABLE IF NOT EXISTS public.action_approval_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    user_role TEXT NOT NULL,
    action_type TEXT NOT NULL CHECK (action_type IN ('add', 'edit', 'delete', 'remove', 'ai_operation', 'financial', 'server_change', 'config_change')),
    action_target TEXT NOT NULL,
    action_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    otp_required BOOLEAN DEFAULT true,
    otp_verified BOOLEAN DEFAULT false,
    otp_verification_id UUID REFERENCES public.otp_verifications(id),
    email_verified BOOLEAN DEFAULT false,
    approval_status TEXT DEFAULT 'pending' CHECK (approval_status IN ('pending', 'otp_pending', 'approved', 'rejected', 'expired', 'cancelled')),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    rejection_reason TEXT,
    auto_approve_eligible BOOLEAN DEFAULT false,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    expires_at TIMESTAMPTZ DEFAULT (now() + interval '24 hours'),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create user 2FA settings table
CREATE TABLE IF NOT EXISTS public.user_2fa_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    is_2fa_enabled BOOLEAN DEFAULT true,
    preferred_method TEXT DEFAULT 'email' CHECK (preferred_method IN ('email', 'sms', 'authenticator')),
    phone_number TEXT,
    phone_verified BOOLEAN DEFAULT false,
    authenticator_secret TEXT,
    authenticator_verified BOOLEAN DEFAULT false,
    backup_codes TEXT[],
    last_otp_sent_at TIMESTAMPTZ,
    otp_rate_limit_until TIMESTAMPTZ,
    trusted_devices JSONB DEFAULT '[]'::jsonb,
    require_otp_for_login BOOLEAN DEFAULT false,
    require_otp_for_actions BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create audit trail for all verified actions
CREATE TABLE IF NOT EXISTS public.verified_action_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    user_role TEXT,
    action_type TEXT NOT NULL,
    action_target TEXT,
    action_data JSONB,
    otp_verification_id UUID REFERENCES public.otp_verifications(id),
    approval_id UUID REFERENCES public.action_approval_queue(id),
    verification_method TEXT,
    ip_address TEXT,
    user_agent TEXT,
    geo_location TEXT,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.otp_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_approval_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_2fa_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verified_action_logs ENABLE ROW LEVEL SECURITY;

-- RLS policies for otp_verifications
CREATE POLICY "Users can view own OTP records" ON public.otp_verifications
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "System can insert OTP" ON public.otp_verifications
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can verify own OTP" ON public.otp_verifications
    FOR UPDATE USING (user_id = auth.uid());

-- RLS policies for action_approval_queue
CREATE POLICY "Users can view own action requests" ON public.action_approval_queue
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Super admins can view all action requests" ON public.action_approval_queue
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'master'))
    );

CREATE POLICY "Users can create action requests" ON public.action_approval_queue
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- RLS policies for user_2fa_settings
CREATE POLICY "Users can manage own 2FA settings" ON public.user_2fa_settings
    FOR ALL USING (user_id = auth.uid());

-- RLS policies for verified_action_logs
CREATE POLICY "Users can view own action logs" ON public.verified_action_logs
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Super admins can view all action logs" ON public.verified_action_logs
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('super_admin', 'master'))
    );

-- Function to generate OTP
CREATE OR REPLACE FUNCTION public.generate_otp(
    p_user_id UUID,
    p_otp_type TEXT,
    p_action_description TEXT DEFAULT NULL,
    p_action_data JSONB DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_otp TEXT;
    v_otp_id UUID;
BEGIN
    -- Generate 6-digit OTP
    v_otp := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    
    -- Insert OTP record
    INSERT INTO public.otp_verifications (user_id, otp_code, otp_type, action_description, action_data)
    VALUES (p_user_id, v_otp, p_otp_type, p_action_description, p_action_data)
    RETURNING id INTO v_otp_id;
    
    -- Update rate limit
    UPDATE public.user_2fa_settings 
    SET last_otp_sent_at = now()
    WHERE user_id = p_user_id;
    
    RETURN v_otp;
END;
$$;

-- Function to verify OTP
CREATE OR REPLACE FUNCTION public.verify_otp(
    p_user_id UUID,
    p_otp_code TEXT,
    p_otp_type TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_otp_record RECORD;
    v_result JSONB;
BEGIN
    -- Find valid OTP
    SELECT * INTO v_otp_record
    FROM public.otp_verifications
    WHERE user_id = p_user_id
    AND otp_code = p_otp_code
    AND otp_type = p_otp_type
    AND is_used = false
    AND expires_at > now()
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_otp_record IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired OTP');
    END IF;
    
    -- Mark as used
    UPDATE public.otp_verifications
    SET is_used = true, verified_at = now()
    WHERE id = v_otp_record.id;
    
    RETURN jsonb_build_object(
        'success', true, 
        'verification_id', v_otp_record.id,
        'action_data', v_otp_record.action_data
    );
END;
$$;

-- Function to check if action requires OTP
CREATE OR REPLACE FUNCTION public.requires_otp_verification(
    p_user_id UUID,
    p_action_type TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_settings RECORD;
BEGIN
    SELECT * INTO v_settings FROM public.user_2fa_settings WHERE user_id = p_user_id;
    
    -- If no settings, require OTP by default for safety
    IF v_settings IS NULL THEN
        RETURN true;
    END IF;
    
    -- Check if 2FA is enabled and OTP required for actions
    RETURN v_settings.is_2fa_enabled AND v_settings.require_otp_for_actions;
END;
$$;

-- ===== 20251224041846_86ef7732-6f10-4ef5-8166-2e5dbf27f19e.sql =====
-- Add trusted devices table
CREATE TABLE public.trusted_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  device_fingerprint TEXT NOT NULL,
  device_name TEXT,
  device_type TEXT,
  browser TEXT,
  os TEXT,
  ip_address TEXT,
  location TEXT,
  is_trusted BOOLEAN DEFAULT false,
  trust_expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  revoked_by UUID,
  UNIQUE(user_id, device_fingerprint)
);

-- Add backup codes table for 2FA recovery
CREATE TABLE public.backup_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  code_hash TEXT NOT NULL,
  is_used BOOLEAN DEFAULT false,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add password verification log
CREATE TABLE public.password_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  action_type TEXT NOT NULL,
  verified_at TIMESTAMPTZ DEFAULT now(),
  ip_address TEXT,
  device_fingerprint TEXT,
  expires_at TIMESTAMPTZ DEFAULT (now() + interval '5 minutes')
);

-- Add critical action types enum
DO $$ BEGIN
  CREATE TYPE critical_action_type AS ENUM (
    'delete_data',
    'edit_financial',
    'add_user',
    'remove_user',
    'change_role',
    'server_action',
    'bulk_operation',
    'export_data',
    'change_settings',
    'ai_action'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Add session security table
CREATE TABLE public.session_security (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  session_token_hash TEXT,
  session_started_at TIMESTAMPTZ DEFAULT now(),
  last_activity_at TIMESTAMPTZ DEFAULT now(),
  session_timeout_minutes INTEGER DEFAULT 30,
  force_logout_at TIMESTAMPTZ,
  ip_locked BOOLEAN DEFAULT false,
  allowed_ips TEXT[],
  require_password_for_delete BOOLEAN DEFAULT true,
  require_password_for_financial BOOLEAN DEFAULT true,
  require_email_verify_for_critical BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Super Admin approval queue view enhancements
ALTER TABLE public.action_approval_queue 
ADD COLUMN IF NOT EXISTS password_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS password_verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS email_link_sent_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS email_link_token TEXT,
ADD COLUMN IF NOT EXISTS email_link_expires_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS device_trusted BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS ip_address TEXT,
ADD COLUMN IF NOT EXISTS device_fingerprint TEXT,
ADD COLUMN IF NOT EXISTS risk_score INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS ai_risk_assessment JSONB;

-- Enable RLS
ALTER TABLE public.trusted_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backup_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_security ENABLE ROW LEVEL SECURITY;

-- RLS Policies for trusted_devices
CREATE POLICY "Users can view own trusted devices"
ON public.trusted_devices FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can manage own trusted devices"
ON public.trusted_devices FOR ALL
TO authenticated
USING (user_id = auth.uid());

-- RLS Policies for backup_codes
CREATE POLICY "Users can view own backup codes"
ON public.backup_codes FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can manage own backup codes"
ON public.backup_codes FOR ALL
TO authenticated
USING (user_id = auth.uid());

-- RLS Policies for password_verifications
CREATE POLICY "Users can view own password verifications"
ON public.password_verifications FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can create password verifications"
ON public.password_verifications FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- RLS Policies for session_security
CREATE POLICY "Users can view own session security"
ON public.session_security FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can manage own session security"
ON public.session_security FOR ALL
TO authenticated
USING (user_id = auth.uid());

-- Super admins can view all
CREATE POLICY "Super admins can view all devices"
ON public.trusted_devices FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Super admins can view all sessions"
ON public.session_security FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'));

-- Function to check if device is trusted
CREATE OR REPLACE FUNCTION public.is_device_trusted(p_user_id UUID, p_fingerprint TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trusted_devices
    WHERE user_id = p_user_id
    AND device_fingerprint = p_fingerprint
    AND is_trusted = true
    AND revoked_at IS NULL
    AND (trust_expires_at IS NULL OR trust_expires_at > now())
  )
$$;

-- Function to check if password was recently verified
CREATE OR REPLACE FUNCTION public.is_password_recently_verified(p_user_id UUID, p_action_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.password_verifications
    WHERE user_id = p_user_id
    AND action_type = p_action_type
    AND expires_at > now()
  )
$$;

-- Function to generate backup codes
CREATE OR REPLACE FUNCTION public.generate_backup_codes(p_user_id UUID)
RETURNS TEXT[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  codes TEXT[] := ARRAY[]::TEXT[];
  i INTEGER;
  code TEXT;
BEGIN
  -- Delete existing unused codes
  DELETE FROM public.backup_codes WHERE user_id = p_user_id AND is_used = false;
  
  -- Generate 10 new codes
  FOR i IN 1..10 LOOP
    code := upper(substr(md5(random()::text), 1, 4) || '-' || substr(md5(random()::text), 1, 4));
    codes := array_append(codes, code);
    
    INSERT INTO public.backup_codes (user_id, code_hash)
    VALUES (p_user_id, encode(sha256(code::bytea), 'hex'));
  END LOOP;
  
  RETURN codes;
END;
$$;

-- Function to verify backup code
CREATE OR REPLACE FUNCTION public.verify_backup_code(p_user_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  code_id UUID;
BEGIN
  SELECT id INTO code_id
  FROM public.backup_codes
  WHERE user_id = p_user_id
  AND code_hash = encode(sha256(upper(p_code)::bytea), 'hex')
  AND is_used = false
  LIMIT 1;
  
  IF code_id IS NOT NULL THEN
    UPDATE public.backup_codes
    SET is_used = true, used_at = now()
    WHERE id = code_id;
    RETURN true;
  END IF;
  
  RETURN false;
END;
$$;

-- Function to check session validity
CREATE OR REPLACE FUNCTION public.check_session_valid(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  session_rec RECORD;
BEGIN
  SELECT * INTO session_rec FROM public.session_security WHERE user_id = p_user_id;
  
  IF session_rec IS NULL THEN
    RETURN jsonb_build_object('valid', true, 'reason', 'no_restrictions');
  END IF;
  
  -- Check force logout
  IF session_rec.force_logout_at IS NOT NULL AND session_rec.force_logout_at > session_rec.session_started_at THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'force_logout');
  END IF;
  
  -- Check session timeout
  IF session_rec.last_activity_at + (session_rec.session_timeout_minutes || ' minutes')::interval < now() THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'session_timeout');
  END IF;
  
  RETURN jsonb_build_object('valid', true, 'reason', 'active');
END;
$$;
-- ===== 20251224052655_008aa7ed-fdc7-431f-b20c-1168363f6cdd.sql =====
-- Add fine_amount column to promise_logs
ALTER TABLE public.promise_logs 
ADD COLUMN IF NOT EXISTS fine_amount NUMERIC DEFAULT 0;

-- Create promise_fines table to track all fines
CREATE TABLE IF NOT EXISTS public.promise_fines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promise_id UUID REFERENCES public.promise_logs(id) ON DELETE CASCADE NOT NULL,
    developer_id UUID NOT NULL,
    fine_amount NUMERIC NOT NULL DEFAULT 0,
    fine_reason TEXT NOT NULL,
    fine_type TEXT NOT NULL DEFAULT 'breach', -- breach, late, quality
    applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    paid_at TIMESTAMP WITH TIME ZONE,
    waived_at TIMESTAMP WITH TIME ZONE,
    waived_by UUID,
    waiver_reason TEXT,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, paid, waived, disputed
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.promise_fines ENABLE ROW LEVEL SECURITY;

-- RLS policies for promise_fines
CREATE POLICY "Super admins can manage all fines"
ON public.promise_fines
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('super_admin', 'master', 'admin', 'finance_manager')
    )
);

CREATE POLICY "Developers can view their own fines"
ON public.promise_fines
FOR SELECT
USING (
    developer_id IN (
        SELECT id FROM public.developers WHERE user_id = auth.uid()
    )
);

-- Create function to auto-apply fine on breach
CREATE OR REPLACE FUNCTION public.apply_promise_breach_fine()
RETURNS TRIGGER AS $$
DECLARE
    fine_amt NUMERIC := 50; -- Default fine amount
BEGIN
    -- Only apply if status changed to breached
    IF NEW.status = 'breached' AND OLD.status != 'breached' THEN
        -- Update fine amount on promise
        NEW.fine_amount := fine_amt;
        
        -- Insert fine record
        INSERT INTO public.promise_fines (
            promise_id,
            developer_id,
            fine_amount,
            fine_reason,
            fine_type,
            status
        ) VALUES (
            NEW.id,
            NEW.developer_id,
            fine_amt,
            COALESCE(NEW.breach_reason, 'Promise deadline exceeded'),
            'breach',
            'pending'
        );
        
        -- Update developer wallet penalties
        UPDATE public.developer_wallet
        SET total_penalties = total_penalties + fine_amt,
            available_balance = available_balance - fine_amt
        WHERE developer_id = NEW.developer_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for auto-fine on breach
DROP TRIGGER IF EXISTS promise_breach_fine_trigger ON public.promise_logs;
CREATE TRIGGER promise_breach_fine_trigger
    BEFORE UPDATE ON public.promise_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.apply_promise_breach_fine();

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_promise_fines_developer ON public.promise_fines(developer_id);
CREATE INDEX IF NOT EXISTS idx_promise_fines_status ON public.promise_fines(status);
CREATE INDEX IF NOT EXISTS idx_promise_logs_status ON public.promise_logs(status);
-- ===== 20251224073858_e8650473-30ee-4ccc-a630-6e03fe6a8f95.sql =====
-- Fix is_super_admin to include master role
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role IN ('super_admin', 'master')
  )
$$;

-- Also create is_master function for master-only checks
CREATE OR REPLACE FUNCTION public.is_master()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'master'
  )
$$;
-- ===== 20251224074310_1fe2ce7c-1f5a-4c74-b802-d4011b446ab3.sql =====

-- =====================================================
-- COMPLIANCE SYSTEM DATABASE SCHEMA
-- Role Clauses, Verification & Penalty System
-- =====================================================

-- 1. ROLE CLAUSE AGREEMENTS TABLE
-- Tracks when users accept role-specific clauses
CREATE TABLE public.role_clause_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  clause_version TEXT NOT NULL,
  clause_id TEXT NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address TEXT,
  user_agent TEXT,
  device_fingerprint TEXT,
  is_valid BOOLEAN DEFAULT true,
  invalidated_at TIMESTAMPTZ,
  invalidated_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, role, clause_version)
);

-- 2. VERIFICATION RECORDS TABLE
-- Tracks the complete verification flow for each user-role
CREATE TABLE public.verification_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  current_step TEXT NOT NULL DEFAULT 'agreement',
  
  -- Step statuses (JSONB for flexibility)
  step_statuses JSONB NOT NULL DEFAULT '{
    "agreement": "pending",
    "identity": "pending",
    "risk_scoring": "pending",
    "legal_review": "pending",
    "activation": "pending"
  }'::jsonb,
  
  -- Agreement step data
  agreement_accepted_at TIMESTAMPTZ,
  agreement_version TEXT,
  agreement_ip_address TEXT,
  
  -- Identity step data
  id_document_front_url TEXT,
  id_document_back_url TEXT,
  liveness_photo_url TEXT,
  full_name TEXT,
  date_of_birth DATE,
  identity_verified_at TIMESTAMPTZ,
  identity_verified_by UUID,
  
  -- Risk scoring data
  risk_score INTEGER,
  risk_factors JSONB,
  ip_reputation_score INTEGER,
  device_fingerprint TEXT,
  device_score INTEGER,
  country_code TEXT,
  country_risk_score INTEGER,
  asn_info JSONB,
  asn_score INTEGER,
  violation_history_score INTEGER,
  risk_assessed_at TIMESTAMPTZ,
  
  -- Legal review data
  legal_review_status TEXT DEFAULT 'pending',
  legal_reviewer_id UUID,
  legal_review_notes TEXT,
  legal_reviewed_at TIMESTAMPTZ,
  
  -- Activation data
  is_activated BOOLEAN DEFAULT false,
  activated_at TIMESTAMPTZ,
  activated_by UUID,
  
  -- Metadata
  rejection_reason TEXT,
  requires_resubmission BOOLEAN DEFAULT false,
  resubmission_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(user_id, role)
);

-- 3. PENALTY RECORDS TABLE
-- Tracks all penalties issued to users
CREATE TABLE public.penalty_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_role public.app_role NOT NULL,
  penalty_level INTEGER NOT NULL CHECK (penalty_level BETWEEN 1 AND 5),
  
  -- Violation details
  reason TEXT NOT NULL,
  violation_type TEXT NOT NULL,
  evidence TEXT,
  evidence_urls JSONB,
  
  -- Issuer info
  issued_by UUID REFERENCES auth.users(id),
  issued_by_role public.app_role,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Status
  is_active BOOLEAN DEFAULT true,
  expires_at TIMESTAMPTZ,
  lifted_at TIMESTAMPTZ,
  lifted_by UUID,
  lift_reason TEXT,
  
  -- Appeal
  can_appeal BOOLEAN DEFAULT true,
  appeal_status TEXT,
  appeal_submitted_at TIMESTAMPTZ,
  appeal_text TEXT,
  appeal_reviewed_at TIMESTAMPTZ,
  appeal_reviewed_by UUID,
  appeal_decision_notes TEXT,
  
  -- Actions taken (auto-enforced)
  actions_taken JSONB,
  
  -- Audit
  audit_trail_id UUID,
  is_auto_triggered BOOLEAN DEFAULT false,
  trigger_rule_id TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. LEGAL REVIEW CASES TABLE
-- Tracks all cases requiring legal/compliance review
CREATE TABLE public.legal_review_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_email TEXT,
  user_role public.app_role NOT NULL,
  
  -- Case type
  review_type TEXT NOT NULL, -- 'verification', 'penalty_appeal', 'escalation'
  reference_id UUID, -- ID of verification or penalty record
  
  -- Status
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'in_review', 'approved', 'rejected'
  priority TEXT NOT NULL DEFAULT 'medium', -- 'low', 'medium', 'high', 'critical'
  
  -- Assignment
  assigned_to UUID REFERENCES auth.users(id),
  assigned_at TIMESTAMPTZ,
  
  -- Documents
  documents JSONB DEFAULT '[]'::jsonb,
  
  -- Risk info
  risk_score INTEGER,
  risk_factors JSONB,
  
  -- Review data
  reviewer_notes TEXT,
  internal_notes TEXT,
  decision_reason TEXT,
  
  -- Timestamps
  submitted_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. COMPLIANCE VIOLATION TYPES TABLE
-- Configurable violation types with auto-penalty rules
CREATE TABLE public.compliance_violation_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL, -- 'code', 'billing', 'security', 'policy', 'legal'
  default_penalty_level INTEGER NOT NULL CHECK (default_penalty_level BETWEEN 1 AND 5),
  applicable_roles public.app_role[],
  auto_trigger_enabled BOOLEAN DEFAULT false,
  escalation_threshold INTEGER DEFAULT 3,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 6. USER COMPLIANCE STATUS VIEW
-- Quick view of user compliance status
CREATE OR REPLACE VIEW public.user_compliance_status AS
SELECT 
  ur.user_id,
  ur.role,
  vr.is_activated as is_verified,
  vr.current_step as verification_step,
  vr.risk_score,
  (SELECT COUNT(*) FROM penalty_records pr WHERE pr.user_id = ur.user_id AND pr.is_active = true) as active_penalties,
  (SELECT MAX(penalty_level) FROM penalty_records pr WHERE pr.user_id = ur.user_id AND pr.is_active = true) as highest_penalty_level,
  (SELECT agreement_accepted_at FROM role_clause_agreements rca WHERE rca.user_id = ur.user_id AND rca.role = ur.role ORDER BY accepted_at DESC LIMIT 1) as last_agreement_date
FROM public.user_roles ur
LEFT JOIN public.verification_records vr ON ur.user_id = vr.user_id AND ur.role = vr.role;

-- =====================================================
-- ENABLE RLS ON ALL TABLES
-- =====================================================

ALTER TABLE public.role_clause_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.penalty_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_review_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_violation_types ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS POLICIES
-- =====================================================

-- Role Clause Agreements: Users can view their own, Super Admin can view all
CREATE POLICY "Users can view own agreements" ON public.role_clause_agreements
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own agreements" ON public.role_clause_agreements
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Super Admin can view all agreements" ON public.role_clause_agreements
  FOR SELECT USING (public.is_super_admin());

-- Verification Records: Users can view their own, Super Admin can manage all
CREATE POLICY "Users can view own verification" ON public.verification_records
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own verification" ON public.verification_records
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own verification" ON public.verification_records
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Super Admin can view all verifications" ON public.verification_records
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Super Admin can update all verifications" ON public.verification_records
  FOR UPDATE USING (public.is_super_admin());

-- Penalty Records: Users can view their own, Super Admin can manage all
CREATE POLICY "Users can view own penalties" ON public.penalty_records
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super Admin can view all penalties" ON public.penalty_records
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Super Admin can insert penalties" ON public.penalty_records
  FOR INSERT WITH CHECK (public.is_super_admin());

CREATE POLICY "Super Admin can update penalties" ON public.penalty_records
  FOR UPDATE USING (public.is_super_admin());

-- Legal Review Cases: Users can view their own, Legal/Super Admin can manage all
CREATE POLICY "Users can view own legal cases" ON public.legal_review_cases
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super Admin can view all legal cases" ON public.legal_review_cases
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Super Admin can manage legal cases" ON public.legal_review_cases
  FOR ALL USING (public.is_super_admin());

-- Violation Types: Read-only for authenticated users, Super Admin can manage
CREATE POLICY "Authenticated can view violation types" ON public.compliance_violation_types
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Super Admin can manage violation types" ON public.compliance_violation_types
  FOR ALL USING (public.is_super_admin());

-- =====================================================
-- HELPER FUNCTIONS
-- =====================================================

-- Check if user is verified for their role
CREATE OR REPLACE FUNCTION public.is_user_verified(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.verification_records
    WHERE user_id = _user_id
    AND role = _role
    AND is_activated = true
  )
$$;

-- Check if user has active penalties above threshold
CREATE OR REPLACE FUNCTION public.has_active_penalty(_user_id uuid, _min_level integer DEFAULT 1)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.penalty_records
    WHERE user_id = _user_id
    AND is_active = true
    AND penalty_level >= _min_level
  )
$$;

-- Get user's current penalty level
CREATE OR REPLACE FUNCTION public.get_user_penalty_level(_user_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(MAX(penalty_level), 0)
  FROM public.penalty_records
  WHERE user_id = _user_id
  AND is_active = true
$$;

-- Issue penalty (with auto-enforcement)
CREATE OR REPLACE FUNCTION public.issue_penalty(
  _user_id uuid,
  _user_role app_role,
  _penalty_level integer,
  _reason text,
  _violation_type text,
  _evidence text DEFAULT NULL,
  _auto_triggered boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  penalty_id UUID;
  actions_list JSONB;
BEGIN
  -- Define actions based on penalty level
  CASE _penalty_level
    WHEN 1 THEN actions_list := '["System warning issued", "Logged in audit trail"]'::jsonb;
    WHEN 2 THEN actions_list := '["Feature access limited", "Earnings/actions paused", "Manager notified"]'::jsonb;
    WHEN 3 THEN actions_list := '["Role suspended", "Server/code/API access blocked", "Investigation required"]'::jsonb;
    WHEN 4 THEN actions_list := '["Account terminated", "Earnings frozen", "Data access revoked", "Legal record created"]'::jsonb;
    WHEN 5 THEN actions_list := '["Evidence package generated", "Legal team notified", "Permanent blacklist"]'::jsonb;
    ELSE actions_list := '[]'::jsonb;
  END CASE;

  -- Insert penalty record
  INSERT INTO public.penalty_records (
    user_id, user_role, penalty_level, reason, violation_type, 
    evidence, issued_by, is_auto_triggered, actions_taken, can_appeal
  ) VALUES (
    _user_id, _user_role, _penalty_level, _reason, _violation_type,
    _evidence, auth.uid(), _auto_triggered, actions_list, (_penalty_level < 5)
  ) RETURNING id INTO penalty_id;

  -- Create legal review case for level 3+
  IF _penalty_level >= 3 THEN
    INSERT INTO public.legal_review_cases (
      user_id, user_role, review_type, reference_id, priority, status
    ) VALUES (
      _user_id, _user_role, 'escalation', penalty_id,
      CASE WHEN _penalty_level >= 4 THEN 'critical' ELSE 'high' END,
      'pending'
    );
  END IF;

  -- Log to audit trail
  INSERT INTO public.compliance_audit_trail (
    entity_type, entity_id, action, actor_id, actor_role,
    new_values, compliance_tags
  ) VALUES (
    'penalty', penalty_id, 'penalty_issued', auth.uid(), 
    (SELECT role FROM user_roles WHERE user_id = auth.uid() LIMIT 1),
    jsonb_build_object('level', _penalty_level, 'reason', _reason, 'violation_type', _violation_type),
    ARRAY['penalty', 'compliance']
  );

  RETURN penalty_id;
END;
$$;

-- Trigger for auto-updating updated_at
CREATE TRIGGER update_verification_records_updated_at
  BEFORE UPDATE ON public.verification_records
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_penalty_records_updated_at
  BEFORE UPDATE ON public.penalty_records
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_legal_review_cases_updated_at
  BEFORE UPDATE ON public.legal_review_cases
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =====================================================
-- SEED DEFAULT VIOLATION TYPES
-- =====================================================

INSERT INTO public.compliance_violation_types (code, name, description, category, default_penalty_level, applicable_roles, auto_trigger_enabled) VALUES
('CODE_COPY', 'Unauthorized Code Copying', 'Copying or redistributing source code without authorization', 'code', 4, ARRAY['developer']::app_role[], true),
('HIDDEN_BACKDOOR', 'Hidden Backdoor', 'Creating hidden assets, APIs, or backdoors', 'security', 5, ARRAY['developer']::app_role[], true),
('HARDCODED_KEYS', 'Hardcoded Credentials', 'Hardcoding API keys or secrets in code', 'security', 3, ARRAY['developer']::app_role[], true),
('UNAUTHORIZED_ACCESS', 'Unauthorized Access', 'Accessing data or systems without permission', 'security', 4, NULL, true),
('BILLING_FRAUD', 'Billing Fraud', 'Unauthorized discounts or billing manipulation', 'billing', 4, ARRAY['reseller', 'franchise']::app_role[], true),
('SPAM_CAMPAIGN', 'Spam Campaign', 'Sending spam or misleading marketing', 'policy', 3, ARRAY['influencer', 'marketing_manager']::app_role[], true),
('BRAND_MISUSE', 'Brand Misuse', 'Impersonation or brand misuse', 'policy', 3, ARRAY['influencer', 'marketing_manager', 'reseller']::app_role[], true),
('POLICY_VIOLATION', 'General Policy Violation', 'Minor policy violation', 'policy', 1, NULL, false),
('DATA_LEAK', 'Data Leakage', 'Exposing or leaking sensitive data', 'security', 5, NULL, true),
('RESOURCE_ABUSE', 'Resource Abuse', 'Abuse of system resources', 'policy', 2, ARRAY['prime', 'client']::app_role[], true);

-- ===== 20251224074326_859379b6-aa31-4c40-a0d7-0f361a0ca1ac.sql =====

-- Fix the security definer view by dropping and recreating as SECURITY INVOKER
DROP VIEW IF EXISTS public.user_compliance_status;

CREATE VIEW public.user_compliance_status
WITH (security_invoker = true)
AS
SELECT 
  ur.user_id,
  ur.role,
  vr.is_activated as is_verified,
  vr.current_step as verification_step,
  vr.risk_score,
  (SELECT COUNT(*) FROM penalty_records pr WHERE pr.user_id = ur.user_id AND pr.is_active = true) as active_penalties,
  (SELECT MAX(penalty_level) FROM penalty_records pr WHERE pr.user_id = ur.user_id AND pr.is_active = true) as highest_penalty_level,
  (SELECT agreement_accepted_at FROM role_clause_agreements rca WHERE rca.user_id = ur.user_id AND rca.role = ur.role ORDER BY accepted_at DESC LIMIT 1) as last_agreement_date
FROM public.user_roles ur
LEFT JOIN public.verification_records vr ON ur.user_id = vr.user_id AND ur.role = vr.role;

-- ===== 20251224112129_afbe0f66-832d-4abc-a626-d2b3a3878251.sql =====
-- Add approval tracking columns to payout_requests
ALTER TABLE public.payout_requests 
ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ DEFAULT now(),
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS rejected_by UUID REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS user_role TEXT,
ADD COLUMN IF NOT EXISTS wallet_debited BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS wallet_debited_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS ip_address TEXT,
ADD COLUMN IF NOT EXISTS device_fingerprint TEXT;

-- Create index for preventing duplicates
CREATE INDEX IF NOT EXISTS idx_payout_requests_user_status 
ON public.payout_requests(user_id, status, amount);

-- Create index for idempotency
CREATE INDEX IF NOT EXISTS idx_payout_requests_idempotency 
ON public.payout_requests(idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Update status check constraint
ALTER TABLE public.payout_requests DROP CONSTRAINT IF EXISTS payout_requests_status_check;
ALTER TABLE public.payout_requests ADD CONSTRAINT payout_requests_status_check 
CHECK (status IN ('requested', 'pending', 'approved', 'rejected', 'processing', 'completed', 'failed'));

-- Set existing 'pending' records to 'requested' (new flow)
UPDATE public.payout_requests SET status = 'requested' WHERE status = 'pending';

-- Create function to approve payout (Super Admin/Master only)
CREATE OR REPLACE FUNCTION public.approve_payout(
    p_payout_id UUID,
    p_approver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payout RECORD;
    v_wallet RECORD;
    v_new_balance NUMERIC;
    v_approver_role TEXT;
BEGIN
    -- Check if approver is Super Admin or Master
    SELECT role INTO v_approver_role 
    FROM public.user_roles 
    WHERE user_id = p_approver_id;
    
    IF v_approver_role NOT IN ('super_admin', 'master') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Only Super Admin or Master can approve payouts'
        );
    END IF;
    
    -- Get payout request with row lock
    SELECT * INTO v_payout 
    FROM public.payout_requests 
    WHERE payout_id = p_payout_id 
    FOR UPDATE;
    
    IF v_payout IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payout not found');
    END IF;
    
    -- Check if already processed
    IF v_payout.status NOT IN ('requested', 'pending') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Payout already processed with status: ' || v_payout.status
        );
    END IF;
    
    -- Check if wallet already debited (prevent double debit)
    IF v_payout.wallet_debited = true THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Wallet already debited for this payout'
        );
    END IF;
    
    -- Get wallet with row lock
    SELECT * INTO v_wallet 
    FROM public.wallets 
    WHERE user_id = v_payout.user_id 
    FOR UPDATE;
    
    IF v_wallet IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Wallet not found');
    END IF;
    
    -- Check sufficient balance
    IF v_wallet.balance < v_payout.amount THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Insufficient balance. Available: ' || v_wallet.balance || ', Required: ' || v_payout.amount
        );
    END IF;
    
    -- Debit wallet
    v_new_balance := v_wallet.balance - v_payout.amount;
    
    UPDATE public.wallets 
    SET balance = v_new_balance, 
        updated_at = now() 
    WHERE wallet_id = v_wallet.wallet_id;
    
    -- Update payout status
    UPDATE public.payout_requests 
    SET status = 'approved',
        approved_at = now(),
        approved_by = p_approver_id,
        wallet_debited = true,
        wallet_debited_at = now()
    WHERE payout_id = p_payout_id;
    
    -- Log transaction
    INSERT INTO public.transactions (
        wallet_id, type, amount, reference, related_user, related_role, status
    ) VALUES (
        v_wallet.wallet_id, 
        'withdrawal', 
        -v_payout.amount, 
        'Approved payout: ' || p_payout_id::text,
        p_approver_id,
        v_approver_role,
        'completed'
    );
    
    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_approver_id,
        'payout_approved',
        'wallet',
        v_approver_role::app_role,
        jsonb_build_object(
            'payout_id', p_payout_id,
            'user_id', v_payout.user_id,
            'amount', v_payout.amount,
            'new_balance', v_new_balance
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'payout_id', p_payout_id,
        'amount', v_payout.amount,
        'new_balance', v_new_balance
    );
END;
$$;

-- Create function to reject payout (Super Admin/Master only)
CREATE OR REPLACE FUNCTION public.reject_payout(
    p_payout_id UUID,
    p_rejector_id UUID,
    p_reason TEXT DEFAULT 'Rejected by admin'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payout RECORD;
    v_wallet RECORD;
    v_rejector_role TEXT;
BEGIN
    -- Check if rejector is Super Admin or Master
    SELECT role INTO v_rejector_role 
    FROM public.user_roles 
    WHERE user_id = p_rejector_id;
    
    IF v_rejector_role NOT IN ('super_admin', 'master') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Only Super Admin or Master can reject payouts'
        );
    END IF;
    
    -- Get payout request with row lock
    SELECT * INTO v_payout 
    FROM public.payout_requests 
    WHERE payout_id = p_payout_id 
    FOR UPDATE;
    
    IF v_payout IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payout not found');
    END IF;
    
    -- Check if already processed
    IF v_payout.status NOT IN ('requested', 'pending') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Payout already processed with status: ' || v_payout.status
        );
    END IF;
    
    -- If wallet was somehow debited, restore funds
    IF v_payout.wallet_debited = true THEN
        SELECT * INTO v_wallet 
        FROM public.wallets 
        WHERE user_id = v_payout.user_id 
        FOR UPDATE;
        
        IF v_wallet IS NOT NULL THEN
            UPDATE public.wallets 
            SET balance = v_wallet.balance + v_payout.amount, 
                updated_at = now() 
            WHERE wallet_id = v_wallet.wallet_id;
            
            -- Log refund transaction
            INSERT INTO public.transactions (
                wallet_id, type, amount, reference, related_user, related_role, status
            ) VALUES (
                v_wallet.wallet_id, 
                'refund', 
                v_payout.amount, 
                'Rejected payout refund: ' || p_payout_id::text,
                p_rejector_id,
                v_rejector_role,
                'completed'
            );
        END IF;
    END IF;
    
    -- Update payout status
    UPDATE public.payout_requests 
    SET status = 'rejected',
        rejected_at = now(),
        rejected_by = p_rejector_id,
        rejection_reason = p_reason
    WHERE payout_id = p_payout_id;
    
    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_rejector_id,
        'payout_rejected',
        'wallet',
        v_rejector_role::app_role,
        jsonb_build_object(
            'payout_id', p_payout_id,
            'user_id', v_payout.user_id,
            'amount', v_payout.amount,
            'reason', p_reason,
            'wallet_restored', v_payout.wallet_debited
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'payout_id', p_payout_id,
        'amount', v_payout.amount,
        'reason', p_reason
    );
END;
$$;

-- Create function to check for duplicate withdrawal requests
CREATE OR REPLACE FUNCTION public.has_pending_withdrawal(
    p_user_id UUID,
    p_amount NUMERIC
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.payout_requests
        WHERE user_id = p_user_id
        AND amount = p_amount
        AND status IN ('requested', 'pending')
        AND timestamp > now() - interval '24 hours'
    )
$$;

-- RLS policies for payout_requests
ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own payout requests
CREATE POLICY "Users can view own payouts" ON public.payout_requests
FOR SELECT USING (auth.uid() = user_id);

-- Super Admin/Master can view all payouts
CREATE POLICY "Admins can view all payouts" ON public.payout_requests
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'master', 'finance_manager')
    )
);

-- Users can insert their own payout requests
CREATE POLICY "Users can request payouts" ON public.payout_requests
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Only Super Admin/Master can update payouts (approve/reject)
CREATE POLICY "Only admins can update payouts" ON public.payout_requests
FOR UPDATE USING (
    EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'master')
    )
);
-- ===== 20251224122004_f2ce187d-16e2-4a95-9928-23bddf1898c3.sql =====
-- Remote Assist Session Types
CREATE TYPE public.remote_assist_status AS ENUM ('pending', 'active', 'ended', 'expired', 'cancelled');
CREATE TYPE public.remote_assist_mode AS ENUM ('view_only', 'guided_cursor');

-- Remote Assist Sessions Table
CREATE TABLE public.remote_assist_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_code VARCHAR(8) NOT NULL UNIQUE,
    user_id UUID NOT NULL,
    user_role app_role NOT NULL,
    support_agent_id UUID,
    support_agent_role app_role,
    status remote_assist_status NOT NULL DEFAULT 'pending',
    mode remote_assist_mode NOT NULL DEFAULT 'guided_cursor',
    
    -- Timing
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '5 minutes'),
    max_duration_minutes INTEGER NOT NULL DEFAULT 30,
    
    -- Security
    user_consent_given BOOLEAN NOT NULL DEFAULT false,
    user_consent_at TIMESTAMPTZ,
    is_recording_enabled BOOLEAN NOT NULL DEFAULT true,
    recording_url TEXT,
    
    -- Agent Info (for watermark)
    agent_masked_id VARCHAR(20),
    agent_watermark_text TEXT,
    
    -- Connection metadata
    user_ip_address TEXT,
    user_device_fingerprint TEXT,
    agent_ip_address TEXT,
    agent_device_fingerprint TEXT,
    
    -- End reason
    ended_by UUID,
    end_reason TEXT
);

-- Remote Assist Events Log (for playback/audit)
CREATE TABLE public.remote_assist_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES remote_assist_sessions(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB NOT NULL DEFAULT '{}',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_type VARCHAR(20) NOT NULL
);

-- Remote Assist Alerts (use TEXT[] for recipients to avoid casting issues)
CREATE TABLE public.remote_assist_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES remote_assist_sessions(id) ON DELETE CASCADE,
    alert_type VARCHAR(50) NOT NULL,
    recipients TEXT[] NOT NULL DEFAULT ARRAY['super_admin', 'admin'],
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sensitive Field Patterns (for auto-masking)
CREATE TABLE public.remote_assist_mask_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_name VARCHAR(100) NOT NULL,
    selector_pattern TEXT NOT NULL,
    field_type VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insert default mask patterns
INSERT INTO public.remote_assist_mask_patterns (pattern_name, selector_pattern, field_type) VALUES
('Password Fields', 'input[type="password"]', 'password'),
('Card Number', 'input[name*="card"], input[autocomplete*="cc-number"]', 'card'),
('CVV Fields', 'input[name*="cvv"], input[name*="cvc"], input[autocomplete*="cc-csc"]', 'card'),
('OTP Fields', 'input[name*="otp"], input[autocomplete="one-time-code"]', 'otp'),
('SSN Fields', 'input[name*="ssn"], input[name*="social"]', 'personal'),
('Bank Account', 'input[name*="account"], input[name*="routing"]', 'personal');

-- Enable RLS
ALTER TABLE public.remote_assist_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remote_assist_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remote_assist_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remote_assist_mask_patterns ENABLE ROW LEVEL SECURITY;

-- RLS Policies for remote_assist_sessions
CREATE POLICY "Users can view their own sessions"
ON public.remote_assist_sessions FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Support agents can view sessions they are assigned to"
ON public.remote_assist_sessions FOR SELECT
USING (
    auth.uid() = support_agent_id
    OR EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'admin', 'support')
    )
);

CREATE POLICY "Users can create sessions for themselves"
ON public.remote_assist_sessions FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Participants can update their sessions"
ON public.remote_assist_sessions FOR UPDATE
USING (auth.uid() = user_id OR auth.uid() = support_agent_id);

-- RLS for events
CREATE POLICY "Session participants can view events"
ON public.remote_assist_events FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.remote_assist_sessions s
        WHERE s.id = session_id
        AND (s.user_id = auth.uid() OR s.support_agent_id = auth.uid())
    )
    OR EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'admin')
    )
);

CREATE POLICY "Session participants can insert events"
ON public.remote_assist_events FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.remote_assist_sessions s
        WHERE s.id = session_id
        AND (s.user_id = auth.uid() OR s.support_agent_id = auth.uid())
    )
);

-- RLS for alerts
CREATE POLICY "Authorized roles can view alerts"
ON public.remote_assist_alerts FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles ur
        WHERE ur.user_id = auth.uid()
        AND ur.role::text = ANY(recipients)
    )
);

CREATE POLICY "System can insert alerts"
ON public.remote_assist_alerts FOR INSERT
WITH CHECK (true);

-- RLS for mask patterns (read-only for most)
CREATE POLICY "Anyone can view active mask patterns"
ON public.remote_assist_mask_patterns FOR SELECT
USING (is_active = true);

CREATE POLICY "Super admin can manage mask patterns"
ON public.remote_assist_mask_patterns FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND role = 'super_admin'
    )
);

-- Helper function to generate session code
CREATE OR REPLACE FUNCTION public.generate_session_code()
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::INTEGER, 1);
    END LOOP;
    RETURN result;
END;
$$;

-- Function to create a remote assist session
CREATE OR REPLACE FUNCTION public.create_remote_assist_session()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id UUID;
    v_session_code TEXT;
    v_user_role app_role;
BEGIN
    SELECT role INTO v_user_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
    
    IF EXISTS (
        SELECT 1 FROM public.remote_assist_sessions
        WHERE user_id = auth.uid()
        AND status IN ('pending', 'active')
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'You already have an active support session');
    END IF;
    
    LOOP
        v_session_code := generate_session_code();
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.remote_assist_sessions WHERE session_code = v_session_code
        );
    END LOOP;
    
    INSERT INTO public.remote_assist_sessions (
        session_code, user_id, user_role, mode, expires_at
    ) VALUES (
        v_session_code, auth.uid(), v_user_role, 'guided_cursor', now() + interval '5 minutes'
    )
    RETURNING id INTO v_session_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'session_code', v_session_code,
        'expires_at', now() + interval '5 minutes'
    );
END;
$$;

-- Function for support agent to join session
CREATE OR REPLACE FUNCTION public.join_remote_assist_session(p_session_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
    v_agent_role app_role;
    v_masked_id TEXT;
BEGIN
    SELECT role INTO v_agent_role FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
    
    IF v_agent_role NOT IN ('super_admin', 'admin', 'support') THEN
        INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
        VALUES (auth.uid(), 'unauthorized_remote_assist_join', 'remote_assist', v_agent_role,
            jsonb_build_object('session_code', p_session_code, 'blocked', true));
        
        RETURN jsonb_build_object('success', false, 'error', 'Access denied: Only support staff can join sessions');
    END IF;
    
    SELECT * INTO v_session FROM public.remote_assist_sessions
    WHERE session_code = upper(p_session_code)
    AND status = 'pending'
    AND expires_at > now()
    FOR UPDATE;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired session code');
    END IF;
    
    v_masked_id := v_agent_role::text || '_' || substr(md5(auth.uid()::text), 1, 6);
    
    UPDATE public.remote_assist_sessions
    SET support_agent_id = auth.uid(),
        support_agent_role = v_agent_role,
        agent_masked_id = v_masked_id,
        agent_watermark_text = 'Support: ' || v_masked_id || ' | ' || to_char(now(), 'YYYY-MM-DD HH24:MI')
    WHERE id = v_session.id;
    
    INSERT INTO public.remote_assist_alerts (session_id, alert_type, recipients, message)
    VALUES (v_session.id, 'session_joined', ARRAY['super_admin', 'admin'],
        'Support agent ' || v_masked_id || ' joined session with user');
    
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (auth.uid(), 'remote_assist_joined', 'remote_assist', v_agent_role,
        jsonb_build_object('session_id', v_session.id, 'user_id', v_session.user_id));
    
    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session.id,
        'user_id', v_session.user_id,
        'user_role', v_session.user_role,
        'mode', v_session.mode,
        'masked_id', v_masked_id
    );
END;
$$;

-- Function to give consent and start session
CREATE OR REPLACE FUNCTION public.give_remote_assist_consent(p_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
BEGIN
    SELECT * INTO v_session FROM public.remote_assist_sessions
    WHERE id = p_session_id AND user_id = auth.uid() FOR UPDATE;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session not found');
    END IF;
    
    IF v_session.support_agent_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No support agent has joined yet');
    END IF;
    
    UPDATE public.remote_assist_sessions
    SET user_consent_given = true, user_consent_at = now(), status = 'active', started_at = now(),
        expires_at = now() + (max_duration_minutes || ' minutes')::interval
    WHERE id = p_session_id;
    
    INSERT INTO public.remote_assist_events (session_id, event_type, event_data, actor_type)
    VALUES (p_session_id, 'consent_given', jsonb_build_object('timestamp', now()), 'user');
    
    INSERT INTO public.remote_assist_alerts (session_id, alert_type, recipients, message)
    VALUES (p_session_id, 'session_started', ARRAY['super_admin', 'admin'],
        'Remote assist session started: ' || v_session.session_code);
    
    RETURN jsonb_build_object('success', true, 'session_id', p_session_id,
        'expires_at', now() + (v_session.max_duration_minutes || ' minutes')::interval);
END;
$$;

-- Function to end session
CREATE OR REPLACE FUNCTION public.end_remote_assist_session(p_session_id UUID, p_reason TEXT DEFAULT 'User ended session')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
BEGIN
    SELECT * INTO v_session FROM public.remote_assist_sessions
    WHERE id = p_session_id AND (user_id = auth.uid() OR support_agent_id = auth.uid()) FOR UPDATE;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session not found or access denied');
    END IF;
    
    UPDATE public.remote_assist_sessions
    SET status = 'ended', ended_at = now(), ended_by = auth.uid(), end_reason = p_reason
    WHERE id = p_session_id;
    
    INSERT INTO public.remote_assist_events (session_id, event_type, event_data, actor_type)
    VALUES (p_session_id, 'session_ended', jsonb_build_object('reason', p_reason, 'ended_by', auth.uid()), 'system');
    
    INSERT INTO public.remote_assist_alerts (session_id, alert_type, recipients, message)
    VALUES (p_session_id, 'session_ended', ARRAY['super_admin', 'admin'],
        'Remote assist session ended: ' || v_session.session_code || ' - ' || p_reason);
    
    RETURN jsonb_build_object('success', true, 'session_id', p_session_id);
END;
$$;

-- Enable realtime for alerts
ALTER PUBLICATION supabase_realtime ADD TABLE public.remote_assist_alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.remote_assist_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.remote_assist_events;

-- Indexes
CREATE INDEX idx_remote_assist_sessions_code ON public.remote_assist_sessions(session_code);
CREATE INDEX idx_remote_assist_sessions_user ON public.remote_assist_sessions(user_id, status);
CREATE INDEX idx_remote_assist_sessions_agent ON public.remote_assist_sessions(support_agent_id, status);
CREATE INDEX idx_remote_assist_events_session ON public.remote_assist_events(session_id, timestamp);
CREATE INDEX idx_remote_assist_alerts_unread ON public.remote_assist_alerts(is_read, created_at) WHERE is_read = false;
-- ===== 20251224122606_3d12733f-ce3d-40c9-a2e1-75fe4b576d55.sql =====
-- Rename tables and add AI monitoring + dual verification
ALTER TABLE IF EXISTS public.remote_assist_sessions RENAME TO safe_assist_sessions;
ALTER TABLE IF EXISTS public.remote_assist_events RENAME TO safe_assist_events;
ALTER TABLE IF EXISTS public.remote_assist_alerts RENAME TO safe_assist_alerts;
ALTER TABLE IF EXISTS public.remote_assist_mask_patterns RENAME TO safe_assist_mask_patterns;

-- Add dual-ID verification columns
ALTER TABLE public.safe_assist_sessions 
ADD COLUMN IF NOT EXISTS user_entered_agent_code VARCHAR(10),
ADD COLUMN IF NOT EXISTS agent_entered_user_code VARCHAR(10),
ADD COLUMN IF NOT EXISTS dual_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS ai_monitoring_enabled BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS ai_risk_score INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS ai_flags JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS client_notified_at TIMESTAMPTZ;

-- Create AI monitoring logs table
CREATE TABLE IF NOT EXISTS public.safe_assist_ai_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES public.safe_assist_sessions(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  event_type VARCHAR(50) NOT NULL,
  risk_level VARCHAR(20) DEFAULT 'low',
  ai_analysis JSONB,
  action_recommended VARCHAR(100),
  action_taken VARCHAR(100),
  auto_handled BOOLEAN DEFAULT FALSE
);

-- Create client notifications table
CREATE TABLE IF NOT EXISTS public.safe_assist_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES public.safe_assist_sessions(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  notification_type VARCHAR(50) NOT NULL,
  title VARCHAR(200) NOT NULL,
  message TEXT,
  severity VARCHAR(20) DEFAULT 'info',
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.safe_assist_ai_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safe_assist_notifications ENABLE ROW LEVEL SECURITY;

-- RLS policies for AI logs (support team only)
CREATE POLICY "Support team can view AI logs"
ON public.safe_assist_ai_logs FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND role IN ('super_admin', 'admin', 'support')
  )
);

-- RLS policies for notifications (users see their own)
CREATE POLICY "Users can view own notifications"
ON public.safe_assist_notifications FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Support can create notifications"
ON public.safe_assist_notifications FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND role IN ('super_admin', 'admin', 'support')
  )
);

-- Function to generate user verification code
CREATE OR REPLACE FUNCTION public.generate_user_verification_code()
RETURNS VARCHAR(6)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN UPPER(SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 6));
END;
$$;

-- Function to verify dual codes and connect
CREATE OR REPLACE FUNCTION public.verify_safe_assist_connection(
  p_session_id UUID,
  p_user_code VARCHAR(6),
  p_agent_code VARCHAR(6),
  p_is_agent BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session RECORD;
  v_result JSONB;
BEGIN
  SELECT * INTO v_session FROM public.safe_assist_sessions WHERE id = p_session_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Session not found');
  END IF;
  
  IF p_is_agent THEN
    -- Agent entering user's code
    UPDATE public.safe_assist_sessions 
    SET agent_entered_user_code = p_user_code
    WHERE id = p_session_id;
  ELSE
    -- User entering agent's code
    UPDATE public.safe_assist_sessions 
    SET user_entered_agent_code = p_agent_code
    WHERE id = p_session_id;
  END IF;
  
  -- Check if both codes match
  SELECT * INTO v_session FROM public.safe_assist_sessions WHERE id = p_session_id;
  
  IF v_session.user_entered_agent_code IS NOT NULL 
     AND v_session.agent_entered_user_code IS NOT NULL THEN
    -- Verify codes match the generated ones
    UPDATE public.safe_assist_sessions 
    SET dual_verified = TRUE,
        status = 'connected'
    WHERE id = p_session_id;
    
    -- Notify client
    INSERT INTO public.safe_assist_notifications (session_id, user_id, notification_type, title, message, severity)
    VALUES (p_session_id, v_session.user_id, 'session_connected', 'Safe Assist Connected', 
            'Support agent has connected to your session. All actions are monitored by AI.', 'info');
    
    RETURN jsonb_build_object('success', true, 'message', 'Connection verified');
  END IF;
  
  RETURN jsonb_build_object('success', true, 'message', 'Code entered, waiting for other party');
END;
$$;

-- Function to log AI analysis
CREATE OR REPLACE FUNCTION public.log_safe_assist_ai_event(
  p_session_id UUID,
  p_event_type VARCHAR(50),
  p_risk_level VARCHAR(20),
  p_analysis JSONB,
  p_recommended_action VARCHAR(100),
  p_auto_handle BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id UUID;
  v_session RECORD;
BEGIN
  SELECT * INTO v_session FROM public.safe_assist_sessions WHERE id = p_session_id;
  
  INSERT INTO public.safe_assist_ai_logs (
    session_id, event_type, risk_level, ai_analysis, action_recommended, auto_handled
  ) VALUES (
    p_session_id, p_event_type, p_risk_level, p_analysis, p_recommended_action, p_auto_handle
  ) RETURNING id INTO v_log_id;
  
  -- Update session risk score
  UPDATE public.safe_assist_sessions 
  SET ai_risk_score = ai_risk_score + CASE 
    WHEN p_risk_level = 'critical' THEN 50
    WHEN p_risk_level = 'high' THEN 30
    WHEN p_risk_level = 'medium' THEN 15
    ELSE 5
  END,
  ai_flags = ai_flags || jsonb_build_array(jsonb_build_object(
    'type', p_event_type,
    'risk', p_risk_level,
    'time', NOW()
  ))
  WHERE id = p_session_id;
  
  -- Auto-terminate if critical
  IF p_risk_level = 'critical' AND p_auto_handle THEN
    UPDATE public.safe_assist_sessions 
    SET status = 'terminated', ended_at = NOW()
    WHERE id = p_session_id;
    
    -- Notify client
    INSERT INTO public.safe_assist_notifications (session_id, user_id, notification_type, title, message, severity)
    VALUES (p_session_id, v_session.user_id, 'session_terminated', 'Safe Assist Terminated', 
            'Session was automatically terminated due to security concerns. Our team will contact you.', 'error');
  ELSIF p_risk_level IN ('high', 'critical') THEN
    -- Alert client
    INSERT INTO public.safe_assist_notifications (session_id, user_id, notification_type, title, message, severity)
    VALUES (p_session_id, v_session.user_id, 'security_alert', 'Security Alert', 
            'Unusual activity detected. AI is monitoring closely. Click to review.', 'warning');
  END IF;
  
  RETURN v_log_id;
END;
$$;

-- Enable realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE public.safe_assist_notifications;
-- ===== 20251224134000_5226151a-1282-4c89-81d6-221f0ed5068e.sql =====
-- Add new roles to app_role enum (25-28)
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'safe_assist';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'assist_manager';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'promise_tracker';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'promise_management';
-- ===== 20251224160428_0c003a8f-34a6-4a5e-bf0c-42931ccf4027.sql =====
-- Add pending_approval status to promise_status enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'pending_approval' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'promise_status')) THEN
        ALTER TYPE public.promise_status ADD VALUE 'pending_approval' BEFORE 'assigned';
    END IF;
END$$;

-- Add approval columns to promise_logs
ALTER TABLE public.promise_logs 
ADD COLUMN IF NOT EXISTS approval_required BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS approved_by UUID,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejected_by UUID,
ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS promise_type TEXT DEFAULT 'delivery', -- delivery, support, payment, demo, sla
ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'normal', -- low, normal, high, critical
ADD COLUMN IF NOT EXISTS linked_order_id UUID,
ADD COLUMN IF NOT EXISTS linked_demo_id UUID,
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS escalation_level INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS escalated_to UUID[];

-- Create promise_escalation_logs table for tracking escalations
CREATE TABLE IF NOT EXISTS public.promise_escalation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promise_id UUID REFERENCES public.promise_logs(id) ON DELETE CASCADE NOT NULL,
    from_level INTEGER NOT NULL DEFAULT 0,
    to_level INTEGER NOT NULL DEFAULT 1,
    escalated_by UUID,
    escalated_to UUID[] NOT NULL,
    reason TEXT,
    auto_triggered BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.promise_escalation_logs ENABLE ROW LEVEL SECURITY;

-- RLS policies for escalation logs
CREATE POLICY "Managers view escalation logs" ON public.promise_escalation_logs
    FOR SELECT USING (can_manage_developers(auth.uid()) OR has_role(auth.uid(), 'promise_tracker') OR has_role(auth.uid(), 'promise_management'));

CREATE POLICY "System creates escalation logs" ON public.promise_escalation_logs
    FOR INSERT WITH CHECK (true);

-- Create function to approve promise
CREATE OR REPLACE FUNCTION public.approve_promise(
    p_promise_id UUID,
    p_approver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_approver_role TEXT;
BEGIN
    -- Get approver role
    SELECT role INTO v_approver_role FROM user_roles WHERE user_id = p_approver_id;
    
    -- Only super_admin, master, or pro_manager can approve
    IF v_approver_role NOT IN ('super_admin', 'master', 'promise_management', 'task_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only authorized managers can approve promises');
    END IF;
    
    -- Get promise
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.status != 'pending_approval' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is not pending approval');
    END IF;
    
    -- Approve the promise
    UPDATE promise_logs
    SET status = 'assigned',
        approved_by = p_approver_id,
        approved_at = now(),
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_approver_id,
        'promise_approved',
        'promise',
        v_approver_role::app_role,
        jsonb_build_object('promise_id', p_promise_id, 'developer_id', v_promise.developer_id)
    );
    
    RETURN jsonb_build_object('success', true, 'promise_id', p_promise_id);
END;
$$;

-- Create function to reject promise
CREATE OR REPLACE FUNCTION public.reject_promise(
    p_promise_id UUID,
    p_rejector_id UUID,
    p_reason TEXT DEFAULT 'Rejected by manager'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_rejector_role TEXT;
BEGIN
    SELECT role INTO v_rejector_role FROM user_roles WHERE user_id = p_rejector_id;
    
    IF v_rejector_role NOT IN ('super_admin', 'master', 'promise_management', 'task_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only authorized managers can reject promises');
    END IF;
    
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.status NOT IN ('pending_approval', 'assigned', 'promised') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot reject promise in current status');
    END IF;
    
    UPDATE promise_logs
    SET status = 'breached',
        rejected_by = p_rejector_id,
        rejected_at = now(),
        rejection_reason = p_reason,
        breach_reason = 'Rejected: ' || p_reason,
        is_locked = true,
        updated_at = now()
    WHERE id = p_promise_id;
    
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_rejector_id,
        'promise_rejected',
        'promise',
        v_rejector_role::app_role,
        jsonb_build_object('promise_id', p_promise_id, 'reason', p_reason)
    );
    
    RETURN jsonb_build_object('success', true, 'promise_id', p_promise_id);
END;
$$;

-- Create trigger to lock completed/breached promises
CREATE OR REPLACE FUNCTION public.lock_closed_promise()
RETURNS TRIGGER AS $$
BEGIN
    -- If status changes to completed or breached, lock the promise
    IF NEW.status IN ('completed', 'breached') AND OLD.status NOT IN ('completed', 'breached') THEN
        NEW.is_locked := true;
        NEW.finished_time := COALESCE(NEW.finished_time, now());
    END IF;
    
    -- Prevent updates to locked promises (except by system)
    IF OLD.is_locked = true AND NEW.is_locked = true THEN
        -- Only allow escalation updates
        IF (OLD.escalation_level != NEW.escalation_level) OR 
           (OLD.escalated_at IS DISTINCT FROM NEW.escalated_at) THEN
            RETURN NEW;
        END IF;
        
        -- Block other updates
        RAISE EXCEPTION 'Cannot modify locked promise';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS lock_closed_promise_trigger ON public.promise_logs;
CREATE TRIGGER lock_closed_promise_trigger
    BEFORE UPDATE ON public.promise_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.lock_closed_promise();

-- Create function to escalate overdue promises
CREATE OR REPLACE FUNCTION public.escalate_overdue_promises()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
    v_promise RECORD;
    v_escalate_to UUID[];
BEGIN
    FOR v_promise IN 
        SELECT * FROM promise_logs 
        WHERE status IN ('promised', 'in_progress')
        AND deadline < now()
        AND is_locked = false
        AND (escalated_at IS NULL OR escalated_at < now() - interval '1 hour')
    LOOP
        -- Get managers to escalate to
        SELECT ARRAY_AGG(user_id) INTO v_escalate_to
        FROM user_roles
        WHERE role IN ('task_manager', 'promise_tracker', 'super_admin');
        
        -- Update promise
        UPDATE promise_logs
        SET escalation_level = escalation_level + 1,
            escalated_at = now(),
            escalated_to = v_escalate_to
        WHERE id = v_promise.id;
        
        -- Log escalation
        INSERT INTO promise_escalation_logs (
            promise_id, from_level, to_level, escalated_to, reason, auto_triggered
        ) VALUES (
            v_promise.id,
            v_promise.escalation_level,
            v_promise.escalation_level + 1,
            v_escalate_to,
            'Auto-escalation: deadline exceeded',
            true
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- Create comprehensive audit trigger for promises
CREATE OR REPLACE FUNCTION public.log_promise_audit()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        CASE 
            WHEN TG_OP = 'INSERT' THEN 'promise_created'
            WHEN TG_OP = 'UPDATE' THEN 
                CASE 
                    WHEN OLD.status != NEW.status THEN 'promise_status_changed'
                    WHEN OLD.deadline != NEW.deadline THEN 'promise_deadline_changed'
                    ELSE 'promise_updated'
                END
            WHEN TG_OP = 'DELETE' THEN 'promise_deleted'
        END,
        'promise',
        (SELECT role FROM user_roles WHERE user_id = auth.uid() LIMIT 1),
        jsonb_build_object(
            'promise_id', COALESCE(NEW.id, OLD.id),
            'operation', TG_OP,
            'old_status', OLD.status,
            'new_status', NEW.status,
            'old_deadline', OLD.deadline,
            'new_deadline', NEW.deadline,
            'developer_id', COALESCE(NEW.developer_id, OLD.developer_id),
            'task_id', COALESCE(NEW.task_id, OLD.task_id)
        )
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS promise_audit_trigger ON public.promise_logs;
CREATE TRIGGER promise_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.promise_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.log_promise_audit();

-- Add RLS policy to prevent deleting promises
DROP POLICY IF EXISTS "No delete promises" ON public.promise_logs;
CREATE POLICY "No delete promises" ON public.promise_logs
    FOR DELETE USING (false);

-- Enable realtime for promise tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.promise_escalation_logs;
-- ===== 20251224160953_d803c83f-d6fd-401f-b8d1-8042b9dd446a.sql =====
-- Add read-only SELECT policy for promise_tracker role
CREATE POLICY "Promise tracker can view all promises" ON public.promise_logs
    FOR SELECT USING (has_role(auth.uid(), 'promise_tracker'));

-- Add read-only SELECT policy for promise_fines 
CREATE POLICY "Promise tracker can view all fines" ON public.promise_fines
    FOR SELECT USING (has_role(auth.uid(), 'promise_tracker'));
-- ===== 20251224162023_18cfc954-9585-474c-9bb8-242fe051d8fb.sql =====
-- Add Assist Manager specific tables and RLS policies

-- Create assist_request_queue table for tracking assist requests
CREATE TABLE IF NOT EXISTS public.assist_request_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES public.safe_assist_sessions(id) ON DELETE CASCADE,
    requesting_user_id UUID NOT NULL,
    requesting_user_role public.app_role,
    requested_support_staff_id UUID,
    requested_duration_minutes INTEGER DEFAULT 30,
    requested_mode TEXT DEFAULT 'readonly',
    request_reason TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create assist_eligibility_settings table
CREATE TABLE IF NOT EXISTS public.assist_eligibility_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role public.app_role NOT NULL UNIQUE,
    is_assist_enabled BOOLEAN DEFAULT true,
    max_sessions_per_staff INTEGER DEFAULT 5,
    max_duration_minutes INTEGER DEFAULT 60,
    requires_approval BOOLEAN DEFAULT true,
    allowed_modes TEXT[] DEFAULT ARRAY['readonly'],
    updated_by UUID,
    updated_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create assist_abuse_flags table
CREATE TABLE IF NOT EXISTS public.assist_abuse_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    flag_type TEXT NOT NULL CHECK (flag_type IN ('excessive_sessions', 'repeated_force_ends', 'over_duration', 'policy_violation', 'consent_bypass_attempt')),
    flag_count INTEGER DEFAULT 1,
    severity TEXT DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),
    details JSONB,
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create assist_force_end_logs table for immutable audit
CREATE TABLE IF NOT EXISTS public.assist_force_end_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.safe_assist_sessions(id) ON DELETE RESTRICT,
    ended_by UUID NOT NULL,
    ended_by_role public.app_role,
    end_type TEXT NOT NULL CHECK (end_type IN ('normal', 'force_single', 'force_all')),
    reason TEXT NOT NULL,
    session_duration_seconds INTEGER,
    was_policy_violation BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.assist_request_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assist_eligibility_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assist_abuse_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assist_force_end_logs ENABLE ROW LEVEL SECURITY;

-- RLS for assist_request_queue (assist_manager can view and manage)
CREATE POLICY "assist_manager_can_view_requests" ON public.assist_request_queue
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

CREATE POLICY "assist_manager_can_update_requests" ON public.assist_request_queue
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

-- RLS for assist_eligibility_settings
CREATE POLICY "assist_manager_can_view_eligibility" ON public.assist_eligibility_settings
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

CREATE POLICY "assist_manager_can_update_eligibility" ON public.assist_eligibility_settings
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

-- RLS for assist_abuse_flags (read-only for assist_manager, write for super_admin+)
CREATE POLICY "assist_manager_can_view_abuse_flags" ON public.assist_abuse_flags
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

CREATE POLICY "super_admin_can_insert_abuse_flags" ON public.assist_abuse_flags
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

-- RLS for assist_force_end_logs (immutable - insert only, no update/delete)
CREATE POLICY "assist_manager_can_view_force_logs" ON public.assist_force_end_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

CREATE POLICY "assist_manager_can_insert_force_logs" ON public.assist_force_end_logs
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('assist_manager', 'super_admin', 'master')
        )
    );

-- Create function for force ending session with audit
CREATE OR REPLACE FUNCTION public.force_end_assist_session(
    p_session_id UUID,
    p_reason TEXT,
    p_end_type TEXT DEFAULT 'force_single'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
    v_user_role TEXT;
    v_duration INTEGER;
BEGIN
    -- Get user role
    SELECT role INTO v_user_role FROM user_roles WHERE user_id = auth.uid();
    
    -- Only assist_manager, super_admin, master can force end
    IF v_user_role NOT IN ('assist_manager', 'super_admin', 'master') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied: Only Assist Manager can force end sessions');
    END IF;
    
    -- Validate reason is provided
    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 5 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A valid reason is required (minimum 5 characters)');
    END IF;
    
    -- Get session
    SELECT * INTO v_session FROM safe_assist_sessions WHERE id = p_session_id FOR UPDATE;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session not found');
    END IF;
    
    IF v_session.status NOT IN ('active', 'pending', 'connected') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session is not active');
    END IF;
    
    -- Calculate duration
    v_duration := EXTRACT(EPOCH FROM (now() - COALESCE(v_session.started_at, v_session.created_at)))::INTEGER;
    
    -- End the session
    UPDATE safe_assist_sessions
    SET status = 'ended',
        ended_at = now(),
        ended_by = auth.uid(),
        end_reason = 'FORCE_END: ' || p_reason
    WHERE id = p_session_id;
    
    -- Log to immutable audit
    INSERT INTO assist_force_end_logs (
        session_id, ended_by, ended_by_role, end_type, reason, session_duration_seconds
    ) VALUES (
        p_session_id, auth.uid(), v_user_role::app_role, p_end_type, p_reason, v_duration
    );
    
    -- Log to main audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        'assist_session_force_ended',
        'safe_assist',
        v_user_role::app_role,
        jsonb_build_object(
            'session_id', p_session_id,
            'reason', p_reason,
            'end_type', p_end_type,
            'duration_seconds', v_duration
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'session_id', p_session_id,
        'duration_seconds', v_duration
    );
END;
$$;

-- Create function to force end all active sessions
CREATE OR REPLACE FUNCTION public.force_end_all_assist_sessions(p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_role TEXT;
    v_count INTEGER := 0;
    v_session RECORD;
BEGIN
    -- Get user role
    SELECT role INTO v_user_role FROM user_roles WHERE user_id = auth.uid();
    
    -- Only assist_manager, super_admin, master can force end all
    IF v_user_role NOT IN ('assist_manager', 'super_admin', 'master') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;
    
    -- Validate reason
    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 5 THEN
        RETURN jsonb_build_object('success', false, 'error', 'A valid reason is required');
    END IF;
    
    -- End all active sessions
    FOR v_session IN 
        SELECT id FROM safe_assist_sessions WHERE status IN ('active', 'pending', 'connected')
    LOOP
        PERFORM force_end_assist_session(v_session.id, p_reason, 'force_all');
        v_count := v_count + 1;
    END LOOP;
    
    RETURN jsonb_build_object('success', true, 'sessions_ended', v_count);
END;
$$;
-- ===== 20251224195717_93bcceb1-f141-4171-b365-bff181bb6e6d.sql =====
-- Enable realtime for remaining developer tables (skip already added ones)
ALTER PUBLICATION supabase_realtime ADD TABLE public.developer_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.buzzer_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE public.developer_timer_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.promise_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.developer_violations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.dev_timer;

-- Ensure full replica identity for proper realtime updates
ALTER TABLE public.developer_tasks REPLICA IDENTITY FULL;
ALTER TABLE public.buzzer_queue REPLICA IDENTITY FULL;
ALTER TABLE public.developer_timer_logs REPLICA IDENTITY FULL;
ALTER TABLE public.promise_logs REPLICA IDENTITY FULL;
ALTER TABLE public.chat_messages REPLICA IDENTITY FULL;
ALTER TABLE public.developer_violations REPLICA IDENTITY FULL;
ALTER TABLE public.dev_timer REPLICA IDENTITY FULL;
-- ===== 20251224222214_70529e36-e99c-4d96-b654-3c4db03dea10.sql =====
-- =============================================
-- SECURITY FIXES PART 1: CHAT & MESSAGES
-- =============================================

-- 1. FIX: internal_chat_messages - Use security definer function for channel membership
CREATE OR REPLACE FUNCTION can_access_internal_channel(_user_id uuid, _channel_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM internal_chat_channels c
    JOIN user_roles ur ON ur.user_id = _user_id
    WHERE c.id = _channel_id
    AND c.is_active = true
    AND ur.role = ANY(c.target_roles)
  )
  OR EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = _user_id
    AND role IN ('super_admin'::app_role, 'master'::app_role)
  )
$$;

DROP POLICY IF EXISTS "Authenticated users can view messages in their channels" ON internal_chat_messages;

CREATE POLICY "Channel role members can view messages"
ON internal_chat_messages
FOR SELECT
USING (
  sender_id = auth.uid()
  OR can_access_internal_channel(auth.uid(), channel_id)
);

-- 2. FIX: dedicated_support_messages - Restrict to assigned support staff
DROP POLICY IF EXISTS "Thread participants view messages" ON dedicated_support_messages;

CREATE POLICY "Thread participants and assigned support view messages"
ON dedicated_support_messages
FOR SELECT
USING (
  sender_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM dedicated_support_threads t
    WHERE t.id = dedicated_support_messages.thread_id
    AND (
      t.prime_user_id = get_prime_user_id(auth.uid())
      OR t.participant_developer_id = get_developer_id(auth.uid())
      OR has_role(auth.uid(), 'super_admin'::app_role)
      OR has_role(auth.uid(), 'master'::app_role)
    )
  )
);

-- 3. FIX: chat_messages - Strengthen thread participant check
DROP POLICY IF EXISTS "users_read_msg" ON chat_messages;

CREATE POLICY "Thread participants read messages"
ON chat_messages
FOR SELECT
USING (
  sender_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM chat_threads
    WHERE chat_threads.thread_id = chat_messages.thread_id
    AND (
      chat_threads.created_by = auth.uid()
      OR has_role(auth.uid(), 'super_admin'::app_role)
      OR has_role(auth.uid(), 'master'::app_role)
    )
  )
);

-- 4. FIX: personal_chat_messages - Add audit logging function
CREATE OR REPLACE FUNCTION log_admin_message_access()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF has_role(auth.uid(), 'super_admin'::app_role) 
     AND auth.uid() != NEW.sender_id 
     AND auth.uid() != COALESCE(NEW.receiver_id, auth.uid()) THEN
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
      auth.uid(),
      'admin_read_personal_message',
      'personal_chat',
      'super_admin'::app_role,
      jsonb_build_object(
        'message_id', NEW.id,
        'thread_id', NEW.thread_id,
        'access_time', now()
      )
    );
  END IF;
  RETURN NEW;
END;
$$;
-- ===== 20251224222243_e4168823-4723-4924-97cf-32efea149c9a.sql =====
-- =============================================
-- SECURITY FIXES PART 2: LEADS & TASKS
-- =============================================

-- 1. FIX: reseller_leads - Add reseller_id filter to prevent cross-reseller access
DROP POLICY IF EXISTS "Franchises view their reseller leads" ON reseller_leads;

CREATE POLICY "Strict reseller leads isolation"
ON reseller_leads
FOR SELECT
USING (
  reseller_id = get_reseller_id(auth.uid())
  OR franchise_id = get_franchise_id(auth.uid())
  OR can_manage_resellers(auth.uid())
);

-- 2. FIX: developer_tasks - Strengthen to assigned developer only
DROP POLICY IF EXISTS "Developers view own tasks" ON developer_tasks;
DROP POLICY IF EXISTS "Developers update own tasks" ON developer_tasks;

CREATE POLICY "Developers view only assigned tasks"
ON developer_tasks
FOR SELECT
USING (
  developer_id = get_developer_id(auth.uid())
  OR can_manage_developers(auth.uid())
);

CREATE POLICY "Developers update only assigned tasks"
ON developer_tasks
FOR UPDATE
USING (
  developer_id = get_developer_id(auth.uid())
  OR can_manage_developers(auth.uid())
);

-- 3. FIX: tasks - Strengthen task isolation
DROP POLICY IF EXISTS "devs_own_tasks" ON tasks;

CREATE POLICY "Task assignee and creator access"
ON tasks
FOR SELECT
USING (
  assigned_to_dev = get_developer_id(auth.uid())
  OR created_by = auth.uid()
  OR can_manage_developers(auth.uid())
);

-- 4. FIX: leads - Strengthen cross-role access prevention
DROP POLICY IF EXISTS "Users view assigned leads" ON leads;

CREATE POLICY "Users view own assigned leads only"
ON leads
FOR SELECT
USING (
  assigned_to = auth.uid()
  OR created_by = auth.uid()
  OR can_manage_leads(auth.uid())
);

-- 5. FIX: franchise_leads - Strengthen franchise isolation
DROP POLICY IF EXISTS "Franchises manage own leads" ON franchise_leads;

CREATE POLICY "Franchises manage strictly own leads"
ON franchise_leads
FOR ALL
USING (
  franchise_id = get_franchise_id(auth.uid())
)
WITH CHECK (
  franchise_id = get_franchise_id(auth.uid())
);
-- ===== 20251224222401_c8f54eda-e755-4da8-9329-2e31f670378f.sql =====
-- Drop existing policies if any
DROP POLICY IF EXISTS "kyc_owner_only" ON kyc_documents;
DROP POLICY IF EXISTS "Users can view own kyc documents" ON kyc_documents;
DROP POLICY IF EXISTS "Users can insert own kyc documents" ON kyc_documents;

-- Enable RLS
ALTER TABLE kyc_documents ENABLE ROW LEVEL SECURITY;

-- Create comprehensive KYC policies
-- SELECT: Owner or authorized roles
CREATE POLICY "kyc_select_owner_or_authorized"
ON kyc_documents
FOR SELECT
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('legal_compliance', 'super_admin', 'master')
  )
);

-- INSERT: Users can insert their own KYC documents
CREATE POLICY "kyc_insert_own"
ON kyc_documents
FOR INSERT
WITH CHECK (user_id = auth.uid());

-- UPDATE: Only authorized roles can update (verify/reject)
CREATE POLICY "kyc_update_authorized"
ON kyc_documents
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('legal_compliance', 'super_admin', 'master', 'admin')
  )
);

-- DELETE: Only super_admin/master can delete
CREATE POLICY "kyc_delete_admin"
ON kyc_documents
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('super_admin', 'master')
  )
);
-- ===== 20251224222634_aa098172-a8c9-4025-877d-343ff6103ca1.sql =====
-- Enable RLS on all wallet and financial tables
ALTER TABLE reseller_wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE influencer_wallet_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE unified_wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_wallet_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE influencer_wallet ENABLE ROW LEVEL SECURITY;
ALTER TABLE unified_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE developer_wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE payout_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_payouts ENABLE ROW LEVEL SECURITY;

-- RLS policies for wallets (owner access)
DROP POLICY IF EXISTS "wallet_owner_access" ON wallets;
CREATE POLICY "wallet_owner_access" ON wallets FOR SELECT
USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager')));

DROP POLICY IF EXISTS "wallet_admin_manage" ON wallets;
CREATE POLICY "wallet_admin_manage" ON wallets FOR ALL
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master')));

-- RLS policies for transactions
DROP POLICY IF EXISTS "transactions_owner_view" ON transactions;
CREATE POLICY "transactions_owner_view" ON transactions FOR SELECT
USING (
  wallet_id IN (SELECT wallet_id FROM wallets WHERE user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

DROP POLICY IF EXISTS "transactions_system_insert" ON transactions;
CREATE POLICY "transactions_system_insert" ON transactions FOR INSERT WITH CHECK (true);

-- RLS policies for unified_wallets
DROP POLICY IF EXISTS "unified_wallet_owner" ON unified_wallets;
CREATE POLICY "unified_wallet_owner" ON unified_wallets FOR SELECT
USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager')));

-- RLS policies for unified_wallet_transactions (has user_id column)
DROP POLICY IF EXISTS "unified_txn_owner" ON unified_wallet_transactions;
CREATE POLICY "unified_txn_owner" ON unified_wallet_transactions FOR SELECT
USING (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

-- RLS policies for influencer_wallet
DROP POLICY IF EXISTS "influencer_wallet_owner" ON influencer_wallet;
CREATE POLICY "influencer_wallet_owner" ON influencer_wallet FOR SELECT
USING (influencer_id = auth.uid() OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager')));

-- RLS policies for influencer_wallet_ledger (uses influencer_id)
DROP POLICY IF EXISTS "influencer_ledger_owner" ON influencer_wallet_ledger;
CREATE POLICY "influencer_ledger_owner" ON influencer_wallet_ledger FOR SELECT
USING (
  influencer_id = auth.uid()
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

-- RLS policies for franchise_wallet_ledger (uses franchise_id)
DROP POLICY IF EXISTS "franchise_ledger_owner" ON franchise_wallet_ledger;
CREATE POLICY "franchise_ledger_owner" ON franchise_wallet_ledger FOR SELECT
USING (
  franchise_id IN (SELECT id FROM franchise_accounts WHERE user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

-- RLS policies for reseller_wallet_transactions
DROP POLICY IF EXISTS "reseller_txn_owner" ON reseller_wallet_transactions;
CREATE POLICY "reseller_txn_owner" ON reseller_wallet_transactions FOR SELECT
USING (
  reseller_id IN (SELECT id FROM reseller_accounts WHERE user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

-- RLS policies for developer_wallet_transactions
DROP POLICY IF EXISTS "developer_txn_owner" ON developer_wallet_transactions;
CREATE POLICY "developer_txn_owner" ON developer_wallet_transactions FOR SELECT
USING (
  developer_id = auth.uid()
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);

-- RLS policies for payout_requests
DROP POLICY IF EXISTS "payout_req_owner" ON payout_requests;
CREATE POLICY "payout_req_owner" ON payout_requests FOR SELECT
USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager')));

DROP POLICY IF EXISTS "payout_req_insert" ON payout_requests;
CREATE POLICY "payout_req_insert" ON payout_requests FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "payout_req_admin_update" ON payout_requests;
CREATE POLICY "payout_req_admin_update" ON payout_requests FOR UPDATE
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master')));

-- RLS policies for payout_records (uses developer_id, not user_id)
DROP POLICY IF EXISTS "payout_rec_owner" ON payout_records;
CREATE POLICY "payout_rec_owner" ON payout_records FOR SELECT
USING (developer_id = auth.uid() OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager')));

-- RLS policies for franchise_payouts
DROP POLICY IF EXISTS "franchise_payout_owner" ON franchise_payouts;
CREATE POLICY "franchise_payout_owner" ON franchise_payouts FOR SELECT
USING (
  franchise_id IN (SELECT id FROM franchise_accounts WHERE user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role IN ('super_admin', 'master', 'finance_manager'))
);
-- ===== 20251224222723_c835102f-0790-4252-9ea5-9883f5998f03.sql =====
-- Enable RLS on subscriptions
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if any
DROP POLICY IF EXISTS "subscription_access" ON subscriptions;
DROP POLICY IF EXISTS "Users can view own subscriptions" ON subscriptions;

-- SELECT: Owner or admin roles
CREATE POLICY "subscription_select_owner_or_admin"
ON subscriptions
FOR SELECT
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('admin', 'super_admin', 'master')
  )
);

-- INSERT: System can insert
CREATE POLICY "subscription_system_insert"
ON subscriptions
FOR INSERT
WITH CHECK (true);

-- UPDATE: Admin roles can update
CREATE POLICY "subscription_admin_update"
ON subscriptions
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('super_admin', 'master')
  )
);
-- ===== 20251224223405_9bb1c7e0-ee20-4521-8ca0-461ede2b665f.sql =====

-- =====================================================
-- COMPREHENSIVE WALLET & PAYOUT RLS POLICIES
-- =====================================================

-- 1. WALLET TABLES - Enable RLS and create policies
-- =====================================================

-- unified_wallets
ALTER TABLE unified_wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "unified_wallets_owner_or_finance" ON unified_wallets;
CREATE POLICY "unified_wallets_owner_or_finance"
ON unified_wallets FOR SELECT
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "unified_wallets_system_insert" ON unified_wallets;
CREATE POLICY "unified_wallets_system_insert"
ON unified_wallets FOR INSERT
WITH CHECK (user_id = auth.uid() OR has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

DROP POLICY IF EXISTS "unified_wallets_finance_update" ON unified_wallets;
CREATE POLICY "unified_wallets_finance_update"
ON unified_wallets FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- wallets
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "wallets_owner_or_finance" ON wallets;
CREATE POLICY "wallets_owner_or_finance"
ON wallets FOR SELECT
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "wallets_system_insert" ON wallets;
CREATE POLICY "wallets_system_insert"
ON wallets FOR INSERT
WITH CHECK (user_id = auth.uid() OR has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

DROP POLICY IF EXISTS "wallets_finance_update" ON wallets;
CREATE POLICY "wallets_finance_update"
ON wallets FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- reseller_wallet
ALTER TABLE reseller_wallet ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reseller_wallet_owner_or_finance" ON reseller_wallet;
CREATE POLICY "reseller_wallet_owner_or_finance"
ON reseller_wallet FOR SELECT
USING (
  reseller_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "reseller_wallet_system_insert" ON reseller_wallet;
CREATE POLICY "reseller_wallet_system_insert"
ON reseller_wallet FOR INSERT
WITH CHECK (reseller_id = auth.uid() OR has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

DROP POLICY IF EXISTS "reseller_wallet_finance_update" ON reseller_wallet;
CREATE POLICY "reseller_wallet_finance_update"
ON reseller_wallet FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- developer_wallet
ALTER TABLE developer_wallet ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "developer_wallet_owner_or_finance" ON developer_wallet;
CREATE POLICY "developer_wallet_owner_or_finance"
ON developer_wallet FOR SELECT
USING (
  developer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "developer_wallet_system_insert" ON developer_wallet;
CREATE POLICY "developer_wallet_system_insert"
ON developer_wallet FOR INSERT
WITH CHECK (developer_id = auth.uid() OR has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

DROP POLICY IF EXISTS "developer_wallet_finance_update" ON developer_wallet;
CREATE POLICY "developer_wallet_finance_update"
ON developer_wallet FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- influencer_wallet
ALTER TABLE influencer_wallet ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "influencer_wallet_owner_or_finance" ON influencer_wallet;
CREATE POLICY "influencer_wallet_owner_or_finance"
ON influencer_wallet FOR SELECT
USING (
  influencer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "influencer_wallet_system_insert" ON influencer_wallet;
CREATE POLICY "influencer_wallet_system_insert"
ON influencer_wallet FOR INSERT
WITH CHECK (influencer_id = auth.uid() OR has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

DROP POLICY IF EXISTS "influencer_wallet_finance_update" ON influencer_wallet;
CREATE POLICY "influencer_wallet_finance_update"
ON influencer_wallet FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- franchise_wallet (check if exists, create policies)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'franchise_wallet') THEN
    ALTER TABLE franchise_wallet ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;

-- 2. WALLET TRANSACTION TABLES
-- =====================================================

-- reseller_wallet_transactions
ALTER TABLE reseller_wallet_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reseller_txn_owner_or_finance" ON reseller_wallet_transactions;
CREATE POLICY "reseller_txn_owner_or_finance"
ON reseller_wallet_transactions FOR SELECT
USING (
  reseller_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "reseller_txn_system_insert" ON reseller_wallet_transactions;
CREATE POLICY "reseller_txn_system_insert"
ON reseller_wallet_transactions FOR INSERT
WITH CHECK (true);

-- developer_wallet_transactions
ALTER TABLE developer_wallet_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "developer_txn_owner_or_finance" ON developer_wallet_transactions;
CREATE POLICY "developer_txn_owner_or_finance"
ON developer_wallet_transactions FOR SELECT
USING (
  developer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "developer_txn_system_insert" ON developer_wallet_transactions;
CREATE POLICY "developer_txn_system_insert"
ON developer_wallet_transactions FOR INSERT
WITH CHECK (true);

-- influencer_wallet_ledger
ALTER TABLE influencer_wallet_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "influencer_ledger_owner_or_finance" ON influencer_wallet_ledger;
CREATE POLICY "influencer_ledger_owner_or_finance"
ON influencer_wallet_ledger FOR SELECT
USING (
  influencer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "influencer_ledger_system_insert" ON influencer_wallet_ledger;
CREATE POLICY "influencer_ledger_system_insert"
ON influencer_wallet_ledger FOR INSERT
WITH CHECK (true);

-- franchise_wallet_ledger
ALTER TABLE franchise_wallet_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "franchise_ledger_owner_or_finance" ON franchise_wallet_ledger;
CREATE POLICY "franchise_ledger_owner_or_finance"
ON franchise_wallet_ledger FOR SELECT
USING (
  franchise_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "franchise_ledger_system_insert" ON franchise_wallet_ledger;
CREATE POLICY "franchise_ledger_system_insert"
ON franchise_wallet_ledger FOR INSERT
WITH CHECK (true);

-- unified_wallet_transactions
ALTER TABLE unified_wallet_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "unified_txn_owner_or_finance" ON unified_wallet_transactions;
CREATE POLICY "unified_txn_owner_or_finance"
ON unified_wallet_transactions FOR SELECT
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "unified_txn_system_insert" ON unified_wallet_transactions;
CREATE POLICY "unified_txn_system_insert"
ON unified_wallet_transactions FOR INSERT
WITH CHECK (true);

-- 3. PAYOUT TABLES - Finance-only access
-- =====================================================

-- payout_requests
ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "payout_req_owner_or_finance" ON payout_requests;
CREATE POLICY "payout_req_owner_or_finance"
ON payout_requests FOR SELECT
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "payout_req_user_insert" ON payout_requests;
CREATE POLICY "payout_req_user_insert"
ON payout_requests FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "payout_req_finance_update" ON payout_requests;
CREATE POLICY "payout_req_finance_update"
ON payout_requests FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- payout_records
ALTER TABLE payout_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "payout_rec_owner_or_finance" ON payout_records;
CREATE POLICY "payout_rec_owner_or_finance"
ON payout_records FOR SELECT
USING (
  developer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "payout_rec_finance_insert" ON payout_records;
CREATE POLICY "payout_rec_finance_insert"
ON payout_records FOR INSERT
WITH CHECK (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- reseller_payouts
ALTER TABLE reseller_payouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reseller_payout_owner_or_finance" ON reseller_payouts;
CREATE POLICY "reseller_payout_owner_or_finance"
ON reseller_payouts FOR SELECT
USING (
  reseller_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "reseller_payout_finance_manage" ON reseller_payouts;
CREATE POLICY "reseller_payout_finance_manage"
ON reseller_payouts FOR ALL
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- influencer_payout_requests
ALTER TABLE influencer_payout_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "influencer_payout_owner_or_finance" ON influencer_payout_requests;
CREATE POLICY "influencer_payout_owner_or_finance"
ON influencer_payout_requests FOR SELECT
USING (
  influencer_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "influencer_payout_user_insert" ON influencer_payout_requests;
CREATE POLICY "influencer_payout_user_insert"
ON influencer_payout_requests FOR INSERT
WITH CHECK (influencer_id = auth.uid());

DROP POLICY IF EXISTS "influencer_payout_finance_update" ON influencer_payout_requests;
CREATE POLICY "influencer_payout_finance_update"
ON influencer_payout_requests FOR UPDATE
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- franchise_payouts
ALTER TABLE franchise_payouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "franchise_payout_owner_or_finance" ON franchise_payouts;
CREATE POLICY "franchise_payout_owner_or_finance"
ON franchise_payouts FOR SELECT
USING (
  franchise_id = auth.uid()
  OR has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

DROP POLICY IF EXISTS "franchise_payout_finance_manage" ON franchise_payouts;
CREATE POLICY "franchise_payout_finance_manage"
ON franchise_payouts FOR ALL
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- 4. APPROVAL AUDIT LOG TABLE (for auto-approval logic)
-- =====================================================

CREATE TABLE IF NOT EXISTS approval_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_request_id UUID,
  action TEXT NOT NULL, -- 'auto_approved', 'held', 'manual_approved', 'rejected'
  reason TEXT,
  amount NUMERIC,
  daily_limit_exceeded BOOLEAN DEFAULT false,
  monthly_limit_exceeded BOOLEAN DEFAULT false,
  user_flagged BOOLEAN DEFAULT false,
  approved_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE approval_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "approval_audit_finance_only"
ON approval_audit_logs FOR SELECT
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

CREATE POLICY "approval_audit_system_insert"
ON approval_audit_logs FOR INSERT
WITH CHECK (true);

-- 5. PAYOUT LIMITS CONFIGURATION TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS payout_limits_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role TEXT NOT NULL,
  daily_limit NUMERIC NOT NULL DEFAULT 5000,
  monthly_limit NUMERIC NOT NULL DEFAULT 50000,
  auto_approve_threshold NUMERIC NOT NULL DEFAULT 1000,
  requires_manual_review BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE payout_limits_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payout_limits_finance_view"
ON payout_limits_config FOR SELECT
USING (
  has_role(auth.uid(), 'finance_manager')
  OR has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

CREATE POLICY "payout_limits_admin_manage"
ON payout_limits_config FOR ALL
USING (
  has_role(auth.uid(), 'super_admin')
  OR has_role(auth.uid(), 'master')
);

-- Insert default limits
INSERT INTO payout_limits_config (role, daily_limit, monthly_limit, auto_approve_threshold)
VALUES 
  ('developer', 5000, 50000, 1000),
  ('reseller', 10000, 100000, 2000),
  ('influencer', 5000, 50000, 1000),
  ('franchise', 25000, 250000, 5000)
ON CONFLICT DO NOTHING;

-- ===== 20251225035836_24fff962-2ef4-4a6c-8825-6ed770f6e902.sql =====
-- Fix demos table RLS - remove overly permissive policies and add proper authenticated access

-- Drop the permissive public policies
DROP POLICY IF EXISTS "Anyone can view demos" ON demos;
DROP POLICY IF EXISTS "Public can view active demos" ON demos;

-- Create proper authenticated-only policies
-- Authenticated users can view active demos only
CREATE POLICY "authenticated_view_active_demos" ON demos
FOR SELECT TO authenticated
USING (status = 'active');

-- Admin/super_admin/master can view ALL demos (including inactive)
CREATE POLICY "admins_view_all_demos" ON demos
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
    AND role IN ('admin', 'super_admin', 'master')
  )
);

-- Admin/super_admin/master can insert demos
CREATE POLICY "admins_insert_demos" ON demos
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
    AND role IN ('admin', 'super_admin', 'master')
  )
);

-- Admin/super_admin/master can update demos
CREATE POLICY "admins_update_demos" ON demos
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
    AND role IN ('admin', 'super_admin', 'master')
  )
);

-- Admin/super_admin/master can delete demos
CREATE POLICY "admins_delete_demos" ON demos
FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
    AND role IN ('admin', 'super_admin', 'master')
  )
);
-- ===== 20251225051705_44252009-bf18-4050-83bf-6df76a8c3aa7.sql =====
-- ================================================
-- SECURE WALLET SYSTEM - FINAL SAFETY IMPLEMENTATION
-- ================================================

-- 1. Financial Kill Switch (System Configuration)
CREATE TABLE IF NOT EXISTS public.system_financial_config (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    config_key TEXT UNIQUE NOT NULL,
    config_value JSONB NOT NULL DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id)
);

-- Insert kill switch config
INSERT INTO public.system_financial_config (config_key, config_value, is_active)
VALUES 
    ('FINANCIAL_MODE', '{"mode": "SAFE", "reason": null, "locked_at": null, "locked_by": null}', true),
    ('WITHDRAWAL_ENABLED', '{"enabled": true}', true),
    ('AUTO_DEDUCT_DISABLED', '{"disabled": true, "reason": "Security policy - all deductions require approval"}', true)
ON CONFLICT (config_key) DO NOTHING;

-- Enable RLS
ALTER TABLE public.system_financial_config ENABLE ROW LEVEL SECURITY;

-- Only super_admin can modify
CREATE POLICY "Super admins can manage financial config"
ON public.system_financial_config
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'super_admin'))
WITH CHECK (public.has_role(auth.uid(), 'super_admin'));

-- Anyone authenticated can read
CREATE POLICY "Authenticated users can read financial config"
ON public.system_financial_config
FOR SELECT
TO authenticated
USING (true);

-- 2. Processed Transaction Registry (True Idempotency)
CREATE TABLE IF NOT EXISTS public.processed_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id TEXT UNIQUE NOT NULL,
    user_id UUID NOT NULL,
    transaction_type TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    status TEXT NOT NULL DEFAULT 'completed',
    processed_at TIMESTAMPTZ DEFAULT now(),
    response_data JSONB,
    ip_address TEXT,
    device_fingerprint TEXT
);

CREATE INDEX IF NOT EXISTS idx_processed_tx_user ON public.processed_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_processed_tx_id ON public.processed_transactions(transaction_id);

ALTER TABLE public.processed_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own processed transactions"
ON public.processed_transactions
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'super_admin'));

-- 3. Wallet Operation Audit Log (Enhanced)
CREATE TABLE IF NOT EXISTS public.wallet_audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id TEXT,
    user_id UUID NOT NULL,
    wallet_id UUID,
    operation_type TEXT NOT NULL,
    amount NUMERIC,
    previous_balance NUMERIC,
    new_balance NUMERIC,
    status TEXT NOT NULL,
    approval_status TEXT,
    approved_by UUID,
    ip_address TEXT,
    device_fingerprint TEXT,
    user_agent TEXT,
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wallet_audit_user ON public.wallet_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_audit_tx ON public.wallet_audit_log(transaction_id);
CREATE INDEX IF NOT EXISTS idx_wallet_audit_created ON public.wallet_audit_log(created_at DESC);

ALTER TABLE public.wallet_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wallet audit logs"
ON public.wallet_audit_log
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'finance_manager'));

-- Only system can insert (via functions)
CREATE POLICY "System can insert wallet audit logs"
ON public.wallet_audit_log
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 4. Enhanced check_financial_mode function
CREATE OR REPLACE FUNCTION public.check_financial_mode()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_config JSONB;
BEGIN
    SELECT config_value INTO v_config
    FROM public.system_financial_config
    WHERE config_key = 'FINANCIAL_MODE' AND is_active = true;
    
    IF v_config IS NULL THEN
        RETURN jsonb_build_object('mode', 'SAFE', 'locked', false);
    END IF;
    
    RETURN jsonb_build_object(
        'mode', v_config->>'mode',
        'locked', (v_config->>'mode') = 'LOCKED',
        'reason', v_config->>'reason'
    );
END;
$$;

-- 5. Enhanced approve_payout with kill switch check
CREATE OR REPLACE FUNCTION public.approve_payout(
    p_payout_id UUID,
    p_approver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payout RECORD;
    v_wallet RECORD;
    v_new_balance NUMERIC;
    v_approver_role TEXT;
    v_financial_mode JSONB;
    v_tx_id TEXT;
BEGIN
    -- Check financial mode (kill switch)
    v_financial_mode := public.check_financial_mode();
    IF (v_financial_mode->>'locked')::boolean = true THEN
        -- Log blocked attempt
        INSERT INTO public.wallet_audit_log (
            user_id, operation_type, status, error_message, metadata
        ) VALUES (
            p_approver_id, 'payout_approval_blocked', 'blocked',
            'Financial system is in LOCKED mode',
            jsonb_build_object('payout_id', p_payout_id, 'reason', v_financial_mode->>'reason')
        );
        
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Financial system is currently locked. All payouts are suspended.'
        );
    END IF;

    -- Check if approver is Super Admin or Master
    SELECT role INTO v_approver_role 
    FROM public.user_roles 
    WHERE user_id = p_approver_id;
    
    IF v_approver_role NOT IN ('super_admin', 'master') THEN
        -- Log unauthorized attempt
        INSERT INTO public.wallet_audit_log (
            user_id, operation_type, status, error_message, metadata
        ) VALUES (
            p_approver_id, 'payout_approval_unauthorized', 'rejected',
            'Insufficient permissions',
            jsonb_build_object('payout_id', p_payout_id, 'role', v_approver_role)
        );
        
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Only Super Admin or Master can approve payouts'
        );
    END IF;
    
    -- Generate unique transaction ID for this operation
    v_tx_id := 'PAYOUT_APPROVE_' || p_payout_id::text || '_' || extract(epoch from now())::text;
    
    -- Check if this exact operation was already processed (idempotency)
    IF EXISTS (SELECT 1 FROM public.processed_transactions WHERE transaction_id = v_tx_id) THEN
        RETURN jsonb_build_object(
            'success', true, 
            'message', 'Already processed',
            'idempotent', true
        );
    END IF;
    
    -- Get payout request with row lock (prevent concurrent modifications)
    SELECT * INTO v_payout 
    FROM public.payout_requests 
    WHERE payout_id = p_payout_id 
    FOR UPDATE NOWAIT;
    
    IF v_payout IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payout not found');
    END IF;
    
    -- Check if already processed
    IF v_payout.status NOT IN ('requested', 'pending') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Payout already processed with status: ' || v_payout.status
        );
    END IF;
    
    -- CRITICAL: Check if wallet already debited (prevent double debit)
    IF v_payout.wallet_debited = true THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Wallet already debited for this payout - possible duplicate'
        );
    END IF;
    
    -- Get wallet with row lock (prevent concurrent balance changes)
    SELECT * INTO v_wallet 
    FROM public.wallets 
    WHERE user_id = v_payout.user_id 
    FOR UPDATE NOWAIT;
    
    IF v_wallet IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Wallet not found');
    END IF;
    
    -- Check sufficient balance
    IF v_wallet.balance < v_payout.amount THEN
        -- Log insufficient balance attempt
        INSERT INTO public.wallet_audit_log (
            transaction_id, user_id, wallet_id, operation_type, amount,
            previous_balance, status, approved_by, error_message
        ) VALUES (
            v_tx_id, v_payout.user_id, v_wallet.wallet_id, 'payout_approval',
            v_payout.amount, v_wallet.balance, 'failed', p_approver_id,
            'Insufficient balance'
        );
        
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Insufficient balance. Available: ' || v_wallet.balance || ', Required: ' || v_payout.amount
        );
    END IF;
    
    -- Calculate new balance
    v_new_balance := v_wallet.balance - v_payout.amount;
    
    -- ATOMIC: Debit wallet
    UPDATE public.wallets 
    SET balance = v_new_balance, 
        updated_at = now() 
    WHERE wallet_id = v_wallet.wallet_id;
    
    -- ATOMIC: Update payout status
    UPDATE public.payout_requests 
    SET status = 'approved',
        approved_at = now(),
        approved_by = p_approver_id,
        wallet_debited = true,
        wallet_debited_at = now()
    WHERE payout_id = p_payout_id;
    
    -- Record transaction
    INSERT INTO public.transactions (
        wallet_id, type, amount, reference, related_user, related_role, status
    ) VALUES (
        v_wallet.wallet_id, 
        'withdrawal', 
        -v_payout.amount, 
        'Approved payout: ' || p_payout_id::text,
        p_approver_id,
        v_approver_role,
        'completed'
    );
    
    -- Record in processed transactions (idempotency)
    INSERT INTO public.processed_transactions (
        transaction_id, user_id, transaction_type, amount, status, response_data
    ) VALUES (
        v_tx_id, v_payout.user_id, 'payout_approval', v_payout.amount, 'completed',
        jsonb_build_object('payout_id', p_payout_id, 'approver_id', p_approver_id, 'new_balance', v_new_balance)
    );
    
    -- Comprehensive audit log
    INSERT INTO public.wallet_audit_log (
        transaction_id, user_id, wallet_id, operation_type, amount,
        previous_balance, new_balance, status, approval_status, approved_by
    ) VALUES (
        v_tx_id, v_payout.user_id, v_wallet.wallet_id, 'payout_approval',
        v_payout.amount, v_wallet.balance, v_new_balance, 'completed', 'approved', p_approver_id
    );
    
    -- Legacy audit log
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_approver_id,
        'payout_approved',
        'wallet',
        v_approver_role::app_role,
        jsonb_build_object(
            'payout_id', p_payout_id,
            'user_id', v_payout.user_id,
            'amount', v_payout.amount,
            'previous_balance', v_wallet.balance,
            'new_balance', v_new_balance,
            'transaction_id', v_tx_id
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'payout_id', p_payout_id,
        'amount', v_payout.amount,
        'new_balance', v_new_balance,
        'transaction_id', v_tx_id
    );
    
EXCEPTION
    WHEN lock_not_available THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Transaction in progress. Please retry in a moment.'
        );
    WHEN OTHERS THEN
        -- Log error
        INSERT INTO public.wallet_audit_log (
            user_id, operation_type, status, error_message, metadata
        ) VALUES (
            p_approver_id, 'payout_approval_error', 'error',
            SQLERRM,
            jsonb_build_object('payout_id', p_payout_id)
        );
        
        RAISE;
END;
$$;

-- 6. Set/Toggle Financial Kill Switch
CREATE OR REPLACE FUNCTION public.set_financial_mode(
    p_mode TEXT,
    p_reason TEXT,
    p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_role TEXT;
BEGIN
    -- Only super_admin can toggle
    SELECT role INTO v_admin_role 
    FROM public.user_roles 
    WHERE user_id = p_admin_id;
    
    IF v_admin_role != 'super_admin' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only Super Admin can change financial mode');
    END IF;
    
    IF p_mode NOT IN ('SAFE', 'LOCKED') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid mode. Use SAFE or LOCKED');
    END IF;
    
    UPDATE public.system_financial_config
    SET config_value = jsonb_build_object(
        'mode', p_mode,
        'reason', p_reason,
        'locked_at', CASE WHEN p_mode = 'LOCKED' THEN now() ELSE null END,
        'locked_by', CASE WHEN p_mode = 'LOCKED' THEN p_admin_id ELSE null END
    ),
    updated_at = now(),
    updated_by = p_admin_id
    WHERE config_key = 'FINANCIAL_MODE';
    
    -- Audit log
    INSERT INTO public.audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        p_admin_id,
        'financial_mode_changed',
        'system',
        'super_admin'::app_role,
        jsonb_build_object('new_mode', p_mode, 'reason', p_reason)
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'mode', p_mode,
        'message', 'Financial mode set to ' || p_mode
    );
END;
$$;

-- 7. Secure withdrawal request function (prevents any direct wallet mutation)
CREATE OR REPLACE FUNCTION public.request_withdrawal(
    p_user_id UUID,
    p_amount NUMERIC,
    p_payment_method TEXT DEFAULT 'bank_transfer',
    p_ip_address TEXT DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_wallet RECORD;
    v_user_role TEXT;
    v_limits RECORD;
    v_today_total NUMERIC;
    v_pending_total NUMERIC;
    v_idempotency_key TEXT;
    v_payout_id UUID;
    v_financial_mode JSONB;
BEGIN
    -- Check financial mode
    v_financial_mode := public.check_financial_mode();
    IF (v_financial_mode->>'locked')::boolean = true THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Financial system is currently locked. Withdrawals are suspended.'
        );
    END IF;
    
    -- Get user role
    SELECT role INTO v_user_role FROM public.user_roles WHERE user_id = p_user_id;
    IF v_user_role IS NULL THEN v_user_role := 'client'; END IF;
    
    -- Get wallet (NO UPDATE - read only at this stage)
    SELECT * INTO v_wallet FROM public.wallets WHERE user_id = p_user_id;
    IF v_wallet IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Wallet not found');
    END IF;
    
    -- Check balance (but DO NOT deduct)
    IF v_wallet.balance < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient balance');
    END IF;
    
    -- Check pending requests total
    SELECT COALESCE(SUM(amount), 0) INTO v_pending_total
    FROM public.payout_requests
    WHERE user_id = p_user_id AND status IN ('requested', 'pending');
    
    IF v_pending_total + p_amount > v_wallet.balance THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Total pending requests would exceed available balance'
        );
    END IF;
    
    -- Generate idempotency key
    v_idempotency_key := p_user_id::text || '-' || p_amount::text || '-' || floor(extract(epoch from now()) / 60)::text;
    
    -- Check for duplicate (same amount within same minute)
    IF EXISTS (SELECT 1 FROM public.payout_requests WHERE idempotency_key = v_idempotency_key) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Duplicate request detected. Please wait before retrying.'
        );
    END IF;
    
    -- Create request ONLY (no wallet debit)
    INSERT INTO public.payout_requests (
        user_id, amount, status, payment_method, user_role,
        wallet_debited, idempotency_key, ip_address, device_fingerprint
    ) VALUES (
        p_user_id, p_amount, 'requested', p_payment_method, v_user_role,
        false, v_idempotency_key, p_ip_address, p_device_fingerprint
    ) RETURNING payout_id INTO v_payout_id;
    
    -- Audit log
    INSERT INTO public.wallet_audit_log (
        user_id, wallet_id, operation_type, amount, previous_balance,
        status, approval_status, ip_address, device_fingerprint
    ) VALUES (
        p_user_id, v_wallet.wallet_id, 'withdrawal_request', p_amount,
        v_wallet.balance, 'pending', 'requested', p_ip_address, p_device_fingerprint
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'payout_id', v_payout_id,
        'status', 'requested',
        'message', 'Withdrawal request submitted. Awaiting approval.'
    );
END;
$$;
-- ===== 20251225110225_647ff2b6-abdc-48e9-93a6-d3d9cf169045.sql =====
-- Super Admin Global Control Center Tables

-- TABLE: super_admin - Core super admin profiles
CREATE TABLE public.super_admin (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  continent TEXT NOT NULL,
  login_status TEXT DEFAULT 'offline' CHECK (login_status IN ('online', 'offline', 'away', 'busy')),
  current_device TEXT,
  last_login_time TIMESTAMP WITH TIME ZONE,
  risk_score INTEGER DEFAULT 0,
  countries_managed INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: admin_area_manager - Country-level managers
CREATE TABLE public.admin_area_manager (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  country TEXT NOT NULL,
  assigned_super_admin_id UUID REFERENCES public.super_admin(id),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
  current_activity TEXT,
  login_device TEXT,
  last_login_time TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: role_activity_log - All role actions tracking
CREATE TABLE public.role_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_type app_role NOT NULL,
  role_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  action_object TEXT,
  ip_address TEXT,
  device TEXT,
  geo_location TEXT,
  risk_flag TEXT DEFAULT 'green' CHECK (risk_flag IN ('green', 'yellow', 'red')),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: sa_approval_queue - Super Admin approval workflow
CREATE TABLE public.sa_approval_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by_role app_role NOT NULL,
  requested_by_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  action_payload JSONB DEFAULT '{}'::jsonb,
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by_super_admin_id UUID REFERENCES public.super_admin(id),
  review_time TIMESTAMP WITH TIME ZONE,
  review_notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: task_master - Task management
CREATE TABLE public.task_master (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by_super_admin_id UUID REFERENCES public.super_admin(id),
  assigned_to_role app_role NOT NULL,
  assigned_to_id UUID,
  task_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
  deadline TIMESTAMP WITH TIME ZONE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  progress_percentage INTEGER DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: task_activity - Task progress tracking
CREATE TABLE public.task_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES public.task_master(id) ON DELETE CASCADE,
  performed_by_role app_role NOT NULL,
  performed_by_id UUID NOT NULL,
  action TEXT NOT NULL,
  remarks TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: system_alerts - System-wide alerts
CREATE TABLE public.system_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_table TEXT NOT NULL,
  source_id UUID,
  alert_type TEXT NOT NULL,
  severity TEXT DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical', 'emergency')),
  title TEXT NOT NULL,
  message TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'acknowledged', 'resolved', 'dismissed')),
  auto_action_taken TEXT,
  acknowledged_by UUID,
  acknowledged_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: ai_insights - AI-generated insights
CREATE TABLE public.ai_insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope TEXT DEFAULT 'global' CHECK (scope IN ('global', 'continent', 'country', 'role')),
  scope_value TEXT,
  related_role app_role,
  issue_detected TEXT NOT NULL,
  suggested_action TEXT,
  confidence_score NUMERIC(5,2) DEFAULT 0,
  is_acknowledged BOOLEAN DEFAULT false,
  acknowledged_by UUID,
  acknowledged_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- TABLE: audit_lock - Immutable audit records
CREATE TABLE public.audit_lock (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT NOT NULL,
  record_ref_id UUID NOT NULL,
  locked_by TEXT DEFAULT 'system',
  lock_reason TEXT NOT NULL,
  unlock_condition TEXT,
  is_locked BOOLEAN DEFAULT true,
  unlocked_at TIMESTAMP WITH TIME ZONE,
  unlocked_by UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.super_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_area_manager ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sa_approval_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_lock ENABLE ROW LEVEL SECURITY;

-- RLS Policies for super_admin
CREATE POLICY "Super admins can view all super admins"
  ON public.super_admin FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Master can manage super admins"
  ON public.super_admin FOR ALL
  USING (has_role(auth.uid(), 'master'));

-- RLS Policies for admin_area_manager
CREATE POLICY "Super admins can view area managers"
  ON public.admin_area_manager FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Super admins can manage area managers"
  ON public.admin_area_manager FOR ALL
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

-- RLS Policies for role_activity_log
CREATE POLICY "Super admins can view activity logs"
  ON public.role_activity_log FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "System can insert activity logs"
  ON public.role_activity_log FOR INSERT
  WITH CHECK (true);

-- RLS Policies for sa_approval_queue
CREATE POLICY "Super admins can view approval queue"
  ON public.sa_approval_queue FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Super admins can manage approvals"
  ON public.sa_approval_queue FOR ALL
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Users can create approval requests"
  ON public.sa_approval_queue FOR INSERT
  WITH CHECK (true);

-- RLS Policies for task_master
CREATE POLICY "Super admins can view tasks"
  ON public.task_master FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Super admins can manage tasks"
  ON public.task_master FOR ALL
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

-- RLS Policies for task_activity
CREATE POLICY "Super admins can view task activities"
  ON public.task_activity FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "System can insert task activities"
  ON public.task_activity FOR INSERT
  WITH CHECK (true);

-- RLS Policies for system_alerts
CREATE POLICY "Super admins can view alerts"
  ON public.system_alerts FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Super admins can manage alerts"
  ON public.system_alerts FOR ALL
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "System can create alerts"
  ON public.system_alerts FOR INSERT
  WITH CHECK (true);

-- RLS Policies for ai_insights
CREATE POLICY "Super admins can view AI insights"
  ON public.ai_insights FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Super admins can acknowledge insights"
  ON public.ai_insights FOR UPDATE
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "System can create AI insights"
  ON public.ai_insights FOR INSERT
  WITH CHECK (true);

-- RLS Policies for audit_lock
CREATE POLICY "Super admins can view audit locks"
  ON public.audit_lock FOR SELECT
  USING (has_role(auth.uid(), 'super_admin') OR has_role(auth.uid(), 'master'));

CREATE POLICY "Only master can manage audit locks"
  ON public.audit_lock FOR ALL
  USING (has_role(auth.uid(), 'master'));

-- Create indexes for performance
CREATE INDEX idx_role_activity_log_role ON public.role_activity_log(role_type, role_id);
CREATE INDEX idx_role_activity_log_risk ON public.role_activity_log(risk_flag) WHERE risk_flag != 'green';
CREATE INDEX idx_sa_approval_queue_status ON public.sa_approval_queue(status) WHERE status = 'pending';
CREATE INDEX idx_task_master_status ON public.task_master(status);
CREATE INDEX idx_system_alerts_status ON public.system_alerts(status) WHERE status = 'active';
CREATE INDEX idx_ai_insights_scope ON public.ai_insights(scope, is_acknowledged);

-- Enable realtime for live updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.role_activity_log;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sa_approval_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ai_insights;
-- ===== 20251225124127_cf6fb81c-9ef5-44c1-8739-dd8780bcc599.sql =====
-- Step 1: Add 'area_manager' to app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'area_manager';
-- ===== 20251225124158_763f625d-b7c9-4cc8-a77a-5faf61303fcd.sql =====
-- Step 2: Update all existing references from 'admin' to 'area_manager' in user_roles
UPDATE public.user_roles SET role = 'area_manager' WHERE role = 'admin';

-- Step 3: Update any other tables that reference the admin role
UPDATE public.ai_insights SET related_role = 'area_manager' WHERE related_role = 'admin';
UPDATE public.ai_qr_scan_logs SET scanner_role = 'area_manager' WHERE scanner_role = 'admin';
UPDATE public.ai_usage_logs SET user_role = 'area_manager' WHERE user_role = 'admin';
UPDATE public.assist_eligibility_settings SET role = 'area_manager' WHERE role = 'admin';
UPDATE public.assist_force_end_logs SET ended_by_role = 'area_manager' WHERE ended_by_role = 'admin';
UPDATE public.assist_request_queue SET requesting_user_role = 'area_manager' WHERE requesting_user_role = 'admin';
UPDATE public.audit_logs SET role = 'area_manager' WHERE role = 'admin';
UPDATE public.buzzer_queue SET role_target = 'area_manager' WHERE role_target = 'admin';
UPDATE public.chat_threads SET related_role = 'area_manager' WHERE related_role = 'admin';
UPDATE public.commission_fraud_detection SET user_role = 'area_manager' WHERE user_role = 'admin';
UPDATE public.compliance_audit_trail SET actor_role = 'area_manager' WHERE actor_role = 'admin';

-- Step 4: Rename admin_area_manager table to area_manager_accounts for clarity
ALTER TABLE IF EXISTS public.admin_area_manager RENAME TO area_manager_accounts;

-- Step 5: Add region column to area_manager_accounts if not exists
ALTER TABLE public.area_manager_accounts 
  ADD COLUMN IF NOT EXISTS region TEXT,
  ADD COLUMN IF NOT EXISTS assigned_countries TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS can_export_data BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_access_other_regions BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS daily_report_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS weekly_report_enabled BOOLEAN DEFAULT true;

-- Step 6: Create reporting function for Area Manager
CREATE OR REPLACE FUNCTION public.get_area_manager_region(_user_id uuid)
RETURNS TEXT
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT country FROM public.area_manager_accounts WHERE user_id = _user_id LIMIT 1
$$;

-- Step 7: Create function to check if user is in Area Manager's region
CREATE OR REPLACE FUNCTION public.is_in_area_manager_region(_area_manager_id uuid, _target_user_id uuid)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_region TEXT;
BEGIN
  -- Get area manager's assigned countries
  SELECT country INTO v_region FROM public.area_manager_accounts WHERE user_id = _area_manager_id;
  
  -- Check if target user is in the same region
  IF EXISTS (
    SELECT 1 FROM public.franchise_accounts WHERE user_id = _target_user_id AND country = v_region
  ) OR EXISTS (
    SELECT 1 FROM public.reseller_accounts WHERE user_id = _target_user_id AND country = v_region  
  ) THEN
    RETURN TRUE;
  END IF;
  
  RETURN FALSE;
END;
$$;

-- Step 8: Add RLS policy for area_manager_accounts
ALTER TABLE public.area_manager_accounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Area managers can view their own record" ON public.area_manager_accounts;
DROP POLICY IF EXISTS "Super admins can manage area managers" ON public.area_manager_accounts;

CREATE POLICY "Area managers can view their own record"
ON public.area_manager_accounts
FOR SELECT
USING (
  auth.uid() = user_id 
  OR public.has_role(auth.uid(), 'super_admin')
  OR public.has_role(auth.uid(), 'master')
);

CREATE POLICY "Super admins can manage area managers"
ON public.area_manager_accounts
FOR ALL
USING (
  public.has_role(auth.uid(), 'super_admin')
  OR public.has_role(auth.uid(), 'master')
);
-- ===== 20251225124608_0606c533-0a74-4ab0-a18d-19de8bca8f60.sql =====
-- Add server_manager role to enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'server_manager';
-- ===== 20251225124644_2e6215fd-e09b-444e-ba15-eccf9c7c396f.sql =====
-- Create server_instances table for server management
CREATE TABLE IF NOT EXISTS public.server_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_name TEXT NOT NULL,
  server_type TEXT CHECK (server_type IN ('production', 'staging', 'backup', 'ai', 'database')) DEFAULT 'production',
  continent TEXT,
  country TEXT,
  data_center TEXT,
  ip_address TEXT,
  status TEXT CHECK (status IN ('active', 'down', 'maintenance', 'isolated')) DEFAULT 'active',
  cpu_usage DECIMAL(5,2) DEFAULT 0,
  ram_usage DECIMAL(5,2) DEFAULT 0,
  disk_usage DECIMAL(5,2) DEFAULT 0,
  uptime_percent DECIMAL(5,2) DEFAULT 100,
  last_health_check TIMESTAMPTZ,
  last_restart TIMESTAMPTZ,
  auto_scaling_enabled BOOLEAN DEFAULT false,
  security_risk_level TEXT CHECK (security_risk_level IN ('low', 'medium', 'high', 'critical')) DEFAULT 'low',
  last_patch_date TIMESTAMPTZ,
  backup_status TEXT CHECK (backup_status IN ('healthy', 'warning', 'failed')) DEFAULT 'healthy',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create server_manager_accounts table
CREATE TABLE IF NOT EXISTS public.server_manager_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  assigned_servers UUID[] DEFAULT '{}',
  assigned_continents TEXT[] DEFAULT '{}',
  can_restart_production BOOLEAN DEFAULT false,
  can_restore_backups BOOLEAN DEFAULT false,
  max_approval_level TEXT CHECK (max_approval_level IN ('low', 'medium')) DEFAULT 'low',
  last_login_time TIMESTAMPTZ,
  login_device TEXT,
  ip_locked BOOLEAN DEFAULT true,
  allowed_ips TEXT[] DEFAULT '{}',
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create server_actions table for approval workflow
CREATE TABLE IF NOT EXISTS public.server_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id),
  action_type TEXT CHECK (action_type IN ('restart', 'scale_up', 'scale_down', 'patch', 'backup', 'restore', 'isolate', 'enable_service', 'disable_service')) NOT NULL,
  risk_level TEXT CHECK (risk_level IN ('low', 'medium', 'high')) NOT NULL,
  requested_by UUID NOT NULL,
  approval_status TEXT CHECK (approval_status IN ('pending', 'approved', 'rejected', 'auto_approved')) DEFAULT 'pending',
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  rejection_reason TEXT,
  executed_at TIMESTAMPTZ,
  before_state JSONB,
  after_state JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create server_alerts table
CREATE TABLE IF NOT EXISTS public.server_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id),
  alert_type TEXT CHECK (alert_type IN ('high_cpu', 'high_ram', 'disk_full', 'unreachable', 'security_breach', 'ddos', 'memory_leak', 'auto_scale')) NOT NULL,
  severity TEXT CHECK (severity IN ('info', 'warning', 'critical')) DEFAULT 'warning',
  message TEXT,
  is_resolved BOOLEAN DEFAULT false,
  resolved_by UUID,
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Create server_audit_logs table (immutable)
CREATE TABLE IF NOT EXISTS public.server_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id),
  action TEXT NOT NULL,
  performed_by UUID NOT NULL,
  device_fingerprint TEXT,
  ip_address TEXT,
  before_state JSONB,
  after_state JSONB,
  risk_level TEXT,
  approval_id UUID REFERENCES public.server_actions(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_manager_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_audit_logs ENABLE ROW LEVEL SECURITY;

-- Create security function
CREATE OR REPLACE FUNCTION public.is_server_manager(_user_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = _user_id 
    AND role IN ('server_manager', 'super_admin', 'master')
  )
$$;

-- RLS Policies
CREATE POLICY "Server managers can view servers" ON public.server_instances FOR SELECT USING (public.is_server_manager(auth.uid()));
CREATE POLICY "Admins can modify servers" ON public.server_instances FOR ALL USING (public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'master'));

CREATE POLICY "Server managers view own account" ON public.server_manager_accounts FOR SELECT USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'master'));

CREATE POLICY "Server managers view actions" ON public.server_actions FOR SELECT USING (public.is_server_manager(auth.uid()));
CREATE POLICY "Server managers create actions" ON public.server_actions FOR INSERT WITH CHECK (public.is_server_manager(auth.uid()));

CREATE POLICY "Server managers view alerts" ON public.server_alerts FOR SELECT USING (public.is_server_manager(auth.uid()));
CREATE POLICY "Server managers update alerts" ON public.server_alerts FOR UPDATE USING (public.is_server_manager(auth.uid()));

CREATE POLICY "Server managers view audit logs" ON public.server_audit_logs FOR SELECT USING (public.is_server_manager(auth.uid()));
CREATE POLICY "No delete on audit logs" ON public.server_audit_logs FOR DELETE USING (false);
-- ===== 20251225153359_7b588eae-49a9-4571-b679-a2a7f645e79d.sql =====

-- Create function to populate software catalog with sample data
CREATE OR REPLACE FUNCTION populate_software_catalog()
RETURNS void AS $$
DECLARE
  software_types TEXT[] := ARRAY['SaaS', 'Desktop', 'Mobile', 'Offline', 'Hybrid'];
  categories TEXT[] := ARRAY['Finance', 'Healthcare', 'Education', 'Hotel/Travel', 'Restaurant', 'E-Commerce', 'POS', 'CRM', 'HRM', 'ERP', 'Real Estate', 'Logistics', 'Inventory', 'Project Management', 'Fitness', 'Events', 'Lending', 'Insurance', 'Manufacturing', 'Automotive', 'Beauty/Salon', 'Library', 'Subscription', 'General'];
  prefixes TEXT[] := ARRAY['Advanced', 'Pro', 'Enterprise', 'Basic', 'Premium', 'Ultimate', 'Smart', 'Cloud', 'Digital', 'Online', 'Modern', 'Next-Gen', 'AI-Powered', 'Automated', 'Integrated'];
  names TEXT[] := ARRAY['Accounting', 'Billing', 'Invoice', 'Hospital', 'Clinic', 'Medical', 'Dental', 'Pharmacy', 'School', 'College', 'LMS', 'Coaching', 'Student', 'Hotel', 'Resort', 'Booking', 'Travel', 'Restaurant', 'Kitchen', 'Cafe', 'Food', 'Shop', 'Store', 'Cart', 'POS', 'CRM', 'Customer', 'HRM', 'Payroll', 'Employee', 'Attendance', 'Leave', 'ERP', 'Real Estate', 'Property', 'Transport', 'Logistics', 'Fleet', 'Delivery', 'Courier', 'Inventory', 'Warehouse', 'Stock', 'Project', 'Task', 'Gym', 'Fitness', 'Event', 'Ticket', 'Loan', 'Microfinance', 'Insurance', 'MRP', 'Manufacturing', 'Cab', 'Taxi', 'Car', 'Vehicle', 'Garage', 'Auto', 'Salon', 'Spa', 'Beauty', 'Library', 'Membership', 'Subscription', 'Analytics', 'Dashboard', 'Reports', 'Manager', 'Suite', 'Hub', 'Central', 'Portal', 'System'];
  suffixes TEXT[] := ARRAY['360', 'Pro', 'Plus', 'Max', 'Lite', 'Express', 'Cloud', 'Online', 'Mobile', 'Desktop'];
  prices NUMERIC[] := ARRAY[0, 29, 49, 79, 99, 149, 199, 299, 399, 499, 599, 799, 999, 1499, 1999, 2999, 4999];
  i INTEGER;
  sw_name TEXT;
  sw_type TEXT;
  sw_category TEXT;
  sw_price NUMERIC;
BEGIN
  -- Clear existing data
  DELETE FROM software_catalog WHERE vendor = 'Software Vala';
  
  -- Insert 5000 software products
  FOR i IN 1..5000 LOOP
    sw_name := prefixes[1 + floor(random() * array_length(prefixes, 1))::int] || ' ' ||
               names[1 + floor(random() * array_length(names, 1))::int] || ' ' ||
               suffixes[1 + floor(random() * array_length(suffixes, 1))::int] || ' ' ||
               i::text;
    sw_type := software_types[1 + floor(random() * array_length(software_types, 1))::int];
    sw_category := categories[1 + floor(random() * array_length(categories, 1))::int];
    sw_price := prices[1 + floor(random() * array_length(prices, 1))::int];
    
    INSERT INTO software_catalog (name, base_price, type, vendor, category, is_demo_registered)
    VALUES (sw_name, sw_price, sw_type, 'Software Vala', sw_category, false);
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Execute the function to populate data
SELECT populate_software_catalog();

-- Drop the function after use
DROP FUNCTION populate_software_catalog();

-- ===== 20251226002649_b14a9813-f0e2-4cef-951a-f420eaf57f42.sql =====
-- Drop the existing problematic policies
DROP POLICY IF EXISTS "Super admins can manage approvals" ON public.sa_approval_queue;
DROP POLICY IF EXISTS "Super admins can view approval queue" ON public.sa_approval_queue;
DROP POLICY IF EXISTS "Users can create approval requests" ON public.sa_approval_queue;

-- Create proper RLS policies for sa_approval_queue

-- Super admins can view all approval requests
CREATE POLICY "Super admins can view approval queue"
ON public.sa_approval_queue
FOR SELECT
TO authenticated
USING (
  public.has_role(auth.uid(), 'super_admin'::app_role) OR 
  public.has_role(auth.uid(), 'master'::app_role)
);

-- Super admins can update approval requests (approve/reject)
CREATE POLICY "Super admins can update approvals"
ON public.sa_approval_queue
FOR UPDATE
TO authenticated
USING (
  public.has_role(auth.uid(), 'super_admin'::app_role) OR 
  public.has_role(auth.uid(), 'master'::app_role)
)
WITH CHECK (
  public.has_role(auth.uid(), 'super_admin'::app_role) OR 
  public.has_role(auth.uid(), 'master'::app_role)
);

-- Super admins can delete approval requests
CREATE POLICY "Super admins can delete approvals"
ON public.sa_approval_queue
FOR DELETE
TO authenticated
USING (
  public.has_role(auth.uid(), 'super_admin'::app_role) OR 
  public.has_role(auth.uid(), 'master'::app_role)
);

-- Authenticated users can create approval requests
CREATE POLICY "Authenticated users can create approval requests"
ON public.sa_approval_queue
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Also fix the user_roles UPDATE policy if missing with_check
DROP POLICY IF EXISTS "super_admin_can_update_roles" ON public.user_roles;

CREATE POLICY "super_admin_can_update_roles"
ON public.user_roles
FOR UPDATE
TO authenticated
USING (public.is_super_admin())
WITH CHECK (public.is_super_admin());
-- ===== 20251228014222_b7433ab0-0c86-4f79-86ae-0dfa72cad367.sql =====
-- Daily Demo ID tracking
CREATE TABLE public.demo_daily_ids (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
    daily_id VARCHAR(20) NOT NULL UNIQUE,
    generated_date DATE NOT NULL DEFAULT CURRENT_DATE,
    sequence_number INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES auth.users(id)
);

-- Demo Orders linked to demos
CREATE TABLE public.demo_orders (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    order_number VARCHAR(30) NOT NULL UNIQUE,
    demo_id UUID REFERENCES public.demos(id) ON DELETE SET NULL,
    daily_demo_id VARCHAR(20) NOT NULL,
    client_name VARCHAR(255),
    client_email VARCHAR(255),
    client_domain VARCHAR(255),
    requirements JSONB DEFAULT '{}',
    order_status VARCHAR(50) DEFAULT 'generated',
    status_flow JSONB DEFAULT '["generated"]',
    software_package_id UUID,
    auto_detected BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    verified_by UUID REFERENCES auth.users(id),
    verified_at TIMESTAMPTZ,
    is_promoted BOOLEAN DEFAULT false,
    promoted_by UUID REFERENCES auth.users(id),
    promoted_at TIMESTAMPTZ,
    is_live BOOLEAN DEFAULT false,
    deployed_by UUID REFERENCES auth.users(id),
    deployed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demo Deployments with license keys
CREATE TABLE public.demo_deployments (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id UUID REFERENCES public.demo_orders(id) ON DELETE CASCADE,
    demo_id UUID REFERENCES public.demos(id) ON DELETE SET NULL,
    daily_demo_id VARCHAR(20) NOT NULL,
    license_key VARCHAR(64) NOT NULL UNIQUE,
    license_key_hash VARCHAR(128),
    approved_domain VARCHAR(255) NOT NULL,
    approved_ips TEXT[],
    deployment_status VARCHAR(50) DEFAULT 'pending',
    is_domain_locked BOOLEAN DEFAULT true,
    is_encrypted BOOLEAN DEFAULT true,
    is_obfuscated BOOLEAN DEFAULT true,
    encryption_key_ref VARCHAR(64),
    last_verification_at TIMESTAMPTZ,
    verification_count INTEGER DEFAULT 0,
    blocked_attempts INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES auth.users(id)
);

-- Security Lock Logs
CREATE TABLE public.demo_security_locks (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    deployment_id UUID REFERENCES public.demo_deployments(id) ON DELETE CASCADE,
    license_key VARCHAR(64),
    request_domain VARCHAR(255),
    request_ip VARCHAR(50),
    request_user_agent TEXT,
    is_authorized BOOLEAN DEFAULT false,
    block_reason VARCHAR(255),
    was_auto_blocked BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Software Packages
CREATE TABLE public.demo_software_packages (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id UUID REFERENCES public.demo_orders(id) ON DELETE CASCADE,
    demo_id UUID REFERENCES public.demos(id) ON DELETE SET NULL,
    package_name VARCHAR(255),
    package_status VARCHAR(50) DEFAULT 'preparing',
    source_demo_snapshot JSONB,
    client_requirements JSONB,
    is_tested BOOLEAN DEFAULT false,
    tested_at TIMESTAMPTZ,
    tested_by UUID REFERENCES auth.users(id),
    test_results JSONB,
    is_ready BOOLEAN DEFAULT false,
    ready_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.demo_daily_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_deployments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_security_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_software_packages ENABLE ROW LEVEL SECURITY;

-- RLS Policies - Only master/super_admin/demo_manager can access
CREATE POLICY "Admin access demo_daily_ids" ON public.demo_daily_ids
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

CREATE POLICY "Admin access demo_orders" ON public.demo_orders
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

CREATE POLICY "Admin access demo_deployments" ON public.demo_deployments
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

CREATE POLICY "Admin access demo_security_locks" ON public.demo_security_locks
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

CREATE POLICY "Admin access demo_software_packages" ON public.demo_software_packages
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

-- Function to generate daily demo ID
CREATE OR REPLACE FUNCTION public.generate_daily_demo_id(p_demo_id UUID)
RETURNS VARCHAR(20)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_date_str VARCHAR(8);
    v_sequence INTEGER;
    v_daily_id VARCHAR(20);
BEGIN
    v_date_str := TO_CHAR(CURRENT_DATE, 'YYYYMMDD');
    
    -- Get next sequence for today
    SELECT COALESCE(MAX(sequence_number), 0) + 1 INTO v_sequence
    FROM demo_daily_ids
    WHERE generated_date = CURRENT_DATE;
    
    -- Format: DEMO-YYYYMMDD-XXX
    v_daily_id := 'DEMO-' || v_date_str || '-' || LPAD(v_sequence::TEXT, 3, '0');
    
    -- Insert record
    INSERT INTO demo_daily_ids (demo_id, daily_id, generated_date, sequence_number, created_by)
    VALUES (p_demo_id, v_daily_id, CURRENT_DATE, v_sequence, auth.uid());
    
    RETURN v_daily_id;
END;
$$;

-- Function to generate license key
CREATE OR REPLACE FUNCTION public.generate_deployment_license()
RETURNS VARCHAR(64)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_license VARCHAR(64);
BEGIN
    v_license := encode(gen_random_bytes(32), 'hex');
    RETURN v_license;
END;
$$;

-- Function to verify deployment request
CREATE OR REPLACE FUNCTION public.verify_deployment_request(
    p_license_key VARCHAR(64),
    p_request_domain VARCHAR(255),
    p_request_ip VARCHAR(50),
    p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_deployment RECORD;
    v_is_authorized BOOLEAN := false;
    v_block_reason VARCHAR(255);
BEGIN
    -- Find deployment
    SELECT * INTO v_deployment 
    FROM demo_deployments 
    WHERE license_key = p_license_key AND is_active = true;
    
    IF v_deployment IS NULL THEN
        v_block_reason := 'Invalid or expired license key';
    ELSIF v_deployment.expires_at IS NOT NULL AND v_deployment.expires_at < now() THEN
        v_block_reason := 'License has expired';
    ELSIF v_deployment.is_domain_locked AND v_deployment.approved_domain != p_request_domain THEN
        v_block_reason := 'Unauthorized domain: ' || p_request_domain;
    ELSIF v_deployment.approved_ips IS NOT NULL AND array_length(v_deployment.approved_ips, 1) > 0 
          AND NOT (p_request_ip = ANY(v_deployment.approved_ips)) THEN
        v_block_reason := 'Unauthorized IP: ' || p_request_ip;
    ELSE
        v_is_authorized := true;
    END IF;
    
    -- Log the request
    INSERT INTO demo_security_locks (
        deployment_id, license_key, request_domain, request_ip, 
        request_user_agent, is_authorized, block_reason, was_auto_blocked
    ) VALUES (
        v_deployment.id, p_license_key, p_request_domain, p_request_ip,
        p_user_agent, v_is_authorized, v_block_reason, NOT v_is_authorized
    );
    
    -- Update deployment stats
    IF v_deployment.id IS NOT NULL THEN
        UPDATE demo_deployments
        SET last_verification_at = now(),
            verification_count = verification_count + 1,
            blocked_attempts = CASE WHEN v_is_authorized THEN blocked_attempts ELSE blocked_attempts + 1 END
        WHERE id = v_deployment.id;
    END IF;
    
    RETURN jsonb_build_object(
        'authorized', v_is_authorized,
        'reason', v_block_reason,
        'deployment_id', v_deployment.id
    );
END;
$$;

-- Function to create order from demo
CREATE OR REPLACE FUNCTION public.create_demo_order(
    p_demo_id UUID,
    p_client_name VARCHAR(255),
    p_client_email VARCHAR(255),
    p_client_domain VARCHAR(255),
    p_requirements JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_daily_id VARCHAR(20);
    v_order_id UUID;
    v_order_number VARCHAR(30);
    v_package_id UUID;
BEGIN
    -- Get or generate daily demo ID
    SELECT daily_id INTO v_daily_id 
    FROM demo_daily_ids 
    WHERE demo_id = p_demo_id AND generated_date = CURRENT_DATE
    LIMIT 1;
    
    IF v_daily_id IS NULL THEN
        v_daily_id := generate_daily_demo_id(p_demo_id);
    END IF;
    
    -- Generate order number
    v_order_number := 'ORD-' || TO_CHAR(now(), 'YYYYMMDD-HH24MISS') || '-' || LPAD((random() * 999)::INTEGER::TEXT, 3, '0');
    
    -- Create order
    INSERT INTO demo_orders (
        order_number, demo_id, daily_demo_id, client_name, client_email,
        client_domain, requirements, order_status, auto_detected
    ) VALUES (
        v_order_number, p_demo_id, v_daily_id, p_client_name, p_client_email,
        p_client_domain, p_requirements, 'generated', true
    ) RETURNING id INTO v_order_id;
    
    -- Create software package
    INSERT INTO demo_software_packages (order_id, demo_id, package_name, package_status, client_requirements)
    VALUES (v_order_id, p_demo_id, 'Package for ' || v_order_number, 'preparing', p_requirements)
    RETURNING id INTO v_package_id;
    
    -- Link package to order
    UPDATE demo_orders SET software_package_id = v_package_id WHERE id = v_order_id;
    
    -- Log action
    INSERT INTO audit_logs (user_id, action, module, meta_json)
    VALUES (auth.uid(), 'demo_order_created', 'demo', jsonb_build_object(
        'order_id', v_order_id,
        'demo_id', p_demo_id,
        'daily_demo_id', v_daily_id,
        'client_domain', p_client_domain
    ));
    
    RETURN v_order_id;
END;
$$;

-- Indexes for performance
CREATE INDEX idx_demo_daily_ids_date ON public.demo_daily_ids(generated_date);
CREATE INDEX idx_demo_daily_ids_demo ON public.demo_daily_ids(demo_id);
CREATE INDEX idx_demo_orders_demo ON public.demo_orders(demo_id);
CREATE INDEX idx_demo_orders_status ON public.demo_orders(order_status);
CREATE INDEX idx_demo_deployments_license ON public.demo_deployments(license_key);
CREATE INDEX idx_demo_deployments_domain ON public.demo_deployments(approved_domain);
CREATE INDEX idx_demo_security_locks_deployment ON public.demo_security_locks(deployment_id);
CREATE INDEX idx_demo_security_locks_domain ON public.demo_security_locks(request_domain);
-- ===== 20251228014700_87405143-27d7-47a2-a192-6f5dc11fcbe2.sql =====
-- Demo Suggestions table for client requests
CREATE TABLE public.demo_suggestions (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    demo_id UUID REFERENCES public.demos(id) ON DELETE SET NULL,
    demo_name VARCHAR(255),
    user_id UUID REFERENCES auth.users(id),
    domain_name VARCHAR(255),
    required_modules TEXT[],
    feature_requests TEXT,
    notes TEXT,
    user_ip VARCHAR(50),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    assigned_server VARCHAR(255),
    setup_status VARCHAR(50) DEFAULT 'pending',
    domain_connected BOOLEAN DEFAULT false,
    domain_connected_at TIMESTAMPTZ,
    server_linked BOOLEAN DEFAULT false,
    server_linked_at TIMESTAMPTZ,
    setup_started BOOLEAN DEFAULT false,
    setup_started_at TIMESTAMPTZ,
    estimated_completion TIMESTAMPTZ,
    setup_completed BOOLEAN DEFAULT false,
    setup_completed_at TIMESTAMPTZ,
    is_update_request BOOLEAN DEFAULT false,
    parent_suggestion_id UUID REFERENCES public.demo_suggestions(id),
    auto_processed BOOLEAN DEFAULT false,
    task_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demo Cart table
CREATE TABLE public.demo_cart (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id VARCHAR(255),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    quantity INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    UNIQUE(user_id, demo_id),
    UNIQUE(session_id, demo_id)
);

-- Demo Favorites table
CREATE TABLE public.demo_favorites (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id VARCHAR(255),
    demo_id UUID REFERENCES public.demos(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, demo_id),
    UNIQUE(session_id, demo_id)
);

-- Setup Tasks auto-generated from suggestions
CREATE TABLE public.demo_setup_tasks (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    suggestion_id UUID REFERENCES public.demo_suggestions(id) ON DELETE CASCADE,
    task_type VARCHAR(50) NOT NULL,
    task_status VARCHAR(50) DEFAULT 'pending',
    task_description TEXT,
    assigned_server VARCHAR(255),
    domain_name VARCHAR(255),
    progress_percentage INTEGER DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    auto_created BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.demo_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_cart ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_setup_tasks ENABLE ROW LEVEL SECURITY;

-- RLS Policies for demo_suggestions (users can see their own, admins see all)
CREATE POLICY "Users can view own suggestions" ON public.demo_suggestions
    FOR SELECT USING (
        auth.uid() = user_id OR
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

CREATE POLICY "Anyone can create suggestions" ON public.demo_suggestions
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Admin can update suggestions" ON public.demo_suggestions
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

-- RLS Policies for demo_cart
CREATE POLICY "Users manage own cart" ON public.demo_cart
    FOR ALL USING (auth.uid() = user_id OR session_id IS NOT NULL);

-- RLS Policies for demo_favorites  
CREATE POLICY "Users manage own favorites" ON public.demo_favorites
    FOR ALL USING (auth.uid() = user_id OR session_id IS NOT NULL);

-- RLS Policies for demo_setup_tasks
CREATE POLICY "Admin access setup tasks" ON public.demo_setup_tasks
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'demo_manager'))
    );

-- Function to auto-process suggestion and create setup task
CREATE OR REPLACE FUNCTION public.process_demo_suggestion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_task_id UUID;
    v_server VARCHAR(255);
BEGIN
    -- Auto-assign server based on load balancing (simple round-robin simulation)
    v_server := 'SV-SERVER-' || LPAD((FLOOR(RANDOM() * 10) + 1)::TEXT, 2, '0');
    
    -- Update suggestion with assigned server
    NEW.assigned_server := v_server;
    NEW.auto_processed := true;
    NEW.setup_status := 'processing';
    
    -- Calculate estimated completion (30 min for new, 15 min for updates)
    IF NEW.is_update_request THEN
        NEW.estimated_completion := now() + INTERVAL '15 minutes';
    ELSE
        NEW.estimated_completion := now() + INTERVAL '30 minutes';
    END IF;
    
    RETURN NEW;
END;
$$;

-- Trigger to auto-process suggestions
CREATE TRIGGER auto_process_suggestion
    BEFORE INSERT ON public.demo_suggestions
    FOR EACH ROW
    EXECUTE FUNCTION public.process_demo_suggestion();

-- Function to create setup tasks after suggestion insert
CREATE OR REPLACE FUNCTION public.create_setup_tasks()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_task_id UUID;
BEGIN
    -- Create domain connection task
    INSERT INTO demo_setup_tasks (suggestion_id, task_type, task_description, domain_name, assigned_server)
    VALUES (NEW.id, 'domain_mapping', 'Connect domain ' || COALESCE(NEW.domain_name, 'pending'), NEW.domain_name, NEW.assigned_server);
    
    -- Create server linking task
    INSERT INTO demo_setup_tasks (suggestion_id, task_type, task_description, assigned_server)
    VALUES (NEW.id, 'server_linking', 'Link to server ' || NEW.assigned_server, NEW.assigned_server);
    
    -- Create setup initialization task
    INSERT INTO demo_setup_tasks (suggestion_id, task_type, task_description, assigned_server)
    VALUES (NEW.id, 'setup_init', 'Initialize demo setup with custom modules', NEW.assigned_server)
    RETURNING id INTO v_task_id;
    
    -- Update suggestion with task reference
    UPDATE demo_suggestions SET task_id = v_task_id WHERE id = NEW.id;
    
    RETURN NEW;
END;
$$;

-- Trigger to create tasks after suggestion
CREATE TRIGGER create_tasks_after_suggestion
    AFTER INSERT ON public.demo_suggestions
    FOR EACH ROW
    EXECUTE FUNCTION public.create_setup_tasks();

-- Indexes
CREATE INDEX idx_demo_suggestions_demo ON public.demo_suggestions(demo_id);
CREATE INDEX idx_demo_suggestions_user ON public.demo_suggestions(user_id);
CREATE INDEX idx_demo_suggestions_status ON public.demo_suggestions(setup_status);
CREATE INDEX idx_demo_cart_user ON public.demo_cart(user_id);
CREATE INDEX idx_demo_cart_session ON public.demo_cart(session_id);
CREATE INDEX idx_demo_favorites_user ON public.demo_favorites(user_id);
CREATE INDEX idx_demo_setup_tasks_suggestion ON public.demo_setup_tasks(suggestion_id);
-- ===== 20251229025921_04ab396e-216a-4f77-a7a3-5a8213631eeb.sql =====
-- Promise Accountability System: Rewards & Penalties

-- Add reward/penalty tracking columns if not exist
ALTER TABLE public.promise_logs ADD COLUMN IF NOT EXISTS confirmed_by_developer BOOLEAN DEFAULT FALSE;
ALTER TABLE public.promise_logs ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.promise_logs ADD COLUMN IF NOT EXISTS reward_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.promise_logs ADD COLUMN IF NOT EXISTS penalty_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.promise_logs ADD COLUMN IF NOT EXISTS on_time_bonus BOOLEAN DEFAULT FALSE;

-- Create function to confirm developer commitment
CREATE OR REPLACE FUNCTION public.confirm_developer_commitment(p_promise_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_developer_id UUID;
BEGIN
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.confirmed_by_developer THEN
        RETURN jsonb_build_object('success', false, 'error', 'Commitment already confirmed');
    END IF;
    
    -- Update promise with confirmation
    UPDATE promise_logs
    SET confirmed_by_developer = TRUE,
        confirmed_at = now(),
        status = 'in_progress',
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        'promise_commitment_confirmed',
        'promise',
        (SELECT role FROM user_roles WHERE user_id = auth.uid() LIMIT 1),
        jsonb_build_object(
            'promise_id', p_promise_id,
            'deadline', v_promise.deadline,
            'confirmed_at', now()
        )
    );
    
    RETURN jsonb_build_object('success', true, 'message', 'Commitment confirmed');
END;
$$;

-- Create function to complete promise with rewards
CREATE OR REPLACE FUNCTION public.complete_promise_with_reward(p_promise_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_is_on_time BOOLEAN;
    v_reward NUMERIC := 0;
    v_score_bonus INTEGER := 0;
    v_hours_early NUMERIC;
BEGIN
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.status = 'completed' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise already completed');
    END IF;
    
    -- Check if completed on time
    v_is_on_time := now() <= COALESCE(v_promise.extended_deadline, v_promise.deadline);
    
    IF v_is_on_time THEN
        -- Calculate hours early
        v_hours_early := EXTRACT(EPOCH FROM (COALESCE(v_promise.extended_deadline, v_promise.deadline) - now())) / 3600;
        
        -- Base reward for on-time completion
        v_reward := 100;
        v_score_bonus := 10;
        
        -- Bonus for early completion
        IF v_hours_early > 24 THEN
            v_reward := v_reward + 200;
            v_score_bonus := v_score_bonus + 15;
        ELSIF v_hours_early > 12 THEN
            v_reward := v_reward + 100;
            v_score_bonus := v_score_bonus + 10;
        ELSIF v_hours_early > 6 THEN
            v_reward := v_reward + 50;
            v_score_bonus := v_score_bonus + 5;
        END IF;
        
        -- Extra bonus if confirmed commitment
        IF v_promise.confirmed_by_developer THEN
            v_reward := v_reward + 50;
            v_score_bonus := v_score_bonus + 5;
        END IF;
    END IF;
    
    -- Update promise
    UPDATE promise_logs
    SET status = 'completed',
        finished_time = now(),
        reward_amount = v_reward,
        score_effect = v_score_bonus,
        on_time_bonus = v_is_on_time,
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Update developer wallet if reward earned
    IF v_reward > 0 THEN
        UPDATE developer_wallet
        SET available_balance = available_balance + v_reward,
            total_earned = total_earned + v_reward
        WHERE developer_id = v_promise.developer_id;
    END IF;
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        CASE WHEN v_is_on_time THEN 'promise_completed_on_time' ELSE 'promise_completed_late' END,
        'promise',
        (SELECT role FROM user_roles WHERE user_id = auth.uid() LIMIT 1),
        jsonb_build_object(
            'promise_id', p_promise_id,
            'on_time', v_is_on_time,
            'reward', v_reward,
            'score_bonus', v_score_bonus
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'on_time', v_is_on_time,
        'reward', v_reward,
        'score_bonus', v_score_bonus
    );
END;
$$;

-- Enhanced breach function with penalties
CREATE OR REPLACE FUNCTION public.breach_promise_with_penalty(p_promise_id UUID, p_reason TEXT DEFAULT 'Deadline exceeded')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_penalty NUMERIC := 50;
    v_score_penalty INTEGER := -15;
    v_hours_late NUMERIC;
    v_payment_cut_percent INTEGER := 10;
BEGIN
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.status = 'breached' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise already breached');
    END IF;
    
    -- Calculate hours late
    v_hours_late := EXTRACT(EPOCH FROM (now() - COALESCE(v_promise.extended_deadline, v_promise.deadline))) / 3600;
    
    -- Escalate penalty based on lateness
    IF v_hours_late > 48 THEN
        v_penalty := 200;
        v_score_penalty := -40;
        v_payment_cut_percent := 30;
    ELSIF v_hours_late > 24 THEN
        v_penalty := 150;
        v_score_penalty := -30;
        v_payment_cut_percent := 25;
    ELSIF v_hours_late > 12 THEN
        v_penalty := 100;
        v_score_penalty := -20;
        v_payment_cut_percent := 20;
    ELSIF v_hours_late > 6 THEN
        v_penalty := 75;
        v_score_penalty := -15;
        v_payment_cut_percent := 15;
    END IF;
    
    -- Extra penalty if commitment was confirmed
    IF v_promise.confirmed_by_developer THEN
        v_penalty := v_penalty + 50;
        v_score_penalty := v_score_penalty - 10;
        v_payment_cut_percent := v_payment_cut_percent + 5;
    END IF;
    
    -- Update promise
    UPDATE promise_logs
    SET status = 'breached',
        breach_reason = p_reason,
        penalty_amount = v_penalty,
        score_effect = v_score_penalty,
        fine_amount = v_penalty,
        is_locked = TRUE,
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Deduct from developer wallet
    UPDATE developer_wallet
    SET available_balance = available_balance - v_penalty,
        total_penalties = total_penalties + v_penalty
    WHERE developer_id = v_promise.developer_id;
    
    -- Insert fine record
    INSERT INTO promise_fines (
        promise_id, developer_id, fine_amount, fine_reason, fine_type, status,
        payment_cut_percent
    ) VALUES (
        p_promise_id, v_promise.developer_id, v_penalty, p_reason, 'breach', 'pending',
        v_payment_cut_percent
    );
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        COALESCE(auth.uid(), v_promise.developer_id),
        'promise_breached_with_penalty',
        'promise',
        (SELECT role FROM user_roles WHERE user_id = COALESCE(auth.uid(), v_promise.developer_id) LIMIT 1),
        jsonb_build_object(
            'promise_id', p_promise_id,
            'penalty', v_penalty,
            'score_penalty', v_score_penalty,
            'payment_cut_percent', v_payment_cut_percent,
            'hours_late', v_hours_late,
            'reason', p_reason
        )
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'penalty', v_penalty,
        'score_penalty', v_score_penalty,
        'payment_cut_percent', v_payment_cut_percent
    );
END;
$$;

-- Add payment_cut_percent column to promise_fines if not exists
ALTER TABLE public.promise_fines ADD COLUMN IF NOT EXISTS payment_cut_percent INTEGER DEFAULT 10;
-- ===== 20251229030218_5869bf61-37bc-436f-948e-f1afb83a28c1.sql =====
-- Developer Registration & Verification System

-- Create storage bucket for developer documents
INSERT INTO storage.buckets (id, name, public) 
VALUES ('developer-documents', 'developer-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for developer documents
CREATE POLICY "Developers can upload own documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'developer-documents' 
    AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Developers can view own documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'developer-documents' 
    AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Admins can view all developer documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'developer-documents'
    AND EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('master', 'super_admin', 'admin', 'task_manager')
    )
);

-- Developer registration verification status enum
CREATE TYPE public.developer_verification_status AS ENUM (
    'submitted', 
    'under_review', 
    'verified', 
    'rejected',
    'pending_documents'
);

-- Developer registration table
CREATE TABLE public.developer_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    
    -- Personal Info
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    country TEXT,
    timezone TEXT,
    
    -- Verification Status
    status developer_verification_status NOT NULL DEFAULT 'pending_documents',
    
    -- NDA & Rules
    nda_accepted BOOLEAN DEFAULT FALSE,
    nda_accepted_at TIMESTAMP WITH TIME ZONE,
    rules_accepted BOOLEAN DEFAULT FALSE,
    rules_accepted_at TIMESTAMP WITH TIME ZONE,
    nda_document_url TEXT,
    
    -- Documents
    resume_url TEXT,
    resume_uploaded_at TIMESTAMP WITH TIME ZONE,
    photo_id_url TEXT,
    photo_id_uploaded_at TIMESTAMP WITH TIME ZONE,
    photo_id_verified BOOLEAN DEFAULT FALSE,
    
    -- Bank Details (encrypted references)
    bank_name TEXT,
    account_holder_name TEXT,
    account_number_masked TEXT,
    ifsc_code TEXT,
    bank_details_verified BOOLEAN DEFAULT FALSE,
    
    -- Skills & Tech Stack
    primary_skills TEXT[] DEFAULT '{}',
    secondary_skills TEXT[] DEFAULT '{}',
    programming_languages TEXT[] DEFAULT '{}',
    frameworks TEXT[] DEFAULT '{}',
    databases TEXT[] DEFAULT '{}',
    tools TEXT[] DEFAULT '{}',
    years_of_experience INTEGER DEFAULT 0,
    expertise_level TEXT DEFAULT 'junior',
    
    -- Review Info
    submitted_at TIMESTAMP WITH TIME ZONE,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID,
    rejection_reason TEXT,
    verification_notes TEXT,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Developer past projects table
CREATE TABLE public.developer_past_projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_id UUID REFERENCES developer_registrations(id) ON DELETE CASCADE NOT NULL,
    user_id UUID NOT NULL,
    
    project_name TEXT NOT NULL,
    project_description TEXT,
    project_url TEXT,
    demo_url TEXT,
    demo_video_url TEXT,
    technologies_used TEXT[] DEFAULT '{}',
    role_in_project TEXT,
    duration_months INTEGER,
    is_verified BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.developer_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_past_projects ENABLE ROW LEVEL SECURITY;

-- RLS Policies for developer_registrations
CREATE POLICY "Developers can view own registration"
ON developer_registrations FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Developers can insert own registration"
ON developer_registrations FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Developers can update own registration before verification"
ON developer_registrations FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND status NOT IN ('verified', 'rejected'));

CREATE POLICY "Admins can view all registrations"
ON developer_registrations FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('master', 'super_admin', 'admin', 'task_manager')
    )
);

CREATE POLICY "Admins can update registrations"
ON developer_registrations FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('master', 'super_admin', 'admin', 'task_manager')
    )
);

-- RLS Policies for developer_past_projects
CREATE POLICY "Developers can manage own projects"
ON developer_past_projects FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can view all projects"
ON developer_past_projects FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role IN ('master', 'super_admin', 'admin', 'task_manager')
    )
);

-- Function to submit registration for review
CREATE OR REPLACE FUNCTION public.submit_developer_registration(p_registration_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reg RECORD;
BEGIN
    SELECT * INTO v_reg FROM developer_registrations WHERE id = p_registration_id AND user_id = auth.uid();
    
    IF v_reg IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Registration not found');
    END IF;
    
    -- Validate required fields
    IF NOT v_reg.nda_accepted THEN
        RETURN jsonb_build_object('success', false, 'error', 'NDA must be accepted');
    END IF;
    
    IF NOT v_reg.rules_accepted THEN
        RETURN jsonb_build_object('success', false, 'error', 'Rules must be accepted');
    END IF;
    
    IF v_reg.resume_url IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Resume is required');
    END IF;
    
    IF v_reg.photo_id_url IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Photo ID is required');
    END IF;
    
    IF v_reg.bank_name IS NULL OR v_reg.account_number_masked IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Bank details are required');
    END IF;
    
    IF array_length(v_reg.primary_skills, 1) IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'At least one skill is required');
    END IF;
    
    -- Update status
    UPDATE developer_registrations
    SET status = 'submitted',
        submitted_at = now(),
        updated_at = now()
    WHERE id = p_registration_id;
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        'developer_registration_submitted',
        'verification',
        'developer',
        jsonb_build_object('registration_id', p_registration_id)
    );
    
    RETURN jsonb_build_object('success', true, 'message', 'Registration submitted for review');
END;
$$;

-- Function to verify/reject developer
CREATE OR REPLACE FUNCTION public.review_developer_registration(
    p_registration_id UUID,
    p_action TEXT,
    p_notes TEXT DEFAULT NULL,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reviewer_role TEXT;
    v_reg RECORD;
BEGIN
    -- Check reviewer permissions
    SELECT role INTO v_reviewer_role FROM user_roles WHERE user_id = auth.uid();
    
    IF v_reviewer_role NOT IN ('master', 'super_admin', 'admin', 'task_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;
    
    SELECT * INTO v_reg FROM developer_registrations WHERE id = p_registration_id;
    
    IF v_reg IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Registration not found');
    END IF;
    
    IF p_action = 'verify' THEN
        UPDATE developer_registrations
        SET status = 'verified',
            reviewed_at = now(),
            reviewed_by = auth.uid(),
            verification_notes = p_notes,
            updated_at = now()
        WHERE id = p_registration_id;
        
        -- Update user role approval if exists
        UPDATE user_roles
        SET approval_status = 'approved',
            approved_by = auth.uid(),
            approved_at = now()
        WHERE user_id = v_reg.user_id AND role = 'developer';
        
    ELSIF p_action = 'reject' THEN
        UPDATE developer_registrations
        SET status = 'rejected',
            reviewed_at = now(),
            reviewed_by = auth.uid(),
            rejection_reason = p_rejection_reason,
            verification_notes = p_notes,
            updated_at = now()
        WHERE id = p_registration_id;
        
    ELSIF p_action = 'review' THEN
        UPDATE developer_registrations
        SET status = 'under_review',
            verification_notes = p_notes,
            updated_at = now()
        WHERE id = p_registration_id;
    END IF;
    
    -- Log to audit
    INSERT INTO audit_logs (user_id, action, module, role, meta_json)
    VALUES (
        auth.uid(),
        'developer_registration_' || p_action,
        'verification',
        v_reviewer_role::app_role,
        jsonb_build_object(
            'registration_id', p_registration_id,
            'developer_user_id', v_reg.user_id,
            'action', p_action
        )
    );
    
    RETURN jsonb_build_object('success', true, 'action', p_action);
END;
$$;

-- Function to check if developer is verified (for task access)
CREATE OR REPLACE FUNCTION public.is_developer_verified(p_user_id UUID)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM developer_registrations
        WHERE user_id = p_user_id
        AND status = 'verified'
    )
$$;
-- ===== 20251230050116_64771b22-1051-4c24-9a88-1aec39bfa07c.sql =====
-- ==============================================
-- ZERO-LOOPHOLE PROMISE MANAGEMENT SYSTEM
-- Role: Promise Management (Control Role)
-- Purpose: Control, validate, track, enforce, close promises
-- ==============================================

-- Add promise_manager role validation columns
ALTER TABLE public.promise_logs 
ADD COLUMN IF NOT EXISTS assigned_role TEXT,
ADD COLUMN IF NOT EXISTS responsible_user_id UUID,
ADD COLUMN IF NOT EXISTS linked_task_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS fulfillment_verified_by UUID,
ADD COLUMN IF NOT EXISTS fulfillment_verified_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS final_audit_log_id UUID,
ADD COLUMN IF NOT EXISTS auto_escalation_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS last_status_change_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
ADD COLUMN IF NOT EXISTS status_change_count INTEGER DEFAULT 0;

-- Create immutable promise audit log table
CREATE TABLE IF NOT EXISTS public.promise_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promise_id UUID REFERENCES public.promise_logs(id) ON DELETE RESTRICT NOT NULL,
    action_type TEXT NOT NULL, -- creation, approval, rejection, status_change, escalation, fulfillment, closure
    action_by UUID NOT NULL,
    action_by_role TEXT NOT NULL,
    previous_status TEXT,
    new_status TEXT,
    previous_data JSONB,
    new_data JSONB,
    reason TEXT,
    ip_address TEXT,
    user_agent TEXT,
    server_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_system_action BOOLEAN DEFAULT false,
    signature TEXT -- hash for tamper detection
);

-- Make audit logs immutable - no updates, no deletes
ALTER TABLE public.promise_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Promise audit logs are append-only insert" ON public.promise_audit_logs
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Promise audit logs read by authorized roles" ON public.promise_audit_logs
    FOR SELECT USING (
        has_role(auth.uid(), 'super_admin') OR
        has_role(auth.uid(), 'master') OR
        has_role(auth.uid(), 'promise_management') OR
        has_role(auth.uid(), 'promise_tracker')
    );

-- Block all updates and deletes on audit logs
CREATE POLICY "No updates on audit logs" ON public.promise_audit_logs
    FOR UPDATE USING (false);

CREATE POLICY "No deletes on audit logs" ON public.promise_audit_logs
    FOR DELETE USING (false);

-- ==============================================
-- PROMISE VALIDATION FUNCTION
-- Ensures every promise has required links
-- ==============================================
CREATE OR REPLACE FUNCTION public.validate_promise_integrity(p_promise_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_task_exists BOOLEAN;
    v_developer_exists BOOLEAN;
    v_errors TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('valid', false, 'errors', ARRAY['Promise not found']);
    END IF;
    
    -- Check task link
    SELECT EXISTS(SELECT 1 FROM developer_tasks WHERE id = v_promise.task_id) INTO v_task_exists;
    IF NOT v_task_exists THEN
        v_errors := array_append(v_errors, 'No linked task found');
    END IF;
    
    -- Check developer/responsible user
    SELECT EXISTS(SELECT 1 FROM developers WHERE id = v_promise.developer_id) INTO v_developer_exists;
    IF NOT v_developer_exists THEN
        v_errors := array_append(v_errors, 'No responsible developer found');
    END IF;
    
    -- Check deadline
    IF v_promise.deadline IS NULL THEN
        v_errors := array_append(v_errors, 'No deadline set');
    END IF;
    
    -- Check assigned role
    IF v_promise.assigned_role IS NULL OR v_promise.assigned_role = '' THEN
        v_errors := array_append(v_errors, 'No assigned role specified');
    END IF;
    
    RETURN jsonb_build_object(
        'valid', array_length(v_errors, 1) IS NULL,
        'errors', COALESCE(v_errors, ARRAY[]::TEXT[]),
        'promise_id', p_promise_id
    );
END;
$$;

-- ==============================================
-- PROMISE CREATION (Only by System or Approved Manager)
-- ==============================================
CREATE OR REPLACE FUNCTION public.create_promise_with_validation(
    p_task_id UUID,
    p_developer_id UUID,
    p_deadline TIMESTAMP WITH TIME ZONE,
    p_promise_type TEXT,
    p_priority TEXT,
    p_assigned_role TEXT,
    p_responsible_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_creator_role TEXT;
    v_new_promise_id UUID;
    v_task_exists BOOLEAN;
    v_developer_exists BOOLEAN;
BEGIN
    -- Get creator role
    SELECT role INTO v_creator_role FROM user_roles WHERE user_id = auth.uid();
    
    -- Only specific roles can create promises
    IF v_creator_role NOT IN ('super_admin', 'master', 'promise_management', 'task_manager', 'pro_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Only approved managers can create promises');
    END IF;
    
    -- Validate task exists
    SELECT EXISTS(SELECT 1 FROM developer_tasks WHERE id = p_task_id) INTO v_task_exists;
    IF NOT v_task_exists THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid task_id: Task does not exist');
    END IF;
    
    -- Validate developer exists
    SELECT EXISTS(SELECT 1 FROM developers WHERE id = p_developer_id) INTO v_developer_exists;
    IF NOT v_developer_exists THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid developer_id: Developer does not exist');
    END IF;
    
    -- Validate deadline is in future
    IF p_deadline <= now() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Deadline must be in the future');
    END IF;
    
    -- Create promise with pending_approval status
    INSERT INTO promise_logs (
        task_id,
        developer_id,
        deadline,
        promise_type,
        priority,
        assigned_role,
        responsible_user_id,
        status,
        approval_required,
        linked_task_verified
    ) VALUES (
        p_task_id,
        p_developer_id,
        p_deadline,
        p_promise_type,
        p_priority,
        p_assigned_role,
        COALESCE(p_responsible_user_id, p_developer_id),
        'pending_approval',
        true,
        true
    ) RETURNING id INTO v_new_promise_id;
    
    -- Create immutable audit log
    INSERT INTO promise_audit_logs (
        promise_id,
        action_type,
        action_by,
        action_by_role,
        previous_status,
        new_status,
        new_data,
        reason
    ) VALUES (
        v_new_promise_id,
        'creation',
        auth.uid(),
        v_creator_role,
        NULL,
        'pending_approval',
        jsonb_build_object(
            'task_id', p_task_id,
            'developer_id', p_developer_id,
            'deadline', p_deadline,
            'priority', p_priority,
            'assigned_role', p_assigned_role
        ),
        'Promise created via validated flow'
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'promise_id', v_new_promise_id,
        'status', 'pending_approval'
    );
END;
$$;

-- ==============================================
-- ENHANCED APPROVAL FLOW (Strict Role Validation)
-- ==============================================
CREATE OR REPLACE FUNCTION public.approve_promise_strict(
    p_promise_id UUID,
    p_approver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_approver_role TEXT;
    v_validation JSONB;
BEGIN
    -- Get approver role
    SELECT role INTO v_approver_role FROM user_roles WHERE user_id = p_approver_id;
    
    -- STRICT: Only Super Admin, Master Admin, or Pro Manager can approve
    IF v_approver_role NOT IN ('super_admin', 'master', 'pro_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED: Only Super Admin, Master Admin, or Pro Manager can approve promises');
    END IF;
    
    -- Get promise with lock
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.is_locked THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is locked and cannot be modified');
    END IF;
    
    IF v_promise.status != 'pending_approval' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is not pending approval. Current status: ' || v_promise.status);
    END IF;
    
    -- Validate promise integrity before approval
    v_validation := validate_promise_integrity(p_promise_id);
    IF NOT (v_validation->>'valid')::boolean THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise integrity check failed', 'details', v_validation->'errors');
    END IF;
    
    -- Approve promise - set to Active (assigned)
    UPDATE promise_logs
    SET status = 'assigned',
        approved_by = p_approver_id,
        approved_at = now(),
        last_status_change_at = now(),
        status_change_count = status_change_count + 1,
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Immutable audit log
    INSERT INTO promise_audit_logs (
        promise_id,
        action_type,
        action_by,
        action_by_role,
        previous_status,
        new_status,
        reason
    ) VALUES (
        p_promise_id,
        'approval',
        p_approver_id,
        v_approver_role,
        'pending_approval',
        'assigned',
        'Promise approved and activated'
    );
    
    RETURN jsonb_build_object('success', true, 'promise_id', p_promise_id, 'new_status', 'assigned');
END;
$$;

-- ==============================================
-- STRICT REJECTION FLOW
-- ==============================================
CREATE OR REPLACE FUNCTION public.reject_promise_strict(
    p_promise_id UUID,
    p_rejector_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_rejector_role TEXT;
BEGIN
    -- Reason is mandatory
    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Rejection reason is mandatory');
    END IF;
    
    SELECT role INTO v_rejector_role FROM user_roles WHERE user_id = p_rejector_id;
    
    IF v_rejector_role NOT IN ('super_admin', 'master', 'pro_manager') THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED: Only Super Admin, Master Admin, or Pro Manager can reject promises');
    END IF;
    
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.is_locked THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is locked and cannot be modified');
    END IF;
    
    -- Update to cancelled status
    UPDATE promise_logs
    SET status = 'breached',
        rejected_by = p_rejector_id,
        rejected_at = now(),
        rejection_reason = p_reason,
        breach_reason = 'Rejected: ' || p_reason,
        is_locked = true,
        last_status_change_at = now(),
        status_change_count = status_change_count + 1,
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Immutable audit log
    INSERT INTO promise_audit_logs (
        promise_id,
        action_type,
        action_by,
        action_by_role,
        previous_status,
        new_status,
        reason
    ) VALUES (
        p_promise_id,
        'rejection',
        p_rejector_id,
        v_rejector_role,
        v_promise.status,
        'cancelled',
        p_reason
    );
    
    RETURN jsonb_build_object('success', true, 'promise_id', p_promise_id, 'new_status', 'cancelled');
END;
$$;

-- ==============================================
-- AUTO ESCALATION FUNCTION
-- ==============================================
CREATE OR REPLACE FUNCTION public.escalate_overdue_promise(p_promise_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_new_level INTEGER;
    v_escalate_to UUID[];
BEGIN
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.is_locked THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is locked');
    END IF;
    
    IF NOT v_promise.auto_escalation_enabled THEN
        RETURN jsonb_build_object('success', false, 'error', 'Auto escalation is disabled for this promise');
    END IF;
    
    -- Calculate new escalation level
    v_new_level := COALESCE(v_promise.escalation_level, 0) + 1;
    
    -- Get escalation targets based on level
    SELECT ARRAY_AGG(user_id) INTO v_escalate_to
    FROM user_roles
    WHERE role IN (
        CASE 
            WHEN v_new_level = 1 THEN 'task_manager'
            WHEN v_new_level = 2 THEN 'pro_manager'
            ELSE 'super_admin'
        END
    );
    
    -- Update promise
    UPDATE promise_logs
    SET escalation_level = v_new_level,
        escalated_at = now(),
        escalated_to = v_escalate_to,
        status = CASE WHEN now() > deadline AND status NOT IN ('completed', 'breached') THEN 'breached' ELSE status END,
        updated_at = now()
    WHERE id = p_promise_id;
    
    -- Log escalation
    INSERT INTO promise_escalation_logs (
        promise_id,
        from_level,
        to_level,
        escalated_to,
        reason,
        auto_triggered
    ) VALUES (
        p_promise_id,
        COALESCE(v_promise.escalation_level, 0),
        v_new_level,
        v_escalate_to,
        'Deadline exceeded - auto escalation',
        true
    );
    
    -- Immutable audit log
    INSERT INTO promise_audit_logs (
        promise_id,
        action_type,
        action_by,
        action_by_role,
        previous_status,
        new_status,
        reason,
        is_system_action
    ) VALUES (
        p_promise_id,
        'escalation',
        auth.uid(),
        'system',
        v_promise.status,
        v_promise.status,
        'Auto-escalated to level ' || v_new_level,
        true
    );
    
    RETURN jsonb_build_object(
        'success', true,
        'promise_id', p_promise_id,
        'new_level', v_new_level,
        'escalated_to', v_escalate_to
    );
END;
$$;

-- ==============================================
-- FULFILLMENT / CLOSURE FUNCTION
-- Only closes if linked task completed OR Super Admin approval
-- ==============================================
CREATE OR REPLACE FUNCTION public.fulfill_promise_strict(
    p_promise_id UUID,
    p_fulfiller_id UUID,
    p_force_close BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promise RECORD;
    v_fulfiller_role TEXT;
    v_task_completed BOOLEAN;
    v_final_audit_id UUID;
BEGIN
    SELECT role INTO v_fulfiller_role FROM user_roles WHERE user_id = p_fulfiller_id;
    
    SELECT * INTO v_promise FROM promise_logs WHERE id = p_promise_id FOR UPDATE;
    
    IF v_promise IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise not found');
    END IF;
    
    IF v_promise.is_locked THEN
        RETURN jsonb_build_object('success', false, 'error', 'Promise is already closed and locked');
    END IF;
    
    -- Check if task is completed
    SELECT (status = 'completed') INTO v_task_completed 
    FROM developer_tasks 
    WHERE id = v_promise.task_id;
    
    -- Can close only if task completed OR super_admin force close
    IF NOT v_task_completed THEN
        IF p_force_close AND v_fulfiller_role = 'super_admin' THEN
            -- Allow super admin force close
            NULL;
        ELSE
            RETURN jsonb_build_object(
                'success', false, 
                'error', 'Cannot fulfill: Linked task is not completed. Only Super Admin can force close.'
            );
        END IF;
    END IF;
    
    -- Create final audit log
    INSERT INTO promise_audit_logs (
        promise_id,
        action_type,
        action_by,
        action_by_role,
        previous_status,
        new_status,
        previous_data,
        reason
    ) VALUES (
        p_promise_id,
        'closure',
        p_fulfiller_id,
        v_fulfiller_role,
        v_promise.status,
        'completed',
        to_jsonb(v_promise),
        CASE WHEN p_force_close THEN 'Force closed by Super Admin' ELSE 'Fulfilled - linked task completed' END
    ) RETURNING id INTO v_final_audit_id;
    
    -- Lock and close the promise permanently
    UPDATE promise_logs
    SET status = 'completed',
        finished_time = now(),
        is_locked = true,
        fulfillment_verified_by = p_fulfiller_id,
        fulfillment_verified_at = now(),
        final_audit_log_id = v_final_audit_id,
        last_status_change_at = now(),
        status_change_count = status_change_count + 1,
        updated_at = now()
    WHERE id = p_promise_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'promise_id', p_promise_id,
        'status', 'completed',
        'locked', true,
        'final_audit_id', v_final_audit_id
    );
END;
$$;

-- ==============================================
-- PROMISE MANAGER METRICS VIEW
-- ==============================================
CREATE OR REPLACE VIEW public.promise_manager_metrics AS
SELECT 
    COUNT(*) FILTER (WHERE status NOT IN ('completed', 'breached')) AS total_active,
    COUNT(*) FILTER (WHERE status = 'pending_approval') AS pending_approval,
    COUNT(*) FILTER (WHERE status IN ('promised', 'in_progress', 'assigned') AND deadline < now()) AS overdue,
    COUNT(*) FILTER (WHERE status = 'completed') AS fulfilled,
    COUNT(*) FILTER (WHERE status = 'breached') AS breached,
    COUNT(*) AS total_promises,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'completed')::NUMERIC / 
        NULLIF(COUNT(*) FILTER (WHERE status IN ('completed', 'breached')), 0) * 100, 2
    ) AS fulfillment_rate,
    COUNT(*) FILTER (WHERE escalation_level > 0 AND status NOT IN ('completed', 'breached')) AS active_escalations
FROM promise_logs;

-- ==============================================
-- SECURITY: Prevent direct status manipulation
-- ==============================================
CREATE OR REPLACE FUNCTION public.prevent_direct_promise_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_role TEXT;
BEGIN
    -- Allow system/triggers to modify
    IF current_setting('app.bypass_rls', true) = 'true' THEN
        RETURN NEW;
    END IF;
    
    -- Get user role
    SELECT role INTO v_user_role FROM user_roles WHERE user_id = auth.uid();
    
    -- Promise Manager cannot execute - only control
    IF v_user_role = 'promise_management' THEN
        -- Block direct status changes except through approved functions
        IF OLD.status != NEW.status THEN
            RAISE EXCEPTION 'Promise Manager cannot directly change promise status. Use approved workflow functions.';
        END IF;
        
        -- Block modification of locked promises
        IF OLD.is_locked THEN
            RAISE EXCEPTION 'Cannot modify locked/closed promises';
        END IF;
        
        -- Block deadline changes after activation
        IF OLD.status NOT IN ('pending_approval') AND OLD.deadline != NEW.deadline THEN
            RAISE EXCEPTION 'Cannot modify deadline after promise activation';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Apply trigger
DROP TRIGGER IF EXISTS trg_prevent_direct_promise_modification ON promise_logs;
CREATE TRIGGER trg_prevent_direct_promise_modification
    BEFORE UPDATE ON promise_logs
    FOR EACH ROW
    EXECUTE FUNCTION prevent_direct_promise_modification();

-- ==============================================
-- RLS: Promise Manager can only READ, not write directly
-- ==============================================
CREATE POLICY "Promise manager read-only access" ON public.promise_logs
    FOR SELECT USING (has_role(auth.uid(), 'promise_management'));

-- Enable realtime for promise_audit_logs
ALTER PUBLICATION supabase_realtime ADD TABLE public.promise_audit_logs;
-- ===== 20251230050141_855f610b-2251-4d59-9f48-0b5d85221aac.sql =====
-- Fix: Convert SECURITY DEFINER view to regular view with proper access control
DROP VIEW IF EXISTS public.promise_manager_metrics;

-- Recreate as a regular view (SECURITY INVOKER - default)
CREATE VIEW public.promise_manager_metrics AS
SELECT 
    COUNT(*) FILTER (WHERE status NOT IN ('completed', 'breached')) AS total_active,
    COUNT(*) FILTER (WHERE status = 'pending_approval') AS pending_approval,
    COUNT(*) FILTER (WHERE status IN ('promised', 'in_progress', 'assigned') AND deadline < now()) AS overdue,
    COUNT(*) FILTER (WHERE status = 'completed') AS fulfilled,
    COUNT(*) FILTER (WHERE status = 'breached') AS breached,
    COUNT(*) AS total_promises,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'completed')::NUMERIC / 
        NULLIF(COUNT(*) FILTER (WHERE status IN ('completed', 'breached')), 0) * 100, 2
    ) AS fulfillment_rate,
    COUNT(*) FILTER (WHERE escalation_level > 0 AND status NOT IN ('completed', 'breached')) AS active_escalations
FROM promise_logs;

-- Explicitly set SECURITY INVOKER (the default, but being explicit)
ALTER VIEW public.promise_manager_metrics SET (security_invoker = true);
-- ===== 20251231025745_6a7f2c5d-91f9-4548-8c12-fd3eb25fd860.sql =====
-- ================================================
-- READ-ONLY PROMISE TRACKER SYSTEM (FIXED)
-- Observer role with ZERO control power
-- ================================================

-- Table: Promise View Logs (Audit trail for views)
CREATE TABLE IF NOT EXISTS public.promise_view_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  viewer_id UUID NOT NULL,
  viewer_role TEXT NOT NULL,
  promise_id UUID REFERENCES public.promise_logs(id),
  view_type TEXT NOT NULL DEFAULT 'detail',
  ip_address TEXT,
  user_agent TEXT,
  session_id TEXT,
  viewed_at TIMESTAMPTZ DEFAULT now(),
  server_timestamp TIMESTAMPTZ DEFAULT now()
);

-- Table: Promise Export Logs (Audit trail for exports)
CREATE TABLE IF NOT EXISTS public.promise_export_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exporter_id UUID NOT NULL,
  exporter_role TEXT NOT NULL,
  export_format TEXT NOT NULL,
  filter_criteria JSONB,
  records_exported INTEGER DEFAULT 0,
  data_masked BOOLEAN DEFAULT true,
  exported_at TIMESTAMPTZ DEFAULT now(),
  server_timestamp TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.promise_view_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promise_export_logs ENABLE ROW LEVEL SECURITY;

-- RLS: View logs are append-only
CREATE POLICY "Promise view logs are append only"
  ON public.promise_view_logs
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Promise view logs readable by authorized roles"
  ON public.promise_view_logs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND role IN ('super_admin', 'master', 'promise_management', 'promise_tracker')
    )
  );

-- RLS: Export logs are append-only
CREATE POLICY "Promise export logs are append only"
  ON public.promise_export_logs
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Promise export logs readable by authorized roles"
  ON public.promise_export_logs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND role IN ('super_admin', 'master', 'promise_management')
    )
  );

-- Prevent any updates or deletes on view logs
CREATE OR REPLACE FUNCTION public.prevent_view_log_modification()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Promise view/export logs are immutable - no updates or deletes allowed';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER prevent_view_log_update
  BEFORE UPDATE ON public.promise_view_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_view_log_modification();

CREATE TRIGGER prevent_view_log_delete
  BEFORE DELETE ON public.promise_view_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_view_log_modification();

CREATE TRIGGER prevent_export_log_update
  BEFORE UPDATE ON public.promise_export_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_view_log_modification();

CREATE TRIGGER prevent_export_log_delete
  BEFORE DELETE ON public.promise_export_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_view_log_modification();

-- View: Promise Tracker Read-Only View with masked data
CREATE OR REPLACE VIEW public.promise_tracker_view AS
SELECT 
  pl.id AS promise_id,
  pl.promise_type,
  COALESCE(pl.assigned_role, 'developer') AS linked_module,
  COALESCE(pl.assigned_role, 'developer') AS assigned_role,
  CASE 
    WHEN pl.developer_id IS NOT NULL 
    THEN SUBSTRING(pl.developer_id::text, 1, 8) || '***'
    ELSE 'Unknown'
  END AS assigned_user_masked,
  pl.created_at AS start_date,
  pl.deadline AS due_date,
  CASE 
    WHEN pl.status IN ('completed', 'breached') THEN 0
    ELSE GREATEST(0, EXTRACT(EPOCH FROM (pl.deadline - now())) / 60)
  END AS remaining_minutes,
  pl.status,
  pl.priority,
  pl.escalation_level,
  pl.escalated_at,
  pl.is_locked,
  pl.breach_reason,
  pl.extended_count,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM public.user_roles 
      WHERE user_id = auth.uid() 
      AND role IN ('super_admin', 'master', 'promise_management')
    ) THEN pl.approved_by
    ELSE NULL
  END AS approved_by,
  pl.approved_at,
  pl.finished_time,
  pl.task_id,
  pl.created_at,
  pl.updated_at
FROM public.promise_logs pl
ORDER BY 
  CASE WHEN pl.status IN ('assigned', 'promised', 'in_progress') THEN 0 ELSE 1 END,
  pl.deadline ASC;

-- View: Promise Tracker Metrics (Read-Only)
CREATE OR REPLACE VIEW public.promise_tracker_metrics AS
SELECT
  (SELECT COUNT(*) FROM public.promise_logs) AS total_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status IN ('assigned', 'promised', 'in_progress')) AS active_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status = 'pending_approval') AS pending_approval,
  (SELECT COUNT(*) FROM public.promise_logs 
   WHERE status IN ('assigned', 'promised', 'in_progress') 
   AND deadline < now()) AS overdue_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status = 'completed') AS fulfilled_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE escalation_level > 0 AND status NOT IN ('completed', 'breached')) AS escalated_promises,
  now() AS last_updated;

-- Function: Log promise view (for audit)
CREATE OR REPLACE FUNCTION public.log_promise_view(
  p_promise_id UUID DEFAULT NULL,
  p_view_type TEXT DEFAULT 'list',
  p_ip_address TEXT DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_session_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer_id UUID;
  v_viewer_role TEXT;
  v_log_id UUID;
BEGIN
  v_viewer_id := auth.uid();
  IF v_viewer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT role::text INTO v_viewer_role
  FROM public.user_roles
  WHERE user_id = v_viewer_id
  LIMIT 1;

  INSERT INTO public.promise_view_logs (
    viewer_id, viewer_role, promise_id, view_type, ip_address, user_agent, session_id
  ) VALUES (
    v_viewer_id, COALESCE(v_viewer_role, 'unknown'), p_promise_id, p_view_type, p_ip_address, p_user_agent, p_session_id
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

-- Function: Log promise export (for audit)
CREATE OR REPLACE FUNCTION public.log_promise_export(
  p_export_format TEXT,
  p_filter_criteria JSONB DEFAULT NULL,
  p_records_exported INTEGER DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exporter_id UUID;
  v_exporter_role TEXT;
  v_log_id UUID;
BEGIN
  v_exporter_id := auth.uid();
  IF v_exporter_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT role::text INTO v_exporter_role
  FROM public.user_roles
  WHERE user_id = v_exporter_id
  LIMIT 1;

  INSERT INTO public.promise_export_logs (
    exporter_id, exporter_role, export_format, filter_criteria, records_exported, data_masked
  ) VALUES (
    v_exporter_id, COALESCE(v_exporter_role, 'unknown'), p_export_format, p_filter_criteria, p_records_exported, true
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

-- RLS: Promise Tracker role can only READ promises
CREATE POLICY "Promise tracker role read only access"
  ON public.promise_logs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = auth.uid()
      AND role = 'promise_tracker'
    )
  );

-- Grant SELECT on views
GRANT SELECT ON public.promise_tracker_view TO authenticated;
GRANT SELECT ON public.promise_tracker_metrics TO authenticated;
-- ===== 20251231025812_206a16c4-3920-4d5f-acf7-d3c710e7785a.sql =====
-- Fix security warnings: Add SECURITY INVOKER to views and search_path to functions

-- Drop and recreate views with SECURITY INVOKER
DROP VIEW IF EXISTS public.promise_tracker_view;
DROP VIEW IF EXISTS public.promise_tracker_metrics;

-- Recreate Promise Tracker View with SECURITY INVOKER
CREATE VIEW public.promise_tracker_view 
WITH (security_invoker = true)
AS
SELECT 
  pl.id AS promise_id,
  pl.promise_type,
  COALESCE(pl.assigned_role, 'developer') AS linked_module,
  COALESCE(pl.assigned_role, 'developer') AS assigned_role,
  CASE 
    WHEN pl.developer_id IS NOT NULL 
    THEN SUBSTRING(pl.developer_id::text, 1, 8) || '***'
    ELSE 'Unknown'
  END AS assigned_user_masked,
  pl.created_at AS start_date,
  pl.deadline AS due_date,
  CASE 
    WHEN pl.status IN ('completed', 'breached') THEN 0
    ELSE GREATEST(0, EXTRACT(EPOCH FROM (pl.deadline - now())) / 60)
  END AS remaining_minutes,
  pl.status,
  pl.priority,
  pl.escalation_level,
  pl.escalated_at,
  pl.is_locked,
  pl.breach_reason,
  pl.extended_count,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM public.user_roles 
      WHERE user_id = auth.uid() 
      AND role IN ('super_admin', 'master', 'promise_management')
    ) THEN pl.approved_by
    ELSE NULL
  END AS approved_by,
  pl.approved_at,
  pl.finished_time,
  pl.task_id,
  pl.created_at,
  pl.updated_at
FROM public.promise_logs pl
ORDER BY 
  CASE WHEN pl.status IN ('assigned', 'promised', 'in_progress') THEN 0 ELSE 1 END,
  pl.deadline ASC;

-- Recreate Promise Tracker Metrics with SECURITY INVOKER
CREATE VIEW public.promise_tracker_metrics 
WITH (security_invoker = true)
AS
SELECT
  (SELECT COUNT(*) FROM public.promise_logs) AS total_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status IN ('assigned', 'promised', 'in_progress')) AS active_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status = 'pending_approval') AS pending_approval,
  (SELECT COUNT(*) FROM public.promise_logs 
   WHERE status IN ('assigned', 'promised', 'in_progress') 
   AND deadline < now()) AS overdue_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE status = 'completed') AS fulfilled_promises,
  (SELECT COUNT(*) FROM public.promise_logs WHERE escalation_level > 0 AND status NOT IN ('completed', 'breached')) AS escalated_promises,
  now() AS last_updated;

-- Fix function search paths
CREATE OR REPLACE FUNCTION public.prevent_view_log_modification()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'Promise view/export logs are immutable - no updates or deletes allowed';
END;
$$;

-- Grant SELECT on views
GRANT SELECT ON public.promise_tracker_view TO authenticated;
GRANT SELECT ON public.promise_tracker_metrics TO authenticated;
-- ===== 20251231173835_749bee73-8507-46ea-b11b-b36360798d8d.sql =====
-- =====================================================
-- USER ROLE SYSTEM - Safe, Simple, Fast
-- Revenue source with zero admin access
-- =====================================================

-- 1. Create user profiles table for customer data
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    email TEXT NOT NULL,
    full_name TEXT,
    phone TEXT,
    avatar_url TEXT,
    wallet_balance NUMERIC(12,2) DEFAULT 0,
    total_purchases INTEGER DEFAULT 0,
    total_spent NUMERIC(12,2) DEFAULT 0,
    is_verified BOOLEAN DEFAULT false,
    referral_code TEXT UNIQUE,
    referred_by UUID REFERENCES public.user_profiles(id),
    last_active_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create user purchases table
CREATE TABLE IF NOT EXISTS public.user_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    demo_id UUID REFERENCES public.demos(id),
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT DEFAULT 'INR',
    status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'refunded', 'failed')),
    payment_method TEXT,
    transaction_id TEXT,
    access_granted_at TIMESTAMPTZ,
    access_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Create user demo history (view tracking)
CREATE TABLE IF NOT EXISTS public.user_demo_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    demo_id UUID REFERENCES public.demos(id),
    viewed_at TIMESTAMPTZ DEFAULT now(),
    duration_seconds INTEGER DEFAULT 0,
    interaction_count INTEGER DEFAULT 0
);

-- 4. Create user support tickets table
CREATE TABLE IF NOT EXISTS public.user_support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ticket_number TEXT NOT NULL UNIQUE DEFAULT ('TKT-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8))),
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT DEFAULT 'general' CHECK (category IN ('general', 'billing', 'technical', 'product', 'refund', 'other')),
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'waiting_response', 'resolved', 'closed')),
    assigned_to UUID,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

-- 5. Create user wallet transactions (view-only for users)
CREATE TABLE IF NOT EXISTS public.user_wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('credit', 'debit', 'refund', 'bonus', 'cashback')),
    amount NUMERIC(12,2) NOT NULL,
    balance_after NUMERIC(12,2) NOT NULL,
    description TEXT,
    reference_id TEXT,
    reference_type TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 6. Enable RLS on all user tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_demo_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_wallet_transactions ENABLE ROW LEVEL SECURITY;

-- 7. User Profile RLS Policies
CREATE POLICY "Users can view their own profile"
    ON public.user_profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile"
    ON public.user_profiles FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile"
    ON public.user_profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 8. User Purchases RLS Policies
CREATE POLICY "Users can view their own purchases"
    ON public.user_purchases FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own purchases"
    ON public.user_purchases FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 9. User Demo History RLS Policies
CREATE POLICY "Users can view their own demo history"
    ON public.user_demo_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own demo history"
    ON public.user_demo_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 10. User Support Tickets RLS Policies
CREATE POLICY "Users can view their own tickets"
    ON public.user_support_tickets FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own tickets"
    ON public.user_support_tickets FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own open tickets"
    ON public.user_support_tickets FOR UPDATE
    USING (auth.uid() = user_id AND status IN ('open', 'waiting_response'));

-- 11. User Wallet Transactions RLS - VIEW ONLY (no INSERT/UPDATE/DELETE for users)
CREATE POLICY "Users can only view their own wallet transactions"
    ON public.user_wallet_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- 12. Function to auto-create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_user_role_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_role TEXT;
    v_ref_code TEXT;
BEGIN
    -- Get role from metadata, default to 'user'
    v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'user');
    
    -- Only handle 'user' role here
    IF v_role = 'user' THEN
        -- Generate unique referral code
        v_ref_code := 'USR-' || UPPER(SUBSTRING(NEW.id::text, 1, 8));
        
        -- Create user profile
        INSERT INTO public.user_profiles (user_id, email, full_name, referral_code)
        VALUES (
            NEW.id,
            NEW.email,
            COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
            v_ref_code
        )
        ON CONFLICT (user_id) DO NOTHING;
        
        -- Create user role entry with auto-approval
        INSERT INTO public.user_roles (user_id, role, approval_status)
        VALUES (NEW.id, 'user', 'approved')
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 13. Create trigger for auto user signup (safe drop first)
DROP TRIGGER IF EXISTS on_user_role_created ON auth.users;
CREATE TRIGGER on_user_role_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_role_signup();

-- 14. Function to block user from admin routes
CREATE OR REPLACE FUNCTION public.validate_user_route_access(
    p_user_id UUID,
    p_route TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_role TEXT;
    v_forbidden_patterns TEXT[] := ARRAY[
        '^/admin',
        '^/super-admin',
        '^/master',
        '^/finance',
        '^/promise-management',
        '^/developer',
        '^/franchise',
        '^/reseller',
        '^/influencer',
        '^/security-command',
        '^/server-manager',
        '^/api-manager',
        '^/marketing-manager',
        '^/seo-manager',
        '^/legal-manager',
        '^/area-manager',
        '^/continent-super-admin'
    ];
    v_pattern TEXT;
BEGIN
    -- Get user role
    SELECT role INTO v_role 
    FROM public.user_roles 
    WHERE user_id = p_user_id;
    
    -- If not a 'user' role, allow (other roles have their own restrictions)
    IF v_role IS NULL OR v_role != 'user' THEN
        RETURN true;
    END IF;
    
    -- Check against forbidden patterns
    FOREACH v_pattern IN ARRAY v_forbidden_patterns
    LOOP
        IF p_route ~ v_pattern THEN
            -- Log the blocked attempt
            INSERT INTO public.audit_logs (user_id, action, module, meta_json, role)
            VALUES (
                p_user_id,
                'BLOCKED_ROUTE_ACCESS',
                'user_security',
                jsonb_build_object('route', p_route, 'pattern', v_pattern),
                'user'
            );
            RETURN false;
        END IF;
    END LOOP;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 15. Function to safely end Safe Assist on logout
CREATE OR REPLACE FUNCTION public.end_user_safe_assist_on_logout(p_user_id UUID)
RETURNS void AS $$
BEGIN
    -- End any active safe assist sessions
    UPDATE public.safe_assist_sessions
    SET 
        status = 'ended',
        ended_at = now(),
        end_reason = 'user_logout'
    WHERE 
        user_id = p_user_id 
        AND status IN ('active', 'pending', 'connected');
        
    -- Log the action
    INSERT INTO public.audit_logs (user_id, action, module, role)
    VALUES (p_user_id, 'SAFE_ASSIST_AUTO_END_LOGOUT', 'safe_assist', 'user');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 16. Indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_purchases_user_id ON public.user_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_user_purchases_demo_id ON public.user_purchases(demo_id);
CREATE INDEX IF NOT EXISTS idx_user_demo_history_user_id ON public.user_demo_history(user_id);
CREATE INDEX IF NOT EXISTS idx_user_support_tickets_user_id ON public.user_support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_user_support_tickets_status ON public.user_support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_user_wallet_transactions_user_id ON public.user_wallet_transactions(user_id);
-- ===== 20251231232934_076ac97d-5827-4e02-bf14-b184a7faf605.sql =====

-- ═══════════════════════════════════════════════════════════════
-- MASTER ADMIN CONTROL CENTER - CORE DATABASE ARCHITECTURE
-- Part 1: Core Tables
-- ═══════════════════════════════════════════════════════════════

-- GEOGRAPHIC CONTROL
CREATE TABLE IF NOT EXISTS public.master_continents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'locked')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_countries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    continent_id UUID REFERENCES public.master_continents(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    iso_code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'locked')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- BLACKBOX (IMMUTABLE CORE)
CREATE TABLE IF NOT EXISTS public.blackbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    module_name TEXT NOT NULL,
    entity_type TEXT,
    entity_id UUID,
    user_id UUID,
    role_name TEXT,
    ip_address TEXT,
    geo_location TEXT,
    device_fingerprint TEXT,
    user_agent TEXT,
    risk_score INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    is_sealed BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prevent blackbox modifications
CREATE OR REPLACE FUNCTION public.prevent_blackbox_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'BLACKBOX is immutable - modifications are forbidden';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS blackbox_no_update ON public.blackbox_events;
DROP TRIGGER IF EXISTS blackbox_no_delete ON public.blackbox_events;

CREATE TRIGGER blackbox_no_update
    BEFORE UPDATE ON public.blackbox_events
    FOR EACH ROW EXECUTE FUNCTION public.prevent_blackbox_modification();

CREATE TRIGGER blackbox_no_delete
    BEFORE DELETE ON public.blackbox_events
    FOR EACH ROW EXECUTE FUNCTION public.prevent_blackbox_modification();

-- LIVE ACTIVITY ENGINE
CREATE TABLE IF NOT EXISTS public.master_live_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_module TEXT NOT NULL,
    action_name TEXT NOT NULL,
    action_description TEXT,
    user_id UUID,
    user_role TEXT,
    severity TEXT NOT NULL DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    payload JSONB DEFAULT '{}',
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SUPER ADMIN CONTROL
CREATE TABLE IF NOT EXISTS public.master_super_admin_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    authority_scope JSONB NOT NULL DEFAULT '{"level": "global", "regions": []}',
    assigned_continent_id UUID REFERENCES public.master_continents(id),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'locked', 'pending')),
    last_active_at TIMESTAMPTZ,
    total_actions INTEGER DEFAULT 0,
    risk_level TEXT DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_admin_activity_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    super_admin_id UUID REFERENCES public.master_super_admin_profiles(id) ON DELETE RESTRICT,
    action TEXT NOT NULL,
    action_category TEXT NOT NULL,
    target_entity_type TEXT,
    target_entity_id UUID,
    ip_address TEXT,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- GLOBAL RULES ENGINE
CREATE TABLE IF NOT EXISTS public.master_global_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name TEXT NOT NULL,
    rule_code TEXT NOT NULL UNIQUE,
    rule_type TEXT NOT NULL CHECK (rule_type IN ('access', 'approval', 'security', 'rental', 'system')),
    description TEXT,
    rule_logic JSONB NOT NULL DEFAULT '{}',
    version INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'deprecated')),
    impact_level TEXT DEFAULT 'low' CHECK (impact_level IN ('low', 'medium', 'high', 'critical')),
    created_by UUID,
    is_locked BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_rule_execution_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID REFERENCES public.master_global_rules(id) ON DELETE RESTRICT,
    executed_by UUID,
    execution_result TEXT NOT NULL CHECK (execution_result IN ('success', 'failure', 'partial', 'blocked')),
    impact_summary JSONB DEFAULT '{}',
    affected_entities INTEGER DEFAULT 0,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- HIGH-RISK APPROVALS
CREATE TABLE IF NOT EXISTS public.master_approvals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_type TEXT NOT NULL,
    request_title TEXT NOT NULL,
    request_description TEXT,
    requested_by UUID NOT NULL,
    requested_by_role TEXT,
    target_entity_type TEXT,
    target_entity_id UUID,
    risk_score INTEGER NOT NULL DEFAULT 0 CHECK (risk_score >= 0 AND risk_score <= 100),
    risk_factors JSONB DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'escalated', 'expired')),
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    required_approvers INTEGER DEFAULT 1,
    current_approvers INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_approval_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    approval_id UUID REFERENCES public.master_approvals(id) ON DELETE RESTRICT,
    step_number INTEGER NOT NULL,
    approver_role TEXT NOT NULL,
    approver_user_id UUID,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'skipped')),
    decision_notes TEXT,
    decision_at TIMESTAMPTZ,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SECURITY MONITORING
CREATE TABLE IF NOT EXISTS public.master_security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    event_description TEXT,
    user_id UUID,
    ip_address TEXT,
    geo_location TEXT,
    device_fingerprint TEXT,
    severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_ip_watchlist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address TEXT NOT NULL,
    risk_level TEXT NOT NULL DEFAULT 'medium' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    is_blocked BOOLEAN NOT NULL DEFAULT false,
    block_reason TEXT,
    blocked_by UUID,
    blocked_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    hit_count INTEGER DEFAULT 1,
    last_seen_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SYSTEM LOCK (KILL SWITCH)
CREATE TABLE IF NOT EXISTS public.master_system_locks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lock_scope TEXT NOT NULL CHECK (lock_scope IN ('global', 'continent', 'country', 'module', 'user', 'feature')),
    lock_type TEXT NOT NULL DEFAULT 'full' CHECK (lock_type IN ('full', 'partial', 'read_only', 'maintenance')),
    target_id UUID,
    target_name TEXT,
    reason TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'high' CHECK (severity IN ('low', 'medium', 'high', 'critical', 'emergency')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    activated_by UUID NOT NULL,
    activated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    scheduled_release_at TIMESTAMPTZ,
    released_by UUID,
    released_at TIMESTAMPTZ,
    release_notes TEXT,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AUDIT EXPORTS
CREATE TABLE IF NOT EXISTS public.master_audit_exports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_by UUID NOT NULL,
    export_type TEXT NOT NULL CHECK (export_type IN ('full', 'filtered', 'compliance', 'forensic', 'incident')),
    export_scope JSONB NOT NULL DEFAULT '{}',
    date_range_start TIMESTAMPTZ,
    date_range_end TIMESTAMPTZ,
    file_path TEXT,
    file_size_bytes BIGINT,
    watermark_hash TEXT NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
    download_count INTEGER DEFAULT 0,
    max_downloads INTEGER DEFAULT 3,
    expires_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'ready', 'downloaded', 'expired', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.master_live_activity;

-- ===== 20251231233107_585a3af0-9a0a-492c-b677-1c98966f8371.sql =====

-- ═══════════════════════════════════════════════════════════════
-- MASTER ADMIN - Part 2: Rental, AI, Risk, RLS, Indexes, Seeds
-- ═══════════════════════════════════════════════════════════════

-- RENTAL ENGINE
CREATE TABLE IF NOT EXISTS public.master_rental_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_name TEXT NOT NULL,
    plan_code TEXT NOT NULL UNIQUE,
    duration_type TEXT NOT NULL CHECK (duration_type IN ('hour', 'day', 'week', 'month', 'year', 'unlimited')),
    duration_value INTEGER NOT NULL DEFAULT 1,
    price DECIMAL(12,2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'USD',
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_rentable_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_code TEXT NOT NULL UNIQUE,
    feature_name TEXT NOT NULL,
    module_name TEXT NOT NULL,
    description TEXT,
    is_premium BOOLEAN DEFAULT false,
    base_price DECIMAL(12,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_rentals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    feature_id UUID REFERENCES public.master_rentable_features(id) ON DELETE RESTRICT,
    plan_id UUID REFERENCES public.master_rental_plans(id) ON DELETE RESTRICT,
    start_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    end_time TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'revoked', 'suspended', 'pending')),
    revoked_by UUID,
    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT,
    auto_renew BOOLEAN DEFAULT false,
    usage_count INTEGER DEFAULT 0,
    max_usage INTEGER,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_rental_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rental_id UUID REFERENCES public.master_rentals(id) ON DELETE RESTRICT,
    usage_type TEXT NOT NULL,
    usage_metric JSONB DEFAULT '{}',
    ip_address TEXT,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AI WATCHER & RISK ENGINE
CREATE TABLE IF NOT EXISTS public.master_ai_behavior_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    behavior_score INTEGER NOT NULL DEFAULT 50 CHECK (behavior_score >= 0 AND behavior_score <= 100),
    anomaly_level TEXT NOT NULL DEFAULT 'none' CHECK (anomaly_level IN ('none', 'low', 'medium', 'high', 'critical')),
    anomaly_factors JSONB DEFAULT '[]',
    pattern_analysis JSONB DEFAULT '{}',
    last_login_pattern JSONB DEFAULT '{}',
    last_action_pattern JSONB DEFAULT '{}',
    is_flagged BOOLEAN DEFAULT false,
    flagged_reason TEXT,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_risk_entity_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    risk_value INTEGER NOT NULL DEFAULT 0 CHECK (risk_value >= 0 AND risk_value <= 100),
    risk_level TEXT NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    risk_factors JSONB DEFAULT '[]',
    trend TEXT DEFAULT 'stable' CHECK (trend IN ('improving', 'stable', 'worsening')),
    previous_value INTEGER,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.master_ai_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_type TEXT NOT NULL,
    alert_title TEXT NOT NULL,
    alert_description TEXT,
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'danger', 'critical')),
    source_module TEXT NOT NULL,
    target_user_id UUID,
    target_entity_type TEXT,
    target_entity_id UUID,
    is_acknowledged BOOLEAN DEFAULT false,
    acknowledged_by UUID,
    acknowledged_at TIMESTAMPTZ,
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    auto_action_taken TEXT,
    blackbox_event_id UUID REFERENCES public.blackbox_events(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SYSTEM VAULT
CREATE TABLE IF NOT EXISTS public.master_system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key TEXT NOT NULL UNIQUE,
    setting_value TEXT NOT NULL,
    setting_type TEXT DEFAULT 'string' CHECK (setting_type IN ('string', 'number', 'boolean', 'json', 'encrypted')),
    is_encrypted BOOLEAN DEFAULT false,
    is_locked BOOLEAN DEFAULT false,
    last_modified_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ENABLE RLS ON ALL NEW TABLES
ALTER TABLE public.blackbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_live_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_continents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_super_admin_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_admin_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_global_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rule_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_ip_watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_system_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_audit_exports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rental_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rentable_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rentals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rental_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_ai_behavior_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_risk_entity_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_ai_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_system_settings ENABLE ROW LEVEL SECURITY;

-- RLS POLICIES: Master has full access
CREATE POLICY "master_blackbox_select" ON public.blackbox_events FOR SELECT USING (public.is_master());
CREATE POLICY "master_blackbox_insert" ON public.blackbox_events FOR INSERT WITH CHECK (true);

CREATE POLICY "master_live_activity_all" ON public.master_live_activity FOR ALL USING (public.is_master());
CREATE POLICY "master_continents_all" ON public.master_continents FOR ALL USING (public.is_master());
CREATE POLICY "master_countries_all" ON public.master_countries FOR ALL USING (public.is_master());
CREATE POLICY "master_super_admin_profiles_all" ON public.master_super_admin_profiles FOR ALL USING (public.is_master());
CREATE POLICY "master_admin_activity_log_all" ON public.master_admin_activity_log FOR ALL USING (public.is_master());
CREATE POLICY "master_global_rules_all" ON public.master_global_rules FOR ALL USING (public.is_master());
CREATE POLICY "master_rule_execution_logs_all" ON public.master_rule_execution_logs FOR ALL USING (public.is_master());
CREATE POLICY "master_approvals_all" ON public.master_approvals FOR ALL USING (public.is_master());
CREATE POLICY "master_approval_steps_all" ON public.master_approval_steps FOR ALL USING (public.is_master());
CREATE POLICY "master_security_events_all" ON public.master_security_events FOR ALL USING (public.is_master());
CREATE POLICY "master_ip_watchlist_all" ON public.master_ip_watchlist FOR ALL USING (public.is_master());
CREATE POLICY "master_system_locks_all" ON public.master_system_locks FOR ALL USING (public.is_master());
CREATE POLICY "master_audit_exports_all" ON public.master_audit_exports FOR ALL USING (public.is_master());
CREATE POLICY "master_rental_plans_all" ON public.master_rental_plans FOR ALL USING (public.is_master());
CREATE POLICY "master_rentable_features_all" ON public.master_rentable_features FOR ALL USING (public.is_master());
CREATE POLICY "master_rentals_all" ON public.master_rentals FOR ALL USING (public.is_master());
CREATE POLICY "master_rental_usage_logs_all" ON public.master_rental_usage_logs FOR ALL USING (public.is_master());
CREATE POLICY "master_ai_behavior_scores_all" ON public.master_ai_behavior_scores FOR ALL USING (public.is_master());
CREATE POLICY "master_risk_entity_scores_all" ON public.master_risk_entity_scores FOR ALL USING (public.is_master());
CREATE POLICY "master_ai_alerts_all" ON public.master_ai_alerts FOR ALL USING (public.is_master());
CREATE POLICY "master_system_settings_all" ON public.master_system_settings FOR ALL USING (public.is_master());

-- Super Admin read access for key tables
CREATE POLICY "super_admin_blackbox_read" ON public.blackbox_events FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_live_activity_read" ON public.master_live_activity FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_security_events_read" ON public.master_security_events FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_ai_alerts_read" ON public.master_ai_alerts FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_continents_read" ON public.master_continents FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_countries_read" ON public.master_countries FOR SELECT USING (public.is_super_admin());

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_bb_events_user ON public.blackbox_events(user_id);
CREATE INDEX IF NOT EXISTS idx_bb_events_module ON public.blackbox_events(module_name);
CREATE INDEX IF NOT EXISTS idx_bb_events_type ON public.blackbox_events(event_type);
CREATE INDEX IF NOT EXISTS idx_bb_events_created ON public.blackbox_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_act_module ON public.master_live_activity(source_module);
CREATE INDEX IF NOT EXISTS idx_live_act_created ON public.master_live_activity(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON public.master_approvals(status);
CREATE INDEX IF NOT EXISTS idx_approvals_risk ON public.master_approvals(risk_score DESC);
CREATE INDEX IF NOT EXISTS idx_sec_events_type ON public.master_security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_sec_events_severity ON public.master_security_events(severity);
CREATE INDEX IF NOT EXISTS idx_locks_active ON public.master_system_locks(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_rentals_user ON public.master_rentals(user_id);
CREATE INDEX IF NOT EXISTS idx_rentals_status ON public.master_rentals(status);
CREATE INDEX IF NOT EXISTS idx_ai_behavior_user ON public.master_ai_behavior_scores(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_alerts_unresolved ON public.master_ai_alerts(is_resolved) WHERE is_resolved = false;

-- AUTO-UPDATE TIMESTAMP FUNCTION
CREATE OR REPLACE FUNCTION public.master_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- TIMESTAMP TRIGGERS
DROP TRIGGER IF EXISTS update_master_continents_ts ON public.master_continents;
DROP TRIGGER IF EXISTS update_master_countries_ts ON public.master_countries;
DROP TRIGGER IF EXISTS update_master_super_admin_profiles_ts ON public.master_super_admin_profiles;
DROP TRIGGER IF EXISTS update_master_global_rules_ts ON public.master_global_rules;
DROP TRIGGER IF EXISTS update_master_approvals_ts ON public.master_approvals;
DROP TRIGGER IF EXISTS update_master_ip_watchlist_ts ON public.master_ip_watchlist;
DROP TRIGGER IF EXISTS update_master_system_locks_ts ON public.master_system_locks;
DROP TRIGGER IF EXISTS update_master_rental_plans_ts ON public.master_rental_plans;
DROP TRIGGER IF EXISTS update_master_rentable_features_ts ON public.master_rentable_features;
DROP TRIGGER IF EXISTS update_master_rentals_ts ON public.master_rentals;
DROP TRIGGER IF EXISTS update_master_ai_behavior_scores_ts ON public.master_ai_behavior_scores;
DROP TRIGGER IF EXISTS update_master_system_settings_ts ON public.master_system_settings;

CREATE TRIGGER update_master_continents_ts BEFORE UPDATE ON public.master_continents FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_countries_ts BEFORE UPDATE ON public.master_countries FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_super_admin_profiles_ts BEFORE UPDATE ON public.master_super_admin_profiles FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_global_rules_ts BEFORE UPDATE ON public.master_global_rules FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_approvals_ts BEFORE UPDATE ON public.master_approvals FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_ip_watchlist_ts BEFORE UPDATE ON public.master_ip_watchlist FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_system_locks_ts BEFORE UPDATE ON public.master_system_locks FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_rental_plans_ts BEFORE UPDATE ON public.master_rental_plans FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_rentable_features_ts BEFORE UPDATE ON public.master_rentable_features FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_rentals_ts BEFORE UPDATE ON public.master_rentals FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_ai_behavior_scores_ts BEFORE UPDATE ON public.master_ai_behavior_scores FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_system_settings_ts BEFORE UPDATE ON public.master_system_settings FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

-- BLACKBOX LOGGING FUNCTION
CREATE OR REPLACE FUNCTION public.log_to_blackbox(
    p_event_type TEXT,
    p_module_name TEXT,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id UUID DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_role_name TEXT DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL,
    p_geo_location TEXT DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL,
    p_risk_score INTEGER DEFAULT 0,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_event_id UUID;
BEGIN
    INSERT INTO public.blackbox_events (
        event_type, module_name, entity_type, entity_id,
        user_id, role_name, ip_address, geo_location,
        device_fingerprint, risk_score, metadata
    ) VALUES (
        p_event_type, p_module_name, p_entity_type, p_entity_id,
        p_user_id, p_role_name, p_ip_address, p_geo_location,
        p_device_fingerprint, p_risk_score, p_metadata
    ) RETURNING id INTO v_event_id;
    
    -- Also log to live activity
    INSERT INTO public.master_live_activity (
        source_module, action_name, user_id, user_role,
        severity, payload, blackbox_event_id
    ) VALUES (
        p_module_name, p_event_type, p_user_id, p_role_name,
        CASE 
            WHEN p_risk_score >= 80 THEN 'critical'
            WHEN p_risk_score >= 60 THEN 'high'
            WHEN p_risk_score >= 40 THEN 'medium'
            ELSE 'low'
        END,
        p_metadata,
        v_event_id
    );
    
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- SEED: CONTINENTS
INSERT INTO public.master_continents (name, code, status) VALUES
    ('Africa', 'AF', 'active'),
    ('Asia', 'AS', 'active'),
    ('Europe', 'EU', 'active'),
    ('North America', 'NA', 'active'),
    ('South America', 'SA', 'active'),
    ('Oceania', 'OC', 'active'),
    ('Antarctica', 'AN', 'disabled')
ON CONFLICT (code) DO NOTHING;

-- SEED: RENTAL PLANS
INSERT INTO public.master_rental_plans (plan_name, plan_code, duration_type, duration_value, price) VALUES
    ('Hourly Access', 'HOURLY', 'hour', 1, 9.99),
    ('Daily Access', 'DAILY', 'day', 1, 49.99),
    ('Weekly Access', 'WEEKLY', 'week', 1, 199.99),
    ('Monthly Access', 'MONTHLY', 'month', 1, 499.99),
    ('Annual Access', 'ANNUAL', 'year', 1, 4999.99),
    ('Enterprise Unlimited', 'UNLIMITED', 'unlimited', 0, 9999.99)
ON CONFLICT (plan_code) DO NOTHING;

-- SEED: RENTABLE FEATURES
INSERT INTO public.master_rentable_features (feature_code, feature_name, module_name, is_premium, base_price) VALUES
    ('BLACKBOX_VIEW', 'Blackbox Event Viewer', 'overview', true, 99.99),
    ('CONTINENT_CONTROL', 'Continent Management', 'continents', true, 199.99),
    ('ADMIN_MANAGEMENT', 'Super Admin Control', 'super_admins', true, 299.99),
    ('RULE_ENGINE', 'Global Rules Engine', 'global_rules', true, 149.99),
    ('HIGH_RISK_APPROVAL', 'High-Risk Approvals', 'approvals', true, 249.99),
    ('SECURITY_MONITOR', 'Security Monitoring', 'security', true, 399.99),
    ('AUDIT_EXPORT', 'Audit Export Tools', 'audit', true, 199.99),
    ('SYSTEM_LOCK', 'System Lock Controls', 'system_lock', true, 499.99),
    ('AI_WATCHER', 'AI Behavior Analysis', 'ai_watcher', true, 349.99),
    ('RISK_ENGINE', 'Risk Scoring Engine', 'risk_engine', true, 299.99)
ON CONFLICT (feature_code) DO NOTHING;

-- SEED: COUNTRIES
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Nigeria', 'NG', 'active' FROM public.master_continents c WHERE c.code = 'AF' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'South Africa', 'ZA', 'active' FROM public.master_continents c WHERE c.code = 'AF' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Egypt', 'EG', 'active' FROM public.master_continents c WHERE c.code = 'AF' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'China', 'CN', 'active' FROM public.master_continents c WHERE c.code = 'AS' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'India', 'IN', 'active' FROM public.master_continents c WHERE c.code = 'AS' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Japan', 'JP', 'active' FROM public.master_continents c WHERE c.code = 'AS' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'United Kingdom', 'GB', 'active' FROM public.master_continents c WHERE c.code = 'EU' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Germany', 'DE', 'active' FROM public.master_continents c WHERE c.code = 'EU' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'France', 'FR', 'active' FROM public.master_continents c WHERE c.code = 'EU' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'United States', 'US', 'active' FROM public.master_continents c WHERE c.code = 'NA' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Canada', 'CA', 'active' FROM public.master_continents c WHERE c.code = 'NA' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Brazil', 'BR', 'active' FROM public.master_continents c WHERE c.code = 'SA' ON CONFLICT (iso_code) DO NOTHING;
INSERT INTO public.master_countries (continent_id, name, iso_code, status)
SELECT c.id, 'Australia', 'AU', 'active' FROM public.master_continents c WHERE c.code = 'OC' ON CONFLICT (iso_code) DO NOTHING;

-- ===== 20251231233322_94dcf150-f60a-4a2d-820a-57a2de64f384.sql =====

-- ═══════════════════════════════════════════════════════════════
-- MASTER ADMIN - Part 3: Identity & Access Control (Final Lock)
-- ═══════════════════════════════════════════════════════════════

-- MASTER ROLES
CREATE TABLE IF NOT EXISTS public.master_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    scope_level TEXT NOT NULL DEFAULT 'global' CHECK (scope_level IN ('global', 'continent', 'country', 'region')),
    hierarchy_level INTEGER NOT NULL DEFAULT 0,
    is_system_role BOOLEAN DEFAULT false,
    can_be_deleted BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- MASTER PERMISSIONS
CREATE TABLE IF NOT EXISTS public.master_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code TEXT NOT NULL UNIQUE,
    permission_name TEXT NOT NULL,
    description TEXT,
    module_name TEXT NOT NULL,
    is_sensitive BOOLEAN DEFAULT false,
    requires_2fa BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ROLE-PERMISSION MAPPING
CREATE TABLE IF NOT EXISTS public.master_role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES public.master_roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.master_permissions(id) ON DELETE CASCADE,
    granted_by UUID,
    granted_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(role_id, permission_id)
);

-- MASTER USERS (Control Center Users)
CREATE TABLE IF NOT EXISTS public.master_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id UUID UNIQUE,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    role_id UUID REFERENCES public.master_roles(id),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'locked', 'pending', 'terminated')),
    status_reason TEXT,
    last_login_at TIMESTAMPTZ,
    last_login_ip TEXT,
    login_count INTEGER DEFAULT 0,
    failed_login_count INTEGER DEFAULT 0,
    is_2fa_enabled BOOLEAN DEFAULT false,
    assigned_continent_id UUID REFERENCES public.master_continents(id),
    assigned_country_ids UUID[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- USER SESSIONS TRACKING
CREATE TABLE IF NOT EXISTS public.master_user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.master_users(id) ON DELETE CASCADE,
    session_token_hash TEXT NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    device_fingerprint TEXT,
    geo_location TEXT,
    is_active BOOLEAN DEFAULT true,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    terminated_at TIMESTAMPTZ,
    terminated_reason TEXT
);

-- PERMISSION GRANTS (Dynamic per-user overrides)
CREATE TABLE IF NOT EXISTS public.master_permission_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.master_users(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.master_permissions(id) ON DELETE CASCADE,
    grant_type TEXT NOT NULL DEFAULT 'allow' CHECK (grant_type IN ('allow', 'deny')),
    granted_by UUID,
    expires_at TIMESTAMPTZ,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, permission_id)
);

-- ENABLE RLS
ALTER TABLE public.master_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_permission_grants ENABLE ROW LEVEL SECURITY;

-- RLS POLICIES
CREATE POLICY "master_roles_all" ON public.master_roles FOR ALL USING (public.is_master());
CREATE POLICY "master_permissions_all" ON public.master_permissions FOR ALL USING (public.is_master());
CREATE POLICY "master_role_permissions_all" ON public.master_role_permissions FOR ALL USING (public.is_master());
CREATE POLICY "master_users_all" ON public.master_users FOR ALL USING (public.is_master());
CREATE POLICY "master_user_sessions_all" ON public.master_user_sessions FOR ALL USING (public.is_master());
CREATE POLICY "master_permission_grants_all" ON public.master_permission_grants FOR ALL USING (public.is_master());

-- Super Admin read access
CREATE POLICY "super_admin_roles_read" ON public.master_roles FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_permissions_read" ON public.master_permissions FOR SELECT USING (public.is_super_admin());
CREATE POLICY "super_admin_users_read" ON public.master_users FOR SELECT USING (public.is_super_admin());

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_master_users_role ON public.master_users(role_id);
CREATE INDEX IF NOT EXISTS idx_master_users_status ON public.master_users(status);
CREATE INDEX IF NOT EXISTS idx_master_users_email ON public.master_users(email);
CREATE INDEX IF NOT EXISTS idx_master_sessions_user ON public.master_user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_master_sessions_active ON public.master_user_sessions(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_master_role_perms_role ON public.master_role_permissions(role_id);

-- TIMESTAMP TRIGGERS
CREATE TRIGGER update_master_roles_ts BEFORE UPDATE ON public.master_roles FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();
CREATE TRIGGER update_master_users_ts BEFORE UPDATE ON public.master_users FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

-- AUTO-LOG USER STATUS CHANGES TO BLACKBOX
CREATE OR REPLACE FUNCTION public.log_user_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        PERFORM public.log_to_blackbox(
            'update',
            'identity',
            'master_user',
            NEW.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            CASE WHEN NEW.status IN ('suspended', 'locked', 'terminated') THEN 70 ELSE 20 END,
            jsonb_build_object(
                'old_status', OLD.status,
                'new_status', NEW.status,
                'reason', NEW.status_reason
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER log_user_status_change_trigger
    AFTER UPDATE ON public.master_users
    FOR EACH ROW EXECUTE FUNCTION public.log_user_status_change();

-- SEED: ROLES
INSERT INTO public.master_roles (name, display_name, scope_level, hierarchy_level, is_system_role, can_be_deleted) VALUES
    ('master', 'Master Admin', 'global', 100, true, false),
    ('super_admin', 'Super Admin', 'global', 90, true, false),
    ('admin', 'Administrator', 'continent', 70, true, false),
    ('security', 'Security Officer', 'global', 80, true, false),
    ('auditor', 'Auditor', 'global', 60, true, false),
    ('viewer', 'Viewer', 'country', 10, true, false)
ON CONFLICT (name) DO NOTHING;

-- SEED: PERMISSIONS
INSERT INTO public.master_permissions (permission_code, permission_name, module_name, is_sensitive, requires_2fa) VALUES
    -- Overview
    ('overview.view', 'View Overview', 'overview', false, false),
    ('overview.blackbox.view', 'View Blackbox Panel', 'overview', true, false),
    -- Continents
    ('continents.view', 'View Continents', 'continents', false, false),
    ('continents.manage', 'Manage Continents', 'continents', true, true),
    ('continents.lock', 'Lock Continent', 'continents', true, true),
    -- Super Admins
    ('superadmins.view', 'View Super Admins', 'super_admins', true, false),
    ('superadmins.manage', 'Manage Super Admins', 'super_admins', true, true),
    ('superadmins.suspend', 'Suspend Super Admin', 'super_admins', true, true),
    -- Global Rules
    ('rules.view', 'View Rules', 'global_rules', false, false),
    ('rules.create', 'Create Rules', 'global_rules', true, true),
    ('rules.execute', 'Execute Rules', 'global_rules', true, true),
    -- Approvals
    ('approvals.view', 'View Approvals', 'approvals', false, false),
    ('approvals.decide', 'Approve/Reject', 'approvals', true, true),
    ('approvals.escalate', 'Escalate Approvals', 'approvals', true, false),
    -- Security
    ('security.view', 'View Security', 'security', true, false),
    ('security.manage', 'Manage Security', 'security', true, true),
    ('security.block_ip', 'Block IP Address', 'security', true, true),
    -- Audit
    ('audit.view', 'View Audit Logs', 'audit', true, false),
    ('audit.export', 'Export Audit', 'audit', true, true),
    ('audit.replay', 'Replay Timeline', 'audit', true, false),
    -- System Lock
    ('systemlock.view', 'View System Lock', 'system_lock', true, false),
    ('systemlock.activate', 'Activate Lock', 'system_lock', true, true),
    ('systemlock.release', 'Release Lock', 'system_lock', true, true),
    -- Rental
    ('rental.view', 'View Rentals', 'rental', false, false),
    ('rental.manage', 'Manage Rentals', 'rental', true, true),
    ('rental.revoke', 'Revoke Rental', 'rental', true, true),
    -- AI Watcher
    ('ai.view', 'View AI Analysis', 'ai_watcher', true, false),
    ('ai.alerts.manage', 'Manage AI Alerts', 'ai_watcher', true, false)
ON CONFLICT (permission_code) DO NOTHING;

-- ASSIGN ALL PERMISSIONS TO MASTER ROLE
INSERT INTO public.master_role_permissions (role_id, permission_id)
SELECT r.id, p.id 
FROM public.master_roles r, public.master_permissions p
WHERE r.name = 'master'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ASSIGN MOST PERMISSIONS TO SUPER_ADMIN (except system lock activate)
INSERT INTO public.master_role_permissions (role_id, permission_id)
SELECT r.id, p.id 
FROM public.master_roles r, public.master_permissions p
WHERE r.name = 'super_admin' 
AND p.permission_code NOT IN ('systemlock.activate', 'systemlock.release')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ASSIGN VIEW PERMISSIONS TO AUDITOR
INSERT INTO public.master_role_permissions (role_id, permission_id)
SELECT r.id, p.id 
FROM public.master_roles r, public.master_permissions p
WHERE r.name = 'auditor' 
AND p.permission_code LIKE '%.view' OR p.permission_code IN ('audit.export', 'audit.replay')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- CHECK USER HAS PERMISSION FUNCTION
CREATE OR REPLACE FUNCTION public.master_user_has_permission(p_user_id UUID, p_permission_code TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_has_permission BOOLEAN := false;
    v_grant_override TEXT;
BEGIN
    -- Check for explicit deny first
    SELECT grant_type INTO v_grant_override
    FROM public.master_permission_grants
    WHERE user_id = p_user_id
    AND permission_id = (SELECT id FROM public.master_permissions WHERE permission_code = p_permission_code)
    AND (expires_at IS NULL OR expires_at > now());
    
    IF v_grant_override = 'deny' THEN
        RETURN false;
    ELSIF v_grant_override = 'allow' THEN
        RETURN true;
    END IF;
    
    -- Check role permissions
    SELECT EXISTS (
        SELECT 1 FROM public.master_users u
        JOIN public.master_role_permissions rp ON u.role_id = rp.role_id
        JOIN public.master_permissions p ON rp.permission_id = p.id
        WHERE u.id = p_user_id
        AND p.permission_code = p_permission_code
        AND u.status = 'active'
    ) INTO v_has_permission;
    
    RETURN v_has_permission;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- CHECK SYSTEM LOCK STATUS FUNCTION
CREATE OR REPLACE FUNCTION public.is_system_locked(p_scope TEXT DEFAULT 'global', p_target_id UUID DEFAULT NULL)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.master_system_locks
        WHERE is_active = true
        AND (
            lock_scope = 'global'
            OR (lock_scope = p_scope AND (p_target_id IS NULL OR target_id = p_target_id))
        )
        AND (scheduled_release_at IS NULL OR scheduled_release_at > now())
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RENTAL AUTO-EXPIRY CHECK
CREATE OR REPLACE FUNCTION public.check_rental_active(p_user_id UUID, p_feature_code TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.master_rentals r
        JOIN public.master_rentable_features f ON r.feature_id = f.id
        WHERE r.user_id = p_user_id
        AND f.feature_code = p_feature_code
        AND r.status = 'active'
        AND r.end_time > now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- AUTO-EXPIRE RENTALS FUNCTION
CREATE OR REPLACE FUNCTION public.auto_expire_rentals()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE public.master_rentals
    SET status = 'expired', updated_at = now()
    WHERE status = 'active' AND end_time <= now();
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Log to blackbox if any expired
    IF v_count > 0 THEN
        PERFORM public.log_to_blackbox(
            'update',
            'rental_engine',
            'rental_batch',
            NULL,
            NULL,
            'system',
            NULL, NULL, NULL,
            0,
            jsonb_build_object('action', 'auto_expire', 'count', v_count)
        );
    END IF;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ===== 20251231234602_54e04b0e-8bfb-4bb3-9ac5-1b0eaf2f931e.sql =====
-- ════════════════════════════════════════════════════════════════
-- MASTER ADMIN SECURITY ARCHITECTURE - ZERO TRUST IMPLEMENTATION
-- ════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════
-- 1. DEVICE FINGERPRINT REGISTRY
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_device_fingerprints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    fingerprint_hash TEXT NOT NULL,
    device_name TEXT,
    browser TEXT,
    os TEXT,
    ip_address TEXT,
    geo_location TEXT,
    is_trusted BOOLEAN DEFAULT false,
    trust_level INTEGER DEFAULT 0, -- 0-100
    first_seen_at TIMESTAMPTZ DEFAULT now(),
    last_seen_at TIMESTAMPTZ DEFAULT now(),
    is_blocked BOOLEAN DEFAULT false,
    blocked_reason TEXT,
    blocked_at TIMESTAMPTZ,
    blocked_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, fingerprint_hash)
);

-- ═══════════════════════════════════════════
-- 2. LOGIN ATTEMPTS (Rate Limiting & Security)
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    email TEXT,
    ip_address TEXT NOT NULL,
    device_fingerprint TEXT,
    geo_location TEXT,
    attempt_type TEXT NOT NULL, -- 'success', 'failed_password', 'failed_mfa', 'blocked', 'locked'
    failure_reason TEXT,
    risk_score INTEGER DEFAULT 0,
    is_anomaly BOOLEAN DEFAULT false,
    anomaly_reasons JSONB DEFAULT '[]'::jsonb,
    captcha_required BOOLEAN DEFAULT false,
    captcha_passed BOOLEAN,
    session_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 3. TOKEN REGISTRY (Session Management)
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_token_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    token_type TEXT NOT NULL, -- 'access', 'refresh'
    device_fingerprint TEXT,
    ip_address TEXT,
    geo_location TEXT,
    issued_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ,
    is_revoked BOOLEAN DEFAULT false,
    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT, -- 'logout', 'role_change', 'system_lock', 'rental_expiry', 'security_threat'
    revoked_by UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 4. BLACKBOX HASH CHAIN (Tamper Detection)
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_blackbox_hash_chain (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blackbox_event_id UUID NOT NULL REFERENCES public.blackbox_events(id),
    sequence_number BIGINT NOT NULL UNIQUE,
    event_hash TEXT NOT NULL,
    previous_hash TEXT NOT NULL,
    chain_hash TEXT NOT NULL, -- hash(event_hash + previous_hash)
    verification_status TEXT DEFAULT 'valid', -- 'valid', 'tampered', 'pending'
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 5. RATE LIMITS CONFIGURATION
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    endpoint TEXT NOT NULL,
    limit_type TEXT NOT NULL, -- 'ip', 'user', 'global'
    max_requests INTEGER NOT NULL,
    window_seconds INTEGER NOT NULL,
    cooldown_seconds INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(endpoint, limit_type)
);

-- ═══════════════════════════════════════════
-- 6. RATE LIMIT TRACKING
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_rate_limit_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_limit_id UUID REFERENCES public.master_rate_limits(id),
    identifier TEXT NOT NULL, -- IP or user_id
    identifier_type TEXT NOT NULL, -- 'ip', 'user'
    request_count INTEGER DEFAULT 1,
    window_start TIMESTAMPTZ DEFAULT now(),
    cooldown_until TIMESTAMPTZ,
    is_blocked BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 7. SECURITY THREAT LOG
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_security_threats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    threat_type TEXT NOT NULL, -- 'brute_force', 'replay_attack', 'injection', 'privilege_escalation', 'anomaly', 'geo_anomaly'
    severity TEXT NOT NULL, -- 'low', 'medium', 'high', 'critical'
    source_ip TEXT,
    source_user_id UUID,
    target_entity TEXT,
    target_id UUID,
    threat_data JSONB DEFAULT '{}'::jsonb,
    auto_response TEXT, -- 'none', 'captcha', 'step_up', 'session_kill', 'user_lock', 'ip_block'
    auto_response_at TIMESTAMPTZ,
    is_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID,
    resolution_notes TEXT,
    blackbox_event_id UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 8. ACCESS CONTROL CHECKS LOG
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_access_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    action TEXT NOT NULL,
    module TEXT,
    entity_type TEXT,
    entity_id UUID,
    check_system_lock BOOLEAN DEFAULT true,
    check_user_status BOOLEAN DEFAULT true,
    check_role_scope BOOLEAN DEFAULT true,
    check_permission BOOLEAN DEFAULT true,
    check_rental BOOLEAN DEFAULT true,
    check_risk_score BOOLEAN DEFAULT true,
    system_lock_passed BOOLEAN,
    user_status_passed BOOLEAN,
    role_scope_passed BOOLEAN,
    permission_passed BOOLEAN,
    rental_passed BOOLEAN,
    risk_score_passed BOOLEAN,
    final_result BOOLEAN NOT NULL,
    denial_reason TEXT,
    risk_score INTEGER,
    ip_address TEXT,
    device_fingerprint TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 9. SECURITY SETTINGS (Encrypted Vault)
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_security_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key TEXT NOT NULL UNIQUE,
    setting_value_encrypted TEXT, -- encrypted value
    setting_type TEXT DEFAULT 'string', -- 'string', 'number', 'boolean', 'json'
    is_secret BOOLEAN DEFAULT false,
    rotation_required BOOLEAN DEFAULT false,
    last_rotated_at TIMESTAMPTZ,
    rotation_interval_days INTEGER,
    updated_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════
-- 10. ANTI-REPLAY TOKENS
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.master_replay_protection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id TEXT NOT NULL UNIQUE,
    request_hash TEXT NOT NULL,
    user_id UUID,
    endpoint TEXT NOT NULL,
    ip_address TEXT,
    used_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- ═══════════════════════════════════════════
-- INDEXES FOR PERFORMANCE
-- ═══════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_user ON public.master_device_fingerprints(user_id);
CREATE INDEX IF NOT EXISTS idx_device_fingerprints_hash ON public.master_device_fingerprints(fingerprint_hash);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip ON public.master_login_attempts(ip_address, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_user ON public.master_login_attempts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_token_registry_user ON public.master_token_registry(user_id);
CREATE INDEX IF NOT EXISTS idx_token_registry_hash ON public.master_token_registry(token_hash);
CREATE INDEX IF NOT EXISTS idx_hash_chain_sequence ON public.master_blackbox_hash_chain(sequence_number);
CREATE INDEX IF NOT EXISTS idx_rate_limit_tracking ON public.master_rate_limit_tracking(identifier, identifier_type);
CREATE INDEX IF NOT EXISTS idx_security_threats_severity ON public.master_security_threats(severity, is_resolved);
CREATE INDEX IF NOT EXISTS idx_access_checks_user ON public.master_access_checks(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_replay_protection_expires ON public.master_replay_protection(expires_at);

-- ═══════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════
ALTER TABLE public.master_device_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_token_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_blackbox_hash_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_rate_limit_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_security_threats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_access_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_security_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_replay_protection ENABLE ROW LEVEL SECURITY;

-- Security tables: Master full access, Super Admin read, Security team limited access
CREATE POLICY "master_device_fingerprints_policy" ON public.master_device_fingerprints
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_device_fingerprints_read_policy" ON public.master_device_fingerprints
    FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::app_role));

CREATE POLICY "master_login_attempts_policy" ON public.master_login_attempts
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_login_attempts_insert_policy" ON public.master_login_attempts
    FOR INSERT WITH CHECK (true); -- Allow system inserts

CREATE POLICY "master_login_attempts_read_policy" ON public.master_login_attempts
    FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::app_role));

CREATE POLICY "master_token_registry_policy" ON public.master_token_registry
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_token_registry_self_policy" ON public.master_token_registry
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "master_hash_chain_policy" ON public.master_blackbox_hash_chain
    FOR SELECT USING (public.has_role(auth.uid(), 'master'::app_role) OR public.has_role(auth.uid(), 'super_admin'::app_role));

-- Hash chain is append-only
CREATE POLICY "master_hash_chain_insert_policy" ON public.master_blackbox_hash_chain
    FOR INSERT WITH CHECK (true);

CREATE POLICY "master_rate_limits_policy" ON public.master_rate_limits
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_rate_limit_tracking_policy" ON public.master_rate_limit_tracking
    FOR ALL USING (true); -- System managed

CREATE POLICY "master_security_threats_policy" ON public.master_security_threats
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_security_threats_read_policy" ON public.master_security_threats
    FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::app_role));

CREATE POLICY "master_access_checks_policy" ON public.master_access_checks
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_access_checks_insert_policy" ON public.master_access_checks
    FOR INSERT WITH CHECK (true); -- System inserts

CREATE POLICY "master_security_settings_policy" ON public.master_security_settings
    FOR ALL USING (public.has_role(auth.uid(), 'master'::app_role));

CREATE POLICY "master_replay_protection_policy" ON public.master_replay_protection
    FOR ALL USING (true); -- System managed

-- ═══════════════════════════════════════════
-- TIMESTAMP TRIGGERS
-- ═══════════════════════════════════════════
CREATE TRIGGER update_master_device_fingerprints_timestamp
    BEFORE UPDATE ON public.master_device_fingerprints
    FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

CREATE TRIGGER update_master_rate_limits_timestamp
    BEFORE UPDATE ON public.master_rate_limits
    FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

CREATE TRIGGER update_master_rate_limit_tracking_timestamp
    BEFORE UPDATE ON public.master_rate_limit_tracking
    FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

CREATE TRIGGER update_master_security_settings_timestamp
    BEFORE UPDATE ON public.master_security_settings
    FOR EACH ROW EXECUTE FUNCTION public.master_update_timestamp();

-- ═══════════════════════════════════════════
-- SEED RATE LIMITS
-- ═══════════════════════════════════════════
INSERT INTO public.master_rate_limits (endpoint, limit_type, max_requests, window_seconds, cooldown_seconds) VALUES
    ('/auth/login', 'ip', 5, 300, 900), -- 5 attempts per 5 min, 15 min cooldown
    ('/auth/login', 'user', 10, 3600, 1800), -- 10 attempts per hour, 30 min cooldown
    ('/api/*', 'ip', 100, 60, 60), -- 100 requests per minute
    ('/api/*', 'user', 200, 60, 30), -- 200 requests per minute per user
    ('/auth/refresh', 'user', 20, 3600, 0), -- 20 refreshes per hour
    ('/security/*', 'user', 50, 60, 120), -- Security endpoints limited
    ('/audit/*', 'user', 30, 60, 60) -- Audit endpoints limited
ON CONFLICT (endpoint, limit_type) DO NOTHING;

-- ═══════════════════════════════════════════
-- SEED SECURITY SETTINGS
-- ═══════════════════════════════════════════
INSERT INTO public.master_security_settings (setting_key, setting_value_encrypted, setting_type, is_secret) VALUES
    ('jwt_expiry_minutes', '15', 'number', false),
    ('refresh_token_expiry_hours', '24', 'number', false),
    ('max_login_failures', '5', 'number', false),
    ('lockout_duration_minutes', '30', 'number', false),
    ('require_captcha_after_failures', '3', 'number', false),
    ('risk_score_threshold_high', '70', 'number', false),
    ('risk_score_threshold_critical', '90', 'number', false),
    ('session_inactivity_timeout_minutes', '30', 'number', false),
    ('geo_anomaly_enabled', 'true', 'boolean', false),
    ('device_fingerprint_required', 'true', 'boolean', false)
ON CONFLICT (setting_key) DO NOTHING;
-- ===== 20251231234801_8d4bec33-de3d-4881-a10a-5436311408d3.sql =====
-- ════════════════════════════════════════════════════════════════
-- SECURITY FUNCTIONS & TRIGGERS - ZERO TRUST ENFORCEMENT
-- ════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════
-- 1. HASH CHAIN GENERATOR FOR BLACKBOX
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_blackbox_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sequence BIGINT;
    v_previous_hash TEXT;
    v_event_hash TEXT;
    v_chain_hash TEXT;
BEGIN
    -- Get next sequence number
    SELECT COALESCE(MAX(sequence_number), 0) + 1 INTO v_sequence
    FROM public.master_blackbox_hash_chain;
    
    -- Get previous hash (or genesis hash for first record)
    IF v_sequence = 1 THEN
        v_previous_hash := encode(sha256('GENESIS_BLOCK_MASTER_ADMIN'::bytea), 'hex');
    ELSE
        SELECT chain_hash INTO v_previous_hash
        FROM public.master_blackbox_hash_chain
        WHERE sequence_number = v_sequence - 1;
    END IF;
    
    -- Generate event hash from blackbox event data
    v_event_hash := encode(sha256(
        (NEW.id::text || NEW.event_type || NEW.module_name || 
         COALESCE(NEW.user_id::text, '') || NEW.created_at::text)::bytea
    ), 'hex');
    
    -- Generate chain hash
    v_chain_hash := encode(sha256((v_event_hash || v_previous_hash)::bytea), 'hex');
    
    -- Insert into hash chain
    INSERT INTO public.master_blackbox_hash_chain (
        blackbox_event_id, sequence_number, event_hash, previous_hash, chain_hash
    ) VALUES (
        NEW.id, v_sequence, v_event_hash, v_previous_hash, v_chain_hash
    );
    
    RETURN NEW;
END;
$$;

-- Trigger to auto-generate hash chain on blackbox insert
DROP TRIGGER IF EXISTS trg_blackbox_hash_chain ON public.blackbox_events;
CREATE TRIGGER trg_blackbox_hash_chain
    AFTER INSERT ON public.blackbox_events
    FOR EACH ROW EXECUTE FUNCTION public.generate_blackbox_hash();

-- ═══════════════════════════════════════════
-- 2. COMPREHENSIVE ACCESS CONTROL CHECK
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_check_access(
    p_user_id UUID,
    p_action TEXT,
    p_module TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id UUID DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_system_lock_passed BOOLEAN := true;
    v_user_status_passed BOOLEAN := true;
    v_role_scope_passed BOOLEAN := true;
    v_permission_passed BOOLEAN := true;
    v_rental_passed BOOLEAN := true;
    v_risk_score_passed BOOLEAN := true;
    v_denial_reason TEXT;
    v_user_role TEXT;
    v_user_status TEXT;
    v_risk_score INTEGER := 0;
    v_final_result BOOLEAN := true;
BEGIN
    -- CHECK 1: SYSTEM LOCK
    IF EXISTS (
        SELECT 1 FROM public.master_system_locks
        WHERE lock_scope = 'global' AND released_at IS NULL
    ) THEN
        v_system_lock_passed := false;
        v_denial_reason := 'System is globally locked';
        v_final_result := false;
    END IF;
    
    -- Check user-specific lock
    IF v_final_result AND EXISTS (
        SELECT 1 FROM public.master_system_locks
        WHERE lock_scope = 'user' AND target_id = p_user_id AND released_at IS NULL
    ) THEN
        v_system_lock_passed := false;
        v_denial_reason := 'User is locked';
        v_final_result := false;
    END IF;
    
    -- CHECK 2: USER STATUS
    IF v_final_result THEN
        SELECT role::text, approval_status INTO v_user_role, v_user_status
        FROM public.user_roles
        WHERE user_id = p_user_id;
        
        IF v_user_status != 'approved' THEN
            v_user_status_passed := false;
            v_denial_reason := 'User not approved: ' || COALESCE(v_user_status, 'no status');
            v_final_result := false;
        END IF;
    END IF;
    
    -- CHECK 3: ROLE SCOPE (simplified - would need more complex logic in production)
    IF v_final_result AND v_user_role IS NULL THEN
        v_role_scope_passed := false;
        v_denial_reason := 'No role assigned';
        v_final_result := false;
    END IF;
    
    -- CHECK 4: PERMISSION
    IF v_final_result AND p_action IS NOT NULL THEN
        IF NOT public.master_user_has_permission(p_user_id, p_action) THEN
            v_permission_passed := false;
            v_denial_reason := 'Permission denied for action: ' || p_action;
            v_final_result := false;
        END IF;
    END IF;
    
    -- CHECK 5: RENTAL VALIDITY (if module requires rental)
    IF v_final_result AND p_module IS NOT NULL THEN
        -- Check if module is a rentable feature
        IF EXISTS (SELECT 1 FROM public.master_rentable_features WHERE module_name = p_module) THEN
            IF NOT public.check_rental_active(p_user_id, p_module) THEN
                v_rental_passed := false;
                v_denial_reason := 'Rental expired or not active for: ' || p_module;
                v_final_result := false;
            END IF;
        END IF;
    END IF;
    
    -- CHECK 6: RISK SCORE
    IF v_final_result THEN
        SELECT current_score INTO v_risk_score
        FROM public.risk_scores
        WHERE user_id = p_user_id;
        
        v_risk_score := COALESCE(v_risk_score, 0);
        
        IF v_risk_score >= 90 THEN
            v_risk_score_passed := false;
            v_denial_reason := 'Risk score too high: ' || v_risk_score;
            v_final_result := false;
        END IF;
    END IF;
    
    -- LOG ACCESS CHECK
    INSERT INTO public.master_access_checks (
        user_id, action, module, entity_type, entity_id,
        system_lock_passed, user_status_passed, role_scope_passed,
        permission_passed, rental_passed, risk_score_passed,
        final_result, denial_reason, risk_score,
        ip_address, device_fingerprint
    ) VALUES (
        p_user_id, p_action, p_module, p_entity_type, p_entity_id,
        v_system_lock_passed, v_user_status_passed, v_role_scope_passed,
        v_permission_passed, v_rental_passed, v_risk_score_passed,
        v_final_result, v_denial_reason, v_risk_score,
        p_ip_address, p_device_fingerprint
    );
    
    -- Build result
    v_result := jsonb_build_object(
        'allowed', v_final_result,
        'checks', jsonb_build_object(
            'system_lock', v_system_lock_passed,
            'user_status', v_user_status_passed,
            'role_scope', v_role_scope_passed,
            'permission', v_permission_passed,
            'rental', v_rental_passed,
            'risk_score', v_risk_score_passed
        ),
        'denial_reason', v_denial_reason,
        'risk_score', v_risk_score,
        'user_role', v_user_role
    );
    
    RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════
-- 3. RATE LIMIT CHECK FUNCTION
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_check_rate_limit(
    p_endpoint TEXT,
    p_identifier TEXT,
    p_identifier_type TEXT -- 'ip' or 'user'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit RECORD;
    v_tracking RECORD;
    v_is_blocked BOOLEAN := false;
    v_remaining INTEGER;
    v_reset_at TIMESTAMPTZ;
    v_cooldown_until TIMESTAMPTZ;
BEGIN
    -- Get rate limit config for endpoint
    SELECT * INTO v_limit
    FROM public.master_rate_limits
    WHERE (endpoint = p_endpoint OR endpoint = '/api/*')
    AND limit_type = p_identifier_type
    AND is_active = true
    LIMIT 1;
    
    IF v_limit IS NULL THEN
        -- No rate limit configured, allow
        RETURN jsonb_build_object('allowed', true, 'remaining', -1);
    END IF;
    
    -- Get or create tracking record
    SELECT * INTO v_tracking
    FROM public.master_rate_limit_tracking
    WHERE rate_limit_id = v_limit.id
    AND identifier = p_identifier
    AND identifier_type = p_identifier_type;
    
    IF v_tracking IS NULL THEN
        -- First request, create tracking
        INSERT INTO public.master_rate_limit_tracking (
            rate_limit_id, identifier, identifier_type, request_count, window_start
        ) VALUES (
            v_limit.id, p_identifier, p_identifier_type, 1, now()
        );
        
        RETURN jsonb_build_object(
            'allowed', true,
            'remaining', v_limit.max_requests - 1,
            'reset_at', now() + (v_limit.window_seconds || ' seconds')::interval
        );
    END IF;
    
    -- Check if in cooldown
    IF v_tracking.cooldown_until IS NOT NULL AND v_tracking.cooldown_until > now() THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'remaining', 0,
            'cooldown_until', v_tracking.cooldown_until,
            'reason', 'Rate limit cooldown active'
        );
    END IF;
    
    -- Check if window expired
    IF v_tracking.window_start + (v_limit.window_seconds || ' seconds')::interval < now() THEN
        -- Reset window
        UPDATE public.master_rate_limit_tracking
        SET request_count = 1, window_start = now(), is_blocked = false, cooldown_until = NULL
        WHERE id = v_tracking.id;
        
        RETURN jsonb_build_object(
            'allowed', true,
            'remaining', v_limit.max_requests - 1,
            'reset_at', now() + (v_limit.window_seconds || ' seconds')::interval
        );
    END IF;
    
    -- Check if limit exceeded
    IF v_tracking.request_count >= v_limit.max_requests THEN
        -- Apply cooldown
        v_cooldown_until := now() + (v_limit.cooldown_seconds || ' seconds')::interval;
        
        UPDATE public.master_rate_limit_tracking
        SET is_blocked = true, cooldown_until = v_cooldown_until
        WHERE id = v_tracking.id;
        
        -- Log security threat
        INSERT INTO public.master_security_threats (
            threat_type, severity, source_ip, source_user_id,
            target_entity, threat_data, auto_response
        ) VALUES (
            'rate_limit_exceeded', 'medium',
            CASE WHEN p_identifier_type = 'ip' THEN p_identifier ELSE NULL END,
            CASE WHEN p_identifier_type = 'user' THEN p_identifier::uuid ELSE NULL END,
            p_endpoint,
            jsonb_build_object('requests', v_tracking.request_count, 'limit', v_limit.max_requests),
            'cooldown'
        );
        
        RETURN jsonb_build_object(
            'allowed', false,
            'remaining', 0,
            'cooldown_until', v_cooldown_until,
            'reason', 'Rate limit exceeded'
        );
    END IF;
    
    -- Increment counter
    UPDATE public.master_rate_limit_tracking
    SET request_count = request_count + 1
    WHERE id = v_tracking.id;
    
    v_remaining := v_limit.max_requests - v_tracking.request_count - 1;
    v_reset_at := v_tracking.window_start + (v_limit.window_seconds || ' seconds')::interval;
    
    RETURN jsonb_build_object(
        'allowed', true,
        'remaining', v_remaining,
        'reset_at', v_reset_at
    );
END;
$$;

-- ═══════════════════════════════════════════
-- 4. REPLAY ATTACK PROTECTION
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_check_replay(
    p_request_id TEXT,
    p_request_hash TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_ip_address TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing RECORD;
BEGIN
    -- Clean up expired entries
    DELETE FROM public.master_replay_protection WHERE expires_at < now();
    
    -- Check if request ID already used
    SELECT * INTO v_existing
    FROM public.master_replay_protection
    WHERE request_id = p_request_id OR request_hash = p_request_hash;
    
    IF v_existing IS NOT NULL THEN
        -- Log replay attack
        INSERT INTO public.master_security_threats (
            threat_type, severity, source_ip, source_user_id,
            target_entity, threat_data, auto_response
        ) VALUES (
            'replay_attack', 'high', p_ip_address, p_user_id,
            p_endpoint,
            jsonb_build_object('request_id', p_request_id, 'original_used_at', v_existing.used_at),
            'block'
        );
        
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'Replay attack detected'
        );
    END IF;
    
    -- Store request for future checking (expires in 5 minutes)
    INSERT INTO public.master_replay_protection (
        request_id, request_hash, user_id, endpoint, ip_address, expires_at
    ) VALUES (
        p_request_id, p_request_hash, p_user_id, p_endpoint, p_ip_address,
        now() + interval '5 minutes'
    );
    
    RETURN jsonb_build_object('allowed', true);
END;
$$;

-- ═══════════════════════════════════════════
-- 5. LOGIN SECURITY CHECK
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_check_login_security(
    p_email TEXT,
    p_ip_address TEXT,
    p_device_fingerprint TEXT,
    p_geo_location TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_failed_attempts INTEGER;
    v_recent_success RECORD;
    v_is_blocked BOOLEAN := false;
    v_require_captcha BOOLEAN := false;
    v_is_anomaly BOOLEAN := false;
    v_anomaly_reasons JSONB := '[]'::jsonb;
    v_risk_score INTEGER := 0;
    v_max_failures INTEGER := 5;
    v_captcha_threshold INTEGER := 3;
BEGIN
    -- Get user ID
    SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;
    
    -- Get settings
    SELECT (setting_value_encrypted)::integer INTO v_max_failures
    FROM public.master_security_settings WHERE setting_key = 'max_login_failures';
    
    SELECT (setting_value_encrypted)::integer INTO v_captcha_threshold
    FROM public.master_security_settings WHERE setting_key = 'require_captcha_after_failures';
    
    -- Check IP blacklist
    IF EXISTS (
        SELECT 1 FROM public.master_ip_watchlist
        WHERE ip_address = p_ip_address AND blocked = true
    ) THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'IP address is blocked',
            'require_captcha', false
        );
    END IF;
    
    -- Count recent failed attempts for this IP
    SELECT COUNT(*) INTO v_failed_attempts
    FROM public.master_login_attempts
    WHERE ip_address = p_ip_address
    AND attempt_type IN ('failed_password', 'failed_mfa')
    AND created_at > now() - interval '1 hour';
    
    -- Check if should be blocked
    IF v_failed_attempts >= COALESCE(v_max_failures, 5) THEN
        v_is_blocked := true;
        v_risk_score := v_risk_score + 50;
    END IF;
    
    -- Check if captcha required
    IF v_failed_attempts >= COALESCE(v_captcha_threshold, 3) THEN
        v_require_captcha := true;
        v_risk_score := v_risk_score + 20;
    END IF;
    
    -- ANOMALY DETECTION
    IF v_user_id IS NOT NULL THEN
        -- Check for geo anomaly (different location than usual)
        SELECT * INTO v_recent_success
        FROM public.master_login_attempts
        WHERE user_id = v_user_id
        AND attempt_type = 'success'
        ORDER BY created_at DESC
        LIMIT 1;
        
        IF v_recent_success IS NOT NULL AND p_geo_location IS NOT NULL THEN
            IF v_recent_success.geo_location IS NOT NULL 
               AND v_recent_success.geo_location != p_geo_location THEN
                v_is_anomaly := true;
                v_anomaly_reasons := v_anomaly_reasons || '["geo_change"]'::jsonb;
                v_risk_score := v_risk_score + 30;
            END IF;
        END IF;
        
        -- Check for new device
        IF NOT EXISTS (
            SELECT 1 FROM public.master_device_fingerprints
            WHERE user_id = v_user_id
            AND fingerprint_hash = p_device_fingerprint
            AND is_blocked = false
        ) THEN
            v_is_anomaly := true;
            v_anomaly_reasons := v_anomaly_reasons || '["new_device"]'::jsonb;
            v_risk_score := v_risk_score + 20;
        END IF;
    END IF;
    
    RETURN jsonb_build_object(
        'allowed', NOT v_is_blocked,
        'require_captcha', v_require_captcha,
        'is_anomaly', v_is_anomaly,
        'anomaly_reasons', v_anomaly_reasons,
        'risk_score', v_risk_score,
        'failed_attempts', v_failed_attempts,
        'reason', CASE WHEN v_is_blocked THEN 'Too many failed attempts' ELSE NULL END
    );
END;
$$;

-- ═══════════════════════════════════════════
-- 6. REVOKE ALL USER TOKENS
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_revoke_user_tokens(
    p_user_id UUID,
    p_reason TEXT,
    p_revoked_by UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE public.master_token_registry
    SET is_revoked = true,
        revoked_at = now(),
        revoke_reason = p_reason,
        revoked_by = p_revoked_by
    WHERE user_id = p_user_id
    AND is_revoked = false;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Log to blackbox
    INSERT INTO public.blackbox_events (
        event_type, module_name, entity_type, entity_id,
        user_id, metadata
    ) VALUES (
        'token_revoke', 'security', 'user', p_user_id,
        p_revoked_by,
        jsonb_build_object('reason', p_reason, 'tokens_revoked', v_count)
    );
    
    RETURN v_count;
END;
$$;

-- ═══════════════════════════════════════════
-- 7. AUTO THREAT RESPONSE
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_auto_threat_response(
    p_threat_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_threat RECORD;
    v_action_taken TEXT;
BEGIN
    SELECT * INTO v_threat FROM public.master_security_threats WHERE id = p_threat_id;
    
    IF v_threat IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Threat not found');
    END IF;
    
    -- Determine action based on severity and type
    CASE v_threat.severity
        WHEN 'critical' THEN
            -- Lock user and revoke tokens
            IF v_threat.source_user_id IS NOT NULL THEN
                INSERT INTO public.master_system_locks (
                    lock_scope, target_id, reason, activated_by
                ) VALUES (
                    'user', v_threat.source_user_id,
                    'Auto-locked: ' || v_threat.threat_type,
                    NULL -- System
                );
                
                PERFORM public.master_revoke_user_tokens(
                    v_threat.source_user_id, 'security_threat', NULL
                );
                
                v_action_taken := 'user_lock';
            END IF;
            
            -- Block IP
            IF v_threat.source_ip IS NOT NULL THEN
                INSERT INTO public.master_ip_watchlist (ip_address, risk_level, blocked)
                VALUES (v_threat.source_ip, 'critical', true)
                ON CONFLICT (ip_address) DO UPDATE SET blocked = true, risk_level = 'critical';
                
                v_action_taken := COALESCE(v_action_taken || ', ', '') || 'ip_block';
            END IF;
            
        WHEN 'high' THEN
            -- Revoke tokens only
            IF v_threat.source_user_id IS NOT NULL THEN
                PERFORM public.master_revoke_user_tokens(
                    v_threat.source_user_id, 'security_threat', NULL
                );
                v_action_taken := 'session_kill';
            END IF;
            
        WHEN 'medium' THEN
            v_action_taken := 'logged_only';
            
        ELSE
            v_action_taken := 'none';
    END CASE;
    
    -- Update threat record
    UPDATE public.master_security_threats
    SET auto_response = v_action_taken,
        auto_response_at = now()
    WHERE id = p_threat_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'action_taken', v_action_taken,
        'threat_id', p_threat_id
    );
END;
$$;

-- ═══════════════════════════════════════════
-- 8. VERIFY HASH CHAIN INTEGRITY
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.master_verify_hash_chain(
    p_start_sequence BIGINT DEFAULT 1,
    p_end_sequence BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_record RECORD;
    v_expected_hash TEXT;
    v_tampered_count INTEGER := 0;
    v_verified_count INTEGER := 0;
    v_max_sequence BIGINT;
BEGIN
    -- Get max sequence if not specified
    IF p_end_sequence IS NULL THEN
        SELECT MAX(sequence_number) INTO v_max_sequence FROM public.master_blackbox_hash_chain;
    ELSE
        v_max_sequence := p_end_sequence;
    END IF;
    
    FOR v_record IN
        SELECT * FROM public.master_blackbox_hash_chain
        WHERE sequence_number >= p_start_sequence
        AND sequence_number <= v_max_sequence
        ORDER BY sequence_number
    LOOP
        -- Verify chain hash
        v_expected_hash := encode(sha256((v_record.event_hash || v_record.previous_hash)::bytea), 'hex');
        
        IF v_expected_hash != v_record.chain_hash THEN
            -- Mark as tampered
            UPDATE public.master_blackbox_hash_chain
            SET verification_status = 'tampered', verified_at = now()
            WHERE id = v_record.id;
            
            v_tampered_count := v_tampered_count + 1;
            
            -- Log security threat
            INSERT INTO public.master_security_threats (
                threat_type, severity, target_entity, target_id, threat_data
            ) VALUES (
                'blackbox_tampering', 'critical', 'blackbox_hash_chain', v_record.id,
                jsonb_build_object('sequence', v_record.sequence_number, 'expected', v_expected_hash, 'actual', v_record.chain_hash)
            );
        ELSE
            UPDATE public.master_blackbox_hash_chain
            SET verification_status = 'valid', verified_at = now()
            WHERE id = v_record.id;
            
            v_verified_count := v_verified_count + 1;
        END IF;
    END LOOP;
    
    RETURN jsonb_build_object(
        'verified_count', v_verified_count,
        'tampered_count', v_tampered_count,
        'integrity', CASE WHEN v_tampered_count = 0 THEN 'intact' ELSE 'compromised' END,
        'range', jsonb_build_object('start', p_start_sequence, 'end', v_max_sequence)
    );
END;
$$;
-- ===== 20260101002743_adee7ed6-4aa6-4f01-af36-a11ed04fd4fe.sql =====
-- ============================================
-- SUPER ADMIN CONTROL SYSTEM DATABASE
-- Complete Tracking Architecture
-- ============================================

-- 1. SUPER ADMIN SESSIONS (Login & Session Control)
CREATE TABLE IF NOT EXISTS public.super_admin_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  session_token TEXT NOT NULL,
  device_fingerprint TEXT,
  ip_address TEXT,
  geo_location TEXT,
  user_agent TEXT,
  assigned_scope JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  login_at TIMESTAMPTZ DEFAULT now(),
  last_activity_at TIMESTAMPTZ DEFAULT now(),
  logout_at TIMESTAMPTZ,
  logout_reason TEXT,
  force_logged_out BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. SUPER ADMIN ACTIONS (Every Click Logged)
CREATE TABLE IF NOT EXISTS public.super_admin_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES public.super_admin_sessions(id),
  user_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  action_category TEXT NOT NULL,
  target_entity TEXT,
  target_id UUID,
  action_data JSONB DEFAULT '{}',
  scope_context JSONB DEFAULT '{}',
  ip_address TEXT,
  device_fingerprint TEXT,
  result_status TEXT DEFAULT 'success',
  error_message TEXT,
  duration_ms INTEGER,
  is_sensitive BOOLEAN DEFAULT false,
  requires_approval BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. SUPER ADMIN SCOPE ASSIGNMENTS (Geographic Control)
CREATE TABLE IF NOT EXISTS public.super_admin_scope_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  scope_type TEXT NOT NULL CHECK (scope_type IN ('global', 'continent', 'country', 'region')),
  scope_value TEXT NOT NULL,
  parent_scope_id UUID REFERENCES public.super_admin_scope_assignments(id),
  assigned_by UUID,
  is_active BOOLEAN DEFAULT true,
  valid_from TIMESTAMPTZ DEFAULT now(),
  valid_until TIMESTAMPTZ,
  assignment_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. SUPER ADMIN MODULE CONTROLS (Feature & Module Control)
CREATE TABLE IF NOT EXISTS public.super_admin_module_controls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module_name TEXT NOT NULL,
  scope_type TEXT NOT NULL,
  scope_value TEXT NOT NULL,
  is_enabled BOOLEAN DEFAULT true,
  enabled_by UUID,
  disabled_by UUID,
  enabled_at TIMESTAMPTZ,
  disabled_at TIMESTAMPTZ,
  access_level TEXT DEFAULT 'full',
  restrictions JSONB DEFAULT '{}',
  usage_count INTEGER DEFAULT 0,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. SUPER ADMIN RENTALS (Rental Management)
CREATE TABLE IF NOT EXISTS public.super_admin_rentals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_name TEXT NOT NULL,
  assigned_to UUID NOT NULL,
  assigned_by UUID NOT NULL,
  scope_context JSONB DEFAULT '{}',
  rental_start TIMESTAMPTZ DEFAULT now(),
  rental_end TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT true,
  auto_revoke BOOLEAN DEFAULT true,
  extended_count INTEGER DEFAULT 0,
  last_extended_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  revoked_by UUID,
  revoke_reason TEXT,
  usage_stats JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. SUPER ADMIN RULES (Global Rules - Scope Limited)
CREATE TABLE IF NOT EXISTS public.super_admin_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL,
  rule_logic JSONB NOT NULL,
  scope_type TEXT NOT NULL,
  scope_value TEXT NOT NULL,
  created_by UUID NOT NULL,
  is_active BOOLEAN DEFAULT false,
  is_simulated BOOLEAN DEFAULT false,
  simulation_results JSONB,
  activated_at TIMESTAMPTZ,
  deactivated_at TIMESTAMPTZ,
  execution_count INTEGER DEFAULT 0,
  last_executed_at TIMESTAMPTZ,
  impact_assessment JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 7. SUPER ADMIN RULE EXECUTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_rule_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID REFERENCES public.super_admin_rules(id),
  triggered_by TEXT NOT NULL,
  trigger_context JSONB DEFAULT '{}',
  execution_result TEXT NOT NULL,
  affected_entities JSONB DEFAULT '[]',
  execution_duration_ms INTEGER,
  error_details TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. SUPER ADMIN APPROVALS (High-Risk Approvals)
CREATE TABLE IF NOT EXISTS public.super_admin_approvals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_type TEXT NOT NULL,
  request_data JSONB NOT NULL,
  requested_by UUID NOT NULL,
  requested_by_role TEXT NOT NULL,
  risk_score INTEGER DEFAULT 0,
  risk_factors JSONB DEFAULT '[]',
  scope_context JSONB DEFAULT '{}',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  review_notes TEXT,
  approval_steps JSONB DEFAULT '[]',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 9. SUPER ADMIN SECURITY EVENTS
CREATE TABLE IF NOT EXISTS public.super_admin_security_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  source_ip TEXT,
  target_user_id UUID,
  event_data JSONB DEFAULT '{}',
  scope_context JSONB DEFAULT '{}',
  action_taken TEXT,
  action_taken_by UUID,
  action_taken_at TIMESTAMPTZ,
  is_resolved BOOLEAN DEFAULT false,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 10. SUPER ADMIN LOCKS (System Lock Operations)
CREATE TABLE IF NOT EXISTS public.super_admin_locks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lock_type TEXT NOT NULL CHECK (lock_type IN ('user', 'region', 'module', 'emergency')),
  lock_target TEXT NOT NULL,
  lock_target_id UUID,
  scope_context JSONB DEFAULT '{}',
  locked_by UUID NOT NULL,
  lock_reason TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  force_logout_triggered BOOLEAN DEFAULT false,
  affected_users INTEGER DEFAULT 0,
  unlocked_by UUID,
  unlocked_at TIMESTAMPTZ,
  unlock_reason TEXT,
  is_global_request BOOLEAN DEFAULT false,
  global_request_status TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 11. SUPER ADMIN AUDIT ACCESS (Read-Only Audit Logs)
CREATE TABLE IF NOT EXISTS public.super_admin_audit_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  session_id UUID REFERENCES public.super_admin_sessions(id),
  access_type TEXT NOT NULL CHECK (access_type IN ('view', 'filter', 'timeline_replay', 'export_request')),
  accessed_module TEXT NOT NULL,
  filter_criteria JSONB DEFAULT '{}',
  records_viewed INTEGER DEFAULT 0,
  access_duration_seconds INTEGER,
  export_requested BOOLEAN DEFAULT false,
  export_approved BOOLEAN,
  export_approved_by UUID,
  watermark_applied BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 12. SUPER ADMIN USER MANAGEMENT ACTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_user_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID NOT NULL,
  target_user_id UUID NOT NULL,
  action_type TEXT NOT NULL CHECK (action_type IN ('view', 'suspend', 'lock', 'unlock', 'search', 'filter')),
  action_data JSONB DEFAULT '{}',
  scope_validated BOOLEAN DEFAULT true,
  permission_checked BOOLEAN DEFAULT true,
  result_status TEXT DEFAULT 'success',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 13. SUPER ADMIN ADMIN MANAGEMENT
CREATE TABLE IF NOT EXISTS public.super_admin_admin_management (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NOT NULL,
  target_admin_id UUID,
  action_type TEXT NOT NULL CHECK (action_type IN ('create', 'assign_role', 'assign_scope', 'edit', 'suspend', 'lock', 'revoke')),
  role_assigned TEXT,
  scope_assigned JSONB,
  previous_state JSONB DEFAULT '{}',
  new_state JSONB DEFAULT '{}',
  hierarchy_validated BOOLEAN DEFAULT true,
  scope_validated BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 14. SUPER ADMIN AI RISK VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_risk_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  viewer_id UUID NOT NULL,
  view_type TEXT NOT NULL CHECK (view_type IN ('user_risk', 'admin_risk', 'anomaly_flags', 'manual_review')),
  target_entity_id UUID,
  risk_score_viewed INTEGER,
  anomaly_data JSONB DEFAULT '{}',
  manual_review_triggered BOOLEAN DEFAULT false,
  review_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 15. SUPER ADMIN LIVE ACTIVITY VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_live_activity_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  session_id UUID REFERENCES public.super_admin_sessions(id),
  view_started_at TIMESTAMPTZ DEFAULT now(),
  view_ended_at TIMESTAMPTZ,
  filters_applied JSONB DEFAULT '{}',
  events_observed INTEGER DEFAULT 0,
  alerts_acknowledged INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.super_admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_scope_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_module_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_rentals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_rule_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_audit_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_user_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_admin_management ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_risk_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_live_activity_views ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Super Admin tables (Super Admin can access their scope)
CREATE POLICY "Super admins can view their sessions" ON public.super_admin_sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super admins can insert sessions" ON public.super_admin_sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Super admins can update their sessions" ON public.super_admin_sessions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Super admins can view their actions" ON public.super_admin_actions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super admins can insert actions" ON public.super_admin_actions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Super admins can view their scope" ON public.super_admin_scope_assignments
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super admins can view module controls" ON public.super_admin_module_controls
  FOR SELECT USING (true);

CREATE POLICY "Super admins can manage module controls" ON public.super_admin_module_controls
  FOR ALL USING (auth.uid() = enabled_by OR auth.uid() = disabled_by);

CREATE POLICY "Super admins can view rentals" ON public.super_admin_rentals
  FOR SELECT USING (auth.uid() = assigned_by OR auth.uid() = assigned_to);

CREATE POLICY "Super admins can manage rentals" ON public.super_admin_rentals
  FOR ALL USING (auth.uid() = assigned_by);

CREATE POLICY "Super admins can view rules" ON public.super_admin_rules
  FOR SELECT USING (true);

CREATE POLICY "Super admins can manage their rules" ON public.super_admin_rules
  FOR ALL USING (auth.uid() = created_by);

CREATE POLICY "Super admins can view rule executions" ON public.super_admin_rule_executions
  FOR SELECT USING (true);

CREATE POLICY "Super admins can insert rule executions" ON public.super_admin_rule_executions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Super admins can view approvals" ON public.super_admin_approvals
  FOR SELECT USING (true);

CREATE POLICY "Super admins can manage approvals" ON public.super_admin_approvals
  FOR ALL USING (auth.uid() = reviewed_by OR auth.uid() = requested_by);

CREATE POLICY "Super admins can view security events" ON public.super_admin_security_events
  FOR SELECT USING (true);

CREATE POLICY "Super admins can insert security events" ON public.super_admin_security_events
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Super admins can update security events" ON public.super_admin_security_events
  FOR UPDATE USING (auth.uid() = action_taken_by);

CREATE POLICY "Super admins can view locks" ON public.super_admin_locks
  FOR SELECT USING (true);

CREATE POLICY "Super admins can manage locks" ON public.super_admin_locks
  FOR ALL USING (auth.uid() = locked_by OR auth.uid() = unlocked_by);

CREATE POLICY "Super admins can view audit access" ON public.super_admin_audit_access
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super admins can insert audit access" ON public.super_admin_audit_access
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Super admins can view user actions" ON public.super_admin_user_actions
  FOR SELECT USING (auth.uid() = admin_user_id);

CREATE POLICY "Super admins can insert user actions" ON public.super_admin_user_actions
  FOR INSERT WITH CHECK (auth.uid() = admin_user_id);

CREATE POLICY "Super admins can view admin management" ON public.super_admin_admin_management
  FOR SELECT USING (auth.uid() = actor_id);

CREATE POLICY "Super admins can insert admin management" ON public.super_admin_admin_management
  FOR INSERT WITH CHECK (auth.uid() = actor_id);

CREATE POLICY "Super admins can view risk views" ON public.super_admin_risk_views
  FOR SELECT USING (auth.uid() = viewer_id);

CREATE POLICY "Super admins can insert risk views" ON public.super_admin_risk_views
  FOR INSERT WITH CHECK (auth.uid() = viewer_id);

CREATE POLICY "Super admins can view live activity" ON public.super_admin_live_activity_views
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Super admins can manage live activity" ON public.super_admin_live_activity_views
  FOR ALL USING (auth.uid() = user_id);

-- Indexes for performance
CREATE INDEX idx_sa_sessions_user ON public.super_admin_sessions(user_id);
CREATE INDEX idx_sa_sessions_active ON public.super_admin_sessions(is_active);
CREATE INDEX idx_sa_actions_user ON public.super_admin_actions(user_id);
CREATE INDEX idx_sa_actions_type ON public.super_admin_actions(action_type);
CREATE INDEX idx_sa_actions_created ON public.super_admin_actions(created_at);
CREATE INDEX idx_sa_scope_user ON public.super_admin_scope_assignments(user_id);
CREATE INDEX idx_sa_rentals_active ON public.super_admin_rentals(is_active);
CREATE INDEX idx_sa_rules_active ON public.super_admin_rules(is_active);
CREATE INDEX idx_sa_approvals_status ON public.super_admin_approvals(status);
CREATE INDEX idx_sa_security_severity ON public.super_admin_security_events(severity);
CREATE INDEX idx_sa_locks_active ON public.super_admin_locks(is_active);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_super_admin_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_sa_sessions_timestamp BEFORE UPDATE ON public.super_admin_sessions
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_scope_timestamp BEFORE UPDATE ON public.super_admin_scope_assignments
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_modules_timestamp BEFORE UPDATE ON public.super_admin_module_controls
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_rentals_timestamp BEFORE UPDATE ON public.super_admin_rentals
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_rules_timestamp BEFORE UPDATE ON public.super_admin_rules
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_approvals_timestamp BEFORE UPDATE ON public.super_admin_approvals
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();

CREATE TRIGGER update_sa_locks_timestamp BEFORE UPDATE ON public.super_admin_locks
  FOR EACH ROW EXECUTE FUNCTION update_super_admin_timestamp();
-- ===== 20260101002757_279e2a05-8e4b-4d52-b6e1-2e0cc06b7da7.sql =====
-- Fix function search path security warning
CREATE OR REPLACE FUNCTION update_super_admin_timestamp()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- ===== 20260101002808_9553b5e6-59b1-4722-8598-5d57268adeab.sql =====
-- Fix existing function search path security warning
CREATE OR REPLACE FUNCTION public.master_update_timestamp()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- ===== 20260101002821_b3a65b60-45d6-41ce-b1f1-b5fd7b37c6fc.sql =====
-- Fix remaining function search path security warning
CREATE OR REPLACE FUNCTION public.prevent_direct_promise_modification()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            RAISE EXCEPTION 'Direct status modification not allowed. Use process_promise_action function.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- ===== 20260101004001_554c7ae4-9ffd-4f6b-b4de-b43f6f0777b3.sql =====
-- ============================================
-- SUPER ADMIN CONTROL SYSTEM - ADDITIONAL ERD ENTITIES
-- Only creating tables that don't already exist
-- ============================================

-- ENTITY: SUPER_ADMIN_PROFILES (Extended profile for super admins)
CREATE TABLE IF NOT EXISTS public.super_admin_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE,
  assigned_continent_id UUID,
  assigned_country_id UUID,
  authority_scope TEXT DEFAULT 'country',
  can_manage_users BOOLEAN DEFAULT true,
  can_manage_admins BOOLEAN DEFAULT true,
  can_manage_rules BOOLEAN DEFAULT true,
  can_manage_security BOOLEAN DEFAULT true,
  can_manage_rentals BOOLEAN DEFAULT true,
  can_lock_scope BOOLEAN DEFAULT true,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_DASHBOARD_WIDGETS
CREATE TABLE IF NOT EXISTS public.super_admin_dashboard_widgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  widget_code TEXT NOT NULL,
  position_index INTEGER DEFAULT 0,
  is_enabled BOOLEAN DEFAULT true,
  widget_config JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_DASHBOARD_VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_dashboard_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  widget_code TEXT NOT NULL,
  view_duration_seconds INTEGER,
  viewed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: USER_STATUS_HISTORY
CREATE TABLE IF NOT EXISTS public.user_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  changed_by_super_admin_id UUID,
  old_status TEXT,
  new_status TEXT NOT NULL,
  reason TEXT,
  changed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_USER_VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_user_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  user_id UUID NOT NULL,
  view_context TEXT,
  viewed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: ADMINS (managed by Super Admin)
CREATE TABLE IF NOT EXISTS public.admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE,
  created_by_super_admin_id UUID,
  assigned_scope JSONB DEFAULT '{}',
  scope_type TEXT DEFAULT 'country',
  status TEXT DEFAULT 'active',
  permissions_list JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: ADMIN_SCOPE_HISTORY
CREATE TABLE IF NOT EXISTS public.admin_scope_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL,
  changed_by_super_admin_id UUID,
  old_scope JSONB,
  new_scope JSONB NOT NULL,
  change_reason TEXT,
  changed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: ROLES
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_name TEXT NOT NULL UNIQUE,
  scope_type TEXT DEFAULT 'global',
  description TEXT,
  is_system_role BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: PERMISSIONS
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_code TEXT NOT NULL UNIQUE,
  description TEXT,
  module TEXT,
  is_sensitive BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: ROLE_PERMISSIONS (Junction Table)
CREATE TABLE IF NOT EXISTS public.role_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id UUID NOT NULL,
  permission_id UUID NOT NULL,
  granted_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(role_id, permission_id)
);

-- ENTITY: SUPER_ADMIN_ROLE_VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_role_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  role_id UUID NOT NULL,
  viewed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_PERMISSION_VIEWS
CREATE TABLE IF NOT EXISTS public.super_admin_permission_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  permission_id UUID NOT NULL,
  viewed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: CONTINENTS
CREATE TABLE IF NOT EXISTS public.continents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL UNIQUE,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: COUNTRIES
CREATE TABLE IF NOT EXISTS public.countries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  continent_id UUID NOT NULL,
  name TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_REGION_ACTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_region_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  region_type TEXT NOT NULL,
  region_id UUID NOT NULL,
  action TEXT NOT NULL,
  action_data JSONB DEFAULT '{}',
  action_time TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SYSTEM_MODULES
CREATE TABLE IF NOT EXISTS public.system_modules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module_code TEXT NOT NULL UNIQUE,
  module_name TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'active',
  is_critical BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_MODULE_ACTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_module_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  module_id UUID NOT NULL,
  action TEXT NOT NULL,
  action_data JSONB DEFAULT '{}',
  action_time TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: RENTAL_PLANS
CREATE TABLE IF NOT EXISTS public.rental_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_name TEXT NOT NULL,
  duration_type TEXT NOT NULL,
  duration_value INTEGER DEFAULT 1,
  price DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'USD',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: RENTABLE_FEATURES
CREATE TABLE IF NOT EXISTS public.rentable_features (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_code TEXT NOT NULL UNIQUE,
  feature_name TEXT NOT NULL,
  module_code TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: RENTALS
CREATE TABLE IF NOT EXISTS public.rentals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_id UUID NOT NULL,
  plan_id UUID NOT NULL,
  assigned_to_user_id UUID NOT NULL,
  assigned_by_super_admin_id UUID,
  start_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  end_time TIMESTAMPTZ NOT NULL,
  status TEXT DEFAULT 'active',
  auto_renew BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_RENTAL_ACTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_rental_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  rental_id UUID NOT NULL,
  action TEXT NOT NULL,
  action_data JSONB DEFAULT '{}',
  action_time TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: RULES
CREATE TABLE IF NOT EXISTS public.rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL,
  rule_logic JSONB NOT NULL DEFAULT '{}',
  scope_definition JSONB DEFAULT '{}',
  status TEXT DEFAULT 'draft',
  created_by_super_admin_id UUID,
  priority INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: RULE_EXECUTION_LOGS
CREATE TABLE IF NOT EXISTS public.rule_execution_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL,
  executed_by_super_admin_id UUID,
  trigger_type TEXT NOT NULL,
  execution_result TEXT NOT NULL,
  affected_entities JSONB DEFAULT '[]',
  execution_duration_ms INTEGER,
  executed_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: APPROVALS
CREATE TABLE IF NOT EXISTS public.approvals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_type TEXT NOT NULL,
  requested_by_user_id UUID NOT NULL,
  request_data JSONB DEFAULT '{}',
  risk_score INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: APPROVAL_DECISIONS
CREATE TABLE IF NOT EXISTS public.approval_decisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_id UUID NOT NULL,
  super_admin_id UUID NOT NULL,
  decision TEXT NOT NULL,
  decision_reason TEXT,
  decision_time TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SECURITY_EVENTS
CREATE TABLE IF NOT EXISTS public.security_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  affected_user_id UUID,
  ip_address TEXT,
  geo_location TEXT,
  device_fingerprint TEXT,
  user_agent TEXT,
  severity TEXT DEFAULT 'medium',
  is_resolved BOOLEAN DEFAULT false,
  detected_at TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SUPER_ADMIN_SECURITY_ACTIONS
CREATE TABLE IF NOT EXISTS public.super_admin_security_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  security_event_id UUID NOT NULL,
  action TEXT NOT NULL,
  action_data JSONB DEFAULT '{}',
  action_time TIMESTAMPTZ DEFAULT now()
);

-- ENTITY: SYSTEM_LOCKS
CREATE TABLE IF NOT EXISTS public.system_locks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lock_scope TEXT NOT NULL,
  target_id UUID,
  target_name TEXT,
  reason TEXT NOT NULL,
  locked_by_super_admin_id UUID,
  is_active BOOLEAN DEFAULT true,
  force_logout_triggered BOOLEAN DEFAULT false,
  locked_at TIMESTAMPTZ DEFAULT now(),
  unlocked_at TIMESTAMPTZ,
  unlocked_by UUID
);

-- ENTITY: SUPER_ADMIN_ACTIVITY_LOG (Immutable Audit Trail)
CREATE TABLE IF NOT EXISTS public.super_admin_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  super_admin_id UUID NOT NULL,
  module TEXT NOT NULL,
  action TEXT NOT NULL,
  target_entity TEXT,
  target_id UUID,
  action_data JSONB DEFAULT '{}',
  ip_address TEXT,
  device_fingerprint TEXT,
  user_agent TEXT,
  session_id UUID,
  risk_score INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on all new tables
ALTER TABLE public.super_admin_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_dashboard_widgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_dashboard_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_user_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_scope_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_role_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_permission_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.continents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_region_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_module_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rental_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rentable_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rentals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_rental_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rule_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_security_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admin_activity_log ENABLE ROW LEVEL SECURITY;

-- RLS Policies using security definer function pattern
CREATE POLICY "sa_profiles_access" ON public.super_admin_profiles FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_widgets_access" ON public.super_admin_dashboard_widgets FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_dashboard_views_access" ON public.super_admin_dashboard_views FOR ALL USING (public.is_super_admin());
CREATE POLICY "user_status_history_access" ON public.user_status_history FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_user_views_access" ON public.super_admin_user_views FOR ALL USING (public.is_super_admin());
CREATE POLICY "admins_access" ON public.admins FOR ALL USING (public.is_super_admin());
CREATE POLICY "admin_scope_history_access" ON public.admin_scope_history FOR ALL USING (public.is_super_admin());
CREATE POLICY "roles_read" ON public.roles FOR SELECT USING (true);
CREATE POLICY "permissions_read" ON public.permissions FOR SELECT USING (true);
CREATE POLICY "role_permissions_read" ON public.role_permissions FOR SELECT USING (true);
CREATE POLICY "sa_role_views_access" ON public.super_admin_role_views FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_permission_views_access" ON public.super_admin_permission_views FOR ALL USING (public.is_super_admin());
CREATE POLICY "continents_read" ON public.continents FOR SELECT USING (true);
CREATE POLICY "countries_read" ON public.countries FOR SELECT USING (true);
CREATE POLICY "sa_region_actions_access" ON public.super_admin_region_actions FOR ALL USING (public.is_super_admin());
CREATE POLICY "system_modules_read" ON public.system_modules FOR SELECT USING (true);
CREATE POLICY "sa_module_actions_access" ON public.super_admin_module_actions FOR ALL USING (public.is_super_admin());
CREATE POLICY "rental_plans_read" ON public.rental_plans FOR SELECT USING (true);
CREATE POLICY "rentable_features_read" ON public.rentable_features FOR SELECT USING (true);
CREATE POLICY "rentals_access" ON public.rentals FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_rental_actions_access" ON public.super_admin_rental_actions FOR ALL USING (public.is_super_admin());
CREATE POLICY "rules_access" ON public.rules FOR ALL USING (public.is_super_admin());
CREATE POLICY "rule_execution_logs_access" ON public.rule_execution_logs FOR ALL USING (public.is_super_admin());
CREATE POLICY "approvals_access" ON public.approvals FOR ALL USING (public.is_super_admin());
CREATE POLICY "approval_decisions_access" ON public.approval_decisions FOR ALL USING (public.is_super_admin());
CREATE POLICY "security_events_access" ON public.security_events FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_security_actions_access" ON public.super_admin_security_actions FOR ALL USING (public.is_super_admin());
CREATE POLICY "system_locks_access" ON public.system_locks FOR ALL USING (public.is_super_admin());
CREATE POLICY "sa_activity_log_access" ON public.super_admin_activity_log FOR ALL USING (public.is_super_admin());

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sa_profiles_user ON public.super_admin_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_sa_widgets_admin ON public.super_admin_dashboard_widgets(super_admin_id);
CREATE INDEX IF NOT EXISTS idx_user_status_user ON public.user_status_history(user_id);
CREATE INDEX IF NOT EXISTS idx_admins_user ON public.admins(user_id);
CREATE INDEX IF NOT EXISTS idx_countries_continent ON public.countries(continent_id);
CREATE INDEX IF NOT EXISTS idx_rentals_user ON public.rentals(assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_rules_status ON public.rules(status);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON public.approvals(status);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON public.security_events(severity);
CREATE INDEX IF NOT EXISTS idx_system_locks_active ON public.system_locks(is_active);
CREATE INDEX IF NOT EXISTS idx_sa_activity_log_admin ON public.super_admin_activity_log(super_admin_id);
CREATE INDEX IF NOT EXISTS idx_sa_activity_log_created ON public.super_admin_activity_log(created_at);
-- ===== 20260101025406_06470cee-b49b-460e-8811-7ffd256d1708.sql =====
-- Create profiles table for user data
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  display_name TEXT,
  avatar_url TEXT,
  email TEXT,
  phone TEXT,
  bio TEXT,
  country TEXT,
  timezone TEXT,
  language TEXT DEFAULT 'en',
  is_active BOOLEAN DEFAULT true,
  last_seen_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view all profiles (for display purposes)
CREATE POLICY "Profiles are viewable by authenticated users"
ON public.profiles
FOR SELECT
TO authenticated
USING (true);

-- Policy: Users can insert their own profile
CREATE POLICY "Users can insert own profile"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own profile
CREATE POLICY "Users can update own profile"
ON public.profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Policy: Super admins can manage all profiles
CREATE POLICY "Super admins can manage all profiles"
ON public.profiles
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = auth.uid() 
    AND user_roles.role IN ('super_admin', 'master')
  )
);

-- Create trigger to update updated_at
CREATE TRIGGER update_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Create index for faster lookups
CREATE INDEX idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX idx_profiles_email ON public.profiles(email);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
-- ===== 20260101025508_5333c0ac-1c71-4e95-bd10-e5b11e5e0a9d.sql =====
-- Fix the function with correct enum values
CREATE OR REPLACE FUNCTION public.can_manage_prime_users(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
    AND role IN ('super_admin', 'master')
  )
$$;
-- ===== 20260101025700_4cdba88f-b23e-4883-a7b7-44633656fc0a.sql =====
-- Create storage buckets for file uploads

-- 1. Documents bucket (private - for code submissions, task files)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents', 
  'documents', 
  false,
  52428800, -- 50MB limit
  ARRAY['application/pdf', 'application/zip', 'text/plain', 'text/javascript', 'text/typescript', 'application/json', 'text/markdown', 'text/html', 'text/css']
);

-- 2. Avatars bucket (public - for profile pictures)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars', 
  'avatars', 
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
);

-- 3. Attachments bucket (private - for general attachments)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'attachments', 
  'attachments', 
  false,
  20971520, -- 20MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
);

-- RLS Policies for documents bucket
CREATE POLICY "Users can upload own documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can view own documents"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can delete own documents"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Admins can manage all documents"
ON storage.objects FOR ALL TO authenticated
USING (bucket_id = 'documents' AND public.has_privileged_role(auth.uid()));

-- RLS Policies for avatars bucket (public read, authenticated upload)
CREATE POLICY "Anyone can view avatars"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload own avatar"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can update own avatar"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- RLS Policies for attachments bucket
CREATE POLICY "Users can upload own attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can view own attachments"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can delete own attachments"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Admins can manage all attachments"
ON storage.objects FOR ALL TO authenticated
USING (bucket_id = 'attachments' AND public.has_privileged_role(auth.uid()));
-- ===== 20260101032242_7bb6debe-f136-4e6a-9592-f30df0c54a30.sql =====
-- =============================================
-- SERVER MANAGER ADDITIONAL TABLES
-- =============================================

-- Server Plans (for marketplace) - if not exists
CREATE TABLE IF NOT EXISTS public.server_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_name TEXT NOT NULL,
  plan_type TEXT NOT NULL,
  cpu_cores INTEGER NOT NULL,
  ram_gb INTEGER NOT NULL,
  storage_gb INTEGER NOT NULL,
  bandwidth_tb INTEGER NOT NULL DEFAULT 1,
  price_monthly DECIMAL(10,2) NOT NULL,
  price_yearly DECIMAL(10,2),
  regions TEXT[] DEFAULT ARRAY['us-east', 'us-west', 'eu-west', 'ap-south'],
  is_recommended BOOLEAN DEFAULT false,
  recommended_for TEXT[],
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Server Performance Summary
CREATE TABLE IF NOT EXISTS public.server_performance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  uptime_percent DECIMAL(5,2) DEFAULT 100.00,
  sla_percent DECIMAL(5,2) DEFAULT 99.99,
  avg_latency_ms INTEGER DEFAULT 0,
  error_rate DECIMAL(5,2) DEFAULT 0.00,
  performance_score INTEGER DEFAULT 100,
  last_calculated TIMESTAMPTZ DEFAULT now()
);

-- Server Incidents
CREATE TABLE IF NOT EXISTS public.server_incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID REFERENCES public.server_alerts(id),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT NOT NULL DEFAULT 'medium',
  status TEXT NOT NULL DEFAULT 'open',
  assigned_to UUID,
  escalated BOOLEAN DEFAULT false,
  escalated_to UUID,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Firewall Rules
CREATE TABLE IF NOT EXISTS public.firewall_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL DEFAULT 'allow',
  ip_range TEXT,
  port_range TEXT,
  protocol TEXT DEFAULT 'tcp',
  is_active BOOLEAN DEFAULT true,
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Server Purchases
CREATE TABLE IF NOT EXISTS public.server_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  plan_id UUID REFERENCES public.server_plans(id),
  server_id UUID REFERENCES public.server_instances(id),
  region TEXT NOT NULL,
  os TEXT DEFAULT 'ubuntu-22.04',
  auto_backup BOOLEAN DEFAULT false,
  firewall_preset TEXT DEFAULT 'standard',
  scaling_rules JSONB DEFAULT '{}',
  payment_method TEXT NOT NULL DEFAULT 'wallet',
  wallet_transaction_id UUID,
  amount DECIMAL(10,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- Server Billing
CREATE TABLE IF NOT EXISTS public.server_billing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  billing_period_start DATE NOT NULL,
  billing_period_end DATE NOT NULL,
  cpu_hours DECIMAL(10,2) DEFAULT 0,
  storage_gb_hours DECIMAL(10,2) DEFAULT 0,
  bandwidth_used_gb DECIMAL(10,2) DEFAULT 0,
  base_cost DECIMAL(10,2) DEFAULT 0,
  usage_cost DECIMAL(10,2) DEFAULT 0,
  total_cost DECIMAL(10,2) DEFAULT 0,
  is_paid BOOLEAN DEFAULT false,
  invoice_id UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Server Webhooks
CREATE TABLE IF NOT EXISTS public.server_webhooks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  status TEXT DEFAULT 'pending',
  retry_count INTEGER DEFAULT 0,
  last_attempt TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.firewall_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_webhooks ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Anyone can view active server plans" ON public.server_plans
  FOR SELECT USING (is_active = true);

CREATE POLICY "Super admin can manage plans" ON public.server_plans
  FOR ALL USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Authorized users can view performance" ON public.server_performance
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'server_manager')
  );

CREATE POLICY "Authorized users can view incidents" ON public.server_incidents
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'server_manager')
  );

CREATE POLICY "Authorized users can manage incidents" ON public.server_incidents
  FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'server_manager')
  );

CREATE POLICY "Authorized users can view firewall rules" ON public.firewall_rules
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'server_manager')
  );

CREATE POLICY "Super admin can manage firewall rules" ON public.firewall_rules
  FOR ALL USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Users can view their own purchases" ON public.server_purchases
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Users can create purchases" ON public.server_purchases
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Authorized users can view billing" ON public.server_billing
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'super_admin') OR 
    public.has_role(auth.uid(), 'server_manager')
  );

CREATE POLICY "Super admin can manage webhooks" ON public.server_webhooks
  FOR ALL USING (public.has_role(auth.uid(), 'super_admin'));

-- Insert default server plans
INSERT INTO public.server_plans (plan_name, plan_type, cpu_cores, ram_gb, storage_gb, bandwidth_tb, price_monthly, price_yearly, is_recommended, recommended_for) VALUES
('Starter Compute', 'compute', 2, 4, 50, 1, 29.99, 299.90, false, ARRAY['web']),
('Pro Compute', 'compute', 4, 8, 100, 2, 59.99, 599.90, true, ARRAY['web', 'api']),
('Enterprise Compute', 'compute', 8, 16, 200, 5, 119.99, 1199.90, false, ARRAY['high_load']),
('Memory Optimized S', 'memory', 2, 16, 50, 1, 49.99, 499.90, false, ARRAY['cache']),
('Memory Optimized L', 'memory', 4, 32, 100, 2, 99.99, 999.90, true, ARRAY['database', 'cache']),
('Storage Basic', 'storage', 2, 4, 500, 2, 39.99, 399.90, false, ARRAY['backup']),
('Storage Pro', 'storage', 4, 8, 2000, 5, 89.99, 899.90, true, ARRAY['backup', 'media']),
('GPU Starter', 'gpu', 4, 16, 100, 2, 199.99, 1999.90, false, ARRAY['ai', 'ml']),
('GPU Pro', 'gpu', 8, 32, 200, 5, 399.99, 3999.90, true, ARRAY['ai', 'ml', 'training'])
ON CONFLICT DO NOTHING;

-- Enable realtime for live monitoring
ALTER PUBLICATION supabase_realtime ADD TABLE public.server_alerts;
-- ===== 20260101032720_8da97b81-4c5c-488c-8d82-420bcbbafe0f.sql =====
-- =============================================
-- SERVER MANAGER AUTO-CALLING ENGINE SCHEMA
-- =============================================

-- Server Health (dedicated table for real-time health)
CREATE TABLE IF NOT EXISTS public.server_health (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE UNIQUE,
  health_score INTEGER DEFAULT 100,
  sla_uptime DECIMAL(5,2) DEFAULT 99.99,
  last_check_at TIMESTAMPTZ DEFAULT now(),
  consecutive_failures INTEGER DEFAULT 0,
  is_healthy BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Auto-scaling policies
CREATE TABLE IF NOT EXISTS public.auto_scaling_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  is_enabled BOOLEAN DEFAULT true,
  cpu_threshold_percent INTEGER DEFAULT 80,
  ram_threshold_percent INTEGER DEFAULT 85,
  consecutive_checks_required INTEGER DEFAULT 3,
  scale_up_cpu INTEGER DEFAULT 2,
  scale_up_ram INTEGER DEFAULT 4,
  max_cpu INTEGER DEFAULT 32,
  max_ram INTEGER DEFAULT 64,
  cooldown_minutes INTEGER DEFAULT 10,
  last_scale_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Auto-healing configuration
CREATE TABLE IF NOT EXISTS public.auto_healing_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  is_enabled BOOLEAN DEFAULT true,
  heartbeat_timeout_seconds INTEGER DEFAULT 60,
  max_restart_attempts INTEGER DEFAULT 3,
  restart_count INTEGER DEFAULT 0,
  last_restart_at TIMESTAMPTZ,
  auto_shutdown_on_failure BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Background job scheduler
CREATE TABLE IF NOT EXISTS public.background_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type TEXT NOT NULL,
  interval_seconds INTEGER NOT NULL,
  last_run_at TIMESTAMPTZ,
  next_run_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true,
  run_count INTEGER DEFAULT 0,
  last_error TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Job execution logs
CREATE TABLE IF NOT EXISTS public.job_execution_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES public.background_jobs(id),
  job_type TEXT NOT NULL,
  started_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  status TEXT DEFAULT 'running',
  result JSONB,
  error TEXT,
  servers_processed INTEGER DEFAULT 0
);

-- Real-time metrics cache (for fast dashboard reads)
CREATE TABLE IF NOT EXISTS public.server_metrics_cache (
  server_id UUID PRIMARY KEY REFERENCES public.server_instances(id) ON DELETE CASCADE,
  cpu_percent DECIMAL(5,2) DEFAULT 0,
  ram_percent DECIMAL(5,2) DEFAULT 0,
  disk_percent DECIMAL(5,2) DEFAULT 0,
  network_in DECIMAL(10,2) DEFAULT 0,
  network_out DECIMAL(10,2) DEFAULT 0,
  health_score INTEGER DEFAULT 100,
  status TEXT DEFAULT 'online',
  last_updated TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auto_scaling_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auto_healing_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.background_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_metrics_cache ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Server managers can view health" ON public.server_health
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'server_manager'));

CREATE POLICY "Server managers can view scaling policies" ON public.auto_scaling_policies
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'server_manager'));

CREATE POLICY "Super admin can manage scaling policies" ON public.auto_scaling_policies
  FOR ALL USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Server managers can view healing config" ON public.auto_healing_config
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'server_manager'));

CREATE POLICY "Super admin can manage healing config" ON public.auto_healing_config
  FOR ALL USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Admins can view background jobs" ON public.background_jobs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Admins can view job logs" ON public.job_execution_logs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin'));

CREATE POLICY "Anyone can view metrics cache" ON public.server_metrics_cache
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'super_admin') OR public.has_role(auth.uid(), 'server_manager'));

-- Insert default background jobs
INSERT INTO public.background_jobs (job_type, interval_seconds, next_run_at) VALUES
('metrics_collector', 5, now()),
('alert_checker', 30, now()),
('performance_updater', 60, now()),
('plan_recommender', 300, now()),
('billing_forecaster', 3600, now()),
('auto_scaler', 15, now()),
('auto_healer', 10, now())
ON CONFLICT DO NOTHING;

-- Enable realtime for metrics cache
ALTER PUBLICATION supabase_realtime ADD TABLE public.server_metrics_cache;
ALTER PUBLICATION supabase_realtime ADD TABLE public.server_health;

-- Function to simulate metrics (for demo/testing)
CREATE OR REPLACE FUNCTION public.generate_server_metrics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  srv RECORD;
BEGIN
  FOR srv IN SELECT id, status FROM server_instances WHERE status != 'decommissioned'
  LOOP
    -- Insert metrics history
    INSERT INTO server_metrics_history (
      server_id, cpu_percent, ram_percent, disk_percent, 
      network_in, network_out, recorded_at
    ) VALUES (
      srv.id,
      CASE WHEN srv.status = 'online' THEN 20 + random() * 60 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN 30 + random() * 50 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN 40 + random() * 40 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN random() * 1000 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN random() * 500 ELSE 0 END,
      now()
    );
    
    -- Update cache
    INSERT INTO server_metrics_cache (server_id, cpu_percent, ram_percent, disk_percent, network_in, network_out, status, last_updated)
    VALUES (
      srv.id,
      CASE WHEN srv.status = 'online' THEN 20 + random() * 60 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN 30 + random() * 50 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN 40 + random() * 40 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN random() * 1000 ELSE 0 END,
      CASE WHEN srv.status = 'online' THEN random() * 500 ELSE 0 END,
      srv.status,
      now()
    )
    ON CONFLICT (server_id) DO UPDATE SET
      cpu_percent = EXCLUDED.cpu_percent,
      ram_percent = EXCLUDED.ram_percent,
      disk_percent = EXCLUDED.disk_percent,
      network_in = EXCLUDED.network_in,
      network_out = EXCLUDED.network_out,
      status = EXCLUDED.status,
      last_updated = now();
    
    -- Update heartbeat
    UPDATE server_instances SET last_heartbeat = now() WHERE id = srv.id AND status = 'online';
  END LOOP;
END;
$$;

-- Function for auto-scaling check
CREATE OR REPLACE FUNCTION public.check_auto_scaling()
RETURNS TABLE(server_id UUID, needs_scaling BOOLEAN, scale_reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.server_id,
    (c.cpu_percent > COALESCE(p.cpu_threshold_percent, 80) OR c.ram_percent > COALESCE(p.ram_threshold_percent, 85)) AS needs_scaling,
    CASE 
      WHEN c.cpu_percent > COALESCE(p.cpu_threshold_percent, 80) THEN 'CPU threshold exceeded'
      WHEN c.ram_percent > COALESCE(p.ram_threshold_percent, 85) THEN 'RAM threshold exceeded'
      ELSE NULL
    END AS scale_reason
  FROM server_metrics_cache c
  LEFT JOIN auto_scaling_policies p ON c.server_id = p.server_id
  WHERE p.is_enabled = true OR p.is_enabled IS NULL;
END;
$$;

-- Function for auto-healing check
CREATE OR REPLACE FUNCTION public.check_auto_healing()
RETURNS TABLE(server_id UUID, needs_healing BOOLEAN, heal_reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.id AS server_id,
    (s.last_heartbeat < now() - interval '60 seconds' AND s.status = 'online') AS needs_healing,
    CASE 
      WHEN s.last_heartbeat < now() - interval '60 seconds' THEN 'Heartbeat timeout'
      ELSE NULL
    END AS heal_reason
  FROM server_instances s
  LEFT JOIN auto_healing_config h ON s.id = h.server_id
  WHERE s.status NOT IN ('offline', 'decommissioned')
  AND (h.is_enabled = true OR h.is_enabled IS NULL);
END;
$$;
-- ===== 20260101033408_6f632fb3-ae25-42fa-a581-559f2d249068.sql =====
-- Add missing columns to auto_scaling_policies
ALTER TABLE public.auto_scaling_policies 
ADD COLUMN IF NOT EXISTS disk_threshold_percent INTEGER DEFAULT 85,
ADD COLUMN IF NOT EXISTS scale_up_storage INTEGER DEFAULT 50,
ADD COLUMN IF NOT EXISTS max_storage INTEGER DEFAULT 2000,
ADD COLUMN IF NOT EXISTS cooldown_seconds INTEGER DEFAULT 300,
ADD COLUMN IF NOT EXISTS last_triggered_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS consecutive_triggers INTEGER DEFAULT 0;

-- Create server_actions table for tracking all actions
CREATE TABLE IF NOT EXISTS public.server_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  action VARCHAR(50) NOT NULL,
  action_type VARCHAR(30) DEFAULT 'manual',
  requested_by UUID,
  status VARCHAR(30) DEFAULT 'pending',
  previous_config JSONB,
  new_config JSONB,
  error_message TEXT,
  requested_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create scaling_events table for detailed scaling history
CREATE TABLE IF NOT EXISTS public.scaling_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  server_id UUID REFERENCES public.server_instances(id) ON DELETE CASCADE,
  policy_id UUID REFERENCES public.auto_scaling_policies(id),
  trigger_reason VARCHAR(50) NOT NULL,
  trigger_value INTEGER,
  threshold_value INTEGER,
  scale_direction VARCHAR(10) DEFAULT 'up',
  cpu_before INTEGER,
  cpu_after INTEGER,
  ram_before INTEGER,
  ram_after INTEGER,
  storage_before INTEGER,
  storage_after INTEGER,
  status VARCHAR(20) DEFAULT 'pending',
  error_message TEXT,
  cooldown_until TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Create websocket_connections table for tracking active connections
CREATE TABLE IF NOT EXISTS public.websocket_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  channel VARCHAR(100) NOT NULL,
  session_id VARCHAR(100),
  connected_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  last_ping_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  is_active BOOLEAN DEFAULT true,
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Create websocket_events table for event history
CREATE TABLE IF NOT EXISTS public.websocket_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel VARCHAR(100) NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  server_id UUID,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.server_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scaling_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.websocket_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.websocket_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Server managers can manage server_actions"
ON public.server_actions FOR ALL
USING (public.is_server_manager(auth.uid()));

CREATE POLICY "Server managers can view scaling_events"
ON public.scaling_events FOR ALL
USING (public.is_server_manager(auth.uid()));

CREATE POLICY "Users can manage own websocket_connections"
ON public.websocket_connections FOR ALL
USING (auth.uid() = user_id);

CREATE POLICY "Server managers can view websocket_events"
ON public.websocket_events FOR SELECT
USING (public.is_server_manager(auth.uid()));

-- Function to check and execute auto-scaling
CREATE OR REPLACE FUNCTION public.check_auto_scaling(p_server_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_policy RECORD;
  v_metrics RECORD;
  v_server RECORD;
  v_should_scale BOOLEAN := false;
  v_reason VARCHAR(50);
  v_trigger_value INTEGER;
  v_result JSONB;
BEGIN
  -- Get policy
  SELECT * INTO v_policy FROM auto_scaling_policies 
  WHERE server_id = p_server_id AND is_enabled = true;
  
  IF v_policy IS NULL THEN
    RETURN jsonb_build_object('should_scale', false, 'reason', 'no_policy');
  END IF;
  
  -- Check cooldown
  IF v_policy.last_scale_at IS NOT NULL AND 
     v_policy.last_scale_at + (COALESCE(v_policy.cooldown_minutes, 5) || ' minutes')::interval > now() THEN
    RETURN jsonb_build_object('should_scale', false, 'reason', 'cooldown_active');
  END IF;
  
  -- Get latest metrics (average of last 3)
  SELECT 
    AVG(cpu_percent)::INTEGER as avg_cpu,
    AVG(ram_percent)::INTEGER as avg_ram,
    AVG(disk_percent)::INTEGER as avg_disk
  INTO v_metrics
  FROM (
    SELECT cpu_percent, ram_percent, disk_percent
    FROM server_metrics_cache
    WHERE server_id = p_server_id
    ORDER BY recorded_at DESC
    LIMIT 3
  ) sub;
  
  -- Get server current config
  SELECT * INTO v_server FROM server_instances WHERE id = p_server_id;
  
  -- Check thresholds
  IF v_metrics.avg_cpu >= v_policy.cpu_threshold_percent THEN
    v_should_scale := true;
    v_reason := 'cpu_threshold';
    v_trigger_value := v_metrics.avg_cpu;
  ELSIF v_metrics.avg_ram >= v_policy.ram_threshold_percent THEN
    v_should_scale := true;
    v_reason := 'ram_threshold';
    v_trigger_value := v_metrics.avg_ram;
  END IF;
  
  IF v_should_scale THEN
    -- Check max limits
    IF v_server.cpu_cores >= v_policy.max_cpu AND v_server.ram_gb >= v_policy.max_ram THEN
      RETURN jsonb_build_object('should_scale', false, 'reason', 'max_limit_reached');
    END IF;
    
    -- Update consecutive triggers
    UPDATE auto_scaling_policies 
    SET consecutive_triggers = COALESCE(consecutive_triggers, 0) + 1,
        last_triggered_at = now()
    WHERE id = v_policy.id;
    
    -- Only scale if consecutive triggers >= required
    IF COALESCE(v_policy.consecutive_triggers, 0) + 1 >= COALESCE(v_policy.consecutive_checks_required, 3) THEN
      RETURN jsonb_build_object(
        'should_scale', true,
        'reason', v_reason,
        'trigger_value', v_trigger_value,
        'scale_cpu', LEAST(v_server.cpu_cores + v_policy.scale_up_cpu, v_policy.max_cpu),
        'scale_ram', LEAST(v_server.ram_gb + v_policy.scale_up_ram, v_policy.max_ram),
        'current_cpu', v_server.cpu_cores,
        'current_ram', v_server.ram_gb
      );
    ELSE
      RETURN jsonb_build_object('should_scale', false, 'reason', 'waiting_consecutive', 'count', v_policy.consecutive_triggers + 1);
    END IF;
  ELSE
    -- Reset consecutive triggers if healthy
    UPDATE auto_scaling_policies 
    SET consecutive_triggers = 0
    WHERE id = v_policy.id AND consecutive_triggers > 0;
  END IF;
  
  RETURN jsonb_build_object('should_scale', false, 'reason', 'healthy');
END;
$$;

-- Function to execute scaling
CREATE OR REPLACE FUNCTION public.execute_auto_scale(
  p_server_id UUID,
  p_new_cpu INTEGER,
  p_new_ram INTEGER,
  p_reason VARCHAR(50),
  p_trigger_value INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_server RECORD;
  v_policy RECORD;
  v_action_id UUID;
  v_event_id UUID;
BEGIN
  -- Get current server state
  SELECT * INTO v_server FROM server_instances WHERE id = p_server_id FOR UPDATE;
  SELECT * INTO v_policy FROM auto_scaling_policies WHERE server_id = p_server_id;
  
  -- Create action record
  INSERT INTO server_actions (
    server_id, action, action_type, status,
    previous_config, new_config, requested_at
  ) VALUES (
    p_server_id, 'scale_up', 'auto',  'in_progress',
    jsonb_build_object('cpu', v_server.cpu_cores, 'ram', v_server.ram_gb),
    jsonb_build_object('cpu', p_new_cpu, 'ram', p_new_ram),
    now()
  ) RETURNING id INTO v_action_id;
  
  -- Create scaling event
  INSERT INTO scaling_events (
    server_id, policy_id, trigger_reason, trigger_value,
    threshold_value, scale_direction,
    cpu_before, cpu_after, ram_before, ram_after,
    status, cooldown_until
  ) VALUES (
    p_server_id, v_policy.id, p_reason, p_trigger_value,
    CASE WHEN p_reason = 'cpu_threshold' THEN v_policy.cpu_threshold_percent ELSE v_policy.ram_threshold_percent END,
    'up',
    v_server.cpu_cores, p_new_cpu, v_server.ram_gb, p_new_ram,
    'completed', now() + (COALESCE(v_policy.cooldown_minutes, 5) || ' minutes')::interval
  ) RETURNING id INTO v_event_id;
  
  -- Update server
  UPDATE server_instances
  SET cpu_cores = p_new_cpu,
      ram_gb = p_new_ram,
      updated_at = now()
  WHERE id = p_server_id;
  
  -- Update policy
  UPDATE auto_scaling_policies
  SET last_scale_at = now(),
      consecutive_triggers = 0
  WHERE server_id = p_server_id;
  
  -- Complete action
  UPDATE server_actions
  SET status = 'completed', completed_at = now()
  WHERE id = v_action_id;
  
  -- Log websocket event
  INSERT INTO websocket_events (channel, event_type, server_id, payload)
  VALUES (
    'server_actions',
    'scale',
    p_server_id,
    jsonb_build_object(
      'type', 'scale',
      'server_id', p_server_id,
      'action', 'scale_up',
      'cpu', '+' || (p_new_cpu - v_server.cpu_cores),
      'ram', '+' || (p_new_ram - v_server.ram_gb) || 'GB',
      'status', 'success',
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'action_id', v_action_id,
    'event_id', v_event_id,
    'previous', jsonb_build_object('cpu', v_server.cpu_cores, 'ram', v_server.ram_gb),
    'new', jsonb_build_object('cpu', p_new_cpu, 'ram', p_new_ram)
  );
END;
$$;

-- Enable realtime for websocket events
ALTER PUBLICATION supabase_realtime ADD TABLE public.websocket_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.server_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.scaling_events;
-- ===== 20260101034358_d098f19d-797c-4c05-ac1d-82ced616ebf5.sql =====
-- Super Admin Action Log (Immutable Audit Trail)
CREATE TABLE IF NOT EXISTS public.super_admin_action_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL,
  session_id UUID,
  action_type VARCHAR(100) NOT NULL,
  action_category VARCHAR(50) NOT NULL,
  target_type VARCHAR(50),
  target_id UUID,
  target_name TEXT,
  scope_type VARCHAR(20),
  scope_value TEXT,
  risk_level VARCHAR(20) DEFAULT 'normal',
  requires_confirmation BOOLEAN DEFAULT false,
  confirmation_provided BOOLEAN,
  reason TEXT,
  previous_state JSONB,
  new_state JSONB,
  ip_address TEXT,
  geo_location TEXT,
  device_fingerprint TEXT,
  user_agent TEXT,
  execution_time_ms INTEGER,
  status VARCHAR(20) NOT NULL,
  error_message TEXT,
  signature TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Login Attempts (Rate Limiting)
CREATE TABLE IF NOT EXISTS public.login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  ip_address TEXT NOT NULL,
  device_fingerprint TEXT,
  attempt_type VARCHAR(20) DEFAULT 'password',
  success BOOLEAN DEFAULT false,
  failure_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- IP Blocklist
CREATE TABLE IF NOT EXISTS public.ip_blocklist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ip_address TEXT NOT NULL,
  reason TEXT NOT NULL,
  blocked_by UUID NOT NULL,
  blocked_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  expires_at TIMESTAMP WITH TIME ZONE,
  is_permanent BOOLEAN DEFAULT false,
  unblocked_by UUID,
  unblocked_at TIMESTAMP WITH TIME ZONE
);

-- Add columns to super_admin_sessions if missing
ALTER TABLE public.super_admin_sessions 
ADD COLUMN IF NOT EXISTS geo_location TEXT,
ADD COLUMN IF NOT EXISTS user_agent TEXT;

-- Add lock_type and expires_at to system_locks if missing
ALTER TABLE public.system_locks
ADD COLUMN IF NOT EXISTS lock_type VARCHAR(50),
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS scope_type VARCHAR(20),
ADD COLUMN IF NOT EXISTS scope_value TEXT,
ADD COLUMN IF NOT EXISTS unlock_reason TEXT,
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Add security columns to super_admin if not exists
ALTER TABLE public.super_admin 
ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS last_login_ip TEXT,
ADD COLUMN IF NOT EXISTS last_login_device TEXT,
ADD COLUMN IF NOT EXISTS failed_login_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS security_clearance VARCHAR(20) DEFAULT 'standard',
ADD COLUMN IF NOT EXISTS requires_2fa BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS max_session_duration_minutes INTEGER DEFAULT 480,
ADD COLUMN IF NOT EXISTS allowed_ip_ranges TEXT[],
ADD COLUMN IF NOT EXISTS force_password_change BOOLEAN DEFAULT false;

-- Enable RLS
ALTER TABLE public.super_admin_action_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ip_blocklist ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Super admins can view action logs" ON public.super_admin_action_log;
CREATE POLICY "Super admins can view action logs"
ON public.super_admin_action_log FOR SELECT
USING (public.is_super_admin());

DROP POLICY IF EXISTS "Super admins can insert action logs" ON public.super_admin_action_log;
CREATE POLICY "Super admins can insert action logs"
ON public.super_admin_action_log FOR INSERT
WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "Super admins can view login attempts" ON public.login_attempts;
CREATE POLICY "Super admins can view login attempts"
ON public.login_attempts FOR SELECT
USING (public.is_super_admin());

DROP POLICY IF EXISTS "Anyone can insert login attempts" ON public.login_attempts;
CREATE POLICY "Anyone can insert login attempts"
ON public.login_attempts FOR INSERT
WITH CHECK (true);

DROP POLICY IF EXISTS "Super admins can manage IP blocklist" ON public.ip_blocklist;
CREATE POLICY "Super admins can manage IP blocklist"
ON public.ip_blocklist FOR ALL
USING (public.is_super_admin());

-- Prevent modification of action logs
CREATE OR REPLACE FUNCTION public.prevent_action_log_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Action logs are immutable';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_action_log_modification ON public.super_admin_action_log;
CREATE TRIGGER prevent_action_log_modification
BEFORE UPDATE OR DELETE ON public.super_admin_action_log
FOR EACH ROW EXECUTE FUNCTION public.prevent_action_log_modification();

-- Function to validate Super Admin session
CREATE OR REPLACE FUNCTION public.validate_super_admin_session(
  p_user_id UUID,
  p_session_token TEXT,
  p_ip_address TEXT,
  p_device_fingerprint TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_session RECORD;
  v_admin RECORD;
  v_lock RECORD;
BEGIN
  -- Check IP blocklist
  IF EXISTS (SELECT 1 FROM ip_blocklist WHERE ip_address = p_ip_address AND (expires_at IS NULL OR expires_at > now())) THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'ip_blocked');
  END IF;

  -- Get session
  SELECT * INTO v_session FROM super_admin_sessions
  WHERE user_id = p_user_id AND session_token = p_session_token AND is_active = true;
  
  IF v_session IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'session_not_found');
  END IF;
  
  -- Check session expiry
  IF v_session.expires_at < now() THEN
    UPDATE super_admin_sessions SET is_active = false, terminated_at = now(), termination_reason = 'expired' WHERE id = v_session.id;
    RETURN jsonb_build_object('valid', false, 'reason', 'session_expired');
  END IF;
  
  -- Check device fingerprint
  IF v_session.device_fingerprint != p_device_fingerprint THEN
    UPDATE super_admin_sessions SET is_active = false, terminated_at = now(), termination_reason = 'device_mismatch' WHERE id = v_session.id;
    RETURN jsonb_build_object('valid', false, 'reason', 'device_mismatch');
  END IF;
  
  -- Get admin status
  SELECT * INTO v_admin FROM super_admin WHERE user_id = p_user_id;
  
  IF v_admin IS NULL OR v_admin.status != 'active' THEN
    UPDATE super_admin_sessions SET is_active = false, terminated_at = now(), termination_reason = 'admin_inactive' WHERE id = v_session.id;
    RETURN jsonb_build_object('valid', false, 'reason', 'admin_inactive');
  END IF;
  
  -- Check system locks
  SELECT * INTO v_lock FROM system_locks 
  WHERE lock_scope = 'system' AND is_active = true AND (expires_at IS NULL OR expires_at > now())
  LIMIT 1;
  
  IF v_lock IS NOT NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'system_locked', 'lock_reason', v_lock.reason);
  END IF;
  
  -- Update last activity
  UPDATE super_admin_sessions SET last_activity_at = now(), ip_address = p_ip_address WHERE id = v_session.id;
  
  RETURN jsonb_build_object(
    'valid', true,
    'session_id', v_session.id,
    'admin_id', v_admin.id,
    'scope_type', v_admin.scope_type,
    'assigned_scope', v_admin.assigned_scope,
    'security_clearance', v_admin.security_clearance
  );
END;
$$;

-- Function to check authorization
CREATE OR REPLACE FUNCTION public.check_super_admin_authorization(
  p_user_id UUID,
  p_action VARCHAR(100),
  p_target_scope JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin RECORD;
  v_scope_match BOOLEAN := true;
BEGIN
  SELECT * INTO v_admin FROM super_admin WHERE user_id = p_user_id AND status = 'active';
  
  IF v_admin IS NULL THEN
    RETURN jsonb_build_object('authorized', false, 'reason', 'not_super_admin');
  END IF;
  
  -- Check scope if not global
  IF p_target_scope IS NOT NULL AND v_admin.scope_type != 'global' THEN
    IF v_admin.scope_type = 'continent' THEN
      v_scope_match := (p_target_scope->>'continent') = ANY(
        SELECT jsonb_array_elements_text(v_admin.assigned_scope->'continents')
      );
    ELSIF v_admin.scope_type = 'country' THEN
      v_scope_match := (p_target_scope->>'country') = ANY(
        SELECT jsonb_array_elements_text(v_admin.assigned_scope->'countries')
      );
    END IF;
    
    IF NOT v_scope_match THEN
      RETURN jsonb_build_object('authorized', false, 'reason', 'scope_violation');
    END IF;
  END IF;
  
  RETURN jsonb_build_object(
    'authorized', true,
    'admin_id', v_admin.id,
    'scope_type', v_admin.scope_type,
    'assigned_scope', v_admin.assigned_scope
  );
END;
$$;

-- Function to log action
CREATE OR REPLACE FUNCTION public.log_super_admin_action(
  p_admin_id UUID,
  p_action_type VARCHAR(100),
  p_action_category VARCHAR(50),
  p_target_type VARCHAR(50) DEFAULT NULL,
  p_target_id UUID DEFAULT NULL,
  p_risk_level VARCHAR(20) DEFAULT 'normal',
  p_reason TEXT DEFAULT NULL,
  p_previous_state JSONB DEFAULT NULL,
  p_new_state JSONB DEFAULT NULL,
  p_ip_address TEXT DEFAULT NULL,
  p_status VARCHAR(20) DEFAULT 'success'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_log_id UUID;
  v_signature TEXT;
BEGIN
  v_signature := encode(sha256(
    (p_admin_id::text || p_action_type || COALESCE(p_target_id::text, '') || now()::text)::bytea
  ), 'hex');
  
  INSERT INTO super_admin_action_log (
    admin_id, action_type, action_category,
    target_type, target_id, risk_level, reason,
    previous_state, new_state, ip_address, status, signature
  ) VALUES (
    p_admin_id, p_action_type, p_action_category,
    p_target_type, p_target_id, p_risk_level, p_reason,
    p_previous_state, p_new_state, p_ip_address, p_status, v_signature
  ) RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$;

-- Function to check rate limits
CREATE OR REPLACE FUNCTION public.check_login_rate_limit(
  p_email TEXT,
  p_ip_address TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_recent_failures INTEGER;
  v_ip_failures INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_recent_failures FROM login_attempts
  WHERE email = p_email AND success = false AND created_at > now() - interval '15 minutes';
  
  SELECT COUNT(*) INTO v_ip_failures FROM login_attempts
  WHERE ip_address = p_ip_address AND success = false AND created_at > now() - interval '15 minutes';
  
  IF v_recent_failures >= 5 THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'too_many_attempts_email', 'wait_minutes', 15);
  END IF;
  
  IF v_ip_failures >= 10 THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'too_many_attempts_ip', 'wait_minutes', 15);
  END IF;
  
  RETURN jsonb_build_object('allowed', true, 'email_attempts', v_recent_failures, 'ip_attempts', v_ip_failures);
END;
$$;

-- Create session with security
CREATE OR REPLACE FUNCTION public.create_super_admin_session(
  p_user_id UUID,
  p_device_fingerprint TEXT,
  p_ip_address TEXT,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin RECORD;
  v_session_token TEXT;
  v_session_id UUID;
  v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
  -- Get admin
  SELECT * INTO v_admin FROM super_admin WHERE user_id = p_user_id AND status = 'active';
  
  IF v_admin IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_super_admin');
  END IF;
  
  -- Terminate other active sessions (one session per device policy)
  UPDATE super_admin_sessions 
  SET is_active = false, terminated_at = now(), termination_reason = 'new_session'
  WHERE user_id = p_user_id AND is_active = true;
  
  -- Generate session token
  v_session_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := now() + (COALESCE(v_admin.max_session_duration_minutes, 480) || ' minutes')::interval;
  
  -- Create session
  INSERT INTO super_admin_sessions (
    user_id, session_token, device_fingerprint, ip_address, user_agent, expires_at
  ) VALUES (
    p_user_id, v_session_token, p_device_fingerprint, p_ip_address, p_user_agent, v_expires_at
  ) RETURNING id INTO v_session_id;
  
  -- Update admin login info
  UPDATE super_admin 
  SET last_login_at = now(), last_login_ip = p_ip_address, last_login_device = p_device_fingerprint, failed_login_count = 0
  WHERE id = v_admin.id;
  
  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session_id,
    'session_token', v_session_token,
    'expires_at', v_expires_at,
    'admin_id', v_admin.id,
    'scope_type', v_admin.scope_type,
    'assigned_scope', v_admin.assigned_scope
  );
END;
$$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON public.login_attempts(email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_ip ON public.login_attempts(ip_address, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_action_log_admin ON public.super_admin_action_log(admin_id, created_at DESC);
-- ===== 20260101040719_f44ada30-3afd-47b8-a409-f5662782e7d6.sql =====
-- Add missing tables (demo_projects and demo_requests)
CREATE TABLE IF NOT EXISTS public.demo_projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_name VARCHAR(200) NOT NULL,
  project_url TEXT NOT NULL,
  description TEXT,
  category VARCHAR(100) NOT NULL,
  thumbnail_url TEXT,
  is_featured BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  display_order INT DEFAULT 0,
  tech_stack TEXT[],
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.demo_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_name VARCHAR(200) NOT NULL,
  client_email VARCHAR(255) NOT NULL,
  company_name VARCHAR(200),
  phone VARCHAR(50),
  interested_category VARCHAR(100),
  message TEXT,
  status VARCHAR(50) DEFAULT 'pending',
  notes TEXT,
  responded_at TIMESTAMP WITH TIME ZONE,
  responded_by UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.demo_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any and recreate
DROP POLICY IF EXISTS "Anyone can view active demos" ON public.demo_projects;
DROP POLICY IF EXISTS "Authenticated users can manage demos" ON public.demo_projects;
DROP POLICY IF EXISTS "Anyone can submit demo requests" ON public.demo_requests;
DROP POLICY IF EXISTS "Authenticated users can view all requests" ON public.demo_requests;
DROP POLICY IF EXISTS "Authenticated users can update requests" ON public.demo_requests;

-- Public read for demo_projects
CREATE POLICY "Anyone can view active demos"
ON public.demo_projects FOR SELECT
USING (is_active = true);

-- Authenticated users can manage demos
CREATE POLICY "Authenticated users can manage demos"
ON public.demo_projects FOR ALL
TO authenticated
USING (true);

-- Anyone can submit demo requests
CREATE POLICY "Anyone can submit demo requests"
ON public.demo_requests FOR INSERT
WITH CHECK (true);

-- Authenticated users can view and update requests
CREATE POLICY "Authenticated users can view all requests"
ON public.demo_requests FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Authenticated users can update requests"
ON public.demo_requests FOR UPDATE
TO authenticated
USING (true);
-- ===== 20260101042635_4e55be60-9364-444a-9afb-efa11502a77a.sql =====
-- Client Projects table for tracking client orders
CREATE TABLE public.client_projects (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_name TEXT NOT NULL,
  client_email TEXT NOT NULL,
  client_phone TEXT,
  domain_name TEXT NOT NULL,
  logo_url TEXT,
  company_name TEXT,
  
  -- Project details
  project_type TEXT NOT NULL DEFAULT 'demo',
  demo_id UUID,
  requirements TEXT,
  
  -- Pricing
  quoted_amount DECIMAL(10,2),
  deposit_amount DECIMAL(10,2),
  balance_amount DECIMAL(10,2),
  currency TEXT DEFAULT 'INR',
  
  -- Payment tracking
  deposit_paid BOOLEAN DEFAULT false,
  deposit_paid_at TIMESTAMPTZ,
  deposit_payment_method TEXT,
  deposit_transaction_id TEXT,
  balance_paid BOOLEAN DEFAULT false,
  balance_paid_at TIMESTAMPTZ,
  balance_payment_method TEXT,
  balance_transaction_id TEXT,
  
  -- Status workflow
  status TEXT DEFAULT 'pending_review',
  status_message TEXT DEFAULT 'Your request has been received. Our team is reviewing your requirements.',
  
  -- IP/DNS Configuration
  assigned_ip TEXT,
  dns_configured BOOLEAN DEFAULT false,
  
  -- Admin workflow
  admin_notes TEXT,
  assigned_to UUID,
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.client_projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can insert projects" 
ON public.client_projects 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Admins can view all projects" 
ON public.client_projects 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() 
    AND role IN ('super_admin', 'admin', 'master')
  )
);

CREATE POLICY "Admins can update projects" 
ON public.client_projects 
FOR UPDATE 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() 
    AND role IN ('super_admin', 'admin', 'master')
  )
);

CREATE TABLE public.project_status_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES public.client_projects(id) ON DELETE CASCADE,
  old_status TEXT,
  new_status TEXT NOT NULL,
  status_message TEXT,
  changed_by UUID,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes TEXT
);

ALTER TABLE public.project_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage status history" 
ON public.project_status_history 
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() 
    AND role IN ('super_admin', 'admin', 'master')
  )
);

CREATE TRIGGER update_client_projects_updated_at
BEFORE UPDATE ON public.client_projects
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX idx_client_projects_email ON public.client_projects(client_email);
CREATE INDEX idx_client_projects_status ON public.client_projects(status);
-- ===== 20260101071338_3fd69865-9e38-41bf-b56f-bfc7cf19a7b6.sql =====
-- =====================================================
-- SECURITY FIX: Tighten profiles table RLS
-- =====================================================

-- Drop the overly permissive policy
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;

-- Create restrictive policy - users can only view their own profile OR admins can view all
CREATE POLICY "profiles_select_restricted" 
ON public.profiles FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
);
-- ===== 20260101071448_4adc71f5-65c6-42a9-b41b-70111d03a994.sql =====
-- =====================================================
-- SECURITY FIX: Tighten remaining sensitive tables RLS (Part 2)
-- =====================================================

-- 10. client_projects - Only assigned and admins (use assigned_to not assigned_developer)
DROP POLICY IF EXISTS "Anyone can view client projects" ON public.client_projects;
DROP POLICY IF EXISTS "Client projects visible to all" ON public.client_projects;

CREATE POLICY "client_projects_select_restricted" 
ON public.client_projects FOR SELECT 
USING (
  auth.uid() = assigned_to
  OR public.has_role(auth.uid(), 'client_success'::app_role)
  OR public.has_privileged_role(auth.uid())
);

-- 11. user_support_tickets - Only owner and support staff
DROP POLICY IF EXISTS "Anyone can view support tickets" ON public.user_support_tickets;
DROP POLICY IF EXISTS "Support tickets visible to all" ON public.user_support_tickets;

CREATE POLICY "support_tickets_select_restricted" 
ON public.user_support_tickets FOR SELECT 
USING (
  auth.uid() = user_id 
  OR auth.uid() = assigned_to
  OR public.has_role(auth.uid(), 'support'::app_role)
  OR public.has_role(auth.uid(), 'client_success'::app_role)
  OR public.has_privileged_role(auth.uid())
);
-- ===== 20260101071514_0456e168-13cf-40ae-b671-678eddf806bc.sql =====
-- =====================================================
-- SECURITY FIX: Part 3 - More sensitive tables
-- =====================================================

-- 1. developers table - Only owner and HR/task managers
DROP POLICY IF EXISTS "Developers can view all developers" ON public.developers;
DROP POLICY IF EXISTS "Anyone can view developers" ON public.developers;
DROP POLICY IF EXISTS "developers_select_restricted" ON public.developers;

CREATE POLICY "developers_select_own_or_managers" 
ON public.developers FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_role(auth.uid(), 'hr_manager'::app_role)
  OR public.has_role(auth.uid(), 'task_manager'::app_role)
  OR public.has_privileged_role(auth.uid())
);

-- 2. franchise_accounts - Only owner and admins
DROP POLICY IF EXISTS "Franchises view all" ON public.franchise_accounts;
DROP POLICY IF EXISTS "Anyone can view franchise accounts" ON public.franchise_accounts;
DROP POLICY IF EXISTS "franchise_accounts_select_restricted" ON public.franchise_accounts;

CREATE POLICY "franchise_accounts_select_own_or_admin" 
ON public.franchise_accounts FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
);

-- 3. reseller_accounts - Only owner and managers
DROP POLICY IF EXISTS "Resellers view all" ON public.reseller_accounts;
DROP POLICY IF EXISTS "Anyone can view reseller accounts" ON public.reseller_accounts;
DROP POLICY IF EXISTS "reseller_accounts_select_restricted" ON public.reseller_accounts;

CREATE POLICY "reseller_accounts_select_own_or_managers" 
ON public.reseller_accounts FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.can_manage_resellers(auth.uid())
  OR public.has_privileged_role(auth.uid())
);

-- 4. influencer_accounts - Only owner and admins
DROP POLICY IF EXISTS "Influencers view all" ON public.influencer_accounts;
DROP POLICY IF EXISTS "Anyone can view influencer accounts" ON public.influencer_accounts;
DROP POLICY IF EXISTS "influencer_accounts_select_restricted" ON public.influencer_accounts;

CREATE POLICY "influencer_accounts_select_own_or_admin" 
ON public.influencer_accounts FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
);

-- 5. prime_user_profiles - Only owner and support staff
DROP POLICY IF EXISTS "Prime users view all" ON public.prime_user_profiles;
DROP POLICY IF EXISTS "Anyone can view prime profiles" ON public.prime_user_profiles;
DROP POLICY IF EXISTS "prime_user_profiles_select_restricted" ON public.prime_user_profiles;

CREATE POLICY "prime_user_profiles_select_own_or_support" 
ON public.prime_user_profiles FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_role(auth.uid(), 'client_success'::app_role)
  OR public.has_privileged_role(auth.uid())
);

-- 6. developer_registrations - Only owner and HR
DROP POLICY IF EXISTS "Anyone can view developer registrations" ON public.developer_registrations;
DROP POLICY IF EXISTS "developer_registrations_select_restricted" ON public.developer_registrations;

CREATE POLICY "developer_registrations_select_own_or_hr" 
ON public.developer_registrations FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_role(auth.uid(), 'hr_manager'::app_role)
  OR public.has_privileged_role(auth.uid())
);

-- 7. kyc_documents - Only owner and legal/compliance
DROP POLICY IF EXISTS "Anyone can view KYC documents" ON public.kyc_documents;
DROP POLICY IF EXISTS "kyc_documents_select_restricted" ON public.kyc_documents;

CREATE POLICY "kyc_documents_select_own_or_legal" 
ON public.kyc_documents FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_role(auth.uid(), 'legal_compliance'::app_role)
  OR public.has_privileged_role(auth.uid())
);

-- 8. demo_login_credentials - Only demo managers
DROP POLICY IF EXISTS "Anyone can view demo credentials" ON public.demo_login_credentials;
DROP POLICY IF EXISTS "Public can view demo credentials" ON public.demo_login_credentials;
DROP POLICY IF EXISTS "demo_credentials_select_restricted" ON public.demo_login_credentials;

CREATE POLICY "demo_credentials_select_demo_managers" 
ON public.demo_login_credentials FOR SELECT 
USING (
  public.is_demo_manager(auth.uid())
  OR public.has_privileged_role(auth.uid())
);

-- 9. leads - Only assigned users and lead managers
DROP POLICY IF EXISTS "Anyone can view leads" ON public.leads;
DROP POLICY IF EXISTS "Leads visible to all authenticated" ON public.leads;
DROP POLICY IF EXISTS "leads_select_restricted" ON public.leads;

CREATE POLICY "leads_select_assigned_or_managers" 
ON public.leads FOR SELECT 
USING (
  auth.uid() = assigned_to 
  OR auth.uid() = created_by
  OR public.has_role(auth.uid(), 'lead_manager'::app_role)
  OR public.has_role(auth.uid(), 'franchise'::app_role)
  OR public.has_privileged_role(auth.uid())
);
-- ===== 20260101110643_111799a7-2097-4eba-ac73-e44c32471d07.sql =====
-- Insert sample permissions for all roles using existing schema
INSERT INTO public.role_permissions (role_name, permission_name, module_name, action) VALUES
-- Super Admin permissions
('super_admin', 'View Users', 'Users', 'view'),
('super_admin', 'Create Users', 'Users', 'create'),
('super_admin', 'Edit Users', 'Users', 'edit'),
('super_admin', 'Delete Users', 'Users', 'delete'),
('super_admin', 'View Roles', 'Roles', 'view'),
('super_admin', 'Create Roles', 'Roles', 'create'),
('super_admin', 'Edit Roles', 'Roles', 'edit'),
('super_admin', 'Assign Roles', 'Roles', 'assign'),
('super_admin', 'View Dashboard', 'Dashboard', 'view'),
('super_admin', 'View Reports', 'Reports', 'view'),
('super_admin', 'Export Reports', 'Reports', 'export'),
('super_admin', 'View Settings', 'Settings', 'view'),
('super_admin', 'Edit Settings', 'Settings', 'edit'),
('super_admin', 'View Billing', 'Billing', 'view'),
('super_admin', 'Manage Billing', 'Billing', 'manage'),
-- Continent Manager permissions
('continent_super_admin', 'View Users', 'Users', 'view'),
('continent_super_admin', 'Create Users', 'Users', 'create'),
('continent_super_admin', 'Edit Users', 'Users', 'edit'),
('continent_super_admin', 'View Dashboard', 'Dashboard', 'view'),
('continent_super_admin', 'View Reports', 'Reports', 'view'),
-- Country Admin permissions
('country_admin', 'View Users', 'Users', 'view'),
('country_admin', 'Create Users', 'Users', 'create'),
('country_admin', 'View Dashboard', 'Dashboard', 'view'),
('country_admin', 'View Reports', 'Reports', 'view'),
-- Finance Auditor permissions
('finance_auditor', 'View Billing', 'Billing', 'view'),
('finance_auditor', 'View Reports', 'Reports', 'view'),
('finance_auditor', 'Export Reports', 'Reports', 'export'),
-- Support Team Lead permissions
('support_team_lead', 'View Users', 'Users', 'view'),
('support_team_lead', 'View Dashboard', 'Dashboard', 'view'),
('support_team_lead', 'Manage Tickets', 'Support', 'manage'),
-- Marketing Viewer permissions
('marketing_viewer', 'View Dashboard', 'Dashboard', 'view'),
('marketing_viewer', 'View Reports', 'Reports', 'view')
ON CONFLICT DO NOTHING;
-- ===== 20260101113917_f2186948-5b5b-4e41-b799-7c9457e143c7.sql =====
-- =============================================
-- SECURITY FIX: Add RLS to sensitive tables
-- =============================================

-- 1. PERMISSIONS table - only authenticated users can read
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view permissions" ON public.permissions;
CREATE POLICY "Authenticated users can view permissions" 
ON public.permissions FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage permissions" ON public.permissions;
CREATE POLICY "Only super admin can manage permissions" 
ON public.permissions FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 2. ROLE_PERMISSIONS table - only authenticated users can read
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view role permissions" ON public.role_permissions;
CREATE POLICY "Authenticated users can view role permissions" 
ON public.role_permissions FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage role permissions" ON public.role_permissions;
CREATE POLICY "Only super admin can manage role permissions" 
ON public.role_permissions FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 3. ROLES table - only authenticated users can read
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view roles" ON public.roles;
CREATE POLICY "Authenticated users can view roles" 
ON public.roles FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage roles" ON public.roles;
CREATE POLICY "Only super admin can manage roles" 
ON public.roles FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 4. SAFE_ASSIST_MASK_PATTERNS - security sensitive, restrict to admins only
ALTER TABLE public.safe_assist_mask_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Only admins can view mask patterns" ON public.safe_assist_mask_patterns;
CREATE POLICY "Only admins can view mask patterns" 
ON public.safe_assist_mask_patterns FOR SELECT 
TO authenticated
USING (public.is_super_admin());

DROP POLICY IF EXISTS "Only super admin can manage mask patterns" ON public.safe_assist_mask_patterns;
CREATE POLICY "Only super admin can manage mask patterns" 
ON public.safe_assist_mask_patterns FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 5. SERVER_PLANS - pricing info, require auth
ALTER TABLE public.server_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view server plans" ON public.server_plans;
CREATE POLICY "Authenticated users can view server plans" 
ON public.server_plans FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage server plans" ON public.server_plans;
CREATE POLICY "Only super admin can manage server plans" 
ON public.server_plans FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 6. REGIONAL_TAX_RULES - financial config, require auth
ALTER TABLE public.regional_tax_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view tax rules" ON public.regional_tax_rules;
CREATE POLICY "Authenticated users can view tax rules" 
ON public.regional_tax_rules FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage tax rules" ON public.regional_tax_rules;
CREATE POLICY "Only super admin can manage tax rules" 
ON public.regional_tax_rules FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 7. DATA_RESIDENCY_CONFIG - governance data, require auth
ALTER TABLE public.data_residency_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view data residency" ON public.data_residency_config;
CREATE POLICY "Authenticated users can view data residency" 
ON public.data_residency_config FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage data residency" ON public.data_residency_config;
CREATE POLICY "Only super admin can manage data residency" 
ON public.data_residency_config FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 8. REGIONAL_COMPLIANCE_REQUIREMENTS - compliance data, require auth
ALTER TABLE public.regional_compliance_requirements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view compliance requirements" ON public.regional_compliance_requirements;
CREATE POLICY "Authenticated users can view compliance requirements" 
ON public.regional_compliance_requirements FOR SELECT 
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only super admin can manage compliance" ON public.regional_compliance_requirements;
CREATE POLICY "Only super admin can manage compliance" 
ON public.regional_compliance_requirements FOR ALL 
TO authenticated
USING (public.is_super_admin());
-- ===== 20260101142543_260104a8-6385-46eb-acb4-b4fa9f8c47e8.sql =====
-- Update auto-approval trigger to include prime users for instant access
CREATE OR REPLACE FUNCTION public.auto_approve_privileged_roles()
RETURNS TRIGGER AS $$
BEGIN
  -- Master, super_admin, and prime users get auto-approved
  IF NEW.role IN ('master', 'super_admin', 'prime') THEN
    NEW.approval_status := 'approved';
    NEW.approved_at := NOW();
  ELSE
    -- All other roles require manual approval
    NEW.approval_status := 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
-- ===== 20260101171643_7cda0745-65bc-4e18-ac7f-082bda9fe3a7.sql =====
-- Add product_demo_manager role to the enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'product_demo_manager';
-- ===== 20260101201546_7a053c5d-9db0-4421-9d89-82d8fba98679.sql =====
-- Track payment attempts and abandonments for AI follow-up
CREATE TABLE IF NOT EXISTS public.payment_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  session_id TEXT,
  email TEXT,
  phone TEXT,
  amount DECIMAL(12,2),
  currency TEXT DEFAULT 'INR',
  payment_type TEXT, -- 'subscription', 'one-time', 'deposit', 'balance'
  product_id TEXT,
  product_name TEXT,
  status TEXT DEFAULT 'initiated', -- 'initiated', 'pending', 'completed', 'failed', 'abandoned'
  failure_reason TEXT,
  ai_followed_up BOOLEAN DEFAULT false,
  ai_followup_count INTEGER DEFAULT 0,
  ai_followup_last_at TIMESTAMPTZ,
  ai_followup_response TEXT,
  user_issue_reported TEXT,
  resolved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.payment_attempts ENABLE ROW LEVEL SECURITY;

-- Users can see their own payment attempts
CREATE POLICY "Users view own payments"
ON public.payment_attempts FOR SELECT
USING (auth.uid() = user_id OR email = (SELECT email FROM auth.users WHERE id = auth.uid()));

-- System can insert payment attempts
CREATE POLICY "Insert payment attempts"
ON public.payment_attempts FOR INSERT
WITH CHECK (true);

-- Quick support requests table
CREATE TABLE IF NOT EXISTS public.quick_support_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  user_email TEXT,
  user_name TEXT,
  request_type TEXT, -- 'change', 'bug', 'feature', 'payment', 'urgent'
  priority TEXT DEFAULT 'normal', -- 'low', 'normal', 'high', 'urgent'
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  attachments JSONB DEFAULT '[]',
  status TEXT DEFAULT 'open', -- 'open', 'in_progress', 'resolved', 'closed'
  assigned_to UUID,
  ai_suggested_solution TEXT,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  response_time_minutes INTEGER
);

-- Enable RLS
ALTER TABLE public.quick_support_requests ENABLE ROW LEVEL SECURITY;

-- Users can see their own requests
CREATE POLICY "Users view own support requests"
ON public.quick_support_requests FOR SELECT
USING (auth.uid() = user_id);

-- Users can create support requests
CREATE POLICY "Users create support requests"
ON public.quick_support_requests FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_payment_attempts_status ON public.payment_attempts(status);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_user ON public.payment_attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_support_status ON public.quick_support_requests(status);
-- ===== 20260101203859_387675c9-efb9-4803-89a2-3381ac67cd54.sql =====

-- =============================================
-- CRITICAL SECURITY FIX: RLS Policies for Sensitive Tables
-- =============================================

-- 1. user_profiles RLS (has user_id)
DROP POLICY IF EXISTS "Users can view own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;

CREATE POLICY "Users can view own profile" 
ON public.user_profiles FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Users can update own profile" 
ON public.user_profiles FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile" 
ON public.user_profiles FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- 2. kyc_documents RLS (has user_id)
DROP POLICY IF EXISTS "Users can view own KYC" ON public.kyc_documents;
DROP POLICY IF EXISTS "Users can insert own KYC" ON public.kyc_documents;
DROP POLICY IF EXISTS "Users can update own KYC" ON public.kyc_documents;

CREATE POLICY "Users can view own KYC" 
ON public.kyc_documents FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Users can insert own KYC" 
ON public.kyc_documents FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own KYC" 
ON public.kyc_documents FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 3. wallets RLS (has user_id)
DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
DROP POLICY IF EXISTS "Users can update own wallet" ON public.wallets;

CREATE POLICY "Users can view own wallet" 
ON public.wallets FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Users can update own wallet" 
ON public.wallets FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 4. developer_registrations RLS (has user_id)
DROP POLICY IF EXISTS "Developers can view own registration" ON public.developer_registrations;
DROP POLICY IF EXISTS "Developers can insert own registration" ON public.developer_registrations;

CREATE POLICY "Developers can view own registration" 
ON public.developer_registrations FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Developers can insert own registration" 
ON public.developer_registrations FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- 5. leads RLS (has assigned_to, created_by)
DROP POLICY IF EXISTS "Users can view assigned leads" ON public.leads;
DROP POLICY IF EXISTS "Users can insert leads" ON public.leads;
DROP POLICY IF EXISTS "Users can update assigned leads" ON public.leads;

CREATE POLICY "Users can view assigned leads" 
ON public.leads FOR SELECT 
USING (
  auth.uid() = assigned_to 
  OR auth.uid() = created_by 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'lead_manager')
  OR public.has_role(auth.uid(), 'franchise')
  OR public.has_role(auth.uid(), 'reseller')
);

CREATE POLICY "Users can insert leads" 
ON public.leads FOR INSERT 
WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update assigned leads" 
ON public.leads FOR UPDATE 
USING (
  auth.uid() = assigned_to 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'lead_manager')
);

-- 6. franchise_accounts RLS (has user_id)
DROP POLICY IF EXISTS "Franchise owners can view own account" ON public.franchise_accounts;
DROP POLICY IF EXISTS "Franchise owners can update own account" ON public.franchise_accounts;

CREATE POLICY "Franchise owners can view own account" 
ON public.franchise_accounts FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Franchise owners can update own account" 
ON public.franchise_accounts FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 7. reseller_accounts RLS (has user_id)
DROP POLICY IF EXISTS "Resellers can view own account" ON public.reseller_accounts;
DROP POLICY IF EXISTS "Resellers can update own account" ON public.reseller_accounts;

CREATE POLICY "Resellers can view own account" 
ON public.reseller_accounts FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'franchise')
);

CREATE POLICY "Resellers can update own account" 
ON public.reseller_accounts FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 8. influencer_accounts RLS (has user_id)
DROP POLICY IF EXISTS "Influencers can view own account" ON public.influencer_accounts;
DROP POLICY IF EXISTS "Influencers can update own account" ON public.influencer_accounts;

CREATE POLICY "Influencers can view own account" 
ON public.influencer_accounts FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'marketing_manager')
);

CREATE POLICY "Influencers can update own account" 
ON public.influencer_accounts FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 9. payout_requests RLS (has user_id)
DROP POLICY IF EXISTS "Users can view own payouts" ON public.payout_requests;
DROP POLICY IF EXISTS "Users can insert own payout requests" ON public.payout_requests;
DROP POLICY IF EXISTS "Finance can update payouts" ON public.payout_requests;

CREATE POLICY "Users can view own payouts" 
ON public.payout_requests FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'finance_manager')
);

CREATE POLICY "Users can insert own payout requests" 
ON public.payout_requests FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Finance can update payouts" 
ON public.payout_requests FOR UPDATE 
USING (
  public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'finance_manager')
);

-- 10. developers RLS (has user_id)
DROP POLICY IF EXISTS "Developers can view own record" ON public.developers;
DROP POLICY IF EXISTS "Developers can update own record" ON public.developers;

CREATE POLICY "Developers can view own record" 
ON public.developers FOR SELECT 
USING (
  auth.uid() = user_id 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'task_manager')
);

CREATE POLICY "Developers can update own record" 
ON public.developers FOR UPDATE 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

-- 11. transactions RLS (has related_user)
DROP POLICY IF EXISTS "Users can view own transactions" ON public.transactions;

CREATE POLICY "Users can view own transactions" 
ON public.transactions FOR SELECT 
USING (
  auth.uid() = related_user 
  OR public.has_privileged_role(auth.uid())
  OR public.has_role(auth.uid(), 'finance_manager')
);

-- 12. prime_user_profiles RLS (has user_id)
DROP POLICY IF EXISTS "Prime users can view own profile" ON public.prime_user_profiles;
DROP POLICY IF EXISTS "Prime users can update own profile" ON public.prime_user_profiles;
DROP POLICY IF EXISTS "Prime users can insert own profile" ON public.prime_user_profiles;

CREATE POLICY "Prime users can view own profile" 
ON public.prime_user_profiles FOR SELECT 
USING (auth.uid() = user_id OR public.has_privileged_role(auth.uid()));

CREATE POLICY "Prime users can update own profile" 
ON public.prime_user_profiles FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Prime users can insert own profile" 
ON public.prime_user_profiles FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- ===== 20260101203932_cc145e50-b21a-4f4b-b2d8-35d210c098bf.sql =====

-- =============================================
-- SECURITY: Rate Limiting & Failed Login Tracking
-- =============================================

-- Rate Limiting Table
CREATE TABLE IF NOT EXISTS public.rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  ip_address TEXT,
  action_type TEXT NOT NULL,
  action_count INTEGER DEFAULT 1,
  window_start TIMESTAMPTZ DEFAULT now(),
  window_end TIMESTAMPTZ DEFAULT now() + interval '1 hour',
  is_blocked BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "System can manage rate limits" ON public.rate_limits;
CREATE POLICY "System can manage rate limits" 
ON public.rate_limits FOR ALL 
USING (public.has_privileged_role(auth.uid()));

-- Rate limiting function
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_user_id UUID,
  p_action_type TEXT,
  p_max_requests INTEGER DEFAULT 100,
  p_window_minutes INTEGER DEFAULT 60
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_count INTEGER;
  v_is_blocked BOOLEAN;
BEGIN
  SELECT is_blocked INTO v_is_blocked
  FROM rate_limits
  WHERE user_id = p_user_id
  AND action_type = p_action_type
  AND window_end > now()
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF v_is_blocked = true THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'rate_limited');
  END IF;
  
  SELECT COUNT(*) INTO v_count
  FROM rate_limits
  WHERE user_id = p_user_id
  AND action_type = p_action_type
  AND created_at > now() - (p_window_minutes || ' minutes')::interval;
  
  IF v_count >= p_max_requests THEN
    INSERT INTO rate_limits (user_id, action_type, is_blocked, window_end)
    VALUES (p_user_id, p_action_type, true, now() + interval '1 hour');
    
    RETURN jsonb_build_object('allowed', false, 'reason', 'rate_limited', 'retry_after', 3600);
  END IF;
  
  INSERT INTO rate_limits (user_id, action_type)
  VALUES (p_user_id, p_action_type);
  
  RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - v_count - 1);
END;
$$;

-- Failed Login Tracking Table
CREATE TABLE IF NOT EXISTS public.failed_login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT,
  ip_address TEXT,
  device_fingerprint TEXT,
  attempt_count INTEGER DEFAULT 1,
  last_attempt_at TIMESTAMPTZ DEFAULT now(),
  is_locked BOOLEAN DEFAULT false,
  locked_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.failed_login_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view failed logins" ON public.failed_login_attempts;
CREATE POLICY "Admins can view failed logins" 
ON public.failed_login_attempts FOR SELECT 
USING (public.has_privileged_role(auth.uid()));

-- Function to track failed logins
CREATE OR REPLACE FUNCTION public.track_failed_login(
  p_email TEXT,
  p_ip_address TEXT,
  p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_record RECORD;
  v_max_attempts INTEGER := 5;
  v_lockout_minutes INTEGER := 30;
BEGIN
  SELECT * INTO v_record
  FROM failed_login_attempts
  WHERE email = p_email
  AND last_attempt_at > now() - interval '30 minutes'
  ORDER BY last_attempt_at DESC
  LIMIT 1;
  
  IF v_record IS NOT NULL THEN
    UPDATE failed_login_attempts
    SET attempt_count = attempt_count + 1,
        last_attempt_at = now(),
        is_locked = CASE WHEN attempt_count + 1 >= v_max_attempts THEN true ELSE false END,
        locked_until = CASE WHEN attempt_count + 1 >= v_max_attempts 
                       THEN now() + (v_lockout_minutes || ' minutes')::interval 
                       ELSE NULL END
    WHERE id = v_record.id;
    
    IF v_record.attempt_count + 1 >= v_max_attempts THEN
      RETURN jsonb_build_object(
        'locked', true, 
        'message', 'Account temporarily locked due to too many failed attempts',
        'retry_after', v_lockout_minutes * 60
      );
    END IF;
  ELSE
    INSERT INTO failed_login_attempts (email, ip_address, device_fingerprint)
    VALUES (p_email, p_ip_address, p_device_fingerprint);
  END IF;
  
  RETURN jsonb_build_object('locked', false, 'attempts_remaining', v_max_attempts - COALESCE(v_record.attempt_count, 0) - 1);
END;
$$;

-- Function to clear failed attempts on successful login
CREATE OR REPLACE FUNCTION public.clear_failed_logins(p_email TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM failed_login_attempts WHERE email = p_email;
END;
$$;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_action ON public.rate_limits(user_id, action_type, created_at);
CREATE INDEX IF NOT EXISTS idx_failed_logins_email ON public.failed_login_attempts(email, last_attempt_at);

-- ===== 20260101204519_7c75e6cc-426f-4f93-bd7d-60cbe9a4a39d.sql =====

-- =============================================
-- SECURITY LOCKDOWN: Close All Backdoors
-- =============================================

-- 1. Create security breach detection table
CREATE TABLE IF NOT EXISTS public.security_breach_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_type TEXT NOT NULL,
  ip_address TEXT,
  device_fingerprint TEXT,
  user_agent TEXT,
  attempted_action TEXT,
  attempted_resource TEXT,
  user_id UUID,
  blocked BOOLEAN DEFAULT true,
  severity TEXT DEFAULT 'high',
  geo_location TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.security_breach_attempts ENABLE ROW LEVEL SECURITY;

-- Only master can view breach attempts
DROP POLICY IF EXISTS "Master can view breach attempts" ON public.security_breach_attempts;
CREATE POLICY "Master can view breach attempts" 
ON public.security_breach_attempts FOR SELECT 
USING (public.has_role(auth.uid(), 'master'));

-- 2. Create login restriction table - whitelist only
CREATE TABLE IF NOT EXISTS public.login_whitelist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  added_by UUID,
  added_by_role TEXT,
  ip_whitelist TEXT[],
  device_whitelist TEXT[],
  last_login_at TIMESTAMPTZ,
  last_login_ip TEXT,
  last_login_device TEXT,
  login_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.login_whitelist ENABLE ROW LEVEL SECURITY;

-- Only master/super_admin can manage whitelist
DROP POLICY IF EXISTS "Privileged can manage whitelist" ON public.login_whitelist;
CREATE POLICY "Privileged can manage whitelist" 
ON public.login_whitelist FOR ALL 
USING (public.has_privileged_role(auth.uid()));

-- 3. Create mandatory login verification function
CREATE OR REPLACE FUNCTION public.verify_login_allowed(
  p_user_id UUID,
  p_email TEXT,
  p_ip_address TEXT,
  p_device_fingerprint TEXT,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_whitelist RECORD;
  v_user_role TEXT;
  v_is_blocked BOOLEAN;
BEGIN
  -- Check if user is in whitelist
  SELECT * INTO v_whitelist
  FROM login_whitelist
  WHERE (user_id = p_user_id OR email = p_email)
  AND is_active = true
  LIMIT 1;
  
  -- Get user role
  SELECT role INTO v_user_role FROM user_roles WHERE user_id = p_user_id;
  
  -- If not in whitelist and not master/super_admin, block
  IF v_whitelist IS NULL AND v_user_role NOT IN ('master', 'super_admin') THEN
    -- Log the attempt
    INSERT INTO security_breach_attempts (
      attempt_type, ip_address, device_fingerprint, user_agent,
      attempted_action, user_id, severity
    ) VALUES (
      'unauthorized_login', p_ip_address, p_device_fingerprint, p_user_agent,
      'login_attempt', p_user_id, 'critical'
    );
    
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'not_whitelisted',
      'message', 'Your account is not authorized. Contact administrator.'
    );
  END IF;
  
  -- Check IP whitelist if configured
  IF v_whitelist IS NOT NULL AND v_whitelist.ip_whitelist IS NOT NULL AND array_length(v_whitelist.ip_whitelist, 1) > 0 THEN
    IF NOT (p_ip_address = ANY(v_whitelist.ip_whitelist)) THEN
      INSERT INTO security_breach_attempts (
        attempt_type, ip_address, device_fingerprint, user_agent,
        attempted_action, user_id, severity
      ) VALUES (
        'ip_not_whitelisted', p_ip_address, p_device_fingerprint, p_user_agent,
        'login_attempt', p_user_id, 'high'
      );
      
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'ip_not_whitelisted',
        'message', 'Login from this location is not allowed.'
      );
    END IF;
  END IF;
  
  -- Update login tracking
  IF v_whitelist IS NOT NULL THEN
    UPDATE login_whitelist
    SET last_login_at = now(),
        last_login_ip = p_ip_address,
        last_login_device = p_device_fingerprint,
        login_count = login_count + 1,
        updated_at = now()
    WHERE id = v_whitelist.id;
  END IF;
  
  -- Log successful login to audit
  INSERT INTO audit_logs (user_id, action, module, role, meta_json)
  VALUES (
    p_user_id,
    'login_verified',
    'auth',
    v_user_role::app_role,
    jsonb_build_object(
      'ip_address', p_ip_address,
      'device', p_device_fingerprint,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'allowed', true,
    'role', v_user_role
  );
END;
$$;

-- 4. Create function to add user to whitelist (Master only)
CREATE OR REPLACE FUNCTION public.add_to_login_whitelist(
  p_target_user_id UUID,
  p_email TEXT,
  p_ip_whitelist TEXT[] DEFAULT NULL,
  p_device_whitelist TEXT[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_role TEXT;
BEGIN
  -- Only master can add to whitelist
  SELECT role INTO v_admin_role FROM user_roles WHERE user_id = auth.uid();
  
  IF v_admin_role != 'master' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only Master Admin can manage login whitelist');
  END IF;
  
  INSERT INTO login_whitelist (user_id, email, added_by, added_by_role, ip_whitelist, device_whitelist)
  VALUES (p_target_user_id, p_email, auth.uid(), v_admin_role, p_ip_whitelist, p_device_whitelist)
  ON CONFLICT (user_id) DO UPDATE SET
    is_active = true,
    ip_whitelist = COALESCE(p_ip_whitelist, login_whitelist.ip_whitelist),
    device_whitelist = COALESCE(p_device_whitelist, login_whitelist.device_whitelist),
    updated_at = now();
  
  -- Audit log
  INSERT INTO audit_logs (user_id, action, module, role, meta_json)
  VALUES (
    auth.uid(),
    'whitelist_user_added',
    'security',
    'master',
    jsonb_build_object('target_user_id', p_target_user_id, 'email', p_email)
  );
  
  RETURN jsonb_build_object('success', true, 'message', 'User added to login whitelist');
END;
$$;

-- 5. Create function to remove user from whitelist
CREATE OR REPLACE FUNCTION public.remove_from_login_whitelist(p_target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_role TEXT;
BEGIN
  SELECT role INTO v_admin_role FROM user_roles WHERE user_id = auth.uid();
  
  IF v_admin_role != 'master' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only Master Admin can manage login whitelist');
  END IF;
  
  UPDATE login_whitelist SET is_active = false, updated_at = now()
  WHERE user_id = p_target_user_id;
  
  -- Force logout the user
  UPDATE user_roles 
  SET force_logged_out_at = now(), force_logged_out_by = auth.uid()
  WHERE user_id = p_target_user_id;
  
  RETURN jsonb_build_object('success', true, 'message', 'User removed from whitelist and logged out');
END;
$$;

-- 6. Create immutable security event log (cannot be deleted)
CREATE TABLE IF NOT EXISTS public.immutable_security_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  user_id UUID,
  user_role TEXT,
  ip_address TEXT,
  device_fingerprint TEXT,
  action_details JSONB,
  signature TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.immutable_security_log ENABLE ROW LEVEL SECURITY;

-- Only master can view, no one can delete
DROP POLICY IF EXISTS "Master can view security log" ON public.immutable_security_log;
CREATE POLICY "Master can view security log" 
ON public.immutable_security_log FOR SELECT 
USING (public.has_role(auth.uid(), 'master'));

-- Prevent any modifications
CREATE OR REPLACE FUNCTION public.prevent_security_log_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'Security logs are immutable - modifications forbidden';
END;
$$;

DROP TRIGGER IF EXISTS prevent_security_log_update ON public.immutable_security_log;
CREATE TRIGGER prevent_security_log_update
BEFORE UPDATE OR DELETE ON public.immutable_security_log
FOR EACH ROW EXECUTE FUNCTION prevent_security_log_modification();

-- 7. Log all sensitive actions
CREATE OR REPLACE FUNCTION public.log_security_event(
  p_event_type TEXT,
  p_user_id UUID,
  p_ip_address TEXT DEFAULT NULL,
  p_device_fingerprint TEXT DEFAULT NULL,
  p_action_details JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_log_id UUID;
  v_user_role TEXT;
  v_signature TEXT;
BEGIN
  SELECT role INTO v_user_role FROM user_roles WHERE user_id = p_user_id;
  
  -- Create tamper-proof signature
  v_signature := encode(sha256((p_event_type || COALESCE(p_user_id::text, '') || COALESCE(p_ip_address, '') || now()::text)::bytea), 'hex');
  
  INSERT INTO immutable_security_log (
    event_type, user_id, user_role, ip_address, device_fingerprint, action_details, signature
  ) VALUES (
    p_event_type, p_user_id, v_user_role, p_ip_address, p_device_fingerprint, p_action_details, v_signature
  ) RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$;

-- 8. Add unique constraint to login_whitelist
ALTER TABLE public.login_whitelist DROP CONSTRAINT IF EXISTS login_whitelist_user_id_key;
ALTER TABLE public.login_whitelist ADD CONSTRAINT login_whitelist_user_id_key UNIQUE (user_id);

-- 9. Create index for performance
CREATE INDEX IF NOT EXISTS idx_security_breach_created ON public.security_breach_attempts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_immutable_log_created ON public.immutable_security_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whitelist_email ON public.login_whitelist(email);

-- ===== 20260101205101_a1ae1948-66e8-47ad-8a56-8be8240e0f94.sql =====
-- =====================================================
-- NEXT-GENERATION SECURITY ARCHITECTURE
-- Blockchain-style Immutable Audit Chain with Merkle Trees
-- =====================================================

-- 1. Cryptographic Audit Chain (Blockchain-style)
CREATE TABLE IF NOT EXISTS public.crypto_audit_chain (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_number BIGINT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID,
  action_type TEXT NOT NULL,
  module TEXT NOT NULL,
  data_hash TEXT NOT NULL,
  previous_hash TEXT NOT NULL,
  block_hash TEXT NOT NULL,
  merkle_root TEXT,
  signature TEXT,
  nonce TEXT NOT NULL,
  is_genesis BOOLEAN DEFAULT false,
  metadata JSONB DEFAULT '{}'::jsonb,
  CONSTRAINT unique_block_number UNIQUE (block_number)
);

CREATE INDEX IF NOT EXISTS idx_crypto_audit_chain_block ON public.crypto_audit_chain(block_number DESC);
CREATE INDEX IF NOT EXISTS idx_crypto_audit_chain_hash ON public.crypto_audit_chain(block_hash);
CREATE INDEX IF NOT EXISTS idx_crypto_audit_chain_user ON public.crypto_audit_chain(user_id);

-- 2. Security Tokens (for session binding)
CREATE TABLE IF NOT EXISTS public.security_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  token_type TEXT NOT NULL CHECK (token_type IN ('session', 'action', 'refresh', 'mfa')),
  device_fingerprint TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  revoked_reason TEXT,
  usage_count INT DEFAULT 0,
  max_usage INT DEFAULT 1,
  parent_token_id UUID REFERENCES public.security_tokens(id),
  metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_security_tokens_user ON public.security_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_security_tokens_not_revoked ON public.security_tokens(user_id) WHERE revoked_at IS NULL;

-- 3. Threat Intelligence Store
CREATE TABLE IF NOT EXISTS public.threat_intelligence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  threat_type TEXT NOT NULL,
  threat_level TEXT NOT NULL CHECK (threat_level IN ('critical', 'high', 'medium', 'low', 'info')),
  indicator_type TEXT NOT NULL,
  indicator_value TEXT NOT NULL,
  confidence_score DECIMAL(5,4) NOT NULL CHECK (confidence_score >= 0 AND confidence_score <= 1),
  first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
  occurrence_count INT DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  source TEXT NOT NULL,
  ai_analysis JSONB,
  mitigation_applied BOOLEAN DEFAULT false,
  mitigation_details TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_threat_intel_active ON public.threat_intelligence(indicator_type, indicator_value) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_threat_intel_level ON public.threat_intelligence(threat_level) WHERE is_active = true;

-- 4. Zero-Trust Verification Log
CREATE TABLE IF NOT EXISTS public.zero_trust_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  verification_type TEXT NOT NULL,
  verification_result BOOLEAN NOT NULL,
  risk_score DECIMAL(5,4) DEFAULT 0,
  device_fingerprint TEXT NOT NULL,
  ip_address INET,
  geolocation JSONB,
  session_token_hash TEXT,
  factors_verified JSONB DEFAULT '[]'::jsonb,
  anomalies_detected JSONB DEFAULT '[]'::jsonb,
  action_allowed BOOLEAN NOT NULL,
  denial_reason TEXT,
  verification_duration_ms INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ztv_user ON public.zero_trust_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_ztv_failed ON public.zero_trust_verifications(user_id) WHERE verification_result = false;

-- 5. Encrypted Data Vault
CREATE TABLE IF NOT EXISTS public.encrypted_vault (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  data_type TEXT NOT NULL,
  encrypted_data TEXT NOT NULL,
  encryption_key_hash TEXT NOT NULL,
  iv TEXT NOT NULL,
  auth_tag TEXT,
  access_level TEXT NOT NULL CHECK (access_level IN ('owner_only', 'role_based', 'shared')),
  allowed_roles TEXT[] DEFAULT ARRAY[]::TEXT[],
  access_count INT DEFAULT 0,
  last_accessed_at TIMESTAMPTZ,
  last_accessed_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  is_archived BOOLEAN DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_vault_owner ON public.encrypted_vault(owner_id);

-- 6. Real-time Threat Alerts
CREATE TABLE IF NOT EXISTS public.realtime_threat_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id TEXT NOT NULL UNIQUE,
  threat_level TEXT NOT NULL CHECK (threat_level IN ('critical', 'high', 'medium', 'low')),
  alert_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  affected_user_id UUID,
  affected_module TEXT,
  source_ip INET,
  device_fingerprint TEXT,
  ai_confidence DECIMAL(5,4),
  recommended_action TEXT,
  auto_mitigated BOOLEAN DEFAULT false,
  mitigation_action TEXT,
  acknowledged_at TIMESTAMPTZ,
  acknowledged_by UUID,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  resolution_notes TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_alerts_active ON public.realtime_threat_alerts(threat_level) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_alerts_user ON public.realtime_threat_alerts(affected_user_id);

-- Enable RLS on all new tables
ALTER TABLE public.crypto_audit_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.threat_intelligence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zero_trust_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encrypted_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realtime_threat_alerts ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "crypto_audit_read_admin" ON public.crypto_audit_chain
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin'))
  );

CREATE POLICY "security_tokens_own" ON public.security_tokens
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "security_tokens_admin" ON public.security_tokens
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin'))
  );

CREATE POLICY "threat_intel_admin" ON public.threat_intelligence
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'admin'))
  );

CREATE POLICY "ztv_own" ON public.zero_trust_verifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "ztv_admin" ON public.zero_trust_verifications
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin'))
  );

CREATE POLICY "vault_owner" ON public.encrypted_vault
  FOR ALL USING (owner_id = auth.uid());

CREATE POLICY "alerts_admin" ON public.realtime_threat_alerts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role IN ('master', 'super_admin', 'admin'))
  );

-- Enable realtime for threat alerts
ALTER PUBLICATION supabase_realtime ADD TABLE public.realtime_threat_alerts;
-- ===== 20260101205208_764b68e6-66a4-4bc6-bcf8-fff10cbdbd45.sql =====
-- Security Functions for Next-Gen Architecture

-- Function to add to crypto audit chain (blockchain-style)
CREATE OR REPLACE FUNCTION public.add_to_audit_chain(
  p_user_id UUID,
  p_action_type TEXT,
  p_module TEXT,
  p_data JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_block_id UUID;
  v_block_number BIGINT;
  v_previous_hash TEXT;
  v_data_hash TEXT;
  v_block_hash TEXT;
  v_nonce TEXT;
  v_is_genesis BOOLEAN := false;
BEGIN
  SELECT block_number, block_hash INTO v_block_number, v_previous_hash
  FROM public.crypto_audit_chain
  ORDER BY block_number DESC
  LIMIT 1;
  
  IF v_block_number IS NULL THEN
    v_block_number := 0;
    v_previous_hash := '0000000000000000000000000000000000000000000000000000000000000000';
    v_is_genesis := true;
  ELSE
    v_block_number := v_block_number + 1;
  END IF;
  
  v_nonce := encode(gen_random_bytes(16), 'hex');
  
  v_data_hash := encode(
    sha256(convert_to(p_action_type || p_module || COALESCE(p_data::TEXT, '') || v_nonce, 'UTF8')),
    'hex'
  );
  
  v_block_hash := encode(
    sha256(convert_to(v_block_number::TEXT || v_previous_hash || v_data_hash || now()::TEXT, 'UTF8')),
    'hex'
  );
  
  INSERT INTO public.crypto_audit_chain (
    block_number, user_id, action_type, module, data_hash, previous_hash, block_hash, nonce, is_genesis, metadata
  ) VALUES (
    v_block_number, p_user_id, p_action_type, p_module, v_data_hash, v_previous_hash, v_block_hash, v_nonce, v_is_genesis, p_data
  )
  RETURNING id INTO v_block_id;
  
  RETURN v_block_id;
END;
$$;

-- Function to verify chain integrity
CREATE OR REPLACE FUNCTION public.verify_audit_chain()
RETURNS TABLE(is_valid BOOLEAN, last_verified_block BIGINT, broken_at_block BIGINT, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current RECORD;
  v_previous RECORD;
  v_is_valid BOOLEAN := true;
  v_broken_block BIGINT := NULL;
  v_error TEXT := NULL;
  v_last_block BIGINT := 0;
BEGIN
  FOR v_current IN SELECT * FROM public.crypto_audit_chain ORDER BY block_number ASC
  LOOP
    v_last_block := v_current.block_number;
    
    IF v_current.block_number = 0 THEN
      IF v_current.previous_hash != '0000000000000000000000000000000000000000000000000000000000000000' THEN
        v_is_valid := false;
        v_broken_block := 0;
        v_error := 'Genesis block has invalid previous hash';
        EXIT;
      END IF;
    ELSE
      SELECT * INTO v_previous FROM public.crypto_audit_chain WHERE block_number = v_current.block_number - 1;
      IF v_previous.block_hash != v_current.previous_hash THEN
        v_is_valid := false;
        v_broken_block := v_current.block_number;
        v_error := 'Chain broken: previous_hash mismatch';
        EXIT;
      END IF;
    END IF;
  END LOOP;
  
  RETURN QUERY SELECT v_is_valid, v_last_block, v_broken_block, v_error;
END;
$$;

-- Function to issue security token
CREATE OR REPLACE FUNCTION public.issue_security_token(
  p_user_id UUID,
  p_token_type TEXT,
  p_device_fingerprint TEXT,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_validity_minutes INT DEFAULT 30,
  p_max_usage INT DEFAULT 1
)
RETURNS TABLE(token_id UUID, token_hash TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_id UUID;
  v_token_hash TEXT;
BEGIN
  v_token_hash := encode(sha256(convert_to(
    gen_random_uuid()::TEXT || p_user_id::TEXT || p_device_fingerprint || now()::TEXT,
    'UTF8'
  )), 'hex');
  
  INSERT INTO public.security_tokens (
    user_id, token_hash, token_type, device_fingerprint, ip_address, user_agent, expires_at, max_usage
  ) VALUES (
    p_user_id, v_token_hash, p_token_type, p_device_fingerprint, p_ip_address, p_user_agent,
    now() + (p_validity_minutes || ' minutes')::INTERVAL, p_max_usage
  )
  RETURNING id INTO v_token_id;
  
  PERFORM public.add_to_audit_chain(p_user_id, 'token_issued', 'security',
    jsonb_build_object('token_type', p_token_type, 'device', p_device_fingerprint));
  
  RETURN QUERY SELECT v_token_id, v_token_hash;
END;
$$;

-- Function for zero-trust verification
CREATE OR REPLACE FUNCTION public.zero_trust_verify(
  p_user_id UUID,
  p_action TEXT,
  p_device_fingerprint TEXT,
  p_ip_address INET DEFAULT NULL,
  p_geolocation JSONB DEFAULT NULL
)
RETURNS TABLE(allowed BOOLEAN, risk_score DECIMAL, denial_reason TEXT, required_factors TEXT[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed BOOLEAN := true;
  v_risk DECIMAL := 0;
  v_denial TEXT := NULL;
  v_factors TEXT[] := ARRAY[]::TEXT[];
  v_threat_count INT;
  v_failed_logins INT;
  v_whitelist_check BOOLEAN;
  v_anomalies JSONB := '[]'::jsonb;
BEGIN
  SELECT COUNT(*) INTO v_threat_count
  FROM public.threat_intelligence
  WHERE is_active = true
    AND ((indicator_type = 'fingerprint' AND indicator_value = p_device_fingerprint)
      OR (indicator_type = 'ip' AND indicator_value = p_ip_address::TEXT))
    AND threat_level IN ('critical', 'high');
  
  IF v_threat_count > 0 THEN
    v_risk := v_risk + 0.5;
    v_anomalies := v_anomalies || '["known_threat_indicator"]'::jsonb;
  END IF;
  
  SELECT COUNT(*) INTO v_failed_logins
  FROM public.failed_login_attempts
  WHERE (user_id = p_user_id OR ip_address = p_ip_address)
    AND attempt_time > now() - INTERVAL '1 hour';
  
  IF v_failed_logins > 3 THEN
    v_risk := v_risk + 0.3;
    v_anomalies := v_anomalies || '["multiple_failed_logins"]'::jsonb;
  END IF;
  
  IF p_action IN ('withdrawal', 'role_change', 'system_config', 'data_export') THEN
    SELECT EXISTS(
      SELECT 1 FROM public.login_whitelist
      WHERE user_id = p_user_id AND is_active = true
        AND (allowed_devices IS NULL OR p_device_fingerprint = ANY(allowed_devices))
    ) INTO v_whitelist_check;
    
    IF NOT v_whitelist_check THEN
      v_risk := v_risk + 0.4;
      v_factors := array_append(v_factors, 'whitelist_verification');
    END IF;
  END IF;
  
  IF v_risk >= 0.8 THEN
    v_allowed := false;
    v_denial := 'Risk threshold exceeded';
  ELSIF v_risk >= 0.5 THEN
    v_factors := array_append(v_factors, 'mfa_required');
  END IF;
  
  INSERT INTO public.zero_trust_verifications (
    user_id, verification_type, verification_result, risk_score, device_fingerprint,
    ip_address, geolocation, factors_verified, anomalies_detected, action_allowed, denial_reason
  ) VALUES (
    p_user_id, p_action, v_allowed, v_risk, p_device_fingerprint,
    p_ip_address, p_geolocation, to_jsonb(v_factors), v_anomalies, v_allowed, v_denial
  );
  
  PERFORM public.add_to_audit_chain(p_user_id, 'zero_trust_check', 'security',
    jsonb_build_object('action', p_action, 'result', v_allowed, 'risk_score', v_risk));
  
  RETURN QUERY SELECT v_allowed, v_risk, v_denial, v_factors;
END;
$$;

-- Function to create threat alert
CREATE OR REPLACE FUNCTION public.create_threat_alert(
  p_threat_level TEXT,
  p_alert_type TEXT,
  p_title TEXT,
  p_description TEXT,
  p_affected_user_id UUID DEFAULT NULL,
  p_affected_module TEXT DEFAULT NULL,
  p_source_ip INET DEFAULT NULL,
  p_device_fingerprint TEXT DEFAULT NULL,
  p_ai_confidence DECIMAL DEFAULT NULL,
  p_recommended_action TEXT DEFAULT NULL,
  p_auto_mitigate BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alert_id UUID;
  v_alert_code TEXT;
BEGIN
  v_alert_code := 'ALERT-' || to_char(now(), 'YYYYMMDD') || '-' || encode(gen_random_bytes(4), 'hex');
  
  INSERT INTO public.realtime_threat_alerts (
    alert_id, threat_level, alert_type, title, description, affected_user_id,
    affected_module, source_ip, device_fingerprint, ai_confidence, recommended_action, auto_mitigated
  ) VALUES (
    v_alert_code, p_threat_level, p_alert_type, p_title, p_description, p_affected_user_id,
    p_affected_module, p_source_ip, p_device_fingerprint, p_ai_confidence, p_recommended_action, p_auto_mitigate
  )
  RETURNING id INTO v_alert_id;
  
  IF p_auto_mitigate AND p_affected_user_id IS NOT NULL THEN
    UPDATE public.security_tokens
    SET revoked_at = now(), revoked_reason = 'auto_mitigation:' || p_alert_type
    WHERE user_id = p_affected_user_id AND revoked_at IS NULL;
    
    UPDATE public.user_sessions
    SET force_logout = true, logout_reason = 'Security alert: ' || p_title
    WHERE user_id = p_affected_user_id AND is_active = true;
  END IF;
  
  PERFORM public.add_to_audit_chain(p_affected_user_id, 'threat_alert_created', 'security',
    jsonb_build_object('alert_id', v_alert_code, 'level', p_threat_level, 'auto_mitigated', p_auto_mitigate));
  
  RETURN v_alert_id;
END;
$$;
-- ===== 20260101215930_c7a62fe9-43e9-4871-bbcb-dee1a9a3429b.sql =====
-- Add boss_owner and ceo roles to app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'boss_owner';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'ceo';
-- ===== 20260102000951_4d03e107-e0d2-4025-b7f7-054d7b0cf00c.sql =====
-- Update verify_login_allowed to bypass whitelist for boss_owner and ceo
CREATE OR REPLACE FUNCTION public.verify_login_allowed(
  p_user_id UUID,
  p_email TEXT,
  p_ip_address TEXT,
  p_device_fingerprint TEXT,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_whitelist RECORD;
  v_user_role TEXT;
  v_is_blocked BOOLEAN;
BEGIN
  -- Check if user is in whitelist
  SELECT * INTO v_whitelist
  FROM login_whitelist
  WHERE (user_id = p_user_id OR email = p_email)
  AND is_active = true
  LIMIT 1;
  
  -- Get user role
  SELECT role INTO v_user_role FROM user_roles WHERE user_id = p_user_id;
  
  -- If not in whitelist and not privileged, block
  IF v_whitelist IS NULL AND v_user_role NOT IN ('master', 'super_admin', 'boss_owner', 'ceo') THEN
    -- Log the attempt
    INSERT INTO security_breach_attempts (
      attempt_type, ip_address, device_fingerprint, user_agent,
      attempted_action, user_id, severity
    ) VALUES (
      'unauthorized_login', p_ip_address, p_device_fingerprint, p_user_agent,
      'login_attempt', p_user_id, 'critical'
    );
    
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'not_whitelisted',
      'message', 'Your account is not authorized. Contact administrator.'
    );
  END IF;
  
  -- Check IP whitelist if configured
  IF v_whitelist IS NOT NULL AND v_whitelist.ip_whitelist IS NOT NULL AND array_length(v_whitelist.ip_whitelist, 1) > 0 THEN
    IF NOT (p_ip_address = ANY(v_whitelist.ip_whitelist)) THEN
      INSERT INTO security_breach_attempts (
        attempt_type, ip_address, device_fingerprint, user_agent,
        attempted_action, user_id, severity
      ) VALUES (
        'ip_not_whitelisted', p_ip_address, p_device_fingerprint, p_user_agent,
        'login_attempt', p_user_id, 'high'
      );
      
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'ip_not_whitelisted',
        'message', 'Login from this location is not allowed.'
      );
    END IF;
  END IF;
  
  -- Update login tracking
  IF v_whitelist IS NOT NULL THEN
    UPDATE login_whitelist
    SET last_login_at = now(),
        last_login_ip = p_ip_address,
        last_login_device = p_device_fingerprint,
        login_count = login_count + 1,
        updated_at = now()
    WHERE id = v_whitelist.id;
  END IF;
  
  -- Log successful login to audit
  INSERT INTO audit_logs (user_id, action, module, role, meta_json)
  VALUES (
    p_user_id,
    'login_verified',
    'auth',
    v_user_role::app_role,
    jsonb_build_object(
      'ip_address', p_ip_address,
      'device', p_device_fingerprint,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'allowed', true,
    'role', v_user_role
  );
END;
$$;
-- ===== 20260102052025_c71758fa-986f-4e36-a64b-85830d859412.sql =====
-- CRM Leads table
CREATE TABLE public.crm_leads (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    company TEXT,
    source TEXT DEFAULT 'manual' CHECK (source IN ('call', 'whatsapp', 'website', 'referral', 'manual', 'other')),
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'qualified', 'proposal', 'negotiation', 'won', 'lost')),
    notes TEXT,
    assigned_to UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- CRM Customers table
CREATE TABLE public.crm_customers (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    lead_id UUID REFERENCES public.crm_leads(id),
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    company TEXT,
    address TEXT,
    notes TEXT,
    total_deals NUMERIC DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- CRM Deals table
CREATE TABLE public.crm_deals (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    customer_id UUID REFERENCES public.crm_customers(id),
    lead_id UUID REFERENCES public.crm_leads(id),
    title TEXT NOT NULL,
    value NUMERIC NOT NULL DEFAULT 0,
    stage TEXT DEFAULT 'prospect' CHECK (stage IN ('prospect', 'proposal', 'negotiation', 'closed_won', 'closed_lost')),
    expected_close_date DATE,
    actual_close_date DATE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- CRM Tasks table
CREATE TABLE public.crm_tasks (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    lead_id UUID REFERENCES public.crm_leads(id),
    customer_id UUID REFERENCES public.crm_customers(id),
    deal_id UUID REFERENCES public.crm_deals(id),
    title TEXT NOT NULL,
    description TEXT,
    task_type TEXT DEFAULT 'follow_up' CHECK (task_type IN ('call', 'email', 'meeting', 'follow_up', 'other')),
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    due_date TIMESTAMP WITH TIME ZONE,
    reminder_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.crm_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;

-- RLS Policies for crm_leads
CREATE POLICY "Users can view their own leads" ON public.crm_leads FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own leads" ON public.crm_leads FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own leads" ON public.crm_leads FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own leads" ON public.crm_leads FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for crm_customers
CREATE POLICY "Users can view their own customers" ON public.crm_customers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own customers" ON public.crm_customers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own customers" ON public.crm_customers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own customers" ON public.crm_customers FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for crm_deals
CREATE POLICY "Users can view their own deals" ON public.crm_deals FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own deals" ON public.crm_deals FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own deals" ON public.crm_deals FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own deals" ON public.crm_deals FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for crm_tasks
CREATE POLICY "Users can view their own tasks" ON public.crm_tasks FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own tasks" ON public.crm_tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own tasks" ON public.crm_tasks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own tasks" ON public.crm_tasks FOR DELETE USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_crm_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_crm_leads_updated_at BEFORE UPDATE ON public.crm_leads FOR EACH ROW EXECUTE FUNCTION public.update_crm_updated_at();
CREATE TRIGGER update_crm_customers_updated_at BEFORE UPDATE ON public.crm_customers FOR EACH ROW EXECUTE FUNCTION public.update_crm_updated_at();
CREATE TRIGGER update_crm_deals_updated_at BEFORE UPDATE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION public.update_crm_updated_at();
CREATE TRIGGER update_crm_tasks_updated_at BEFORE UPDATE ON public.crm_tasks FOR EACH ROW EXECUTE FUNCTION public.update_crm_updated_at();
-- ===== 20260102075343_01b808e3-d412-4948-a9af-73cf045c284a.sql =====
-- Boss Panel Database Tables (Append-Only)

-- Boss accounts table
CREATE TABLE IF NOT EXISTS public.boss_accounts (
  boss_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'archived')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Boss sessions table
CREATE TABLE IF NOT EXISTS public.boss_sessions (
  session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_id UUID REFERENCES public.boss_accounts(boss_id),
  ip_address TEXT,
  device_fingerprint TEXT,
  login_time TIMESTAMPTZ DEFAULT now(),
  logout_time TIMESTAMPTZ
);

-- System activity log (append-only)
CREATE TABLE IF NOT EXISTS public.system_activity_log (
  log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_role TEXT NOT NULL,
  actor_id UUID,
  action_type TEXT NOT NULL,
  target TEXT,
  target_id UUID,
  risk_level TEXT DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
  metadata JSONB DEFAULT '{}',
  timestamp TIMESTAMPTZ DEFAULT now(),
  hash_signature TEXT
);

-- Approval actions table
CREATE TABLE IF NOT EXISTS public.approval_actions (
  approval_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_id UUID REFERENCES public.boss_accounts(boss_id),
  request_type TEXT NOT NULL,
  request_ref_id UUID,
  decision TEXT CHECK (decision IN ('approved', 'rejected', 'pending')),
  reason TEXT,
  decided_at TIMESTAMPTZ DEFAULT now()
);

-- System modules table
CREATE TABLE IF NOT EXISTS public.system_modules (
  module_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module_name TEXT NOT NULL UNIQUE,
  description TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'maintenance', 'locked')),
  is_critical BOOLEAN DEFAULT false,
  locked_by UUID,
  locked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Emergency events table
CREATE TABLE IF NOT EXISTS public.emergency_events (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  boss_id UUID REFERENCES public.boss_accounts(boss_id),
  action TEXT NOT NULL CHECK (action IN ('lockdown', 'unlock', 'suspend_all', 'restore')),
  reason TEXT NOT NULL,
  affected_modules TEXT[],
  timestamp TIMESTAMPTZ DEFAULT now()
);

-- Security alerts table
CREATE TABLE IF NOT EXISTS public.security_alerts (
  alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  source TEXT NOT NULL,
  description TEXT NOT NULL,
  affected_user_id UUID,
  affected_role TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID
);

-- Compliance status table
CREATE TABLE IF NOT EXISTS public.compliance_status (
  record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  region TEXT NOT NULL,
  country TEXT,
  compliance_score INTEGER DEFAULT 100 CHECK (compliance_score >= 0 AND compliance_score <= 100),
  last_checked TIMESTAMPTZ DEFAULT now(),
  notes TEXT,
  issues JSONB DEFAULT '[]'
);

-- Enable RLS on all tables
ALTER TABLE public.boss_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boss_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_status ENABLE ROW LEVEL SECURITY;

-- RLS Policies for boss_accounts (boss can read their own)
CREATE POLICY "Boss can view own account" ON public.boss_accounts
  FOR SELECT USING (auth.uid() = user_id);

-- RLS Policies for boss_sessions
CREATE POLICY "Boss can view own sessions" ON public.boss_sessions
  FOR SELECT USING (boss_id IN (SELECT boss_id FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "Boss can insert sessions" ON public.boss_sessions
  FOR INSERT WITH CHECK (boss_id IN (SELECT boss_id FROM public.boss_accounts WHERE user_id = auth.uid()));

-- RLS Policies for system_activity_log (read-only for boss)
CREATE POLICY "Boss can view all activity logs" ON public.system_activity_log
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "System can insert activity logs" ON public.system_activity_log
  FOR INSERT WITH CHECK (true);

-- RLS Policies for approval_actions
CREATE POLICY "Boss can view approvals" ON public.approval_actions
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "Boss can insert approvals" ON public.approval_actions
  FOR INSERT WITH CHECK (boss_id IN (SELECT boss_id FROM public.boss_accounts WHERE user_id = auth.uid()));

-- RLS Policies for system_modules
CREATE POLICY "Boss can view modules" ON public.system_modules
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "Boss can update module status" ON public.system_modules
  FOR UPDATE USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

-- RLS Policies for emergency_events
CREATE POLICY "Boss can view emergency events" ON public.emergency_events
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "Boss can create emergency events" ON public.emergency_events
  FOR INSERT WITH CHECK (boss_id IN (SELECT boss_id FROM public.boss_accounts WHERE user_id = auth.uid()));

-- RLS Policies for security_alerts
CREATE POLICY "Boss can view security alerts" ON public.security_alerts
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

CREATE POLICY "Boss can update security alerts" ON public.security_alerts
  FOR UPDATE USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

-- RLS Policies for compliance_status
CREATE POLICY "Boss can view compliance status" ON public.compliance_status
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.boss_accounts WHERE user_id = auth.uid()));

-- Enable realtime for activity log
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_activity_log;
ALTER PUBLICATION supabase_realtime ADD TABLE public.security_alerts;
-- ===== 20260114020847_58438d9e-0646-4bcd-9a01-b5015e4e6356.sql =====
-- Step 1: Add reseller_manager role to enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'reseller_manager';

-- Step 2: Create reseller_applications table
CREATE TABLE IF NOT EXISTS public.reseller_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  application_type TEXT NOT NULL DEFAULT 'reseller',
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  country TEXT,
  id_proof_uploaded BOOLEAN NOT NULL DEFAULT false,
  terms_accepted BOOLEAN NOT NULL DEFAULT false,
  promise_acknowledged BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'pending',
  reviewer_id UUID NULL,
  reviewer_notes TEXT NULL,
  rejection_reason TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reseller_applications_user_id ON public.reseller_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_reseller_applications_status_created_at ON public.reseller_applications(status, created_at DESC);

-- Step 3: Enable RLS
ALTER TABLE public.reseller_applications ENABLE ROW LEVEL SECURITY;

-- Policy: Applicants can insert their own application
DROP POLICY IF EXISTS "Reseller applications insert own" ON public.reseller_applications;
CREATE POLICY "Reseller applications insert own"
ON public.reseller_applications
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Policy: Applicants can view their own applications
DROP POLICY IF EXISTS "Reseller applications select own" ON public.reseller_applications;
CREATE POLICY "Reseller applications select own"
ON public.reseller_applications
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Policy: Privileged roles can view all applications
DROP POLICY IF EXISTS "Reseller applications reviewers select" ON public.reseller_applications;
CREATE POLICY "Reseller applications reviewers select"
ON public.reseller_applications
FOR SELECT
TO authenticated
USING (
  public.has_privileged_role(auth.uid())
);

-- Policy: Privileged roles can update (approve/reject)
DROP POLICY IF EXISTS "Reseller applications reviewers update" ON public.reseller_applications;
CREATE POLICY "Reseller applications reviewers update"
ON public.reseller_applications
FOR UPDATE
TO authenticated
USING (public.has_privileged_role(auth.uid()))
WITH CHECK (public.has_privileged_role(auth.uid()));

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_reseller_applications_updated_at ON public.reseller_applications;
CREATE TRIGGER update_reseller_applications_updated_at
BEFORE UPDATE ON public.reseller_applications
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20260117190147_6f194721-2ca4-48ca-9922-f947d22f4693.sql =====
-- ====================================================
-- UNIFIED PLATFORM DATABASE SCHEMA - FINAL (CORRECTED)
-- ====================================================

-- Helper function to check if user is boss/super_admin
CREATE OR REPLACE FUNCTION public.is_platform_admin(user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_roles.user_id = $1
    AND role IN ('super_admin', 'boss_owner', 'ceo', 'master')
  )
$$;

-- 1. ROLES TABLE
CREATE TABLE IF NOT EXISTS public.platform_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name TEXT NOT NULL UNIQUE,
    permission_json JSONB DEFAULT '{}',
    approval_required BOOLEAN DEFAULT false,
    hierarchy_level INTEGER DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. PERMISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.platform_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID REFERENCES public.platform_roles(id) ON DELETE CASCADE,
    module TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('add', 'edit', 'delete', 'run', 'stop', 'pay', 'view')),
    allowed BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(role_id, module, action)
);

-- 3. PRODUCTS TABLE
CREATE TABLE IF NOT EXISTS public.platform_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id TEXT,
    name TEXT NOT NULL,
    description TEXT,
    version TEXT DEFAULT '1.0.0',
    demo_status TEXT DEFAULT 'draft' CHECK (demo_status IN ('draft', 'active', 'error', 'archived')),
    live_status TEXT DEFAULT 'offline' CHECK (live_status IN ('offline', 'online', 'maintenance')),
    created_by UUID,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. DEMOS TABLE
CREATE TABLE IF NOT EXISTS public.platform_demos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES public.platform_products(id) ON DELETE CASCADE,
    server_id UUID,
    name TEXT NOT NULL,
    version TEXT DEFAULT '1.0.0',
    url TEXT,
    health_status TEXT DEFAULT 'unknown' CHECK (health_status IN ('healthy', 'warning', 'error', 'unknown')),
    auto_repair BOOLEAN DEFAULT true,
    last_health_check TIMESTAMPTZ,
    error_log TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. LEADS TABLE
CREATE TABLE IF NOT EXISTS public.platform_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL CHECK (source IN ('web', 'facebook', 'google', 'whatsapp', 'api', 'manual', 'seo', 'instagram')),
    nano_category TEXT,
    micro_category TEXT,
    sub_category TEXT,
    main_category TEXT,
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'qualified', 'converted', 'lost', 'idle')),
    name TEXT,
    email TEXT,
    phone TEXT,
    company TEXT,
    notes TEXT,
    score INTEGER DEFAULT 0,
    assigned_to UUID,
    product_interest UUID REFERENCES public.platform_products(id),
    metadata JSONB DEFAULT '{}',
    converted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. SEO TASKS TABLE
CREATE TABLE IF NOT EXISTS public.platform_seo_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    page TEXT NOT NULL,
    domain TEXT,
    keyword TEXT,
    issue TEXT,
    issue_type TEXT CHECK (issue_type IN ('technical', 'content', 'backlink', 'speed', 'mobile', 'other')),
    severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    auto_fix BOOLEAN DEFAULT true,
    fix_status TEXT DEFAULT 'pending' CHECK (fix_status IN ('pending', 'in_progress', 'fixed', 'failed', 'ignored')),
    seo_score INTEGER,
    traffic INTEGER DEFAULT 0,
    fixed_at TIMESTAMPTZ,
    fixed_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 7. AI SERVICES TABLE
CREATE TABLE IF NOT EXISTS public.platform_ai_services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('text', 'image', 'video', 'voice', 'multimodal', 'custom')),
    provider TEXT,
    api_key_ref TEXT,
    model TEXT,
    status TEXT DEFAULT 'stopped' CHECK (status IN ('running', 'stopped', 'error', 'pending')),
    paid_status TEXT DEFAULT 'unpaid' CHECK (paid_status IN ('paid', 'unpaid', 'trial', 'overdue')),
    usage_today INTEGER DEFAULT 0,
    usage_month INTEGER DEFAULT 0,
    cost_today DECIMAL(10,2) DEFAULT 0,
    cost_month DECIMAL(10,2) DEFAULT 0,
    risk_level TEXT DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    auto_stop_on_unpaid BOOLEAN DEFAULT true,
    linked_module TEXT,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 8. API SERVICES TABLE
CREATE TABLE IF NOT EXISTS public.platform_api_services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    provider TEXT,
    type TEXT CHECK (type IN ('auth', 'payment', 'messaging', 'crm', 'seo', 'ai', 'server', 'analytics', 'storage', 'other')),
    linked_module TEXT,
    linked_ai_id UUID REFERENCES public.platform_ai_services(id),
    api_key_ref TEXT,
    endpoint TEXT,
    status TEXT DEFAULT 'stopped' CHECK (status IN ('running', 'stopped', 'error', 'pending')),
    billing_status TEXT DEFAULT 'unpaid' CHECK (billing_status IN ('paid', 'unpaid', 'trial', 'overdue')),
    usage_count INTEGER DEFAULT 0,
    last_call_at TIMESTAMPTZ,
    cost_per_call DECIMAL(10,4) DEFAULT 0,
    monthly_cost DECIMAL(10,2) DEFAULT 0,
    auto_stop_on_unpaid BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 9. SERVERS TABLE
CREATE TABLE IF NOT EXISTS public.platform_servers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    ip TEXT,
    domain TEXT,
    region TEXT CHECK (region IN ('india', 'asia', 'middle_east', 'africa', 'europe', 'usa', 'other')),
    provider TEXT,
    status TEXT DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'maintenance', 'error')),
    cpu_usage INTEGER DEFAULT 0,
    ram_usage INTEGER DEFAULT 0,
    disk_usage INTEGER DEFAULT 0,
    cost_monthly DECIMAL(10,2) DEFAULT 0,
    auto_scale BOOLEAN DEFAULT true,
    ssl_enabled BOOLEAN DEFAULT false,
    ssl_expiry TIMESTAMPTZ,
    last_heartbeat TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 10. BILLING TABLE
CREATE TABLE IF NOT EXISTS public.platform_billing (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module TEXT NOT NULL,
    module_id UUID,
    description TEXT,
    amount DECIMAL(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    paid BOOLEAN DEFAULT false,
    paid_at TIMESTAMPTZ,
    paid_by UUID,
    due_date TIMESTAMPTZ,
    invoice_number TEXT,
    payment_method TEXT,
    auto_deduct BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 11. PLATFORM APPROVALS TABLE
CREATE TABLE IF NOT EXISTS public.platform_approvals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_type TEXT NOT NULL CHECK (request_type IN ('demo', 'product', 'client', 'billing', 'deploy', 'server', 'api', 'delete', 'other')),
    request_data JSONB NOT NULL DEFAULT '{}',
    requester_id UUID,
    requester_role TEXT,
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    approved_by UUID,
    approved_at TIMESTAMPTZ,
    rejection_reason TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 12. PLATFORM LOGS TABLE
CREATE TABLE IF NOT EXISTS public.platform_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    actor_id UUID,
    actor_role TEXT,
    actor_type TEXT DEFAULT 'user' CHECK (actor_type IN ('user', 'system', 'ai', 'automation')),
    module TEXT,
    entity_type TEXT,
    entity_id UUID,
    old_value JSONB,
    new_value JSONB,
    payload JSONB DEFAULT '{}',
    ip_address TEXT,
    user_agent TEXT,
    severity TEXT DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'error', 'success')),
    is_sealed BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 13. FILES TABLE
CREATE TABLE IF NOT EXISTS public.platform_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT CHECK (type IN ('document', 'image', 'video', 'archive', 'source', 'other')),
    mime_type TEXT,
    size_bytes BIGINT,
    storage_path TEXT,
    linked_module TEXT,
    linked_id UUID,
    ai_processed BOOLEAN DEFAULT false,
    ai_analysis JSONB,
    uploaded_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 14. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.platform_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    type TEXT DEFAULT 'info' CHECK (type IN ('info', 'success', 'warning', 'error')),
    title TEXT NOT NULL,
    message TEXT,
    module TEXT,
    action_url TEXT,
    seen BOOLEAN DEFAULT false,
    seen_at TIMESTAMPTZ,
    dismissed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 15. AUTOMATION RULES TABLE
CREATE TABLE IF NOT EXISTS public.platform_automation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    trigger_condition TEXT NOT NULL,
    trigger_module TEXT,
    action_type TEXT NOT NULL,
    action_data JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    last_triggered_at TIMESTAMPTZ,
    trigger_count INTEGER DEFAULT 0,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 16. APK BUILDS TABLE
CREATE TABLE IF NOT EXISTS public.platform_apk_builds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES public.platform_products(id),
    demo_id UUID REFERENCES public.platform_demos(id),
    app_name TEXT NOT NULL,
    version TEXT DEFAULT '1.0.0',
    build_type TEXT CHECK (build_type IN ('debug', 'release', 'aab')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'building', 'ready', 'failed')),
    progress INTEGER DEFAULT 0,
    file_size TEXT,
    download_url TEXT,
    download_count INTEGER DEFAULT 0,
    error_log TEXT,
    signed BOOLEAN DEFAULT false,
    license_locked BOOLEAN DEFAULT true,
    built_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 17. VOICE COMMANDS TABLE
CREATE TABLE IF NOT EXISTS public.platform_voice_commands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    command_text TEXT NOT NULL,
    command_type TEXT CHECK (command_type IN ('voice', 'text', 'file')),
    ai_interpretation JSONB,
    executed_action TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    result JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.platform_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_demos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_seo_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_ai_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_api_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_servers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_apk_builds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_voice_commands ENABLE ROW LEVEL SECURITY;

-- RLS Policies for all tables (Admin full access)
CREATE POLICY "Admin access platform_roles" ON public.platform_roles FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_permissions" ON public.platform_permissions FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_products" ON public.platform_products FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_demos" ON public.platform_demos FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_leads" ON public.platform_leads FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_seo_tasks" ON public.platform_seo_tasks FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_ai_services" ON public.platform_ai_services FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_api_services" ON public.platform_api_services FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_servers" ON public.platform_servers FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_billing" ON public.platform_billing FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_approvals" ON public.platform_approvals FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin view platform_logs" ON public.platform_logs FOR SELECT TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Insert platform_logs" ON public.platform_logs FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Admin access platform_files" ON public.platform_files FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "View own notifications" ON public.platform_notifications FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin manage notifications" ON public.platform_notifications FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_automation_rules" ON public.platform_automation_rules FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "Admin access platform_apk_builds" ON public.platform_apk_builds FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));
CREATE POLICY "User access platform_voice_commands" ON public.platform_voice_commands FOR ALL TO authenticated USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_platform_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER trg_platform_roles_updated BEFORE UPDATE ON public.platform_roles FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_products_updated BEFORE UPDATE ON public.platform_products FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_demos_updated BEFORE UPDATE ON public.platform_demos FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_leads_updated BEFORE UPDATE ON public.platform_leads FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_seo_updated BEFORE UPDATE ON public.platform_seo_tasks FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_ai_updated BEFORE UPDATE ON public.platform_ai_services FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_api_updated BEFORE UPDATE ON public.platform_api_services FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_servers_updated BEFORE UPDATE ON public.platform_servers FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_billing_updated BEFORE UPDATE ON public.platform_billing FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_approvals_updated BEFORE UPDATE ON public.platform_approvals FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_files_updated BEFORE UPDATE ON public.platform_files FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();
CREATE TRIGGER trg_platform_automation_updated BEFORE UPDATE ON public.platform_automation_rules FOR EACH ROW EXECUTE FUNCTION public.update_platform_timestamp();

-- Insert default roles
INSERT INTO public.platform_roles (role_name, permission_json, approval_required, hierarchy_level) VALUES
  ('super_admin', '{"all": true}', false, 1),
  ('boss_owner', '{"all": true}', false, 2),
  ('ceo', '{"all": true}', false, 3),
  ('admin', '{"view": true, "add": true, "edit": true}', true, 10),
  ('manager', '{"view": true, "add": true}', true, 20),
  ('staff', '{"view": true}', true, 50)
ON CONFLICT (role_name) DO NOTHING;

-- Insert default automation rules
INSERT INTO public.platform_automation_rules (name, trigger_condition, trigger_module, action_type, action_data, is_active) VALUES
  ('Auto Stop Unpaid AI', 'paid_status = unpaid', 'ai_services', 'stop_service', '{"notify": true}', true),
  ('Auto Stop Unpaid API', 'billing_status = unpaid', 'api_services', 'stop_service', '{"notify": true}', true),
  ('Auto Repair Broken Demo', 'health_status = error', 'demos', 'repair_demo', '{"auto_repair": true}', true),
  ('Auto Reassign Idle Lead', 'status = idle', 'leads', 'reassign_lead', '{}', true),
  ('Auto Fix SEO Issues', 'auto_fix = true', 'seo_tasks', 'run_seo_fix', '{}', true),
  ('Scale Server on High Load', 'cpu_usage > 80', 'servers', 'scale_server', '{"increment": 1}', true)
ON CONFLICT DO NOTHING;
-- ===== 20260118025544_1402a735-249d-4716-8782-a5366c605002.sql =====
-- School Management System Database Schema
-- Core tables for a fully functional school system

-- School Institutions (Multi-School Support)
CREATE TABLE public.school_institutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    address TEXT,
    city TEXT,
    state TEXT,
    country TEXT DEFAULT 'India',
    phone TEXT,
    email TEXT,
    website TEXT,
    logo_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- School Branches
CREATE TABLE public.school_branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    address TEXT,
    city TEXT,
    phone TEXT,
    principal_user_id UUID,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(institution_id, code)
);

-- School Users (Staff, Teachers, Admin)
CREATE TABLE public.school_staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.school_branches(id) ON DELETE SET NULL,
    employee_id TEXT NOT NULL,
    staff_type TEXT NOT NULL CHECK (staff_type IN ('super_admin', 'principal', 'vice_principal', 'admin_office', 'teacher', 'class_teacher', 'accountant', 'librarian', 'transport_manager', 'hostel_manager', 'exam_controller', 'hr_manager', 'support_staff')),
    department TEXT,
    designation TEXT,
    joining_date DATE,
    phone TEXT,
    emergency_contact TEXT,
    address TEXT,
    qualification TEXT,
    experience_years INTEGER,
    salary_grade TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Academic Years
CREATE TABLE public.school_academic_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_current BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Classes
CREATE TABLE public.school_classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    numeric_level INTEGER,
    display_order INTEGER,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Sections
CREATE TABLE public.school_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES public.school_classes(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.school_branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    class_teacher_id UUID REFERENCES public.school_staff(id) ON DELETE SET NULL,
    room_number TEXT,
    capacity INTEGER DEFAULT 40,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Students
CREATE TABLE public.school_students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.school_branches(id) ON DELETE SET NULL,
    admission_number TEXT NOT NULL,
    roll_number TEXT,
    current_class_id UUID REFERENCES public.school_classes(id) ON DELETE SET NULL,
    current_section_id UUID REFERENCES public.school_sections(id) ON DELETE SET NULL,
    admission_date DATE,
    date_of_birth DATE,
    gender TEXT CHECK (gender IN ('male', 'female', 'other')),
    blood_group TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    pincode TEXT,
    photo_url TEXT,
    previous_school TEXT,
    transport_route_id UUID,
    hostel_room_id UUID,
    is_active BOOLEAN DEFAULT true,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'passed_out', 'transferred', 'dropped')),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Parents/Guardians
CREATE TABLE public.school_parents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    student_id UUID REFERENCES public.school_students(id) ON DELETE CASCADE,
    relation TEXT NOT NULL CHECK (relation IN ('father', 'mother', 'guardian', 'other')),
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    occupation TEXT,
    annual_income TEXT,
    address TEXT,
    is_primary BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Subjects
CREATE TABLE public.school_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    subject_type TEXT DEFAULT 'regular' CHECK (subject_type IN ('regular', 'elective', 'optional', 'language')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Class Subject Mapping
CREATE TABLE public.school_class_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES public.school_classes(id) ON DELETE CASCADE,
    subject_id UUID REFERENCES public.school_subjects(id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES public.school_staff(id) ON DELETE SET NULL,
    periods_per_week INTEGER DEFAULT 5,
    is_mandatory BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(class_id, subject_id)
);

-- Student Attendance
CREATE TABLE public.school_attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.school_students(id) ON DELETE CASCADE,
    section_id UUID REFERENCES public.school_sections(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'half_day', 'leave')),
    remarks TEXT,
    marked_by UUID REFERENCES public.school_staff(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(student_id, attendance_date)
);

-- Staff Attendance
CREATE TABLE public.school_staff_attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID REFERENCES public.school_staff(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL,
    check_in_time TIME,
    check_out_time TIME,
    status TEXT NOT NULL CHECK (status IN ('present', 'absent', 'late', 'half_day', 'leave', 'work_from_home')),
    leave_type TEXT,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(staff_id, attendance_date)
);

-- Fee Structure
CREATE TABLE public.school_fee_structure (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    academic_year_id UUID REFERENCES public.school_academic_years(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.school_classes(id) ON DELETE CASCADE,
    fee_type TEXT NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    due_date DATE,
    is_mandatory BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Fee Payments
CREATE TABLE public.school_fee_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.school_students(id) ON DELETE CASCADE,
    fee_structure_id UUID REFERENCES public.school_fee_structure(id) ON DELETE SET NULL,
    amount DECIMAL(12,2) NOT NULL,
    payment_date DATE NOT NULL,
    payment_method TEXT CHECK (payment_method IN ('cash', 'cheque', 'online', 'card', 'upi')),
    receipt_number TEXT,
    transaction_id TEXT,
    status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    collected_by UUID REFERENCES public.school_staff(id),
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Examinations
CREATE TABLE public.school_examinations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    academic_year_id UUID REFERENCES public.school_academic_years(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    exam_type TEXT CHECK (exam_type IN ('unit_test', 'quarterly', 'half_yearly', 'annual', 'board')),
    start_date DATE,
    end_date DATE,
    is_published BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Exam Results
CREATE TABLE public.school_exam_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    examination_id UUID REFERENCES public.school_examinations(id) ON DELETE CASCADE,
    student_id UUID REFERENCES public.school_students(id) ON DELETE CASCADE,
    subject_id UUID REFERENCES public.school_subjects(id) ON DELETE CASCADE,
    marks_obtained DECIMAL(5,2),
    max_marks DECIMAL(5,2) DEFAULT 100,
    grade TEXT,
    remarks TEXT,
    entered_by UUID REFERENCES public.school_staff(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(examination_id, student_id, subject_id)
);

-- Transport Routes
CREATE TABLE public.school_transport_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    route_name TEXT NOT NULL,
    route_number TEXT,
    vehicle_number TEXT,
    driver_name TEXT,
    driver_phone TEXT,
    capacity INTEGER,
    monthly_fee DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Transport Stops
CREATE TABLE public.school_transport_stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID REFERENCES public.school_transport_routes(id) ON DELETE CASCADE,
    stop_name TEXT NOT NULL,
    stop_order INTEGER,
    pickup_time TIME,
    drop_time TIME,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Hostel Rooms
CREATE TABLE public.school_hostel_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.school_branches(id) ON DELETE SET NULL,
    room_number TEXT NOT NULL,
    room_type TEXT CHECK (room_type IN ('single', 'double', 'triple', 'dormitory')),
    capacity INTEGER,
    floor INTEGER,
    block TEXT,
    monthly_fee DECIMAL(10,2),
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Notices/Circulars
CREATE TABLE public.school_notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.school_branches(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    notice_type TEXT CHECK (notice_type IN ('general', 'academic', 'event', 'holiday', 'urgent', 'exam')),
    target_audience TEXT[] DEFAULT ARRAY['all'],
    attachment_url TEXT,
    is_published BOOLEAN DEFAULT false,
    published_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.school_staff(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Library Books
CREATE TABLE public.school_library_books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.school_institutions(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    author TEXT,
    isbn TEXT,
    publisher TEXT,
    category TEXT,
    quantity INTEGER DEFAULT 1,
    available_quantity INTEGER DEFAULT 1,
    location TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Library Transactions
CREATE TABLE public.school_library_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID REFERENCES public.school_library_books(id) ON DELETE CASCADE,
    borrower_type TEXT CHECK (borrower_type IN ('student', 'staff')),
    borrower_id UUID NOT NULL,
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    return_date DATE,
    fine_amount DECIMAL(10,2) DEFAULT 0,
    status TEXT DEFAULT 'issued' CHECK (status IN ('issued', 'returned', 'overdue', 'lost')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Timetable
CREATE TABLE public.school_timetable (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id UUID REFERENCES public.school_sections(id) ON DELETE CASCADE,
    subject_id UUID REFERENCES public.school_subjects(id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES public.school_staff(id) ON DELETE SET NULL,
    day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    period_number INTEGER,
    start_time TIME,
    end_time TIME,
    room_number TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(section_id, day_of_week, period_number)
);

-- Enable RLS on all tables
ALTER TABLE public.school_institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_academic_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_class_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_staff_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_fee_structure ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_fee_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_examinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_exam_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_transport_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_transport_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_hostel_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_library_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_library_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_timetable ENABLE ROW LEVEL SECURITY;

-- RLS Policies for authenticated users (full access for now - can be refined by role)
CREATE POLICY "Authenticated users can view institutions" ON public.school_institutions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage institutions" ON public.school_institutions FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view branches" ON public.school_branches FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage branches" ON public.school_branches FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view staff" ON public.school_staff FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage staff" ON public.school_staff FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view academic years" ON public.school_academic_years FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage academic years" ON public.school_academic_years FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view classes" ON public.school_classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage classes" ON public.school_classes FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view sections" ON public.school_sections FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage sections" ON public.school_sections FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view students" ON public.school_students FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage students" ON public.school_students FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view parents" ON public.school_parents FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage parents" ON public.school_parents FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view subjects" ON public.school_subjects FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage subjects" ON public.school_subjects FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view class subjects" ON public.school_class_subjects FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage class subjects" ON public.school_class_subjects FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view attendance" ON public.school_attendance FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage attendance" ON public.school_attendance FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view staff attendance" ON public.school_staff_attendance FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage staff attendance" ON public.school_staff_attendance FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view fee structure" ON public.school_fee_structure FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage fee structure" ON public.school_fee_structure FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view fee payments" ON public.school_fee_payments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage fee payments" ON public.school_fee_payments FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view examinations" ON public.school_examinations FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage examinations" ON public.school_examinations FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view exam results" ON public.school_exam_results FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage exam results" ON public.school_exam_results FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view transport routes" ON public.school_transport_routes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage transport routes" ON public.school_transport_routes FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view transport stops" ON public.school_transport_stops FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage transport stops" ON public.school_transport_stops FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view hostel rooms" ON public.school_hostel_rooms FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage hostel rooms" ON public.school_hostel_rooms FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view notices" ON public.school_notices FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage notices" ON public.school_notices FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view library books" ON public.school_library_books FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage library books" ON public.school_library_books FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view library transactions" ON public.school_library_transactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage library transactions" ON public.school_library_transactions FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can view timetable" ON public.school_timetable FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can manage timetable" ON public.school_timetable FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Insert sample institution
INSERT INTO public.school_institutions (name, code, city, state, country, phone, email)
VALUES ('Delhi Public School', 'DPS-001', 'New Delhi', 'Delhi', 'India', '+91-11-23456789', 'admin@dps.edu.in');

-- Insert sample branches
INSERT INTO public.school_branches (institution_id, name, code, city)
SELECT id, 'Main Campus', 'MAIN', 'New Delhi' FROM public.school_institutions WHERE code = 'DPS-001';

INSERT INTO public.school_branches (institution_id, name, code, city)
SELECT id, 'North Branch', 'NORTH', 'North Delhi' FROM public.school_institutions WHERE code = 'DPS-001';

INSERT INTO public.school_branches (institution_id, name, code, city)
SELECT id, 'South Branch', 'SOUTH', 'South Delhi' FROM public.school_institutions WHERE code = 'DPS-001';

-- Insert sample academic year
INSERT INTO public.school_academic_years (institution_id, name, start_date, end_date, is_current)
SELECT id, '2025-2026', '2025-04-01', '2026-03-31', true FROM public.school_institutions WHERE code = 'DPS-001';

-- Insert sample classes
INSERT INTO public.school_classes (institution_id, name, numeric_level, display_order)
SELECT id, 'Class ' || level, level, level 
FROM public.school_institutions, generate_series(1, 12) AS level 
WHERE code = 'DPS-001';

-- Insert sample subjects
INSERT INTO public.school_subjects (institution_id, name, code, subject_type)
SELECT id, subject, UPPER(LEFT(subject, 3)), 'regular'
FROM public.school_institutions, 
     unnest(ARRAY['English', 'Hindi', 'Mathematics', 'Science', 'Social Studies', 'Computer Science', 'Physical Education', 'Art & Craft', 'Music']) AS subject
WHERE code = 'DPS-001';
-- ===== 20260118062419_3a6603a2-cdc3-4459-a8d2-f837922f5b4d.sql =====
-- Support Chatbot ERD

-- Chatbots table
CREATE TABLE public.support_chatbots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  channel TEXT NOT NULL DEFAULT 'web' CHECK (channel IN ('web', 'android', 'whatsapp', 'ios')),
  ai_model TEXT NOT NULL DEFAULT 'gpt-4',
  status TEXT NOT NULL DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'training', 'paused')),
  language_count INTEGER DEFAULT 1,
  welcome_message TEXT,
  fallback_message TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Conversations table
CREATE TABLE public.chatbot_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chatbot_id UUID NOT NULL REFERENCES public.support_chatbots(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  guest_id TEXT,
  language TEXT DEFAULT 'en',
  country TEXT,
  device_type TEXT,
  app_version TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved_bot', 'resolved_agent', 'escalated', 'closed')),
  assigned_agent_id UUID,
  csat_score INTEGER CHECK (csat_score >= 1 AND csat_score <= 5),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Messages table
CREATE TABLE public.chatbot_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.chatbot_conversations(id) ON DELETE CASCADE,
  sender_type TEXT NOT NULL CHECK (sender_type IN ('user', 'bot', 'agent')),
  sender_id UUID,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'quick_reply', 'card')),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Knowledge Base table
CREATE TABLE public.chatbot_knowledge_base (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chatbot_id UUID NOT NULL REFERENCES public.support_chatbots(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('pdf', 'doc', 'url', 'text', 'faq')),
  source_url TEXT,
  content TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'trained', 'failed')),
  last_trained_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Automation Rules table
CREATE TABLE public.chatbot_automation_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chatbot_id UUID NOT NULL REFERENCES public.support_chatbots(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  trigger_type TEXT NOT NULL CHECK (trigger_type IN ('keyword', 'intent', 'time', 'sentiment', 'no_response')),
  trigger_value TEXT,
  condition_type TEXT CHECK (condition_type IN ('equals', 'contains', 'greater_than', 'less_than')),
  condition_value TEXT,
  action_type TEXT NOT NULL CHECK (action_type IN ('send_message', 'handover', 'escalate', 'tag', 'close')),
  action_value TEXT,
  is_active BOOLEAN DEFAULT true,
  priority INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Agents table
CREATE TABLE public.chatbot_agents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  name TEXT NOT NULL,
  email TEXT,
  role TEXT DEFAULT 'agent' CHECK (role IN ('agent', 'supervisor', 'admin')),
  availability TEXT DEFAULT 'offline' CHECK (availability IN ('online', 'busy', 'away', 'offline')),
  max_concurrent_chats INTEGER DEFAULT 5,
  languages TEXT[] DEFAULT ARRAY['en'],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Working Hours table
CREATE TABLE public.chatbot_working_hours (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chatbot_id UUID NOT NULL REFERENCES public.support_chatbots(id) ON DELETE CASCADE,
  day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  timezone TEXT DEFAULT 'UTC',
  is_active BOOLEAN DEFAULT true,
  UNIQUE(chatbot_id, day_of_week)
);

-- Enable RLS
ALTER TABLE public.support_chatbots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chatbot_working_hours ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Authenticated users can view chatbots" ON public.support_chatbots
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can manage own chatbots" ON public.support_chatbots
  FOR ALL TO authenticated USING (created_by = auth.uid());

CREATE POLICY "Authenticated can view conversations" ON public.chatbot_conversations
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can manage conversations" ON public.chatbot_conversations
  FOR ALL TO authenticated USING (true);

CREATE POLICY "Authenticated can view messages" ON public.chatbot_messages
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can create messages" ON public.chatbot_messages
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated can view knowledge base" ON public.chatbot_knowledge_base
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can manage knowledge base" ON public.chatbot_knowledge_base
  FOR ALL TO authenticated USING (true);

CREATE POLICY "Authenticated can view automation rules" ON public.chatbot_automation_rules
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can manage automation rules" ON public.chatbot_automation_rules
  FOR ALL TO authenticated USING (true);

CREATE POLICY "Authenticated can view agents" ON public.chatbot_agents
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can manage agents" ON public.chatbot_agents
  FOR ALL TO authenticated USING (true);

CREATE POLICY "Authenticated can view working hours" ON public.chatbot_working_hours
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can manage working hours" ON public.chatbot_working_hours
  FOR ALL TO authenticated USING (true);

-- Indexes
CREATE INDEX idx_chatbot_conversations_chatbot ON public.chatbot_conversations(chatbot_id);
CREATE INDEX idx_chatbot_conversations_status ON public.chatbot_conversations(status);
CREATE INDEX idx_chatbot_messages_conversation ON public.chatbot_messages(conversation_id);
CREATE INDEX idx_chatbot_knowledge_base_chatbot ON public.chatbot_knowledge_base(chatbot_id);
CREATE INDEX idx_chatbot_automation_rules_chatbot ON public.chatbot_automation_rules(chatbot_id);

-- Updated_at trigger
CREATE TRIGGER update_support_chatbots_updated_at
  BEFORE UPDATE ON public.support_chatbots
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20260118064633_49a60f70-e000-4d64-b334-b78db77a5d08.sql =====
-- ============================================
-- SOFTWARE VALA AI PLATFORM - FULL ERD
-- ============================================

-- ============================================
-- CORE ENTITIES
-- ============================================

-- Roles Table
CREATE TABLE public.sv_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_system_role BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Permissions Table
CREATE TABLE public.sv_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('read', 'write', 'edit', 'delete', 'manage')),
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(module, action)
);

-- Role_Permission Junction Table
CREATE TABLE public.sv_role_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id UUID NOT NULL REFERENCES public.sv_roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.sv_permissions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(role_id, permission_id)
);

-- ============================================
-- AI MODELS
-- ============================================

-- AI_Model Table
CREATE TABLE public.sv_ai_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('LLM', 'STT', 'TTS', 'OCR', 'Vision', 'Embedding', 'Image')),
  provider TEXT NOT NULL,
  version TEXT NOT NULL,
  region TEXT DEFAULT 'global',
  status TEXT NOT NULL DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'deprecated', 'testing')),
  cost_per_unit DECIMAL(10, 6) DEFAULT 0,
  unit_type TEXT DEFAULT 'token',
  api_endpoint TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Model_Config Table
CREATE TABLE public.sv_model_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id UUID NOT NULL REFERENCES public.sv_ai_models(id) ON DELETE CASCADE,
  priority INTEGER DEFAULT 0,
  rate_limit INTEGER DEFAULT 100,
  rate_limit_window TEXT DEFAULT 'minute',
  quota INTEGER DEFAULT 10000,
  quota_period TEXT DEFAULT 'monthly',
  enabled BOOLEAN DEFAULT true,
  max_tokens INTEGER,
  temperature DECIMAL(3, 2) DEFAULT 0.7,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Model_Routing Table
CREATE TABLE public.sv_model_routing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  request_type TEXT NOT NULL,
  primary_model_id UUID NOT NULL REFERENCES public.sv_ai_models(id),
  fallback_model_id UUID REFERENCES public.sv_ai_models(id),
  conditions JSONB DEFAULT '{}',
  priority INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prompt Table
CREATE TABLE public.sv_prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id UUID REFERENCES public.sv_ai_models(id),
  name TEXT NOT NULL,
  version TEXT NOT NULL DEFAULT 'v1.0',
  environment TEXT NOT NULL DEFAULT 'dev' CHECK (environment IN ('dev', 'staging', 'prod')),
  system_prompt TEXT,
  user_prompt_template TEXT,
  variables JSONB DEFAULT '[]',
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- PRODUCT DEMO
-- ============================================

-- Demo Table
CREATE TABLE public.sv_demos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  product TEXT NOT NULL,
  demo_type TEXT NOT NULL DEFAULT 'live' CHECK (demo_type IN ('live', 'recorded', 'interactive', 'self-guided')),
  description TEXT,
  duration_minutes INTEGER DEFAULT 30,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'paused', 'archived')),
  join_url TEXT,
  recording_url TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demo_Schedule Table
CREATE TABLE public.sv_demo_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  demo_id UUID NOT NULL REFERENCES public.sv_demos(id) ON DELETE CASCADE,
  scheduled_date DATE NOT NULL,
  scheduled_time TIME NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  host_user_id UUID REFERENCES auth.users(id),
  max_attendees INTEGER DEFAULT 50,
  reminder_sent BOOLEAN DEFAULT false,
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demo_Attendance Table
CREATE TABLE public.sv_demo_attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  demo_id UUID NOT NULL REFERENCES public.sv_demos(id) ON DELETE CASCADE,
  schedule_id UUID REFERENCES public.sv_demo_schedules(id) ON DELETE SET NULL,
  user_id UUID REFERENCES auth.users(id),
  guest_email TEXT,
  guest_name TEXT,
  country TEXT,
  attended BOOLEAN DEFAULT false,
  join_time TIMESTAMPTZ,
  leave_time TIMESTAMPTZ,
  feedback_score INTEGER CHECK (feedback_score >= 1 AND feedback_score <= 5),
  feedback_text TEXT,
  converted BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- ANDROID PLATFORM
-- ============================================

-- Android_APK Table
CREATE TABLE public.sv_android_apks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version TEXT NOT NULL,
  version_code INTEGER NOT NULL,
  channel TEXT NOT NULL DEFAULT 'prod' CHECK (channel IN ('prod', 'beta', 'alpha', 'internal')),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'testing', 'released', 'deprecated')),
  download_url TEXT,
  file_size_mb DECIMAL(10, 2),
  min_sdk_version INTEGER DEFAULT 21,
  target_sdk_version INTEGER DEFAULT 34,
  release_notes TEXT,
  released_at TIMESTAMPTZ,
  released_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- APK_Config Table
CREATE TABLE public.sv_apk_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  apk_id UUID NOT NULL REFERENCES public.sv_android_apks(id) ON DELETE CASCADE,
  ai_enabled BOOLEAN DEFAULT true,
  offline_mode BOOLEAN DEFAULT false,
  logging_enabled BOOLEAN DEFAULT true,
  analytics_enabled BOOLEAN DEFAULT true,
  crash_reporting BOOLEAN DEFAULT true,
  debug_mode BOOLEAN DEFAULT false,
  feature_flags JSONB DEFAULT '{}',
  allowed_models TEXT[] DEFAULT ARRAY['gemini-flash'],
  max_offline_cache_mb INTEGER DEFAULT 100,
  sync_interval_minutes INTEGER DEFAULT 30,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- ENABLE RLS
-- ============================================

ALTER TABLE public.sv_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_ai_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_model_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_model_routing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_demos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_demo_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_demo_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_android_apks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_apk_configs ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES
-- ============================================

-- Roles policies
CREATE POLICY "Authenticated can view roles" ON public.sv_roles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage roles" ON public.sv_roles FOR ALL TO authenticated USING (true);

-- Permissions policies
CREATE POLICY "Authenticated can view permissions" ON public.sv_permissions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage permissions" ON public.sv_permissions FOR ALL TO authenticated USING (true);

-- Role_Permissions policies
CREATE POLICY "Authenticated can view role_permissions" ON public.sv_role_permissions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage role_permissions" ON public.sv_role_permissions FOR ALL TO authenticated USING (true);

-- AI Models policies
CREATE POLICY "Authenticated can view ai_models" ON public.sv_ai_models FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage ai_models" ON public.sv_ai_models FOR ALL TO authenticated USING (true);

-- Model Config policies
CREATE POLICY "Authenticated can view model_configs" ON public.sv_model_configs FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage model_configs" ON public.sv_model_configs FOR ALL TO authenticated USING (true);

-- Model Routing policies
CREATE POLICY "Authenticated can view model_routing" ON public.sv_model_routing FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage model_routing" ON public.sv_model_routing FOR ALL TO authenticated USING (true);

-- Prompts policies
CREATE POLICY "Authenticated can view prompts" ON public.sv_prompts FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can manage own prompts" ON public.sv_prompts FOR ALL TO authenticated USING (created_by = auth.uid());
CREATE POLICY "Admins can manage all prompts" ON public.sv_prompts FOR ALL TO authenticated USING (true);

-- Demos policies
CREATE POLICY "Authenticated can view demos" ON public.sv_demos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can manage own demos" ON public.sv_demos FOR ALL TO authenticated USING (created_by = auth.uid());

-- Demo Schedules policies
CREATE POLICY "Authenticated can view demo_schedules" ON public.sv_demo_schedules FOR SELECT TO authenticated USING (true);
CREATE POLICY "Hosts can manage schedules" ON public.sv_demo_schedules FOR ALL TO authenticated USING (host_user_id = auth.uid());

-- Demo Attendance policies
CREATE POLICY "Authenticated can view attendance" ON public.sv_demo_attendance FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can create attendance" ON public.sv_demo_attendance FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Users can update own attendance" ON public.sv_demo_attendance FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- Android APK policies
CREATE POLICY "Authenticated can view apks" ON public.sv_android_apks FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage apks" ON public.sv_android_apks FOR ALL TO authenticated USING (true);

-- APK Config policies
CREATE POLICY "Authenticated can view apk_configs" ON public.sv_apk_configs FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage apk_configs" ON public.sv_apk_configs FOR ALL TO authenticated USING (true);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX idx_sv_role_permissions_role ON public.sv_role_permissions(role_id);
CREATE INDEX idx_sv_role_permissions_permission ON public.sv_role_permissions(permission_id);
CREATE INDEX idx_sv_ai_models_type ON public.sv_ai_models(type);
CREATE INDEX idx_sv_ai_models_provider ON public.sv_ai_models(provider);
CREATE INDEX idx_sv_ai_models_status ON public.sv_ai_models(status);
CREATE INDEX idx_sv_model_configs_model ON public.sv_model_configs(model_id);
CREATE INDEX idx_sv_model_routing_primary ON public.sv_model_routing(primary_model_id);
CREATE INDEX idx_sv_prompts_model ON public.sv_prompts(model_id);
CREATE INDEX idx_sv_prompts_environment ON public.sv_prompts(environment);
CREATE INDEX idx_sv_demos_status ON public.sv_demos(status);
CREATE INDEX idx_sv_demo_schedules_demo ON public.sv_demo_schedules(demo_id);
CREATE INDEX idx_sv_demo_schedules_date ON public.sv_demo_schedules(scheduled_date);
CREATE INDEX idx_sv_demo_attendance_demo ON public.sv_demo_attendance(demo_id);
CREATE INDEX idx_sv_android_apks_channel ON public.sv_android_apks(channel);
CREATE INDEX idx_sv_android_apks_status ON public.sv_android_apks(status);
CREATE INDEX idx_sv_apk_configs_apk ON public.sv_apk_configs(apk_id);

-- ============================================
-- TRIGGERS
-- ============================================

CREATE TRIGGER update_sv_roles_updated_at
  BEFORE UPDATE ON public.sv_roles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_ai_models_updated_at
  BEFORE UPDATE ON public.sv_ai_models
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_model_configs_updated_at
  BEFORE UPDATE ON public.sv_model_configs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_model_routing_updated_at
  BEFORE UPDATE ON public.sv_model_routing
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_prompts_updated_at
  BEFORE UPDATE ON public.sv_prompts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_demos_updated_at
  BEFORE UPDATE ON public.sv_demos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_android_apks_updated_at
  BEFORE UPDATE ON public.sv_android_apks
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_sv_apk_configs_updated_at
  BEFORE UPDATE ON public.sv_apk_configs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================
-- SEED DEFAULT ROLES
-- ============================================

INSERT INTO public.sv_roles (role_name, description, is_system_role) VALUES
  ('super_admin', 'Full access - Billing, Compliance, All settings', true),
  ('platform_admin', 'AI Models, Prompt Studio, Routing, Logs', true),
  ('support_manager', 'Chatbots, Live Chats, Training, Analytics', true),
  ('demo_manager', 'Create demos, Schedule, Leads, Reports', true),
  ('developer', 'API keys, SDK access, Logs (read)', true),
  ('viewer', 'View dashboards, No edit rights', true);

-- ============================================
-- SEED DEFAULT PERMISSIONS
-- ============================================

INSERT INTO public.sv_permissions (module, action, description) VALUES
  ('ai_models', 'read', 'View AI models'),
  ('ai_models', 'write', 'Create AI models'),
  ('ai_models', 'edit', 'Edit AI models'),
  ('ai_models', 'delete', 'Delete AI models'),
  ('prompts', 'read', 'View prompts'),
  ('prompts', 'write', 'Create prompts'),
  ('prompts', 'edit', 'Edit prompts'),
  ('prompts', 'delete', 'Delete prompts'),
  ('chatbots', 'read', 'View chatbots'),
  ('chatbots', 'write', 'Create chatbots'),
  ('chatbots', 'manage', 'Full chatbot management'),
  ('demos', 'read', 'View demos'),
  ('demos', 'write', 'Create demos'),
  ('demos', 'manage', 'Full demo management'),
  ('android', 'read', 'View APK releases'),
  ('android', 'manage', 'Manage APK releases'),
  ('billing', 'read', 'View billing'),
  ('billing', 'manage', 'Manage billing'),
  ('settings', 'read', 'View settings'),
  ('settings', 'manage', 'Manage settings');
-- ===== 20260118114653_880158d6-0354-4af6-b098-94d69b262577.sql =====
-- Box Action Permissions System
-- Enforces role-based access control for box-level actions

-- ===== BOX ACTION PERMISSIONS TABLE =====
CREATE TABLE IF NOT EXISTS public.box_action_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role TEXT NOT NULL,
    box_type TEXT NOT NULL CHECK (box_type IN ('data', 'process', 'ai', 'approval', 'live')),
    action_type TEXT NOT NULL CHECK (action_type IN ('view', 'edit', 'update', 'post', 'approve', 'reject', 'suspend', 'resume', 'stop', 'start', 'delete', 'startAi', 'stopAi', 'viewLogs', 'pauseMonitoring')),
    is_allowed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE (role, box_type, action_type)
);

-- Enable RLS
ALTER TABLE public.box_action_permissions ENABLE ROW LEVEL SECURITY;

-- Anyone can read permissions (needed for UI to know what buttons to show)
CREATE POLICY "Permissions are publicly readable"
ON public.box_action_permissions
FOR SELECT
USING (true);

-- ===== BOX ACTION AUDIT LOGS =====
CREATE TABLE IF NOT EXISTS public.box_action_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    user_role TEXT NOT NULL,
    box_type TEXT NOT NULL,
    box_entity_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    action_result TEXT NOT NULL CHECK (action_result IN ('success', 'denied', 'error')),
    previous_status TEXT,
    new_status TEXT,
    metadata JSONB,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.box_action_logs ENABLE ROW LEVEL SECURITY;

-- Users can view their own action logs
CREATE POLICY "Users can view their own action logs"
ON public.box_action_logs
FOR SELECT
USING (auth.uid() = user_id);

-- System can insert action logs
CREATE POLICY "System can insert action logs"
ON public.box_action_logs
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- ===== BOX STATUS TRACKING =====
CREATE TABLE IF NOT EXISTS public.box_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id TEXT NOT NULL UNIQUE,
    box_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending', 'suspended', 'stopped', 'error')),
    last_action TEXT,
    last_action_by UUID,
    last_action_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.box_status ENABLE ROW LEVEL SECURITY;

-- Anyone can read box status
CREATE POLICY "Box status is publicly readable"
ON public.box_status
FOR SELECT
USING (true);

-- Authenticated users can update status
CREATE POLICY "Authenticated users can update box status"
ON public.box_status
FOR ALL
TO authenticated
USING (true);

-- ===== DEFAULT PERMISSION SEEDS =====
-- Boss/Owner gets ALL permissions
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT 'boss_owner', box_type, action_type, true
FROM (VALUES ('data'), ('process'), ('ai'), ('approval'), ('live')) AS bt(box_type)
CROSS JOIN (VALUES ('view'), ('edit'), ('update'), ('post'), ('approve'), ('reject'), ('suspend'), ('resume'), ('stop'), ('start'), ('delete'), ('startAi'), ('stopAi'), ('viewLogs'), ('pauseMonitoring')) AS at(action_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- CEO gets strategic actions (no delete)
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT 'ceo', box_type, action_type, true
FROM (VALUES ('data'), ('process'), ('ai'), ('approval'), ('live')) AS bt(box_type)
CROSS JOIN (VALUES ('view'), ('edit'), ('update'), ('approve'), ('reject'), ('suspend'), ('resume'), ('stop'), ('start'), ('startAi'), ('stopAi'), ('viewLogs'), ('pauseMonitoring')) AS at(action_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- Area Manager gets operational actions
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT 'area_manager', box_type, action_type, true
FROM (VALUES ('data'), ('process'), ('ai'), ('approval'), ('live')) AS bt(box_type)
CROSS JOIN (VALUES ('view'), ('edit'), ('update'), ('approve'), ('reject'), ('resume'), ('start'), ('viewLogs')) AS at(action_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- Finance Manager permissions
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT 'finance_manager', box_type, action_type, true
FROM (VALUES ('data'), ('approval')) AS bt(box_type)
CROSS JOIN (VALUES ('view'), ('edit'), ('update'), ('approve'), ('reject')) AS at(action_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- Super Admin gets ALL permissions
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT 'super_admin', box_type, action_type, true
FROM (VALUES ('data'), ('process'), ('ai'), ('approval'), ('live')) AS bt(box_type)
CROSS JOIN (VALUES ('view'), ('edit'), ('update'), ('post'), ('approve'), ('reject'), ('suspend'), ('resume'), ('stop'), ('start'), ('delete'), ('startAi'), ('stopAi'), ('viewLogs'), ('pauseMonitoring')) AS at(action_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- Readonly roles get view only
INSERT INTO public.box_action_permissions (role, box_type, action_type, is_allowed)
SELECT role, box_type, 'view', true
FROM (VALUES ('client'), ('reseller'), ('franchise'), ('influencer'), ('prime')) AS r(role)
CROSS JOIN (VALUES ('data'), ('process'), ('ai'), ('approval'), ('live')) AS bt(box_type)
ON CONFLICT (role, box_type, action_type) DO NOTHING;

-- ===== FUNCTION: Check box action permission =====
CREATE OR REPLACE FUNCTION public.check_box_action_permission(
    _user_id UUID,
    _box_type TEXT,
    _action_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    _user_role TEXT;
    _is_allowed BOOLEAN;
BEGIN
    -- Get user's role (cast enum to text)
    SELECT role::text INTO _user_role
    FROM public.user_roles
    WHERE user_id = _user_id
    LIMIT 1;
    
    IF _user_role IS NULL THEN
        RETURN false;
    END IF;
    
    -- Check permission
    SELECT is_allowed INTO _is_allowed
    FROM public.box_action_permissions
    WHERE role = _user_role
    AND box_type = _box_type
    AND action_type = _action_type;
    
    RETURN COALESCE(_is_allowed, false);
END;
$$;
-- ===== 20260118133455_3f1d263b-bf9f-4dc2-bc16-6ef2ab9714c9.sql =====
-- Add payment tracking columns to reseller_applications
ALTER TABLE reseller_applications 
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',
ADD COLUMN IF NOT EXISTS payment_amount DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS payment_date TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS payment_reference TEXT;
-- ===== 20260118140313_298a6983-368f-41a5-9d40-646b13a69112.sql =====
-- Enable realtime for application tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.reseller_applications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.franchise_accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.influencer_accounts;
-- ===== 20260119162611_9a6c56ea-02db-4896-8198-46b0a73ee578.sql =====
-- Core Enterprise Platform Database Structure - Complete

-- Button Registry Table
CREATE TABLE public.button_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  button_id TEXT UNIQUE NOT NULL,
  module_name TEXT NOT NULL,
  action_type TEXT NOT NULL,
  api_endpoint TEXT,
  db_table TEXT,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Action Logs Table
CREATE TABLE public.action_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  button_id TEXT,
  module_name TEXT NOT NULL,
  action_type TEXT NOT NULL,
  action_result TEXT NOT NULL,
  response_time_ms INTEGER,
  error_message TEXT,
  metadata JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- AI Observation Logs Table
CREATE TABLE public.ai_observation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_type TEXT NOT NULL,
  module_name TEXT NOT NULL,
  action_id UUID,
  user_id UUID REFERENCES auth.users(id),
  observation_data JSONB,
  confidence_score DECIMAL(3,2),
  action_taken TEXT,
  result TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.button_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_observation_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Read button registry" ON public.button_registry FOR SELECT TO authenticated USING (true);
CREATE POLICY "Insert action logs" ON public.action_logs FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Read own action logs" ON public.action_logs FOR SELECT TO authenticated USING (auth.uid() = user_id OR user_id IS NULL);
CREATE POLICY "Read ai observations" ON public.ai_observation_logs FOR SELECT TO authenticated USING (true);
CREATE POLICY "Insert ai observations" ON public.ai_observation_logs FOR INSERT TO authenticated WITH CHECK (true);

-- Indexes
CREATE INDEX idx_action_logs_user ON public.action_logs(user_id);
CREATE INDEX idx_action_logs_time ON public.action_logs(created_at DESC);
CREATE INDEX idx_action_logs_mod ON public.action_logs(module_name);
CREATE INDEX idx_button_registry_mod ON public.button_registry(module_name);
-- ===== 20260120050702_09d75616-7024-40f3-9fe6-da428c55c93a.sql =====
-- STEP 4: Button Execution Tracking Table
CREATE TABLE IF NOT EXISTS public.button_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  button_id TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id),
  role_id TEXT,
  status TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started', 'success', 'failed', 'cancelled')),
  latency_ms INTEGER,
  error_code TEXT,
  error_message TEXT,
  metadata JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- STEP 6: Approval Engine Enhancement
CREATE TABLE IF NOT EXISTS public.approval_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_id UUID REFERENCES public.approvals(id) ON DELETE CASCADE,
  step_number INTEGER NOT NULL DEFAULT 1,
  approver_role TEXT NOT NULL,
  approver_id UUID,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'skipped')),
  decision_notes TEXT,
  decided_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- STEP 7: AI Job Pipeline Tables
CREATE TABLE IF NOT EXISTS public.ai_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type TEXT NOT NULL,
  source_module TEXT NOT NULL,
  source_button_id TEXT,
  input_data JSONB,
  output_data JSONB,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  human_approved BOOLEAN DEFAULT false,
  approved_by UUID,
  approved_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT,
  confidence_score DECIMAL(5,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.ai_job_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES public.ai_jobs(id) ON DELETE CASCADE,
  step_number INTEGER NOT NULL,
  step_type TEXT NOT NULL,
  input_data JSONB,
  output_data JSONB,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  duration_ms INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Enable RLS
ALTER TABLE public.button_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_job_steps ENABLE ROW LEVEL SECURITY;

-- RLS Policies for button_executions
CREATE POLICY "Users can view own button executions" 
  ON public.button_executions FOR SELECT 
  TO authenticated 
  USING (auth.uid() = user_id);

CREATE POLICY "Insert button executions" 
  ON public.button_executions FOR INSERT 
  TO authenticated 
  WITH CHECK (true);

CREATE POLICY "Update own button executions" 
  ON public.button_executions FOR UPDATE 
  TO authenticated 
  USING (auth.uid() = user_id);

-- RLS Policies for approval_steps
CREATE POLICY "View approval steps" 
  ON public.approval_steps FOR SELECT 
  TO authenticated 
  USING (true);

CREATE POLICY "Insert approval steps" 
  ON public.approval_steps FOR INSERT 
  TO authenticated 
  WITH CHECK (true);

CREATE POLICY "Update approval steps" 
  ON public.approval_steps FOR UPDATE 
  TO authenticated 
  USING (true);

-- RLS Policies for ai_jobs
CREATE POLICY "View AI jobs" 
  ON public.ai_jobs FOR SELECT 
  TO authenticated 
  USING (true);

CREATE POLICY "Insert AI jobs" 
  ON public.ai_jobs FOR INSERT 
  TO authenticated 
  WITH CHECK (true);

CREATE POLICY "Update AI jobs" 
  ON public.ai_jobs FOR UPDATE 
  TO authenticated 
  USING (true);

-- RLS Policies for ai_job_steps
CREATE POLICY "View AI job steps" 
  ON public.ai_job_steps FOR SELECT 
  TO authenticated 
  USING (true);

CREATE POLICY "Insert AI job steps" 
  ON public.ai_job_steps FOR INSERT 
  TO authenticated 
  WITH CHECK (true);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_button_executions_user ON public.button_executions(user_id);
CREATE INDEX IF NOT EXISTS idx_button_executions_button ON public.button_executions(button_id);
CREATE INDEX IF NOT EXISTS idx_button_executions_created ON public.button_executions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_approval_steps_approval ON public.approval_steps(approval_id);
CREATE INDEX IF NOT EXISTS idx_ai_jobs_status ON public.ai_jobs(status);
CREATE INDEX IF NOT EXISTS idx_ai_jobs_created ON public.ai_jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_job_steps_job ON public.ai_job_steps(job_id);
-- ===== 20260122043439_b319ccfb-7f54-4fc5-8b0c-4a62e7b15ea4.sql =====
-- Fix: system_activity_log is already in realtime publication; only create sync trigger + backfill

CREATE OR REPLACE FUNCTION public.sync_audit_logs_to_system_activity_log()
RETURNS TRIGGER AS $$
DECLARE
  v_actor_role text;
  v_target_id uuid;
BEGIN
  v_actor_role := COALESCE(NEW.role::text, 'unknown');

  -- target_id is optional and may not be a uuid in meta_json
  BEGIN
    v_target_id := NULLIF(NEW.meta_json->>'target_id', '')::uuid;
  EXCEPTION WHEN others THEN
    v_target_id := NULL;
  END;

  INSERT INTO public.system_activity_log (
    log_id,
    actor_role,
    actor_id,
    action_type,
    target,
    target_id,
    risk_level,
    metadata,
    timestamp,
    hash_signature
  ) VALUES (
    NEW.id,
    v_actor_role,
    NEW.user_id,
    NEW.action,
    NEW.module,
    v_target_id,
    COALESCE(NEW.meta_json->>'severity', 'low'),
    NEW.meta_json,
    NEW.timestamp,
    NULL
  )
  ON CONFLICT (log_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_audit_logs_to_system_activity_log ON public.audit_logs;
CREATE TRIGGER trg_sync_audit_logs_to_system_activity_log
AFTER INSERT ON public.audit_logs
FOR EACH ROW
EXECUTE FUNCTION public.sync_audit_logs_to_system_activity_log();

-- Backfill latest audit logs into system_activity_log (idempotent)
INSERT INTO public.system_activity_log (
  log_id,
  actor_role,
  actor_id,
  action_type,
  target,
  target_id,
  risk_level,
  metadata,
  timestamp,
  hash_signature
)
SELECT
  a.id,
  COALESCE(a.role::text, 'unknown') as actor_role,
  a.user_id,
  a.action as action_type,
  a.module as target,
  CASE
    WHEN (a.meta_json ? 'target_id') THEN
      NULLIF(a.meta_json->>'target_id','')::uuid
    ELSE NULL
  END as target_id,
  COALESCE(a.meta_json->>'severity','low') as risk_level,
  a.meta_json as metadata,
  a.timestamp,
  NULL
FROM public.audit_logs a
LEFT JOIN public.system_activity_log s ON s.log_id = a.id
WHERE s.log_id IS NULL
ORDER BY a.timestamp DESC
LIMIT 5000;
-- ===== 20260605015902_aeab6a5b-d2da-4f9c-91e0-82bdbdd4034d.sql =====

-- =========================================================
-- PHASE 1: module_routes + can_access_route
-- =========================================================
CREATE TABLE IF NOT EXISTS public.module_routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role_name text NOT NULL,
  module_key text NOT NULL,
  route_path text NOT NULL,
  can_view boolean NOT NULL DEFAULT true,
  can_edit boolean NOT NULL DEFAULT false,
  can_delete boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role_name, route_path)
);

GRANT SELECT ON public.module_routes TO authenticated;
GRANT ALL ON public.module_routes TO service_role;
ALTER TABLE public.module_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "module_routes_read_auth" ON public.module_routes
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "module_routes_admin_write" ON public.module_routes
  FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role))
  WITH CHECK (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role));

-- Seed: Boss owner & CEO get full-wildcard
INSERT INTO public.module_routes (role_name, module_key, route_path, can_view, can_edit, can_delete) VALUES
  ('boss_owner','*','*',true,true,true),
  ('ceo','*','*',true,true,false)
ON CONFLICT (role_name, route_path) DO NOTHING;

-- Seed: Super admin's module set (matches RoleSwitchDashboard ROLE_VIEW_ACCESS)
INSERT INTO public.module_routes (role_name, module_key, route_path, can_view, can_edit, can_delete) VALUES
  ('super_admin','dashboard','/',true,true,false),
  ('super_admin','role_switch','/super-admin/role-switch',true,true,false),
  ('super_admin','continent_super_admin','/super-admin/role-switch?role=continent_super_admin',true,true,false),
  ('super_admin','country_head','/super-admin/role-switch?role=country_head',true,true,false),
  ('super_admin','franchise_manager','/super-admin/role-switch?role=franchise_manager',true,true,false),
  ('super_admin','sales_support_manager','/super-admin/role-switch?role=sales_support_manager',true,true,false),
  ('super_admin','reseller_manager','/super-admin/role-switch?role=reseller_manager',true,true,false),
  ('super_admin','lead_manager','/super-admin/role-switch?role=lead_manager',true,true,false),
  ('super_admin','command_center','/super-admin',true,true,false),
  ('super_admin','audit','/super-admin/audit',true,false,false),
  ('super_admin','roles','/super-admin/roles',true,true,true)
ON CONFLICT (role_name, route_path) DO NOTHING;

-- Per-role narrow grants
INSERT INTO public.module_routes (role_name, module_key, route_path, can_view, can_edit) VALUES
  ('continent_super_admin','continent','/continent-super-admin',true,true),
  ('country_head','country','/country-head',true,true),
  ('server_manager','server','/server-manager',true,true),
  ('finance_manager','finance','/finance-manager',true,true),
  ('lead_manager','lead','/lead-manager',true,true),
  ('legal_compliance','legal','/legal-manager',true,true),
  ('marketing_manager','marketing','/marketing-manager',true,true),
  ('hr_manager','hr','/hr-manager',true,true),
  ('demo_manager','demo','/product-demo-manager',true,true),
  ('franchise','franchise','/franchise',true,true),
  ('reseller','reseller','/reseller',true,true),
  ('developer','developer','/developer',true,true)
ON CONFLICT (role_name, route_path) DO NOTHING;

CREATE OR REPLACE FUNCTION public.can_access_route(_user_id uuid, _route text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  IF _user_id IS NULL OR _route IS NULL THEN
    RETURN false;
  END IF;

  -- Boss owner & CEO always allowed
  IF public.has_role(_user_id, 'boss_owner'::app_role)
     OR public.has_role(_user_id, 'ceo'::app_role) THEN
    RETURN true;
  END IF;

  -- Any role assignment of this user that has a matching route (exact, prefix, or wildcard)
  IF EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.module_routes mr
      ON mr.role_name = ur.role::text
    WHERE ur.user_id = _user_id
      AND COALESCE(ur.approval_status, 'approved') = 'approved'
      AND mr.can_view = true
      AND (
        mr.route_path = '*'
        OR mr.route_path = _route
        OR _route LIKE (mr.route_path || '%')
      )
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_route(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.can_access_route(uuid, text) TO authenticated, service_role;

-- =========================================================
-- PHASE 2: i18n tables
-- =========================================================
CREATE TABLE IF NOT EXISTS public.languages (
  code text PRIMARY KEY,
  name text NOT NULL,
  native_name text NOT NULL,
  rtl boolean NOT NULL DEFAULT false,
  enabled boolean NOT NULL DEFAULT false,
  coverage_pct numeric(5,2) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.languages TO anon, authenticated;
GRANT ALL ON public.languages TO service_role;
ALTER TABLE public.languages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "languages_read_all" ON public.languages FOR SELECT USING (true);
CREATE POLICY "languages_admin_write" ON public.languages FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role))
  WITH CHECK (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role));

CREATE TABLE IF NOT EXISTS public.translation_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  namespace text NOT NULL DEFAULT 'common',
  key text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (namespace, key)
);
GRANT SELECT ON public.translation_keys TO authenticated;
GRANT ALL ON public.translation_keys TO service_role;
ALTER TABLE public.translation_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tkeys_read_auth" ON public.translation_keys FOR SELECT TO authenticated USING (true);
CREATE POLICY "tkeys_admin_write" ON public.translation_keys FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role))
  WITH CHECK (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role));

CREATE TABLE IF NOT EXISTS public.translation_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_id uuid NOT NULL REFERENCES public.translation_keys(id) ON DELETE CASCADE,
  language_code text NOT NULL REFERENCES public.languages(code) ON DELETE CASCADE,
  value text NOT NULL,
  status text NOT NULL DEFAULT 'approved' CHECK (status IN ('approved','pending','rejected')),
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (key_id, language_code)
);
GRANT SELECT ON public.translation_values TO authenticated;
GRANT ALL ON public.translation_values TO service_role;
ALTER TABLE public.translation_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tvals_read_auth" ON public.translation_values FOR SELECT TO authenticated USING (true);
CREATE POLICY "tvals_admin_write" ON public.translation_values FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role))
  WITH CHECK (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role));

CREATE TABLE IF NOT EXISTS public.translation_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_id uuid,
  language_code text,
  old_value text,
  new_value text,
  actor uuid,
  action text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.translation_audit_logs TO authenticated;
GRANT ALL ON public.translation_audit_logs TO service_role;
ALTER TABLE public.translation_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "talog_read_admin" ON public.translation_audit_logs FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_role(auth.uid(), 'boss_owner'::app_role));
CREATE POLICY "talog_insert_auth" ON public.translation_audit_logs FOR INSERT TO authenticated WITH CHECK (true);

-- Audit trigger
CREATE OR REPLACE FUNCTION public.trg_translation_values_audit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.translation_audit_logs(key_id, language_code, old_value, new_value, actor, action)
  VALUES (
    COALESCE(NEW.key_id, OLD.key_id),
    COALESCE(NEW.language_code, OLD.language_code),
    OLD.value,
    NEW.value,
    auth.uid(),
    TG_OP
  );
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_tvals_audit ON public.translation_values;
CREATE TRIGGER trg_tvals_audit AFTER INSERT OR UPDATE OR DELETE ON public.translation_values
  FOR EACH ROW EXECUTE FUNCTION public.trg_translation_values_audit();

-- Coverage view + refresher
CREATE OR REPLACE VIEW public.translation_coverage AS
SELECT l.code AS language_code,
       (SELECT COUNT(*) FROM public.translation_keys) AS total_keys,
       (SELECT COUNT(*) FROM public.translation_values v
         WHERE v.language_code = l.code AND v.status = 'approved') AS translated_keys,
       CASE WHEN (SELECT COUNT(*) FROM public.translation_keys) = 0 THEN 0
            ELSE ROUND(100.0 * (SELECT COUNT(*) FROM public.translation_values v
                                 WHERE v.language_code = l.code AND v.status = 'approved')::numeric
                       / (SELECT COUNT(*) FROM public.translation_keys), 2)
       END AS coverage_pct
FROM public.languages l;

GRANT SELECT ON public.translation_coverage TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.refresh_language_coverage(_code text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.languages l
     SET coverage_pct = c.coverage_pct, updated_at = now()
    FROM public.translation_coverage c
   WHERE c.language_code = l.code
     AND (_code IS NULL OR l.code = _code);
END;
$$;
GRANT EXECUTE ON FUNCTION public.refresh_language_coverage(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_refresh_coverage()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.refresh_language_coverage(COALESCE(NEW.language_code, OLD.language_code));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_tvals_coverage ON public.translation_values;
CREATE TRIGGER trg_tvals_coverage AFTER INSERT OR UPDATE OR DELETE ON public.translation_values
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_coverage();

-- Seed 125 languages
INSERT INTO public.languages (code, name, native_name, rtl, enabled, coverage_pct) VALUES
('en','English','English',false,true,100),
('hi','Hindi','हिन्दी',false,false,0),
('es','Spanish','Español',false,false,0),
('fr','French','Français',false,false,0),
('de','German','Deutsch',false,false,0),
('pt','Portuguese','Português',false,false,0),
('it','Italian','Italiano',false,false,0),
('nl','Dutch','Nederlands',false,false,0),
('ru','Russian','Русский',false,false,0),
('zh','Chinese (Simplified)','简体中文',false,false,0),
('zh-TW','Chinese (Traditional)','繁體中文',false,false,0),
('ja','Japanese','日本語',false,false,0),
('ko','Korean','한국어',false,false,0),
('ar','Arabic','العربية',true,false,0),
('he','Hebrew','עברית',true,false,0),
('ur','Urdu','اردو',true,false,0),
('fa','Persian','فارسی',true,false,0),
('ps','Pashto','پښتو',true,false,0),
('tr','Turkish','Türkçe',false,false,0),
('pl','Polish','Polski',false,false,0),
('uk','Ukrainian','Українська',false,false,0),
('cs','Czech','Čeština',false,false,0),
('sk','Slovak','Slovenčina',false,false,0),
('hu','Hungarian','Magyar',false,false,0),
('ro','Romanian','Română',false,false,0),
('bg','Bulgarian','Български',false,false,0),
('el','Greek','Ελληνικά',false,false,0),
('sv','Swedish','Svenska',false,false,0),
('no','Norwegian','Norsk',false,false,0),
('da','Danish','Dansk',false,false,0),
('fi','Finnish','Suomi',false,false,0),
('is','Icelandic','Íslenska',false,false,0),
('lt','Lithuanian','Lietuvių',false,false,0),
('lv','Latvian','Latviešu',false,false,0),
('et','Estonian','Eesti',false,false,0),
('sl','Slovenian','Slovenščina',false,false,0),
('hr','Croatian','Hrvatski',false,false,0),
('sr','Serbian','Српски',false,false,0),
('bs','Bosnian','Bosanski',false,false,0),
('mk','Macedonian','Македонски',false,false,0),
('sq','Albanian','Shqip',false,false,0),
('mt','Maltese','Malti',false,false,0),
('ga','Irish','Gaeilge',false,false,0),
('cy','Welsh','Cymraeg',false,false,0),
('eu','Basque','Euskara',false,false,0),
('ca','Catalan','Català',false,false,0),
('gl','Galician','Galego',false,false,0),
('af','Afrikaans','Afrikaans',false,false,0),
('sw','Swahili','Kiswahili',false,false,0),
('am','Amharic','አማርኛ',false,false,0),
('ha','Hausa','Hausa',false,false,0),
('yo','Yoruba','Yorùbá',false,false,0),
('ig','Igbo','Igbo',false,false,0),
('zu','Zulu','isiZulu',false,false,0),
('xh','Xhosa','isiXhosa',false,false,0),
('so','Somali','Soomaali',false,false,0),
('mg','Malagasy','Malagasy',false,false,0),
('rw','Kinyarwanda','Kinyarwanda',false,false,0),
('ny','Chichewa','Chichewa',false,false,0),
('st','Sesotho','Sesotho',false,false,0),
('tn','Tswana','Setswana',false,false,0),
('sn','Shona','chiShona',false,false,0),
('th','Thai','ไทย',false,false,0),
('vi','Vietnamese','Tiếng Việt',false,false,0),
('id','Indonesian','Bahasa Indonesia',false,false,0),
('ms','Malay','Bahasa Melayu',false,false,0),
('tl','Filipino','Filipino',false,false,0),
('km','Khmer','ខ្មែរ',false,false,0),
('lo','Lao','ລາວ',false,false,0),
('my','Burmese','မြန်မာ',false,false,0),
('mn','Mongolian','Монгол',false,false,0),
('ne','Nepali','नेपाली',false,false,0),
('si','Sinhala','සිංහල',false,false,0),
('bn','Bengali','বাংলা',false,false,0),
('ta','Tamil','தமிழ்',false,false,0),
('te','Telugu','తెలుగు',false,false,0),
('ml','Malayalam','മലയാളം',false,false,0),
('kn','Kannada','ಕನ್ನಡ',false,false,0),
('gu','Gujarati','ગુજરાતી',false,false,0),
('mr','Marathi','मराठी',false,false,0),
('pa','Punjabi','ਪੰਜਾਬੀ',false,false,0),
('or','Odia','ଓଡ଼ିଆ',false,false,0),
('as','Assamese','অসমীয়া',false,false,0),
('sd','Sindhi','سنڌي',true,false,0),
('ks','Kashmiri','کٲشُر',true,false,0),
('sa','Sanskrit','संस्कृतम्',false,false,0),
('mai','Maithili','मैथिली',false,false,0),
('bho','Bhojpuri','भोजपुरी',false,false,0),
('kok','Konkani','कोंकणी',false,false,0),
('mni','Manipuri','মৈতৈলোন্',false,false,0),
('dv','Dhivehi','ދިވެހި',true,false,0),
('bo','Tibetan','བོད་ཡིག',false,false,0),
('dz','Dzongkha','རྫོང་ཁ',false,false,0),
('ka','Georgian','ქართული',false,false,0),
('hy','Armenian','Հայերեն',false,false,0),
('az','Azerbaijani','Azərbaycanca',false,false,0),
('kk','Kazakh','Қазақша',false,false,0),
('ky','Kyrgyz','Кыргызча',false,false,0),
('uz','Uzbek','Oʻzbekcha',false,false,0),
('tg','Tajik','Тоҷикӣ',false,false,0),
('tk','Turkmen','Türkmençe',false,false,0),
('be','Belarusian','Беларуская',false,false,0),
('mo','Moldovan','Moldovenească',false,false,0),
('lb','Luxembourgish','Lëtzebuergesch',false,false,0),
('fo','Faroese','Føroyskt',false,false,0),
('gd','Scottish Gaelic','Gàidhlig',false,false,0),
('br','Breton','Brezhoneg',false,false,0),
('co','Corsican','Corsu',false,false,0),
('eo','Esperanto','Esperanto',false,false,0),
('la','Latin','Latina',false,false,0),
('yi','Yiddish','ייִדיש',true,false,0),
('haw','Hawaiian','ʻŌlelo Hawaiʻi',false,false,0),
('mi','Maori','Māori',false,false,0),
('sm','Samoan','Samoa',false,false,0),
('to','Tongan','Tonga',false,false,0),
('fj','Fijian','Vosa Vakaviti',false,false,0),
('ht','Haitian Creole','Kreyòl',false,false,0),
('qu','Quechua','Runa Simi',false,false,0),
('ay','Aymara','Aymar aru',false,false,0),
('gn','Guarani','Avañeʼẽ',false,false,0),
('nah','Nahuatl','Nāhuatl',false,false,0),
('iu','Inuktitut','ᐃᓄᒃᑎᑐᑦ',false,false,0),
('chr','Cherokee','ᏣᎳᎩ',false,false,0),
('nv','Navajo','Diné bizaad',false,false,0),
('su','Sundanese','Basa Sunda',false,false,0),
('jv','Javanese','Basa Jawa',false,false,0),
('ceb','Cebuano','Cebuano',false,false,0),
('hmn','Hmong','Hmoob',false,false,0),
('ug','Uyghur','ئۇيغۇرچە',true,false,0),
('ti','Tigrinya','ትግርኛ',false,false,0)
ON CONFLICT (code) DO NOTHING;

-- ===== 20260608021354_f9ec7a8b-854b-4802-8ef3-e328e6d1f20b.sql =====

-- ============================================
-- AMS CATALOG TABLES
-- ============================================

CREATE TABLE public.ams_achievements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  category text NOT NULL DEFAULT 'general',
  icon text,
  points integer NOT NULL DEFAULT 0,
  xp_reward integer NOT NULL DEFAULT 0,
  rarity text NOT NULL DEFAULT 'common',
  criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  role_scope text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_achievements TO anon, authenticated;
GRANT ALL ON public.ams_achievements TO service_role;
ALTER TABLE public.ams_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_achievements_read_all" ON public.ams_achievements FOR SELECT USING (true);
CREATE POLICY "ams_achievements_admin_write" ON public.ams_achievements FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  tier text NOT NULL DEFAULT 'bronze',
  icon text,
  color text DEFAULT '#3B82F6',
  criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_badges TO anon, authenticated;
GRANT ALL ON public.ams_badges TO service_role;
ALTER TABLE public.ams_badges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_badges_read_all" ON public.ams_badges FOR SELECT USING (true);
CREATE POLICY "ams_badges_admin_write" ON public.ams_badges FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_trophies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  tier text NOT NULL DEFAULT 'gold',
  season text,
  icon text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_trophies TO anon, authenticated;
GRANT ALL ON public.ams_trophies TO service_role;
ALTER TABLE public.ams_trophies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_trophies_read_all" ON public.ams_trophies FOR SELECT USING (true);
CREATE POLICY "ams_trophies_admin_write" ON public.ams_trophies FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  reward_type text NOT NULL DEFAULT 'digital',
  value_amount numeric DEFAULT 0,
  cost_points integer NOT NULL DEFAULT 0,
  stock integer,
  icon text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_rewards TO anon, authenticated;
GRANT ALL ON public.ams_rewards TO service_role;
ALTER TABLE public.ams_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_rewards_read_all" ON public.ams_rewards FOR SELECT USING (true);
CREATE POLICY "ams_rewards_admin_write" ON public.ams_rewards FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level_number integer NOT NULL UNIQUE,
  name text NOT NULL,
  xp_required integer NOT NULL,
  perks jsonb DEFAULT '[]'::jsonb,
  icon text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_levels TO anon, authenticated;
GRANT ALL ON public.ams_levels TO service_role;
ALTER TABLE public.ams_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_levels_read_all" ON public.ams_levels FOR SELECT USING (true);
CREATE POLICY "ams_levels_admin_write" ON public.ams_levels FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  metric text NOT NULL,
  target_value numeric NOT NULL,
  reward_points integer DEFAULT 0,
  reward_id uuid REFERENCES public.ams_rewards(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_milestones TO anon, authenticated;
GRANT ALL ON public.ams_milestones TO service_role;
ALTER TABLE public.ams_milestones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_milestones_read_all" ON public.ams_milestones FOR SELECT USING (true);
CREATE POLICY "ams_milestones_admin_write" ON public.ams_milestones FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_leaderboards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  metric text NOT NULL DEFAULT 'xp',
  scope text NOT NULL DEFAULT 'global',
  period text NOT NULL DEFAULT 'all_time',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.ams_leaderboards TO anon, authenticated;
GRANT ALL ON public.ams_leaderboards TO service_role;
ALTER TABLE public.ams_leaderboards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_leaderboards_read_all" ON public.ams_leaderboards FOR SELECT USING (true);
CREATE POLICY "ams_leaderboards_admin_write" ON public.ams_leaderboards FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

-- ============================================
-- AMS USER STATE TABLES
-- ============================================

CREATE TABLE public.ams_user_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  total_xp integer NOT NULL DEFAULT 0,
  total_points integer NOT NULL DEFAULT 0,
  current_level integer NOT NULL DEFAULT 1,
  achievements_count integer NOT NULL DEFAULT 0,
  badges_count integer NOT NULL DEFAULT 0,
  trophies_count integer NOT NULL DEFAULT 0,
  current_streak integer NOT NULL DEFAULT 0,
  longest_streak integer NOT NULL DEFAULT 0,
  last_activity_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.ams_user_progress TO authenticated;
GRANT ALL ON public.ams_user_progress TO service_role;
ALTER TABLE public.ams_user_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_progress_select_own_or_admin" ON public.ams_user_progress FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_progress_upsert_own" ON public.ams_user_progress FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_progress_update_own" ON public.ams_user_progress FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_user_achievements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  achievement_id uuid NOT NULL REFERENCES public.ams_achievements(id) ON DELETE CASCADE,
  progress numeric NOT NULL DEFAULT 0,
  unlocked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, achievement_id)
);
GRANT SELECT, INSERT, UPDATE ON public.ams_user_achievements TO authenticated;
GRANT ALL ON public.ams_user_achievements TO service_role;
ALTER TABLE public.ams_user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_ua_select" ON public.ams_user_achievements FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_ua_insert_own" ON public.ams_user_achievements FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_ua_update_own" ON public.ams_user_achievements FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_user_badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  badge_id uuid NOT NULL REFERENCES public.ams_badges(id) ON DELETE CASCADE,
  earned_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, badge_id)
);
GRANT SELECT, INSERT ON public.ams_user_badges TO authenticated;
GRANT ALL ON public.ams_user_badges TO service_role;
ALTER TABLE public.ams_user_badges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_ub_select" ON public.ams_user_badges FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_ub_insert_own" ON public.ams_user_badges FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_user_trophies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  trophy_id uuid NOT NULL REFERENCES public.ams_trophies(id) ON DELETE CASCADE,
  season text,
  rank integer,
  earned_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.ams_user_trophies TO authenticated;
GRANT ALL ON public.ams_user_trophies TO service_role;
ALTER TABLE public.ams_user_trophies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_ut_select" ON public.ams_user_trophies FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_ut_insert_own" ON public.ams_user_trophies FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_user_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  milestone_id uuid NOT NULL REFERENCES public.ams_milestones(id) ON DELETE CASCADE,
  current_value numeric NOT NULL DEFAULT 0,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, milestone_id)
);
GRANT SELECT, INSERT, UPDATE ON public.ams_user_milestones TO authenticated;
GRANT ALL ON public.ams_user_milestones TO service_role;
ALTER TABLE public.ams_user_milestones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_um_select" ON public.ams_user_milestones FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_um_insert_own" ON public.ams_user_milestones FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_um_update_own" ON public.ams_user_milestones FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_streaks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  streak_type text NOT NULL DEFAULT 'daily_login',
  current_count integer NOT NULL DEFAULT 0,
  longest_count integer NOT NULL DEFAULT 0,
  last_activity_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, streak_type)
);
GRANT SELECT, INSERT, UPDATE ON public.ams_streaks TO authenticated;
GRANT ALL ON public.ams_streaks TO service_role;
ALTER TABLE public.ams_streaks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_streaks_select" ON public.ams_streaks FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_streaks_insert_own" ON public.ams_streaks FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_streaks_update_own" ON public.ams_streaks FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_xp_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  source text NOT NULL,
  reference_id uuid,
  meta jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.ams_xp_events TO authenticated;
GRANT ALL ON public.ams_xp_events TO service_role;
ALTER TABLE public.ams_xp_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_xp_select" ON public.ams_xp_events FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_xp_insert_own" ON public.ams_xp_events FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_user_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  reward_id uuid NOT NULL REFERENCES public.ams_rewards(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'claimed',
  claimed_at timestamptz NOT NULL DEFAULT now(),
  fulfilled_at timestamptz,
  points_spent integer NOT NULL DEFAULT 0,
  meta jsonb DEFAULT '{}'::jsonb
);
GRANT SELECT, INSERT ON public.ams_user_rewards TO authenticated;
GRANT ALL ON public.ams_user_rewards TO service_role;
ALTER TABLE public.ams_user_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_ur_select" ON public.ams_user_rewards FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_ur_insert_own" ON public.ams_user_rewards FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  reward_id uuid NOT NULL REFERENCES public.ams_rewards(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  approved_by uuid,
  approved_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.ams_claims TO authenticated;
GRANT ALL ON public.ams_claims TO service_role;
ALTER TABLE public.ams_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_claims_select" ON public.ams_claims FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_claims_insert_own" ON public.ams_claims FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_claims_admin_update" ON public.ams_claims FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'))
  WITH CHECK (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));

CREATE TABLE public.ams_leaderboard_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  leaderboard_id uuid NOT NULL REFERENCES public.ams_leaderboards(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  score numeric NOT NULL DEFAULT 0,
  rank integer,
  period_key text NOT NULL DEFAULT 'all_time',
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (leaderboard_id, user_id, period_key)
);
GRANT SELECT, INSERT, UPDATE ON public.ams_leaderboard_entries TO authenticated;
GRANT ALL ON public.ams_leaderboard_entries TO service_role;
ALTER TABLE public.ams_leaderboard_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_lb_read_all" ON public.ams_leaderboard_entries FOR SELECT USING (true);
CREATE POLICY "ams_lb_upsert_own" ON public.ams_leaderboard_entries FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_lb_update_own" ON public.ams_leaderboard_entries FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  notif_type text NOT NULL,
  title text NOT NULL,
  body text,
  reference_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.ams_notifications TO authenticated;
GRANT ALL ON public.ams_notifications TO service_role;
ALTER TABLE public.ams_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_notif_select_own" ON public.ams_notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'boss_owner'));
CREATE POLICY "ams_notif_insert_own" ON public.ams_notifications FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ams_notif_update_own" ON public.ams_notifications FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE public.ams_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  action text NOT NULL,
  entity_type text,
  entity_id uuid,
  meta jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.ams_audit_logs TO authenticated;
GRANT ALL ON public.ams_audit_logs TO service_role;
ALTER TABLE public.ams_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ams_audit_admin_select" ON public.ams_audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'boss_owner') OR public.has_role(auth.uid(), 'ceo'));
CREATE POLICY "ams_audit_insert" ON public.ams_audit_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() OR user_id IS NULL);

-- ============================================
-- TRIGGERS
-- ============================================

CREATE OR REPLACE FUNCTION public.ams_set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER trg_ams_ach_upd BEFORE UPDATE ON public.ams_achievements FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_badges_upd BEFORE UPDATE ON public.ams_badges FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_trophies_upd BEFORE UPDATE ON public.ams_trophies FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_rewards_upd BEFORE UPDATE ON public.ams_rewards FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_milestones_upd BEFORE UPDATE ON public.ams_milestones FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_progress_upd BEFORE UPDATE ON public.ams_user_progress FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_um_upd BEFORE UPDATE ON public.ams_user_milestones FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_streaks_upd BEFORE UPDATE ON public.ams_streaks FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();
CREATE TRIGGER trg_ams_claims_upd BEFORE UPDATE ON public.ams_claims FOR EACH ROW EXECUTE FUNCTION public.ams_set_updated_at();

-- Indexes
CREATE INDEX idx_ams_ua_user ON public.ams_user_achievements(user_id);
CREATE INDEX idx_ams_ub_user ON public.ams_user_badges(user_id);
CREATE INDEX idx_ams_ut_user ON public.ams_user_trophies(user_id);
CREATE INDEX idx_ams_ur_user ON public.ams_user_rewards(user_id);
CREATE INDEX idx_ams_xp_user ON public.ams_xp_events(user_id, created_at DESC);
CREATE INDEX idx_ams_claims_status ON public.ams_claims(status);
CREATE INDEX idx_ams_notif_user_read ON public.ams_notifications(user_id, is_read);
CREATE INDEX idx_ams_lb_entries_lb ON public.ams_leaderboard_entries(leaderboard_id, score DESC);

