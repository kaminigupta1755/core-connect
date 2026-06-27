#!/usr/bin/env node
/**
 * Visual regression check for Software Vala marketplace.
 *
 * Captures `/` and `/auth` at 4K (3840x2160 @ DPR 1) and compares against
 * baseline PNGs stored under tests/visual/baseline/. On first run (or with
 * UPDATE_BASELINE=1) it writes the baselines instead of asserting.
 *
 * Also asserts:
 *   - brand palette presence: the rendered frame contains pixels close to
 *     the Vala Nexus primary (blue), magenta, and gold tokens
 *   - hero text contrast: WCAG AA contrast ratio (>= 4.5) between the
 *     largest hero headline and its background
 *
 * Run: node tests/visual/visual-regression.mjs
 *      UPDATE_BASELINE=1 node tests/visual/visual-regression.mjs
 */
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE_URL = process.env.BASE_URL || 'http://localhost:8080';
const BASELINE_DIR = path.join(__dirname, 'baseline');
const ACTUAL_DIR = path.join(__dirname, 'actual');
const DIFF_DIR = path.join(__dirname, 'diff');
const UPDATE = process.env.UPDATE_BASELINE === '1';
// Allow up to 2% pixel drift to absorb cursor blink / live-clock animation.
const MAX_DIFF_RATIO = Number(process.env.MAX_DIFF_RATIO || 0.02);

// Vala Nexus brand tokens (sRGB) — must be present somewhere in each frame.
const BRAND_TOKENS = {
  primary: [37, 99, 235],   // hsl(221 83% 53%)
  magenta: [217, 70, 239],  // hsl(305 85% 60%)
  gold:    [240, 192, 64],  // hsl(45 95% 58%)
};
const PALETTE_TOLERANCE = 40; // per-channel distance

const ROUTES = [
  { name: 'home',  path: '/' },
  // The project's login screen is mounted at /auth; alias /login for parity.
  { name: 'login', path: '/auth' },
];

for (const dir of [BASELINE_DIR, ACTUAL_DIR, DIFF_DIR]) {
  fs.mkdirSync(dir, { recursive: true });
}

function loadPng(file) {
  return PNG.sync.read(fs.readFileSync(file));
}

function paletteHasColor(png, target, tolerance = PALETTE_TOLERANCE) {
  const { data } = png;
  for (let i = 0; i < data.length; i += 4) {
    const dr = Math.abs(data[i]     - target[0]);
    const dg = Math.abs(data[i + 1] - target[1]);
    const db = Math.abs(data[i + 2] - target[2]);
    if (dr <= tolerance && dg <= tolerance && db <= tolerance) return true;
  }
  return false;
}

function relativeLuminance([r, g, b]) {
  const ch = (c) => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

function contrastRatio(fg, bg) {
  const L1 = relativeLuminance(fg);
  const L2 = relativeLuminance(bg);
  const [hi, lo] = L1 > L2 ? [L1, L2] : [L2, L1];
  return (hi + 0.05) / (lo + 0.05);
}

const results = [];

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH || '/bin/chromium' });
const context = await browser.newContext({
  viewport: { width: 3840, height: 2160 },
  deviceScaleFactor: 1,
  reducedMotion: 'reduce',
  colorScheme: 'dark',
});
const page = await context.newPage();

for (const route of ROUTES) {
  const url = `${BASE_URL}${route.path}`;
  console.log(`→ ${url}`);
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 }).catch(async (e) => {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  });
  // Freeze CSS animations so the snapshot is deterministic.
  await page.addStyleTag({
    content: `*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;transition-duration:0s!important;transition-delay:0s!important;caret-color:transparent!important}`,
  });
  await page.waitForTimeout(800);

  const actualPath = path.join(ACTUAL_DIR, `${route.name}.png`);
  await page.screenshot({ path: actualPath, fullPage: false });
  const actual = loadPng(actualPath);

  // 1. Brand palette presence
  const paletteReport = {};
  for (const [name, rgb] of Object.entries(BRAND_TOKENS)) {
    paletteReport[name] = paletteHasColor(actual, rgb);
  }

  // 2. Hero text contrast — sample a text region near the top hero.
  const heroFg = await page.evaluate(() => {
    const el =
      document.querySelector('h1') ||
      document.querySelector('[class*="hero"] *') ||
      document.body;
    const cs = getComputedStyle(el);
    const parse = (s) => (s.match(/\d+(?:\.\d+)?/g) || []).slice(0, 3).map(Number);
    return { color: parse(cs.color), bg: parse(getComputedStyle(document.body).backgroundColor) };
  });
  const contrast = contrastRatio(heroFg.color, heroFg.bg);

  // 3. Pixel diff vs baseline
  const baselinePath = path.join(BASELINE_DIR, `${route.name}.png`);
  let diffRatio = 0;
  let diffStatus = 'baseline-written';
  if (UPDATE || !fs.existsSync(baselinePath)) {
    fs.copyFileSync(actualPath, baselinePath);
  } else {
    const baseline = loadPng(baselinePath);
    if (baseline.width === actual.width && baseline.height === actual.height) {
      const diff = new PNG({ width: actual.width, height: actual.height });
      const pixels = pixelmatch(
        baseline.data, actual.data, diff.data,
        actual.width, actual.height,
        { threshold: 0.1, includeAA: true },
      );
      diffRatio = pixels / (actual.width * actual.height);
      fs.writeFileSync(path.join(DIFF_DIR, `${route.name}.png`), PNG.sync.write(diff));
      diffStatus = diffRatio <= MAX_DIFF_RATIO ? 'pass' : 'fail';
    } else {
      diffStatus = 'size-mismatch';
    }
  }

  const paletteOk  = Object.values(paletteReport).every(Boolean);
  const contrastOk = contrast >= 4.5;
  const pixelOk    = diffStatus === 'pass' || diffStatus === 'baseline-written';

  results.push({
    route: route.path,
    paletteReport,
    paletteOk,
    contrast: Number(contrast.toFixed(2)),
    contrastOk,
    diffRatio: Number((diffRatio * 100).toFixed(3)) + '%',
    diffStatus,
    pixelOk,
    ok: paletteOk && contrastOk && pixelOk,
  });
}

await browser.close();

console.log('\nVisual regression report');
console.table(results.map(r => ({
  route: r.route,
  palette: r.paletteOk ? '✓' : '✗ ' + JSON.stringify(r.paletteReport),
  contrast: (r.contrastOk ? '✓ ' : '✗ ') + r.contrast,
  pixelDiff: (r.pixelOk ? '✓ ' : '✗ ') + r.diffRatio + ' (' + r.diffStatus + ')',
  ok: r.ok ? '✓' : '✗',
})));

const failed = results.filter(r => !r.ok);
if (failed.length) {
  console.error(`\n${failed.length} route(s) failed visual regression.`);
  process.exit(1);
}
console.log('\nAll routes passed visual regression.');
