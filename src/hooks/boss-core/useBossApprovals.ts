import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';
import { bossDispatch } from './bossDispatch';

export interface BossApproval {
  id: string;
  module: BossModule;
  action_key: string;
  title: string;
  description: string | null;
  payload: Record<string, unknown>;
  requested_by: string | null;
  requested_by_role: string | null;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled' | 'expired';
  decided_by: string | null;
  decided_at: string | null;
  decision_reason: string | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
}

export function useBossApprovals(opts?: { module?: BossModule; status?: BossApproval['status']; limit?: number }) {
  const [data, setData] = useState<BossApproval[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('boss_approvals').select('*')
        .order('created_at', { ascending: false }).limit(opts?.limit ?? 100);
      if (opts?.module) q = q.eq('module', opts.module);
      if (opts?.status) q = q.eq('status', opts.status);
      const { data, error } = await q;
      if (!alive) return;
      if (error) setError(error.message);
      else setData((data ?? []) as BossApproval[]);
      setLoading(false);
    };
    load();
    const ch = supabase.channel(`boss-appr-${opts?.module ?? 'all'}-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_approvals' }, load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [opts?.module, opts?.status, opts?.limit]);

  return {
    data, loading, error,
    approve: (id: string, reason?: string) => bossDispatch.decideApproval(id, true, reason),
    reject: (id: string, reason?: string) => bossDispatch.decideApproval(id, false, reason),
  };
}
