import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // GitHub Pages serves this at https://<user>.github.io/demo-cicd/
  base: '/demo-cicd/',
})
