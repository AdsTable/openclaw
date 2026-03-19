// Browser stub for node:os — prevents crashes from os.tmpdir/homedir calls.

export function tmpdir(): string {
  return "/tmp";
}

export function homedir(): string {
  return "/home/user";
}

export function platform(): string {
  return "linux";
}

export function hostname(): string {
  return "browser";
}

export function type(): string {
  return "Browser";
}

export function release(): string {
  return "0.0.0";
}

export function arch(): string {
  return "x64";
}

export function cpus(): unknown[] {
  return [];
}

export function totalmem(): number {
  return 0;
}

export function freemem(): number {
  return 0;
}

export function networkInterfaces(): Record<string, unknown> {
  return {};
}

export const EOL = "\n";

export default {
  tmpdir,
  homedir,
  platform,
  hostname,
  type,
  release,
  arch,
  cpus,
  totalmem,
  freemem,
  networkInterfaces,
  EOL,
};
