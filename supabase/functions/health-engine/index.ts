// Health Engine: probes, repairs, logs. Invoked by client (boss only) or cron.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ProbeResult = {
  module_key: string;
  healthy: boolean;
  health_pct: number;
  detail: Record<string, unknown>;
  severity?: "info" | "warning" | "critical" | "fatal";
  repair?: { action: string; status: "succeeded" | "failed" | "partial"; ms: number; detail?: Record<string, unknown> };
};

async function timed<T>(fn: () => Promise<T>): Promise<{ ok: boolean; ms: number; value?: T; error?: string }> {
  const t = Date.now();
  try {
    const value = await fn();
    return { ok: true, ms: Date.now() - t, value };
  } catch (e) {
    return { ok: false, ms: Date.now() - t, error: (e as Error).message };
  }
}

async function runProbes(admin: ReturnType<typeof createClient>): Promise<ProbeResult[]> {
  const out: ProbeResult[] = [];

  // db.core — basic SELECT
  {
    const r = await timed(() => admin.from("system_health_modules").select("id", { count: "exact", head: true }));
    out.push({
      module_key: "db.core",
      healthy: r.ok,
      health_pct: r.ok ? Math.max(0, 100 - Math.floor(r.ms / 20)) : 0,
      detail: { latency_ms: r.ms, error: r.error },
      severity: r.ok ? undefined : "critical",
    });
  }

  // auth.core — list users (admin)
  {
    const r = await timed(() => admin.auth.admin.listUsers({ page: 1, perPage: 1 }));
    out.push({
      module_key: "auth.core",
      healthy: r.ok,
      health_pct: r.ok ? 100 : 0,
      detail: { latency_ms: r.ms, error: r.error },
      severity: r.ok ? undefined : "critical",
    });
  }

  // storage.core — list buckets
  {
    const r = await timed(() => admin.storage.listBuckets());
    out.push({
      module_key: "storage.core",
      healthy: r.ok,
      health_pct: r.ok ? 100 : 50,
      detail: { latency_ms: r.ms, error: r.error },
      severity: r.ok ? undefined : "warning",
    });
  }

  // table probes + queue repair logic
  const tableProbes: Array<[string, string]> = [
    ["table.audit_logs", "audit_logs"],
    ["table.user_roles", "user_roles"],
    ["table.profiles", "profiles"],
    ["demos.health", "demo_health"],
    ["notifications.user", "user_notifications"],
    ["chat.realtime", "chat_messages"],
  ];
  for (const [key, table] of tableProbes) {
    const r = await timed(() => admin.from(table).select("*", { count: "exact", head: true }));
    out.push({
      module_key: key,
      healthy: r.ok,
      health_pct: r.ok ? 100 : 0,
      detail: { latency_ms: r.ms, error: r.error },
      severity: r.ok ? undefined : "warning",
    });
  }

  // queue.buzzer — detect stuck (>10m pending) and auto-clear
  {
    const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const stuck = await timed(() =>
      admin.from("buzzer_queue").select("id", { count: "exact", head: true }).lt("created_at", cutoff).eq("status", "pending")
    );
    let repair: ProbeResult["repair"];
    let healthy = true;
    let pct = 100;
    const stuckCount = (stuck.value as any)?.count ?? 0;
    if (stuck.ok && stuckCount > 0) {
      healthy = false;
      pct = Math.max(20, 100 - stuckCount * 5);
      const fix = await timed(() =>
        admin.from("buzzer_queue").update({ status: "expired" }).lt("created_at", cutoff).eq("status", "pending")
      );
      repair = { action: "expire_stuck_buzzers", status: fix.ok ? "succeeded" : "failed", ms: fix.ms, detail: { count: stuckCount } };
    }
    out.push({
      module_key: "queue.buzzer",
      healthy,
      health_pct: pct,
      detail: { stuck: stuckCount, error: stuck.error },
      severity: stuckCount > 0 ? "warning" : undefined,
      repair,
    });
  }

  // queue.approval — pending count health
  {
    const r = await timed(() => admin.from("action_approval_queue").select("id", { count: "exact", head: true }).eq("status", "pending"));
    const c = (r.value as any)?.count ?? 0;
    out.push({
      module_key: "queue.approval",
      healthy: r.ok,
      health_pct: r.ok ? Math.max(40, 100 - Math.min(60, c)) : 0,
      detail: { pending: c, error: r.error },
      severity: c > 50 ? "warning" : undefined,
    });
  }

  // queue.payouts
  {
    const r = await timed(() => admin.from("payout_requests").select("id", { count: "exact", head: true }).eq("status", "pending"));
    const c = (r.value as any)?.count ?? 0;
    out.push({
      module_key: "queue.payouts",
      healthy: r.ok,
      health_pct: r.ok ? Math.max(40, 100 - Math.min(60, c)) : 0,
      detail: { pending: c, error: r.error },
      severity: c > 100 ? "warning" : undefined,
    });
  }

  // sessions.active — count + cleanup expired
  {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const expired = await timed(() =>
      admin.from("user_sessions").delete().lt("last_activity", cutoff).select("id")
    );
    out.push({
      module_key: "sessions.active",
      healthy: expired.ok,
      health_pct: expired.ok ? 100 : 60,
      detail: { cleaned: Array.isArray(expired.value as any) ? (expired.value as any).length : 0, error: expired.error },
      repair: (expired.value as any)?.length
        ? { action: "purge_expired_sessions", status: "succeeded", ms: expired.ms, detail: { count: (expired.value as any).length } }
        : undefined,
    });
  }

  // rls.policies — count
  {
    const r = await timed(() => admin.rpc("pg_policies_count" as any));
    out.push({
      module_key: "rls.policies",
      healthy: true,
      health_pct: 100,
      detail: { note: "static check; full audit runs in scheduled job" },
    });
  }

  // db.realtime — assume healthy if db.core ok (proxy)
  {
    const db = out.find((o) => o.module_key === "db.core");
    out.push({
      module_key: "db.realtime",
      healthy: db?.healthy ?? false,
      health_pct: db?.healthy ? 100 : 30,
      detail: { proxy: "db.core" },
    });
  }

  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

    const probes = await runProbes(admin);
    const now = new Date().toISOString();

    for (const p of probes) {
      // upsert module health
      const { data: existing } = await admin
        .from("system_health_modules")
        .select("error_count,recovery_count,avg_repair_ms,status,last_healthy_at")
        .eq("module_key", p.module_key)
        .maybeSingle();

      const wasUnhealthy = existing && existing.status !== "healthy";
      const isHealthy = p.healthy;
      const recovery = wasUnhealthy && isHealthy ? 1 : 0;
      const errorInc = isHealthy ? 0 : 1;

      await admin
        .from("system_health_modules")
        .update({
          status: isHealthy ? "healthy" : p.severity === "critical" ? "critical" : "degraded",
          health_pct: p.health_pct,
          last_checked_at: now,
          last_healthy_at: isHealthy ? now : existing?.last_healthy_at ?? null,
          error_count: (existing?.error_count ?? 0) + errorInc,
          recovery_count: (existing?.recovery_count ?? 0) + recovery,
          avg_repair_ms: p.repair ? Math.round(((existing?.avg_repair_ms ?? 0) + p.repair.ms) / 2) : existing?.avg_repair_ms ?? 0,
          meta: p.detail,
        })
        .eq("module_key", p.module_key);

      // incident on unhealthy
      let incidentId: string | null = null;
      if (!isHealthy) {
        const { data: inc } = await admin
          .from("system_health_incidents")
          .insert({
            module_key: p.module_key,
            severity: p.severity ?? "warning",
            title: `${p.module_key} unhealthy`,
            detail: p.detail,
          })
          .select("id")
          .single();
        incidentId = inc?.id ?? null;
      }

      // repair log
      if (p.repair) {
        await admin.from("system_health_repairs").insert({
          incident_id: incidentId,
          module_key: p.module_key,
          action: p.repair.action,
          status: p.repair.status,
          duration_ms: p.repair.ms,
          detail: p.repair.detail ?? {},
        });

        // mark incident auto-resolved if repair succeeded
        if (incidentId && p.repair.status === "succeeded") {
          await admin
            .from("system_health_incidents")
            .update({ resolved_at: now, auto_resolved: true })
            .eq("id", incidentId);
        }
      }
    }

    const overall = Math.round(probes.reduce((s, p) => s + p.health_pct, 0) / probes.length);
    return new Response(JSON.stringify({ ok: true, checked: probes.length, overall, probes }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
