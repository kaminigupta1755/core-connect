# Visual regression tests

Captures `/` (marketplace home) and `/auth` (login) at 4K (3840×2160) and
asserts three things:

1. **Brand palette presence** — the Vala Nexus primary (blue), magenta, and
   gold tokens are visibly rendered in the frame.
2. **Hero contrast** — WCAG AA contrast ratio (≥ 4.5) between the headline
   text and the page background.
3. **Pixel diff vs baseline** — ≤ 2% of pixels differ from the committed
   baseline (`baseline/*.png`).

## Commands

```bash
# First run / after intentional UI change — write new baselines
UPDATE_BASELINE=1 node tests/visual/visual-regression.mjs

# CI / regression check
node tests/visual/visual-regression.mjs
```

The dev server must be reachable at `BASE_URL` (default `http://localhost:8080`).
Set `MAX_DIFF_RATIO` to tune the pixel-diff tolerance (default `0.02` = 2%).

Artifacts:
- `baseline/` — committed reference PNGs (source of truth)
- `actual/`   — last captured PNGs
- `diff/`     — pixelmatch diff overlay; red pixels = drift
