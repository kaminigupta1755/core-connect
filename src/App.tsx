import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "sonner";
import { TooltipProvider } from "@radix-ui/react-tooltip";

import { AuthProvider } from "@/hooks/useAuth";
import { GlobalRealtimeProvider } from "@/providers/GlobalRealtimeProvider";

import RequireAuth from "@/components/auth/RequireAuth";
import RequireRole from "@/components/auth/RequireRole";

// Public / core pages
import Index from "@/pages/Index";
import Homepage from "@/pages/Homepage";
import Auth from "@/pages/Auth";
import NotFound from "@/pages/NotFound";
import Settings from "@/pages/Settings";
import Dashboard from "@/pages/Dashboard";
import DashboardDirectory from "@/pages/DashboardDirectory";
import SystemSettings from "@/pages/SystemSettings";
import SessionExpiredPage from "@/pages/error/SessionExpiredPage";

// Auth flows
import RoleBasedLogin from "@/pages/auth/RoleBasedLogin";
import EasyAuth from "@/pages/auth/EasyAuth";
import Logout from "@/pages/auth/Logout";
import OTPVerify from "@/pages/auth/OTPVerify";
import DeviceVerify from "@/pages/auth/DeviceVerify";
import IPVerify from "@/pages/auth/IPVerify";
import ForgotPassword from "@/pages/auth/ForgotPassword";
import ResetPassword from "@/pages/auth/ResetPassword";
import AccountSuspension from "@/pages/auth/AccountSuspension";
import AccessDenied from "@/pages/auth/AccessDenied";
import ChangePassword from "@/pages/auth/ChangePassword";
import PendingApproval from "@/pages/auth/PendingApproval";
import UnifiedLogin from "@/pages/auth/UnifiedLogin";
import DemoLogin from "@/pages/DemoLogin";

// Admin
import BulkUserCreation from "@/pages/admin/BulkUserCreation";
import RoleManagerPage from "@/pages/admin/RoleManagerPage";
import SecureAdminDashboard from "@/pages/admin/SecureAdminDashboard";
import SuperAdminDashboard from "@/pages/SuperAdminDashboard";
import CEODashboard from "@/pages/super-admin-system/RoleSwitch/CEODashboard";

// Boss / Owner — single Command Center
import BossPanel from "@/pages/BossPanel";
import RequireBossOwner from "@/components/auth/RequireBossOwner";
import SoftwareWalaOwnerDashboard from "@/pages/owner/SoftwareWalaOwnerDashboard";


// Manager dashboards
import LeadManager from "@/pages/LeadManager";
import TaskManager from "@/pages/TaskManager";
import DemoManagerDashboard from "@/pages/DemoManagerDashboard";
import ProductDemoManager from "@/pages/ProductDemoManager";
import FinanceManager from "@/pages/FinanceManager";
import LegalComplianceManager from "@/pages/LegalComplianceManager";
import MarketingManager from "@/pages/MarketingManager";
import PerformanceManager from "@/pages/PerformanceManager";
import RnDDashboard from "@/pages/RnDDashboard";
import HRDashboard from "@/pages/HRDashboard";
import SEODashboard from "@/pages/SEODashboard";
import SupportDashboard from "@/pages/SupportDashboard";
import SalesSupportDashboard from "@/pages/SalesSupportDashboard";
import ClientSuccessDashboard from "@/pages/ClientSuccessDashboard";
import IncidentCrisisDashboard from "@/pages/IncidentCrisisDashboard";

// Role-based dashboards
import DeveloperDashboard from "@/pages/DeveloperDashboard";
import SecureDeveloperDashboard from "@/pages/developer/SecureDeveloperDashboard";
import FranchiseDashboard from "@/pages/FranchiseDashboard";
import FranchiseOwnerDashboard from "@/pages/franchise/Dashboard";
import FranchiseLanding from "@/pages/FranchiseLanding";
import FranchiseManagement from "@/pages/FranchiseManagement";
import ResellerDashboard from "@/pages/ResellerDashboard";
import ResellerLanding from "@/pages/ResellerLanding";
import ResellerPortal from "@/pages/ResellerPortal";
import InfluencerDashboard from "@/pages/InfluencerDashboard";
import InfluencerManager from "@/pages/InfluencerManager";
import PrimeUserDashboard from "@/pages/PrimeUserDashboard";
import SimpleUserDashboard from "@/pages/SimpleUserDashboard";
import UserDashboard from "@/pages/user/UserDashboard";
import ClientPortal from "@/pages/ClientPortal";


// Demos & marketplace
import DemoAccess from "@/pages/DemoAccess";
import DemoCredentials from "@/pages/DemoCredentials";
import DemoDirectory from "@/pages/DemoDirectory";
import DemoShowcase from "@/pages/DemoShowcase";
import PremiumDemoShowcase from "@/pages/PremiumDemoShowcase";
import SimpleDemoList from "@/pages/SimpleDemoList";
import SimpleDemoView from "@/pages/SimpleDemoView";
import SimpleLanding from "@/pages/SimpleLanding";
import SimpleCheckout from "@/pages/SimpleCheckout";
import SectorsBrowse from "@/pages/SectorsBrowse";
import SubCategoryDemos from "@/pages/SubCategoryDemos";
import CategoryOnboarding from "@/pages/CategoryOnboarding";

// Special dashboards
import OverAI from "@/pages/OverAI";
import InternalChat from "@/pages/InternalChat";
import PersonalChat from "@/pages/PersonalChat";
import InternalSupportAI from "@/pages/InternalSupportAI";
import NotificationBuzzerConsole from "@/pages/NotificationBuzzerConsole";
import APIIntegrationDashboard from "@/pages/APIIntegrationDashboard";
import AIOptimizationConsole from "@/pages/ai-console/AIOptimizationConsole";
import APIManagerDashboard from "@/pages/api-manager/APIManagerDashboard";
import SecureAPIAIManagerDashboard from "@/pages/api-ai-manager/SecureAPIAIManagerDashboard";
import ServerManagerDashboard from "@/pages/server-manager/ServerManagerDashboard";
import SecurityCommandCenter from "@/pages/security-command/SecurityCommandCenter";
import SafeAssistDashboard from "@/pages/safe-assist/SafeAssistDashboard";
import AssistManagerDashboard from "@/pages/assist-manager/AssistManagerDashboard";
import PromiseTrackerDashboard from "@/pages/promise-tracker/PromiseTrackerDashboard";
import PromiseManagementDashboard from "@/pages/promise-management/PromiseManagementDashboard";
import SalesCRMDashboard from "@/pages/sales-crm/SalesCRMDashboard";
import SalesCRMAuthPage from "@/pages/sales-crm/SalesCRMAuthPage";
import ApplyPortal from "@/pages/ApplyPortal";
import CareerPortal from "@/pages/CareerPortal";

// Achievement Management System
import { AMSLayout, AMSOverview, Achievements, Badges, Trophies, Rewards, Levels, Milestones, Leaderboards, XPEngine, Streaks, MyProgress, MyAchievements, MyBadges, MyTrophies, MyRewards, Claims, Notifications, Analytics, AuditLogs, ClaimApprovals, RolePermissions, Seasons, Categories, Integrations, AMSSettings } from "@/pages/ams";

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <BrowserRouter>
          <AuthProvider>
            <GlobalRealtimeProvider>
              <Toaster position="top-right" richColors closeButton />
              <Routes>
                {/* Public */}
                <Route path="/" element={<Index />} />
                <Route path="/home" element={<Index />} />
                <Route path="/landing" element={<SimpleLanding />} />
                <Route path="/franchise-landing" element={<FranchiseLanding />} />
                <Route path="/reseller-landing" element={<ResellerLanding />} />
                <Route path="/apply" element={<ApplyPortal />} />
                <Route path="/careers" element={<CareerPortal />} />

                {/* Auth */}
                <Route path="/auth" element={<Auth />} />
                {/* All legacy login routes consolidate to the single futuristic /auth gateway */}
                <Route path="/login" element={<Navigate to="/auth" replace />} />
                <Route path="/unified-login" element={<Navigate to="/auth" replace />} />
                <Route path="/easy-auth" element={<Navigate to="/auth" replace />} />
                <Route path="/demo-login" element={<Navigate to="/auth" replace />} />
                <Route path="/signin" element={<Navigate to="/auth" replace />} />
                <Route path="/sign-in" element={<Navigate to="/auth" replace />} />
                <Route path="/logout" element={<Logout />} />
                <Route path="/otp-verify" element={<OTPVerify />} />
                <Route path="/device-verify" element={<DeviceVerify />} />
                <Route path="/ip-verify" element={<IPVerify />} />
                <Route path="/forgot-password" element={<ForgotPassword />} />
                <Route path="/reset-password" element={<ResetPassword />} />
                <Route path="/change-password" element={<ChangePassword />} />
                <Route path="/pending-approval" element={<PendingApproval />} />
                <Route path="/account-suspension" element={<AccountSuspension />} />
                <Route path="/access-denied" element={<AccessDenied />} />
                <Route path="/session-expired" element={<SessionExpiredPage />} />

                {/* Demos / Marketplace */}
                <Route path="/demos" element={<SimpleDemoList />} />
                <Route path="/demos/public" element={<Navigate to="/demos" replace />} />
                <Route path="/demo/:id" element={<SimpleDemoView />} />
                <Route path="/demo-access" element={<DemoAccess />} />
                <Route path="/demo-credentials" element={<DemoCredentials />} />
                <Route path="/demo-directory" element={<DemoDirectory />} />
                <Route path="/demo-showcase" element={<DemoShowcase />} />
                <Route path="/premium-demos" element={<PremiumDemoShowcase />} />
                <Route path="/checkout" element={<SimpleCheckout />} />
                <Route path="/sectors" element={<SectorsBrowse />} />
                <Route path="/sectors/:category" element={<SubCategoryDemos />} />
                <Route path="/category-onboarding" element={<CategoryOnboarding />} />

                {/* Authenticated user */}
                <Route path="/dashboard" element={<RequireAuth><Dashboard /></RequireAuth>} />
                <Route path="/me" element={<Navigate to="/dashboard" replace />} />
                <Route path="/dashboards" element={<RequireAuth><DashboardDirectory /></RequireAuth>} />
                <Route path="/settings" element={<RequireAuth><Settings /></RequireAuth>} />
                <Route path="/system-settings" element={<RequireAuth><SystemSettings /></RequireAuth>} />
                <Route path="/client-portal" element={<RequireAuth><ClientPortal /></RequireAuth>} />
                <Route path="/simple-user" element={<RequireAuth><SimpleUserDashboard /></RequireAuth>} />
                <Route path="/user-dashboard" element={<RequireAuth><UserDashboard /></RequireAuth>} />
                <Route path="/user/dashboard" element={<RequireAuth><UserDashboard /></RequireAuth>} />
                <Route path="/prime" element={<RequireAuth><PrimeUserDashboard /></RequireAuth>} />
                <Route path="/prime-user" element={<Navigate to="/prime" replace />} />
                <Route path="/personal-chat" element={<RequireAuth><PersonalChat /></RequireAuth>} />
                <Route path="/internal-chat" element={<RequireAuth><InternalChat /></RequireAuth>} />
                <Route path="/notifications" element={<RequireAuth><NotificationBuzzerConsole /></RequireAuth>} />

                {/* Global Control Center — STRICTLY boss_owner only.
                    Wrong roles get redirected to their own role home (see src/lib/roleRoutes.ts). */}
                <Route path="/boss" element={<RequireBossOwner><BossPanel /></RequireBossOwner>} />
                <Route path="/boss/*" element={<RequireBossOwner><BossPanel /></RequireBossOwner>} />
                <Route path="/command-center" element={<Navigate to="/boss" replace />} />
                <Route path="/owner" element={<RequireRole allowed={["boss_owner"]}><SoftwareWalaOwnerDashboard /></RequireRole>} />
                <Route path="/super-admin-home" element={<RequireRole allowed={["super_admin"]}><SuperAdminDashboard /></RequireRole>} />
                <Route path="/super-admin-dashboard" element={<Navigate to="/super-admin-home" replace />} />
                <Route path="/super-admin" element={<Navigate to="/super-admin-home" replace />} />
                <Route path="/super-admin/*" element={<Navigate to="/super-admin-home" replace />} />
                <Route path="/ceo-dashboard" element={<RequireRole allowed={["ceo"]}><CEODashboard /></RequireRole>} />

                {/* Admin */}
                <Route path="/admin-dashboard" element={<RequireRole allowed={["admin"]}><SecureAdminDashboard /></RequireRole>} />
                <Route path="/admin" element={<Navigate to="/admin-dashboard" replace />} />
                <Route path="/admin/bulk-users" element={<RequireRole allowed={["boss_owner", "ceo", "admin"]}><BulkUserCreation /></RequireRole>} />
                <Route path="/admin/roles" element={<RequireRole allowed={["boss_owner", "ceo", "admin"]}><RoleManagerPage /></RequireRole>} />


                {/* Managers */}
                <Route path="/lead-manager" element={<RequireAuth><LeadManager /></RequireAuth>} />
                <Route path="/leads" element={<Navigate to="/lead-manager" replace />} />
                <Route path="/task-manager" element={<RequireAuth><TaskManager /></RequireAuth>} />
                <Route path="/tasks" element={<Navigate to="/task-manager" replace />} />
                <Route path="/demo-manager" element={<RequireAuth><DemoManagerDashboard /></RequireAuth>} />
                <Route path="/product-demo-manager" element={<RequireAuth><ProductDemoManager /></RequireAuth>} />
                <Route path="/finance-manager" element={<RequireAuth><FinanceManager /></RequireAuth>} />
                <Route path="/finance" element={<Navigate to="/finance-manager" replace />} />
                <Route path="/legal-manager" element={<RequireAuth><LegalComplianceManager /></RequireAuth>} />
                <Route path="/legal" element={<Navigate to="/legal-manager" replace />} />
                <Route path="/legal-manager-secure" element={<Navigate to="/legal-manager" replace />} />
                <Route path="/marketing-manager" element={<RequireAuth><MarketingManager /></RequireAuth>} />
                <Route path="/marketing" element={<Navigate to="/marketing-manager" replace />} />
                <Route path="/marketing-manager-secure" element={<Navigate to="/marketing-manager" replace />} />
                <Route path="/performance-manager" element={<RequireAuth><PerformanceManager /></RequireAuth>} />
                <Route path="/performance" element={<Navigate to="/performance-manager" replace />} />
                <Route path="/rnd" element={<RequireAuth><RnDDashboard /></RequireAuth>} />
                <Route path="/rnd-dashboard" element={<Navigate to="/rnd" replace />} />
                <Route path="/hr" element={<RequireAuth><HRDashboard /></RequireAuth>} />
                <Route path="/hr-dashboard" element={<Navigate to="/hr" replace />} />
                <Route path="/seo" element={<RequireAuth><SEODashboard /></RequireAuth>} />
                <Route path="/seo-dashboard" element={<Navigate to="/seo" replace />} />
                <Route path="/support" element={<RequireAuth><SupportDashboard /></RequireAuth>} />
                <Route path="/support-dashboard" element={<Navigate to="/support" replace />} />
                <Route path="/sales" element={<Navigate to="/sales-support" replace />} />
                <Route path="/sales-support" element={<RequireAuth><SalesSupportDashboard /></RequireAuth>} />
                <Route path="/client-success" element={<RequireAuth><ClientSuccessDashboard /></RequireAuth>} />
                <Route path="/clients" element={<Navigate to="/client-success" replace />} />
                <Route path="/incident-crisis" element={<RequireAuth><IncidentCrisisDashboard /></RequireAuth>} />

                {/* Role-specific */}
                <Route path="/developer" element={<RequireAuth><DeveloperDashboard /></RequireAuth>} />
                <Route path="/developer-dashboard" element={<Navigate to="/developer" replace />} />
                <Route path="/developer/secure-dashboard" element={<RequireAuth><SecureDeveloperDashboard /></RequireAuth>} />
                <Route path="/dev-command-center" element={<Navigate to="/boss" replace />} />
                <Route path="/franchise" element={<RequireAuth><FranchiseDashboard /></RequireAuth>} />
                <Route path="/franchise-dashboard" element={<Navigate to="/franchise" replace />} />
                <Route path="/franchise/dashboard" element={<RequireAuth><FranchiseOwnerDashboard /></RequireAuth>} />
                <Route path="/franchise-management" element={<RequireAuth><FranchiseManagement /></RequireAuth>} />
                <Route path="/reseller" element={<RequireAuth><ResellerDashboard /></RequireAuth>} />
                <Route path="/reseller-dashboard" element={<Navigate to="/reseller" replace />} />
                <Route path="/reseller-portal" element={<RequireAuth><ResellerPortal /></RequireAuth>} />
                <Route path="/influencer" element={<RequireAuth><InfluencerDashboard /></RequireAuth>} />
                <Route path="/influencer-dashboard" element={<Navigate to="/influencer" replace />} />
                <Route path="/influencer-manager" element={<RequireAuth><InfluencerManager /></RequireAuth>} />
                <Route path="/influencer-command" element={<Navigate to="/boss" replace />} />


                {/* AI / Support / Integration */}
                <Route path="/over-ai" element={<RequireAuth><OverAI /></RequireAuth>} />
                <Route path="/ai-console" element={<RequireAuth><AIOptimizationConsole /></RequireAuth>} />
                <Route path="/internal-support-ai" element={<RequireAuth><InternalSupportAI /></RequireAuth>} />
                <Route path="/api-integration" element={<RequireAuth><APIIntegrationDashboard /></RequireAuth>} />
                <Route path="/api-integrations" element={<Navigate to="/api-integration" replace />} />
                <Route path="/api-manager" element={<RequireAuth><APIManagerDashboard /></RequireAuth>} />
                <Route path="/api-manager/*" element={<RequireAuth><APIManagerDashboard /></RequireAuth>} />
                <Route path="/api-ai-manager" element={<RequireAuth><SecureAPIAIManagerDashboard /></RequireAuth>} />
                <Route path="/api-ai-manager-secure" element={<RequireAuth><SecureAPIAIManagerDashboard /></RequireAuth>} />
                <Route path="/server-manager" element={<RequireAuth><ServerManagerDashboard /></RequireAuth>} />
                <Route path="/server-manager/*" element={<RequireAuth><ServerManagerDashboard /></RequireAuth>} />
                <Route path="/security-command" element={<RequireAuth><SecurityCommandCenter /></RequireAuth>} />
                <Route path="/security-dashboard" element={<Navigate to="/security-command" replace />} />
                <Route path="/safe-assist" element={<RequireAuth><SafeAssistDashboard /></RequireAuth>} />
                <Route path="/assist-manager" element={<RequireAuth><AssistManagerDashboard /></RequireAuth>} />
                <Route path="/promise-tracker" element={<RequireAuth><PromiseTrackerDashboard /></RequireAuth>} />
                <Route path="/promise-management" element={<RequireAuth><PromiseManagementDashboard /></RequireAuth>} />
                <Route path="/sales-crm" element={<SalesCRMDashboard />} />
                <Route path="/sales-crm/auth" element={<SalesCRMAuthPage />} />

                {/* Achievement Management System */}
                <Route path="/ams" element={<RequireRole allowed={["boss_owner", "super_admin", "admin", "ceo", "franchise", "reseller", "developer"]}><AMSLayout /></RequireRole>}>
                  <Route index element={<AMSOverview />} />
                  <Route path="achievements" element={<Achievements />} />
                  <Route path="badges" element={<Badges />} />
                  <Route path="trophies" element={<Trophies />} />
                  <Route path="rewards" element={<Rewards />} />
                  <Route path="levels" element={<Levels />} />
                  <Route path="milestones" element={<Milestones />} />
                  <Route path="leaderboards" element={<Leaderboards />} />
                  <Route path="xp" element={<XPEngine />} />
                  <Route path="streaks" element={<Streaks />} />
                  <Route path="my-progress" element={<MyProgress />} />
                  <Route path="my-achievements" element={<MyAchievements />} />
                  <Route path="my-badges" element={<MyBadges />} />
                  <Route path="my-trophies" element={<MyTrophies />} />
                  <Route path="my-rewards" element={<MyRewards />} />
                  <Route path="claims" element={<Claims />} />
                  <Route path="notifications" element={<Notifications />} />
                  <Route path="analytics" element={<Analytics />} />
                  <Route path="audit" element={<AuditLogs />} />
                  <Route path="admin/approvals" element={<ClaimApprovals />} />
                  <Route path="admin/roles" element={<RolePermissions />} />
                  <Route path="seasons" element={<Seasons />} />
                  <Route path="categories" element={<Categories />} />
                  <Route path="integrations" element={<Integrations />} />
                  <Route path="settings" element={<AMSSettings />} />
                </Route>

                {/* Redirects */}
                <Route path="/index" element={<Navigate to="/" replace />} />

                {/* 404 */}
                <Route path="*" element={<NotFound />} />
              </Routes>
            </GlobalRealtimeProvider>
          </AuthProvider>
        </BrowserRouter>
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;