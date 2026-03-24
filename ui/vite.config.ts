import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = path.dirname(fileURLToPath(import.meta.url));

function normalizeBase(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) {
    return "/";
  }
  if (trimmed === "./") {
    return "./";
  }
  if (trimmed.endsWith("/")) {
    return trimmed;
  }
  return `${trimmed}/`;
}

export default defineConfig(() => {
  const envBase = process.env.OPENCLAW_CONTROL_UI_BASE_PATH?.trim();
  // Fork fix: use absolute "/" instead of upstream's "./" to prevent SPA routes
  // like /5 from breaking relative asset paths.  Sub-path deployments MUST set
  // OPENCLAW_CONTROL_UI_BASE_PATH explicitly.
  const base = envBase ? normalizeBase(envBase) : "/";
  return {
    base,
    publicDir: path.resolve(here, "public"),
    optimizeDeps: {
      include: ["lit/directives/repeat.js"],
    },
    build: {
      outDir: path.resolve(here, "../dist/control-ui"),
      emptyOutDir: true,
      sourcemap: true,
      // Keep CI/onboard logs clean; current control UI chunking is intentionally above 500 kB.
      chunkSizeWarningLimit: 1024,
    },
    resolve: {
      alias: {
        // Prevent server-only Node.js built-ins from crashing the browser bundle.
        // Each alias maps to a minimal browser-safe stub under src/node-stubs/.
        "node:fs/promises": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:fs": path.resolve(here, "src/node-stubs/fs.ts"),
        "node:path": path.resolve(here, "src/node-stubs/path.ts"),
        "node:os": path.resolve(here, "src/node-stubs/os.ts"),
        "node:util": path.resolve(here, "src/node-stubs/util.ts"),
        "node:child_process": path.resolve(here, "src/node-stubs/empty.ts"),
        // The remaining node: modules are auto-externalized by Vite as empty
        // objects. Alias them to empty.ts so they don't emit console warnings
        // and any named import resolves to a no-op function.
        "node:assert": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:crypto": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:module": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:perf_hooks": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:process": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:tty": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:url": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:v8": path.resolve(here, "src/node-stubs/empty.ts"),
        "node:vm": path.resolve(here, "src/node-stubs/empty.ts"),
      },
    },
    define: {
      // Vite 8 no longer polyfills Node.js globals for browser bundles.
      // src/ modules that use process.env / process.cwd() transitively cause
      // "process is not defined" at runtime — provide safe browser stubs.
      "process.env": "{}",
      "process.cwd": '() => "/"',
      "process.platform": '"browser"',
      "process.version": '"v0.0.0"',
    },
    server: {
      host: true,
      port: 5173,
      strictPort: true,
    },
    plugins: [
      {
        name: "control-ui-dev-stubs",
        configureServer(server) {
          server.middlewares.use("/__openclaw/control-ui-config.json", (_req, res) => {
            res.setHeader("Content-Type", "application/json");
            res.end(
              JSON.stringify({
                basePath: "/",
                assistantName: "",
                assistantAvatar: "",
                assistantAgentId: "",
              }),
            );
          });
        },
      },
    ],
  };
});
