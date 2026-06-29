import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Activity, AlertTriangle, CheckCircle2, RefreshCw, Wrench, ShieldAlert, Zap } from 'lucide-react';
import { toast } from 'sonner';

type Module = {
  id: string;
  module_key: string;
  module_name: string;
  category: string;
  status: 'healthy' | 'degraded' | 'critical' | 'unknown' | 'recovering';
  health_pct: number;
  last_checked_at: string | null;
  error_count: number;
  recovery_count: number;
  avg_repair_ms: number;
  meta: Record<string, unknown>;
};

type Incident = {
  id: string;
  module_key: string;
  severity: string;
  title: string;
  detected_at: string;
  resolved_at: string | null;
  auto_resolved: boolean;
};

type Repair = {
  id: string;
  module_key: string;
  action: string;
  status: string;
  duration_ms: number;
  attempted_at: string;
};

const statusColor: Record<string, string> = {
  healthy: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/30',
  degraded: 'text-amber-400 bg-amber-500/10 border-amber-500/30',
  critical: 'text-red-400 bg-red-500/10 border-red-500/30',
  recovering: 'text-blue-400 bg-blue-500/10 border-blue-500/30',
  unknown: 'text-slate-400 bg-slate-500/10 border-slate-500/30',
};

export function SelfHealing() {
  const [modules, setModules] = useState<Module[]>([]);
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [repairs, setRepairs] = useState<Repair[]>([]);
  const [running, setRunning] = useState(false);
  const [autoTick, setAutoTick] = useState(true);

  const load = useCallback(async () => {
    const [m, i, r] = await Promise.all([
      supabase.from('system_health_modules').select('*').order('category').order('module_name'),
      supabase.from('system_health_incidents').select('*').order('detected_at', { ascending: false }).limit(25),
      supabase.from('system_health_repairs').select('*').order('attempted_at', { ascending: false }).limit(25),
    ]);
    if (m.data) setModules(m.data as any);
    if (i.data) setIncidents(i.data as any);
    if (r.data) setRepairs(r.data as any);
  }, []);

  const probe = useCallback(async () => {
    setRunning(true);
    try {
      const { data, error } = await supabase.functions.invoke('health-engine');
      if (error) throw error;
      toast.success(`Health probe complete — overall ${data?.overall ?? '?'}%`);
      await load();
    } catch (e) {
      toast.error('Probe failed: ' + (e as Error).message);
    } finally {
      setRunning(false);
    }
  }, [load]);

  useEffect(() => {
    load();
    const channel = supabase
      .channel(`health-engine-${Math.random()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'system_health_modules' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'system_health_incidents' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'system_health_repairs' }, load)
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [load]);

  useEffect(() => {
    if (!autoTick) return;
    probe();
    const t = setInterval(probe, 60_000);
    return () => clearInterval(t);
  }, [autoTick, probe]);

  const overall = modules.length
    ? Math.round(modules.reduce((s, m) => s + Number(m.health_pct), 0) / modules.length)
    : 0;
  const criticals = modules.filter((m) => m.status === 'critical').length;
  const degraded = modules.filter((m) => m.status === 'degraded').length;
  const totalRecoveries = modules.reduce((s, m) => s + m.recovery_count, 0);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Zap className="w-6 h-6 text-cyan-400" /> Self-Healing Command Center
          </h1>
          <p className="text-sm text-slate-400 mt-1">Autonomous health detection, repair, and verification.</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoTick((v) => !v)}
            className={`px-3 py-2 rounded-lg text-xs border ${autoTick ? 'border-emerald-500/40 text-emerald-300 bg-emerald-500/10' : 'border-slate-600 text-slate-300'}`}
          >
            Auto 60s · {autoTick ? 'ON' : 'OFF'}
          </button>
          <button
            onClick={probe}
            disabled={running}
            className="px-4 py-2 rounded-lg bg-cyan-500/20 border border-cyan-400/40 text-cyan-200 text-sm flex items-center gap-2 hover:bg-cyan-500/30 disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${running ? 'animate-spin' : ''}`} /> Run Probe
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
        <KPI label="Overall Health" value={`${overall}%`} icon={Activity} tone={overall >= 90 ? 'good' : overall >= 70 ? 'warn' : 'bad'} />
        <KPI label="Critical" value={String(criticals)} icon={ShieldAlert} tone={criticals ? 'bad' : 'good'} />
        <KPI label="Degraded" value={String(degraded)} icon={AlertTriangle} tone={degraded ? 'warn' : 'good'} />
        <KPI label="Auto-Recoveries" value={String(totalRecoveries)} icon={Wrench} tone="good" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2 bg-slate-900/60 border border-slate-700/60 rounded-xl p-4 backdrop-blur">
          <h2 className="text-sm font-semibold text-white mb-3">Monitored Modules ({modules.length})</h2>
          <div className="space-y-2 max-h-[520px] overflow-y-auto">
            {modules.map((m) => (
              <div key={m.id} className="flex items-center gap-3 p-3 rounded-lg bg-slate-800/50 border border-slate-700/40">
                <div className={`px-2 py-1 rounded text-[10px] uppercase tracking-wide border ${statusColor[m.status]}`}>{m.status}</div>
                <div className="flex-1 min-w-0">
                  <div className="text-sm text-white font-medium truncate">{m.module_name}</div>
                  <div className="text-[11px] text-slate-400 truncate">{m.module_key} · {m.category} · errors {m.error_count} · recoveries {m.recovery_count}</div>
                </div>
                <div className="w-32">
                  <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                    <div
                      className={`h-full ${m.health_pct >= 90 ? 'bg-emerald-400' : m.health_pct >= 70 ? 'bg-amber-400' : 'bg-red-400'}`}
                      style={{ width: `${m.health_pct}%` }}
                    />
                  </div>
                  <div className="text-right text-[10px] text-slate-400 mt-1">{Math.round(Number(m.health_pct))}%</div>
                </div>
              </div>
            ))}
            {modules.length === 0 && <div className="text-center text-slate-500 text-sm py-8">No modules yet — run a probe.</div>}
          </div>
        </div>

        <div className="space-y-4">
          <div className="bg-slate-900/60 border border-slate-700/60 rounded-xl p-4 backdrop-blur">
            <h2 className="text-sm font-semibold text-white mb-3 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-400" /> Recent Incidents
            </h2>
            <div className="space-y-2 max-h-60 overflow-y-auto">
              {incidents.map((i) => (
                <div key={i.id} className="text-xs p-2 rounded bg-slate-800/40 border border-slate-700/40">
                  <div className="flex items-center justify-between">
                    <span className="text-white truncate">{i.title}</span>
                    {i.auto_resolved && <CheckCircle2 className="w-3 h-3 text-emerald-400" />}
                  </div>
                  <div className="text-[10px] text-slate-400">{new Date(i.detected_at).toLocaleTimeString()} · {i.severity}</div>
                </div>
              ))}
              {incidents.length === 0 && <div className="text-center text-slate-500 text-xs py-4">No incidents.</div>}
            </div>
          </div>

          <div className="bg-slate-900/60 border border-slate-700/60 rounded-xl p-4 backdrop-blur">
            <h2 className="text-sm font-semibold text-white mb-3 flex items-center gap-2">
              <Wrench className="w-4 h-4 text-cyan-400" /> Recent Repairs
            </h2>
            <div className="space-y-2 max-h-60 overflow-y-auto">
              {repairs.map((r) => (
                <div key={r.id} className="text-xs p-2 rounded bg-slate-800/40 border border-slate-700/40">
                  <div className="text-white truncate">{r.action}</div>
                  <div className="text-[10px] text-slate-400">{r.module_key} · {r.status} · {r.duration_ms}ms</div>
                </div>
              ))}
              {repairs.length === 0 && <div className="text-center text-slate-500 text-xs py-4">No repairs yet.</div>}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function KPI({ label, value, icon: Icon, tone }: { label: string; value: string; icon: React.ElementType; tone: 'good' | 'warn' | 'bad' }) {
  const toneCls =
    tone === 'good' ? 'border-emerald-500/40 text-emerald-300' :
    tone === 'warn' ? 'border-amber-500/40 text-amber-300' :
    'border-red-500/40 text-red-300';
  return (
    <div className={`bg-slate-900/60 border ${toneCls} rounded-xl p-4 backdrop-blur`}>
      <div className="flex items-center justify-between">
        <div className="text-[11px] uppercase tracking-wider text-slate-400">{label}</div>
        <Icon className="w-4 h-4 opacity-70" />
      </div>
      <div className="text-2xl font-bold mt-2">{value}</div>
    </div>
  );
}
