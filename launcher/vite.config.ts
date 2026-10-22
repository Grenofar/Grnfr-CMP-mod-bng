import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { readFileSync } from "node:fs"

const pkg = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8"))

// Config Tauri standard (voir https://v2.tauri.app) : port fixe pour le serveur de dev (le process Rust
// attend précisément cette URL, voir src-tauri/tauri.conf.json), build qui ignore src-tauri/ (watcher Vite),
// cible moderne (webviews système, pas besoin de polyfills vieux navigateurs).
export default defineConfig({
  plugins: [react()],
  define: { __APP_VERSION__: JSON.stringify(pkg.version) },
  clearScreen: false,
  server: {
    port: 1421,
    strictPort: true,
    watch: { ignored: ["**/src-tauri/**"] },
  },
  build: {
    target: process.env.TAURI_ENV_PLATFORM === "windows" ? "chrome105" : "safari13",
    outDir: "dist",
  },
})
