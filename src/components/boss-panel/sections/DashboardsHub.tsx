import { Link } from 'react-router-dom';
import { Card } from '@/components/ui/card';
import {
  Users, Briefcase, DollarSign, Scale, Megaphone, TrendingUp, FlaskConical,
  Heart, Search, LifeBuoy, HeartHandshake, AlertTriangle, Code2, Store,
  Building2, UserPlus, Sparkles, Bot, MessageSquare, Plug, Package, ClipboardList,
  KeyRound, Bell, Crown, Shield, Activity, Layers, Trophy, Server
} from 'lucide-react';

type DashItem = { label: string; path: string; icon: any; desc?: string };

const groups: { title: string; items: DashItem[] }[] = [
  {
    title: 'Executive & Ownership',
    items: [
      { label: 'Owner Console', path: '/owner', icon: Crown, desc: 'Boss-owner only' },
      { label: 'Prime', path: '/prime', icon: Sparkles },
      { label: 'AMS Command Center', path: '/ams', icon: Trophy, desc: 'Awards / achievements' },
    ],
  },
  {
    title: 'Operations Managers',
    items: [
      { label: 'Lead Manager', path: '/lead-manager', icon: UserPlus },
      { label: 'Task Manager', path: '/task-manager', icon: ClipboardList },
      { label: 'Finance Manager', path: '/finance-manager', icon: DollarSign },
      { label: 'Legal & Compliance', path: '/legal-manager', icon: Scale },
      { label: 'Marketing Manager', path: '/marketing-manager', icon: Megaphone },
      { label: 'Performance Manager', path: '/performance-manager', icon: TrendingUp },
      { label: 'HR Dashboard', path: '/hr', icon: Users },
      { label: 'SEO Dashboard', path: '/seo', icon: Search },
      { label: 'R&D Dashboard', path: '/rnd', icon: FlaskConical },
    ],
  },
  {
    title: 'Customer & Support',
    items: [
      { label: 'Support Dashboard', path: '/support', icon: LifeBuoy },
      { label: 'Sales Support', path: '/sales-support', icon: Briefcase },
      { label: 'Client Success', path: '/client-success', icon: HeartHandshake },
      { label: 'Incident & Crisis', path: '/incident-crisis', icon: AlertTriangle },
      { label: 'Internal Support AI', path: '/internal-support-ai', icon: Bot },
      { label: 'Internal Chat', path: '/internal-chat', icon: MessageSquare },
    ],
  },
  {
    title: 'Partners & Channels',
    items: [
      { label: 'Franchise Dashboard', path: '/franchise', icon: Building2 },
      { label: 'Franchise Management', path: '/franchise-management', icon: Building2 },
      { label: 'Reseller Dashboard', path: '/reseller', icon: Store },
      { label: 'Reseller Portal', path: '/reseller-portal', icon: Store },
      { label: 'Influencer Dashboard', path: '/influencer', icon: Heart },
      { label: 'Influencer Manager', path: '/influencer-manager', icon: Heart },
    ],
  },
  {
    title: 'Product & Catalog',
    items: [
      { label: 'Demo Manager', path: '/demo-manager', icon: Package },
      { label: 'Product Demo Manager', path: '/product-demo-manager', icon: Package },
      { label: 'Demo Directory', path: '/demo-directory', icon: Layers },
      { label: 'Sectors', path: '/sectors', icon: Layers },
    ],
  },
  {
    title: 'Engineering & Platform',
    items: [
      { label: 'Developer Dashboard', path: '/developer', icon: Code2 },
      { label: 'Over AI', path: '/over-ai', icon: Bot },
      { label: 'API Integration', path: '/api-integration', icon: Plug },
      { label: 'Notifications Console', path: '/notifications', icon: Bell },
      { label: 'System Settings', path: '/system-settings', icon: Server },
      { label: 'Settings', path: '/settings', icon: KeyRound },
    ],
  },
];

export function DashboardsHub() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
          <Shield className="w-6 h-6 text-primary" /> Dashboards Hub
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Centralised access to every real dashboard in the platform — controlled from the Control Panel.
        </p>
      </div>

      {groups.map((g) => (
        <section key={g.title} className="space-y-3">
          <h2 className="text-xs uppercase tracking-widest text-muted-foreground flex items-center gap-2">
            <Activity className="w-3.5 h-3.5" /> {g.title}
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
            {g.items.map((item) => {
              const Icon = item.icon;
              return (
                <Link key={item.path} to={item.path} className="group">
                  <Card className="p-4 h-full bg-card/60 backdrop-blur border-border/60 hover:border-primary/60 hover:bg-card transition-all">
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center shrink-0 group-hover:bg-primary/20 transition-colors">
                        <Icon className="w-5 h-5 text-primary" />
                      </div>
                      <div className="min-w-0">
                        <div className="font-semibold text-sm text-foreground truncate">{item.label}</div>
                        <div className="text-[11px] text-muted-foreground truncate">{item.desc ?? item.path}</div>
                      </div>
                    </div>
                  </Card>
                </Link>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}

export default DashboardsHub;
