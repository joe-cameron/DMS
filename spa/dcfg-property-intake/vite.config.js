/**
 * vite.config.js — Decades Onboarding Concierge
 *
 * Matches dcfg-shell pattern: classic JSX runtime for React 16.14 (Power Pages host).
 * No externals — bundles everything into a single chunk.
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [
    react({
      jsxRuntime: 'classic',
    }),
  ],
  base: '/',
  build: {
    outDir: 'dist',
    sourcemap: true,
    chunkSizeWarningLimit: 700,
    rollupOptions: {
      output: {
        manualChunks: undefined,
      },
    },
  },
});
