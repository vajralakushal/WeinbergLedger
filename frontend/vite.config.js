import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Use the automatic JSX runtime (no need for React in scope) — also applies
  // to files transformed directly by esbuild under Vitest.
  esbuild: { jsx: 'automatic' },
  server: {
    proxy: {
      // Route API calls to the Rails backend (backend/, port 3000)
      '/api': 'http://localhost:3000',
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.js',
  },
})
