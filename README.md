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

This repository doesn't contain Zola. It holds small patch series for the Zola releases it
publishes (`VERSIONS`: currently **0.22.1** and **0.23.6**), scripts that fetch a release,
patch, build and test it, and a JavaScript wrapper for browsers and Node. GitHub Actions publish
a release for every version in `VERSIONS` and add new Zola releases as they come out.

## Download

Each [release](../../releases) has:

| Asset | |
|---|---|
| `zola.wasm`, `zola.wasm.gz` | Zola's CLI for `wasm32-wasip1` |
| `zola-wasi.js` | For browsers: the JavaScript library with a WASI runtime built in, one file, no dependencies |
| `zola-wasi-<version>.tgz` | The JavaScript package, `zola.wasm` included: `npm install <its URL>` |
| `SHA256SUMS` | Checksums of the above |

Release tags match the Zola version they're built from (`v0.23.6`). A re-release of the same
Zola version with changed patches gets a suffix (`v0.23.6-2`).

## Quick start

Needs macOS or Linux, [Rust](https://rustup.rs), Python 3 and, for the JavaScript side,
Node 20+.

```sh
scripts/build.sh        # → dist/zola.wasm
scripts/test.sh         # everything below; --quick skips the upstream checks and clippy
scripts/serve-demo.sh   # live editor in the browser at http://127.0.0.1:8000/
```

Every script works on the newest release in `VERSIONS` unless you set `ZOLA_VERSION`:

```sh
ZOLA_VERSION=v0.22.1 scripts/build.sh
```

`build.sh` downloads its own toolchain into `.toolchain/` (checksums are pinned): wasi-sdk,
whose clang builds Zola's C dependencies (oniguruma, zstd, libwebp) for WASI, and wasmtime for
running the tests. It also installs the `wasm32-wasip1` Rust target if it's missing.

## What's in here

| Path | |
|---|---|
| `VERSIONS` | Every Zola release zola-wasi publishes, with its pinned commit; the last is the scripts' default |
| `UPSTREAM` | Where Zola's source comes from |
| `patches/` | The changes to Zola for each release line, one concern per patch, ready to send upstream (see below) |
| `scripts/setup.sh` | Checks out a release into `zola/` and applies its patches as commits on branch `wasi` |
| `scripts/toolchain.sh` | Downloads and verifies wasi-sdk and wasmtime |
| `scripts/build.sh` | Builds `dist/zola.wasm` (and `zola.wasm.sha256`) |
| `scripts/test.sh` | The full test suite |
| `scripts/export-patches.sh` | Regenerates a release's patch series from commits in `zola/`, sharing patches between versions |
| `scripts/check-series.sh` | Checks that every release has a patch series and every patch is used |
| `scripts/serve-demo.sh` | Serves `web/demo` |
| `scripts/package.sh` | Assembles release assets into `dist/release/` |
| `scripts/release-notes.sh` | Writes a release's notes |
| `scripts/update-upstream.sh` | Adds the latest (or a given) Zola release to `VERSIONS` |
| `scripts/missing-releases.sh` | Lists the versions in `VERSIONS` that have no GitHub release yet |
| `.github/workflows/` | CI (`test.yml`), releases (`release.yml`), upstream updates (`update-upstream.yml`) |
| `web/` | The `zola-wasi` JavaScript package: `src/index.js`, its tests, the demo and `build-bundle.mjs` (browser bundle) |
| `tests/compare_outputs.py` | Compares two Zola output directories |

### The patches

Patches are organised by release line, and versions share them where the code allows:

```
patches/
  v0.23/series     →  v0.23/Don-t-depend-on-reqwest-….patch
                      v0.23/Copy-file-mtimes-….patch
                      v0.23/Don-t-copy-image-file-permissions-on-WASI.patch
                      v0.23/Build-the-zola-CLI-….patch
  v0.22/series     →  v0.22/Don-t-depend-on-reqwest-….patch
                      v0.22/Copy-file-mtimes-….patch
                      v0.23/Don-t-copy-image-file-permissions-on-WASI.patch   ← shared with 0.23
                      v0.22/Build-the-zola-CLI-….patch
```

- **Which series a release uses:** `patches/<tag>/series` if that exact release has one,
  otherwise `patches/<vMAJOR.MINOR>/series`. So every 0.23.x uses `v0.23/` unless one release
  needs its own.
- **A series file** lists patches in the order to apply them, as paths relative to `patches/`.
  Listing another line's patch, as `v0.22/series` does above, shares it: one file, used by both.
- **`scripts/export-patches.sh` shares automatically.** When it exports a commit whose change is
  identical to a patch another series already has (compared with `git patch-id`), it lists that
  patch instead of writing a copy. If you change a shared patch, it tells you which other
  versions use it, and `test.yml` tests all of them.
- **A new release line** (say 0.24) starts from the previous line's series, via
  `scripts/update-upstream.sh`. Patches that still apply stay shared; only the ones that don't
  need a 0.24 version.

Each series makes the same four changes, adapted to that release's code:

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
  `WebAssembly.Module`. The package ships the module as `zola-wasi/zola.wasm`.
- `zola.build({ files, config?, baseUrl?, drafts?, minify? })` resolves to
  `{ ok, exitCode, files, stdout, stderr }`. `files` maps output paths to `Uint8Array`s.
  `stderr` holds Zola's log lines, including errors.
- `zola.check({ files, config?, drafts? })` and `zola.version()` do what you'd expect;
  `zola.run(args)` runs the CLI with any arguments.

Site `files` can be a `Map` or a plain object of path → string, `Uint8Array` or `ArrayBuffer`.
Each call runs in a fresh instance, so calls are independent and can run concurrently.

For anything bigger than a toy site, run it in a Web Worker as `web/demo/worker.js` does. A
build blocks the thread it runs on, and image processing in particular takes seconds.

#### In a web page, without npm

Browsers run WebAssembly but don't implement WASI, which `zola.wasm` needs to read files and
print logs. The release's `zola-wasi.js` provides it: the library with the WASI shim built in,
as one dependency-free ES module (30 KB). Serve it next to `zola.wasm`:

```html
<script type="module">
  import { loadZola } from "./zola-wasi.js";
  const zola = await loadZola(new URL("zola.wasm", import.meta.url));
  const { ok, files } = await zola.build({ files: { /* … */ } });
</script>
```

Serve `zola.wasm` as `application/wasm` so it compiles while it downloads. The demo
(`web/demo`) uses exactly these two files.

#### In Node

Node has WASI built in, so for a site in a folder you can run `zola.wasm` directly, as with
wasmtime, without this library (`node:wasi` is marked experimental and prints a warning):

```js
import { WASI } from "node:wasi";
import { readFile } from "node:fs/promises";

const wasi = new WASI({
  version: "preview1",
  args: ["zola", "--root", "/site", "build"],
  preopens: { "/site": "./my-site" },
});
const module = await WebAssembly.compile(await readFile("zola.wasm"));
wasi.start(await WebAssembly.instantiate(module, wasi.getImportObject()));
```

Use the npm package when the site's files are in memory rather than on disk. It resolves its
dependency through npm; bundlers handle that as usual.

#### In Deno and Bun

Deno's `node:wasi` isn't implemented (constructing `WASI` throws), but `zola-wasi.js` carries its
own runtime and works there: `deno run --allow-read` is enough to load `zola.wasm` from disk. Bun
hasn't been tested.

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
4. The JavaScript library in Node with the browser shim, from source and as the browser bundle:
   `test_site` must be byte-identical to the wasmtime build, plus options, errors, concurrent
   builds, path validation and a silent console.

`.github/workflows/test.yml` runs it on Linux and macOS, on every push and pull request, for the
newest release of each line in `VERSIONS`, which covers every patch series, after checking the
series, shellcheck and actionlint. `release.yml` runs it again for each version it publishes.

The clippy check fails only on warnings in lines the patches add: older Zola releases trip
newer clippy lints in their own code, which is reported but not ours to fix.

## Releases and Zola updates

Both are automated:

`VERSIONS` is the list of versions zola-wasi releases. Every entry gets a release, and entries
stay: a new Zola release is added next to the old ones.

- **`release.yml`** runs when `VERSIONS` or `patches/` change on `main`. It checks which versions
  already have a GitHub release (`v0.23.6`, or a re-release like `v0.23.6-2`), skips those, and
  builds the rest in parallel. Each runs the full test suite, then publishes a **pre-release** (a
  release candidate) tagged with its Zola version; only the newest version can be marked as the
  repository's latest release. Promote a release from the GitHub UI once you're happy with it.
  Run it by hand to do the same, or with `zola_version` to build one version, e.g. to re-release
  it with changed patches as `v0.23.6-2`.
- **`update-upstream.yml`** checks daily for a new Zola release. When there is one, it opens a
  PR (branch `update-zola-<tag>`) adding it to `VERSIONS` and says whether its patch series
  applies. A patch release (v0.23.7) uses its line's series; a new line (v0.24) starts with a
  series sharing the previous line's patches. Merging the PR releases it. Run it by hand to
  target a specific tag.

So adding a release by hand is just a line in `VERSIONS` (with a patch series that applies to
it), pushed to `main`.

One-time setup in the repository's settings:

1. **Actions → General → Workflow permissions:** "Read and write permissions", and allow GitHub
   Actions to create pull requests.
2. **Optional:** add a fine-grained token with Contents and Pull requests read/write as the
   `UPDATE_PR_TOKEN` secret. PRs opened with the default token don't trigger other workflows,
   so without it the update PR's CI only runs once you push to the branch.

### Updating by hand

1. `scripts/update-upstream.sh` (or `scripts/update-upstream.sh v0.24.0`).
2. `scripts/setup.sh`. If a patch doesn't apply, resolve it in `zola/` and `git am --continue`
   (or apply it by hand and commit), then `scripts/export-patches.sh`.
3. `scripts/test.sh`, and `scripts/check-series.sh`.

To stop building a release, remove its line from `VERSIONS` (its existing GitHub release stays)
and run `scripts/check-series.sh`, which lists patch files no series uses any more.

### Changing a patch

1. `ZOLA_VERSION=<tag> scripts/setup.sh`, then edit and commit in `zola/` (branch `wasi`).
2. `ZOLA_VERSION=<tag> scripts/export-patches.sh` (add `--exact` to give that single release its
   own series instead of changing its line's).
3. Test every version whose series uses the patch, e.g. `ZOLA_VERSION=v0.22.1 scripts/test.sh`.

The `zola/` checkout is shared between versions: switching `ZOLA_VERSION` re-checks it out, and
Cargo's build cache carries over. `setup.sh --keep`, which `build.sh` uses, leaves it alone if
it's already for the requested release.

## License

Zola is licensed under the [EUPL-1.2](LICENSE) (MIT for code from before 0.22), and so are these
patches and scripts.
