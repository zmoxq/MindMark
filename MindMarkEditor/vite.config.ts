import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "dist",
    // Single file output for easy embedding in WKWebView
    rollupOptions: {
      output: {
        // Inline all JS/CSS into a single HTML file
        manualChunks: undefined,
      },
    },
    // Ensure assets are inlined
    assetsInlineLimit: 100000000,
  },
});
