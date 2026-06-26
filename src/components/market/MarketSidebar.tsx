import {
  Store, Building2, LayoutGrid, Sparkles, Flame, Rocket, Star, Crown,
  Tag, Repeat, Handshake, ShoppingBag, Network, PenTool, Download,
  Calendar, GraduationCap, LifeBuoy,
} from "lucide-react";
import { useState } from "react";

const groups: { label: string; items: { label: string; icon: React.ComponentType<{ className?: string }>; active?: boolean; badge?: string; tone?: "primary" | "gold" | "magenta" | "success" }[] }[] = [
  {
    label: "Marketplace",
    items: [
      { label: "Marketplace Home", icon: Store, active: true },
      { label: "Industries", icon: Building2 },
      { label: "All Software", icon: LayoutGrid, badge: "1,284" },
      { label: "Featured", icon: Sparkles, tone: "primary" },
      { label: "Trending", icon: Flame, tone: "magenta", badge: "Hot" },
      { label: "New Launches", icon: Rocket, badge: "62" },
      { label: "Top Rated", icon: Star, tone: "gold" },
      { label: "Best Sellers", icon: Crown, tone: "gold" },
      { label: "Lifetime Deals", icon: Tag, tone: "success" },
      { label: "Subscriptions", icon: Repeat },
    ],
  },
  {
    label: "Ecosystem",
    items: [
      { label: "Reseller Zone", icon: Handshake, tone: "primary" },
      { label: "Vendor Zone", icon: ShoppingBag, tone: "magenta" },
      { label: "Franchise Zone", icon: Network, tone: "gold" },
      { label: "Author Zone", icon: PenTool },
    ],
  },
  {
    label: "Resources",
    items: [
      { label: "Downloads", icon: Download },
      { label: "Events", icon: Calendar, badge: "Live" },
      { label: "Academy", icon: GraduationCap },
      { label: "Support", icon: LifeBuoy },
    ],
  },
];

export function MarketSidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <>
      {/* desktop */}
      <aside className="hidden lg:flex w-[280px] shrink-0 sticky top-[72px] self-start h-[calc(100vh-72px)] border-r border-border bg-sidebar/60 backdrop-blur-xl flex-col">
        <SidebarBody />
      </aside>

      {/* mobile drawer */}
      {open && (
        <div className="lg:hidden fixed inset-0 z-50 bg-background/70 backdrop-blur-sm" onClick={onClose}>
          <aside className="absolute left-0 top-0 bottom-0 w-[280px] bg-sidebar border-r border-border animate-rise" onClick={(e) => e.stopPropagation()}>
            <SidebarBody />
          </aside>
        </div>
      )}
    </>
  );
}

function SidebarBody() {
  return (
    <nav className="flex-1 overflow-y-auto p-4 space-y-5">
      {groups.map((g) => (
        <Section key={g.label} label={g.label} items={g.items} />
      ))}
      <div className="panel p-4">
        <div className="text-[10px] uppercase tracking-widest text-gold flex items-center gap-1.5">
          <Crown className="h-3 w-3" /> Vala Pro
        </div>
        <p className="mt-1.5 text-xs text-muted-foreground">Lifetime access to 1,284 products. Save 68%.</p>
        <button className="mt-3 w-full h-9 rounded-lg bg-[image:var(--gradient-gold)] text-[#1a1200] text-xs font-bold hover:opacity-90">
          Upgrade — $499
        </button>
      </div>
    </nav>
  );
}

function Section({ label, items }: { label: string; items: any[] }) {
  return (
    <div>
      <div className="px-2.5 mb-1.5 text-[10px] uppercase tracking-[0.22em] text-muted-foreground/80">{label}</div>
      <ul className="space-y-0.5">
        {items.map((it) => {
          const Icon = it.icon;
          const tone =
            it.tone === "gold" ? "text-gold" :
            it.tone === "magenta" ? "text-magenta" :
            it.tone === "success" ? "text-success" :
            it.active ? "text-primary" : "text-sidebar-foreground/85";
          const badgeCls =
            it.tone === "gold" ? "border-gold/40 text-gold bg-gold/10" :
            it.tone === "magenta" ? "border-magenta/40 text-magenta bg-magenta/10" :
            it.tone === "success" ? "border-success/40 text-success bg-success/10" :
            "border-border text-muted-foreground bg-background/40";
          return (
            <li key={it.label}>
              <button className={`w-full flex items-center gap-2.5 px-2.5 h-9 rounded-lg text-sm transition-colors border ${
                it.active ? "bg-primary/10 border-primary/40 glow-primary" : "hover:bg-sidebar-accent border-transparent"
              }`}>
                <Icon className={`h-4 w-4 ${tone}`} />
                <span className={`flex-1 text-left ${it.active ? "text-foreground font-medium" : ""}`}>{it.label}</span>
                {it.badge && <span className={`text-mono text-[10px] px-1.5 py-0.5 rounded border ${badgeCls}`}>{it.badge}</span>}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export function useSidebarToggle() {
  const [open, setOpen] = useState(false);
  return { open, setOpen };
}
