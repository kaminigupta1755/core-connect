import { useEffect, useState } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

export type AppRole = Database["public"]["Enums"] extends { app_role: infer R } ? R : string;

// Priority order — higher = picked first for role-based redirect
const ROLE_PRIORITY: string[] = [
  "boss", "ceo", "admin", "developer",
  "finance_manager", "support_manager", "sales_manager", "marketing_manager", "product_manager",
  "reseller_manager", "vendor_manager", "franchise_manager",
  "author", "vendor", "reseller", "franchise", "affiliate", "customer",
];

export function pickPrimaryRole(roles: string[]): string {
  for (const r of ROLE_PRIORITY) if (roles.includes(r)) return r;
  return "customer";
}

export function roleHomePath(role: string): string {
  const map: Record<string, string> = {
    boss: "/boss",
    ceo: "/boss",
    admin: "/admin",
    developer: "/admin",
    finance_manager: "/admin",
    support_manager: "/admin",
    sales_manager: "/admin",
    marketing_manager: "/admin",
    product_manager: "/admin",
    reseller_manager: "/admin",
    vendor_manager: "/admin",
    franchise_manager: "/admin",
    reseller: "/reseller",
    vendor: "/vendor",
    author: "/author",
    franchise: "/franchise",
    affiliate: "/customer",
    customer: "/customer",
  };
  return map[role] ?? "/customer";
}

export function useAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s);
      setUser(s?.user ?? null);
    });
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setUser(data.session?.user ?? null);
      setLoading(false);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  return { session, user, loading, signOut: () => supabase.auth.signOut() };
}
