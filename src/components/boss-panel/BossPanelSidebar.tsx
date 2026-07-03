import React from 'react';
import { motion } from 'framer-motion';
import { 
  LayoutDashboard, 
  Activity, 
  Network, 
  Users, 
  Shield, 
  Boxes,
  Package,
  DollarSign,
  FileSearch,
  Lock,
  Settings,
  ChevronLeft,
  ChevronRight,
  Code2,
  Server,
  Brain,
  KeyRound,
  UserCog,
  Zap,
  BellRing
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { BossPanelSection } from './BossPanelLayout';

interface BossPanelSidebarProps {
  activeSection: BossPanelSection;
  onSectionChange: (section: BossPanelSection) => void;
  collapsed: boolean;
  onCollapsedChange: (collapsed: boolean) => void;
}

// LOCKED: Menu items with fixed icons (20px)
const menuItems: { id: BossPanelSection; label: string; icon: React.ElementType }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'dashboards-hub', label: 'Dashboards Hub', icon: Network },
  { id: 'notifications-approvals', label: 'Notifications & Approvals', icon: BellRing },
  { id: 'self-healing', label: 'Self-Healing', icon: Zap },
  { id: 'live-activity', label: 'Live Activity Stream', icon: Activity },
  { id: 'hierarchy', label: 'Hierarchy Control', icon: Network },
  { id: 'super-admins', label: 'Administrators', icon: Users },
  { id: 'roles', label: 'Roles & Permissions', icon: Shield },
  { id: 'modules', label: 'System Modules', icon: Boxes },
  { id: 'products', label: 'Product & Demo', icon: Package },
  { id: 'vala-ai', label: 'VALA AI', icon: Brain },
  { id: 'auth-dashboard', label: 'Auth Dashboard', icon: KeyRound },
  { id: 'auth-management', label: 'Auth Management', icon: UserCog },
  { id: 'revenue', label: 'Revenue Snapshot', icon: DollarSign },
  { id: 'audit', label: 'Audit & Blackbox', icon: FileSearch },
  { id: 'security', label: 'Security & Legal', icon: Lock },
  { id: 'codepilot', label: 'CodePilot', icon: Code2 },
  { id: 'server-hosting', label: 'CodeLab Cloud', icon: Server },
  { id: 'settings', label: 'Settings', icon: Settings },
];

export function BossPanelSidebar({
  activeSection,
  onSectionChange,
  collapsed,
  onCollapsedChange
}: BossPanelSidebarProps) {
  return (
    <motion.aside
      initial={false}
      animate={{ width: collapsed ? 80 : 260 }}
      className="fixed left-0 top-16 h-[calc(100vh-64px)] z-40 flex flex-col border-r border-border bg-background/70 backdrop-blur-xl"
    >
      {/* Collapse Toggle */}
      <button
        onClick={() => onCollapsedChange(!collapsed)}
        className="absolute -right-3 top-6 flex items-center justify-center rounded-full w-6 h-6 bg-primary text-primary-foreground border-2 border-background shadow-[var(--shadow-card-hover)] glow-primary"
      >
        {collapsed ? <ChevronRight className="w-3.5 h-3.5" /> : <ChevronLeft className="w-3.5 h-3.5" />}
      </button>

      {/* Navigation */}
      <nav className="flex-1 py-4 px-3 space-y-1 overflow-y-auto">
        {menuItems.map((item) => {
          const Icon = item.icon;
          const isActive = activeSection === item.id;

          return (
            <motion.button
              key={item.id}
              onClick={() => onSectionChange(item.id)}
              className={cn(
                "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-all border-l-2",
                isActive
                  ? "bg-primary/15 text-foreground border-primary glow-primary"
                  : "text-muted-foreground border-transparent hover:bg-card/60 hover:text-foreground"
              )}
              whileTap={{ scale: 0.98 }}
            >
              <Icon className={cn("w-5 h-5 flex-shrink-0", isActive ? "text-primary" : "text-muted-foreground")} />
              {!collapsed && (
                <span className="truncate text-sm font-medium">{item.label}</span>
              )}
            </motion.button>
          );
        })}
      </nav>

      {/* Footer */}
      {!collapsed && (
        <div className="p-4 border-t border-border">
          <div className="text-center uppercase tracking-widest text-[10px] text-muted-foreground">
            Control Principle
          </div>
          <div className="text-center mt-1 text-[9px] text-foreground/80">
            See Everything • Change Nothing Casually
          </div>
        </div>
      )}
    </motion.aside>
  );
}
