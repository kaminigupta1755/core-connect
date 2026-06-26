/**
 * CONTROL PANEL CONTENT
 * Main content component for the black sidebar Control Panel
 * Contains all live operational sections
 * OPTIMIZED: Memoized components, simplified structure
 */

import React, { memo, useCallback } from 'react';
import { Activity, MessageCircle, ListTodo, Clock, Zap, Bell, Trophy } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { useAuth } from '@/hooks/useAuth';

const AMS_ALLOWED_ROLES = ['boss_owner', 'super_admin', 'admin', 'ceo', 'franchise', 'reseller', 'developer'];
const useCanAccessAMS = () => {
  const { userRole, isBossOwner } = useAuth();
  return isBossOwner || (!!userRole && AMS_ALLOWED_ROLES.includes(userRole));
};
import { LiveStatusIndicators } from './LiveStatusIndicators';
import { LiveChatBlock } from './LiveChatBlock';
import { LiveRunningTasks } from './LiveRunningTasks';
import { LiveCommitments } from './LiveCommitments';
import { QuickActions } from './QuickActions';
import { AlertsPreview } from './AlertsPreview';


interface ControlPanelContentProps {
  collapsed?: boolean;
}

interface SectionProps {
  icon: React.ElementType;
  title: string;
  collapsed?: boolean;
  children: React.ReactNode;
}

const Section = memo<SectionProps>(({ icon: Icon, title, collapsed, children }) => {
  if (collapsed) return null;
  
  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-1.5 px-1">
        <Icon className="w-3 h-3 text-white/50" />
        <span className="text-[9px] font-medium uppercase tracking-wider text-white/50">{title}</span>
      </div>
      {children}
    </div>
  );
});

Section.displayName = 'Section';

const CollapsedView = memo(() => {
  const navigate = useNavigate();

  const handleSystemStatus = useCallback(() => {
    toast.info('All systems operational');
  }, []);

  const handleOpenChat = useCallback(() => {
    toast.success('Opening live chat...');
  }, []);

  const handleOpenTasks = useCallback(() => {
    navigate('/boss/tasks');
  }, [navigate]);

  const handleOpenAlerts = useCallback(() => {
    navigate('/boss/alerts');
  }, [navigate]);

  const handleOpenAMS = useCallback(() => {
    navigate('/ams');
  }, [navigate]);

  return (
    <div className="flex flex-col items-center gap-3 py-3">
      <button 
        className="w-8 h-8 rounded-lg bg-emerald-500/20 flex items-center justify-center cursor-pointer transition-transform active:scale-95"
        title="System Online"
        onClick={handleSystemStatus}
      >
        <Activity className="w-4 h-4 text-emerald-400" />
      </button>
      <button 
        className="w-8 h-8 rounded-lg bg-blue-500/20 flex items-center justify-center cursor-pointer transition-transform active:scale-95"
        title="Live Chat"
        onClick={handleOpenChat}
      >
        <MessageCircle className="w-4 h-4 text-blue-400" />
      </button>
      <button 
        className="w-8 h-8 rounded-lg bg-amber-500/20 flex items-center justify-center cursor-pointer transition-transform active:scale-95"
        title="Tasks"
        onClick={handleOpenTasks}
      >
        <ListTodo className="w-4 h-4 text-amber-400" />
      </button>
      <button 
        className="w-8 h-8 rounded-lg bg-red-500/20 flex items-center justify-center cursor-pointer relative transition-transform active:scale-95"
        title="Alerts"
        onClick={handleOpenAlerts}
      >
        <Bell className="w-4 h-4 text-red-400" />
        <span className="absolute -top-1 -right-1 w-3 h-3 rounded-full bg-red-500 text-[8px] text-white flex items-center justify-center">3</span>
      </button>
      <button 
        className="w-8 h-8 rounded-lg bg-yellow-500/20 flex items-center justify-center cursor-pointer transition-transform active:scale-95"
        title="AMS Management"
        onClick={handleOpenAMS}
      >
        <Trophy className="w-4 h-4 text-yellow-400" />
      </button>
    </div>
  );
});

CollapsedView.displayName = 'CollapsedView';

export const ControlPanelContent: React.FC<ControlPanelContentProps> = memo(({ collapsed = false }) => {
  const navigate = useNavigate();

  if (collapsed) {
    return <CollapsedView />;
  }

  return (
    <div className="p-2 space-y-3 max-h-[280px] overflow-y-auto">
      {/* AMS Management — Award Management System control center */}
      <button
        onClick={() => navigate('/ams')}
        className="w-full group flex items-center gap-2 px-2.5 py-2 rounded-lg bg-gradient-to-r from-yellow-500/20 to-amber-500/10 border border-yellow-500/30 hover:from-yellow-500/30 hover:to-amber-500/20 transition-all active:scale-[0.98]"
      >
        <div className="w-7 h-7 rounded-md bg-yellow-500/30 flex items-center justify-center">
          <Trophy className="w-4 h-4 text-yellow-300" />
        </div>
        <div className="flex-1 text-left">
          <div className="text-[11px] font-semibold text-yellow-100">AMS Management</div>
          <div className="text-[9px] text-yellow-200/60">Awards · Badges · XP · Leaderboards</div>
        </div>
        <span className="text-[9px] px-1.5 py-0.5 rounded bg-yellow-500/30 text-yellow-100 font-medium">Open</span>
      </button>

      {/* Section 1: Live Status */}
      <Section icon={Activity} title="Live Status" collapsed={collapsed}>
        <LiveStatusIndicators />
      </Section>

      {/* Section 2: Live Chat */}
      <Section icon={MessageCircle} title="Support" collapsed={collapsed}>
        <LiveChatBlock />
      </Section>

      {/* Section 3: Running Tasks */}
      <Section icon={ListTodo} title="Running Tasks" collapsed={collapsed}>
        <LiveRunningTasks />
      </Section>

      {/* Section 4: Commitments */}
      <Section icon={Clock} title="Commitments" collapsed={collapsed}>
        <LiveCommitments />
      </Section>

      {/* Section 5: Quick Actions */}
      <Section icon={Zap} title="Quick Actions" collapsed={collapsed}>
        <QuickActions />
      </Section>

      {/* Section 6: Alerts Preview */}
      <Section icon={Bell} title="Alerts" collapsed={collapsed}>
        <AlertsPreview />
      </Section>
    </div>
  );
});

ControlPanelContent.displayName = 'ControlPanelContent';
