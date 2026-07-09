#!/usr/bin/env node
/**
 * Route / navigation consistency audit.
 *
 * Scans every `.tsx`/`.ts` file in src/ and reports:
 *   1. All routes registered in <Route path="..." />
 *   2. Every navigation target used via <Link to="..." />, <NavLink to="..." />,
 *      navigate("..."), <Navigate to="..." />, href="/..."
 *   3. Targets that DO NOT match any registered route (broken links)
 *   4. Registered routes that no code links to (orphan routes)
 *
 * Run:   node scripts/route-audit.mjs
 * Exits non-zero if broken links are found (useful for CI).
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(ROOT, "src");

/** @type {Set<string>} */ const routes = new Set();
/** @type {Map<string, Set<string>>} */ const links = new Map(); // target -> files

const ROUTE_RE = /<Route\s+[^>]*?path\s*=\s*["'`]([^"'`]+)["'`]/g;
const LINK_TO_RE = /<(?:Link|NavLink|Navigate)\s+[^>]*?to\s*=\s*["'`]([^"'`{}]+)["'`]/g;
const NAVIGATE_RE = /\bnavigate\(\s*["'`]([^"'`]+)["'`]/g;
const HREF_RE = /\bhref\s*=\s*["'`](\/[^"'`{}\s]*)["'`]/g;

function normalize(p) {
  if (!p) return p;
  // Drop query/hash
  const clean = p.split("?")[0].split("#")[0];
  // Strip trailing slash except root
  return clean.length > 1 && clean.endsWith("/") ? clean.slice(0, -1) : clean;
}

function matchesRoute(target, routePatterns) {
  const t = normalize(target);
  if (routePatterns.has(t)) return true;
  // Wildcard / param matching: turn "/foo/:id" and "/foo/*" into regex
  for (const pattern of routePatterns) {
    const re = new RegExp(
      "^" +
        pattern
          .replace(/\/$/, "")
          .replace(/:[^/]+/g, "[^/]+")
          .replace(/\*/g, ".*") +
        "$"
    );
    if (re.test(t)) return true;
  }
  return false;
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name.startsWith(".")) continue;
      await walk(full);
    } else if (/\.(t|j)sx?$/.test(e.name)) {
      const src = await fs.readFile(full, "utf8");
      const rel = path.relative(ROOT, full);

      for (const m of src.matchAll(ROUTE_RE)) {
        routes.add(normalize(m[1]));
      }
      const collect = (re) => {
        for (const m of src.matchAll(re)) {
          const target = normalize(m[1]);
          if (!target || !target.startsWith("/")) continue;
          if (target.startsWith("//")) continue; // protocol-relative URL
          if (!links.has(target)) links.set(target, new Set());
          links.get(target).add(rel);
        }
      };
      collect(LINK_TO_RE);
      collect(NAVIGATE_RE);
      collect(HREF_RE);
    }
  }
}

await walk(SRC);

const broken = [];
for (const [target, files] of links) {
  if (target === "*" || target === "/") continue;
  if (!matchesRoute(target, routes)) {
    broken.push({ target, files: [...files] });
  }
}

const linkedTargets = new Set(links.keys());
const orphans = [];
for (const r of routes) {
  if (r === "*" || r === "/" || r.includes(":") || r.includes("*")) continue;
  if (!linkedTargets.has(r)) orphans.push(r);
}

const yellow = (s) => `\x1b[33m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;

console.log(bold("\n=== Route / Navigation Consistency Audit ===\n"));
console.log(`Scanned ${routes.size} registered routes and ${links.size} navigation targets in src/\n`);

if (broken.length === 0) {
  console.log(green("✓ No broken navigation targets found."));
} else {
  console.log(red(`✗ ${broken.length} broken navigation target(s):\n`));
  for (const b of broken.sort((a, b) => a.target.localeCompare(b.target))) {
    console.log(`  ${red(b.target)}`);
    for (const f of b.files) console.log(`      ↳ ${f}`);
  }
}

console.log("");
if (orphans.length === 0) {
  console.log(green("✓ Every registered route is linked from somewhere."));
} else {
  console.log(yellow(`⚠ ${orphans.length} orphan route(s) (registered but nothing links to them):\n`));
  for (const r of orphans.sort()) console.log(`  ${yellow(r)}`);
}

console.log("");
process.exit(broken.length > 0 ? 1 : 0);
