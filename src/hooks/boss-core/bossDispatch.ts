import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';

type Severity = 'info' | 'success' | 'warning' | 'critical';

export const bossDispatch = {
  notify: (args: {
    module: BossModule; title: string; body?: string;
    severity?: Severity; audienceUserId?: string; audienceRole?: string; link?: string;
  }) => supabase.rpc('boss_notify', {
    _module: args.module, _title: args.title, _body: args.body ?? null,
    _severity: args.severity ?? 'info',
    _audience_user_id: args.audienceUserId ?? null,
    _audience_role: args.audienceRole ?? null,
    _link: args.link ?? null,
  }),

  requestApproval: (args: {
    module: BossModule; actionKey: string; title: string;
    description?: string; payload?: Record<string, unknown>; expiresAt?: string;
  }) => supabase.rpc('boss_request_approval', {
    _module: args.module, _action_key: args.actionKey, _title: args.title,
    _description: args.description ?? null,
    _payload: (args.payload ?? {}) as any,
    _expires_at: args.expiresAt ?? null,
  }),

  decideApproval: (id: string, approved: boolean, reason?: string) =>
    supabase.rpc('boss_decide_approval', { _id: id, _approved: approved, _reason: reason ?? null }),

  createTask: (args: {
    module: BossModule; title: string; description?: string;
    assigneeUserId?: string; assigneeRole?: string; priority?: number; dueAt?: string;
  }) => supabase.rpc('boss_create_task', {
    _module: args.module, _title: args.title, _description: args.description ?? null,
    _assignee_user_id: args.assigneeUserId ?? null,
    _assignee_role: args.assigneeRole ?? null,
    _priority: args.priority ?? 3, _due_at: args.dueAt ?? null,
  }),

  updateLiveStatus: (args: {
    module: BossModule; key: string; status: string;
    valueNum?: number; valueText?: string; meta?: Record<string, unknown>;
  }) => supabase.rpc('boss_update_live_status', {
    _module: args.module, _key: args.key, _status: args.status,
    _value_num: args.valueNum ?? null, _value_text: args.valueText ?? null,
    _meta: (args.meta ?? {}) as any,
  }),

  announce: (args: {
    module: BossModule; title: string; body?: string;
    audienceRole?: string; severity?: Severity; endsAt?: string;
  }) => supabase.rpc('boss_announce', {
    _module: args.module, _title: args.title, _body: args.body ?? null,
    _audience_role: args.audienceRole ?? null,
    _severity: args.severity ?? 'info', _ends_at: args.endsAt ?? null,
  }),
};
