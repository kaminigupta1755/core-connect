import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface CommandKPIs {
  totalTasks: number;
  inProgress: number;
  pendingApprovals: number;
  newUsers30d: number;
  activeSessions: number;
  completedToday: number;
  criticalAlerts: number;
  activeModules: number;
  totalModules: number;
  revenueSeries: { month: string; revenue: number; trend: number }[];
  weeklyTasks: { day: string; value: number }[];
  income: { name: string; value: number; color: string }[];
  upcomingAnnouncements: { id: string; title: string; body: string | null; created_at: string }[];
  recentTasks: { id: string; title: string; status: string; created_at: string }[];
}

async function fetchKPIs(): Promise<CommandKPIs> {
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const sixMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 5, 1).toISOString();

  const head = { count: 'exact' as const, head: true };

  const [
    tasksAll,
    tasksInProg,
    approvalsPending,
    profilesNew,
    sessionsActive,
    tasksDoneToday,
    alertsCritical,
    modulesActive,
    modulesAll,
    announcements,
    recentTasks,
    tasksLast7,
    approvalsResolved,
    tasksResolvedMonthly,
  ] = await Promise.all([
    supabase.from('boss_tasks').select('*', head),
    supabase.from('boss_tasks').select('*', head).eq('status', 'in_progress'),
    supabase.from('boss_approvals').select('*', head).eq('status', 'pending'),
    supabase.from('profiles').select('*', head).gte('created_at', thirtyDaysAgo),
    supabase.from('user_sessions').select('*', head).eq('is_active', true),
    supabase.from('boss_tasks').select('*', head).eq('status', 'done').gte('updated_at', startOfToday),
    supabase.from('security_alerts').select('*', head).eq('severity', 'critical').is('resolved_at', null),
    supabase.from('system_modules').select('*', head).eq('status', 'active'),
    supabase.from('system_modules').select('*', head),
    supabase.from('boss_announcements').select('id,title,body,created_at').order('created_at', { ascending: false }).limit(5),
    supabase.from('boss_tasks').select('id,title,status,created_at').order('created_at', { ascending: false }).limit(5),
    supabase.from('boss_tasks').select('created_at,status').gte('created_at', sevenDaysAgo.toISOString()),
    supabase.from('boss_approvals').select('decided_at,status').gte('created_at', sixMonthsAgo).not('decided_at', 'is', null),
    supabase.from('boss_tasks').select('created_at').gte('created_at', sixMonthsAgo),
  ]);

  // Weekly bar chart — count tasks per weekday for last 7 days
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const weeklyBuckets: Record<string, number> = Object.fromEntries(dayNames.map((d) => [d, 0]));
  (tasksLast7.data ?? []).forEach((r: { created_at: string }) => {
    const d = new Date(r.created_at);
    weeklyBuckets[dayNames[d.getDay()]] = (weeklyBuckets[dayNames[d.getDay()]] ?? 0) + 1;
  });
  const weeklyTasks = dayNames.map((day) => ({ day, value: weeklyBuckets[day] }));

  // Monthly series
  const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const months: { month: string; revenue: number; trend: number }[] = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push({ month: monthNames[d.getMonth()], revenue: 0, trend: 0 });
  }
  const monthKey = (iso: string) => {
    const d = new Date(iso);
    const diff = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
    return 5 - diff;
  };
  (tasksResolvedMonthly.data ?? []).forEach((r: { created_at: string }) => {
    const idx = monthKey(r.created_at);
    if (idx >= 0 && idx < 6) months[idx].revenue += 1;
  });
  (approvalsResolved.data ?? []).forEach((r: { decided_at: string | null }) => {
    if (!r.decided_at) return;
    const idx = monthKey(r.decided_at);
    if (idx >= 0 && idx < 6) months[idx].trend += 1;
  });

  const done = tasksDoneToday.count ?? 0;
  const pending = approvalsPending.count ?? 0;
  const income = [
    { name: 'Completed', value: done, color: '#8B5CF6' },
    { name: 'Pending', value: pending, color: '#F97316' },
  ];

  return {
    totalTasks: tasksAll.count ?? 0,
    inProgress: tasksInProg.count ?? 0,
    pendingApprovals: pending,
    newUsers30d: profilesNew.count ?? 0,
    activeSessions: sessionsActive.count ?? 0,
    completedToday: done,
    criticalAlerts: alertsCritical.count ?? 0,
    activeModules: modulesActive.count ?? 0,
    totalModules: modulesAll.count ?? 0,
    revenueSeries: months,
    weeklyTasks,
    income,
    upcomingAnnouncements: (announcements.data ?? []) as CommandKPIs['upcomingAnnouncements'],
    recentTasks: (recentTasks.data ?? []) as CommandKPIs['recentTasks'],
  };
}

export function useBossCommandKPIs() {
  const q = useQuery({ queryKey: ['boss-command-kpis'], queryFn: fetchKPIs, refetchInterval: 30_000 });

  useEffect(() => {
    const ch = supabase
      .channel(`boss-command-kpis-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_tasks' }, () => q.refetch())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_approvals' }, () => q.refetch())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'boss_announcements' }, () => q.refetch())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'security_alerts' }, () => q.refetch())
      .subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return q;
}
