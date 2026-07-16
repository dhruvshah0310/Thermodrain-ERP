import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:4000',
        changeOrigin: true,
      },
    },
  },
  build: mode === 'preview'
    // The preview build (npm run build:preview) has no server to fetch
    // separate chunks from — it's inlined into one self-contained HTML file
    // — so force everything (including the dynamically-imported staticApi
    // chunk) into a single JS output instead of Vite's default code-splitting.
    ? { rollupOptions: { output: { inlineDynamicImports: true } } }
    : {},
}))
