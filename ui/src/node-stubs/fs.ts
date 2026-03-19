// Browser stub for node:fs — prevents top-level crashes and runtime errors.
// Strategy: make all fs calls silently succeed so that server-side code that
// transitively runs in the browser (e.g. resolvePreferredOpenClawTmpDir called
// from logger.ts) completes without throwing.

export const constants = {
  W_OK: 2,
  X_OK: 1,
  R_OK: 4,
  F_OK: 0,
} as const;

// Pretend every path is an accessible, writable directory so that
// resolvePreferredOpenClawTmpDir returns "/tmp/openclaw" on first check.
export function accessSync(_path: string, _mode?: number): void {
  // no-op — directory "accessible" in browser context
}

export function chmodSync(_path: string, _mode: number): void {
  // no-op
}

export function lstatSync(_path: string): {
  isDirectory(): boolean;
  isSymbolicLink(): boolean;
  mode: number;
  uid: number | undefined;
} {
  // Return a stat that passes isTrustedTmpDir: isDirectory=true, isSymbolicLink=false,
  // mode=0o700 (no group/other writable bits), uid=undefined (skips uid check).
  return {
    isDirectory: () => true,
    isSymbolicLink: () => false,
    mode: 0o700,
    uid: undefined,
  };
}

export function mkdirSync(_path: string, _opts?: { recursive?: boolean; mode?: number }): void {
  // no-op
}

export function existsSync(_path: string): boolean {
  return false;
}

export function readFileSync(_path: string, _opts?: unknown): never {
  throw Object.assign(new Error(`ENOENT: no such file: ${_path}`), { code: "ENOENT" });
}

export function writeFileSync(_path: string, _data: unknown): void {
  // no-op
}

export function closeSync(_fd: number): void {}

export default {
  constants,
  accessSync,
  chmodSync,
  lstatSync,
  mkdirSync,
  existsSync,
  readFileSync,
  writeFileSync,
  closeSync,
};

