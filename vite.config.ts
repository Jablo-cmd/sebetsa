import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  // Sebetsa is deployed at the root of its configured host. Keep the base configurable
  // for future sub-path deployments without hard-coding a product domain.
  base: process.env.DEPLOY_BASE || '/',
  plugins: [react(), tsconfigPaths()],
  server: {
    port: 5173,
  },
});
