import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { BossModule } from './index';

export interface BossLiveStatus {
  module: BossModule; key: string; status: string;
  value_num: number | null; value_text: string | null;
  meta: Record<string, unknown>; updated_at: string;
}

export function useBossLiveStatus(module?: BossModule) {
  const [data, setData] = useState<BossLiveStatus[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('boss_live_status').select('*');
      if (module) q = q.eq('module', module);
      const { data } = await q;
      if (!alive) return;
      setData((data ?? []) as BossLiveStatus[]); setLoading(false);
    };
    load();
    const ch = supabase.channel(`boss-live-${module ?? 'all'}-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_live_status' }, load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(ch); };
  }, [module]);
  return { data, loading };
}
