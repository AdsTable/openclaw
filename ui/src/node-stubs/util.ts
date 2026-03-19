// Browser stub for node:util — provides promisify and other commonly used utils.

export function promisify<T extends (...args: unknown[]) => void>(fn: T): (...args: unknown[]) => Promise<unknown> {
  return (...args: unknown[]) =>
    new Promise((resolve, reject) => {
      fn(...args, (err: unknown, result: unknown) => {
        if (err) reject(err);
        else resolve(result);
      });
    });
}

export function inspect(obj: unknown): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch {
    return String(obj);
  }
}

export function format(fmt: string, ...args: unknown[]): string {
  let i = 0;
  return fmt.replace(/%[sdjifoO%]/g, (match) => {
    if (match === "%%") return "%";
    if (i >= args.length) return match;
    return String(args[i++]);
  });
}

export function deprecate<T extends (...args: unknown[]) => unknown>(fn: T, _msg: string): T {
  return fn;
}

export function inherits(ctor: Function, superCtor: Function): void {
  Object.setPrototypeOf(ctor.prototype, superCtor.prototype);
}

export function types() {
  return {};
}

export const TextEncoder = globalThis.TextEncoder;
export const TextDecoder = globalThis.TextDecoder;

export default {
  promisify,
  inspect,
  format,
  deprecate,
  inherits,
  types,
  TextEncoder,
  TextDecoder,
};
