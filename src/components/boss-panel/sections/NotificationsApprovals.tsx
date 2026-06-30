/**
 * Boss Panel — Notifications & Approvals
 * Canonical view across every manager module. This is the only place where
 * notifications, approvals, tasks and announcements are surfaced for the boss.
 */
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Check, X, BellRing, Megaphone, ListChecks, Inbox } from 'lucide-react';
import { toast } from 'sonner';
import {
  useBossNotifications, useBossApprovals, useBossTasks, useBossAnnouncements,
  type BossModule,
} from '@/hooks/boss-core';

const MODULES: { value: BossModule | 'all'; label: string }[] = [
  { value: 'all', label: 'All modules' },
  { value: 'legal', label: 'Legal' }, { value: 'hr', label: 'HR' },
  { value: 'finance', label: 'Finance' }, { value: 'lead', label: 'Lead' },
  { value: 'franchise', label: 'Franchise' }, { value: 'reseller', label: 'Reseller' },
  { value: 'influencer', label: 'Influencer' }, { value: 'marketing', label: 'Marketing' },
  { value: 'seo', label: 'SEO' }, { value: 'pro', label: 'Pro' },
  { value: 'server', label: 'Server' }, { value: 'demo', label: 'Demo' },
  { value: 'ams', label: 'AMS' }, { value: 'security', label: 'Security' },
  { value: 'system', label: 'System' },
];

const sevColor: Record<string, string> = {
  info: 'bg-blue-500/15 text-blue-300',
  success: 'bg-emerald-500/15 text-emerald-300',
  warning: 'bg-amber-500/15 text-amber-300',
  critical: 'bg-red-500/15 text-red-300',
};

export function NotificationsApprovals() {
  const [filter, setFilter] = useState<BossModule | 'all'>('all');
  const mod = filter === 'all' ? undefined : filter;
  const notifs = useBossNotifications(mod);
  const appr = useBossApprovals({ module: mod, status: 'pending' });
  const tasks = useBossTasks(mod);
  const anns = useBossAnnouncements(mod);

  const decide = async (id: string, approve: boolean) => {
    const fn = approve ? appr.approve : appr.reject;
    const { error } = await fn(id);
    if (error) toast.error(error.message);
    else toast.success(approve ? 'Approved' : 'Rejected');
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold text-foreground">Notifications & Approvals</h1>
          <p className="text-sm text-muted-foreground">Single source of truth across every manager module.</p>
        </div>
        <Select value={filter} onValueChange={(v) => setFilter(v as any)}>
          <SelectTrigger className="w-[200px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {MODULES.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <Tabs defaultValue="approvals" className="w-full">
        <TabsList>
          <TabsTrigger value="approvals">Approvals ({appr.data.length})</TabsTrigger>
          <TabsTrigger value="notifications">Notifications ({notifs.data.length})</TabsTrigger>
          <TabsTrigger value="tasks">Tasks ({tasks.data.length})</TabsTrigger>
          <TabsTrigger value="announcements">Announcements ({anns.data.length})</TabsTrigger>
        </TabsList>

        <TabsContent value="approvals">
          <Card><CardHeader><CardTitle className="flex items-center gap-2"><Inbox className="w-4 h-4" />Pending approvals</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {appr.loading && <p className="text-sm text-muted-foreground">Loading…</p>}
              {!appr.loading && appr.data.length === 0 && <EmptyState label="No pending approvals." />}
              {appr.data.map((a) => (
                <div key={a.id} className="flex items-center justify-between gap-3 p-3 rounded-lg border border-border bg-card/40">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <Badge variant="outline" className="uppercase text-[10px]">{a.module}</Badge>
                      <span className="text-xs text-muted-foreground">{a.action_key}</span>
                    </div>
                    <p className="text-sm font-medium text-foreground truncate">{a.title}</p>
                    {a.description && <p className="text-xs text-muted-foreground truncate">{a.description}</p>}
                  </div>
                  <div className="flex gap-2 flex-shrink-0">
                    <Button size="sm" onClick={() => decide(a.id, true)}><Check className="w-4 h-4" /></Button>
                    <Button size="sm" variant="destructive" onClick={() => decide(a.id, false)}><X className="w-4 h-4" /></Button>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="notifications">
          <Card><CardHeader><CardTitle className="flex items-center gap-2"><BellRing className="w-4 h-4" />Notifications</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {notifs.loading && <p className="text-sm text-muted-foreground">Loading…</p>}
              {!notifs.loading && notifs.data.length === 0 && <EmptyState label="No notifications." />}
              {notifs.data.map((n) => (
                <div key={n.id} className="flex items-start justify-between gap-3 p-3 rounded-lg border border-border bg-card/40">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <Badge className={sevColor[n.severity]}>{n.severity}</Badge>
                      <Badge variant="outline" className="uppercase text-[10px]">{n.module}</Badge>
                      <span className="text-xs text-muted-foreground">{new Date(n.created_at).toLocaleString()}</span>
                    </div>
                    <p className="text-sm font-medium text-foreground">{n.title}</p>
                    {n.body && <p className="text-xs text-muted-foreground">{n.body}</p>}
                  </div>
                  {!n.read_at && <Button size="sm" variant="ghost" onClick={() => notifs.markRead(n.id)}>Mark read</Button>}
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="tasks">
          <Card><CardHeader><CardTitle className="flex items-center gap-2"><ListChecks className="w-4 h-4" />Tasks</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {tasks.loading && <p className="text-sm text-muted-foreground">Loading…</p>}
              {!tasks.loading && tasks.data.length === 0 && <EmptyState label="No tasks." />}
              {tasks.data.map((t) => (
                <div key={t.id} className="p-3 rounded-lg border border-border bg-card/40">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge variant="outline" className="uppercase text-[10px]">{t.module}</Badge>
                    <Badge>{t.status}</Badge>
                    {t.due_at && <span className="text-xs text-muted-foreground">due {new Date(t.due_at).toLocaleDateString()}</span>}
                  </div>
                  <p className="text-sm font-medium text-foreground">{t.title}</p>
                  {t.description && <p className="text-xs text-muted-foreground">{t.description}</p>}
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="announcements">
          <Card><CardHeader><CardTitle className="flex items-center gap-2"><Megaphone className="w-4 h-4" />Announcements</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {anns.loading && <p className="text-sm text-muted-foreground">Loading…</p>}
              {!anns.loading && anns.data.length === 0 && <EmptyState label="No announcements." />}
              {anns.data.map((a) => (
                <div key={a.id} className="p-3 rounded-lg border border-border bg-card/40">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge className={sevColor[a.severity]}>{a.severity}</Badge>
                    <Badge variant="outline" className="uppercase text-[10px]">{a.module}</Badge>
                    <span className="text-xs text-muted-foreground">{new Date(a.starts_at).toLocaleString()}</span>
                  </div>
                  <p className="text-sm font-medium text-foreground">{a.title}</p>
                  {a.body && <p className="text-xs text-muted-foreground">{a.body}</p>}
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function EmptyState({ label }: { label: string }) {
  return (
    <div className="py-10 text-center text-sm text-muted-foreground border border-dashed border-border rounded-lg">
      {label}
    </div>
  );
}
