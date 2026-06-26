// One-shot bootstrap: downloads the consolidated migrations SQL from the
// private _bootstrap bucket and applies it to the database in a single
// simple-query call. Safe to invoke repeatedly because every migration in
// the bundle uses CREATE OR REPLACE / IF NOT EXISTS where possible; on a
// fully replayed DB subsequent calls will surface "already exists" errors
// which is the signal that replay is complete.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import postgres from "npm:postgres@3.4.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const DB_URL = Deno.env.get("SUPABASE_DB_URL")!;

  try {
    const supa = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data, error } = await supa.storage.from("_bootstrap").download("all_migrations.sql");
    if (error || !data) {
      return new Response(JSON.stringify({ stage: "download", error: error?.message ?? "no data" }), {
        status: 500, headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }
    const sqlText = await data.text();

    // Split on the file-marker we wrote during concat. Each chunk is one
    // original migration file and must run in its own autocommit batch so
    // that ALTER TYPE ... ADD VALUE statements commit before being used.
    const blocks = sqlText
      .split(/^-- ===== .*? ===== *$/m)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);

    const sql = postgres(DB_URL, { prepare: false, max: 1, ssl: "require", connect_timeout: 30, idle_timeout: 60, max_lifetime: 60 * 30 });
    const startedAt = Date.now();
    const results: { idx: number; ok: boolean; error?: string }[] = [];
    try {
      for (let i = 0; i < blocks.length; i++) {
        try {
          await sql.unsafe(blocks[i]);
          results.push({ idx: i, ok: true });
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          results.push({ idx: i, ok: false, error: msg });
          // Continue applying remaining blocks; report at end.
        }
      }
    } finally {
      await sql.end({ timeout: 5 });
    }
    const failed = results.filter((r) => !r.ok);
    return new Response(
      JSON.stringify({
        ok: failed.length === 0,
        blocks: blocks.length,
        applied: results.length - failed.length,
        failed: failed.length,
        ms: Date.now() - startedAt,
        bytes: sqlText.length,
        failures: failed.slice(0, 20),
      }),
      { status: failed.length === 0 ? 200 : 207, headers: { ...corsHeaders, "content-type": "application/json" } },
    );

    return new Response(
      JSON.stringify({ ok: true, bytes: sqlText.length, ms: Date.now() - startedAt }),
      { status: 200, headers: { ...corsHeaders, "content-type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? `${e.message}\n${e.stack ?? ""}` : String(e);
    return new Response(JSON.stringify({ stage: "exec", error: msg }), {
      status: 500, headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }
});
