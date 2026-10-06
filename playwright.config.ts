import { defineConfig, devices } from '@playwright/test';

const isCI = Boolean(process.env.CI);

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: isCI,
  // One retry in CI only, so a genuine failure is never masked locally.
  retries: isCI ? 1 : 0,
  workers: isCI ? 2 : undefined,
  reporter: isCI ? [['list'], ['github']] : 'list',
  // Hard ceilings so a hung test or suite fails clearly instead of running
  // until the CI job timeout.
  timeout: 30_000,
  globalTimeout: 15 * 60_000,
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'retain-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
    // The suite is fully network-mocked (e2e/utils/sebetsaMocks.ts). Service
    // workers could bypass page.route(), so block them.
    serviceWorkers: 'block',
    launchOptions: {
      // Optional override for environments with a preinstalled Chromium.
      executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
    },
  },
  expect: {
    timeout: 8_000,
  },
  webServer: {
    command: 'npm run build && npm run preview -- --port 5173 --strictPort',
    url: 'http://localhost:5173',
    reuseExistingServer: !isCI,
    timeout: 180_000,
    env: {
      // The E2E bundle must never point at a hosted Supabase project. Every
      // request to this origin is intercepted by the mocks; anything that
      // slips through hits a closed local port and fails loudly.
      VITE_SUPABASE_URL: 'http://localhost:54321',
      VITE_SUPABASE_ANON_KEY: 'e2e-dummy-anon-key-not-a-real-secret',
      VITE_APP_NAME: 'Sebetsa',
    },
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
