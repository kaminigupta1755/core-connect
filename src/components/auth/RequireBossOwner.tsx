import { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { resolveHome } from "@/lib/roleRoutes";

/**
 * Strict boss_owner gate.
 *
 * Unlike RequireRole (which treats master/super_admin as boss_owner and lets
 * CEO through), this ONLY allows role === "boss_owner". Anything else is
 * redirected to that role's own home dashboard, never shown /access-denied.
 *
 * Use this for the Global Control Center at /boss.
 */
export default function RequireBossOwner({ children }: { children: ReactNode }) {
  const { user, userRole, loading, wasForceLoggedOut } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <div className="dark min-h-screen bg-background flex items-center justify-center">
        <Loader2 className="w-10 h-10 animate-spin text-primary" />
      </div>
    );
  }

  if (wasForceLoggedOut) return <Navigate to="/auth" replace />;
  if (!user) return <Navigate to="/auth" replace state={{ from: location }} />;
  if (!userRole) return <Navigate to="/pending-approval" replace />;

  if (userRole !== "boss_owner") {
    return <Navigate to={resolveHome(userRole)} replace />;
  }

  return <>{children}</>;
}
