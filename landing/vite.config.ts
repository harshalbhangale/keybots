import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

export default defineConfig({
  plugins: [react()],
  server: { port: 5180 },
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        logos: resolve(__dirname, "logos.html"),
      },
    },
  },
});
