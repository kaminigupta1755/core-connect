import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';

export interface BossNotification {
  id: string;
  module: BossModule;
  severity: 'info' | 'success' | 'warning' | 'critical';
  title: string;
  body: string | null;
  link: string | null;
  audience_user_id: string | null;
  audience_role: string | null;
  read_at: string | null;
  created_at: string;
}

export function useBossNotifications(module?: BossModule, limit = 50) {
  const [data, setData] = useState<BossNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('boss_notifications').select('*')
        .order('created_at', { ascending: false }).limit(limit);
      if (module) q = q.eq('module', module);
      const { data, error } = await q;
      if (!alive) return;
      if (error) setError(error.message);
      else setData((data ?? []) as BossNotification[]);
      setLoading(false);
    };
    load();
    const ch = supabase.channel(`boss-notif-${module ?? 'all'}-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_notifications' }, load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [module, limit]);

  const markRead = async (id: string) => {
    await supabase.from('boss_notifications').update({ read_at: new Date().toISOString() }).eq('id', id);
  };

  return { data, loading, error, markRead };
}
