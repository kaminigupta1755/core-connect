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

    const sql = postgres(DB_URL, { prepare: false, max: 1, ssl: "require", connect_timeout: 30, idle_timeout: 5 });
    const startedAt = Date.now();
    try {
      await sql.unsafe(sqlText);
    } finally {
      await sql.end({ timeout: 5 });
    }

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
