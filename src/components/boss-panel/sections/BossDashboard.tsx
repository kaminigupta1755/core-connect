import React from 'react';
import { motion } from 'framer-motion';
import {
  Users,
  Activity,
  Clock,
  CheckCircle2,
  ShieldAlert,
  ArrowUpRight,
  Briefcase,
  Calendar,
  Mail,
  Server,
  Inbox,
  Loader2,
} from 'lucide-react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  PieChart,
  Pie,
  Cell,
} from 'recharts';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { GlobalNetworkMap } from './GlobalNetworkMap';
import { useAuth } from '@/hooks/useAuth';
import { useBossCommandKPIs } from '@/hooks/boss-panel/useBossCommandKPIs';
import { formatDistanceToNow } from 'date-fns';

const statusColor: Record<string, string> = {
  todo: 'bg-slate-500',
  in_progress: 'bg-amber-500',
  blocked: 'bg-red-500',
  done: 'bg-emerald-500',
  cancelled: 'bg-zinc-500',
};

export function BossDashboard() {
  const { user } = useAuth();
  const { data, isLoading, isError, refetch, dataUpdatedAt } = useBossCommandKPIs();

  const summaryCards = [
    {
      label: 'Total Tasks',
      value: data?.totalTasks ?? 0,
      icon: Users,
      gradient: 'from-blue-500 to-cyan-400',
      bgGradient: 'from-blue-500/20 to-cyan-400/10',
    },
    {
      label: 'In Progress',
      value: data?.inProgress ?? 0,
      icon: Clock,
      gradient: 'from-orange-500 to-amber-400',
      bgGradient: 'from-orange-500/20 to-amber-400/10',
    },
    {
      label: 'Pending Approvals',
      value: data?.pendingApprovals ?? 0,
      icon: CheckCircle2,
      gradient: 'from-purple-500 to-pink-400',
      bgGradient: 'from-purple-500/20 to-pink-400/10',
    },
  ];

  const initials = (user?.email?.[0] ?? 'B').toUpperCase();
  const displayName =
    (user?.user_metadata as { full_name?: string } | undefined)?.full_name ||
    user?.email?.split('@')[0] ||
    'Boss Admin';

  const modulesActive = data?.activeModules ?? 0;
  const modulesTotal = data?.totalModules ?? 0;
  const healthPct =
    modulesTotal > 0 ? Math.round((modulesActive / modulesTotal) * 100) : 0;

  const income = data?.income ?? [
    { name: 'Completed', value: 0, color: '#8B5CF6' },
    { name: 'Pending', value: 0, color: '#F97316' },
  ];
  const incomeTotal = income.reduce((s, i) => s + i.value, 0);

  return (
    <div className="p-6 space-y-6 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 min-h-full">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 dark:text-white">Command Dashboard</h1>
          <p className="text-sm text-slate-500 dark:text-slate-400">
            Real-time overview from Boss Core (boss_tasks · boss_approvals · security_alerts · system_modules)
          </p>
        </div>
        <div className="flex items-center gap-3">
          {isLoading && <Loader2 className="w-4 h-4 animate-spin text-slate-400" />}
          <span className="text-xs text-slate-500 dark:text-slate-400">
            Last updated: {new Date(dataUpdatedAt || Date.now()).toLocaleTimeString()}
          </span>
          <Button size="sm" variant="outline" onClick={() => refetch()}>
            Refresh
          </Button>
        </div>
      </div>

      {isError && (
        <div className="p-3 rounded-xl border border-red-500/30 bg-red-500/10 text-sm text-red-500">
          Failed to load command KPIs.
        </div>
      )}

      {/* Global Network Map */}
      <GlobalNetworkMap className="w-full" />

      {/* Main Grid */}
      <div className="grid grid-cols-12 gap-6">
        {/* Left Column */}
        <div className="col-span-12 lg:col-span-8 space-y-6">
          {/* Activity History */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700"
          >
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-lg font-semibold text-slate-900 dark:text-white">
                Incoming Activity History (last 6 months)
              </h2>
              <span className="text-xs text-slate-500 dark:text-slate-400">Live · Boss Core</span>
            </div>

            <div className="flex flex-wrap gap-4 mb-6">
              <div className="flex items-center gap-3 bg-gradient-to-r from-blue-500/10 to-blue-400/5 dark:from-blue-500/20 dark:to-blue-400/10 px-4 py-3 rounded-2xl">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-500 to-cyan-400 flex items-center justify-center">
                  <Users className="w-5 h-5 text-white" />
                </div>
                <div>
                  <p className="text-xl font-bold text-slate-900 dark:text-white">{data?.newUsers30d ?? 0}</p>
                  <p className="text-xs text-slate-500 dark:text-slate-400">New Users (30d)</p>
                </div>
              </div>
              <div className="flex items-center gap-3 bg-gradient-to-r from-orange-500/10 to-amber-400/5 dark:from-orange-500/20 dark:to-amber-400/10 px-4 py-3 rounded-2xl">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-orange-500 to-amber-400 flex items-center justify-center">
                  <Activity className="w-5 h-5 text-white" />
                </div>
                <div>
                  <p className="text-xl font-bold text-slate-900 dark:text-white">{data?.activeSessions ?? 0}</p>
                  <p className="text-xs text-slate-500 dark:text-slate-400">Active Sessions</p>
                </div>
              </div>
              <div className="flex items-center gap-3 bg-gradient-to-r from-purple-500/10 to-pink-400/5 dark:from-purple-500/20 dark:to-pink-400/10 px-4 py-3 rounded-2xl">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-purple-500 to-pink-400 flex items-center justify-center">
                  <CheckCircle2 className="w-5 h-5 text-white" />
                </div>
                <div>
                  <p className="text-xl font-bold text-slate-900 dark:text-white">{data?.completedToday ?? 0}</p>
                  <p className="text-xs text-slate-500 dark:text-slate-400">Completed Today</p>
                </div>
              </div>
              <div className="flex items-center gap-3 bg-gradient-to-r from-red-500/10 to-rose-400/5 dark:from-red-500/20 dark:to-rose-400/10 px-4 py-3 rounded-2xl">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-red-500 to-rose-400 flex items-center justify-center">
                  <ShieldAlert className="w-5 h-5 text-white" />
                </div>
                <div>
                  <p className="text-xl font-bold text-slate-900 dark:text-white">{data?.criticalAlerts ?? 0}</p>
                  <p className="text-xs text-slate-500 dark:text-slate-400">Critical Alerts</p>
                </div>
              </div>
            </div>

            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={data?.revenueSeries ?? []}>
                <defs>
                  <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#8B5CF6" stopOpacity={0.4} />
                    <stop offset="95%" stopColor="#8B5CF6" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="colorTrend" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#06B6D4" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#06B6D4" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" className="dark:stroke-slate-700" />
                <XAxis dataKey="month" stroke="#94A3B8" fontSize={12} tickLine={false} axisLine={false} />
                <YAxis stroke="#94A3B8" fontSize={12} tickLine={false} axisLine={false} allowDecimals={false} />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'white',
                    border: 'none',
                    borderRadius: '12px',
                    boxShadow: '0 10px 40px rgba(0,0,0,0.1)',
                  }}
                />
                <Area type="monotone" dataKey="revenue" name="Tasks Created" stroke="#8B5CF6" strokeWidth={3} fill="url(#colorRevenue)" />
                <Area type="monotone" dataKey="trend" name="Approvals Decided" stroke="#06B6D4" strokeWidth={2} fill="url(#colorTrend)" strokeDasharray="5 5" />
              </AreaChart>
            </ResponsiveContainer>
          </motion.div>

          {/* Summary Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {summaryCards.map((card, index) => {
              const Icon = card.icon;
              return (
                <motion.div
                  key={card.label}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.1 }}
                  className={`bg-gradient-to-br ${card.bgGradient} backdrop-blur-sm rounded-2xl p-5 border border-white/50 dark:border-slate-700/50 shadow-lg`}
                >
                  <div className={`w-12 h-12 rounded-2xl bg-gradient-to-br ${card.gradient} flex items-center justify-center mb-4 shadow-lg`}>
                    <Icon className="w-6 h-6 text-white" />
                  </div>
                  <p className="text-3xl font-bold text-slate-900 dark:text-white mb-1">{card.value}</p>
                  <p className="text-sm text-slate-600 dark:text-slate-400">{card.label}</p>
                </motion.div>
              );
            })}
          </div>

          {/* Bottom Row */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Weekly Task Rate */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 }}
              className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700"
            >
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Tasks · Last 7 Days</h3>
                <span className="text-xs text-slate-500 dark:text-slate-400">Weekly</span>
              </div>
              <div className="flex items-end gap-4 mb-4">
                <span className="text-4xl font-bold text-slate-900 dark:text-white">
                  {(data?.weeklyTasks ?? []).reduce((s, d) => s + d.value, 0)}
                </span>
                <div className="flex items-center gap-1 text-emerald-500 text-sm pb-1">
                  <ArrowUpRight className="w-4 h-4" />
                  <span>created</span>
                </div>
              </div>
              <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">Task creation across the week</p>
              <ResponsiveContainer width="100%" height={120}>
                <BarChart data={data?.weeklyTasks ?? []}>
                  <XAxis dataKey="day" stroke="#94A3B8" fontSize={10} tickLine={false} axisLine={false} />
                  <Tooltip />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]}>
                    {(data?.weeklyTasks ?? []).map((_, index) => (
                      <Cell key={`cell-${index}`} fill="#F97316" />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </motion.div>

            {/* Announcements */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4 }}
              className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700"
            >
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Latest Announcements</h3>
                <span className="text-xs text-slate-500 dark:text-slate-400">Boss Core</span>
              </div>
              <div className="space-y-2">
                {(data?.upcomingAnnouncements ?? []).length === 0 ? (
                  <div className="flex flex-col items-center justify-center py-8 text-center text-slate-400">
                    <Inbox className="w-8 h-8 mb-2 opacity-50" />
                    <p className="text-sm">No announcements yet</p>
                  </div>
                ) : (
                  (data?.upcomingAnnouncements ?? []).map((a) => (
                    <div key={a.id} className="p-3 rounded-lg bg-slate-50 dark:bg-slate-700/50">
                      <p className="text-sm font-medium text-slate-900 dark:text-white">{a.title}</p>
                      {a.body && <p className="text-xs text-slate-500 dark:text-slate-400 line-clamp-2">{a.body}</p>}
                      <p className="text-[10px] text-slate-400 mt-1">
                        {formatDistanceToNow(new Date(a.created_at), { addSuffix: true })}
                      </p>
                    </div>
                  ))
                )}
              </div>
            </motion.div>
          </div>
        </div>

        {/* Right Column */}
        <div className="col-span-12 lg:col-span-4 space-y-6">
          {/* Profile Card */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700 text-center"
          >
            <Avatar className="w-20 h-20 mx-auto mb-4 ring-4 ring-violet-500/20">
              <AvatarFallback className="bg-gradient-to-br from-violet-500 to-purple-600 text-white text-xl">
                {initials}
              </AvatarFallback>
            </Avatar>
            <h3 className="text-lg font-semibold text-slate-900 dark:text-white">{displayName}</h3>
            <p className="text-sm text-slate-500 dark:text-slate-400 mb-4 truncate">{user?.email ?? '—'}</p>

            <div className="grid grid-cols-3 gap-2">
              <div className="bg-gradient-to-br from-blue-500/10 to-cyan-400/5 dark:from-blue-500/20 dark:to-cyan-400/10 rounded-xl p-3">
                <Briefcase className="w-5 h-5 text-blue-500 mx-auto mb-1" />
                <p className="text-xs text-slate-500 dark:text-slate-400">Tasks</p>
                <p className="text-sm font-semibold text-slate-900 dark:text-white">{data?.totalTasks ?? 0}</p>
              </div>
              <div className="bg-gradient-to-br from-emerald-500/10 to-teal-400/5 dark:from-emerald-500/20 dark:to-teal-400/10 rounded-xl p-3">
                <Server className="w-5 h-5 text-emerald-500 mx-auto mb-1" />
                <p className="text-xs text-slate-500 dark:text-slate-400">Modules</p>
                <p className="text-sm font-semibold text-slate-900 dark:text-white">
                  {modulesActive}/{modulesTotal}
                </p>
              </div>
              <div className="bg-gradient-to-br from-violet-500/10 to-purple-400/5 dark:from-violet-500/20 dark:to-purple-400/10 rounded-xl p-3">
                <Mail className="w-5 h-5 text-violet-500 mx-auto mb-1" />
                <p className="text-xs text-slate-500 dark:text-slate-400">Approvals</p>
                <p className="text-sm font-semibold text-slate-900 dark:text-white">{data?.pendingApprovals ?? 0}</p>
              </div>
            </div>
          </motion.div>

          {/* Workload Card */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.1 }}
            className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700"
          >
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Today's Workload</h3>
              <span className="text-xs text-slate-500 dark:text-slate-400">Live</span>
            </div>

            <div className="flex items-center justify-center mb-4">
              <div className="relative">
                <ResponsiveContainer width={160} height={160}>
                  <PieChart>
                    <Pie
                      data={incomeTotal === 0 ? [{ name: 'empty', value: 1, color: '#E2E8F0' }] : income}
                      cx="50%"
                      cy="50%"
                      innerRadius={55}
                      outerRadius={75}
                      paddingAngle={2}
                      dataKey="value"
                    >
                      {(incomeTotal === 0 ? [{ color: '#E2E8F0' }] : income).map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                  </PieChart>
                </ResponsiveContainer>
                <div className="absolute inset-0 flex items-center justify-center">
                  <div className="text-center">
                    <p className="text-xl font-bold text-slate-900 dark:text-white">{incomeTotal}</p>
                    <p className="text-[10px] text-slate-500">total</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="flex justify-center gap-6">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-violet-500" />
                <span className="text-xs text-slate-500 dark:text-slate-400">
                  Completed ({data?.completedToday ?? 0})
                </span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-orange-500" />
                <span className="text-xs text-slate-500 dark:text-slate-400">
                  Pending ({data?.pendingApprovals ?? 0})
                </span>
              </div>
            </div>

            <div className="mt-4 pt-4 border-t border-slate-100 dark:border-slate-700">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs text-slate-500 dark:text-slate-400">System Health</span>
                <span className="text-xs font-semibold text-slate-900 dark:text-white">{healthPct}%</span>
              </div>
              <div className="h-2 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-emerald-500 to-teal-400"
                  style={{ width: `${healthPct}%` }}
                />
              </div>
            </div>
          </motion.div>

          {/* Recent Tasks */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white dark:bg-slate-800 rounded-3xl p-6 shadow-xl shadow-slate-200/50 dark:shadow-slate-900/50 border border-slate-100 dark:border-slate-700"
          >
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Recent Tasks</h3>
              <Button variant="link" className="text-violet-500 text-xs p-0 h-auto" asChild>
                <a href="/boss/tasks">View All</a>
              </Button>
            </div>

            <div className="space-y-3">
              {(data?.recentTasks ?? []).length === 0 ? (
                <div className="flex flex-col items-center justify-center py-8 text-center text-slate-400">
                  <Inbox className="w-8 h-8 mb-2 opacity-50" />
                  <p className="text-sm">No tasks yet</p>
                </div>
              ) : (
                (data?.recentTasks ?? []).map((t, i) => (
                  <motion.div
                    key={t.id}
                    initial={{ opacity: 0, x: 10 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.3 + i * 0.05 }}
                    className="flex items-center justify-between p-2 rounded-xl hover:bg-slate-50 dark:hover:bg-slate-700/50 transition-colors"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span
                        className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${
                          statusColor[t.status] ?? 'bg-slate-400'
                        }`}
                      />
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-slate-900 dark:text-white truncate">
                          {t.title}
                        </p>
                        <p className="text-xs text-slate-500 dark:text-slate-400">
                          {t.status} · {formatDistanceToNow(new Date(t.created_at), { addSuffix: true })}
                        </p>
                      </div>
                    </div>
                  </motion.div>
                ))
              )}
            </div>
          </motion.div>
        </div>
      </div>
    </div>
  );
}
