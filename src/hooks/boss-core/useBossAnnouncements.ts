import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';

export interface BossAnnouncement {
  id: string; module: BossModule; title: string; body: string | null;
  audience_role: string | null; severity: 'info'|'success'|'warning'|'critical';
  starts_at: string; ends_at: string | null; created_at: string;
}

export function useBossAnnouncements(module?: BossModule) {
  const [data, setData] = useState<BossAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('boss_announcements').select('*')
        .order('starts_at', { ascending: false }).limit(50);
      if (module) q = q.eq('module', module);
      const { data } = await q;
      if (!alive) return;
      setData((data ?? []) as BossAnnouncement[]); setLoading(false);
    };
    load();
    const ch = supabase.channel(`boss-anno-${module ?? 'all'}-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_announcements' }, load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [module]);
  return { data, loading };
}
