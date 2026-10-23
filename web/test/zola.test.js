// Runs dist/zola.wasm through the library with the browser WASI shim, in Node.
// scripts/test.sh sets the paths; run standalone with `npm test` after scripts/build.sh.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { before, test } from "node:test";
import { fileURLToPath } from "node:url";

import { loadZola } from "../src/index.js";

const repo = fileURLToPath(new URL("../..", import.meta.url));
const wasmPath = process.env.ZOLA_WASM ?? join(repo, "dist/zola.wasm");
const siteDir = process.env.SITE_DIR ?? join(repo, "zola/test_site");
const invalidSiteDir = process.env.INVALID_SITE_DIR ?? join(repo, "zola/test_sites_invalid/indexmd");
const expectedDir = process.env.EXPECTED_DIR;

// Every file under dir, keyed by "/"-separated path relative to it
function readTree(dir) {
  const files = new Map();
  (function walk(current) {
    for (const name of readdirSync(current)) {
      const path = join(current, name);
      if (statSync(path).isDirectory()) walk(path);
      else files.set(relative(dir, path).split(sep).join("/"), new Uint8Array(readFileSync(path)));
    }
  })(dir);
  return files;
}

let zola;
before(async () => {
  assert.ok(existsSync(wasmPath), `${wasmPath} is missing: run scripts/build.sh first`);
  zola = await loadZola(readFileSync(wasmPath));
});

test("reports its version", async () => {
  assert.match(await zola.version(), /^zola \d+\.\d+\.\d+$/);
});

test("builds a site", async () => {
  const result = await zola.build({ files: readTree(siteDir) });
  assert.equal(result.exitCode, 0, result.stderr.join("\n"));
  assert.ok(result.ok);
  assert.ok(result.files.has("index.html"));
  assert.ok(result.stderr.some((line) => line.startsWith("Building site")));

  if (expectedDir) {
    // Same wasm as the wasmtime build, so the output should be byte-identical
    const expected = readTree(expectedDir);
    assert.deepEqual([...result.files.keys()].sort(), [...expected.keys()].sort());
    for (const [path, data] of expected) {
      assert.ok(Buffer.from(result.files.get(path)).equals(Buffer.from(data)), `${path} differs from wasmtime`);
    }
  }
});

test("passes build options through", async () => {
  const result = await zola.build({ files: readTree(siteDir), baseUrl: "https://example.org/sub", minify: true });
  assert.ok(result.ok, result.stderr.join("\n"));
  const index = new TextDecoder().decode(result.files.get("index.html"));
  assert.match(index, /https:\/\/example\.org\/sub\//);
});

test("builds from plain objects of strings, with a custom config file", async () => {
  const result = await zola.build({
    config: "site.toml",
    files: {
      "site.toml": 'base_url = "https://example.com"\ntitle = "Hello"\n',
      "content/_index.md": "+++\ntitle = \"Home\"\n+++\nHello **world**\n",
      "templates/index.html": "<h1>{{ config.title }}</h1>{{ section.content | safe }}",
    },
  });
  assert.ok(result.ok, result.stderr.join("\n"));
  assert.equal(new TextDecoder().decode(result.files.get("index.html")), "<h1>Hello</h1><p>Hello <strong>world</strong></p>\n");
});

test("fails with zola's error for an invalid site", async () => {
  const result = await zola.build({ files: readTree(invalidSiteDir) });
  assert.equal(result.ok, false);
  assert.equal(result.exitCode, 1);
  assert.equal(result.files.size, 0);
  assert.ok(result.stderr.some((line) => line.includes("Failed to build the site")), result.stderr.join("\n"));
});

test("checks a site, skipping external links", async () => {
  const result = await zola.check({ files: readTree(siteDir) });
  assert.ok(result.ok, result.stderr.join("\n"));
  assert.ok(result.stderr.some((line) => line.includes("External links can't be checked on WebAssembly")));
});

test("rejects paths outside the site", async () => {
  await assert.rejects(zola.build({ files: { "../escape.md": "x" } }), /Invalid site path/);
  await assert.rejects(zola.build({}), /files is required/);
});

test("doesn't write to the console", async () => {
  const calls = [];
  const original = { log: console.log, warn: console.warn, error: console.error };
  for (const level of Object.keys(original)) console[level] = (...args) => calls.push([level, ...args]);
  try {
    await zola.build({ files: readTree(siteDir) });
  } finally {
    Object.assign(console, original);
  }
  assert.deepEqual(calls, []);
});

test("builds are independent", async () => {
  const files = readTree(siteDir);
  const [a, b] = await Promise.all([zola.build({ files }), zola.build({ files })]);
  assert.ok(a.ok && b.ok);
  assert.deepEqual(a.files, b.files);
});
