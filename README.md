# zola-wasi

[Zola](https://www.getzola.org), the static site generator, compiled to WebAssembly
(`wasm32-wasip1`). It's the real `zola` CLI, so `build`, `check`, `init` and `completion` work
exactly as they do natively, in any WASI runtime: wasmtime, Node, or the browser.

```sh
wasmtime run --dir my-site::/site dist/zola.wasm --root /site build
```

```js
import { loadZola } from "zola-wasi";

const zola = await loadZola(new URL("zola.wasm", import.meta.url));
const { ok, files, stderr } = await zola.build({
  files: {
    "zola.toml": 'base_url = "https://example.com"\ntitle = "Hello"',
    "content/_index.md": "+++\ntitle = \"Home\"\n+++\nHello **world**",
    "templates/index.html": "<h1>{{ config.title }}</h1>{{ section.content | safe }}",
  },
});
// files: Map of output path → Uint8Array, e.g. files.get("index.html")
```

This repository is a small patch series on top of a pinned Zola release, plus the scripts to
build and test it and a JavaScript wrapper for browsers and Node. It currently targets
**Zola 0.23.6**.

## Quick start

Needs macOS or Linux, [Rust](https://rustup.rs), Python 3 and, for the JavaScript side,
Node 20+.

```sh
scripts/build.sh        # → dist/zola.wasm
scripts/test.sh         # everything below; --quick skips the upstream checks and clippy
scripts/serve-demo.sh   # live editor in the browser at http://127.0.0.1:8000/
```

`build.sh` downloads its own toolchain into `.toolchain/` (checksums are pinned): wasi-sdk,
whose clang builds Zola's C dependencies (oniguruma, zstd, libwebp) for WASI, and wasmtime for
running the tests. It also installs the `wasm32-wasip1` Rust target if it's missing.

## What's in here

| Path | |
|---|---|
| `UPSTREAM` | The Zola release the patches apply to (tag and commit) |
| `patches/` | The changes to Zola, one concern per patch, ready to send upstream |
| `scripts/setup.sh` | Clones the release into `zola/` and applies the patches as commits on branch `wasi` |
| `scripts/toolchain.sh` | Downloads and verifies wasi-sdk and wasmtime |
| `scripts/build.sh` | Builds `dist/zola.wasm` (and `zola.wasm.sha256`) |
| `scripts/test.sh` | The full test suite |
| `scripts/export-patches.sh` | Regenerates `patches/` from commits in `zola/` |
| `scripts/serve-demo.sh` | Serves `web/demo` |
| `web/` | The `zola-wasi` JavaScript package: `src/index.js`, its tests and the demo |
| `tests/compare_outputs.py` | Compares two Zola output directories |

### The patches

1. **Don't depend on reqwest when targeting WebAssembly.** reqwest needs tokio's networking and
   native TLS. On wasm, external link checking reports that it's unsupported, and `load_data`
   with a remote URL errors, or returns nothing when `required=false`.
2. **Copy file mtimes with std instead of filetime.** filetime panics on WASI. Setting the time
   is best-effort so that hosts which can't (like the browser shim) still work.
3. **Don't copy image file permissions on WASI**, which has none.
4. **Build the zola CLI for wasm32-wasip1.** `serve` and its dependencies are native-only;
   `check` skips external links with a warning.

Native builds are unaffected: upstream's own test suite passes with the patches applied.

## Using it

### From the command line

The WASI build sees only the directories you give it, so preopen the site and use paths inside
the guest:

```sh
wasmtime run --dir ./my-site::/site dist/zola.wasm --root /site build
wasmtime run --dir ./my-site::/site dist/zola.wasm --root /site check
wasmtime run --dir ./my-site::/site --dir ./out::/out dist/zola.wasm --root /site build --output-dir /out/public
```

Node's built-in `node:wasi` works the same way.

### From JavaScript (browsers, workers and Node)

`web/src/index.js` is the `zola-wasi` package. It runs `zola.wasm` with
[`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim) and an in-memory
filesystem, so nothing touches the disk or the DOM.

- `loadZola(source)` compiles the module once. `source` is a URL, a `Response`, bytes, or a
  `WebAssembly.Module`.
- `zola.build({ files, config?, baseUrl?, drafts?, minify? })` resolves to
  `{ ok, exitCode, files, stdout, stderr }`. `files` maps output paths to `Uint8Array`s.
  `stderr` holds Zola's log lines, including errors.
- `zola.check({ files, config?, drafts? })` and `zola.version()` do what you'd expect;
  `zola.run(args)` runs the CLI with any arguments.

Site `files` can be a `Map` or a plain object of path → string, `Uint8Array` or `ArrayBuffer`.
Each call runs in a fresh instance, so calls are independent and can run concurrently.

For anything bigger than a toy site, run it in a Web Worker as `web/demo/worker.js` does. A
build blocks the thread it runs on, and image processing in particular takes seconds.

The library imports the shim by its package name, so a bundler (or an import map, on the main
thread) has to resolve it. `scripts/serve-demo.sh` shows a bundler-free setup that rewrites the
import instead.

## Limitations

- **No `zola serve`.** WASI has no sockets or file watching. Rebuild on change yourself, as the
  demo does.
- **No network.** External link checking is skipped and remote `load_data` fails (or returns
  nothing with `required=false`).
- **Size.** `zola.wasm` is about 31 MB, 8.7 MB gzipped. Most of it is Zola itself plus the
  syntax-highlighting grammars and themes.
- **Processed image names differ from a native build.** Zola names resized images by a hash
  whose value depends on the pointer width, and wasm32 is 32-bit. The images themselves can
  also differ by a few bytes because the encoders take different SIMD paths. Both builds are
  internally consistent; just don't mix their outputs.
- **Speed.** 3-4x slower than native under wasmtime (Apple M-series: Zola's test site 39 ms
  native vs 168 ms; its docs 186 ms vs 497 ms). Sites with lots of image processing take
  seconds.

## Tests

`scripts/test.sh` runs:

1. Upstream's CI on the patched tree: `cargo fmt --check`, `cargo build --all`,
   `cargo test --all` and building Zola's docs site.
2. `cargo clippy -D warnings` on library and binary code, natively and for `wasm32-wasip1`.
3. `dist/zola.wasm` under wasmtime: Zola's `test_site`, `test_site_i18n` and docs site must
   produce the same output as a native build (with image hashes normalised, see above); `check`
   skips external links; an invalid site fails.
4. The JavaScript library in Node with the browser shim: `test_site` must be byte-identical to
   the wasmtime build, plus options, errors, concurrent builds and path validation.

## Updating to a new Zola release

1. Set the new tag and its commit in `UPSTREAM`.
2. `rm -rf zola && scripts/setup.sh`. If a patch no longer applies, fix it up with `git am`
   in `zola/` (or apply it by hand and commit), then `scripts/export-patches.sh`.
3. `scripts/test.sh`, and bump `version` in `web/package.json` to match.

To change a patch: edit and commit in `zola/` (on branch `wasi`), then
`scripts/export-patches.sh`. `setup.sh --keep`, which `build.sh` uses, leaves your checkout
alone.

## License

Zola is licensed under the [EUPL-1.2](LICENSE) (MIT for code from before 0.22), and so are these
patches and scripts.
