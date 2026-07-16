import { Link } from "react-router-dom";
import { LayoutDashboard, Shield, Users, Briefcase, Code, Megaphone, Scale,
  DollarSign, BarChart3, LifeBuoy, Sparkles, Building2, Globe, Bell,
  MessageSquare, Server, Bot, Trophy, UserCog, Star, ShoppingBag,
  Handshake, Settings, KeyRound, ClipboardList, Activity, AlertTriangle,
  FlaskConical, Wrench } from "lucide-react";

type Item = { to: string; label: string; group: string; icon: any; desc?: string };

const ITEMS: Item[] = [
  // Core
  { to: "/dashboard", label: "My Dashboard", group: "Core", icon: LayoutDashboard, desc: "Personal role home" },
  { to: "/settings", label: "Settings", group: "Core", icon: Settings },
  { to: "/system-settings", label: "System Settings", group: "Core", icon: Wrench },
  { to: "/notifications", label: "Notifications", group: "Core", icon: Bell },
  { to: "/personal-chat", label: "Personal Chat", group: "Core", icon: MessageSquare },
  { to: "/internal-chat", label: "Internal Chat", group: "Core", icon: MessageSquare },
  { to: "/change-password", label: "Change Password", group: "Core", icon: KeyRound },

  // Control / Admin
  { to: "/boss", label: "Global Control Center", group: "Control", icon: Shield, desc: "Boss / Owner only" },
  { to: "/owner", label: "Owner Dashboard", group: "Control", icon: Star },
  { to: "/admin/bulk-users", label: "Bulk User Creation", group: "Control", icon: Users },
  { to: "/admin/roles", label: "Role Manager", group: "Control", icon: UserCog },

  // Managers
  { to: "/lead-manager", label: "Lead Manager", group: "Managers", icon: Users },
  { to: "/task-manager", label: "Task Manager", group: "Managers", icon: ClipboardList },
  { to: "/demo-manager", label: "Demo Manager", group: "Managers", icon: Briefcase },
  { to: "/product-demo-manager", label: "Product Demo Manager", group: "Managers", icon: ShoppingBag },
  { to: "/finance-manager", label: "Finance Manager", group: "Managers", icon: DollarSign },
  { to: "/legal-manager", label: "Legal & Compliance", group: "Managers", icon: Scale },
  { to: "/marketing-manager", label: "Marketing Manager", group: "Managers", icon: Megaphone },
  { to: "/performance-manager", label: "Performance Manager", group: "Managers", icon: BarChart3 },
  { to: "/hr", label: "HR Dashboard", group: "Managers", icon: Users },
  { to: "/seo", label: "SEO Dashboard", group: "Managers", icon: Globe },
  { to: "/rnd", label: "R&D Dashboard", group: "Managers", icon: FlaskConical },
  { to: "/support", label: "Support Dashboard", group: "Managers", icon: LifeBuoy },
  { to: "/sales-support", label: "Sales Support", group: "Managers", icon: Handshake },
  { to: "/client-success", label: "Client Success", group: "Managers", icon: Star },
  { to: "/incident-crisis", label: "Incident & Crisis", group: "Managers", icon: AlertTriangle },

  // Role-specific
  { to: "/developer", label: "Developer Dashboard", group: "Role", icon: Code },
  { to: "/franchise", label: "Franchise Dashboard", group: "Role", icon: Building2 },
  { to: "/franchise-management", label: "Franchise Management", group: "Role", icon: Building2 },
  { to: "/reseller", label: "Reseller Dashboard", group: "Role", icon: Handshake },
  { to: "/reseller-portal", label: "Reseller Portal", group: "Role", icon: Handshake },
  { to: "/influencer", label: "Influencer Dashboard", group: "Role", icon: Sparkles },
  { to: "/influencer-manager", label: "Influencer Manager", group: "Role", icon: Sparkles },
  { to: "/prime", label: "Prime User", group: "Role", icon: Star },
  { to: "/simple-user", label: "Simple User", group: "Role", icon: Users },
  { to: "/client-portal", label: "Client Portal", group: "Role", icon: Briefcase },

  // AI / Integration
  { to: "/over-ai", label: "Over AI", group: "AI & Integration", icon: Bot },
  { to: "/internal-support-ai", label: "Internal Support AI", group: "AI & Integration", icon: Bot },
  { to: "/api-integration", label: "API Integration", group: "AI & Integration", icon: Server },

  // AMS
  { to: "/ams", label: "Achievement Management", group: "Achievements", icon: Trophy },
];

const GROUPS = ["Core", "Control", "Managers", "Role", "AI & Integration", "Achievements"] as const;

export default function DashboardDirectory() {
  return (
    <div className="min-h-screen bg-background text-foreground p-6 md:p-10">
      <div className="max-w-7xl mx-auto">
        <header className="mb-8">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 flex items-center gap-3">
            <Activity className="w-8 h-8 text-primary" /> All Dashboards
          </h1>
          <p className="text-muted-foreground">
            Complete directory of every dashboard in the platform. Access is still enforced by role — you'll be redirected if not permitted.
          </p>
        </header>

        {GROUPS.map((g) => {
          const items = ITEMS.filter((i) => i.group === g);
          if (!items.length) return null;
          return (
            <section key={g} className="mb-10">
              <h2 className="text-xl font-semibold mb-4 text-primary/90">{g}</h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                {items.map((it) => {
                  const Icon = it.icon;
                  return (
                    <Link
                      key={it.to}
                      to={it.to}
                      className="group border border-border rounded-xl p-4 bg-card hover:bg-accent hover:border-primary/50 transition-all"
                    >
                      <div className="flex items-start gap-3">
                        <div className="p-2 rounded-lg bg-primary/10 text-primary group-hover:scale-110 transition-transform">
                          <Icon className="w-5 h-5" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="font-semibold truncate">{it.label}</div>
                          <div className="text-xs text-muted-foreground truncate">{it.to}</div>
                          {it.desc && <div className="text-xs text-muted-foreground/80 mt-1">{it.desc}</div>}
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
