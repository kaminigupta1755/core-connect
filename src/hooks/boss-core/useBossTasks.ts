import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';

export interface BossTask {
  id: string; module: BossModule; title: string; description: string | null;
  assignee_user_id: string | null; assignee_role: string | null;
  priority: number; status: 'open'|'in_progress'|'blocked'|'done'|'cancelled';
  due_at: string | null; completed_at: string | null;
  created_by: string | null; created_at: string; updated_at: string;
}

export function useBossTasks(module?: BossModule, limit = 100) {
  const [data, setData] = useState<BossTask[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('boss_tasks').select('*')
        .order('due_at', { ascending: true, nullsFirst: false }).limit(limit);
      if (module) q = q.eq('module', module);
      const { data } = await q;
      if (!alive) return;
      setData((data ?? []) as BossTask[]); setLoading(false);
    };
    load();
    const ch = supabase.channel(`boss-task-${module ?? 'all'}-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_tasks' }, load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [module, limit]);
  return { data, loading };
}
