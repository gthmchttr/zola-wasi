// Bundle src/index.js and the WASI shim into one dependency-free ES module for browsers:
//   node build-bundle.mjs OUTFILE
// Pages then need just that file and zola.wasm, no npm or bundler.
import { readFileSync } from "node:fs";
import { build } from "esbuild";

const outfile = process.argv[2];
if (!outfile) throw new Error("usage: node build-bundle.mjs OUTFILE");

const pkg = JSON.parse(readFileSync(new URL("package.json", import.meta.url)));
// The Zola release being built (scripts/build.sh sets it); package.json only holds a placeholder
const version = (process.env.ZOLA_VERSION ?? pkg.version).replace(/^v/, "");
const shim = JSON.parse(readFileSync(new URL("node_modules/@bjorn3/browser_wasi_shim/package.json", import.meta.url)));

await build({
  entryPoints: [new URL("src/index.js", import.meta.url).pathname],
  outfile,
  bundle: true,
  format: "esm",
  platform: "neutral",
  target: "es2022",
  minify: true,
  legalComments: "none",
  banner: {
    js: [
      `/*! zola-wasi ${version}: Zola compiled to WebAssembly. ${pkg.license}, https://www.getzola.org`,
      ` * Includes @bjorn3/browser_wasi_shim ${shim.version} (${shim.license}), https://github.com/bjorn3/browser_wasi_shim */`,
    ].join("\n"),
  },
  logLevel: "warning",
});
