// Browser stub for node:fs — prevents top-level crashes from fs.constants.W_OK etc.
export const constants = {
  W_OK: 2,
  X_OK: 1,
  R_OK: 4,
  F_OK: 0,
} as const;

export function accessSync() {
  throw new Error("node:fs is not available in the browser");
}
export function chmodSync() {
  throw new Error("node:fs is not available in the browser");
}
export function lstatSync(): never {
  throw new Error("node:fs is not available in the browser");
}
export function mkdirSync() {
  throw new Error("node:fs is not available in the browser");
}
export function existsSync() {
  return false;
}
export function readFileSync(): never {
  throw new Error("node:fs is not available in the browser");
}
export function writeFileSync() {
  throw new Error("node:fs is not available in the browser");
}
export function closeSync() {}

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
