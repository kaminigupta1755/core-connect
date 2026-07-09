// Central mapping: role → default landing route.
// Used by RequireRole/RequireBossOwner to send a user to *their* dashboard
// instead of a generic access-denied page when they hit a route not meant
// for their role. Also usable from post-login redirect logic.

export type AppRoleLike = string | null | undefined;

// Order matters only for fallback lookups — first match wins in resolveHome.
export const ROLE_HOME: Record<string, string> = {
  boss_owner: "/boss",
  master: "/boss",           // legacy alias, merged into boss_owner
  super_admin: "/super-admin-home", // super_admin gets its own scope, NOT /boss
  ceo: "/ceo-dashboard",
  admin: "/admin-dashboard",
  developer: "/developer",
  franchise: "/franchise",
  reseller: "/reseller",
  influencer: "/influencer",
  prime: "/prime",
  client: "/client-portal",
  user: "/dashboard",
};

export const DEFAULT_HOME = "/dashboard";

export function resolveHome(role: AppRoleLike): string {
  if (!role) return DEFAULT_HOME;
  return ROLE_HOME[role] ?? DEFAULT_HOME;
}

// Routes that are strictly boss_owner (no elevation, no CEO bypass).
export const BOSS_OWNER_STRICT_ROUTES = new Set<string>(["/boss"]);
