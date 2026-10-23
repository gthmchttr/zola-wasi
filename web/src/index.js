/**
 * Zola, the static site generator, compiled to WebAssembly (wasm32-wasip1).
 * Builds sites entirely in memory, in browsers, workers and Node.
 *
 *   import { loadZola } from "zola-wasi";
 *   const zola = await loadZola(new URL("zola.wasm", import.meta.url));
 *   const result = await zola.build({ files: { "zola.toml": "...", "content/_index.md": "..." } });
 *   if (result.ok) result.files.get("index.html"); // Uint8Array
 *
 * Every call runs the real `zola` CLI in a fresh instance, so calls are independent.
 * Nothing touches the DOM, so it can run in a Web Worker to keep big builds off the main thread.
 */
import {
  ConsoleStdout,
  Directory,
  File,
  OpenDirectory,
  OpenFile,
  PreopenDirectory,
  WASI,
  wasi,
} from "@bjorn3/browser_wasi_shim";

// The shim keeps everything in memory and has no symlinks, but answers readlink with ENOTSUP.
// wasi-libc's realpath(), which Rust's fs::canonicalize uses, treats that as fatal; EINVAL
// ("not a symlink") is the correct answer for a path that exists.
OpenDirectory.prototype.path_readlink = function (path) {
  const { ret } = this.path_filestat_get(0, path);
  return { ret: ret === wasi.ERRNO_SUCCESS ? wasi.ERRNO_INVAL : ret, data: null };
};

const SITE = "/site";
const OUT = "/out";

/** Exit code reported when the module traps (a Rust panic) instead of exiting. */
export const TRAP_EXIT_CODE = 101;

/**
 * Compile zola.wasm. `source` can be a URL or string to fetch, a fetch Response, bytes
 * (ArrayBuffer or a typed array) or an already compiled WebAssembly.Module.
 * @returns {Promise<Zola>}
 */
export async function loadZola(source) {
  return new Zola(await compile(source));
}

async function compile(source) {
  if (source instanceof WebAssembly.Module) return source;
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) return WebAssembly.compile(source);
  if (typeof source === "string" || source instanceof URL) source = await fetch(source);
  if (typeof Response !== "undefined" && source instanceof Response) {
    if (!source.ok) throw new Error(`Failed to fetch zola.wasm: HTTP ${source.status}`);
    // compileStreaming needs the application/wasm content type; fall back to bytes without it
    if (WebAssembly.compileStreaming && source.headers.get("content-type")?.startsWith("application/wasm")) {
      return WebAssembly.compileStreaming(source);
    }
    return WebAssembly.compile(await source.arrayBuffer());
  }
  throw new TypeError("loadZola: expected a URL, Response, bytes or WebAssembly.Module");
}

export class Zola {
  /** @param {WebAssembly.Module} module */
  constructor(module) {
    this.module = module;
  }

  /**
   * Build a site.
   * @param {object} options
   * @param {SiteFiles} options.files the site: zola.toml (or config.toml), content/, templates/, …
   * @param {string} [options.config] config file to use, relative to the site root
   * @param {string} [options.baseUrl] overrides base_url from the config
   * @param {boolean} [options.drafts] include drafts
   * @param {boolean} [options.minify] minify the HTML output
   * @returns {Promise<BuildResult>} the output files, keyed by path relative to the output root
   */
  async build({ files, config, baseUrl, drafts = false, minify = false } = {}) {
    const args = ["build", "--output-dir", `${OUT}/public`];
    if (baseUrl) args.push("--base-url", baseUrl);
    if (drafts) args.push("--drafts");
    if (minify) args.push("--minify");
    const { out, ...result } = await this.#runInSite(files, config, args);
    const output = result.ok ? out.get("public") : undefined;
    return { ...result, files: output ? collect(output.contents) : new Map() };
  }

  /**
   * Check a site without writing anything: loads it and checks internal links. External links
   * can't be checked on WebAssembly and are skipped.
   * @param {object} options
   * @param {SiteFiles} options.files
   * @param {string} [options.config]
   * @param {boolean} [options.drafts]
   * @returns {Promise<RunResult>}
   */
  async check({ files, config, drafts = false } = {}) {
    const args = ["check"];
    if (drafts) args.push("--drafts");
    const { out, ...result } = await this.#runInSite(files, config, args);
    return result;
  }

  /** @returns {Promise<string>} e.g. "zola 0.23.6" */
  async version() {
    const result = await this.run(["--version"]);
    return result.stdout.join("\n").trim();
  }

  /**
   * Run the zola CLI with `args` and no preopened directories.
   * @param {string[]} args
   * @returns {Promise<RunResult>}
   */
  async run(args) {
    return this.#run(args, []);
  }

  async #runInSite(files, config, args) {
    if (!files) throw new TypeError("files is required");
    const outRoot = new PreopenDirectory(OUT, new Map());
    const preopens = [new PreopenDirectory(SITE, toTree(files)), outRoot];
    const cliArgs = ["--root", SITE];
    if (config) cliArgs.push("--config", normalisePath(config));
    const result = await this.#run([...cliArgs, ...args], preopens);
    // Zola recreates its output directory, so read it back from the preopen's root
    return { ...result, out: outRoot.dir.contents };
  }

  async #run(args, preopens) {
    const stdout = [];
    const stderr = [];
    const fds = [
      new OpenFile(new File(new Uint8Array())),
      ConsoleStdout.lineBuffered((line) => stdout.push(line)),
      ConsoleStdout.lineBuffered((line) => stderr.push(line)),
      ...preopens,
    ];
    // The shim logs every call to the console unless debug is explicitly off
    const shim = new WASI(["zola", ...args], [], fds, { debug: false });
    let exitCode;
    try {
      const instance = await WebAssembly.instantiate(this.module, { wasi_snapshot_preview1: shim.wasiImport });
      exitCode = shim.start(instance);
    } catch (error) {
      if (!(error instanceof WebAssembly.RuntimeError)) throw error;
      stderr.push(`zola trapped: ${error.message}`);
      exitCode = TRAP_EXIT_CODE;
    }
    // Flush a last line that had no trailing newline
    fds[1].fd_write(new Uint8Array([10]));
    fds[2].fd_write(new Uint8Array([10]));
    return { ok: exitCode === 0, exitCode, stdout: trimEmpty(stdout), stderr: trimEmpty(stderr) };
  }
}

/**
 * @typedef {Map<string, string | Uint8Array | ArrayBuffer> | Record<string, string | Uint8Array | ArrayBuffer>} SiteFiles
 *   File contents keyed by path relative to the site root, e.g. "content/blog/_index.md".
 * @typedef {{ ok: boolean, exitCode: number, stdout: string[], stderr: string[] }} RunResult
 *   Zola logs progress and errors to stderr, one entry per line.
 * @typedef {RunResult & { files: Map<string, Uint8Array> }} BuildResult
 */

const encoder = new TextEncoder();

function normalisePath(path) {
  const parts = path.replace(/\\/g, "/").split("/").filter((p) => p && p !== ".");
  if (parts.length === 0 || parts.includes("..")) throw new Error(`Invalid site path: ${JSON.stringify(path)}`);
  return parts.join("/");
}

function toBytes(path, value) {
  if (typeof value === "string") return encoder.encode(value);
  if (value instanceof Uint8Array) return value;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  throw new TypeError(`Unsupported contents for ${path}: expected a string, Uint8Array or ArrayBuffer`);
}

function toTree(files) {
  const root = new Map();
  const entries = files instanceof Map ? files.entries() : Object.entries(files);
  for (const [rawPath, value] of entries) {
    const parts = normalisePath(rawPath).split("/");
    let dir = root;
    for (const part of parts.slice(0, -1)) {
      let node = dir.get(part);
      if (!node) dir.set(part, (node = new Directory(new Map())));
      if (!(node instanceof Directory)) throw new Error(`${rawPath}: ${part} is a file, not a directory`);
      dir = node.contents;
    }
    dir.set(parts.at(-1), new File(toBytes(rawPath, value)));
  }
  return root;
}

function collect(contents, prefix = "", into = new Map()) {
  for (const [name, node] of [...contents].sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (node instanceof Directory) collect(node.contents, `${prefix}${name}/`, into);
    else into.set(prefix + name, node.data);
  }
  return into;
}

function trimEmpty(lines) {
  while (lines.length && lines.at(-1) === "") lines.pop();
  return lines;
}
