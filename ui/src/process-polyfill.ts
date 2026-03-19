// Browser runtime shim for server-oriented modules that reference `process`
// at module top-level (e.g. src/logging/node-require.ts).

type BrowserProcessShim = {
  env: Record<string, string>;
  cwd: () => string;
  platform: string;
  version: string;
  versions: { node: string };
  getBuiltinModule?: undefined;
};

const g = globalThis as typeof globalThis & { process?: BrowserProcessShim };

if (typeof g.process === "undefined") {
  g.process = {
    env: {},
    cwd: () => "/",
    platform: "browser",
    version: "v0.0.0",
    versions: { node: "0.0.0" },
    getBuiltinModule: undefined,
  };
}
