// Browser stub for node:child_process — prevents crashes from server-only imports.
export function spawn() {
  throw new Error("node:child_process is not available in the browser");
}
export function execFile() {
  throw new Error("node:child_process is not available in the browser");
}
export function exec() {
  throw new Error("node:child_process is not available in the browser");
}
export function spawnSync() {
  throw new Error("node:child_process is not available in the browser");
}
export default { spawn, execFile, exec, spawnSync };
