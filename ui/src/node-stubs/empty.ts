// Browser stub for Node.js built-ins that should never run in the browser.
// Exports no-op functions for every named import that Vite's bundler resolves.

// node:child_process
export function spawn() {
  throw new Error("not available in browser");
}
export function execFile() {
  throw new Error("not available in browser");
}
export function exec() {
  throw new Error("not available in browser");
}
export function spawnSync() {
  throw new Error("not available in browser");
}

// node:module
export function createRequire() {
  return () => ({});
}

// node:url
export function fileURLToPath(url: string): string {
  return url.replace(/^file:\/\//, "");
}
export function pathToFileURL(p: string): URL {
  return new URL(`file://${p}`);
}

// node:crypto
export function randomUUID(): string {
  return crypto.randomUUID();
}

// node:perf_hooks
export const performance = globalThis.performance;

// node:assert
export function ok() {}
export function strictEqual() {}
export function deepStrictEqual() {}

// node:tty
export function isatty() {
  return false;
}

// node:process
export const env = {};
export function cwd() {
  return "/";
}

// Catch-all default export
export default {
  spawn,
  execFile,
  exec,
  spawnSync,
  createRequire,
  fileURLToPath,
  pathToFileURL,
  randomUUID,
  performance,
  ok,
  strictEqual,
  deepStrictEqual,
  isatty,
  env,
  cwd,
};
