import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// Noms de fichiers fixes (pas de hash) : le binaire Rust les inclut avec include_str! à des chemins connus
// (voir host/src/httpd.rs). Un hash changerait de nom à chaque build et casserait ces chemins.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "dist",
    assetsDir: ".",
    rollupOptions: {
      output: {
        entryFileNames: "app.js",
        chunkFileNames: "app.js",
        assetFileNames: "app.[ext]",
      },
    },
  },
})
