import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  // One retry everywhere (not CI-only): the residual `vite preview`
  // connection-scheduling flake documented below and in
  // docs/FUNDA360_KNOWN_LIMITATIONS.md is a local-server quirk, so it is
  // exactly the local full-suite run that needs the same absorption CI
  // already had.
  retries: 1,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'retain-on-failure',
    // Optional local/sandbox override for a pre-installed Chromium binary
    // whose path doesn't match this pinned @playwright/test version's
    // expected download location — unset (default) everywhere else,
    // including CI, which installs its own matching browser.
    launchOptions: process.env.PW_EXECUTABLE_PATH
      ? {
          executablePath: process.env.PW_EXECUTABLE_PATH,
          args: [
            '--disable-background-networking',
            '--disable-component-update',
            '--disable-domain-reliability',
            '--disable-client-side-phishing-detection',
            '--disable-features=OptimizationHints,MediaRouter,AutofillServerCommunication',
          ],
        }
      : undefined,
  },
  // A residual, separately-diagnosed flake remains even against a
  // prebuilt server: My Profile's request-heavy waterfall (employee +
  // linked learners + teaching assignments + their supporting class/
  // subject data — several concurrent REST calls per test) can
  // occasionally lose a race against `vite preview`'s single Node
  // process when several parallel workers hit it at once — confirmed by
  // running the same spec serially (0 flakes) vs. fully parallel (an
  // occasional one). This is the same known, already-documented
  // local-server connection-handling quirk in
  // docs/FUNDA360_KNOWN_LIMITATIONS.md, not expected against the pilot's
  // real hosted deployment — a small assertion-timeout increase (8s, not
  // a blanket one) plus a single retry is the proportionate response to a
  // diagnosed, bounded, occasional connection-scheduling delay, not a
  // mask for an unexplained failure.
  expect: {
    timeout: 8_000,
  },
  webServer: {
    // Always serve a prebuilt bundle, never the dev server. The dev
    // server compiles each lazy route's module graph on first request,
    // and under fullyParallel workers those cold navigations lose a race
    // that produces flaky failures with no product defect behind them
    // (see the comment above and docs/FUNDA360_KNOWN_LIMITATIONS.md). A
    // prebuilt bundle has no on-demand compilation, so the full-suite
    // `npm run test:e2e` gate is deterministic locally and in CI alike.
    // Iterating on a single spec is still fast: run `npm run dev`
    // yourself and Playwright reuses it (reuseExistingServer, non-CI).
    command: 'npm run build && npm run preview -- --port 5173 --strictPort',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
