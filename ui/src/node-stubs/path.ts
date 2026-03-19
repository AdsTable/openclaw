// Browser stub for node:path — prevents TypeError: path.resolve/join is not a function.
// Transitive imports from src/ use path.resolve/join at module top-level.

export const sep = "/";
export const delimiter = ":";

export function resolve(...parts: string[]): string {
  return join(...parts);
}

export function join(...parts: string[]): string {
  return parts
    .filter((p) => p != null && p !== "")
    .join("/")
    .replace(/\/+/g, "/");
}

export function dirname(p: string): string {
  if (!p) return ".";
  const idx = p.lastIndexOf("/");
  return idx < 0 ? "." : p.slice(0, idx) || "/";
}

export function basename(p: string, ext?: string): string {
  const base = p.split("/").pop() ?? p;
  return ext && base.endsWith(ext) ? base.slice(0, -ext.length) : base;
}

export function extname(p: string): string {
  const base = basename(p);
  const idx = base.lastIndexOf(".");
  return idx < 1 ? "" : base.slice(idx);
}

export function isAbsolute(p: string): boolean {
  return p.startsWith("/");
}

export function normalize(p: string): string {
  return p.replace(/\/+/g, "/");
}

export function relative(from: string, to: string): string {
  return to;
}

export default {
  sep,
  delimiter,
  resolve,
  join,
  dirname,
  basename,
  extname,
  isAbsolute,
  normalize,
  relative,
};
