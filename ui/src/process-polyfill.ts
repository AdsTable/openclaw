// Browser runtime shim for server-oriented modules that reference `process`
// at module top-level (e.g. src/logging/node-require.ts).

const g = globalThis as Record<string, unknown>;

if (typeof g["process"] === "undefined") {
  g["process"] = {
    env: {},
    cwd: () => "/",
    platform: "browser",
    version: "v0.0.0",
    versions: { node: "0.0.0" },
    getBuiltinModule: undefined,
  };
}
